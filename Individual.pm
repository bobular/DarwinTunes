package Individual;

use GeneticProgram;
use PDL;
use PDL::Audio;
use PDL::ReadAudioSoundFile;
use Digest::MD5 qw(md5_hex);

die "You must now use PDL::Audio version 1.1 or greater - available from CPAN\n\n"
  unless ($PDL::Audio::VERSION >= 1.1);

# the PerlGP library is distributed under the GNU General Public License
# all software based on it must also be distributed under the same terms

@ISA = qw(GeneticProgram);

$HOUSEBEATS = 0;
$CACHE_TOP = 300;
$CACHE_BOTTOM = 100;

$SYNTH_FINE_TUNE = 1.0;

$PI = 2*atan2(2,0);
$FXTOTAL = 0;
$FXTIMEOUT = 30;
$MINTRACKS = 1;
$MAXTRACKS = 12;
$MAX_SOUND_LENGTH = 44100*4;

$MutationProb = 1/2000;
$XoverProb = 1/1000;

my %wavnumbers;
my %wavpdls;
my %wavusage;
my %timeouts;
my %synthstore;
my %layerusage;
my %layerpdls;



my $powers = sequence(12)/12;
my $scale = (ones($powers)*2)**$powers;

@p = (($scale/2)->list, $scale->list, 2);
$nn = @p;

my $smoothwindow = ones(51)/51;


sub _init {
  my ($self, %p) = @_;

  my %defaults = ( Bpm => 125,

		   Bars => $HOUSEBEATS ? 2 : 4, # u need to change some things
		   Beats => 4,   # in Grammar.pm too if you
		   SubBeats => 4,# change these (search for "-+-")

		   BgLoop => '', # must not be shorter than the loop you're making
		   BgOffset => 0,# number of samples "into the sample" where the loop starts
		   BgProb => 0.25, # fraction of loops to which bgloop added

                   MinTreeNodes => 0,
		   MaxTreeNodes => 5000,
		   TreeDepthMax => 30,
		   NodeMutationProb => $MutationProb,
		   NodeXoverProb => $XoverProb, # see evolvedInit

		   XoverDepthBias => 0.1,
		   MacroMutationDepthBias => 0.1,
		   PointMutationDepthBias => 0,

		   QuickXoverProb => 0,  # OFF
		   XoverHomologyBias => 1e-9,  # homol xover OFF
		   XoverSizeBias => 1e-9,      # similar size xover OFF

		   NumericMutationFrac => 0, # turned off
		   NumericAllowNTypes => {
					  ZTO=>0.1,
					  WAHPHASE=>0.1,
					  VOL=>0.1,
					 },

# 		   MacroMutationTypes => [ qw(swap_subtrees copy_subtree
#                                             delete_internal) ],
		   NumericFormat => "%.6g",
		   XoverLogProb => 0,
		   MutationLogProb => 0,
		   PointMutationFrac => 0.9,

                   # house beats - comment out once you have them  #
		   #CodeFilter => [ qr/kick/, qr/snare/, qr/hats/ ],
		 );

  $self->SUPER::_init(%defaults, %p);
}

my $LEADIN;

sub evaluateOutput {
  my ($self) = @_;

  my $code = $self->getCode();

  my @keys = $code =~ /seen->\{(\w+)\}\+\+/g;
  my %uniq;
  @keys = grep !$uniq{$_}++, @keys;
  if (@keys < $MINTRACKS) {
    warn "less than $MINTRACKS tracks!\n";
    return [ null ];
  }
  if (@keys > $MAXTRACKS) {
    warn "more than $MAXTRACKS tracks! (experimental)\n";
    return [ null ];
  }

  if ($self->{CodeFilter}) {
    foreach $pattern (@{$self->{CodeFilter}}) {
      unless ($code =~ /$pattern/) {
	warn "code filter $pattern did not match\n";
	return [ null ];
      }
    }
  }

  if ($self->getSize() > $self->MaxTreeNodes) {
    warn "tree too big!\n";
    return [ null ];
  }

  $|=1; print "\nbuilding loop ";

  $FXTOTAL = 0;

  my $seen = {};
  my $output = $self->gen_loop($seen);

  print "\n";

  return [ $output, $self->DBFileStem, $code ];
}

