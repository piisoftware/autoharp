package AutoHarp::Composer::PerformanceSegment;

use strict;
use base qw(AutoHarp::Composer::CompositionElement);
use Carp;

use AutoHarp::MusicBox::Base;
use AutoHarp::Constants;
use AutoHarp::Notation;

my $PLAYER        = 'player';
my $PERFORMANCES  = 'performances';
my $PLAYED        = 'played';
my $SEGMENT_IDX   = 'segmentIdx';
my $TRANSITION_OUT = 'transitionOut';

sub fromParent {
  my $class = shift;
  my $parent = shift;
  return bless $parent->clone(), $class;
}

sub dump {
  my $self = shift;
  $self->SUPER::dump();
  if ($self->hasPerformances()) {
    while (my ($uid, $data) = each %{$self->{$PERFORMANCES}}) {
      if ($data->{$PLAYED}) {
	print "$uid => \n";
	$data->{$PLAYED}->dump();
      }
    }
  }
}

sub time {
  my $self = shift;
  my $time = shift;
  if (length($time)) {
    $self->SUPER::time($time);
    if ($self->hasPerformances()) {
      while (my ($uid, $data) = each %{$self->{$PERFORMANCES}}) {
	$data->{$PLAYED}->time($time) if ($data->{$PLAYED});
      }
    }
  }
  return $self->{$ATTR_TIME} || 0;
}

sub isIntro {
  return (shift)->songElement =~ /$SONG_ELEMENT_INTRO/i;
}

sub isVerse {
  return (shift)->songElement =~ /$SONG_ELEMENT_VERSE/i;
}

sub isChorus {
  return (shift)->songElement =~ /$SONG_ELEMENT_CHORUS/i;
}

sub nextSongElement {
  return $_[0]->scalarAccessor('nextElt',$_[1]);
}

#for noting that we "came down" 
#(brought the song down a notch, as it were)
#at the start of this segment
sub wasComeDown {
  return $_[0]->transitionIn() eq $ATTR_DOWN_TRANSITION;
}

#for noting the opposite
sub wasBuildUp {
  return $_[0]->transitionIn() eq $ATTR_UP_TRANSITION;
}

sub transitionOutIsDown {
  return $_[0]->transitionOut() eq $ATTR_DOWN_TRANSITION;
}

sub transitionOutIsUp {
  return $_[0]->transitionOut() eq $ATTR_UP_TRANSITION;
}

#for noting if this segment is part of a repeat  
sub isRepeat {
  my $self = shift;
  return $self->scalarAccessor('isRepeat',@_);
}

#a string that describes the above
sub description {
  my $self = shift;
  my $str = ($self->isChange()) ? 'Change ' :
    ($self->isRepeat()) ? 'Repeat ' : '';
  if ($self->wasComeDown()) {
    $str .= 'Come Down';
  } elsif ($self->wasBuildUp) {
    $str .= 'Build Up';
  } else {
    $str .= 'Straight';
  }
  return $str;
}

#inferred by the fact that the next segment matches this segment
#and we are a second half.
sub nextHalfSegmentIsRepeat {
  my $self = shift;
  return ($self->songElement eq $self->nextSongElement() && 
	  $self->isSecondHalf());
}

sub addSegmentUid {
  confess "YOU'VE DONE SOMETHING WRONG";
}

sub getNextSegmentUid {
  confess "YOU'VE DONE SOMETHING REALLY WRONG";
}

#we're the start of a new thing (e.g. a chorus after a verse
sub isChange {
  my $self = shift;
  return (!$self->isRepeat() && $self->isFirstHalf());
}

#for noting what number verse/chorus this is
sub elementIndex {
  my $self = shift;
  return $self->scalarAccessor('elementIndex',@_);
}

#if we split a composition element into pieces, what idx is this one?
sub segmentIndex {
  my $self = shift;
  return $self->scalarAccessor($SEGMENT_IDX,@_);
}

