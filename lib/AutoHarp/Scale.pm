package AutoHarp::Scale;

use Carp;
use Data::Dumper;
use MIDI;
use strict;
use AutoHarp::Constants;
use AutoHarp::Event::Chord;
use AutoHarp::Event::Note;

use base qw(AutoHarp::Class);

my $MINOR                    = 'minor';
my $MAJOR                    = 'major';
my $IS_DEFAULT               = 'isDefaultScale';
my $LIKED_CHORD_INTERVALS    = [2,4,6,7,9];
my $ROOT_PITCH               = 'rootPitch';
my $MODE                     = 'mode';
my $MODES                    = [$MAJOR,
				'dorian',
				'phrygian', 
				'lydian',
				'mixolydian',
				$MINOR,
				'locrian'];

my $MINOR_INTERVALS          = {melodic   => [2,1,2,2,2,2,1],
				harmonic  => [2,1,2,2,1,3,1],
				hungarian => [2,1,3,1,1,3,1],
				jazz      => [2,1,2,2,2,2,1], #same as melodic, for the purposes of this program
			       };
my $PENTATONIC_INTERVALS = [2,2,3,2,3];
my $MAJOR_KEY_ACCIDENTAL_MAP = {'G Flat'  => -6,
				'D Flat'  => -5,
				'A Flat'  => -4,
				'E Flat'  => -3,
				'B Flat'  => -2,
				'F'       => -1,
				'C'       => 0,
				'G'       => 1,
				'D'       => 2,
				'A'       => 3,
				'E'       => 4,
				'B'       => 5,
				'F Sharp' => 6
			       };

#this is pitch mod-12.
my $pitch2Accidentals = {0 => 0,
			 1 => -5, #D Flat/C Sharp,
			 2 => 2,  #D
			 3 => -3, #E Flat
			 4 => 4,  #E
			 5 => -1, #F
			 6 => 6, #F Sharp
			 7 => 1, #G 
			 8 => -4, #A Flat
			 9 => 3, #A
			 10 => -2, #B Flat,
			 11 => 5, #B 
			};

#Static Methods
sub ValidateKey {
  my $ret = __parseKey(@_);
  if ($ret) {
    return $ret->{$ATTR_KEY};
  }
  return;
}

sub KeyFromMidiEvent {
  my $event    = shift;
  my $key;
  if (ref($event) && $event->[0] eq $EVENT_KEY_SIGNATURE) {
    my ($type, $time, $accidentals, $isMinor) = @$event;
    $key = KeyFromAccidentals($accidentals, $isMinor);
  }
  return $key;
}

sub KeyFromAccidentals {
  my $accidentals = shift;
  my $isMinor     = shift;
  my $pitch;
  my $a2Note = {reverse %$pitch2Accidentals};
  $pitch = $a2Note->{$accidentals};
  if ($isMinor) {
    $pitch += 9;
  }
  my $key = __pitch2ScaleName($pitch,($accidentals < 0));
  $key .= " Minor" if ($isMinor);
  return $key;
}

#End the static methods!

#constructors
sub new {
  my $class = shift;
  my $args  = {@_};
  my $self;
  my $key;

  if (scalar @_ == 1) {
    $key = $_[0];
  } else {
    $key = $args->{$ATTR_KEY};
  }

  if ($key) {
    $self = __parseKey($key);
  }
  if (!$self) {
    my $note = AutoHarp::Event::Note->new($DEFAULT_ROOT_PITCH);
    $self = {$IS_DEFAULT => 1,
	     $ROOT_PITCH => $DEFAULT_ROOT_PITCH,
	     $ATTR_INTERVALS => $MAJOR_SCALE_INTERVALS,
	     $MODE => $MODES->[0],
	     $ATTR_START_TIME => 0
	    };
  }
  bless $self,$class;
  return $self;
}

sub fromMidiEvent {
  my $class = shift;
  my $event = shift;
  my $key   = AutoHarp::Scale::KeyFromMidiEvent($event);
  my $self  = $class->new($key);
  if ($event) {
    $self->time($event->time);
  }
  return $self;
}

