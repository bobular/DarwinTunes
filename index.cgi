#!/usr/bin/perl -w
#   -*- mode: cperl -*-

use CGI qw(:standard);
use CGI::Ajax;
use Cwd;
use LWP::Simple qw(get);

my $LOVE = 5;
my $LOVETEXT = 'You loved it.';
my $LOVEREGEXP = qr/love/i;
my $LIKE = 4;
my $LIKETEXT = 'You liked it.';
my $LIKEREGEXP = qr/I like/i;
my $OK = 3;
my $OKTEXT = 'It was OK.';
my $OKREGEXP = qr/ok/i;
my $DISLIKE = 2;
my $DISLIKETEXT = "You didn't like it.";
my $DISLIKEREGEXP = qr/don't/i;
my $HATE = 1;
my $HATETEXT = "You couldn't stand it.";
my $HATEREGEXP = qr/stand/i;
my $UNDO = -1;
my $okprob = 0;
my $zeroprob = 0;

my ($channel) = cwd() =~ /(\w+)$/;
my $nice_channel = nice_channel_name($channel);

my $checkbox_warning = '';

if (param('connect') && param('tcs')) {
  if (0 && param('connect') eq 'm3u') {
    print header(-type=>"audio/x-mpegurl",
		 -content_disposition=>"inline; filename=\"$channel.m3u\"");
    print "http://$ENV{SERVER_NAME}:8000/$channel\n";
    exit;
  } else { # if (param('connect') eq 'pls') {
    print header(-type=>"audio/x-scpls",
		 -content_disposition=>"inline; filename=\"$channel.pls\"");
    print "[playlist]\nNumberOfEntries=1

File1=http://$ENV{SERVER_NAME}:8000/$channel
Title1=Evolectronica - evolving electronic music
Length1=-1

Version=2
";
    exit;
  }
} elsif (param('connect')) {
  $checkbox_warning = p(font({-color=>'red'}, 'You must agree to the terms and conditions.'));
}


my $loopid;
if (param('loopid') && param('loopid') =~ /(\d+)/) {
  $loopid = $1;
}

my $uid;
if (param('uid') && param('uid') =~ /(\d+)/) {
  $uid = $1;
}

my ($rating, $rtext) = parse_rating(param('rating'));

my @lastids;
my %lastids;
if (open(LAST, "status/lastplayed")) {
  while (<LAST>) {
    my ($lp) = split;
    my ($id) = $lp =~ /([1-9]\d*)\.mp3/;
    if (defined $id) {
      push @lastids, $id;
      $lastids{$id} = 1;
    }
  }
  close(LAST);
}

# process rating
if (defined $rating && defined $loopid && $lastids{$loopid}) {
  my $pendingfile = glob "*/Individual*0$loopid.pending";
  if (-s $pendingfile) {
    my $fitfile = $pendingfile;
    $fitfile =~ s/\.pending/.fitness/;
    if (open(FIT, ">>$fitfile")) {
      my $userid = $uid ? $uid : $ENV{REMOTE_ADDR};
      print FIT "$rating $userid\n";
      close(FIT);
      # write the general ratings log if possible
      if (open(RLOG, ">>$channel/ratings.log")) {
	print RLOG time()." $rating $userid\n";
	close(RLOG);
      }
      if (rand(1) < $okprob && $rating > $OK) {
	# find oldest pending file and write OK fitness
	my @pending = glob "*/Individual*.pending";
	# sort them oldest first
	my %mtimes;
	grep { $mtimes{$_} = (stat($_))[9] } @pending;
	@pending = sort {$mtimes{$a} <=> $mtimes{$b}} @pending;
	my $oldest = shift @pending;
	if (-s $oldest) {
	  my $fitfile = $oldest;
	  $fitfile =~ s/\.pending/.fitness/;
	  if (open(FIT, ">>$fitfile")) {
	    print FIT "$OK autorate\n";
	    close(FIT);
	  }
	  open(TOUCH, ">status/activity") && close(TOUCH);
	}
      }
    }
  }
}

my $pjx = new CGI::Ajax(get_ids=>\&get_loop_id_buttons);
print $pjx->build_html($CGI::Q, \&main_html);

