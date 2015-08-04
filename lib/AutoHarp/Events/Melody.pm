package AutoHarp::Events::Melody;

use AutoHarp::Constants;
use AutoHarp::Fuzzy;
use AutoHarp::Event::Chord;
use AutoHarp::Event::Note;
use AutoHarp::Notation;

use MIDI;
use Carp;
use strict;
use base qw(AutoHarp::Events);

my $VOLUME_FADER      = 7;
my $PAN_KNOB          = 10;

sub new {
  my $class  = shift;
  my $self   = [
		grep {$_->isMusic || $_->isZeroEvent()} 
		@{$class->SUPER::new(@_)}
	       ];
  bless $self,$class;
  return $self;
}

sub fromScoreEvents {
  my $class     = shift;
  my $melody    = [
		   grep {$_->isMusic || $_->isZeroEvent()} 
		   @{$class->SUPER::fromScoreEvents(@_)}
		  ];
  bless $melody,$class;
  return $melody;
}

sub fromString {
  my $class     = shift;
  my $string    = shift;
  my $guide     = shift;
  if ($string =~ /^\d+$/) {
    #assume it's a loop
    my $es = AutoHarp::Model::Loop->load($string)->events();
    bless $es,$class;
    return $es;
  }
  return AutoHarp::Notation::String2Melody($string, $guide);
}

sub toString {
  confess "Melody cannot necessarily be deconstructed into a single string. Use toDataStructure to condense it into an array of strings";
}

sub toDataStructure {
  my $self     = shift;
  my $guide    = shift;
  return [map {AutoHarp::Notation::Melody2String($_,$guide)} @{$self->split()}];
}

#split myself into melodies with no overlapping notes
sub split {
  my $self     = shift;
  my $melodies = [];
  foreach my $event (@{$self->notes()}) {
    my $idx = 0;
    my $m;
    while ($melodies->[$idx] && 
	   $melodies->[$idx]->reach() > $event->time()) { 
      $idx++;
    }
    if (!$melodies->[$idx]) {
      $melodies->[$idx] = AutoHarp::Events::Melody->new();
      $melodies->[$idx]->time($self->time());
    }
    $melodies->[$idx]->add($event);
  }
  return $melodies;
}

sub eventCanBeAdded {
  my $self  = shift;
  my $event = shift;
  if ($event->isMusic()) {
    if ($event->isChord()) {
      confess "Attempted to add chord to melody. You can't DO that.";
    }
    return 1;
  } elsif ($event->isNameEvent()) {
    #Add name events only if we don't already have them
    return !(scalar grep {$_->type eq $event->type} @$self);
  } 
  return;
}

#clear out everything except the zero event 
sub clear {
  my $self = shift;
  for (my $i = 0; $i < scalar @$self; $i++) {
    if (!$self->[$i]->isZeroEvent()) {
      splice(@$self,$i,1);
      $i--;
    }
  }
}

#return only the notes of a melody
sub notes {
  my $self = shift;
  return [grep {$_->isNotes()} @$self];
}

sub startNote {
  my $self = shift;
  my $first = $self->notes->[0];
  if ($first) {
    return $first->toNote();
  }
  return;
}

sub hasNotes {
  my $self = shift;
  return scalar grep {$_->isNotes()} @$self;
}

sub notesAt {
  my $self = shift;
  my $time = shift;
  return [grep {$_->time <= $time && $_->reach > $time} @{$self->notes()}];
}

#time the music starts, perhaps before time zero 
#(e.g. if this melody has a lead-in)
sub soundingTime {
  my $self = shift;
  return ($self->hasNotes()) ? $self->startNote()->time : $self->time;
}

sub hasLeadIn {
  my $self = shift;
  return ($self->soundingTime < $self->time);
}

sub channel {
  my $self = shift;
  my $arg = shift;
  if (length($arg)) {
    $self->SUPER::channel($arg);
    return $arg;
  }
  return ($self->hasNotes()) ? $self->startNote()->channel() : 0;
}

sub setPatch {
  my $self = shift;
  my $patch = shift;
  if (length($patch)) {
    my $pEvent = 
      AutoHarp::Event->new([$EVENT_PATCH_CHANGE,$self->soundingTime,$self->channel,$patch]);
    $self->removeType($EVENT_PATCH_CHANGE);
    $self->add($pEvent);
  }
}

sub setVolume {
  my $self = shift;
  my $pct  = shift;
  if (length($pct)) {
    my $volEvent = 
      AutoHarp::Event->new([$EVENT_CONTROL_CHANGE, 
			     $self->soundingTime,
			     $self->channel,
			     $VOLUME_FADER,
			     int(($pct / 100) * 127)]);
    $self->remove($volEvent);
    $self->add($volEvent);
  }
}

