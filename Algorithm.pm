package Algorithm;

use TournamentGP;
use PDL;
use PDL::Audio;
use PDL::ReadAudioSoundFile;
use PDL::IO::FastRaw;
use Digest::MD5 qw(md5_hex);
use LWP::Simple;
use Compress::Zlib;


# the PerlGP library is distributed under the GNU General Public License
# all software based on it must also be distributed under the same terms

@ISA = qw(TournamentGP);

my $SLEEPS = 0;

# for reference EQ thing
my @bands = (1, 2, 3, 7, 19, 53, 131);
my $nbands = @bands;

sub _init {
  my ($self, %p) = @_;

  my %defaults = ( TrainingSet => 'default',
		   TestingSet => 'default',

		   WavLoops => 1,
		   DeleteWavs => 0,
		   RawLoops => 0,

                   FitnessDirection => 'up',
		   WorstPossibleFitness => 0,
		   TournamentKillAge => 4,
		   Tournaments => 1e10,
		   TournamentSize => 20,
		   TournamentParents => 10,
		   MateChoiceRandom => 1,
		   LogInterval => 10e10,
		   RefreshInterval => 1,
		   KeepBest => 0,

		   BestFileStem => '',
		   RecentFileStem => '',

		   TemporaryOffset => 10000, # don't change this


		   ##options to change for web version (mainly)##

		   MinPending => 5,       # how many to keep pending
		   MaxPending => $Population::SIZE,  # idle when this many are pending
		   IdleSleepSeconds => 30,# 0 = off (Idle = no ratings and maxpending)
		   IdleCyclesBeforeExit => 0, # 0 = off
		   SleepFactor => 0,      # multiple of used CPU time to sleep for (0 = off, 10 should give <10% usage)
		   MP3Loops => 1,         # 1=on  WavLoops must be on too!
#		   LAME_EXEC => "/usr/local/bin/lame", # on ec2
		   LAME_EXEC => "/usr/bin/lame",       # on local

		   HTTPD_GROUP => 'apache', # group name for write perms ('' for none)

		   SaveEverything => 0,

		   ## HOUSE BEATS ##
		   # leave uncommented to maintain house beats

		   CodeBonus => { },

		   SaveLoopFitnessThreshold => 3,
		   SaveLoopProb => 0.1,
		 );

  $self->SUPER::_init(%defaults, %p);
}

my $smoothwindow = ones(51)/51;

sub run {
  my ($self, %p) = @_;

  my $pdir = $self->Population->PopulationDir();
  if ($self->{HTTPD_GROUP}) {
    system "chgrp $self->{HTTPD_GROUP} $pdir ./status";
    system "chmod g+w $pdir ./status";
  }

  # this doesn't really load anything
  $self->loadData() unless ($self->TrainingData());

  # make the temp population for offspring

  my $temp_pop = $self->{TempPop} = new Population(ExperimentId => "$pdir/temp",
				   PopulationSize => $self->{TournamentSize});
  # and fill it from disk or tar file
  $temp_pop->repopulate();

  # or fill it up with new Individuals
  while ($temp_pop->countIndividuals() < $temp_pop->PopulationSize()) {
    my $ind = new Individual( Population => $temp_pop,
			      ExperimentId => "$pdir/temp",
			      DBFileStem => $temp_pop->findNewDBFileStem() );
    $temp_pop->addIndividual($ind);
  }

  while (1) {
    if (-e 'pause') {
      sleep 2;
    } else {

      my $before_time = time();

      $self->tournament();

      # sleep proportional to time already taken (if >= 1 sec)
      my $time_taken = time() - $before_time;
      sleep $self->{SleepFactor} * $time_taken;

      $self->refresh();
    }
  }
}

sub loadSet {
  my ($self, $dir) = @_;
}

