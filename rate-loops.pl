#!/usr/local/bin/perl -w

use lib '.', $ENV{PERLGP_LIB} ||  die "
  PERLGP_LIB undefined
  please see README file concerning shell environment variables\n\n";

use PDL;
use PDL::ReadAudioSoundFile;
use PDL::IO::FastRaw;
use Cwd;

use Algorithm;
use Individual;

my $scratchdir = $ENV{PERLGP_SCRATCH};
my $tmpdir = '/tmp';

my $cwd = cwd;

my ($expt) = $cwd =~ /([^\/]+)$/;

my $glob = "$tmpdir/$expt-*.raw";

my $savedir = 'results/loops';
my $savenum = getnextnum($savedir);
my $perldir = 'results/perl';

# clean out any raw loops in /tmp
unlink getrawloops($glob);

#
# start ./play-loops.pl
# use a fork so that it's killed when the parent script is killed
#


my $child;

my $loopnum = 0;

while (1) {

  if (-e 'pauselater') {
    pause('pauselater', 'pauseplay');
    unlink('pause');
  }
  if (-e 'pause') {
    pause('pause');
  }
  if (-e 'pauseplay') {
    pause('pauseplay');
  }

  my @pending = glob "$scratchdir/$expt/*.pending";


  # sort them least known fitness first, then oldest first
  my %mtimes;
  grep { $mtimes{$_} = (stat($_))[9] } @pending;

  # my %fsize;
  # grep { my $f = $_; $f =~ s/pending$/fitness/; $fsize{$_} = -s $f || 0 } @pending;
  # @pending = sort { $fsize{$a} <=> $fsize{$b} || $mtimes{$a} <=> $mtimes{$b}} @pending;

  # throw out any with fitness already done
  @pending = grep { my $f = $_; $f =~ s/pending$/fitness/; not -s $f } @pending;

  # sort oldest first
  # @pending = sort { $mtimes{$a} <=> $mtimes{$b}} @pending;

  if (@pending) {
    my $pending = $pending[int rand @pending];
    my $stem = $pending;
    $stem =~ s/\.pending//;

    my $ind = new Individual( Population => 'dummy',
			      ExperimentId => $expt,
			      DBFileStem => $stem );

    my $basefitness;
    if (open(PENDING, $pending)) {
      ($basefitness) = split ' ', <PENDING>;
      close(PENDING);
    }

    if (!defined $basefitness) {

      print "problem reading base fitness from $pending\nsleeping 2 seconds before retry...\n";
      sleep 2;
      next;
    }

    my $wav = PDL::ReadAudioSoundFile::readaudiosoundfile("$stem.wav");

    my $rawstem = sprintf "$tmpdir/$expt-%09d.raw", $loopnum++;
    $wav->mv(-1,0)->writefraw($rawstem);
    unlink "$rawstem.hdr";

    $child = start_play_loops() unless ($child);

    # now wait for $rawstem loop to be first in queue
    # (and hence playing)

    while ((@rawloops = getrawloops($glob)) == 0 || # empty
	   $rawloops[0] ne $rawstem) { # not first in queue
      sleep 1;
    }

    my $fitness;

    do {
      printf "[%-2d loops queued] base fitness %7.4f - rate loop: ", scalar(@pending), $basefitness;
      my $answer = getinput();

      if ($answer =~ /^[p-]/) { # pause with 'p' or '-'
	pause('pause');
      } elsif ($answer =~ /^\/\//) { # pause after nap with '//'
	pause('pauselater', 'pauseplay');
	unlink('pause');
      } elsif ($answer =~ /^\//) { # pause with '/' ("take a slash")
	pause('pauseplay');
      } elsif ($answer =~ /^[r+]/) { # restart esd with 'r' or '+'
	kill 9, $child;
	$child = start_play_loops();
      }	elsif ($answer =~ /^(\d+)?(\.)?$/) {
	my ($rating, $save) = ($1, $2);

	if (defined $rating && $rating == 0) {
	  $fitness = 0;
	} else {
	  $fitness = $rating || 0.1;
	}

	if ($save) {
	  unless (-d $savedir) {
	    system "mkdir -p $savedir";
	  }
	  my $savefile = sprintf "$savedir/%04d.wav", $savenum;
	  system "mv $stem.wav $savefile";
	  print "saved loop as $savefile\n";

	  unless (-d $perldir) {
	    system "mkdir -p $perldir";
	  }
	  $savefile = sprintf "$perldir/%04d.pl", $savenum;
	  system "mv $stem.pl $savefile";

          $savenum++;
	}
      }

    } until (defined $fitness);

    open(FITNESS, ">>$stem.fitness") || die "can't write to $stem.fitness";
    print FITNESS "$fitness localhost\n";
    close(FITNESS);
#    unlink $pending;
#    unlink "$stem.wav"; # stem.wav may already be gone
#    system "touch updated";
  } else {
    print "waiting for loops...\n";

    # remove raw pcm loops so they don't play any more
    unlink getrawloops($glob);

    sleep 2;
  }
}

sub pause {
  my @files = @_;
  system "touch @files";
  print "PAUSED - press enter to unpause:";
  my $foo = <STDIN>;
  unlink @files;
}

sub getinput {
  my $answer = <STDIN>;
  chomp($answer);
  my $clean = join '', grep ord($_)>28, split //, $answer;
  print "clean version: $clean\n" if (length($clean) != length($answer));
  return $clean;
}

sub getrawloops {
  my $glob = shift;
  return sort glob $glob;
}

sub getnextnum {
  my $dir = shift;
  my @files = sort glob "$dir/*.wav";
  if (@files) {
    my $last = pop @files;
    my ($num) = $last =~ /(\d+)/;
    return $num+1;
  } else {
    return 0;
  }
}

sub start_play_loops {
  my $child;
  if ($child = fork()) {
    # i'm the parent;
  } else {
    exec './play-loops.pl', $tmpdir, $expt;
  }
  return $child;
}