#returns a scale object for this chord (e.g. C Major returns C Major scale)
sub fromChord {
  my $class = shift;
  my $chord = shift;
  my $root  = $chord->root();
  my $name  = $chord->toString();
  my $type  = $chord->chordType();
  my $key;
  if ($chord->isMajor() || $chord->isMinor) {
    $key = $root->letter . " $type";
  } elsif ($chord->isDiminished()) {
    #this is the vii chord, so up the root pitch half a step 
    #and give the associated major scale
    my $nRoot = AutoHarp::Event::Note->new($root->pitch + 1);
    $key = $nRoot->letter;
  } else {
    #lacking better info, you get this
    my $t = ($name =~ /minor3/) ? $MINOR : "";
    $key = $root->letter . " $t";
  } 
  return $class->new($ATTR_KEY => $key);
}

#returns the I,IV,and V scales for a chord
#e.g. returns C Major, C Lydian, and C Mixolydian for C Major chord,
#A Minor, A Dorian, A Phyrgian for A Minor
sub allScalesForChord {
  my $class = shift;
  my $first = $class->fromChord(@_);
  my $second = $first->clone();
  my $third  = $first->clone();
  $second->mode(3); #set the mode up 3 steps (a fourth)
  $third->mode(4); #set the mode up 4 steps (a fifth)
  return [$first,$second,$third];
}

