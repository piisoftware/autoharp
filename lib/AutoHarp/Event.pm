package AutoHarp::Event;
use AutoHarp::Event::Marker;
use AutoHarp::Event::Text;
use AutoHarp::Constants;

use base qw(AutoHarp::Class);

use Carp;
use MIDI;
use strict;

# 0 => TYPE
# 1 => TIME
# 2 => CHANNEL
# 3 => VALUE (if relevant)

my $EVENT_ZERO = "timeZero";
my $EVENT_END  = "endMarker";

my @VALID_EVENTS = ($EVENT_CHANNEL_AFTERTOUCH,
		    $EVENT_CHORD,
		    $EVENT_CONTROL_CHANGE,
		    $EVENT_INSTRUMENT_NAME,
		    $EVENT_KEY_AFTERTOUCH,
		    $EVENT_KEY_SIGNATURE,
		    $EVENT_MARKER,
		    $EVENT_NOTE,
		    $EVENT_PATCH_CHANGE,
		    $EVENT_PITCH_WHEEL,
		    $EVENT_REST,
		    $EVENT_SET_TEMPO,
		    $EVENT_TEXT,
		    $EVENT_TIME_SIGNATURE,
		    $EVENT_TRACK_NAME
		   );

my @MUSIC_GUIDE_EVENTS = ($EVENT_KEY_SIGNATURE,
			  $EVENT_SET_TEMPO,
			  $EVENT_TIME_SIGNATURE,
			  $EVENT_TEXT,
			  $EVENT_MARKER
			 );

my @MUSIC_EVENTS = ($EVENT_CHANNEL_AFTERTOUCH,
		    $EVENT_CHORD,
		    $EVENT_CONTROL_CHANGE,
		    $EVENT_KEY_AFTERTOUCH,
		    $EVENT_NOTE,
		    $EVENT_PATCH_CHANGE,
		    $EVENT_PITCH_WHEEL,
		   );

sub new {
  my $class = shift;
  my $event = shift;
  if (ref($event) ne 'ARRAY') {
    confess "Argument to $class must be an array";
  } else {
    my $type = $event->[0];
    if ($type eq $EVENT_TEXT ||
	$type eq $EVENT_TRACK_NAME ||
	$type eq $EVENT_INSTRUMENT_NAME) {
      my $e = AutoHarp::Event::Text->new($event);
      $e->[0] = $type;
      return $e;
    } elsif ($type eq $EVENT_MARKER) {
      return AutoHarp::Event::Marker->new($event);
    } elsif ($type eq $EVENT_NOTE) {
      return AutoHarp::Event::Note->new($event);
    } elsif ($type eq $EVENT_CHORD) {
      return AutoHarp::Event::Chord->new($event);
    }
  }
  bless $event, $class;
  return $event;
}

sub zeroEvent {
  my $class = shift;
  my $time  = shift || 0;
  return AutoHarp::Event::Marker->new($EVENT_ZERO, $time);
}

sub eventEnd {
  my $class = shift;
  my $time  = shift || 0;
  return AutoHarp::Event::Marker->new($EVENT_END, $time);
}

#translate self to a line of text separated by commas
sub toTextLine {
  my $self = shift;
  return join(",",@$self);
}

sub fromTextLine {
  my $class = shift;
  my $line = shift;
  return $class->new([split(",",$line)]);
}

sub __validEvent {
  my $e = shift;
  return (scalar grep {$e eq $_} @VALID_EVENTS);
}

sub __musicEvent {
  my $e = shift;
  return (scalar grep {$e eq $_} @MUSIC_EVENTS);
}

sub __musicGuideEvent {
  my $e = shift;
  return (scalar grep {$e eq $_} @MUSIC_GUIDE_EVENTS);
}

sub clone {
  my $self = shift;
  return bless [@$self],ref($self);
}

sub type {
  my $self = shift;
  return $self->[0];
}

sub isText {
  return (shift)->type eq $EVENT_TEXT;
}

sub isMusic {
  return __musicEvent((shift)->type);
}

sub isNote {
  return (shift)->type eq $EVENT_NOTE;
}