sub refresh {
  my $self = shift;

  ## probably not needed now we sleep for 120 seconds if there are plenty of pending loops
  # this file is made by 'rate-loops.pl'
  # return unless (-e 'updated');
  # unlink 'updated';

  my $done_something;

  # go through population and rebuild tree if fitness is WorstPossibleFitness
  my @pop = @{$self->Population->Individuals()}; # copy array
  my $npending = 0;
  my $bestmp3fitness;
  my $bestmp3file;

  # don't transfer fitness if a loop has been played recently
  my %recently_played;
  if (open(LASTPLAYED, 'status/lastplayed')) {
    while (<LASTPLAYED>) {
      my ($file) = split;
      $file = "$ENV{PERLGP_SCRATCH}/$file";
      $recently_played{$file}++;
    }
    close(LASTPLAYED);
  }

  while (@pop) {
    my $individual = splice @pop, int(rand @pop), 1;

    my $fitfile = $individual->DBFileStem().".fitness";
    my $pendingfile = $individual->DBFileStem().".pending";
    my $mp3file = $individual->DBFileStem().".mp3";
    my $perlfile = $individual->DBFileStem().".pl";



    # ensure that there are always pending loops
    # this works because we are going through population randomly 
    $npending++ if (-s $pendingfile);

    # look for new fitness in a file
    # and set the fitness
    if (-s $fitfile && $npending > $self->{MinPending} && !$recently_played{$mp3file}) {
      if (open(FITNESS, $fitfile)) {
	# one rating per rater
	my %ratings;
	while (<FITNESS>) {
	  my ($fit, $rater) = split;
	  $ratings{$rater} = $fit;
	  if ($fit < 0) { # UNDO RATING
	    delete $ratings{$rater};
	  }
	}
	close(FITNESS);
	# take average of ratings
	if (values %ratings > 0) {
	  my ($fitness) = stats(pdl(values %ratings));
	  if (defined $fitness) {
	    if (open(PENDING, $pendingfile)) {
	      my ($basefitness) = split ' ', <PENDING>;
	      close(PENDING);

	      unlink $fitfile;
	      unlink $pendingfile;
	      $individual->Fitness($fitness ? $fitness + $basefitness : 0);
	      $done_something = 1;
	      if ($fitness >= $self->{SaveLoopFitnessThreshold} &&
		  rand(1) < $self->{SaveLoopProb} &&
		  -s $mp3file) {
		mkdir 'results/saved' unless (-d 'results/saved');
		my $time = time;
		my $savename = "results/saved/$time.mp3";
		system "cp $mp3file $savename";
		# my $savenamepl = "results/saved/$time.pl";
		# system "cp $perlfile $savenamepl";
		# link mp3 and pl file to genealogy
		if (open(LOG, ">>results/genealogy.log")) {
		  foreach my $rater (keys %ratings) {
		    print LOG "audio_for\t".$individual->UniqueID()."\tis\t$savename\n";
		  #  print LOG "perl_for\t".$individual->UniqueID()."\tis\t$savenamepl\n";
		  }
		  close(LOG);
		}
	      }
	      if ($self->{RATED_CGI}) {
		foreach my $rater (keys %ratings) {
		  if ($rater =~ /^(\d+)$/ && $rater > 0) {
		    my $thankyou = get("$self->{RATED_CGI}$rater");
		    # if it fails, it fails...
		  }
		}
	      }
	      # now store ratings against unique_ids in genealogy
	      if (open(LOG, ">>results/genealogy.log")) {
		foreach my $rater (keys %ratings) {
		  print LOG "rating_of\t".$individual->UniqueID()."\tby\t".$rater."\twas\t".$ratings{$rater}."\n";
		}
		close(LOG);
	      }
	    }
	  }
	} else {
	  # user did "undo"
	  unlink $fitfile;
	}
      }
    } elsif ($self->{MP3Loops} && -s $pendingfile && !-s $mp3file) {
      # clean up if there's no mp3file but there should be
      $individual->Fitness($self->{WorstPossibleFitness});
    }

#    my $fitness = $individual->Fitness();
#
## print $individual->DBFileStem, " ", ($fitness || 'undef'), "\n";
#
#    if (defined $fitness && ($fitness == $self->WorstPossibleFitness() || $fitness =~ /nan/i)) {
#      $individual->initTree();
#      $individual->initFitness();
#      $done_something = 1;
#    }

  }

  unless ($done_something || $npending < $self->{MaxPending}) {
    if (-e 'pauselater') {
      system "touch pause"; # a nap becomes sleep
    }
    if ($self->{IdleCyclesBeforeExit} && ++$SLEEPS >= $self->{IdleCyclesBeforeExit}) {
      print "$npending pending, no new ratings ($SLEEPS), exiting...\n";
      exit;
    } else {
      print "$npending pending, no new ratings ($SLEEPS), sleeping $self->{IdleSleepSeconds}s...\n";
      sleep $self->{IdleSleepSeconds};
    }
  } else {
    $SLEEPS = 0;
  }

  if ($done_something && rand(1) < 0.1) {
    my $code = '';
    my $n = 0;
    my $sum = 0;
    foreach my $ind (@{$self->Population()->Individuals()}) {
      my $thiscode = $ind->getCode();
      $code .= $thiscode;
      $sum += length(compress($thiscode, Z_BEST_COMPRESSION));
      $n++;
    }
    open(CLOG, ">>results/genealogy.log");
    printf CLOG "diversity\t%.2f\t%.2f\n", $sum/$n, length(compress($code, Z_BEST_COMPRESSION))/$n;
    close(CLOG);
  }
}

