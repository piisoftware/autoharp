package AutoHarp::MusicBox::Song;

use AutoHarp::Constants;
use AutoHarp::Events::Performance;
use AutoHarp::ScoreCollection;
use AutoHarp::Instrument;
use AutoHarp::Scale;
use AutoHarp::Generator;
use AutoHarp::Clock;
use AutoHarp::Fuzzy;

use MIDI;
use strict;
use Carp;
use Data::Dumper; 
use base qw(AutoHarp::MusicBox);

my $FILE        = 'file';
my $SEGMENTS    = 'segments';
my $VERBOSE     = !$ENV{AUTOHARP_QUIET};
my $CHANNELS    = 'channels';
my $COLLECTION  = 'collection';

sub segments {
  my $self = shift;
  $self->{$SEGMENTS} ||= [];
  return $self->{$SEGMENTS};
}

sub hasSegments {
  my $self = shift;
  return ($self->{$SEGMENTS} && scalar @{$self->{$SEGMENTS}});
}

sub addSegment {
  my $self    = shift;
  my $segment = shift;
  if ($self->hasSegments()) {
    my $last = $self->segments->[-1];
    if ($segment->time != $last->reach) {
      confess sprintf "Adding a segment at time %d immediately after segment #%d ending at %d",$segment->time(),scalar @{$self->{$SEGMENTS}}, $last->reach();
    }
  }
  push(@{$self->{$SEGMENTS}},$segment);
}

sub spliceSegment {
  my $self    = shift;
  my $segment = shift;
  my $where   = shift;
  splice(@{$self->{$SEGMENTS}},$where,0,$segment);
  $self->retimeSegments();
}

sub retimeSegments {
  my $self = shift;
  if ($self->hasSegments()) {
    my $startSeg  = $self->segments()->[0];
    #rezero everything
    my $startTime = 0;
    $startSeg->time($startTime);
    my $soundTime = $startSeg->soundingTime;
    if ($soundTime < 0) {
      $startTime = $startSeg->musicBox->clock->roundToNextMeasure(abs($soundTime));
    }
    my $counter = 0;
    foreach my $seg (@{$self->segments()}) {
      $counter++;
      $seg->time($startTime);
      if ($seg->soundingTime < 0) {
	my $st;
	foreach my $s (@{$seg->scores()}) {
	  if (!$st || $s->soundingTime < $st->soundingTime) {
	    $st = $s;
	  }
	}
	$st->dump();
	confess sprintf("Segment %d has sounding time %d, despite starting at %d",
			$counter,
			$seg->soundingTime,
			$startTime
		       );
      }
      $startTime = $seg->reach();
    }
  }
}

sub time {
  return 0;
}

sub reach {
  my $self = shift;
  if ($self->hasSegments()) {
    return $self->{$SEGMENTS}[-1]->reach();
  }
  return 0;
}

#song starts by definition from zero, so it's however long the longest thing is
sub duration {
  return (shift)->reach();
}

sub measures {
  my $self = shift;
  my $arg  = shift;
  if (length($arg)) {
    confess "A song's measures cannot be set directly";
  }
  return scalar @{$self->eachMeasure()};
}

sub eachMeasure {
  my $self = shift;
  my $m = [];
  foreach my $s (@{$self->segments()}) {
    my $ms  = $s->musicBox->eachMeasure();
    push(@$m,@$ms) if (scalar @$ms);
  }
  return $m;
}

sub guide {
  my $self  = shift;
  my $guide = AutoHarp::Events::Guide->new();
  foreach my $segment (@{$self->segments}) {
    if ($guide->isEmpty()) {
      #steal clock and scale events from the first segment and put them
      #at time 0. Mark it as the beginning of the song
      $guide->setClock($segment->musicBox()->clock(),0);
      $guide->setScale($segment->musicBox()->scale(),0);
    } 
    #remove all non-clock non-text, non-key events
    my $g = [grep {!$_->isText() &&
		     ($_->isClock() || 
		      $_->isScale())} @{$segment->musicBox->guide}];
    $guide->add($g) if (scalar @$g);
    if ($segment->isChange()) {
      my $sTxt = $segment->songElement();
      if ($segment->elementIndex > 1 || 
	  $segment->isChorus() || 
	  $segment->isVerse()) {
	#add a number onto the marker name
	$sTxt .= " " . $segment->elementIndex;
      }
      my $sMarker = AutoHarp::Event::Marker->new(uc($sTxt),$segment->time);
      $guide->add($sMarker);
    }
  }
  return $guide;
}