sub gen_loop {
  my ($self, $seen) = @_;
  my ($bpm, $bars, $beats, $sb) =
    ($self->{Bpm}, $self->{Bars}, $self->{Beats}, $self->{SubBeats});
  my $spc = calc_spc($bpm, $sb);
  my $t = zeroes(5,$sb,$beats,$bars);
  my $s = zeroes float, $sb*$beats*$bars*$spc, 2;

  # add background here
  if ($self->BgLoop && -s $self->BgLoop && rand(1) < $self->BgProb) {
    if (not defined $BGLOOP) {
      my $bgloop = PDL::ReadAudioSoundFile::readaudiosoundfile($self->BgLoop);
      my $bglen = $bgloop->dim(0);
      my $slen = $s->dim(0);
      if ($bglen < $slen) {
	die "Background loop is too short\n";
      }
      $slen--;
      $BGLOOP = $bgloop->slice("0:$slen,:")->rotate(-$self->BgOffset)->sever;
    }

    $s += $BGLOOP;
    ## assume that there's no need to clip
  }

  add_to_loop($spc,$t,$s,$seen);
  return $s;
}

sub evolvedInit {
  my $self = shift;
  $self->NodeMutationProb($MutationProb);
  $self->NodeXoverProb($XoverProb);
}


sub Age {
  my ($self, $incr) = @_;
  # read only version - ignore $incr
  my $res;
  my $genome = $self->tieGenome();
  $genome->{age} = 0 unless (defined $genome->{age});
  $res = $genome->{age};
  $self->untieGenome();
  return $res;
}

# this is now the only way to increase the age
# and we do this in makeFamilies()
sub incrementAge {
  my ($self, $incr) = @_;
  my $res;
  my $genome = $self->tieGenome();
  $genome->{age} = 0 unless (defined $genome->{age});
  if (defined $incr) {
    $res = $genome->{age} += $incr;
  } else {
    $res = $genome->{age};
  }
  $self->untieGenome();
  return $res;
}

sub pdiv {
  return $_[1] ? $_[0]/$_[1] : $_[0];
}

sub nlen {
  my $len = shift;
  $len = 16 if ($len>16);
  $len = 0.25 if ($len<0.25);
  return sprintf "%.3f", $len;
}

sub getsound {
  my $expanded = shift;
  # check the cache for a number and defined audio pdl

  my $wn;
  if (defined ($wn = $wavnumbers{$expanded}) && ($wn == 0 || defined $wavpdls{$wn})) {
    $wavusage{$wn}++;
    return $wn;
  }

  # otherwise make and cache the sound
  print $expanded;
  my ($wav, $ok) = eval $expanded;
  print ";";

  # $ok usually means non-timed out

  if (defined $wav && !$wav->isempty) {
    # get some unique number from the $wav
    $wn = sprintf "%.15g", sum($wav->slice("0:-1:821")) +
      sum($wav->slice("1:-1:953")) +
	sum($wav->slice("2:-1:1009"));
    $wavpdls{$wn} = $wav;
    $wavusage{$wn} = 0;
  } else {
    $wn = 0;
  }
  if ($wn == 0 || $ok) {
    # wav is complete (or nothing) so cache it for next time
    $wavnumbers{$expanded} = $wn;
  } elsif ($timeouts{$expanded}++ > 3) {
    # this sound timed out too many times
    $wavnumbers{$expanded} = ($wn = 0);
  }
  return $wn
}

sub checkcache {
  if (keys %wavpdls > $CACHE_TOP) {
    warn "freeing some less used wavs from cache...\n";
    my @leastused = sort {$wavusage{$a} <=> $wavusage{$b}} keys %wavpdls;
    while (@leastused > $CACHE_BOTTOM) {
      my $rip = shift @leastused;
      delete $wavusage{$rip};
      delete $wavpdls{$rip};
    }
    grep {$wavusage{$_} = 0} keys %wavusage;
    %timeouts = (); # i think this is a good idea...
  }
}

sub loadwav {
  my $file = shift;
  if (-s $file) {
    my $wav = PDL::ReadAudioSoundFile::readaudiosoundfile($file)->float;
    my $maxamp = max(abs($wav));
    $wav *= 32767/$maxamp;
    return ($wav, 1);
  } else {
    return (null, 0);
  }
}