sub fitnessFunction {
  my ($self, %p) = @_;

  # %p gives you Input => data structure
  #              Output => data structure
  #              TimeTaken => total seconds for evaluation
  #              CodeSize => number of nodes in tree (result of getSize)

  die "fitnessFunction needs params Input, Output, TimeTaken, CodeSize\n"
    unless (defined $p{Input} && defined $p{Output} &&
	    defined $p{TimeTaken} && defined $p{CodeSize});

  my $synth = $p{Output}->[0];
  my $stem = $p{Output}->[1];
  my $perl = $p{Output}->[2];

  return $self->WorstPossibleFitness() if ($synth->isempty);

  print "\n";

  my $codebonus = 0;
  if ($self->{CodeBonus}) {
    foreach $pattern (keys %{$self->{CodeBonus}}) {
      if ($perl =~ /$pattern/) {
	$codebonus += $self->{CodeBonus}{$pattern};
      }
    }
  }

  # my $signature = md5_hex(join ':', @{$synth->hdr->{sounds}});

  my $silent = sum($synth == 0);
  my $nsamples = $synth->nelem;
  my $silentfrac = $silent/$nsamples;
  if ($silentfrac > 0.5) {
    print " ** more than 50% is silent **\n";
    return $self->WorstPossibleFitness();
  }


  my $abs = abs($synth);
  my $maxamp = max($abs);

  # printf "maxamp: %d ", $maxamp;

  if ($maxamp < 32767/3) {
    print " ** too quiet **\n";
    return $self->WorstPossibleFitness();
  }

  if ($maxamp > 32767) {
    print " ** ERROR - too loud **\n";
    return $self->WorstPossibleFitness();
  }

  my $sumabs = $abs->sum;
  my ($minchan, $maxchan) = $abs->sumover->minmax;
  # my $balancepenalty = ($maxchan-$minchan)/$maxchan;
  # printf "bpen: %6.4f\n", $balancepenalty;

  my ($l, $r) = $synth->dog();
  # my $widthscore = sum(abs($l-$r))/$sumabs;
  # printf "width: %6.4f\n", $widthscore;

  my $basefitness = 0; # 1 - $silentfrac - $balancepenalty + $widthscore + $codebonus;
  if ($basefitness =~ /nan/i) {
    print " ** nan error **\n";
    return $self->WorstPossibleFitness();
  }

  my $file = "$stem.wav";
  $synth = $synth->short;

  if ($self->RawLoops) {
    open(RAW, ">$stem.raw");
    print RAW ${$synth->mv(-1,0)->get_dataref};
    close(RAW);
    print "wrote RAW AUDIO $stem.raw\n";
  }
  if ($self->WavLoops) {
    PDL::ReadAudioSoundFile::writeaudiosoundfile($synth, $file);
    print "wrote WAV $stem.wav\n";

    if ($self->MP3Loops && $self->LAME_EXEC) {
      print "encoding MP3...\n";
      my $end = $synth->slice("-44100:-1,:"); # ca. 0.5 sec
      PDL::ReadAudioSoundFile::writeaudiosoundfile($end, "$stem-end.wav");
      my $start = $synth->slice("0:44099,:");
      PDL::ReadAudioSoundFile::writeaudiosoundfile($start, "$stem-start.wav");

      my $dir = $stem;
      $dir =~ s{/[^/]+$}{};
      my ($loopnum) = $stem =~ /([1-9]\d*)$/;

      system "$self->{LAME_EXEC} --silent --nogap $stem-end.wav $stem.wav $stem-start.wav";
      unlink "$stem-end.wav", "$stem-end.mp3", "$stem-start.wav", "$stem-start.mp3";
      unlink "$dir/$stem.fitness";

      mkdir 'downloads' unless (-d 'downloads');
      if ($stem !~ m{^/}) { # only if relative
	if (! -l "downloads/loop-$loopnum.mp3" ||
	    readlink("downloads/loop-$loopnum.mp3") ne "../$stem.mp3") {
	  unlink "downloads/loop-$loopnum.mp3";
	  symlink "../$stem.mp3", "downloads/loop-$loopnum.mp3";
	}
      }
      if ($self->{DeleteWavs}) {
	unlink "$stem.wav";
      } else {
	if ($stem !~ m{^/}) { # only if relative
	  if (! -l "downloads/loop-$loopnum.wav" ||
	      readlink("downloads/loop-$loopnum.wav") ne "../$stem.wav") {
	    unlink "downloads/loop-$loopnum.wav";
	    symlink "../$stem.wav", "downloads/loop-$loopnum.wav";
	  }
	}
      }
      # if there was some failure we have to write off the loop because it will never get rated
      unless (-s "$stem.mp3") {
	print "no MP3 file! worst poss fitness.\n";
	return $self->{WorstPossibleFitness};
      }
    }
  }

  open(PENDING, ">$stem.pending") || die "can't write to $stem.pending";
  print PENDING "$basefitness\n";
  close(PENDING);
  print "wrote $stem.pending\n\n";

  open(PERL, ">$stem.pl") || die "can't write to $stem.pl";
  print PERL $perl;
  close(PERL);

  return $self->TemporaryOffset + $basefitness;
}


