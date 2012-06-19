#!/usr/bin/perl -w

#
# do not start this program yourself
#
# let rate-loops.pl do it for you
#

my ($tmpdir, $expt) = @ARGV;

die unless (-d $tmpdir && $expt);

my $glob = "$tmpdir/$expt-*.raw";

my @loops = sort glob $glob;
system "killall esd esdcat > /dev/null 2>&1";
open(ESD, "|esdcat");
while (1) {
  if (-e 'pause' || -e 'pauseplay') {
    sleep 1;
    next;
  }
  if (-e 'restart_esd') {
    print "\nesdcat restarting...\n";
    system "killall esdcat > /dev/null 2>&1";
    open(ESD, "|esdcat");
    unlink 'restart_esd';
  }

  if (@loops) {
    my $play = shift @loops;
    if (open(PCM, $play)) {
      print ESD <PCM>;
      close(PCM);
    }

    @loops = sort glob $glob;
    if (@loops > 1) {
      unlink shift @loops;
    }

  } else {
    sleep 2;
    @loops = sort glob $glob;
  }
}
