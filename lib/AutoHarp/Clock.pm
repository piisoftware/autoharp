package AutoHarp::Clock;

use strict;
use AutoHarp::Constants;
use Data::Dumper;
use Carp;
use base qw(AutoHarp::Class);
#handle meter and tempo in magic alex

my $TEMPO_TO_BPM_MOD  = 60000000;
my $IS_DEFAULT        = 'isDefaultClock';
my $ACCENTS           = 'accentBeats';
my $MAX_DEVIATION     = 1; 
my $INVALID           = "like, std dev too far off";

#Static Method
sub ValidateMeter {
  return _validMeter(shift);
}

sub MeterFromMidiEvent {
  my $event = shift;
  if (ref($event) && $event->isMeter()) {
    my ($type, $time, $num, $exp, @o) = (@$event);
    return "$num/" . (2 ** $exp);
  }
  return;
}

sub TempoFromMidiEvent {
  my $event = shift;
  if (ref($event) && $event->isTempo()) {
    return int($TEMPO_TO_BPM_MOD / $event->[2]);
  }
  return;
}

sub new {
  my $class = shift;
  my $args  = {@_};
  my $sig   = _validMeter($args->{$ATTR_METER});
  my $tempo = $args->{$ATTR_TEMPO};
  my $isDefault = (!$sig && !$tempo);

  $sig   ||= $DEFAULT_MIDI_METER;
  $tempo ||= $DEFAULT_MIDI_TEMPO;
  bless {$ATTR_METER      => $sig,
	 $ATTR_TEMPO      => $tempo,
	 $IS_DEFAULT      => $isDefault,
	 $ATTR_START_TIME => $args->{$ATTR_START_TIME} || 0,
	 $ACCENTS         => {4 => 1} #no feckin' idea
	}, $class;
}

sub fromClockEvents {
  my $class      = shift;
  my $sigEvent   = shift;
  my $tempoEvent = shift;
  my $sig   = MeterFromMidiEvent($sigEvent);
  my $tempo = TempoFromMidiEvent($tempoEvent);
  return $class->new($ATTR_METER      => $sig,
		     $ATTR_TEMPO      => $tempo,
		     $ATTR_START_TIME => ($sigEvent) ? $sigEvent->[1] : 0,
		     $IS_DEFAULT      => (!$sigEvent && !$tempoEvent)
		    );
}

sub time {
  return $_[0]->scalarAccessor($ATTR_START_TIME,$_[1],0);
}

sub equals {
  my $self       = shift;
  my $otherClock = shift;
  if ($otherClock) {
    return ($self->tempo == $otherClock->tempo && 
	    $self->meter eq $otherClock->meter &&
	    $self->isDefault == $otherClock->isDefault);
  }
  return;
}

sub _validMeter {
  my $sig = shift;
  $sig =~ s/\s+//g;
  my ($n,$d) = ($sig =~ m|(\d+)/(\d+)|);
  if ($n > 0 && __isPowerOfTwo($d)) {
    return "$n/$d";
  }
  return;
}

sub isDefault {
  return (shift)->{$IS_DEFAULT};
}

sub meter {
  my $self = shift;
  my $arg  = shift;
  $arg = _validMeter($arg) if ($arg);
  if ($arg) {
    $self->{$ATTR_METER} = $arg;
    delete $self->{$IS_DEFAULT};
  }
  return $self->{$ATTR_METER};
}

sub meter2MidiEvent {
  my $self   = shift;
  my $when   = shift;
  my $sig    = $self->meter;
  my ($num,$denom) = split("/",$sig);
  my $pow  = 0;
  while ((2 ** $pow) < $denom) {
    $pow++;
  }
  if ((2 ** $pow) != $denom) {
    confess "$sig appears to be an invalid meter";
  }
  $when = $self->time if (!length($when));
  return AutoHarp::Event->new([$EVENT_TIME_SIGNATURE,$when,$num,$pow,$num * 4,8]);
}

sub tempo {
  my $self = shift;
  my $arg  = shift; 
  if ($arg > 0) {
    $self->{$ATTR_TEMPO} = $arg;
    delete $self->{$IS_DEFAULT};
  }
  return $self->{$ATTR_TEMPO};
}

sub tempo2MidiEvent {
  my $self  = shift;
  my $when  = shift;
  $when = $self->time if (!length($when));
  return AutoHarp::Event->new([$EVENT_SET_TEMPO, $when, int($TEMPO_TO_BPM_MOD / $self->tempo)]);
}

sub toString {
  my $self = shift;
  return $self->meter . ", " . $self->tempo . " bpm";
}

sub beatsPerMeasure {
  my $self = shift;
  return ($self->meter =~ m|(\d+)/|)[0];
}
 
sub noteOfTheBeat { #4 = quarter, 8 = eighth, etc.
  return ((shift)->meter =~ m|\d+/(\d+)|)[0];
}

sub beatTime {
  return $TICKS_PER_BEAT;
}

sub measure {
  my $self = shift;
  my $time = shift;
  return int($time / $self->measureTime);
}

#beat is one-based, and this will give you the whole-number
sub beat {
  my $self = shift;
  my $time = shift;
  return 1 + int(($time % $self->measureTime) / $self->beatTime);
}

#how far (in ticks) into the beat you are 
sub beatFraction {
  my $self  = shift;
  my $time  = shift;
  my $mTime = int(($time - $self->time) % $self->measureTime());
  return $mTime % $self->beatTime;
}

