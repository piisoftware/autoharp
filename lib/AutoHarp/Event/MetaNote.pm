package AutoHarp::Event::MetaNote;

use AutoHarp::Event;
use AutoHarp::Event::Note;
use AutoHarp::Constants;

use base qw(AutoHarp::Event::Note);
use Carp;

use strict;

#A4 == 440 is our reference frequency
my $REF_FREQ = 440;
my $REF_PITCH = 69;

my $C0_FREQ = 8.1757989156;
my $WHEEL_HALF_STEP = 4096;

sub new {
  my $class = shift;
  my $self  = shift;
  if (ref($self) ne 'HASH') {
    confess "I'm sick of allowing whatever. Pass me a hash";
  }
  if (!$self->{$ATTR_FREQUENCY}) {
    confess "Cannot create a meta-note without a frequency";
  }
  return bless $self, $class;
}

sub toNote {
  confess "Can't call toNote on MetaNote--it's a buncha stuff";
}

sub toNotes {
  my $self = shift;
  my $nearestNote = AutoHarp::Event::Note->new($self->nearestPitch(),
					       $self->duration(),
					       $self->velocity(),
					       $self->time);
  my $pitchAbove = $nearestNote->clone();
  $pitchAbove->pitch($pitchAbove->pitch + 1);
  
  my $lowerFreq = $nearestNote->frequency();
  my $nextFreq  = $pitchAbove->frequency();
  #getting to the frequence we want should be a linear function of the pitch wheel
  #know $nextFreq - $lowerFreq = 4096, so calculate fraction of that that I want
  my $pitchBend = int($WHEEL_HALF_STEP *
		      (($self->frequency() - $lowerFreq) /
		       ($nextFreq - $lowerFreq)));
  my $events = [];
  return [AutoHarp::Event->new([$EVENT_PITCH_WHEEL,
				$self->time,
				$self->channel,
				$pitchBend]),
	  $nearestNote->clone()];
}

sub nearestPitch {
  my $self = shift;
  my $log2 = log($self->frequency / $REF_FREQ) / log(2);
  return ($DEFAULT_SCALE_SPAN * $log2) + $REF_PITCH;
}

sub time {
  return $_[0]->scalarAccessor($ATTR_TIME, $_[1]);
}

sub duration {
  return $_[0]->scalarAccessor($ATTR_DURATION, $_[1]);
}

sub channel {
  return $_[0]->scalarAccessor($ATTR_CHANNEL, $_[1]);
}

sub pitch {
  confess "NO PITCH!";
}

sub frequency {
  return $_[0]->scalarAccessor($ATTR_FREQUENCY, $_[1]);
}

sub velocity {
  return $_[0]->scalarAccessor($ATTR_VELOCITY, $_[1]);
}

sub value {
  return ($_[0]->frequency($_[1]));
}

sub noteAndOctave {
  confess "NO NOTE AND OCTAVE";
}

sub letter {
  confess "NO CAN DO!";
}

sub drum {
  confess "NO drums!";
}

sub isKickDrum {
  confess "NO drums!";
}

sub isSnare {
  confess "I SAID NO DRUMS!";
}

sub octave {
  my $self = shift;
  my $arg  = shift;

  my $start = $C0_FREQ;
  my $oct = 0;
  while ($start < $self->{$ATTR_FREQUENCY}) {
    $start *= 2;
    $oct++;
  }
  if (length($arg)) {
    while ($arg > $oct) {
      $self->{$ATTR_FREQUENCY} *= 2;
      $oct++;
    }
    while ($arg < $oct) {
      $self->{$ATTR_FREQUENCY} /= 2;
      $oct--
    }
  }
  return $oct;
}

sub toString {
  my $self = shift;
  my $theNotes = $self->toNotes();
  
  return sprintf("%4.2f from %d (%4.2f) bent up %2.1f%s of a half-step",
		 $self->frequency(),
		 $theNotes->[1]->pitch(),
		 $theNotes->[1]->frequency(),
		 ($theNotes->[0]->[3]/$WHEEL_HALF_STEP) * 100,
		 '%');
}

sub dump {
  my $self = shift;
  printf "[%4s %6d %4d %2d %4.2f %3d]\n",
    $EVENT_NOTE,
    $self->{$ATTR_TIME},
    $self->{$ATTR_DURATION},
    $self->{$ATTR_CHANNEL},
    $self->{$ATTR_FREQUENCY},
    $self->{$ATTR_VELOCITY};
}

"You've got my heart working overtime.";


