package AutoHarp::Instrument::Bass;

use strict;
use AutoHarp::Event::Note;
use AutoHarp::Clock;
use AutoHarp::Scale;
use AutoHarp::Fuzzy;
use AutoHarp::MusicBox::Base;
use AutoHarp::Events::Melody;
use AutoHarp::Constants;
use AutoHarp::Generator;

use MIDI;
use Carp;

use base qw(AutoHarp::Instrument);
my $BASS_LINES = 'basslines';

#this bass follows the kick drum

sub choosePatch {
  my $self = shift;
  my $inst = shift;
  $self->SUPER::choosePatch($inst || 'bass');
}

sub reset {
  my $self = shift;
  delete $self->{$BASS_LINES};
}

sub playDecision {
  my $self    = shift;
  my $segment = shift;
  
  if ($self->isPlaying()) {
    if ($segment->isChange()) {
      return unlessPigsFly;
    }
    return 1;
  } elsif ($segment->isSecondHalf()) {
    #don't go longer than half a segment without playing
    return 1;
  }
  return sometimes;
}

sub play {
  my $self    = shift;
  my $segment = shift;
  my $fMusic  = shift;
  my $bassline = AutoHarp::Events::Melody->new();
  $bassline->time($segment->time);

  if (!$segment->music->hasProgression()) {
    #nothing to be done for you here
    return;
  }

  my $prog = $segment->music->progression();
  my @kicks;
  if ($fMusic) {
    #get the hits to follow. Ignore hits if they occur 
    #before the segment time (we'll do our own lead-ins, thanks)
    @kicks = grep {
      $_->time >= $segment->time &&
	$_->isKickDrum()
      } @{$fMusic->notes()};
    if (!scalar @kicks) {
      #hmm...no kicks. Try anything low
      @kicks = grep {
	$_->time >= $segment->time && 
	  $_->drum =~ /Low/} @{$fMusic->notes()};
    } else {
      #we did get kicks. Add where there are snares on accent beats
      foreach my $snare (grep {$_->time >= $segment->time && 
				 $_->isSnare()} @{$fMusic->notes()}) {
	my $clock = $segment->music->clockAt($snare->time);
	if ($clock->isAccentBeat($snare->time)) {
	  push(@kicks,$snare);
	}
      }
    }
  }
  if (scalar @kicks) {
    for (my $i = 0; $i < scalar @kicks; $i++) {
      if ($prog->chordAt($kicks[$i]->time)) {
	$bassline->add($self->kickNote($segment->music,
				       $kicks[$i],
				       ($i > 0) ? $kicks[$i-1] : undef,
				       ($i < $#kicks) ? $kicks[$i+1] : undef));
      }
    }
  } else {
    #nothin'
    #gotta freestyle it
    foreach my $chord (@{$prog->chords()}) {
      $bassline->add($self->freeStyleBass($segment,$chord));
    }
  }
  #this all sounds like ass, commenting out
  # if (!$self->isPlaying() && 
  #     !$segment->isIntro() &&
  #     often) {
  #   #we just started, throw on a lead-in
  #   my $leadIn = AutoHarp::Generator->new()->leadInForMusic
  #     (
  #      $segment->music,
  #      $bassline->notes()->[0]
  #     );	
  #   $self->bassifyMelody($leadIn);
  #   $bassline->add($leadIn);
  # }
  #$self->transition($segment,$bassline);
  return $bassline;
}

sub transition {
  my $self       = shift;
  my $segment    = shift;
  my $bassline   = shift;
  if ($segment->transitionOutIsUp() && 
      $segment->music->hasProgression() && 
      mostOfTheTime) {
    #clear the space a measure before the transition and put 8ths in there
    my $clock      = $segment->music()->clockAtEnd();
    my $buildEnd   = $segment->reach();
    my $buildStart = $buildEnd - $clock->measureTime();
    $bassline->truncateToTime($buildStart);
    my $subProg    = $segment->music->progression->subProgression($buildStart,$buildEnd);
    my $velInc     = 0; 
    foreach my $c (@{$subProg->chords}) {
      my $bass = $self->eighthNoteBass($c,$clock);
      foreach my $n (@{$bass->notes()}) {
	$velInc += pickOne(1,2,3);
	$n->velocity($n->velocity + $velInc);
      }
      $bassline->add($bass);
    }
  }
}

#translate a kick-drum into a bass note
sub kickNote {
  my $self  = shift;
  my $music = shift;
  my $kick  = shift;
  my $prev  = shift;
  my $next  = shift;

  my $chord     = $music->progression->chordAt($kick->time);
  my $bassPitch = $chord->bassPitch();

  my $bp        = $self->bassPitch($bassPitch);
  my $clock     = $music->clockAt($kick->time);
  my $nb        = ($next) ? $next->time - $kick->time :
    $clock->toNextBeat($kick->time);
  my $duration  = $clock->beatTime() / 2;

  if ($kick->isHard() && !$kick->isSnare()) {
    $duration *= 2;
  }
  if ($duration > $nb) {
    $duration = ($nb < $NOTE_MINIMUM_TICKS) ? $NOTE_MINIMUM_TICKS : $nb;
  }
  my $note  = $kick->clone();
  $note->pitch($bp);
  #remove the drum channel just for the sake of bookkeeping
  $note->channel(0);
  #fuzz the velocity a touch
  $note->digit2Velocity($note->velocity2Digit());
  $note->duration($duration);
  if ($prev && $prev->time >= $chord->time) {
    #this is not the first kick in this chord, so...
    my $wasRoot   = ($prev->pitch == $bp);
    my $scale     = $music->scaleAt($kick->time);
    my $nextChord = $music->progression->chordAt($kick->time + $nb);
      $prev->letter(),
	$prev->time,
	  $chord->toString(),
	    $chord->time(),
	      $chord->reach();
    #are we going somewhere new next beat? Can we find a note in between?
    if ($nextChord && !$nextChord->equals($chord)) {
      my $steps = 
	$scale->scaleStepsBetween($bassPitch, $nextChord->bassPitch());
      if (abs($steps) > 1) {
	#yes--split the diff
	my $walkingPitch = $scale->steps($bassPitch,int($steps/2));
	$note->pitch($self->bassPitch($walkingPitch));
      } 
    } elsif ($chord->rootPitch() != $bassPitch && asOftenAsNot) {
      #chord has another root! use it
      $note->pitch($self->bassPitch($chord->rootPitch()));
    } elsif ($wasRoot && sometimes) {
      $note->pitch($self->bassPitch($chord->fifth()->pitch));
    } elsif ($wasRoot && sometimes) {
      $note->pitch($self->bassPitch($scale->steps($bassPitch, pickOne(1,-1))));
    } 
  }
  return $note;
}

sub eighthNoteBass {
  my $self   = shift;
  my $chord  = shift;
  my $clock  = shift;

  my $line   = AutoHarp::Events::Melody->new();
  $line->time($chord->time);

  my $cE     = $clock->beatTime / 2;
  my $when   = $chord->time;
  my $eights = int($chord->duration / $cE);
  my $left   = $chord->duration % $cE;
  my $note   = AutoHarp::Event::Note->new();
  $note->pitch($self->bassPitch($chord->rootPitch()));
  $note->duration($cE);
  for (1..$eights) {
    $note->time($when);
    $note->velocity(($_ % 2) ? hardVelocity() : mediumVelocity());
    $line->add($note);
    $when += $cE;
  }
  if ($left) {
    $note->time($when);
    $note->duration($left);
    $note->velocity(hardVelocity());
    $line->add($note);
  }
  return $line;
}

sub freeStyleBass {
  my $self    = shift;
  my $segment = shift;
  my $chord   = shift;
  my $scale   = $segment->music->scaleAt($chord->time());
  my $progId  = $segment->musicTag();
  
  my $pitch  = $self->bassPitch($chord->rootPitch());
  my $bLine  = $self->{$BASS_LINES}{$progId}{$pitch};
  if (!$bLine) {
    if (scalar keys %{$self->{$BASS_LINES}{$progId}} && asOftenAsNot) {
      #sometimes just steal and transpose the line from another chord
      my $oPitch = pickOne(keys %{$self->{$BASS_LINES}{$progId}});
      $bLine     = $self->{$BASS_LINES}{$progId}{$oPitch}->clone();
      if ($chord->isScaleTriad($scale)) {
	my $steps = $scale->scaleStepsBetween($oPitch,$pitch);
	$scale->transpose($bLine, $steps);
      } else {
	$scale->transposeToScale($bLine, AutoHarp::Scale->fromChord($chord));
      }
    } else {
      my $gen = AutoHarp::Generator->new();
      my $sm = $segment->music()->subMusic($chord->time,$chord->reach());
      eval {
	$gen->melodize($sm);
      };
      if ($@) {
	$sm->dump();
	$sm->progression->dump();
	die "IT WAS FUCKING HERE: $@\n";
      }	
      my $newMel = $sm->melody();
      $self->bassifyMelody($newMel);
      $newMel->time(0);
      #make sure we hit the root hard at the first note
      my $clock  = AutoHarp::Clock->new();
      my $sDur   = (mostOfTheTime) ? $clock->beatTime() : $clock->beatTime() / 2;
      my $sNote  = AutoHarp::Event::Note->new($pitch,$sDur,hardVelocity());
      $sNote->time(0);
      
      $bLine = AutoHarp::Events::Melody->new();
      $bLine->add($sNote);
      $bLine->add($newMel->subMelody($sDur,$chord->duration));
    }
    $self->{$BASS_LINES}{$progId}{$pitch} = $bLine;
  }
  my $line = $bLine->clone;
  $line->time($chord->time);
  return $line;
}

sub bassifyMelody {
  my $self = shift;
  my $mel  = shift;
  foreach my $n (grep {$_->isNote()} @$mel) {
    $n->pitch($self->bassPitch($n->pitch));
  }
}

sub bassPitch {
  my $self  = shift;
  my $pitch = shift;
  my $low   = $MIDI::note2number{'C3'};
  my $span  = $ATTR_SCALE_SPAN;
  if ($pitch < $low) {
    $pitch += $span while ($pitch < $low);
    return $pitch;
  }
  while ($pitch - $span > $low) {
    $pitch -= $span;
  }
  return $pitch;
}

"Loosen your ties";

