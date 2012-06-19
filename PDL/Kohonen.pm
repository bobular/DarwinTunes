#                      -*- mode: cperl -*-
package PDL::Kohonen;

use PDL;
use PDL::IO::FastRaw;

@ISA = qw(PDL);

### TO DO: load+save methods (simply with fraw)


# data is always D x N
# where D is the dimensionality of the data
# and there are N data points
# maps are always D x W x H

sub initialize {
  my $class = shift;
  my $self = {
	      PDL => null, # used to store PDL object
	     };
  bless $self, $class;
}

##
# init method
##
# usage: $map->init($data, 10, 6, 4);
#        initialises a 10x6x4 map randomly based on the min/max
#        of the data in $data piddle
# or:    $map->init($perlarrayref, 8, 7)
#        initialises a 8x7 map as above but uses a reference
#        to a perl array of individual data point piddles
#        [note: arrays of many piddles seem to take up memory]
##
sub init {
  my ($self, $data, @mdims) = @_;
  die "init() arguments: data, map_dimensions\n"
    unless (defined $data && @mdims > 0);

  if (ref($data) eq 'ARRAY') {
    $data = cat(@$data);
  }

  my $max = $data->mv(-1,0)->maximum;
  my $min = $data->mv(-1,0)->minimum;

  my @ddims = $data->dims;
  my $n = pop @ddims;
  $self->{mapdims} = \@mdims;  # map dimensions, e.g. 6 x 4
  $self->{nmapdims} = scalar @mdims;
  $self->{mapvolume} = ones(@mdims)->nelem;
  $self->{datadims} = \@ddims; # data dimensions, e.g. 20 x 15
  $self->{ndatadims} = scalar @ddims;
  ($self->{sdim}) = sort { $a<=>$b } @mdims; # smallest map dimension size
  $self->{PDL} = random(@ddims, @mdims);
  $self->{PDL} *= ($max-$min)+$min;
  return $self;
}

sub train {
  my ($self, $data, $p) = @_;

  if (ref($data) eq 'ARRAY') {
    $data = cat(@$data);
  }

  my $n = $data->dim(-1);
  my $dta = $data->mv(-1, 0);

  die "you must init() the map first\n" unless ($self->{mapdims});

  my $alpha = defined $p->{alpha} ? $p->{alpha} : 0.1;
  my $radius = defined $p->{radius} ? $p->{radius} : $self->{sdim}/2;

  $p->{epochs} = 1 unless (defined $p->{epochs});
  $p->{order} = 'random' unless (defined $p->{order}); # also: linear

  $p->{ramp} = 'linear' unless (defined $p->{ramp});    # also: off

  my $winnerfunc = $p->{winnerfunc} || \&euclidean_winner;
  $p->{progress} = 'on' unless (defined $p->{progress});

  my ($dalpha, $dradius) = (0, 0);
  if ($p->{ramp} =~ /linear/i) { 
    $dalpha = $alpha/$p->{epochs};
    $dradius = $radius/$p->{epochs};
  }

  my $progformat = $p->{progress} =~ /on/i ?
    "\rradius %2d alpha %6.4f data %5d of %5d epoch %3d of %3d" : '';

  my $ordertype = 0;
  $ordertype = 1 if ($p->{order} =~ /linear/i);

  if ($p->{progress} =~ /on/) {
    printf "training map (%s) with %d data points (%s) for %d epochs...\n",
      join("x", @{$self->{mapdims}}), $n,
	join("x", @{$self->{datadims}}), $p->{epochs};
  }
  local $| = 1;

  for (my $e=0; $e<$p->{epochs}; $e++) {
    for (my $i=0; $i<$n; $i++) {
      printf $progformat, $radius, $alpha, $i+1, $n, $e+1, $p->{epochs};
      my $d = $ordertype ? $i : int(rand($n));

      my $vec = $dta->slice("($d)");

      my @w = $self->$winnerfunc($vec);

      for (my $r=$radius; $r>=0; $r--) {
	my $hood = $self->hood($r, @w);
	$hood -= ($hood-$vec)*$alpha;
      }
    }
    $alpha -= $dalpha;
    $radius -= $dradius;
  }
  print "\n" if ($progformat);
}


