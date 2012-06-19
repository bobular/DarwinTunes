package PDL::ReadAudioSoundFile;

use PDL;
use PDL::Audio;

#### these are not needed any more - see _OLD subs below
#use Audio::SoundFile;
#use Audio::SoundFile::Header;

#no longer exported due to strange AUTOLOAD problem in perl 5.8.8
#require Exporter;
#@EXPORT = qw(readaudiosoundfile writeaudiosoundfile);

$BUFSIZE = 8**7;

sub readaudiosoundfile {
  my ($file) = @_;

  $^W = 0;
  my $pdl = raudio($file);
  $^W = 1;

  # raudio reads stereo files the other way round
  if ($pdl->ndims == 2) {
    my $hdr = $pdl->gethdr;
    $pdl = $pdl->mv(-1,0)->sever;
    $pdl->sethdr($hdr);
  }
  return $pdl;
}

## default WAV file output only
sub writeaudiosoundfile {
  my ($pdl, $file) = @_;
  $pdl = $pdl->scale2short unless ($pdl->type == short);
  $^W = 0;
  $pdl->mv(-1,0)->waudio( path => $file, filetype => FILE_RIFF,
			  format => FORMAT_16_LINEAR_LITTLE_ENDIAN );
  $^W = 1;
}


sub readaudiosoundfile_OLD {
  my ($file, $debug) = @_;

  my $header;
  my $reader = new Audio::SoundFile::Reader($file, \$header);
  my $channels = $header->{channels};
  my $samples = $header->{samples};
  my $samplerate = $header->{samplerate};
  if ($debug) {
    foreach $key (keys %$header) {
      warn "$key => $header->{$key}\n";
    }
  }
  my %hdr = (path=>$file,
	     rate=>$samplerate);

  my $pdl;
  my $remaining = $samples*$channels;
  my ($buf, $got);
  while (($got = $reader->bread_pdl(\$buf, $remaining > $BUFSIZE ? $BUFSIZE : $remaining)) > 0) {
    $remaining -= $got;
    if (defined $pdl) {
      $pdl = $pdl->append($buf);
      $pdl->sever;
    } else {
      $pdl = $buf->copy();
    }
  }
  $reader->close();
  # if stereo, the piddle from bread_pdl has the two channels
  # 'interleaved' and these need to be separated.
  if ($channels == 2) {
    my $left = $pdl->slice("0:-1:2");
    my $right = $pdl->slice("1:-1:2");
    my $both = cat $left, $right;
    $both->sethdr(\%hdr);
    return $both;
  } elsif ($channels == 1) {
    $pdl->sethdr(\%hdr);
    return $pdl;
  } else {
    die "can't handle $channels channels";
  }
}


sub writeaudiosoundfile_OLD {
  my ($pdl, $file) = @_;

  my $header = new Audio::SoundFile::Header(
  	         samplerate => $pdl->rate() || 44100,
		 channels => $pdl->dim(1),
		 pcmbitwidth => 16,
                 format => SF_FORMAT_WAV | SF_FORMAT_PCM,
	       );

  my $writer = new Audio::SoundFile::Writer($file, $header);

  $pdl = $pdl->scale2short unless ($pdl->type == short);

  # fold stereo sample into a single piddle
  if ($pdl->dim(1) == 2) {
    $pdl = $pdl->xchg(0,1)->flat;
  }

  for (my $i=0; $i<$pdl->dim(0); $i+=$BUFSIZE) {
    my $end = $i+$BUFSIZE-1;
    $end = -1 if ($end >= $pdl->dim(0));

    my $buf = $pdl->slice("$i:$end")->sever;
    my $wrote = $writer->bwrite_pdl($buf);
  }
  $writer->close;
}
1;
