package AutoHarp::Instrument::Pad;

use strict;
use AutoHarp::Constants;
use AutoHarp::Fuzzy;
use base qw(AutoHarp::Instrument);

my $OCTAVE = 'octave';

sub choosePatch {
  my $self = shift;
  my $inst = shift;
  return $self->SUPER::choosePatch($inst || 'synth pad');
}

sub playDecision {
  my $self    = shift;
  my $segment = shift;

  my $was     = $self->isPlaying();
  
  if ($segment->isRepeat() || $segment->wasBuildUp) {
    return mostOfTheTime
  } elsif ($was) {
    if ($segment->wasComeDown()) {
      return epicallySeldom;
    } elsif ($segment->isChange()) {
      return often;
    } 
    return 1;
  }
  
  return rarely;
}

sub play {
  my $self    = shift;
  my $segment = shift;

  $self->{$OCTAVE} ||= 4; #3 sounded like ass pickOne(3,4);
  
  if ($segment->musicBox->hasProgression()) {
    my $padding = AutoHarp::Events::Performance->new();
    $padding->time($segment->time());
    foreach my $c (@{$segment->musicBox->progression->chords()}) {
      #for now we want pads to be subtle, so we'll keep them in soft velocities
      #that may, like, change, later.  
      my $padC = $c->clone();
      $padC->octave($self->{$OCTAVE});
      $padC->velocity(softVelocity());
      $padding->add($padC);
    }
    return $padding;
  }
}

"Your mind bespoke";