sub tournament {
  my ($self, %p) = @_;
  my @cohort = $self->Population()->selectCohort($self->TournamentSize());

  my $fitness;
  foreach my $ind (@cohort) {
    my $output;
    my $fitness = $ind->Fitness();
    if (!defined $fitness || $self->AlwaysEvalFitness()) {
      $ind->reInitialise();
      $ind->Fitness($self->WorstPossibleFitness());
      my $child;
      if ($self->ForkForEval() && ($child = fork())) {
	wait; # forking is sometimes necessary if the alarm call crashes everything
	$ind->eraseMemory(); # force fitness recall from disk
	$fitness = $ind->Fitness();
	if (!defined $fitness) { # genome hash was corrupted somehow
	  $fitness = $self->WorstPossibleFitness();
	  $ind->retieGenome();
	  $ind->initTree();
	}
      } else {
	($fitness, $output) = $self->calcFitnessFor($ind, $self->TrainingData());
	$ind->Fitness($fitness);
        exit if ($self->ForkForEval());
      }
    }

    $fitness{$ind} = $fitness; # for a quicker sort below
  }

  @cohort =  sort { $fitness{$b} <=> $fitness{$a} } @cohort;
  die "can't do this fitness direction" if ($self->FitnessDirection() =~ /down/i);

  # if the best individual has a 'temporary fitness'
  # don't do any crossover
  if ($cohort[0]->Fitness() < $self->TemporaryOffset/2) {

    # take upper chunk as parents
    my @parents = splice @cohort, 0, $self->TournamentParents();
    my @recipients = @{$self->{TempPop}->Individuals()};

    # step through @recipients, assigning pairs to families with random different parents
    my @offspring;
    while (@recipients > 1) {
      my $parent1 = splice @parents, int(rand(@parent)), 1;
      my $parent2 = splice @parents, int(rand(@parent)), 1;
      my ($child1, $child2) = splice @recipients, 0, 2;

      $self->crossoverFamily([$parent1, $parent2, $child1, $child2]);

      push @offspring, $child1, $child2;
      push @parents, $parent1, $parent2; # can be parents again;
    }
    # parents and non-reproductive individuals will all die
    push @cohort, @parents;

    # overwrite cohort with offspring
    open(LOG, ">>results/genealogy.log");
    for (my $i=0; $i<@cohort; $i++) {
      print LOG join("\t", 'death_of', $cohort[$i]->UniqueID())."\n";
      $cohort[$i]->load(FileStem => $offspring[$i]->DBFileStem());
      $cohort[$i]->initFitness();
    }
    close(LOG);
  }

}