#legacy--for noting if this segment is half of a chorus/verse/whatever
sub isFirstHalf {
  return ($_[0]->segmentIndex() == 0);
}

#legacy, see above
sub isSecondHalf {
  return ($_[0]->segmentIndex > 0);
}

sub transitionOut {
  return $_[0]->scalarAccessor($TRANSITION_OUT,$_[1],$ATTR_STRAIGHT_TRANSITION);
}

sub transitionIn {
  return $_[0]->scalarAccessor('transitionIn',$_[1],$ATTR_STRAIGHT_TRANSITION);
}

sub soundingTime {
  my $self = shift;
  if ($self->hasPerformances()) {
    my $st;
    foreach my $s (@{$self->scores()}) {
      if (!length($st) || $s->soundingTime < $st) {
	$st = $s->soundingTime();
      }
    }
    return $st;
  } elsif ($self->hasMusicBox()) {
    return $self->musicBox()->soundingTime();
  }
  return $self->time;
}

sub scores {
  my $self = shift;
  return [
	  grep {ref($_)} 
	  map {$self->{$PERFORMANCES}{$_}{$PLAYED}} 
	  keys %{$self->{$PERFORMANCES}}
	 ];
}

sub playerPerformances {
  my $self = shift;
  return [map 
	  {
	    {$ATTR_INSTRUMENT => $self->{$PERFORMANCES}{$_}{$PLAYER},
	       $ATTR_MELODY => $self->{$PERFORMANCES}{$_}{$PLAYED}
	     }
	  } 
	  grep {$self->{$PERFORMANCES}{$_}{$PLAYED}}
	  keys %{$self->{$PERFORMANCES}}
	 ];
}

sub player {
  my $self = shift;
  my $id = shift;
  return (exists $self->{$PERFORMANCES}{$id}) ?
    $self->{$PERFORMANCES}{$id}{$PLAYER} : undef
}

sub playerPerformance {
  my $self = shift;
  my $id   = shift;
  return (exists $self->{$PERFORMANCES}{$id}) ?
    $self->{$PERFORMANCES}{$id}{$PLAYED} : undef;
}

sub hasPlayers {
  return scalar keys %{$_[0]->{$PERFORMANCES}};
}

sub players {
  my $self = shift;
  return [keys %{$self->{$PERFORMANCES}}];
}

sub nukePerformer {
  my $self = shift;
  my $pId  = shift;
  delete $self->{$PERFORMANCES}{$pId};
}

sub clearPerformanceForPlayer {
  my $self = shift;
  my $pId  = shift;
  if (exists $self->{$PERFORMANCES}{$pId}) {
    delete $self->{$PERFORMANCES}{$pId}{$PLAYED};
  }
}

#note that we expect a performance from a particular instrument
sub addPerformer {
  my $self = shift;
  my $inst = shift;
  $self->{$PERFORMANCES}{$inst->uid} ||= {$PLAYER => $inst};
}

sub hasPerformances {
  my $self = shift;
  if ($self->{$PERFORMANCES} && scalar keys %{$self->{$PERFORMANCES}}) {
    foreach my $id (keys %{$self->{$PERFORMANCES}}) {
      return 1 if ($self->{$PERFORMANCES}{$id}{$PLAYED});
    }
  }
  return;
}

sub hasPerformanceForPlayer {
  my $self = shift;
  my $id   = shift;
  return (exists $self->{$PERFORMANCES}{$id} && 
	  exists $self->{$PERFORMANCES}{$id}{$PLAYED} &&
	  ref($self->{$PERFORMANCES}{$id}{$PLAYED}));
}

sub addPerformance {
  my $self   = shift;
  my $player = shift;
  my $play   = shift;

  if (!$play->duration) {
    confess "Attempted to add 0-duration performance";
  }

  my $storedPlay = $play->clone();
  $storedPlay->time($self->time);
  $self->{$PERFORMANCES}{$player->uid} = {$PLAYER => $player,
					  $PLAYED => $storedPlay};
}
      
"Just hear me out--I'm not over you yet";
