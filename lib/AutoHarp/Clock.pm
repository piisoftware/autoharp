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
my $SWING_TYPES = {eighth => 2,
		   sixteenth => 4};

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

sub SwingFromMidiEvent {
  my $event = shift;
  if (ref($event) && $event->isSwing()) {
    my $data = ($event->text() =~ /$ATTR_SWING=(.+)/)[0];
    my ($pct,$note) = split(",",$data);
    return {$ATTR_SWING_NOTE => $note,
	    $ATTR_SWING_PCT => $pct};
  }
  return {};
}

sub new {
  my $class = shift;
  my $args  = {@_};
  my $sig   = _validMeter($args->{$ATTR_METER});
  my $tempo = $args->{$ATTR_TEMPO};
  my $swingNote = $args->{$ATTR_SWING_NOTE};
  my $swingPct  = $args->{$ATTR_SWING_PCT};
  my $isDefault = (!$sig && !$tempo && !$swingNote && !$swingPct);

  $sig   ||= $DEFAULT_MIDI_METER;
  $tempo ||= $DEFAULT_MIDI_TEMPO;
  bless {$ATTR_METER      => $sig,
	 $ATTR_TEMPO      => $tempo,
	 $IS_DEFAULT      => $isDefault,
	 $ATTR_START_TIME => $args->{$ATTR_START_TIME} || 0,
	 $ATTR_SWING_NOTE => ($SWING_TYPES->{$swingNote}) ? $swingNote : '',
	 $ATTR_SWING_PCT  => $swingPct || 0,
	 $ACCENTS         => {4 => 1} #no feckin' idea
	}, $class;
}