#
# overtones = [ multiple_of_freq, volume, phase_0_to_1, freq_mod_freq, sustain_level, attack, decay, sustain, release, adsr_power ];
#
#
# a negative value for release, defines that the "key down"
# note length is abs(release) - in the same units as $len
#
# adsr envelope is raised to an arbitrary power (between 0.25 and 4) to
#
sub asynth {
  my ($octave, $note, $len, $spc, @overtones) = @_;
  my $pitch = $p[$note];
  my $freq = 440*$octave*$pitch*$SYNTH_FINE_TUNE;

  # force first tone to be the main frequency
  $overtones[0][0] = 1;

  my $wav = zeroes($len*$spc);

  my $overtone;
  foreach $o (@overtones) {
    my $ofreq = $freq*$o->[0];
    next if ($ofreq > 8000);  # 22050
    $overtone = gen_oscil($wav, $ofreq/44100, $o->[2], $o->[3]/44100);
    # volume
    $overtone *= $o->[1]/$o->[0]; # most waveforms have decay proportional to 1/multiple
    # envelope
    if ($o->[8] < 0) {
      my $keydowntime = abs($o->[8]);
      $keydowntime = $len if ($keydowntime > $len);
      $o->[8] = ($o->[5]+$o->[6]+$o->[7])*($len - $keydowntime)/$keydowntime
    }
    $overtone *= PDL::Audio::gen_adsr($wav, $o->[4], $o->[5], $o->[6], $o->[7], $o->[8])**$o->[9];

    $wav += $overtone;
  }

  my $maxamp = max(abs($wav));
  return (null, 0) unless ($maxamp > 0);

  $wav *= 32767/$maxamp;
  return ($wav, oksound($wav));
}

sub mseries {
  my ($overtone, $num, $step, $phase) = @_;
  my @overtones = ($overtone);
  foreach my $i (1 .. $num-1) {
    my @new = @$overtone; # copy of first
    $new[0] += $i*$step;
    $new[2] += $i*$phase;
    while ($new[2] > 1) {
      $new[2]--;
    }
    push @overtones, \@new;
  }
  return @overtones;
}

sub loadsynth {
  my ($file, $pitch, $param, $len, $spc) = @_;
  if (-s $file) {
    unless (defined $synthstore{$file}) {
      open(SYNTH, $file);
      my $code = join '', <SYNTH>;
      close(SYNTH);
      $synthstore{$file} = eval $code;
    }
    $pitch = $p[$pitch];
    $param = $p[$param];
    my $wav = $synthstore{$file}->($pitch, $param, $len*$spc);
    my $maxamp = max(abs($wav));
    $wav *= 32767/$maxamp;
    return ($wav, oksound($wav));
  } else {
    return (null, 0);
  }
}

sub loadeffect {
  my ($file, $sound, $ok, $pitch, $param) = @_;

  if (!$ok || $FXTOTAL > $FXTIMEOUT) {
    print "-skip-fx-";
    return ($sound, 0);
  }

  my $starttime = time;

  if (-s $file) {
    unless (defined $synthstore{$file}) {
      open(SYNTH, $file);
      my $code = join '', <SYNTH>;
      close(SYNTH);
      $synthstore{$file} = eval $code;
    }
    $pitch = $p[$pitch];
    $param = $p[$param];
    my $wav = $synthstore{$file}->($sound, $pitch, $param);
    my $maxamp = max(abs($wav));
    $wav *= 32767/$maxamp;
    $FXTOTAL += time - $starttime;
    return ($wav, oksound($wav));
  } else {
    return (null, 0);
  }
}

sub oksound {
  my ($sound) = @_;
  if (defined $sound) {
    return $sound->dim(0) < $MAX_SOUND_LENGTH;
  } else {
    return 0;
  }
}

# copied from soundmaker/Algorithm.pm
sub oksound0 {
  my $synth = shift;
  my $minhz = 20;
  my $chunklen = int(44100/$minhz);

  # could be empty or timed-out
  unless (defined $synth && $synth->nelem) {
    warn "!!not audio\n";
    return 0;
  }

  if (sum($synth->isfinite) != $synth->nelem) {
    warn "!!NaN or Inf\n";
    return 0;
  }

  my $length = $synth->dim(0);
  my $amp = sum(abs($synth));

  unless ($amp) {
    warn "!!silent\n";
    return 0;
  }

  for (my $start=0; $start<$length-$chunklen-1; $start+=$chunklen) {
    my $end = $start + $chunklen - 1;
    my $slice = $synth->slice("$start:$end");
    my $max = max($slice);
    my $min = min($slice);
    if ($max <= 0 || $min >= 0) {
      warn "!!low freq\n";
      return 0;
    }
    my $ratio = abs($max/$min);
    if ($ratio > 4 || $ratio < 0.25) {
      warn "!!polarity\n";
      return 0;
    }
  }
  return 1;
}

