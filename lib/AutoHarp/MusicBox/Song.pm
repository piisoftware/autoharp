package AutoHarp::MusicBox::Song;

use AutoHarp::Constants;
use AutoHarp::Events::Performance;
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
my $FIRST_HALF  = 'firstHalfPlayers';
my $SECOND_HALF = 'secondHalfPlayers';
my $PLAYERS     = 'players';

sub CompositionFromDataStructure {
  my $ds = shift;
  my $comp = [];
  foreach my $d (@$ds) {
    my $e = AutoHarp::Composer::CompositionElement
      (
       {$ATTR_TAG => $d->{$ATTR_TAG},
	$ATTR_MUSIC => $d->{$ATTR_MUSIC},
	$SONG_ELEMENT_TRANSITION => $d->{$SONG_ELEMENT_TRANSITION}
       }
      );
    $e->firstHalfPerformers([split(/\s*,\s*/,$d->{$FIRST_HALF})]);
    $e->secondHalfPerformers([split(/\s*,\s*/,$d->{$SECOND_HALF})]);
    push(@$comp, $e);
  }
  return $comp;
}

sub toDataStructure {
  my $self = shift;
  my $ds = [];
  my $nextData;
  foreach my $segment (@{$self->segments()}) {
    my $performers = join(", ",
			  sort 
			  map {$_->{$ATTR_INSTRUMENT}->uid} 
			  @{$segment->playerPerformances()}
			 );
    if ($segment->isFirstHalf()) {
      if ($nextData) {
	confess "Found first half segment without having completed a previous segment, cannot convert song to data";
      }
      $nextData = {$ATTR_TAG   => $segment->tag(),
		   $ATTR_MUSIC => $segment->musicTag(),
		   $FIRST_HALF => $performers
		  };
    } elsif ($segment->isSecondHalf) {
      if (!$nextData || !$nextData->{$FIRST_HALF}) {
	confess "Invalid segments constructed, cannot build data structure";
      } elsif ($nextData->{$ATTR_TAG} != $segment->tag() ||
	       $nextData->{$ATTR_MUSIC} != $segment->musicTag()) {
	confess "Second half segment doesn't match first half segment, cannot build data structure";
      } 
      $nextData->{$SECOND_HALF} = $performers;
      $nextData->{$SONG_ELEMENT_TRANSITION} = $segment->transitionOut();
      push(@$ds,$nextData);
      undef $nextData;
    } else {
      push(@$ds,{$ATTR_TAG => $segment->tag(),
		 $ATTR_MUSIC => $segment->musicTag(),
		 $PLAYERS => $performers,
		 $SONG_ELEMENT_TRANSITION => $segment->transitionOut()
		});
    }
  }
  return $ds;
}

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

