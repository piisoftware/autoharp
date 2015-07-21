package AutoHarp::Events::Guide;

use base qw(AutoHarp::Events);
use strict;
use AutoHarp::Constants;
use AutoHarp::Scale;
use AutoHarp::Clock;
use AutoHarp::Model::Genre;
use AutoHarp::Event::Text;
use Carp;

my $DEFAULT_BARS = 8;

sub new {
  my $class  = shift;
  my $events = shift;
  my $self   = [];
  my $start;
  my $end = 0;
  if (ref($events) eq 'ARRAY') {
    foreach my $e (@$events) {
      if (ref($e) eq 'ARRAY') {
	eval {
	  $e = AutoHarp::Event->new($e);
	};
	if ($@) {
	  next;
	}
      }
      if (ref($e) && $e->isa('AutoHarp::Event')) {
	if ($e->time < $start || !length($start)) {
	  $start = $e->time;
	}
	if ($e->time > $end) {
	  $end = $e->time;
	}
	if ($e->isMusicGuide() && !$e->isMarker()) {
	  push(@$self, $e);
	}
      }
    }
  }
  bless $self,$class;
  $self->sort();
  unshift(@$self,AutoHarp::Event->zeroEvent($start));
  $self->setEnd($end);
  return $self;
}

sub fromAttributes {
  my $class = shift;
  my $args  = {@_};
  my $self  = $class->new();
  $self->setClock($args->{$ATTR_CLOCK}) if ($args->{$ATTR_CLOCK});
  $self->setScale($args->{$ATTR_SCALE}) if ($args->{$ATTR_SCALE});
  $self->tempo($args->{$ATTR_TEMPO}) if ($args->{$ATTR_TEMPO});
  $self->meter($args->{$ATTR_METER}) if ($args->{$ATTR_METER});
  $self->measures($args->{$ATTR_BARS} || $DEFAULT_BARS);
  $self->time($args->{$ATTR_TIME}) if ($args->{$ATTR_TIME});
  $self->genre($args->{$ATTR_GENRE}) if ($args->{$ATTR_GENRE});
  return $self;
}

sub fromString {
  my $class = shift;
  my $str   = shift;
  my $self  = $class->fromDataStructure([$str]);
  $self->measures($DEFAULT_BARS);
  return $self;
}

sub fromDataStructure {
  my $class  = shift;
  my $struct = shift;
  my $self   = $class->new();
  my $timeSet;
  foreach my $header (@$struct) {
    my $data = AutoHarp::Notation::ParseHeader($header);
    my $clock = AutoHarp::Clock->new(%$data);
    my $scale = AutoHarp::Scale->new(%$data);
    my $genre = ($data->{$ATTR_GENRE}) ? 
      AutoHarp::Model::Genre->loadByName($data->{$ATTR_GENRE}) : undef;
    if (!$timeSet) {
      $self->time($clock->time);
      $timeSet = 1;
    }
    $self->setClock($clock,$clock->time);
    $self->setScale($scale,$clock->time);
    $self->genre($genre) if ($genre);
    if ($clock->time > $self->reach()) {
      $self->setEnd($clock->time);
    }
  }
  return $self;
}

#one header to rule them all 
sub toString {
  my $self = shift;
  return AutoHarp::Notation::CreateHeader($ATTR_CLOCK => $self->clock(),
					  $ATTR_SCALE => $self->scale(),
					  $ATTR_GENRE => $self->genre(),
					 );
}

#guide's data structure is an array of Notation Headers
sub toDataStructure {
  my $self = shift;
  my $t    = $self->time;
  my $ds   = [];
  my $lastClock;
  foreach my $e (@$self) {
    if ($e->time != $t) {
      $lastClock = 
	push(@$ds,
	     AutoHarp::Notation::CreateHeader($ATTR_CLOCK => $self->clockAt($t),
					      $ATTR_SCALE => $self->scaleAt($t),
					      $ATTR_START_TIME => $t,
					      $ATTR_GENRE => $self->genre(),
					     ));
      $t = $e->time;
    }
  }
  #whatever t's value is now is the end marker event
  push(@$ds, AutoHarp::Notation::CreateHeader($ATTR_START_TIME => $t,
					      $ATTR_CLOCK => $self->clockAtEnd(),
					      $ATTR_SCALE => $self->scaleAtEnd(),
					      $ATTR_GENRE => $self->genre()
					     ));
  return $ds;
}

