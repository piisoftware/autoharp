package AutoHarp::Events::Progression;

use AutoHarp::Constants;
use AutoHarp::Notation;
use AutoHarp::Events::Melody;
use AutoHarp::Event::Chord;
use MIDI;
use Carp;
use strict;
use base qw(AutoHarp::Events::Melody);

use Data::Dumper;
#more than five notes in a chord probably sounds weird?
my $CHORD_MAX_NOTES  = 5;
my $MIN_CHORD_PCT    = .8;

#TODO: Fix/Expand/Make Awesome
sub fromScoreEvents {
  my $class     = shift;
  my $score     = shift || [];
  my $force     = shift;
  my $events    = MIDI::Score::score_r_to_events_r($score);

  my $prog      = [];
  my $chords    = {};
  my $openNotes = {};
  #go through the score to find the time of the first note
  my $time;
  foreach my $s (grep {$_->[0] eq $EVENT_NOTE} @$score) {
    if (!length($time) || $time > $s->[1]) {
      $time = $s->[1];
    }
  }
  my $isValidProgression = 1;
  my $idx = 0;
  foreach my $event (@$events) {
    my ($e,$eTime,$ch,$pitch,$vel) = @$event;
    $time += $eTime;
    if ($e eq $EVENT_NOTE_ON) {
      my $chord = _findChordForNote($chords,$pitch,$time);
      if (!$force && $chord && $chord->getNoteByPitch($pitch)) {
	#not a valid progression given the rules of this program
	$isValidProgression = 0;
	last;
      } elsif (!$chord) {
	if ($chords->{$time}) {
	  print Dumper $chords;
	  confess "Attempted to create a new chord starting at time $time, but there was one already";
	}
	$chord = AutoHarp::Event::Chord->new();
	$chords->{$time} = $chord;
      } 	
      my $newNote = AutoHarp::Event::Note->new($pitch);
      $newNote->velocity($vel);
      $newNote->time($time);
      $chord->addNote($newNote);
      if (!$force && scalar @$chord > $CHORD_MAX_NOTES) {
	_dump($events,$idx);
	$chord->dump;
	print "PROG: TOO MANY NOTES PER CHORD\n";
	#not a valid progression, per our rules
	$isValidProgression = 0;
	last;
      }
    } elsif ($e eq $EVENT_NOTE_OFF) {
      my $chord = _findChordForNote($chords,$pitch,$time);
      if (!$chord) {
	_dump($events,$idx);
	print Dumper $chords;
	confess "Encountered invalid a note off event before the corresponding note on in score when building progression";
      }
      my $note = $chord->getNoteByPitch($pitch);
      my $dur  = $time - $note->time;
      if ($dur <= 0) {
	_dump($events,$idx);
	confess "Encountered zero-length note_on to note_off when building progression";
      }
      $note->duration($dur);
    }
    $idx++;
  }
  if (!$isValidProgression) {
    return;
  } else {
    #check for badness 
    while (my ($t,$c) = each %$chords) {
      foreach my $n (@$c) {
	if ($n->time < $t || $n->duration == 0) {
	  _dump($events);
	  print Dumper $chords, $c, $n;
	  confess "Found bad note in chord construction at time $t";
	}
      }
    }
    if (!$force) {
      #$MIN_CHORD_PCT of these notes must have multiple notes or this isn't a valid progression
      my $mCt = scalar grep {scalar @{$chords->{$_}} > 1} keys %$chords;
      if ($mCt / (scalar keys %$chords) < $MIN_CHORD_PCT) {
	print "PROG: Chord count is $mCt, there are " . (scalar keys %$chords) . ", I find this invalid\n";
	return;
      }
    }
  }
  my $prog = [map {$chords->{$_}} sort {$a <=> $b} keys %$chords];
  bless $prog,$class;
  return $prog;
}

sub fromString {
  my $class = shift;
  my $str   = shift;
  my $guide = shift || AutoHarp::Events::Guide->new();
  return $class->fromDataStructure({$ATTR_PROGRESSION => $str},$guide);
}

sub fromDataStructure {
  my $class  = shift;
  my $ds     = shift;
  my $trueClass = $ds->{$AH_CLASS} || $class;
  my $self   = AutoHarp::Notation::String2Progression($ds->{$ATTR_PROGRESSION},@_);
  bless $self,$trueClass;
  return $self;
}

sub toString {
  my $self  = shift;
  my $guide = shift;
  return AutoHarp::Notation::Progression2String($self,$guide);
}

sub toDataStructure {
  my $self  = shift;
  return {
	  $AH_CLASS => ref($self), 
	  $ATTR_PROGRESSION => AutoHarp::Notation::Progression2String($self,@_)
	 };
}


sub _findChordForNote {
  my $chords  = shift;
  my $pitch   = shift;
  my $time    = shift;
  my $onEvent = shift;
  if ($onEvent && $chords->{$time}) {
    return $chords->{$time};
  }
  foreach my $k (sort {$a <=> $b} keys %$chords) {
    my $c = $chords->{$k};
    my $n = $c->getNoteByPitch($pitch);
    if ($n && $n->duration == 0 && $n->time < $time) {
      return $c;
    } elsif (abs($c->time - $time) < $NOTE_MINIMUM_TICKS) {
      return $c;
    }
  }
  return;
}