sub equivalentMajorScale {
  my $self = shift;
  if ($self->isMajor()) {
    return $self->clone();
  }
  my $mode = $self->mode();
  my $mIdx = (grep {$MODES->[$_] eq $mode} 0..$#$MODES)[0];
  my $newRoot = $self->steps($self->rootPitch(),-1 * $mIdx);
  my $note = $MIDI::number2note{$newRoot};
  $note =~ s/s/\#/;
  return ref($self)->new($note);
}

#end constructors
sub time {
  return $_[0]->scalarAccessor($ATTR_START_TIME,$_[1],0);
}

sub equals {
  my $self = shift;
  my $otherScale = shift;
  my $equals = ($otherScale && $self->isDefault == $otherScale->isDefault);
  if ($equals) {
    eval {
      my $ourMidi   = $self->key2MidiEvent(0);
      my $theirMidi = $otherScale->key2MidiEvent(0);
      for (my $i = 1; $i < scalar @$ourMidi; $i++) {
	if ($ourMidi->[$i] != $theirMidi->[$i]) {
	  $equals = 0;
	  last;
	}
      }
    };
    if ($@) {
      $equals = 0;
    }
  } 
  return $equals;
}

sub isDefault {
  return (shift)->{$IS_DEFAULT};
}

#turns things like "A Flat Major" into stuff we understand
sub __parseKey {
  my $key  = shift;
  my $obj  = {};
  my $fuck = ($key ne 'C');
  $key =~ s/^\s+//;
  $key =~ s/\#/Sharp/g;
  my ($note,$text) = ($key =~ /^(\w)(.*)/);
  $text =~ s/^\s+//;
  my $ind = 4;
  my $rootName = uc($note) . $ind;
  my $computedKey;
  if ($MIDI::note2number{$rootName}) {
    $computedKey = uc($note);
    $obj->{$ROOT_PITCH} = $MIDI::note2number{$rootName};
    my $accidental;
    if ($text =~ s/\s*(flat|sharp)\s*//i) {
      $accidental = lc($1);
    }
    if ($accidental eq 'flat') {
      $obj->{$ROOT_PITCH}--;
      $computedKey .= " Flat";
    } elsif ($accidental eq 'sharp') {
      $computedKey .= " Sharp";
      $obj->{$ROOT_PITCH}++;
    }
    $obj->{$MODE} = $MODES->[0];
    my $found = 0;
    if ($text =~ /(\w+)\s+minor/i) {
      my $type = lc($1);
      if (exists $MINOR_INTERVALS->{$type}) {
	$obj->{$MODE} = $MINOR;
	$obj->{$ATTR_INTERVALS} = $MINOR_INTERVALS->{$type};
	$computedKey .= (" " . upCase($type) . " Minor");
	$found++;
      }
    } 
    if (!$found) {
      foreach my $mode (@$MODES) {
	if ($text =~ /^$mode/i) {
	  $obj->{$ATTR_INTERVALS} = __getScaleIntervals($mode);
	  $computedKey .= (" " . upCase($mode));
	  $obj->{$MODE} = $mode;
	  last;
	}
      }
    }
    $obj->{$ATTR_INTERVALS} ||= $MAJOR_SCALE_INTERVALS;
    $obj->{$ATTR_KEY} = $computedKey;
  }
  return (scalar keys %$obj) ? $obj : undef;
}

sub rootPitch {
  return (shift)->{$ROOT_PITCH};
}

sub mode {
  my $self    = shift;
  my $newMode = lc(shift);
  if ($newMode) {
    my $steps;
    if ($newMode =~ /(\d+)/) {
      $steps = $1;
      my $ints = $self->{$ATTR_INTERVALS};
      for (1..$steps) {
	push(@$ints,shift(@$ints));
      }
      my $old = 0;
      foreach (@$MODES) {
	if (lc($self->{$MODE}) eq lc($_)) {
	  last;
	}
	$old++;
      }
      $self->{$MODE} = $MODES->[($old + $steps) % scalar @$MODES];
    } elsif (scalar grep {$newMode eq lc($_)} @$MODES) {
      $self->{$ATTR_INTERVALS} = __getScaleIntervals($newMode);
      $self->{$MODE} = $newMode;
    }
    delete $self->{$ATTR_KEY};
  }
  $self->{$MODE}     ||= $MODES->[0];
  return $self->{$MODE};
}

sub intervals {
  return (shift)->{$ATTR_INTERVALS};
}

sub key {
  my $self = shift;
  my $new  = shift;
  if ($new) {
    my $attrs = __parseKey($new);
    if ($attrs) {
      while (my ($k, $v) = each %$attrs) {
	$self->{$k} = $v;
      }
      delete $self->{$IS_DEFAULT};
    }
  }
  $self->{$ATTR_KEY} ||= __pitch2ScaleName($self->{$ROOT_PITCH}) . " " . upCase($self->{$MODE});
  return $self->{$ATTR_KEY};
}

sub accidentals {
  return $pitch2Accidentals->{$_[0]->{$ROOT_PITCH} % 12};
}

sub key2MidiEvent {
  my $self        = shift;
  my $when        = shift || '0';
  my $pitch       = $self->rootPitch();
  #start assuming we're major and then correcting as necessary 
  foreach my $m (@$MODES) {
    if ($self->{$MODE} eq $m) {
      last;
    } 
    $pitch = $self->steps($pitch,-1);
  }
  my $lookup = $pitch % $self->scaleSpan();
  my $accidentals = $pitch2Accidentals->{$lookup};
  return AutoHarp::Event->new([$EVENT_KEY_SIGNATURE,$when,$accidentals,($self->isMinor) ? 1 : 0]);
}

sub isMinor {
  my $self = shift;
  return ($self->{$MODE} eq $MINOR);
}

sub isMajor {
  my $self = shift;
  return ($self->{$MODE} eq $MAJOR);
}

#send this key to its relative minor
sub toRelativeMinor {
  my $self = shift;
  if ($self->isMajor()) {
    return $self->mode($MINOR);
  }
  return;
}

#determine whether accidentals are considered sharps or flats
sub isFlatScale {
  my $key = (shift)->key;
  return ($key =~ /flat$/i || $key =~ /^f/);
}

sub isSharpScale {
  my $key = (shift)->key;
  return ($key =~ /sharp$/i || $key =~ /^(a|b|c|d|e|g)/i);
}

sub scaleNotes {
  my $self      = shift;
  my $octave    = shift;
  my $intervals = shift || $self->intervals();
  my $offset    = $octave * $self->scaleSpan;
  my $scale     = [$self->rootPitch + $offset];
  for(my $i = 0; $i < scalar @$intervals; $i++) {
    $scale->[$i+1] = $scale->[$i] + $intervals->[$i];
  }
  return $scale;
}

#return a new scale the specified number of half-steps from this one
sub newScaleFromHalfSteps {
  my $self = shift;
  my $steps = shift;
  if ($steps != 0) {
    my $newNote = AutoHarp::Event::Note->new($self->{$ROOT_PITCH} + $steps);
    my $letter  = $newNote->letter();
    if ($self->isFlatScale() && $letter =~ /\#/) {
      #accomodate flat scales
      $newNote->pitch($newNote->pitch + 1);
      $letter = $newNote->letter() . " Flat";
    }
    return AutoHarp::Scale->new($newNote->letter() . " " . $self->mode());
  }
  return $self->clone();
}

#transpose this list of notes/chords into a new scale
sub transposeToScale {
  my $self     = shift;
  my $events   = shift;
  my $newScale = shift;
  foreach my $e (grep {$_->isNote()} @$events) {
    $self->transposeEventToScale($e,$newScale);
  }
}

#shift this set of notes up within this scale
sub transpose {
  my $self     = shift;
  my $melody   = shift;
  my $steps    = shift;
  foreach my $n (@$melody) {
    $self->transposeEvent($n,$steps);
  }
}

sub transposeEvent {
  my $self   = shift;
  my $e      = shift;
  my $steps  = shift;
  if ($e->isChord()) {
    my @p;
    foreach my $p (@{$e->pitches}) {
      push(@p, $self->steps($p,$steps));
      $e->subtractPitch($p);
    }
    foreach my $p (@p) {
      $e->addPitch($p);
    }
  } elsif ($e->isNote()) {
    $e->pitch($self->steps($e->pitch,$steps));
  }
}

sub transposeEventToScale {
  my $self  = shift;
  my $e     = shift;
  my $scale = shift;
  my $forceNatural = shift;

  my $newPitch = sub {
    my $pitch     = shift;
    my $fromScale = shift;
    my $toScale   = shift;
    my $idx       = $fromScale->scaleIndex($pitch);
    if ($forceNatural) {
      $idx = int($idx);
      if ($toScale->isFlatScale()) {
	$idx++;
	$idx %= scalar @{$toScale->intervals};
      }
    }
    return $toScale->scaleContainingPitch($pitch)->[$idx];
  };
  if ($e->isNote()) {
    $e->pitch($newPitch->($e->pitch,$self,$scale));
  } elsif ($e->isChord()) {
    my $new = [];
    my @pitches = @{$e->pitches};
    foreach my $p (@pitches) {
      push(@$new,$newPitch->($p,$self,$scale));
      $e->subtractPitch($p);
    }
    foreach my $n (@$new) {
      $e->addPitch($n);
    }
  }
}

sub transposeByOctave {
  my $self = shift;
  my $note = shift;
  my $octaves = shift || 1;
  my $steps = $self->scaleSpan * $octaves;
  $note->pitch($note->pitch + $steps);
}

sub rootScale {
  return (shift)->scaleNotes();
}

sub noteIsRoot {
  return (shift)->noteIs(shift,0);
}

sub noteIsSecond {
  return (shift)->noteIs(shift,1);
}

sub noteIsThird {
  return (shift)->noteIs(shift,2);
}

sub noteIsFourth {
  return (shift)->noteIs(shift,3);
}

sub noteIsFifth {
  return (shift)->noteIs(shift,4);
}

sub noteIsSixth {
  return (shift)->noteIs(shift,5);
}

sub noteIsSeventh {
  return (shift)->noteIs(shift,2);
}

sub noteIs {
  my $self = shift;
  my $pitch = shift;
  my $noteIs = shift;
  return ($self->scaleIndex($pitch) == $noteIs);
}

#returns the note letter of note n of the scale
#e.g. returns "c" for 0 in the c-scale;
sub noteLetterByIndex {
  my $self = shift;
  my $idx  = shift;
  return AutoHarp::Event::Note->new($self->steps($self->rootPitch(),$idx))->letter();
}

sub rootLetter {
  return $_[0]->noteLetterByIndex();
}

#12 tone scale until otherwise notified
sub scaleSpan {
  return $ATTR_SCALE_SPAN;
}

#give me the pitch that's the number of steps in the scale from the one I gave you
sub steps {
  my $self      = shift;
  my $start     = shift || $self->rootPitch;
  my $steps     = shift;
  my $intervals = shift || $self->intervals;  
  my $pitch     = $start;

  if ($steps != 0) {

    #figure out where we are in this set of intervals
    my $idx = $self->scaleIndex($pitch,$intervals);
    my $sanity = 4;
    while ($idx != int($idx)) {
      if ($sanity-- == 0) {
	my @i = @{$intervals};
	confess "Too many times trying to find $steps steps from $start in @i";
      }
      #if we were on an accidental, we need to cheat up or down first
      #if we're going up, cheat down
      if ($steps < 0) {
	#if we're going down, cheat up
	$pitch++;
      } else {
	#if we're going up, cheat down
	$pitch--;
      }
      $idx = $self->scaleIndex($pitch,$intervals);
    }
    #walk up the specified number of steps


    my $halfStep = ($steps =~ /\.5/);
    if ($steps > 0) {
      for(1..int($steps)) {
	$pitch += $intervals->[$idx];
	$idx    = ($idx + 1) % (scalar @$intervals);
      }
      if ($halfStep) {
	$pitch++;
      }
    } else {
      for (1..abs($steps)) {
	$idx = ($idx == 0) ? $#$intervals : $idx - 1;
	$pitch -= $intervals->[$idx];
      }
      if ($halfStep) {
	$pitch--;
      }
    }
  }
  return $pitch;
}

#return notes in the five tone scale 
#Major: 0,2,4,7,9
#ANY GODDAMN THING ELSE: varies
sub pentatonicSteps {
  my $self  = shift;
  my $pitch = shift || $self->rootPitch();
  my $steps = shift;
  if (!$steps) {
    return $pitch;
  }
  if (!$self->isMajor()) {
    return $self->equivalentMajorScale()->pentatonicSteps($pitch,$steps);
  }
  return $self->steps($pitch,$steps,$PENTATONIC_INTERVALS);
}

sub isPentatonic {
  my $self  = shift;
  my $pitch = shift;
  my $idx   = ($self->isMajor()) ? 
    $self->scaleIndex($pitch,$PENTATONIC_INTERVALS) : 
      $self->equivalentMajorScale()->scaleIndex($pitch,$PENTATONIC_INTERVALS);
  return ($idx == int($idx));
}

sub scaleStepsBetween {
  my $self   = shift;
  my $first  = shift;
  my $second = shift;
  my $dir    = 1;
  if ($first > $second) {
    #if we're going down, swap them and multiply by -1 at the end
    #it just makes things easier
    ($first, $second) = ($second,$first);
    $dir = -1;
  }
  my $fIdx   = $self->scaleIndex($first);
  my $sIdx   = $self->scaleIndex($second);
  my $octaveDiff = int(($second - $first) / $self->scaleSpan());
  my $octaveSteps = scalar @{$self->intervals};
  
  if ($fIdx == $sIdx) {
    return $octaveDiff * $octaveSteps * $dir;
  }
  if ($fIdx > $sIdx) {
    #we crossed over an octave, so add one 
    $octaveDiff++;
  }
  return $dir * (($octaveDiff * $octaveSteps) + ($sIdx - $fIdx));
}

sub isAccidental {
  my $self  = shift;
  my $pitch = shift;
  if (ref($pitch)) {
    $pitch = $pitch->pitch;
  }
  return ($self->scaleIndex($pitch) =~ /\./);
}

sub isBlueNote {
  my $self = shift;
  my $pitch = shift;
  return ($self->normalizedScaleIndex($pitch) == 1.5);
}

sub isAltSeventh {
  my $self  = shift;
  my $pitch = shift;
  return ($self->normalizedScaleIndex($pitch) == 5.5);
}

sub nearestRoot {
  my $self  = shift;
  my $pitch = shift;
  my $dir   = shift || 1;
  my $root  = $self->scaleContainingPitch($pitch)->[0];
  return ($dir > 0) ? $root + $self->scaleSpan : $root;
}

sub nearestFifth {
  my $self  = shift;
  my $pitch = shift;
  my $dir   = shift || 1;
  my $fifth = $self->scaleContainingPitch($pitch)->[4];
  return ($dir > 0 && $fifth <= $pitch) ? $fifth + $self->scaleSpan() :
    ($dir < 0 && $fifth >= $pitch) ? $fifth - $self->scaleSpan() : 
      $fifth;
}

sub scaleContainingPitch {
  my $self  = shift;
  my $pitch = shift;
  my $intervals = shift || $self->intervals();
  #calculate the scale where the pitch is
  my $delta  = $pitch - $self->rootPitch;
  my $octave = ($delta < 0) ? int($delta / $self->scaleSpan) - 1 : int($delta/$self->scaleSpan);
  return $self->scaleNotes($octave,$intervals);
}

sub scaleIndex {
  my $self      = shift;
  my $pitch     = shift;
  my $intervals = shift || $self->intervals;
  if (!length($pitch)) {
    return 0;
  }
  my $scale = $self->scaleContainingPitch($pitch,$intervals);

  for(my $i = 0; $i <= scalar @$scale; $i++) {
    my $curr = $scale->[$i];
    if ($pitch == $curr) {
      return $i % scalar @$intervals;
    } elsif ($pitch < $curr) {
      #we passed it--this is an accidental. Backtrack
      my $prev = $scale->[$i - 1];
      my $diff = 1 - (($pitch - $prev) / ($curr - $prev));
      return $i - $diff;
    }
  }
  confess "Seriously, this should never happen. How did this happen? Pitch was $pitch, scale is @$scale";
}

#returns the index as if you were in a major scale
sub normalizedScaleIndex {
  my $self  = shift;
  my $idx   = $self->scaleIndex(@_);
  my $mode  = $self->mode();
  if ($mode) {
    my $norm = (grep {$MODES->[$_] eq $mode} 0..$#$MODES)[0];
    my $mod  = scalar @{$self->intervals};
    $idx += $norm;
    $idx -= $mod if ($idx >= $mod);
  }
  return $idx;
}

sub chordInterval {
  my $self     = shift;
  my $chord    = shift;
  my $interval = shift;
  if ($chord && scalar @$chord && $interval > 0) {
    return $self->steps($chord->rootPitch(),$interval - 1);
  }
  return;
}
#given a chord and a melody of notes, find an extra interval (a 2nd, 4th, 6th, 9th?)
#for the chord in that melody, if one exists
sub findChordInterval {
  my $self      = shift;
  my $chord     = shift;
  my $melody    = shift;
  my $pitches   = {};
  foreach my $n (grep {$_->isa('AutoHarp::Event::Note')} @$melody) {
    $pitches->{$n->pitch} += $n->duration();
  }
  if (!scalar @$chord || !scalar keys %$pitches) {
    #no chord interval for you
    return;
  }
  my $span = $self->scaleSpan();
  foreach my $p (sort {$pitches->{$a} <=> $pitches->{$b}} keys %$pitches) {
    foreach my $i (@$LIKED_CHORD_INTERVALS) {
      my $int = $self->chordInterval($chord,$i);
      if (($p % $span) == ($int % $span)) {
	#MATCH! 
	return $int;
      }
    }
  }
  return;
}

sub chordsForPitch {
  my $self = shift;
  my $pitch = shift || $self->rootPitch();
  my $chords = [];
  my $idx = $self->scaleIndex($pitch);
  if ($self->isAccidental($pitch)) {
    #get the chord where this is a 3rd and where it's a 7th
    #perhaps more some day, if I feel like it
    push(@$chords,$self->chordWithPitchAsInterval($pitch,2));
    push(@$chords,$self->chordWithPitchAsInterval($pitch,6));
  } else {
    push(@$chords,$self->triad($pitch));
    push(@$chords,$self->triadFromThird($pitch));
    push(@$chords,$self->triadFromFifth($pitch));

    #add seventh and ninth chords, as long as they're not freaky
    my $s = $self->chordWithPitchAsInterval($pitch, 6);
    my $n = $self->chordWithPitchAsInterval($pitch, 8);
    push(@$chords,$s) if ($s->isMajor || $s->isMinor);
    push(@$chords,$n) if ($n->isMajor || $n->isMinor);
  }
  return $chords;
}

sub triad {
  my $self  = shift;
  my $pitch = shift || $self->rootPitch();
  my $idx   = shift || 0;
  
  if ($self->isAccidental($pitch)) {
    return;
  }
  my $chord = AutoHarp::Event::Chord->new();
  $chord->addPitch($self->steps($pitch,$idx));
  $chord->addPitch($self->steps($pitch,$idx + 2));
  $chord->addPitch($self->steps($pitch,$idx + 4));
  return $chord;
}

sub dominantV {
  my $self     = shift;
  my $equiv    = $self->equivalentMajorScale();
  my $fifth    = $equiv->steps($equiv->rootPitch,-3);
  my $domSeven = $equiv->steps($equiv->rootPitch,3);
  my $triad    = $equiv->triad($fifth);
  $triad->addPitch($domSeven);
  return $triad;
}

#return the chord where the pitch is the asked interval
#e.g. returns C9 if you send us 62 (pitch of D) and 8 
sub chordWithPitchAsInterval {
  my $self     = shift;
  my $pitch    = shift;
  my $interval = shift;
  if (!$pitch) {
    confess "Need a pitch";
  }
  my $isAcc = $self->isAccidental($pitch);
  if ($isAcc) {
    my $normIdx = $self->normalizedScaleIndex($pitch);
    #maps our accidentals to 1 - 5 (just for ease of reference below)
    my $accidentalNo = ($normIdx < 2) ? $normIdx + .5 : $normIdx - .5;
    my $chord;
    if ($interval == 2) {
      #we can make this a third. It won't be in the scale, but whatever
      my $c = AutoHarp::Event::Chord->new();
      $c->addPitch($pitch);
      if ($accidentalNo == 1 || $accidentalNo == 3 || $accidentalNo == 4) {
	#A Major, D Major, E Major in a C scale
	$c->addPitch($self->steps($pitch,-3));
	$c->addPitch($self->steps($pitch,2));
      } elsif ($accidentalNo == 2 || $accidentalNo == 5) {
	#C Minor, G Minor in a C Scale
	$c->addPitch($self->steps($pitch,-2));
	$c->addPitch($self->steps($pitch,3));
      }
      return $c;
    } elsif ($interval == 6) {
      #7th (major (7 steps) or minor (6 steps))
      my $steps = ($accidentalNo == 1 ||
		   $accidentalNo == 3 ||
		   $accidentalNo == 4) ? -7 : -6;
      my $c = $self->triad($self->steps($pitch,$steps));
      $c->addPitch($pitch);
      return $c;
    }
    #other chords to be supported as we see fit 
  } else {
    if ($interval == 0 || $interval == 2 || $interval == 4) {
      return $self->triad($pitch,-1 * $interval);
    }
    my $c = $self->triad($self->steps($pitch,-1 * $interval));
    $c->addPitch($pitch);
    return $c;
  }
  return;
}

#triad where given pitch is the third
sub triadFromThird {
  my $self  = shift;
  my $pitch = shift || $self->rootPitch();
  return $self->triad($pitch, -2);
}

#where given thing is the fifth
sub triadFromFifth {
  my $self  = shift;
  my $pitch = shift || $self->rootPitch();
  return $self->triad($pitch,-4);
}

sub __getScaleIntervals {
  my $mode  = lc(shift); #major, minor, locrian, etc.
  my @steps = @$MAJOR_SCALE_INTERVALS;

  if ($mode) {
    my $idx = (grep {$MODES->[$_] eq $mode} 0..$#$MODES)[0];
    if ($idx > 0) {
      for (1..$idx) {
	push(@steps,shift(@steps));
      }
    }
  }
  return [@steps];
}

sub __pitch2ScaleName {
  my $pitch  = shift;
  my $isFlat = shift;
  my $l = AutoHarp::Event::Note->new($pitch)->letter();
  if ($l =~ s/\#/ Sharp/ && $isFlat) {
    #call this a flat instead of a sharp
    $l = AutoHarp::Event::Note->new($pitch + 1)->letter() . " Flat";
  }
  return $l;
}

sub __findKeyAlias {
  my $key = shift;
  if (!exists $MAJOR_KEY_ACCIDENTAL_MAP->{$key} && $key =~ /Sharp/) {
    #does the like-named flat key exist?
    my $letter = ($key =~ /^([A-G])/)[0];
    if ($letter eq 'G') {
      $letter = 'A';
    } else {
      $letter++;
    }
    $key = "$letter Flat";
  }
  return $key;
}

"De doo doo doo";