#returns the list as MIDI events without zero and end events
sub export {
  my $self = shift;
  my $ret = [];
  foreach my $e (@$self) {
    next if ($e->isZeroEvent() || $e->isEndEvent());
    push(@$ret, [@$e]);
  }
  return MIDI::Score::score_r_to_events_r($ret);
}

sub isEmpty {
  my $self = shift;
  return ($self->[0]->time == $self->[-1]->time && !scalar grep {$_->isClock || $_->isTempo} @$self);
}

sub eventCanBeAdded {
  my $self = shift;
  my $a    = shift;
  if ($a->isZeroEvent()) {
    return;
  } elsif ($a->isEndEvent() && $a->time > $self->reach()) {
    #if we add an end event that's later than our current end, 
    #go ahead and move our existing end event in lieu of adding this one
    $self->setEnd($a->time);
    return;
  } elsif ($a->isScale()) {
    #don't add a scale event if we're already in that scale
    my $scale = $self->scaleAt($a->time);
    return if ($scale->key eq AutoHarp::Scale::KeyFromMidiEvent($a));
  } elsif ($a->isClock()) {
    #don't add a tempo or meter event 
    #if we're already in that time or tempo
    my $clock = $self->clockAt($a->time);
    return if
      ($a->type eq $EVENT_SET_TEMPO && 
       $clock->tempo == AutoHarp::Clock::TempoFromMidiEvent($a));
    return if
      ($a->type eq $EVENT_TIME_SIGNATURE && 
       $clock->meter eq AutoHarp::Clock::MeterFromMidiEvent($a));
  }
  return 1;
}

sub soundingTime {
  return $_[0]->time();
}

sub setEnd {
  my $self   = shift;
  my $newEnd = shift;
  if ($newEnd > $self->time) {
    #round to nearest measure
    my $clock = $self->clockAt($newEnd);
    $newEnd = $clock->nearestMeasure($newEnd);
    if ($newEnd == $self->time) {
      #round up at least one measure
      $newEnd += $clock->measureTime();
    }
    $self->SUPER::truncateToTime($newEnd);
    $self->_moveEndEvent($newEnd);
  }
}

sub _moveEndEvent {
  my $self = shift;
  my $time = shift;
  $self->remove(AutoHarp::Event->eventEnd());
  push(@$self,AutoHarp::Event->eventEnd($time));
}

sub truncate {
  my $self = shift;
  return $self->setDuration(@_);
}

sub setDuration {
  my $self = shift;
  my $newDuration = shift;
  if ($newDuration > 0) {
    $self->setEnd($self->time + $newDuration);
  }
}

sub subList {
  my $self = shift;
  my $from = shift;
  my $to   = shift;
  $to      = $self->reach if (!$to || $to > $self->reach);
  my $fClock = $self->clockAt($from);
  my $fScale = $self->scaleAt($from);
  my $tClock = $self->clockAt($to);
  $from = $fClock->nearestMeasure($from);
  $to   = $tClock->nearestMeasure($to);
  my $sub = $self->SUPER::subList($from,$to);  
  #make sure you at least set the starting clock and scale events, in case
  #those events are not contained in this subList
  $fClock->time($from);
  $sub->setClock($fClock,$from);
  $sub->setScale($fScale,$from);
  $sub->genre($self->genre);
  $sub->setEnd($to);
  return $sub;
}

sub add {
  my $self = shift;
  my $oldReach = $self->reach();
  $self->SUPER::add(@_);
  if ($self->reach() != $oldReach) {
    $self->setEnd($self->reach());
  } else {
    $self->_moveEndEvent($oldReach);
  }
}

sub repeat {
  my $self = shift;
  my $d    = $self->duration;
  my $newR = $self->reach + $d;
  $self->SUPER::repeat($d);
  $self->setEnd($newR);
}

sub scaleAndClockEvents {
  my $self = shift;
  return [grep {$_->isScaleOrClock} @$self];
}

#returns an array of start times per the internal clock of this guide
sub eachMeasure {
  my $self = shift;
  my $t = $self->time();
  my $m = [];
  while ($t < $self->reach()) {
    push(@$m,$t);
    $t += $self->clockAt($t)->measureTime();
  }
  return $m;
}