sub scoreCollection {
  my $self   = shift;
  if (!$self->{$COLLECTION}) {
    my $sHash  = {};
    my $idx = 1;
    $self->{$CHANNELS} = {};
    
    if (!$self->hasSegments()) {
      confess "No segments in the song, nothing to build";
    }
    
    #make sure the segments are correctly timed to allow for intros and the like
    $self->retimeSegments();
    
    foreach my $segment (@{$self->segments}) {
      if ($segment->soundingTime < 0) {
	confess sprintf("Sounding time of segment %s, time %d is %d",$segment->songElement(),$segment->time(),$segment->soundingTime());
      }
      my $perfs = $segment->playerPerformances();
      foreach my $perfData (@$perfs) { 
	my $inst = $perfData->{$ATTR_INSTRUMENT};
	my $performance = $perfData->{$ATTR_MELODY};
	my $instId = $inst->uid();
	if (!$sHash->{$instId}) {
	  my $p = AutoHarp::Events::Performance->new($performance);
	  $self->initChannel($p,$inst);
	  $sHash->{$instId} = $p;
	  
	} else {
	  $sHash->{$instId}->add($performance);
	  if ($sHash->{$instId}->soundingTime < 0) {
	    $performance->dump();
	    confess sprintf("Adding performance of %s to segment %s (%d) caused it to have a negative sounding time",$instId,$segment->songElement(),$segment->time);
	  }
	}
      }
      $idx++;
    }
    $self->{$COLLECTION} = AutoHarp::ScoreCollection->new();
    $self->{$COLLECTION}->scores([values %$sHash]);
    $self->{$COLLECTION}->guide($self->guide);
  }
  return $self->{$COLLECTION};
}

sub tracks {
  my $self = shift;
  my $mix  = shift;
  my $coll = $self->scoreCollection();
  
  return ($mix) ? $coll->mixedTracks() : $coll->tracks();
}

sub initChannel {
  my $self  = shift;
  my $track = shift;
  my $inst  = shift;
  $track->setPatch($inst->patch);

  #prefer any channel already set in the track
  my $channel = $track->channel();
  if (!$channel) {
    #otherwise, find one that's not being used
    $channel = 0;
    while ($self->{$CHANNELS}{$channel} || $channel == $PERCUSSION_CHANNEL) {
      $channel++;
    }
  }
  #note that it is now being used
  $self->{$CHANNELS}{$channel}++;

  $track->channel($channel);
  $track->instrumentName($inst->toString);
  $track->trackName($inst->name);
}

sub nextChannel {
  my $self = shift;
}

sub toObject {
  my $self = shift;
  confess "This doesn't....work?";
  return {scores => $self->scores(),
	  time => $self->MMSS(),
	  bars => $self->measures(),
	  file => $self->file(),
	 };
}

sub durationInSeconds {
  my $self = shift;
  my $secs = 0;
  grep {$secs += $_->durationInSeconds()} @{$self->segments};
  return $secs;
}

sub opus {
  my $self = shift;
  confess "Who's calling this?";
}

sub file {
  return $_[0]->scalarAccessor($FILE,$_[1]);
}

sub out {
  my $self   = shift;
  return $self->scoreCollection()->out(@_);
}

sub dump {
  my $self = shift;
  foreach my $segment (@{$self->segments}) {
    printf "ticks %5d: %s (%s), reach %d\n",
      $segment->time,
	$segment->musicBox->name,
	  $segment->songElement(),
	    $segment->reach; 
  }
}

"How you're the light over me";
