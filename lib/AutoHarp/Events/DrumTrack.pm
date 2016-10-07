package AutoHarp::Events::DrumTrack;

use base qw(AutoHarp::Events::Melody);
use AutoHarp::Notation;
use AutoHarp::Constants;
use strict;
use Carp;
use JSON;

#a melody object which holds drum tracks

sub fromFile {
  my $class  = shift;
  my $file   = shift;
  my $tracks = $class->SUPER::fromFile($file);
  my $guide  = shift(@$tracks);
  if (!$guide || 
      !$guide->duration ||
      !scalar @$tracks
     )  {
    confess "$file produced no valid drum tracks";
  }
  my $track = $class->new();
  $track->time($guide->time);
  foreach my $t (@$tracks) {
    #lengthen out hits to our drum resolution
    foreach my $h (@$t) {
      if ($h->isPercussion()) {
	$h->duration($DRUM_RESOLUTION);
      }
      $track->add($h);
    }
  }
  #filter out blankness in the front, 
  #and move the zero of this track to the correct place
  #for some definition of "correct"
  if ($track->duration() > $guide->clock->measureTime()) {
    #this track is longer than a measure, 
    #check for a pickup and set our guide/time appropriately
    my $fudgeIt = $DRUM_RESOLUTION;
    while ($track->soundingTime > $fudgeIt) {
      my $clock = $guide->clock();
      #move zero up one measure
      $track->moveZero($clock->measureTime());
      #slice off that measure of the guide
      $guide = $guide->subList($clock->measureTime(), $guide->reach());
      #slide everyones zero back to zero
      $track->time(0);
      $guide->time(0);
    }
  }
  if (!$guide->duration || !$track->duration) {
    confess "Yeah, that didn't work";
  }
  #reset the end of the guide, in case we stripped some events off in the process
  $guide->setEnd($track->reach);
  return [$guide,$track];
}

sub toDataStructure {
  my $self    = shift;
  my $guide   = shift;
  my $drumRef = $self->split();
  my $ret     = {};
  my $maxLen;
  while (my ($drum,$track) = each %$drumRef) {
    my $str = AutoHarp::Notation::DrumTrack2String($track,$guide);
    if ($str) {
      $maxLen = length($drum . $str) if (length($drum . $str) > $maxLen);
      $ret->{$drum} = $str;
    }
  }

  #a little formatting sugar--pad out each string with spaces 
  #so the measures line up
  foreach my $k (keys %$ret) {
    my $len = length($k . $ret->{$k});
    if ($len < $maxLen) {
      $ret->{$k} = " " x ($maxLen - $len) . $ret->{$k};
    }
  }
  return $ret;
}

sub fromDataStructure {
  my $class  = shift;
  my $struct = shift;
  my $guide  = shift;
  my $self   = $class->new();
  if ($guide) {
    $self->time($guide->time());
  }
  while (my ($d,$str) = each %{$struct}) {
    my $dPitch = $MIDI::percussion2notenum{$d};
    $self->add(AutoHarp::Notation::String2DrumTrack($str,$guide,$dPitch));
  }
  return $self;
}

sub isPercussion {
  #why yes I am
  return 1;
}

#split myself into individual drums
sub split {
  my $self     = shift;
  my $tracks   = [];
  my $drumRef  = {};
  foreach my $m (@{$self->notes()}) {
    my $d = $MIDI::notenum2percussion{$m->pitch};
    if (!$drumRef->{$d}) {
      $drumRef->{$d} = AutoHarp::Events::DrumTrack->new();
      $drumRef->{$d}->time($self->time);
    }
    $drumRef->{$d}->add($m);
  }
  return $drumRef;
}

#prune out all but the specified hits
sub prune {
  my $self = shift;
  my $what = shift || [];
  my $when = shift;

  my $pruned = [];
  if (!ref($what)) {
    $what = [$what];
  }
  if (!scalar @$what) {
    confess "Got nothing to prune!";
  }

  if (!length($when)) {
    $when = $self->soundingTime();
  }

  for (my $i = 0; $i < scalar @$self; $i++) {
    my $n = $self->[$i];
    if ($n->isPercussion() && 
	$n->time >= $when && 
	scalar grep {$n->drum =~ /$_/i} @$what) {
      push(@$pruned,$n->clone());
      splice(@$self,$i,1);
      $i--;
    }
  }
  return $pruned;
}

sub hasHitAtTime {
  my $self = shift;
  my $hit  = shift;
  return (scalar grep {$_->pitch == $hit->pitch &&
			 $_->time  == $hit->time
		       } @{$self->notes()});
}

sub hitsAt {
  my $self = shift;
  my $time = shift;
  return [grep {$_->time == $time} @{$self->notes()}];
}

#the inverse of the above
sub pruneExcept {
  my $self = shift;
  my $what = shift;
  my $when = shift;
  my $pruned = [];
  
  if (!ref($what)) {
    $what = [$what];
  }
  
  if (!scalar @$what) {
    confess "Would prune everything! You want truncate";
  }

  if (!length($when)) {
    $when = $self->soundingTime();
  }

  for (my $i = 0; $i < scalar @$self; $i++) {
    my $n = $self->[$i];
    if ($n->isPercussion() && 
	$n->time >= $when && 
	!scalar grep {$n->drum =~ /$_/i} @$what) {
      push(@$pruned,$n->clone());
      splice(@$self,$i,1);
      $i--;
    }
  }
  return $pruned;
}

sub snares {
  return $_[0]->drumsInTrack('Snare');
}

sub kicks {
  return $_[0]->drumsInTrack('Bass');
}

sub hats {
  return $_[0]->drumsInTrack('Hi-Hat');
}

sub toms {
  return $_[0]->drumsInTrack('Tom');
}

#a list of the drums in this track
#(of a specific type, if passed in)
sub drumsInTrack {
  my $self = shift;
  my $type = shift;
  my $seen = {};
  return [map {$_->pitch}
	  grep {!$seen->{$_}++ &&
		  (!$type || $_->drum =~ /$type/i)
		} 
	  @{$self->notes()}];
}

sub channel {
  return $PERCUSSION_CHANNEL;
}

sub eventCanBeAdded {
  my $self = shift;
  my $event = shift;
  if ($event->isNote()) {
    if (!$event->drum) {
      #don't want non-drums
      return;
      #confess sprintf("Attempted to add non-drum note %s to drum track",$event->pitch);
    } elsif ($self->hasHitAtTime($event)) {
      #no double-hitting
      return;
    }
  } elsif ($event->isMusic) {
    #no expression or aftertouch is really relevant to us
    return;
  }
  return $self->SUPER::eventCanBeAdded($event);
}

"That Stoner should know better by now";

