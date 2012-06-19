#!/usr/local/bin/perl -w
#GPL#

use lib '.', $ENV{PERLGP_LIB} ||  die "
  PERLGP_LIB undefined
  please see README file concerning shell environment variables\n\n";

use Population;
use Individual;
use Algorithm;
use Cwd;

use Compress::Zlib;

# get the name of this run from the current directory.
# this will be used for filenames to save populations etc.
my ($exptid) = cwd() =~ m:([^/]+)$:;

# make an empty Population object
my $population = new Population( ExperimentId => $exptid,
			       );
# and fill it from disk or tar file
$population->repopulate();

mkdir 'results' unless (-d 'results');
my $algorithm = new Algorithm( Population => $population );
# or fill it up with new Individuals
while ($population->countIndividuals() < $population->PopulationSize()) {
  if ($population->countIndividuals() < 2) {
    my $founder;
    $population->addIndividual($founder =
			       new Individual( Population => $population,
					       ExperimentId => $exptid,
					       DBFileStem => $population->findNewDBFileStem()));
    my $ntracks;
    while ( ($ntracks = num_tracks($founder)) < 6 || $ntracks > 8) {
      $founder->initTree();
    }

    my $gzip_size = length(compress($founder->getCode(), Z_BEST_COMPRESSION));
    open(LOG, ">>results/genealogy.log");
    print LOG join("\t", 'birth_of', $founder->UniqueID(), 'to_parents', '', '', 'nodes', $founder->getSize(), 'gzip_size', $gzip_size)."\n";
    close(LOG);
    $founder->save(FileStem=>"results/saved/".$founder->UniqueID);

  } else {
    my ($parent1, $parent2) = $population->selectCohort(2);
    my $child1 = new Individual( Population => $population,
			       ExperimentId => $exptid,
			       DBFileStem => $population->findNewDBFileStem() );
    $population->addIndividual($child1);
    $child1->getCode(); # to make a tree
    my $child2 = new Individual( Population => $population,
			       ExperimentId => $exptid,
			       DBFileStem => $population->findNewDBFileStem() );
    $population->addIndividual($child2);
    $child2->getCode(); # to make a tree

    $algorithm->crossoverFamily( [$parent1, $parent2, $child1, $child2] );

  }
}

sub num_tracks {
  my ($self) = @_;
  my $code = $self->getCode();

  my @keys = $code =~ /seen->\{(\w+)\}\+\+/g;
  my %uniq;
  @keys = grep !$uniq{$_}++, @keys;
  return scalar @keys;
}