sub main_html {
  my $html = '';
  $html .= start_html(-title=>"$nice_channel feedback",
			       -head=>[ Link({-rel=>'stylesheet',
					      -type=>'text/css',

					      -href=>'stylesheet.css'}) ]);
  $html .= div({-id=>'header'},
            div({-id=>'logo'}, img({-src=>"/icons/evo-logo100.png", -width=>52, -height=>50})),
	    div({-id=>'site-name'},
		 a({-href=>'http://evolectronica.com', -target=>'_blank'}, strong('evolectronica'))),
	       div({-id=>'site-slogan'}, $nice_channel)
	       # '(r)evolutionary music making'
	      );

  # print the rating choice form
  $html .= start_form();
  unless (defined $loopid) {
    $html .= div({-class=>'para'}, $checkbox_warning.p("Click the box to confirm that you accept this site's ".a({-href=>'http://evolectronica.com/print/5'}, 'Terms and Conditions').":", checkbox(-name=>'tcs', param('tcs')?(-value=>1):(), -label=>'')),
  "Then click here: ".submit(-name=>'connect', -value=>'Connect to audio stream', -class=>'connect', -onclick=>'document.location="#connected";'), p(a({-name=>'connected'},''), "iTunes, WinAmp, RealPlayer and xmms are known to work.", small("(<b>Having trouble?</b>  Save ", a({-href=>"?connect=1&tcs=1"}, 'this playlist file'), " to your computer, then open it with iTunes or RealPlayer.)")),
# submit(-name=>'connect', -value=>'m3u', -class=>'connect', -onclick=>'document.location="#connected";'), "(Windows Media Player)",
  p("When you are connected, check that your audio player displays the loop numbers correctly (if not, please check the ",a({-href=>"http://evolectronica.com/windows-help", -target=>"_blank"}, "Windows").',', a({-href=>"http://evolectronica.com/mac-help", -target=>"_blank"}, "Mac").',', a({-href=>"http://evolectronica.com/linux-help", -target=>"_blank"}, "Linux"), "and", a({-href=>"http://evolectronica.com/iphone-help", -target=>"_blank"}, "iPhone"), " help pages)."),
  p("Now sit back and listen to the music. When you particularly like or dislike something, make a mental note of the loop number, and then click below."));
  }
  $html .= div({-id=>'rating_div'}, # -style=>"background: url(/icons/evo-logo100.png) no-repeat bottom"},
	       div("What do you think?"),
	    button(-id=>'rating1', -class=>'rating', -value=>"I love it!",
		   -onclick=>"window.timer===undefined||clearTimeout(timer);get_ids(['rating1','NO_CACHE'],['id_div']);hi('rating1');lo('rating2');lo('rating3');lo('rating4');lo('rating5');"), br, br
	    button(-id=>'rating2', -class=>'rating', -value=>"I like it",
		   -onclick=>"window.timer===undefined||clearTimeout(timer);get_ids(['rating2','NO_CACHE'],['id_div']);lo('rating1');hi('rating2');lo('rating3');lo('rating4');lo('rating5');"), br, br
	    button(-id=>'rating3', -class=>'rating', -value=>"It's OK...",
		   -onclick=>"window.timer===undefined||clearTimeout(timer);get_ids(['rating3','NO_CACHE'],['id_div']);lo('rating1');lo('rating2');hi('rating3');lo('rating4');lo('rating5');"), br, br
	    button(-id=>'rating4', -class=>'rating', -value=>"I don't like it",
		   -onclick=>"window.timer===undefined||clearTimeout(timer);get_ids(['rating4','NO_CACHE'],['id_div']);lo('rating1');lo('rating2');lo('rating3');hi('rating4');lo('rating5');"), br, br
	    button(-id=>'rating5', -class=>'rating', -value=>"I can't stand it!",
		   -onclick=>"window.timer===undefined||clearTimeout(timer);get_ids(['rating5','NO_CACHE'],['id_div']);lo('rating1');lo('rating2');lo('rating3');lo('rating4');hi('rating5');")
	       #img({-src=>"/icons/evo-logo100.png", -width=>104, -height=>100})
	      );
  $html .= div({-id=>'id_div'}, defined $loopid && $rtext ?
	       div('Thank you!'.br.
		   small(br."Rating received for<br>loop $loopid:".br.b($rtext)).br.
		   (defined $rating ? submit(-name=>'rating', -value=>'undo', -class=>'tiny').hidden(-name=>'loopid', -default=>$loopid) : ''),
		   br,br,
		   (-l "downloads/loop-$loopid.mp3" ? a({-href=>"downloads/loop-$loopid.mp3", -class=>'download'}, "[save loop $loopid as MP3]").br : ''),
		   (-l "downloads/loop-$loopid.wav" ? a({-href=>"downloads/loop-$loopid.wav", -class=>'download'}, "[save loop $loopid as WAV]").br : ''),
		   (-l "downloads/loop-$loopid.wav" || -l "downloads/loop-$loopid.mp3" ? '<br /><span class="download">Loop licensing:</span><br /><a rel="license" href="http://creativecommons.org/licenses/by-nc/3.0/" target="_blank"><img alt="Creative Commons License" style="border-width:0" src="http://i.creativecommons.org/l/by-nc/3.0/80x15.png" /></a><br />' : ''),
		  )
	       : '&nbsp;').br({-class=>'clearboth'});
  $html .= hidden(-name=>'uid', -default=>$uid).hidden(-name=>'tcs').end_form.br;
  if (defined $loopid && $rtext) {
    $html .= <<'EOJS';
<script type="text/javascript">
timer = setTimeout("wipe('id_div')", 30*1000);
</script>
EOJS
  }
  my @channels = channels();
  if (@channels) {
    my %nice_channels;
    my %listeners;
    my $status = get("http://localhost:8000/status2.xsl");
    if ($status) {
      foreach my $channel (@channels) {
	$listeners{$channel} = $1 if ($status =~ /$channel,+(\d+)/);
      }
    }
    grep { $nice_channels{$_} = nice_channel_name($_).($listeners{$_} ? ($listeners{$_}==1 ? " (1 listener)" : " ($listeners{$_} listeners)") : '')  } @channels;
    $html .= div({-id=>'footer', -class=>'clearboth'},
		 start_form(-action=>"http://evolectronica.com/connect/", -method=>'GET', -class=>'compactform'),
		 span({-class=>'connect'},'Go to '),
		 popup_menu(-name=>'channel',
			    -class=>'connect',
			    -values=>\@channels,
			    -labels=>\%nice_channels,
			    -default=>$channel,
			    -onchange=>'this.form.submit()',
			   ),
                 submit(-name=>'connect', -value=>'go', -class=>'connect'),
                 hidden(-name=>'tcs'),
		 hidden(-name=>'uid'),
		 end_form,br);
  }
  $html .= <<'EOJS';
<script type="text/javascript">
function hi(id1) {
  var b1 = document.getElementById(id1);
  b1.style.background='#F9D700';
}
function lo(id1) {
  var b1 = document.getElementById(id1);
  b1.style.background='white';
}
function wipe(id) {
  var ele = document.getElementById(id);
  ele.innerHTML = '&nbsp;';
}
</script>
EOJS
  $html .= end_html();
  return $html;
}