#how far (in ticks) to the next beat
sub toNextBeat {
  my $self = shift;
  my $ticks = shift;
  return $self->beatTime - $self->beatFraction($ticks);
}

sub isOnTheBeat {
  my $self = shift;
  my $time = shift;
  return !(($time - $self->time) % $self->beatTime());
}

sub setAccentBeat {
  my $self = shift;
  my $beat = shift;
  $self->{$ACCENTS}{$beat} = 1;
}

sub clearAccentBeats {
  $_[0]->{$ACCENTS} = {};
}

sub isAccentBeat {
  my $self   = shift;
  my $time   = shift;
  my $arg    = shift;
  my $beatNo = 1 + 
    (($time - $self->time) % $self->measureTime) / $self->beatTime();
  return ($self->{$ACCENTS}) ? $self->{$ACCENTS}{$beatNo} : 0;
}

sub nearestBeat {
  my $self     = shift;
  my $time     = shift;
  my $toNext   = $self->toNextBeat($time);
  my $fromLast = $self->beatFraction($time);
  return ($toNext < $fromLast) ? $time + $toNext : $time - $fromLast;
}

#what no. beat is this for a note of given duration?
#e.g. at the half beat, the subbeat of a sixteenth note is 3
sub subBeat {
  my $self = shift;
  my $time = shift;
  my $duration = shift;
  if ($duration > $self->beatTime()) {
    #no sub-beat for you
    return 0;
  }
  if (!$duration) {
    confess "passed 0-length duration to sub beat calculator. Why did you do that?";
  }

  my $fromLast = $self->beatFraction($time);
  if (int($fromLast / $duration) == $fromLast / $duration) {
    return $fromLast / $duration + 1;
  }
  return 0;
} 

sub measureTime {
  my $self = shift;
  return $self->beatTime * $self->beatsPerMeasure;
}

sub ticksToNextMeasure {
  my $self  = shift;
  my $ticks = shift;
  my $t     = (($ticks - $self->time) % $self->measureTime);
  return ($t) ? $self->measureTime - $t : $t;
}

sub ticksFromLastMeasure {
  my $self = shift;
  my $ticks = shift;
  return ($ticks - $self->time) % $self->measureTime();
}

sub roundToNextMeasure {
  my $self     = shift;
  my $duration = shift;
  #this always rounds up...so, you know, be warned
  return $duration + $self->ticksToNextMeasure($duration);
}

sub nearestMeasure {
  my $self = shift;
  my $ticks = shift;
  if ($ticks > 0) {
    my $toPrev = $self->ticksFromLastMeasure($ticks);
    my $toNext = $self->ticksToNextMeasure($ticks);
    if ($toNext <= $toPrev) {
      return $ticks + $toNext;
    }
    return $ticks - $toPrev;
  }
  return 0;
}

sub ticks2measures {
  my $self  = shift;
  my $ticks = $self->nearestMeasure(shift);
  return $ticks - $self->measureTime();
}

sub ticks2seconds {
  my $self = shift;
  my $ticks = shift;
  my $beats = $ticks / $self->beatTime();
  return ($beats * 60) / $self->tempo;
}

#translate simple durations (e.g. 4 = quarter note) into MIDI ticks
sub basicDuration {
  my $self = shift;
  my $no   = shift;
  return ($no > 0) ? (4 * $self->quarter() / $no) : 0;
}

#dotted notes have half of themselves again, 
#which means if you divide them by three, they 
#should be an even number of minimum tick notes
sub isDotted {
  my $self = shift;
  my $dur  = shift;
  my $beat = $NOTE_MINIMUM_TICKS;

  while ($beat < $self->measureTime()) {
    if ($dur / 3 == $beat) {
      return 1;
    }
    $beat *= 2;
  }
  return;
}

#triplets should be a third of a valid beat
sub isTriplet {
  my $self = shift;
  my $dur  = shift;
  my $beat = $NOTE_MINIMUM_TICKS;
  
  while ($beat < $self->measureTime()) {
    if ($dur * 3 == $beat) {
      return 1;
    }
    $beat *= 2;
  }
  return;
}

sub __effectiveBeatLength {
  my $e = shift;
  if ($e->isPercussion) {
    return $DRUM_RESOLUTION;
  }
  my $d     = $e->duration();
  my $over  = $d % $NOTE_MINIMUM_TICKS;
  my $under = $d - 
    (int($e->duration / $NOTE_MINIMUM_TICKS) * $NOTE_MINIMUM_TICKS);
  if ($over < $under && $d > $NOTE_MINIMUM_TICKS) {
    return $d - $over;
  } 
  return $d + $under;
}

sub __findMean {
  my $set      = shift;
  my $devLimit = shift;
  #get a mean and std-dev
  #if too much std-dev, we won't consider this set
  my $mean;
  my $variance;
  grep {$mean += $_} @$set;
  $mean = int($mean / scalar @$set);
  grep {$variance += (($_ - $mean) ** 2)} @$set;
  $variance = int($variance / scalar @$set);
  my $stdDev = int(sqrt($variance));
  if ($stdDev <= $devLimit) {
    #yay!
    return $mean;
  }
  return $INVALID;
}

sub __isPowerOfTwo {
  my $no = shift;
  while ($no > 1) {
    return if ($no / 2 != $no >> 1);
    $no /= 2;
  }
  return 1;
}

"I tried to write a song for you, but you know how it goes";