sub fromClockEvents {
  my $class      = shift;
  my $sigEvent   = shift;
  my $tempoEvent = shift;
  my $swingEvent = shift;
  my $sig   = MeterFromMidiEvent($sigEvent);
  my $tempo = TempoFromMidiEvent($tempoEvent);
  my $swing = SwingFromMidiEvent($swingEvent);
  return $class->new($ATTR_METER      => $sig,
		     $ATTR_TEMPO      => $tempo,
		     $ATTR_SWING_NOTE => $swing->{$ATTR_SWING_NOTE},
		     $ATTR_SWING_PCT  => $swing->{$ATTR_SWING_PCT} || '0',
		     $ATTR_START_TIME => ($sigEvent) ? $sigEvent->[1] : 0,
		     $IS_DEFAULT      => (!$sigEvent && !$tempoEvent && !$swingEvent),
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
	    $self->swingPct == $otherClock->swingPct &&
	    $self->swingNote eq $otherClock->swingNote() &&
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

sub swingNote {
  my $self = shift;
  my $arg  = shift;
  if ($arg && $SWING_TYPES->{$arg}) {
    $self->{$ATTR_SWING_NOTE} = $arg;
  }
  return $self->{$ATTR_SWING_NOTE} ||= 'sixteenth';
}

sub swingNoteDuration {
  my $self = shift;
  my $val  = $SWING_TYPES->{$self->{$ATTR_SWING_NOTE}};
  return ($val) ? $self->beatTime / $val : 0;
}

sub swingPct {
  $_[0]->scalarAccessor($ATTR_SWING_PCT, $_[1], 0);
}

sub hasSwing {
  my $self = shift;
  return int($self->swingNoteDuration() * ($self->swingPct() / 100)) != 0;
}

sub swing2MidiEvent {
  my $self = shift;
  my $when = shift;
  $when = $self->time if (!length($when));
  return AutoHarp::Event->new([$EVENT_TEXT, 
			       $when, 
			       "$ATTR_SWING=" 
			       . $self->{$ATTR_SWING_PCT} . "," 
			       . $self->{$ATTR_SWING_NOTE}
			      ]
			     );
}

sub addSwing {
  my $self   = shift;
  my $melody = shift;
  if (!$self->hasSwing()) {
   return;
  }
  my $swingNote  = $self->swingNoteDuration();
  my $swingTicks = int($swingNote * $self->swingPct() / 100);
  
  foreach my $n (grep {$_->isMusic()} @$melody) {
    my $effectiveTime = $n->time - $self->time;
    #what beat number this is, 0-based
    my $placeInBeat = $effectiveTime % $self->beatTime();
    my $beat        =  $placeInBeat / $swingNote;
    next if ($beat != int($beat)); #not right on the beat
    next if (!($beat % 2)); #not a swing beat
    $n->time($n->time + $swingTicks);
  }
  return 1;
}

#this doesn't work, per se.
sub detectSwing {
  my $self    = shift;
  my $melody  = shift;
  my $timed   = $melody->clone();
  #make sure we're square on zero before we start
  $timed->time(0);
  my $measures = int($melody->duration() / $self->measureTime()) || 1;
  #attempt to detect 8th note, then 16th note swing
  #look at even beats, compare them to off beats to see if swing is actually 
  #occurring...

  my $swingPct;
  my $swingNote;
  
  foreach my $swingType (keys %$SWING_TYPES) {
    my $division = $SWING_TYPES->{$swingType};
    #need at least, quarter as many notes of type as would appear, 
    #times number of measures.
    #e.g. four measures, looking for eighth note swing, 
    #there are four possible swing beats 
    #and four possible non-swing beats per measure, 
    #so ask for at least two of them, times number of measures
    my $swingNotesPerMeasure = ($division * $self->beatsPerMeasure()) / 2;
    my $sampleSizeNeeded     = int($measures * $swingNotesPerMeasure / 4) ||
      $swingNotesPerMeasure;
    my $testLen              = $self->beatTime / $division;
    
    my @swingData;
    my @notSwingData;
    foreach my $e (grep {$_->isMusic()} @$timed) {
      my $t = $e->time;
      my $effectiveLength = __effectiveBeatLength($e);
      #can we consider this as a data point at all?
      #it needs to be the length of the swing we're measuring 
      next if ($effectiveLength != $testLen);
      #it needs to fall nearer to one of our beats than 
      #a beat in between
      #(e.g. it has to be closer to the 8th note than the nearest 16th)
      my $distanceAft  = $t % $testLen;
      my $distanceFore = $testLen - $distanceAft;
      
      my $offset;
      if ($distanceFore < $distanceAft) {
	#we're cheating ahead of the beat
	$offset = -1 * $distanceFore;
      } else {
	#behind it
	$offset = $distanceAft;
      }
      
      #this the tick-time we should be on (will be 0 based) 
      my $platonicBeat = ($e->time - $offset) % $self->beatTime();

      #is the smaller distance closer to us than the beat in between? 
      my $closeHalf = ($offset < 0) ? $platonicBeat - ($testLen / 2) : 
	$platonicBeat + ($testLen / 2);
      my $halfOff   = abs($t - $closeHalf);
      if (abs($halfOff) < abs($offset)) {
	#nope? This note cannot help us
	next;
      }
      
      #figure out if this is on an odd or even swing beat
      #again, 0-based so swing beats are actually 1 & 3
      my $isSwing = ($platonicBeat / $testLen) % 2;
      if ($isSwing) {
	push(@swingData,$offset);
      } else {
	push(@notSwingData,$offset);
      }
    } 
    #to be valid swing, the swing beats need to be more swing-y
    #than the not-swing beats. Otherwise it's just push or pull, 
    #which is, like, not swing
    if (scalar @swingData < $sampleSizeNeeded ||
	scalar @notSwingData < $sampleSizeNeeded) {
	$swingType,
	  $sampleSizeNeeded,
	    scalar @swingData,
	      scalar @notSwingData;
      #not enough data
      next;
    }
    my $on  = __findMean(\@swingData,int($testLen / 10));
    my $off = __findMean(\@notSwingData, int($testLen / 10));
    if ($on eq $INVALID || $off eq $INVALID) {
      #either the swing or the not-swing has too much variance
      #It don't mean a thing, 'cuz it ain't got that swing.
      next;
      #Do you get it? 
      #Do you? 
      #
      #
      #DO YOU?????
    }
    #express swing as a pct of the length of the note being swung
    my $swing = int(100 * (($on - $off) / $testLen));
    #we lose some swing due to rounding errors when the answer is negative
    $swing-- if ($swing < 0);
    if (abs($swing) > abs($swingPct)) {
      #bigger swing wins
      $swingPct  = $swing;
      $swingNote = $swingType;
    }
  }
  if ($swingNote) {
    return {$ATTR_SWING_PCT => $swingPct, 
	    $ATTR_SWING_NOTE => $swingNote};
  }
  return {};
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
