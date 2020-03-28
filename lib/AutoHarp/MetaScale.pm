package AutoHarp::MetaScale;

use Carp;
use Data::Dumper;
use MIDI;
use AutoHarp::Fuzzy;
use AutoHarp::Constants;

use base qw(AutoHarp::Scale);

use strict;

my $DENOMS = [1,2,3,4,5,6,8,9,12];
#A5 == 440 is our reference frequency
my $REF_FREQ = 440;
my $REF_PITCH = $MIDI::note2number{'A5'};
my $REF_OCTAVE = 5;
my $CENTS_LIMIT = 0.01;

my $RAW_NOTE = 'rawNote';
my $BASE_OCTAVE = 'baseOctave';

my $NUM = 'num';
my $DENOM = 'denom';
my $DIFF  = 'diff';
my $NAME = 'name';

sub new {
  my $class = shift;
  my $self  = $class->hashArgs(@_);
  $self->{$ATTR_PITCH}      ||= $DEFAULT_ROOT_PITCH;
  $self->{$ATTR_SCALE_SPAN} ||= $DEFAULT_SCALE_SPAN;
  
  if (!exists $MIDI::number2note{$self->{$ATTR_PITCH}}) {
    confess "$self->{$ATTR_PITCH} is not a valid input";
  }
  
  ($self->{$RAW_NOTE},$self->{$BASE_OCTAVE}) =
    ($MIDI::number2note{$self->{$ATTR_PITCH}} =~ /^(\w+)(\d+)/);
  
  bless $self, $class;
  return $self
}

sub rootPitch {
  my $self = shift;
  return $self->{$ATTR_PITCH};
}

sub rootFrequency {
  return $_[0]->frequencyForPitch($_[0]->{$ATTR_PITCH});
}

sub frequencyForPitch {
  my $self  = shift;
  my $pitch = shift;

  my $exp = ($pitch - $REF_PITCH) / $DEFAULT_SCALE_SPAN;
  return $REF_FREQ * (2 ** $exp);
}

sub frequencyForNote {
  return $_[0]->frequencyForPitch($MIDI::note2number{$_[1]});
}

sub getScaleFrequencies {
  my $self  = shift;
  my $span  = $self->{$ATTR_SCALE_SPAN};
  my $scale = [$self->rootFrequency()];
  my $ratio = (2 ** (1/$span));
  for (1..$span) {
    push(@$scale, $scale->[$_ - 1] * $ratio);
  }
  return $scale;
}

sub dump {
  my $self = shift;
  my $root = $self->rootFrequency();
  my $freqs = $self->getScaleFrequencies();
  for(my $i = 0; $i < scalar @$freqs; $i++) {
    my $data = __findNearestInterval($freqs->[$i] / $root);
    printf "%2d) %4.2f => ",$i,$freqs->[$i];
    if ($data) {
      printf "%d/%d (%s)\n",
	$data->{$NUM},
	$data->{$DENOM},
	$data->{$NAME};
    } else {
      printf "%4.2f (unknown)\n",$freqs->[$i] / $root;
    }
  }
}

sub __findNearestInterval {
  my $frac = shift;
  my $closest = $CENTS_LIMIT;
  my $ret;
  foreach my $d (@$DENOMS) {
    for (my $n = int($d/2) + 1; $n <= 2 * $d; $n++) {
      my $cc = abs(1 - (($n / $d) / $frac));
      if ($cc < $closest) {
	$closest = $cc;
	$ret = {$NUM => $n,
		$DENOM => $d,
		$NAME => __justInterval($n,$d)
	       };
      }
    }
  }
  return $ret;
}
    

sub __justInterval {
  my $num = shift;
  my $denom = shift;
  return $JUST_RATIOS->{"$num:$denom"} || 'Marizan';
}


"Alarm clock!";
