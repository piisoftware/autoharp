package AutoHarp::Events::Performance;


use base qw(AutoHarp::Events::Melody);
use Carp;
use strict;
use Data::Dumper;

#a melody object that can hold either notes or chords
#used when constructing a score

sub add {
  my $self   = shift;
  my $things = shift;

  #expand chords into notes where appropriate
  if (ref($things) eq 'ARRAY' && !ref($things->[0])) {
    $things = AutoHarp::Event->new($things);
  }

  if (ref($things) eq 'ARRAY' || $things->isa('AutoHarp::Events::Progression')) {
    foreach my $t (@$things) {
      if (ref($t) !~ /AutoHarp/) {
	print Dumper $t;
	confess "WTF is this? " . ref($t);
      }
      
      if ($t->isa('AutoHarp::Event::Chord')) {
	foreach my $n (@{$t->toNotes()}) {
	  $self->SUPER::add($n);
	}
      } else {
	$self->SUPER::add($t);
      }
    }
    return 1;
  } elsif ($things->isa('AutoHarp::Event::Chord')) {
    foreach my $n (@{$things->toNotes()}) {
      $self->SUPER::add($n);
    }
    return 1;
  } 
  $self->SUPER::add($things);
}

sub eventCanBeAdded {
  my $self = shift;
  my $event = shift;
  if ($event->isMusic()) {
    return 1;
  }
  return $self->SUPER::eventCanBeAdded($event);
}

"Joyful, bound in its division.";