sub setPan {
  my $self    = shift;
  my $pct     = shift;
  if (length($pct)) {
    my $pivot   = 63;
    my $panEvent = 
      AutoHarp::Event->new([$EVENT_CONTROL_CHANGE,
			     $self->soundingTime,
			     $self->channel,
			     $PAN_KNOB,
			     $pivot + int(($pct * $pivot) / 100)]);
    $self->remove($panEvent);
    $self->add($panEvent);
  } 
}

sub track {
  my $self    = shift;
  my $args    = shift;
  my $obj     = $self->clone();
  if (ref($args)) {
    $obj->channel($args->{$ATTR_CHANNEL});
    $obj->setPatch($args->{$ATTR_PATCH});
    $obj->setPan($args->{$ATTR_PAN});
    $obj->setVolume($args->{$ATTR_VOLUME});
    if ($args->{$ATTR_GUIDE}) {
      $args->{$ATTR_GUIDE}->addSwing($obj);
    }
  }
  return MIDI::Track->new({ 'events' => $obj->export});
}

sub subMelody {
  my $self     = shift;
  my $oStart   = shift;
  my $oEnd     = shift;
  my $noFrontSplits = shift;

  my $int     = $oEnd - $oStart;
  my $start   = (length($oStart)) ? $oStart : $self->time;
  my $end     = (length($oEnd)) ? $oEnd : $self->reach;
  my $mel     = ref($self)->new();
  $mel->time($start);
  if ($end > $start) {
    foreach my $n (@$self) {
      next if ($n->reach <= $start);
      next if ($n->time < $start && $noFrontSplits);
      next if ($n->isMarker());
      last if ($n->time >= $end);

      my $new = $n->clone;
      if ($new->time < $start) {
	my $nDur = $new->duration - ($start - $new->time);
	$new->time($start);
	$new->duration($nDur);
      } 
      if ($new->reach > $end) {
	my $nDur = $new->duration - ($new->reach - $end);
	$new->duration($nDur);
      }
      $mel->add($new);
    }
  }
  return $mel;
}

sub createLeadIn {
  my $self = shift;
  my $guide = shift;
  
  if ($self->reach == $guide->reach) {
    my $clock    = $guide->clock();
    my $maxLen   = $clock->measureTime() / 2;
    my $start    = $self->reach - $maxLen;
    my $leadIn   = $self->subMelody($start, $self->reach);
    my $lDur     = $leadIn->duration();
    $leadIn->time($guide->time - $lDur);
    $self->add($leadIn);
    return $lDur;
  }
  return;
}

#harmonize this melody, given a guide and the harmony you want
sub harmonize {
  my $self   = shift;
  my $guide  = shift;
  my $steps  = shift;
  my $harmony = AutoHarp::Events::Melody->new();
  $harmony->time($self->time);
  foreach my $note (@{$self->notes()}) {
    my $scale = $guide->scaleAt($note->time);
    my $s     = $note->clone();
    $scale->transposeEvent($s,$steps);
    $harmony->add($s);
  }
  return $harmony;
}

#double this melody
sub double {
  my $self   = shift;
  my $double = $self->clone();
  #shift pitch up or down by a couple of cents
  my $cents = pickOne(1,-1) * (int(rand(100)) + 1);
  $double->add([$EVENT_PITCH_WHEEL, $self->time, $self->channel, $cents]);
  foreach my $note (@{$double->notes()}) {
    my $jiggle = pickOne(1,-1) * (int(rand(5)) + 1);
    if (asOftenAsNot) {
      $note->time($note->time + $jiggle);
    }
    if (asOftenAsNot) {
      $note->duration($note->duration - $jiggle);
    }
  }
  $double->add([$EVENT_PITCH_WHEEL, $self->reach, $self->channel, 0]);
  return $double;
}

#reverse this melody
sub reverse {
  my $self  = shift;
  my $new = AutoHarp::Events::Melody->new();
  if ($self->hasNotes()) {
    my $reach = $self->notes()->[-1]->time();
    foreach my $e (reverse @$self) {
      my $c = $e->clone();
      $c->time($reach - $e->time);
      $new->add($c);
    }
    $new->time($self->time());
  }
  return $new;
}

sub popNote {
  my $self = shift;
  my $note;
  while (scalar @$self) {
    $note = pop(@$self);
    last if ($note->isNotes());
  }
  return $note;
}

sub id {
  my $self = shift;
  my $id = $self->SUPER::id();
  $id =~ s/EVENTS/MELODY/;
  return $id;
}

#gets the idx'th note
sub getNote {
  my $self = shift;
  my $idx  = shift;
  return (grep {$_->isNote()} @$self)[$idx];
}

#gets the last note, whatever it is
sub endNote {
  return $_[0]->getNote(-1);
}

sub toString {
  my $self  = shift;
  my $guide = shift;
  return AutoHarp::Notation::Melody2String($self,$guide);
}

"Some people just want to fill the world with silly love songs."
  