sub isChord {
  return (shift)->type eq $EVENT_CHORD;
}

sub isNotes {
  my $self = shift;
  return ($self->isNote || $self->isChord);
}

sub isPercussion {
  my $self = shift;
  return ($self->isNote() && $self->channel() == $PERCUSSION_CHANNEL);
}

sub isMusicGuide {
  return __musicGuideEvent((shift)->type);
}

sub isScaleOrClock {
  my $self = shift;
  return ($self->isScale() || $self->isClock());
}

sub isScale {
  return (shift)->type eq $EVENT_KEY_SIGNATURE;
}

sub isClock {
  my $self = shift;
  return ($self->isTempo() ||
	  $self->isMeter());
}

sub isTempo {
  return ($_[0]->type eq $EVENT_SET_TEMPO);
}

sub isMeter {
  return ($_[0]->type eq $EVENT_TIME_SIGNATURE);
}

sub isGenre {
  return ($_[0]->isText() && $_[0]->text() =~ /$ATTR_GENRE/);
}

sub isZeroEvent {
  my $self = shift;
  return ($self->isMarker() && $self->text() eq $EVENT_ZERO);
}

sub isMarker {
  my $self = shift;
  return ($self->type eq $EVENT_MARKER);
}

sub isEndEvent {
  my $self = shift;
  return ($self->isMarker() && $self->value() eq $EVENT_END);
}

sub isNameEvent {
  my $self = shift;
  return ($self->type eq $EVENT_TRACK_NAME || $self->type eq $EVENT_INSTRUMENT_NAME);
}
  
sub time {
  my $self = shift;
  my $arg  = shift;
  if (length($arg)) {
    $self->[1] = $arg;
  }
  return $self->[1];
}

sub duration {
  return 0;
}

sub reach {
  my $self = shift;
  my $arg  = shift;
  if (length($arg)) {
    confess "Event reach cannot be set, it is a derived quantity";
  }
  return $self->time + $self->duration;
}

sub channel {
  my $self = shift;
  if ($self->isMusic()) {
    my $arg  = shift;
    my $idx  = ($self->type eq $EVENT_NOTE || 
		$self->type eq $EVENT_CHORD) ? 3 : 2;
    if (length($arg) && $arg >= 0) {
      $self->[$idx] = $arg;
    }
    return $self->[$idx];
  } 
  return 0;
}

sub value {
  my $self = shift;
  if (scalar @$self > 3) {
    my $arg = shift;
    if (length($arg)) {
      $self->[3] = $arg;
    }
    return $self->[3];
  } 
  return 0;
}

#compare type and value
sub equals {
  my $self = shift;
  my $otherEvent = shift;
  if (ref($otherEvent) && 
      scalar @$self == scalar @$otherEvent &&
      $self->type() eq $otherEvent->type() &&
      $self->value() eq $otherEvent->value()) {
    return 1;
  }
  return;
}

#compare two events by time and type 
#put notes after everything else, sort notes by pitch low to high
sub lessThan {
  my $self = shift;
  my $other = shift;
  if ($other) {
    if ($self->time == $other->time) {
      if ($self->isNote() && $other->isNote()) {
	return $self->pitch < $other->pitch;
      } elsif ($self->type eq $other->type || $self->isNotes()) {
	return;
      } elsif ($other->isNotes() || $self->isText()) {
	return 1;
      } 
    } else {
      return $self->time < $other->time;
    }
  }
  return;
}

sub dump {
  my $self = shift;
  
  printf "[%-14s %5d",$self->type,$self->time;
  if ($self->isScale) {
    printf " %s",AutoHarp::Scale::KeyFromMidiEvent($self);
  } elsif ($self->type eq $EVENT_TIME_SIGNATURE) {
    printf " %s",AutoHarp::Clock::MeterFromMidiEvent($self);
  } elsif ($self->type eq $EVENT_SET_TEMPO) {
    printf " %s bpm",AutoHarp::Clock::TempoFromMidiEvent($self);
  } else {
    foreach (@{$self}[2..$#$self]) {
      printf " %3s",$_;
    }
  }
  print "]\n";
}

"Our house. In the middle of our street";