sub addlayer {
  my ($s, $l, $spc) = @_;
  # s - main loop audio
  # l - trigger point piddle
  # spc - samples per click

  # first of all, zero out all values where
  # the wavid is zero
  my $nz = ($l->slice("0") != 0); # nonzero
  $l *= $nz;

  my @sounds = $l->flat->list();

  # $s->hdr->{sounds} = [] unless (defined $s->hdr->{sounds});

  my $len = $s->dim(0);
  print "|";
  for (my $i=0; $i<$len; $i+=$spc) {
    my ($wavid, $volume, $pan, $groove, $phase) = splice @sounds, 0, 5;
    $pan = 0.5 if ($pan < 0);
    $pan = 0.5 if ($pan > 1);
    if ($volume > 0 && $wavid) {
      my $left = $volume * sqrt(1-$pan);
      my $right = $volume * sqrt($pan);
      # my $panvec = pdl([$left], [$right]);

      my $wav = $wavpdls{$wavid};
      my ($wavlen, $stereo) = $wav->dims;

      if ($wavlen > $len) {
	print "wav too long! ";
	next;
      }

      my ($wavl, $wavr) = ($wav, $wav);
      if ($stereo) {
	($wavl, $wavr) = $wav->dog;
      }

      $groove = limit_offset($groove, $spc, 0.25);
      $phase = limit_offset($phase, $spc, 0.25);

      my $lstart = $i+$groove-$phase;
      my $rstart = $i+$groove+$phase;
      my $lend = $lstart + $wavlen-1;
      my $rend = $rstart + $wavlen-1;

      # add channels seperately
      my $l = $s;
      # check to see if added sound needs to wrap
      if ($lend >= $l->dim(0) || $lstart < 0) {
	$l = $l->rotate(-$lstart);
	$lstart = 0;
	$lend = $wavlen-1;
      }
      #warn "slice $lstart:$lend,(0) of $len\n";
      addsafe($l->slice("$lstart:$lend,(0)"), $wavl * $left);

      my $r = $s;
      # check to see if added sound needs to wrap
      if ($rend >= $r->dim(0) || $rstart < 0) {
	$r = $r->rotate(-$rstart);
	$rstart = 0;
	$rend = $wavlen-1;
      }
      #warn "slice $rstart:$rend:(1) of $len\n";
      addsafe($r->slice("$rstart:$rend,(1)"), $wavr * $right);
    }
  }
  checkcache();			# wav cache (samples+notes)

  # push @{$s->hdr->{sounds}}, $l->flat->list;

}

sub addsafe {
  my ($s1, $s2) = @_;

  $s1 += $s2;
  my $n = 4;
  while (max(abs($s1)) > 32767 && $n > 0) {
    $s1 -= $s2/4;
    print "$n>";
    $n--;
  }
}

sub offset {
  my ($l, $amount) = @_;
  my ($a, $b, $c, $d) = $l->dims();
  $l->reshape($a,$b*$c*$d);
  $l = $l->mv(-1,0)->rotate($amount)->mv(-1,0);
  $l->reshape($a,$b,$c,$d);
  return $l;
}

sub reverb {
  my ($s, $ok, $secs, $dull) = @_;
  my ($slen, $stereo) = $s->dims;
  my $rvblen = int(44100*$secs);

  if (!$ok || $FXTOTAL > $FXTIMEOUT) {
    print "-skip-fx-";
    return ($s, 0);
  }

  my $starttime = time;

  $secs /= 2; # because i append zeroes twice by mistake
  $s = $s->append(zeroes(float, $rvblen));

  # do some filtering
  my $f = smoothsound($s, 2, $dull);

  # make an integer copy of the sound (1/4 volume)
  my $lofi;
  if ($stereo) {
    $lofi = $f->divide(4,0)->short;
  } else { # make stereo
    $lofi = $f->divide(4,0)->dummy(1,2)->short;
  }
  $lofi = $lofi->append(zeroes(short, $rvblen));

  # make another copy (subtract later)
  my $reverb = $lofi->copy;

  my $length = $reverb->dim(0);
  my $first = 2000;
  my $steps = 64;
  my $pol = 1;
  my $seed = int(rand(99999));
  my $div;
  my $factor = 4*(1 + ($slen/$length));
  # fix the RNG
  srand(42);
  # calculate some bounce times
  my @btimes;
  for (my $i=0; $i<$steps; $i++) {
    push @btimes, int($first + rand($rvblen-$first));
  }
  # now add the echos starting with the earliest
  foreach $btime (sort {$a<=>$b} @btimes) {
    $div = int( $factor * (($length-$btime)/$length)**-6 );
    $pol = $btime % 2 == 0 ? 1 : -1; # reversing polarity avoids drift
    $reverb += $pol*$reverb->rshift($btime, 0) /
      short([int($div+rand($div/2))], [int($div+rand($div/2))]);
  }
  # subtract the original
  $reverb -= $lofi;
  # reset the RNG
  srand($seed);
  $FXTOTAL += time - $starttime;
  # return the sum
  return ($s->append(zeroes(float, $rvblen)) + $reverb, 1);
}

