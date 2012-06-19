package Grammar;

# the PerlGP library is distributed under the GNU General Public License
# all software based on it must also be distributed under the same terms

use PDL;
use PDL::Audio::Scales;

$HOUSEBEATS = 0;

# Functions
%F = ();
# Terminals
%T = ();


$F{ROOT} = [ <<'___',
package Individual;

sub add_to_loop {
  my ($spc,$t,$s,$seen) = @_;
  my @n = ({POSINTS}, {POSINTS}, {POSINTS}, {POSINTS});
  @n = map $_ % $nn, @n;
  {LAYERS}
}
___
];

$F{LAYERS} = [ copies(2, '{LAYERS}

  {LAYERS}'),
    copies(4, '{LAYER}') ];

$F{LAYER} = [
  q^if (!$seen->{{TAG}{TAG}{TAG}}++) {
  my $l = zeroes($t);

  {MUSIC}

  addlayer($s, $l, $spc);
  }^
];

$T{LAYER} = $T{LAYERS} = [ '# no layer' ];

#
# alter the ratio between tuned (melody) and untuned (rhythm) here:
#
if ($HOUSEBEATS) {
  $F{MUSIC} = [ copies(0, '{TUNED}'), copies(1, '{UNTUNED}') ];
} else {
  $F{MUSIC} = [ copies(1, '{TUNED}'), copies(0, '{UNTUNED}') ];
}

$F{TUNED} = [ q^if ('tune') {
    my $sound = q[{TSOUND}];
    {INSTA} = ({POSINT},{POSINT},nlen(4*{NOTELEN}));
    {INSTB} = ({VOL},{PAN},{GROOVE},{PHASE});
    {INSTC} = ({POSINT},{POSINT},{POSINT},{POSINT});
    {TUNE}
  }^,
  q^if ('sequencer') {
    my $sound = q[{TSOUND}];
    {INSTA} = ({POSINT},{POSINT},nlen(4*{NOTELEN}));
    {INSTB} = ({VOL},{PAN},{GROOVE},{PHASE});
    {INSTC} = ({POSINT},{POSINT},{POSINT},{POSINT});
    {TRIGGER}
  }^,


 ];

$F{UNTUNED} = [ q^if ('untuned') {
    my $sound = q[{USOUND}];
    {INSTA} = ({POSINT},{POSINT},nlen(4*{NOTELEN}));
    {INSTB} = ({VOL},{PAN},{GROOVE},{PHASE});
    {INSTC} = ({POSINT},{POSINT},{POSINT},{POSINT});
    {TRIGGER}
  }^ ];

$T{MUSIC} = $T{TUNED} = $T{UNTUNED} = [ '# no music' ];

$T{INSTA} = [ 'my ($note, $param, $len)' ];
$T{INSTB} = [ 'my ($vol, $pan, $groove, $phase)' ];
$T{INSTC} = [ 'my ($lowrad, $lowcyc, $hirad, $hicyc)' ];

# mostly tuned
$F{TSOUND} = [
              copies(40, q^asynth({OCTAVE}, $n[$note % @n], $len, $spc, {OVERTONES}, {OVERTONES})^),
              copies(0, q^stretch(resample(loadwav('{SAMPLES}'),$n[$note % @n]),$n[$note % @n],{SLEN},{SRAMP},{SJITTER})^),
              copies(2, q^stretch({TSOUND},$n[$note % @n],{SLEN},{SRAMP},{SJITTER})^),
              copies(2, q^resample({TSOUND},$n[$note % @n])^),
              copies(8, q^reverb({TSOUND},{REVLEN},{REVDULL})^),
              copies(4, q^wah({TSOUND},{WAHFREQ},{WAHDEPTH},{WAHPHASE})^),
              copies(5, q^lowpass({TSOUND},$lowrad,$lowcyc)^),
              copies(4, q^hipass({TSOUND},$hirad,$hicyc)^),
              copies(4, q^slopier({TSOUND},{SHIFTS})^),
              copies(2, q^combine({TSOUND},{TSOUND},{VOL})^),
              copies(2, q^end2end({TSOUND},{TSOUND})^),
              copies(3, q^backwards({TSOUND})^),
            ];

# mostly untuned sounds
$F{USOUND} = [
              copies($HOUSEBEATS ? 0 : 5, q^asynth({OCTAVE}, $n[$note % @n], $len, $spc, {OVERTONES}, {OVERTONES})^),
              copies(30, q^loadwav('{SAMPLES}')^),
              copies(4, q^stretch(resample(loadwav('{SAMPLES}'),$n[$note % @n]),$n[$note % @n],{SLEN},{SRAMP},{SJITTER})^),
              copies(4, q^stretch({USOUND},$n[$note % @n],{SLEN},{SRAMP},{SJITTER})^),
              copies(4, q^resample({USOUND},$n[$note % @n])^),
              copies(8, q^reverb({USOUND},{REVLEN},{REVDULL})^),
              copies(4, q^wah({USOUND},{WAHFREQ},{WAHDEPTH},{WAHPHASE})^),
              copies(5, q^lowpass({USOUND},$lowrad,$lowcyc)^),
              copies(4, q^hipass({USOUND},$hirad,$hicyc)^),
              copies(4, q^slopier({USOUND},{SHIFTS})^),
              copies(2, q^combine({USOUND},{USOUND},{VOL})^),
              copies(2, q^end2end({USOUND},{USOUND})^),
              copies(3, q^backwards({USOUND})^),
            ];

# copies(15, q^loadsynth('{SYNTHS}',$n[$note % @n],$p[$param % @p],$len,$spc)^),
# copies(5, q^loadeffect('{EFFECTS}', {SOUND}, $n[$note % @n],$p[$param % @p])^),

$T{TSOUND} = $T{USOUND} = [ 'null' ];
$T{OCTAVE} = [ 1/8, 1/4, 1/2, 1, 2, 4 ];

$F{OVERTONES} = [ '{OVERTONE}, {OVERTONES}', '{OVERTONE}',
                  '{OVERTONES}, {OVERTONE}', '{OVERTONE}' ];
$F{OVERTONE} = [ '{OTSPEC}',' mseries({OTSPEC}, {NSERIES}, {MULTIPLE}, {ZTO})',
 ];
$F{OTSPEC} = [ '[{MULTIPLE}, {ZTO}, {ZTO}, {MODFREQ}, {SADSR}]' ];
$F{SADSR} = [ '{ZTO}, {POSINT}, {POSINT}, {POSINT}, {POSINT}, {ADSRPOW}',
              '{ZTO}, {POSINT}, {POSINT}, {POSINT}, -{NOTELEN}, {ADSRPOW}' ];
$T{SADSR} = [ '0.5, 1, 1, 1, 1' ];
$T{OVERTONES} = $T{OVERTONE} = $T{OTSPEC} = [ '[1, 0.1, 0, 0, 0.5, 1, 1, 1, 1]' ];
$T{ADSRPOW} = [ '1/4', '1/3', '1/2', 1, 1, 1, 2, 3, 4 ];
$T{MULTIPLE} = [ map { 1+int(rand(rand(12))) } (1..1000)  ];
$T{NSERIES} = [ map { 1+int(rand(rand(8))) } (1..1000)  ];

$F{STEPS} = [ '{STEP},{STEPS}', '{STEP}' ];
$T{STEP} = $T{STEPS} = [ 1 .. 5 ];

$F{MODFREQ} = [ '0', '0', '{POSINT}*{POSINT}', '{POSINT}' ];
$T{MODFREQ} = [ '0' ];
# $T{WAVEFORM} = [ 0, 0, 0, 1, 2, 3 ];

$F{TRIGGER} = [ copies(2, '{TRIGGER}
    {MODULATES}
    {TRIGGER}'),
  copies(5, q^$l->dice(X,{RHYTHM}) .= pdl([getsound(eval '"'.$sound.'"'),$vol,$pan,$groove,$phase]);^),
    ];

##  copies(0, '$l->dice(X,{RHYTHM}) .= zeroes(5);'), # silence is golden

$F{TUNE} = [ copies(1, q^my $remain=$l->nelem/5;
my $rest;
foreach(1..{NSERIES}){
 foreach my $ref({MELODY}){
  ($note,$len,$rest) = @$ref;
  $l->dice(X,[0],[0],[0]) .= pdl([getsound(eval '"'.$sound.'"'),$vol,$pan,$groove,$phase]);
  $l=offset($l,-int($len+$rest));
  $remain-=$len+$rest;
 }
 last if($remain<0);
}
$l = offset($l,{OFF});^),
];
$T{TUNE} = [ '# no tune' ];

$T{TRIGGER} = [ '# no trigger points' ];
$T{NORP} = [ copies(3, '$note'), '$param' ];

$F{POSINTS} = [ '{POSINT}, {POSINTS}', '{POSINT}' ];

# $F{MORENOTES} = [ copies(2, '{MORENOTES}
#   {MORENOTES}'),
#   copies(5, 'push @n, $n[{POSINT} % @n] + {POSNEG};'),
# ];
# $T{MORENOTES} = [ '# no more notes' ];

$F{MODULATES} = [ copies(2, '{MODULATES}
    {MODULATES}'),
  copies(5, '{MODULATE}'),
 ];

$F{MODULATE} = [
                copies(16, '{INTPARAM} += {POSNEG};'),
                copies(8, '{REALPARAM} *= {NUDGE};'),
                copies(4, '$len = nlen(4*{NOTELEN});'),
                copies($HOUSEBEATS ? 0 : 4, '$l = offset($l, {OFF});'),
#                copies(4, '$sound = q[SOUND}];'),
               ];
$T{MODULATES} = $T{MODULATE} = [ '# no modulation' ];

$T{REALPARAM} = [ qw($vol $pan) ];
$T{INTPARAM} = [ qw($note $note $note $param $param $lowrad $lowcyc $hirad $hicyc) ];

$F{VOL} = [ '{VOLX}+{VOLX}+{VOLX}+{VOLX}+{VOLX}' ];
$T{VOL} = $T{VOLX} = [ map $_/100, 1 .. 15 ];

$T{NUDGE} = [ map $_/100, (80 .. 120) ];

$F{MELODY} = [ '{NOTESPEC}, {MELODY}', '{MELODY}, {NOTESPEC}',
    copies(2, '{NOTESPEC}') ];
$F{NOTESPEC} = [ '[{POSINT}, nlen(4*{NOTELEN}), {OPTREST}]' ];
$T{MELODY} = $T{NOTESPEC} = [ '[1, nlen(4), nlen(4)]' ];

$F{OPTREST} = [ 0, 0, 'nlen(4*{NOTELEN})' ];
$T{OPTREST} = [ 0 ];

$F{NOTELEN} = [ copies(2, '{NOTELEN}*{NOTELEN}'),
                copies(6, '({NLX}/{NLX})'),
              ];
$T{NOTELEN} = [ 1 ];
$T{NLX} = [ 1 .. 4 ];

unless ($HOUSEBEATS) {
  $F{RHYTHM} = [ '{SUBBEAT},{BEAT},{BAR}',
	         '{SUBBEAT},{BEATBAR}',
	         '{SUBBB},{BAR}',
	       ];
}

$T{RHYTHM} = [ '[0],X,X', '[2],X,X', '[0],[1,3],X' ];

$F{BEATBAR} = [ '{BEAT},{BAR}', 'X,X' ];
$T{BEATBAR} = [ 'X,X' ];

$F{SUBBB} = [ '{SUBBEAT},{BEAT}' ];
$T{SUBBB} = [ '[0],X' ];


$F{PAN} = [ '0.5', '0.4', '0.6', copies(3, '{ZTO}') ];
$T{PAN} = [ '0.5' ];

unless ($HOUSEBEATS) {
  $F{GROOVE} = [ copies(6, '{GROOVEX}'),
		 '{POSINT}',
	         '-{POSINT}'
  ];
}

$T{GROOVEX} = $T{GROOVE} = [ 0 ];

$F{PHASE} = [ copies (6, '{PHASEX}'),
	      '{POSINT}',
	      '-{POSINT}',
	    ];
$T{PHASEX} = $T{PHASE} = [ 0 ];

$T{REVLEN} = [ 0.5, 1, 1.5, 1.5, 1.5, 2 ];
$T{REVDULL} = [ 0, 0, 1, 1, 1, 2, 2, 3, 4 ];

$F{WAHFREQ} = [ '{ZTO}*({POSINT})' ];
$T{WAHFREQ} = [ 1 ];
$F{WAHDEPTH} = [ '{ZTO}*{ZTO}' ];
$T{WAHDEPTH} = [ 0.2, 0.5 ];
$F{WAHPHASE} = [ 0, 0, 0.5, 0.5, 0.25, 0.75, '{ZTO}' ];
$T{WAHPHASE} = [ 0, 0, 0.5, 0.5, 0.25, 0.75 ];
$T{SLEN} = [ 0.0001, 0.001, 0.01, 0.05, 0.1, 0.15, 0.2 ];
$T{SRAMP} = [ 0.1, 0.2, 0.3, 0.4 ];
$T{SJITTER} = [ 0.1, 0.25, 0.5, 1, 2 ];

$F{SHIFTS} = [ '{SHIFTS},{SHIFT}','{SHIFT},{SHIFTS}',
               copies(2, '{SHIFT}') ];
$T{SHIFTS} = $T{SHIFT} = [ map {int(1+250*rand(1)*rand(1))} (1 .. 10000)];

$F{FOUR} = [ copies(2, '{FOUR},{FOUR}'),
	     copies(4, '{FOURX}') ];
$T{FOUR} = $T{FOURX} = [ 0 .. 3 ];

$F{SIX} = [ copies(2, '{SIX},{SIX}'),
	     copies(4, '{SIXX}') ];
$T{SIX} = $T{SIXX} = [ 0, 0, 0, 3, 3, 0 .. 5 ];

$F{FIVE} = [ copies(2, '{FIVE},{FIVE}'),
	     copies(4, '{FIVEX}') ];
$T{FIVE} = $T{FIVEX} = [ 0, 0, 0 .. 4 ];

$F{THREE} = [ copies(2, '{THREE},{THREE}'),
	     copies(4, '{THREEX}') ];
$T{THREE} = $T{THREEX} = [ 0, 0 .. 2 ];

$F{TWO} = [ copies(2, '{TWO},{TWO}'),
	     copies(4, '{TWOX}') ];
$T{TWO} = $T{TWOX} = [ 0, 0, 1 ];


### -+- change the "FOUR" to TWO,THREE,FIVE,SIX as required
$F{BAR} = [ copies(1, 'X'), copies(1, '[{FOUR}]') ];
$T{BAR} = [ 'X' ];
$F{BEAT} = [ copies(0, 'X'), copies(2, '[{FOUR}]') ];
$T{BEAT} = [ 'X' ];
$F{SUBBEAT} = [ '[0]', copies(2, '[{FOUR}]') ];
$T{SUBBEAT} = [ '[0]' ];

$F{OFF} = [ '{FOURX}*4*4+{FOURX}*4+{FOURX}' ];
$T{OFF} = [ 0 ];

$F{POSNEG} = [ '-{POSINT}', '{POSINT}' ];
$F{POSINT} = [ copies(2, '({POSINT}+{POSINT})'),
	       copies(2, '{POSINT}*{POSINT}'),
	       copies(12, '{POSINTX}') ];
$T{POSINT} = $T{POSINTX} = $T{FQ} = $T{POSNEG} = $T{POSINTS} = [ 1 .. 8 ];

$F{OFFSETS} = [ copies(2, '{OFFSETS}, {OFFSETS}'),
                copies(5, '{POSINT}'),
              ];
$T{OFFSETS} = [ -8 .. 8 ];

$F{WAVID} = [ q"$wn{'{SAMPLES}'}", '$w->get({POSINT})' ];
$T{WAVID} = [ '$w->get(1)' ];

# find_samples will fill $F{SAMPLES} and children
find_samples('samples');

$T{WAV} = [ 'no_wav' ];

# same for synths
#find_synths('synths');
$T{SYNTHS} = [ 'no_synth' ];

# same for effects
#find_synths('effects');
$T{EFFECTS} = [ 'no_fx' ];

$T{ZTO} = [ map sprintf("%.4g", rand(1)), (1 .. 10000) ];

$T{FREQ} = [ map sprintf("%.6f", $_*110/44100), (1, 2, 4) ];


$F{AMPLIFY} = [ copies(3, '{AMPLIFY}
  {AMPLIFY}'),
		copies(5, '$s *= {ZTO};'),
		copies(5, '$s /= max($s); $s *= 2**15;'),
];

$T{AMPLIFY} = [ '# no amplify' ];

$F{SUM} = [ '{SUM} + {SUM}', '{SUM} - {SUM}', copies(5, '{NUM}') ];

$F{NUM} = [ '{NUM}*{NUM}',
	    'pdiv({NUM},{NUM})',
	    '({NUM} + {NUM})',
	    '({NUM} - {NUM})',
            # '{NUM}**{POW}',
            copies(8, '{NUMX}'),
	  ];

$T{ROOT} = [ 'sub add_to_loop { return }' ];

$T{NUM} = $T{NUMX} = $T{SUM} = [ 1 .. 100 ];
$T{POW} = [ 2 .. 7 ];
$T{DENOM} = [ 100, 200, 400 ]; # [ 25, 50, 100, 200 ];
$T{TAG} = [ 'a' .. 'z' ];


# this helper routine will give you multiple copies of
# something, i.e qw(1 1 1 2 3) is equivalent to (copies(3, 1), 2, 3)
sub copies {
  my ($num, @things) = @_;
  my @result;
  while ($num-->0) {
    push @result, @things;
  }
  return @result;
}

sub find_samples {
  my $dir = shift;
  my @glob = glob "$dir/*";

  my @samples = grep /\.wav/i, @glob;
  my @subdirs = grep { m(/[a-zA-Z]+$) && -d $_ } @glob;

  my @subtypes = map uc, @subdirs;
  grep s/[^A-Z]//g, @subtypes;

  my $type = uc($dir);
  $type =~ s/[^A-Z]//g;

  $F{$type} = [ ( map "{$_}", @subtypes ),
	        @samples
	      ];

  @samples = ('no_wav') unless (@samples); # need something as terminal
  $T{$type} = [];
  foreach $wav (@samples) {
    push @{$T{$type}}, $wav;

    # store the wav file names in an array
    # and keep a hash of the indexes
    $Individual::wn{$wav} = scalar @Individual::wf;
    push @Individual::wf, $wav;
  }

  foreach $dir (@subdirs) {
    find_samples($dir);
  }
}

sub find_synths {
  my $dir = shift;
  my @glob = glob "$dir/*";

  my @synths = grep -f $_, @glob;
  my @subdirs = grep { m(/[a-zA-Z]+$) && -d $_ } @glob;

  my @subtypes = map uc, @subdirs;
  grep s/[^A-Z]//g, @subtypes;

  my $type = uc($dir);
  $type =~ s/[^A-Z]//g;

  $F{$type} = [ ( map "{$_}", @subtypes ),
	        @synths
	      ];

  @synths = ('no_synth') unless (@synths); # need something as terminal
  $T{$type} = [];
  foreach $synth (@synths) {
    push @{$T{$type}}, $synth;
  }
  foreach $dir (@subdirs) {
    find_synths($dir);
  }
}



1;