#how many measures this guide comprises, according to its own clock(s)
sub measures {
  my $self = shift;
  my $arg  = shift;
  if (length($arg)) {
    return $self->setMeasures($arg);
  }
  return scalar @{$self->eachMeasure()};
}

sub bars {
  my $self = shift;
  return $self->measures(@_);
}

sub setMeasures {
  my $self         = shift;
  my $newMeasures  = int(shift);
  my $currMeasures = $self->eachMeasure();
  my $mCount       = scalar @$currMeasures;
  if ($newMeasures < 0) {
    return;
  } elsif ($newMeasures < $mCount) {
    my $truncateTime = $currMeasures->[$newMeasures];
    $self->truncate($truncateTime);
  } else {
    my $addMeasures = $newMeasures - $mCount;
    my $clock       = $self->clockAtEnd();
    my $newEnd      = $self->reach() + ($clock->measureTime * $addMeasures);
    $self->setEnd($newEnd);
  }
  return $newMeasures;
}

#get/set tempo in this guide 
#can be done separately from setting the clock object
sub tempo {
  my $self = shift;
  my $arg  = shift;
  if (length($arg)) {
    my $c = $self->clock();
    $c->tempo($arg);
    $self->removeType($EVENT_SET_TEMPO);
    $self->setClock($c);
  }
  return $self->clock()->tempo;
}

#get/set meter in this blah blah blah etc blah
sub meter {
  my $self = shift;
  my $arg  = shift;
  if ($arg) {
    my $c = $self->clock();
    $c->meter($arg);
    for(my $i = 0; $i < scalar @$self; $i++) {
      if ($self->[$i]->isMeter()) {
	splice(@$self,$i,1);
	$i--;
      }
    }
    $self->setClock($c);
  }
  return $self->clock()->meter();
}

#get/set genre. Can only be set this way, we don't currently
#support multiple genres in a guide
sub genre {
  my $self  = shift;
  my $genre = shift;
  my @gs = (grep {$_->isGenre()} @$self);
  if ($genre) {
    my $genreEvent = AutoHarp::Event::Text->new("$ATTR_GENRE: " . $genre->name,
						$self->time
					       );
    #remove will remove all other genre events
    foreach my $g (@gs) {
      $self->remove($g);
    }
    #and then we add the new one
    $self->add($genreEvent);
    return $genre;
  } 
  if ($gs[0]) {
    return AutoHarp::Model::Genre->loadByName(($gs[0]->text() =~ /$ATTR_GENRE: (.+)/));
  }
  return;
}

#add clock midi events at the mentioned time
sub setClock {
  my $self  = shift;
  my $clock = shift;
  my $when  = shift;
  my $time  = $self->time;

  if (!$clock) {
    return;
  }

  $when = $time if (!length($when));
  if ($when >= $time) {
    my $cClock = $self->clockAt($when);
    if (!$clock->equals($cClock)) {
      #we'll round to the next measure, 
      #cause you, like, can't change the meter 
      #in the middle of a measure
      $when = $cClock->roundToNextMeasure($when);
      if ($clock->tempo != $cClock->tempo) {
	$self->removeType($EVENT_SET_TEMPO,$when);
	$self->add($clock->tempo2MidiEvent($when));
      } 
      if ($clock->meter ne $cClock->meter) {
	$self->removeType($EVENT_TIME_SIGNATURE,$when);
	$self->add($clock->meter2MidiEvent($when));
      }
      if ($clock->swingPct != $cClock->swingPct || 
	  $clock->swingNote ne $cClock->swingNote) {
	my $re = $cClock->swing2MidiEvent($when);
	$self->removeAtTime($re);
	$self->add($clock->swing2MidiEvent($when));
      }
    } 
  } 
}

sub setScale {
  my $self = shift;
  my $scale = shift;
  my $when = shift;
  my $time = $self->time;
  $when = $time if (!length($when));
  if ($when >= $time) {
    my $cScale = $self->scaleAt($when);
    if (!$scale->equals($cScale)) {
      $self->removeType($EVENT_KEY_SIGNATURE,$when);
      $self->add($scale->key2MidiEvent($when));
    }
  }
}

