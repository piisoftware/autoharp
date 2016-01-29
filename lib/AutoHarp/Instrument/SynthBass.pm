package AutoHarp::Instrument::SynthBass;

use AutoHarp::Events::Melody;
use AutoHarp::Constants;
use AutoHarp::Fuzzy;
use strict;

use base qw(AutoHarp::Instrument::FreestyleBass);



sub choosePatch {
  return $_[0]->SUPER::choosePatch('Synth Bass');
}

sub play {
  my $self = shift;
  my $segment = shift;
  if (!$segment->musicBox->hasProgression()) {
    return $self->SUPER::play($segment);
  }
  my $bassLine = AutoHarp::Events::Melody->new();
  $bassLine->time($segment->time);
  foreach my $c (@{$segment->musicBox->progression->chords}) {
    my $clock = $segment->musicBox->clockAt($c->time);
    $bassLine->add($self->eighthNoteBass($c,$clock));
  }

  if (!$self->isPlaying() && often) {
    $self->createLeadIn($segment, $bassLine);
  }
  $self->transition($segment,$bassLine);
  return $bassLine;
}

"Loosen your ties";