# runs your data through a trained map
# returns two piddles
# - winning node coordinates (ushort M x N)
# - quantisation error (double N)
sub apply {
  my ($self, $data, $p) = @_;
  my $winnerfunc = $p->{winnerfunc} || \&euclidean_winner;
  $p->{progress} = 'on' unless (defined $p->{progress});

  if (ref($data) eq 'ARRAY') {
    $data = cat(@$data);
  }

  my $n = $data->dim(-1);
  my $dta = $data->mv(-1, 0);

  my $mds = join("x", @{$self->{mapdims}});
  my $progformat = $p->{progress} =~ /on/i ?
    "\rapplying map ($mds) to data point %5d of %5d" : '';

  local $| = 1;

  my $winvecs = zeroes ushort, $n, $self->{nmapdims};
  my $errors = zeroes $n;

  my $error = 0;
  for (my $i=0; $i<$n; $i++) {
    printf $progformat, $i+1, $n;
    my $vec = $dta->slice("($i)");
    $winvecs->slice("($i)") .= ushort($self->$winnerfunc($vec, \$error));
    set($errors, $i, $error);
  }
  print "\n" if ($progformat);

  return ($winvecs->mv(0, -1), $errors);
}

sub euclidean_winner {
  my ($self, $vec, $qref) = @_;

  my $d = $vec - $self;
  $d *= $d;
  while ($d->ndims > $self->{nmapdims}) {
    $d = $d->sumover();
  }
  my @d = $d->dims();
  my ($i) = $d->flat->qsorti->list;

  # pass the error back through a reference, if given
  if ($qref && ref($qref)) {
    $$qref = sqrt($d->flat->at($i));
  }

  return $self->unflattenindex($i);
}

sub unflattenindex {
  my ($self, $i) = @_;
  my @result;
  my $volume = $self->{mapvolume};
  foreach my $dim (reverse @{$self->{mapdims}}) {
    $volume = $volume/$dim;
    my $index = int($i/$volume);
    unshift @result, $index;
    $i -= $index*$volume;
  }
  return @result;
}

sub hood {
  my ($self, $radius, @coords) = @_;
  $radius = int($radius);

  my $slice = ',' x ($self->{ndatadims}-1);

  if ($radius == 0) {
    return $self->slice(join ',', $slice, @coords);
  }

  for (my $i=0; $i<@coords; $i++) {
    my ($left, $right) = ($coords[$i]-$radius, $coords[$i]+$radius);
    $left = 0 if ($left < 0);
    $right = $self->{mapdims}->[$i] - 1 if ($right >= $self->{mapdims}->[$i]);
    $slice .= ",$left:$right";
  }
  return $self->slice($slice);
}

sub save {
  my ($self, $filename) = @_;
  $self->writefraw($filename);
  open(HDR, ">>$filename.hdr") || die "can't append to $filename.hdr";
  foreach $key (qw(nmapdims ndatadims sdim mapvolume)) {
    print HDR "PDL::Kohonen $key $self->{$key}\n";
  }
  close(HDR);
}

sub load {
  my ($self, $filename) = @_;
  $self->{PDL} = readfraw($filename);

  open(HDR, "$filename.hdr") || die "can't open $filename.hdr";
  while (<HDR>) {
    if (/^PDL::Kohonen/) {
      chomp;
      my ($dum, $key, $val) = split ' ', $_, 3;
      $self->{$key} = $val;
    }
  }
  close(HDR);

  die "couldn't find header information while loading map\n"
    unless ($self->{nmapdims} && $self->{ndatadims} && $self->{sdim});

  my @dims = $self->dims;
  my @mdims = splice @dims, -$self->{nmapdims};
  $self->{mapdims} = \@mdims;
  $self->{datadims} = \@dims;
}



sub quantiseOLDCODE {
  my ($map, $data, $distfunc) = @_;
  $map = $map->clump(1,2);
  my $mapsize = $map->dim(1);
  my $dupdata = $data->dummy(1, $mapsize);
  my $d = $dupdata - $map;
  $d *= $d;
  $d = $d->sumover();
  my $i = $d->qsorti->slice("(0),:"); # get the map index of smallest dists
  for (my $dim = 0; $dim<$map->dim(0); $dim++) {
    $data->slice("($dim)") .= $map->slice("($dim)")->index($i);
  }
}


1;
