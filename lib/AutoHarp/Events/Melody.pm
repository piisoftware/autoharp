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

sub toDataStructure {
  my $self     = shift;
  my $guide    = shift;
  return [map {AutoHarp::Notation::Melody2String($_,$guide)} values %{$self->split()}];
}

#split myself into melodies with no overlapping notes
sub split {
  my $self     = shift;
  my $melodies = {};
  foreach my $event (@{$self->notes()}) {
    my $idx = 0;
    my $m;
    while ($melodies->{$idx} && 
	   $melodies->{$idx}->reach() > $event->time()) { 
      $idx++;
    }
    if (!$melodies->{$idx}) {
      $melodies->{$idx} = AutoHarp::Events::Melody->new();
      $melodies->{$idx}->time($self->time());
    }
    $melodies->{$idx}->add($event);
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

sub toString {
  my $self  = shift;
  my $guide = shift;
  return AutoHarp::Notation::Melody2String($self,$guide);
}

"Some people just want to fill the world with silly love songs."
  