#getters for the above
sub scale {
  my $self = shift;
  my $t    = $self->time();
  return $self->scaleAt($t);
}

#an a-o-a of all scale changes in this guide
sub scales {
  my $self   = shift;
  my $zero   = $self->time;
  my $scales = [[$zero,$self->scale()]];
  foreach my $s (grep {$_->isScale() && $_->time > $zero} @$self) {
    push(@$scales, [$s->time, AutoHarp::Scale->fromMidiEvent($s)]);
  }
  return $scales;
}
  
sub clock {
  my $self = shift;
  my $t    = $self->time();
  return $self->clockAt($t);
}

sub scaleAtEnd {
  my $self = shift;
  my $r = $self->reach();
  return $self->scaleAt($r);
}

sub clockAtEnd {
  my $self = shift;
  my $r = $self->reach();
  return $self->clockAt($r);
}

#returns what the scale is at this time
sub scaleAt {
  my $self = shift;
  my $time = shift;
  my $keyEvent;
  if ($time >= $self->time) {
    foreach my $e (grep {$_->type eq $EVENT_KEY_SIGNATURE} @$self) {
      if ($e->time <= $time) {
	$keyEvent = $e;
      } else {
	last;
      }
    }
  }
  return AutoHarp::Scale->fromMidiEvent($keyEvent);
}

#returns what the clock (tempo/meter/swing) are at this time
sub clockAt {
  my $self = shift;
  my $time = shift;
  my $tempoEvent;
  my $swingEvent;
  my $clockTime = $self->time;
  my $meterEvent = AutoHarp::Clock->new()->meter2MidiEvent($clockTime);
  if ($time >= $clockTime) {
    foreach my $e (@$self) {
      if ($e->time <= $time) {
	if ($e->isTempo()) {
	  $tempoEvent = $e;
	} elsif ($e->isMeter()) {
	  $meterEvent = $e;
	} elsif ($e->isSwing()) {
	  $swingEvent = $e;
	}
      } else {
	last;
      }
    }
  }
  return AutoHarp::Clock->fromClockEvents($meterEvent,
					  $tempoEvent,
					  $swingEvent
					 );
}

#clears all of the above out 
sub clearScaleAndClock {
  my $self      = shift;
  for (my $i = 0; $i < scalar @$self; $i++) {
    if ($self->[$i]->isScaleOrClock()) {
      splice(@$self,$i,1);
      $i--;
    }
  }
}

sub clearScales {
  my $self = shift;
  for (my $i = 0; $i < scalar @$self; $i++) {
    if ($self->[$i]->isScale()) {
      splice(@$self,$i,1);
      $i--;
    }
  }
}

sub hasKeyChange {
  my $self   = shift;
  my $t      = $self->time();
  return scalar grep {$_->isScale() && $_->time > $t} @$self;
}

sub hasTimeChange {
  my $self  = shift;
  my $t     = $self->time();
  return scalar grep {$_->isClock() && $_->time > $t} @$self;
}


sub setSwingFromMelody {
  my $self  = shift;
  my $track = shift;
  #let the initial clock gauge the swing from this melody
  my $clock = $self->clock();
  my $s = $clock->detectSwing($track);
  return $self->swing($s);
}

sub addSwing {
  my $self = shift;
  if ($self->clock->hasSwing()) {
    return $self->clock->addSwing(shift);
  }
}

#return a simple click track for this guide
sub metronome {
  my $self = shift;
  my $score = [];
  my $time = $self->time();
  for (1..$self->measures()) {
    my $clock = $self->clockAt($time);
    my $lBPM     = $clock->beatsPerMeasure();
    foreach my $b (1..$lBPM) {
      my $note = ($b == $lBPM) ? $MIDI::percussion2notenum{'Open Hi-Hat'} :
	$MIDI::percussion2notenum{'Closed Hi-Hat'};
      my $hat = AutoHarp::Event::Note->new($note,$time,120,$time);
      $hat->channel($PERCUSSION_CHANNEL);
      push(@$score, $hat);
      $time += $clock->beatTime();
    }
  }
  return $score; 
}

sub metronomeTrack {
  my $self = shift;
  my $events = MIDI::Score::score_r_to_events_r($self->metronome);
  return MIDI::Track->new({ 'events' => $events });
}

"I have seen the animals and cried";