sub id {
  my $self = shift;
  my $id = $self->SUPER::id();
  $id =~ s/MELODY/PROGRESSION/;
  return $id;
}

sub eventCanBeAdded {
  my $self = shift;
  my $event = shift;
  if ($event->isMusic()) {
    if ($event->isNote()) {
      confess "Attempted to add note to progression. You can't DO that";
    } elsif ($event->isChord) {
      #make sure this event doesn't overlap with any existing chords
      my @olap = grep {$_->duration > 0 && 
			 $_->reach() > $event->time() && 
			   $_->time() < $event->reach()
			 } @$self;
      if (scalar @olap) {
	confess sprintf("Attempt to add chord at time %d (duration %d), overlapping existing chord from %d to %d",
			$event->time(),
			$event->reach(),
			$olap[0]->time(),
			$olap[0]->reach());
      }
    }
    return 1;
  }
  return $self->SUPER::eventCanBeAdded($event);
}

sub subProgression {
  my $self      = shift;
  return $self->subMelody(@_);
}

#go through each chord and add the name of it to the chord object
#useful when passing datagrams back via Ajax.
sub spell {
  my $self = shift;
  grep {$_->toString()} @{$self->chords()};
}

sub repeat {
  my $self = shift;
  my $rTime = shift;
  if ($rTime > $self->duration) {
    $self->truncate($rTime);
  }
  return $self->SUPER::repeat($rTime);
}

sub toMelody {
  my $prog = shift;
  my $events = [];
  foreach my $p (@$prog) {
    if ($p->isChord()) {
      push(@$events, @{$p->toNotes()});
    } else {
      push(@$events, $p->clone());
    }
  }
  return AutoHarp::Events::Melody->new($events);
}

sub chords {
  my $self = shift;
  return [grep {$_->isChord()} @$self];
}

sub chordAt {
  my $self = shift;
  my $time = shift;
  my $chords = $self->chords();
  if ($time <= $self->time()) {
    return $chords->[0];
  } elsif ($time >= $self->reach()) {
    return $chords->[-1];
  }

  #we sometimes lie to you about what chord you're in
  #if you're obviously on your way to a next chord, 
  #we'll give you that instead
  my $leeway = $NOTE_MINIMUM_TICKS / 2;
  my @possibles = grep {$time < $_->reach() && $time > ($_->time - $leeway)} @$chords;
  if (scalar @possibles > 1) {
    #yep... 
    return $possibles[1];
  }
  return $possibles[0];
}

sub chordsInInterval {
  my $self  = shift;
  my $start = shift;
  my $end   = shift;
  my $ret   = [];
  foreach (grep {$_->isChord()} @$self) {
    push(@$ret,$_->clone()) if ($_->time < $end && $_->reach() > $start);
  }
  return $ret;
}

sub replaceChord {
  my $self  = shift;
  my $chord = shift;
  my $idx   = shift;
  my $chords = $self->chords();
  if ($chords->[$idx]) {
    $chords->[$idx]->setPitches($chord->pitches);
  }
}

sub hasChords {
  return scalar grep {$_->isChord()} @{(shift)};
}

#does this chord progression repeat?
#if so, how many chords in the phrase?
sub phraseLength {
  my $self       = shift;
  my $allowSubst = shift;
  if ($self->hasChords()) {
    my $chords = $self->chords();
    my $patternLen = scalar @$chords;
    #start with two. A repeated chord is not a pattern
    
  CHORD_LOOP:
    for(my $i = 2; $i <= int($patternLen / 2); $i++) {
      my $one = $chords->[0];
      my $two = $chords->[$i];
      next if ($one->duration != $two->duration);
      if ($one->isAlike($two) || ($allowSubst && $one->isSubstitution($two))) {
	#if these chords match, see if the chords to this point match the
	#chords afterwards. If yes, we've found a pattern
	my $startPoint = 1;
	while ($startPoint < scalar @$chords) {
	  for (my $j = $startPoint; $j < $startPoint + $i; $j++) {
	    my $subOne = $chords->[$j];
	    my $subTwo = $chords->[$j + $i];
	    next if (!$subTwo);
	    next CHORD_LOOP if ($subOne->duration != $subTwo->duration);
	    if ($subOne->isAlike($subTwo) ||
		($allowSubst && $subOne->isSubstitution($subTwo))) {
	      #these two chords count as the same, we're still okay
	    } else {
	      #noooo
	      next CHORD_LOOP;
	    }
	  }
	  #still here? Up the ticker
	  $startPoint = $startPoint + $i;
	}
	#if we're here, we must have found a pattern
	$patternLen = $i;
	last;
      }
    }
    return $patternLen;
  }
  return 0;
}

"Love, love is a verb/Love is a doing word";