sub lowpass {
  my ($s, $ok, $rad, $cyc) = @_;

  if (!$ok || $FXTOTAL > $FXTIMEOUT) {
    print "-skip-fx-";
    return ($s, 0);
  }
  my $starttime = time;
  ($rad, $cyc) = (abs($rad), abs($cyc));
  while ($rad * $cyc > 256) {
    $rad-- if ($rad > 1);
    $cyc-- if ($cyc > 1);
  }

  $s = smoothsound($s, $rad, $cyc);

  # renormalise
  my $maxamp = max(abs($s));
  $s *= 32767/$maxamp;

  $FXTOTAL += time - $starttime;
  return ($s, 1);
}

sub hipass {
  my ($s, $ok, $rad, $cyc) = @_;

  if (!$ok || $FXTOTAL > $FXTIMEOUT) {
    print "-skip-fx-";
    return ($s, 0);
  }
  my $starttime = time;
  ($rad, $cyc) = (abs($rad), abs($cyc));
  while ($rad * $cyc > 256) {
    $rad-- if ($rad > 1);
    $cyc-- if ($cyc > 1);
  }
  $rad++ if ($rad < 1);
  $cyc++ if ($cyc < 1);

  $s -= smoothsound($s, $rad, $cyc);

  # renormalise
  my $maxamp = max(abs($s));
  $s *= 32767/$maxamp;

  $FXTOTAL += time - $starttime;
  return ($s, 1);
}


sub smoothsound {
  my ($s, $window, $cycles) = @_;
  my $o;
  foreach (1 .. $cycles) {
    $o = zeroes $s;
    my $n=0;
    for (my $i=-$window; $i<=$window; $i++) {
      $o += $s->rshift($i,0);
      $n++;
    }
    $s = $o/$n;
  }
  return $s;
}

sub wah {
  my ($s, $ok, $freq, $depth, $phase) = @_;

  if (!$ok || $FXTOTAL > $FXTIMEOUT) {
    print "-skip-fx-";
    return ($s, 0);
  }
  my $starttime = time;

  my ($slen, $stereo) = $s->dims;
  unless ($stereo) {
    # make it stereo
    $s = $s->dummy(1,2)->copy;
  }

  ($freq, $depth) = (abs($freq), abs($depth));
  $depth = 0 if ($depth < 0);
  $depth = 1 if ($depth > 1);
  $freq = 1 if ($freq == 0);

  my $sine = gen_oscil $slen, $freq/44100, $phase, 0;
  $sine *= $depth;
  $s *= cat(abs($sine+1), abs($sine-1));

  # renormalise
  my $maxamp = max(abs($s));
  $s *= 32767/$maxamp;

  $FXTOTAL += time - $starttime;
  return ($s, 1);
}

sub combine {
  my ($s1, $ok1, $s2, $ok2, $vol2) = @_;
  # no timeout
  my ($len1, $stereo1) = $s1->dims;
  my ($len2, $stereo2) = $s2->dims;

  my $ok = ($ok1 && $ok2);

  if ($stereo1 && !$stereo2) {
    $s2 = $s2->dummy(1,2)->copy;
  } elsif ($stereo2 && !$stereo1) {
    $s1 = $s1->dummy(1,2)->copy;
  }

  if ($len1 > $len2) {
    $s2 = $s2->append(zeroes(float, $len1-$len2));
  } elsif ($len2 > $len1) {
    $s1 = $s1->append(zeroes(float, $len2-$len1));
  }

  # now they are the same length

  # add
  $s1 += $s2*$vol2;

  # and normalise
  my $maxamp = max(abs($s1));
  $s1 *= 32767/$maxamp;
  return ($s1, $ok);
}