sub retimeSegments {
  my $self = shift;
  if ($self->hasSegments()) {
    my $startSeg  = $self->segments()->[0];
    my $startTime = $startSeg->time;
    my $soundTime = $startSeg->soundingTime;
    if ($soundTime < 0) {
      $startTime = $startSeg->music->clock->roundToNextMeasure(abs($soundTime));
    }
    foreach my $seg (@{$self->segments()}) {
      $seg->time($startTime);
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
    my $ms  = $s->music->eachMeasure();
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
      $guide->setClock($segment->music()->clock(),0);
      $guide->setScale($segment->music()->scale(),0);
    } 
    #remove all non-clock non-text, non-key events
    my $g = [grep {!$_->isText() &&
		     ($_->isClock() || 
		      $_->isScale())} @{$segment->music->guide}];
    $guide->add($g) if (scalar @$g);
    if ($segment->isChange()) {
      my $sTxt = $segment->tag();
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

sub scores {
  my $self   = shift;
  my $mix    = shift;
  my $sHash  = {};
  my $idx = 1;
  $self->{$CHANNELS} = {};

  if (!$self->hasSegments()) {
    confess "No segments in the song, nothing to build";
  }
  my $talk = ($VERBOSE && !$mix); 
  print "Building scores...\n" if ($talk);
  
  #make sure the segments are correctly timed to allow for intros and the like
  $self->retimeSegments();
  
  foreach my $segment (@{$self->segments}) {
    printf "%2d) %12s. Players: ",$idx,$segment->tag if ($talk);
    if ($segment->soundingTime < 0) {
      confess sprintf("Sounding time of segment %s, time %d is %d",$segment->tag(),$segment->time(),$segment->soundingTime());
    }
    my $perfs = $segment->playerPerformances();
    my @playList;
    foreach my $perfData (@$perfs) { 
      my $inst = $perfData->{$ATTR_INSTRUMENT};
      my $performance = $perfData->{$ATTR_MELODY};
      my $instId = $inst->uid();
      push(@playList,$instId);
      if (!$sHash->{$instId}) {
	my $p = AutoHarp::Events::Performance->new($performance);
	$self->initChannel($p,$inst,$mix);
	#$segment->music->clock()->addSwing($p);
	$sHash->{$instId} = $p;
      } else {
	#$segment->music->clock()->addSwing($performance);
	$sHash->{$instId}->add($performance);
	if ($sHash->{$instId}->soundingTime < 0) {
	  $performance->dump();
	  confess sprintf("Adding performance of %s to segment %s (%d) caused it to have a negative sounding time",$instId,$segment->tag,$segment->time);
	}
      }
    }
    if ($talk) {
      print join(", ", sort(@playList));
      print "\n";
    }
    $idx++;
  }
  printf "Done building scores.\n" if ($talk);
  my $scores = [values %$sHash];
  push(@$scores, $self->guide);
  return $scores;
}

sub tracks {
  my $self = shift;
  my $mix  = shift;
  return [map {$_->track} @{$self->scores($mix)}];
}

sub initChannel {
  my $self  = shift;
  my $track = shift;
  my $inst  = shift;
  my $mix   = shift;
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
  $track->add([$EVENT_TRACK_NAME, $track->time, $inst->name]);
  $track->add([$EVENT_INSTRUMENT_NAME, $track->time, $inst->name]);

  if ($mix) {
    $track->setVolume(50);
    if ($inst->isDrums()) {
      $track->setVolume(60);
    } elsif ($inst->is($BASS_INSTRUMENT)) {
      $track->setVolume(40);
    } elsif ($inst->is($PAD_INSTRUMENT)) {
      $track->setVolume(50);
    } elsif ($inst->is($RHYTHM_INSTRUMENT)) {
      $track->setVolume(50);
    } elsif ($inst->is($LEAD_INSTRUMENT)) {
      $track->setPan(-10);
    } elsif ($inst->is($HOOK_INSTRUMENT)) {
      $track->setPan(10);
    } else {
      $track->setPan((pickOne(12.5, -12.5)) * (pickOne(2,3,4)));
    }
  }
}

sub nextChannel {
  my $self = shift;
}

sub toObject {
  my $self = shift;
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
  my $mix  = shift;
  return MIDI::Opus->new( {
			   format => 1,
			   ticks => $TICKS_PER_BEAT,
			   tracks => $self->tracks($mix)
			  } );
}

sub file {
  return $_[0]->scalarAccessor($FILE,$_[1]);
}

sub out {
  my $self   = shift;
  my $output = shift;
  my $mix    = shift;
  if ($output) {
    my $file;
    if (-d $output) {
      $output =~ s|/$||;
      $file = $output . "/" . $self->uid() . ".mid";
    } else {
      $file = $output;
    }
    $self->opus($mix)->write_to_file($file);
    $self->file($file);
    return 1;
  }
  return;
}

sub dump {
  my $self = shift;
  foreach my $segment (@{$self->segments}) {
    printf "ticks %5d: %s (%s), reach %d\n",
      $segment->time,
	$segment->music->name,
	  $segment->tag,
	    $segment->reach; 
  }
}

"How you're the light over me";
