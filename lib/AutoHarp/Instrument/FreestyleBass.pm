package AutoHarp::Instrument::FreestyleBass;
use AutoHarp::Fuzzy;
use strict;

use base qw(AutoHarp::Instrument::Bass);

#I FOLLOW NOTHING! NOTHING!
sub getFollowRequest {
  return;
}

sub playDecision {
  my $self = shift;
  my $segment = shift;

  my $was = $self->isPlaying();
  if ($was) {
    return unlessPigsFly;
  }
  return ($segment->isIntro()) ? sometimes : almostAlways;
}

#asking my parent to play without follow music results in free-stylin' it.
sub play {
  my $self = shift;
  my $segment = shift;
  return $self->SUPER::play($segment);
}

"Loosen your ties";