sub saveOutput {
  my ($self, %p) = @_;
  die unless ($p{Filename} && $p{Output} && $p{Output});

  if (open(FILE, ">$p{Filename}")) {
    printf FILE "# Tournament: %d\n", $self->Tournament();
    if ($p{Individual}) {
      printf FILE "# Individual: %s\n", $p{Individual}->DBFileStem();
      printf FILE "# Fitness:    %s\n", $p{Individual}->Fitness();
    }

    print FILE "# not yet able to save WAV\n";

    close(FILE);
  }
}


sub esdplay {
  my ($pdl) = @_;
  PDL::ReadAudioSoundFile::writeaudiosoundfile($pdl, "/tmp/gpmusic.wav");
  system "esdplay /tmp/gpmusic.wav > /dev/null 2>&1 &";
}
sub esdstop {
    system "killall esdplay esd > /dev/null 2>&1";
}


sub freqvec {
  my $pdl = shift;
  my ($len, $chan) = $pdl->dims;

  my $vec = zeroes($nbands);

  for (my $i=0; $i<$nbands; $i++) {
    set $vec, $i, sum(abs($pdl - $pdl->rotate($bands[$i])))/$len;
  }

  return $vec;
}

sub crossoverFamily {
  my ($self, $family) = @_;
  my ($parent1, $parent2, $child1, $child2) = @$family;

  # always crossover
  my $p1genome = $parent1->tieGenome('p1');
  my $p2genome = $parent2->tieGenome('p2');
  my $c1genome = $child1->tieGenome('c1');
  my $c2genome = $child2->tieGenome('c2');

  $parent1->crossover($parent2, $child1, $child2);
  $c1genome->{unique_id} = $child1->getNewUniqueID();
  $c2genome->{unique_id} = $child2->getNewUniqueID();

  $child1->mutate();
  $child2->mutate();

  if ($self->{SaveEverything}) {
    $child1->save(FileStem=>"results/saved/$c1genome->{unique_id}");
    $child2->save(FileStem=>"results/saved/$c2genome->{unique_id}");
  } else {
    system "touch results/saved/$c1genome->{unique_id}.touch";
    system "touch results/saved/$c2genome->{unique_id}.touch";
  }

  if (open(LOG, ">>results/genealogy.log")) {
    print LOG join("\t",
		   'birth_of', ($c1genome->{unique_id} || "unknown"), 'to_parents', ($p1genome->{unique_id} || "unknown"), ($p2genome->{unique_id} || "unknown"), 'nodes', $child1->getSize(), 'gzip_size', length(compress($child1->getCode(), Z_BEST_COMPRESSION))
		  )."\n";

    print LOG join("\t",
		   'birth_of', ($c2genome->{unique_id} || "unknown"), 'to_parents', ($p1genome->{unique_id} || "unknown"), ($p2genome->{unique_id} || "unknown"), 'nodes', $child2->getSize(), 'gzip_size', length(compress($child2->getCode(), Z_BEST_COMPRESSION))
		  )."\n";

    close(LOG);
  }

  $parent1->untieGenome(); $parent2->untieGenome();
  $child1->untieGenome();  $child2->untieGenome();

  # warn "p1 $parent1->{tie_level} p2 $parent2->{tie_level} c1 $child1->{tie_level} c2 $child2->{tie_level}\n";
}


1;