sub get_loop_id_buttons {
  my $input = shift;
  my $html = 'error: no loops have been streamed';
  if (@lastids) {
    $html  = div("What was the<br>loop number?");
    foreach my $id (reverse @lastids) {
      $html .= submit(-name=>'loopid', -value=>$id, -class=>'loopid');
      if (0 && -l "downloads/loop-$id.mp3") {
	$html .= '&nbsp;'.a({-href=>"downloads/loop-$id.mp3", -class=>'download'}, '[mp3]');
      }
      if (0 && -l "downloads/loop-$id.wav") {
	$html .= '&nbsp;'.a({-href=>"downloads/loop-$id.wav", -class=>'download'}, '[wav]');
      }
      $html .= br;
    }
    $html .= br.button(-name=>"back", -value=>'back', -class=>'loopid', -onclick=>"wipe('id_div');lo('rating1');lo('rating2');lo('rating3');lo('rating4');lo('rating5');").hidden(-name=>'rating', -default=>$input);
  }
  return $html;
}

sub parse_rating {
  my $input = shift;
  my $rtext = '<b style="color: red;">ERROR</b>';
  my $rating;
  if ($input) {
    if ($input =~ $LOVEREGEXP) {
      $rating = $LOVE;
      $rtext = $LOVETEXT;
    } elsif ($input =~ $LIKEREGEXP) {
      $rating = $LIKE;
      $rtext = $LIKETEXT;
    } elsif ($input =~ $OKREGEXP) {
      $rating = $OK;
      $rtext = $OKTEXT;
    } elsif ($input =~ $DISLIKEREGEXP) {
      $rating = $DISLIKE;
      $rtext = $DISLIKETEXT;
    } elsif ($input =~ $HATEREGEXP) {
      $rating = rand(1) < $zeroprob ? 0 : $HATE;
      $rtext = $HATETEXT;
    } elsif ($input eq 'undo') {
      $rating = $UNDO;
      $rtext = 'Rating withdrawn for loop ';
    }
  }
  return ($rating, $rtext);
}

#
# return capitalised and a space before number
#
sub nice_channel_name {
  my $channel = shift;
  $channel =~ s/^([a-z])/uc($1)/e;
  $channel =~ s/(\D)(\d)/$1 $2/;
  return $channel;
}

sub channels {
  my %config;
  if (open(CONF, "/usr/local/evolectronica/evolectronica.conf")) {
    while (<CONF>) {
      next if (/^#/);
      chomp;
      my ($key, $value) = $_ =~ /(\w+)\s*=\s*(.+)/;
      if ($value =~ s/^\[\s*// && $value =~ s/\s*\]$//) {
	$value = [ split ' ', $value ];
      }
      $config{$key} = $value;
    }
    close(CONF);
  }
  return $config{channels} ? @{$config{channels}} : ();
}

