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

my $numratings = shift || 1000;

my $scratchdir = $ENV{PERLGP_SCRATCH};
my $tmpdir = '/tmp';

my $cwd = cwd;

my ($expt) = $cwd =~ /([^\/]+)$/;

#
# start ./play-loops.pl
# use a fork so that it's killed when the parent script is killed
#


my $child;

my $loopnum = 0;
my $ratings = 0;

while ($ratings < $numratings) {

  my @pending = glob "$scratchdir/$expt/*.pending";


  # sort them least known fitness first, then oldest first
  my %mtimes;
  grep { $mtimes{$_} = (stat($_))[9] } @pending;

  # my %fsize;
  # grep { my $f = $_; $f =~ s/pending$/fitness/; $fsize{$_} = -s $f || 0 } @pending;
  # @pending = sort { $fsize{$a} <=> $fsize{$b} || $mtimes{$a} <=> $mtimes{$b}} @pending;

  # throw out any with fitness already done
  @pending = grep { my $f = $_; $f =~ s/pending$/fitness/; not -s $f } @pending;

  if (@pending) {
    my $pending = $pending[int rand @pending]; # as in ezstream-loops
    my $stem = $pending;
    $stem =~ s/\.pending//;

    my $ind = new Individual( Population => 'dummy',
			      ExperimentId => $expt,
			      DBFileStem => $stem );

    my $basefitness = 0;
    if (open(PENDING, $pending)) {
      ($basefitness) = split ' ', <PENDING>;
      close(PENDING);
    }

    my $fitness = $basefitness + int(rand(5))+1;

    open(FITNESS, ">>$stem.fitness") || die "can't write to $stem.fitness";
    print FITNESS "$fitness localhost\n";
    close(FITNESS);
    $ratings++;
    print "rated $stem with $fitness done $ratings out of $numratings\n";
#    unlink $pending;
#    unlink "$stem.wav"; # stem.wav may already be gone
#    system "touch updated";
  } else {
    print "waiting for loops...\n";

    sleep 2;
  }
}