sub end2end {
  my ($s1, $ok1, $s2, $ok2) = @_;
  # seems to work for mono+mono mono+stereo stereo+mono and stereo+stereo
  my $joined = $s1->append($s2)->sever;
  return ($joined, $ok1 && $ok2);
}

sub backwards {
  my ($s, $ok) = @_;
  if (!$ok || $FXTOTAL > $FXTIMEOUT) {
    print "-skip-fx-";
    return ($s, 0);
  }
  # no timeout
  # works mono or stereo
  $s .= $s->slice("-1:0");
  return ($s, $ok);
}

sub resample {
  my ($s, $ok, $pitch) = @_;
  if (!$ok || $FXTOTAL > $FXTIMEOUT) {
    print "-skip-fx-";
    return ($s, 0);
  }

  my ($len, $stereo) = $s->dims;
  if ($stereo) {
    my ($wavl, $wavr) = $s->dog;
    ($wavl) = resample($wavl, $ok, $pitch);
    ($wavr) = resample($wavr, $ok, $pitch);
    return (cat($wavl, $wavr), $ok);
  }

  my $wav = filter_src($s, $p[$pitch]);
  my $maxamp = max(abs($wav));
  $wav *= 32767/$maxamp;
  return ($wav, $ok);
}

sub stretch {
  my ($s, $ok, @args) = @_;
  if (!$ok || $FXTOTAL > $FXTIMEOUT) {
    print "-skip-fx-";
    return ($s, 0);
  }

  my ($len, $stereo) = $s->dims;
  if ($stereo) {
    my ($wavl, $wavr) = $s->dog;
    ($wavl) = stretch($wavl, $ok, @args);
    ($wavr) = stretch($wavr, $ok, @args);
    if (defined $wavl && defined $wavr) {
      return (cat($wavl, $wavr), $ok);
    } else {
      warn "bad stereo stretch\n";
      return ($s, 0);
    }
  }

  my ($pitch, $length, $ramp, $jitter) = @args;

  my $wav = filter_granulate($s, $p[$pitch],
			     'length'=>$length,
			     'hop'=>$length/3,
			     'ramp'=>$ramp,
			     'jitter'=>$jitter);

  if (defined $wav) {
    # rescale (as float)
    my $maxamp = max(abs($wav));
    $wav *= 32767/$maxamp;
    return ($wav, $ok);
  } else {
    warn "bad mono stretch\n";
    return ($s, 0);
  }
}

# good values for shifts
# map {int(1+200*rand(1)*rand(1))} (1 .. 10000)
sub slopier {
  my ($s, $ok, @shifts) = @_;
  # no timeout
  # works mono or stereo

  foreach $a (@shifts) {
    $s = ($s - $s->rotate($a));
  }

  my $maxamp = max(abs($s));
  $s *= 32767/$maxamp;

  return ($s, $ok);
}

sub limit_offset {
  my ($value, $spc, $frac) = @_;
  if ($value > $frac*$spc || $value < -$frac*$spc) {
    return 0;
  }
  return $value;
}

sub extraLogInfo {
  my $self = shift;
  return sprintf "mut %-12.6g xover %-12.6g",
    $self->NodeMutationProb(), $self->NodeXoverProb();
}

sub calc_spc {
  my ($bpm, $subbeats) = @_;

  return int(44100*60/($bpm*$subbeats));
}

sub _init_tree {
  my $self = shift;
  $self->{unique_id} = $self->{genome}{unique_id} || $self->getNewUniqueID();
  $self->SUPER::_init_tree();
  $self->{genome}{unique_id} = $self->{unique_id};
}

sub _grow_tree {
  my $self = shift;
  my %p = @_;
  if ($p{depth} == 0 && open(LOG, ">>results/genealogy.log")) {
    print LOG join("\t", 'grow_tree', $self->{genome}{unique_id} || $self->{unique_id}, 'type', $p{type})."\n";
    close(LOG);
  }
  return $self->SUPER::_grow_tree(%p);
}

sub UniqueID {
  my $self = shift;
  my $genome = $self->tieGenome('UniqueID');
  my $res = $genome->{unique_id};
  $self->untieGenome();
  return $res || 'unknown';
}

sub getNewUniqueID {
  my $self = shift;
  mkdir 'results/saved' unless (-d 'results/saved');
  my $unique_id;
  do {
    $unique_id = sprintf("%010d", rand(2147483647));
  } while (glob("./results/saved/$unique_id.*"));
  return $unique_id;
}

1;
