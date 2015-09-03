package AutoHarp::Conductor;

use strict;
use AutoHarp::MusicBox::Song;
use AutoHarp::Fuzzy;
use AutoHarp::Constants;
use AutoHarp::Instrument;
use AutoHarp::MusicBox::Song::Segment;
use Carp;

use Data::Dumper;

use base qw(AutoHarp::Class);

#Third generation of AutoHarp composition process
#Takes a composition from the composer, 
#Takes a list of instruments,
#conducts, and produces a song object

my $VERBOSE  = !$ENV{AUTOHARP_QUIET};
my $PLAY_LOG = 'playLog';
my $LOOP_ID  = 'loop_id';

#allow instruments to follow other instruments in the band
sub handleFollowing {
  my $self        = shift;
  my $instMap     = shift;

  foreach my $uid (keys %$instMap) {
    my $inst   = $instMap->{$uid};
    my $follow = $inst->getFollowRequest();
    next if (!$follow);
    printf "%s wants to follow %s\n",$inst->name,$follow if ($VERBOSE);
    foreach my $u (grep {$_ ne $inst->uid} keys %$instMap) {
      my $i = $instMap->{$u};
      if (!$i->follow() && ($i->is($follow) || $i->id eq $follow)) {
	#Why yes, I am a thing you want to follow, 
	#and I'm not already following someone else
	$inst->follow($i->uid);
	printf "\t%s found %s\n",$inst->name,$i->name if ($VERBOSE);
	last;
      }
    }
    printf "\t%s found NO ONE\n",$inst->name
      if ($VERBOSE && !$inst->follow());
  }
}

sub nextChannel {
  my $self = shift;
  my $found = {map {$_->channel => 1} values %{$self->{$ATTR_INSTRUMENTS}}};
  my $c = 0;
  #always skip 9, as it is drums. If something wants to be drums, it'll tell us
  while ($found->{$c} || $c == $PERCUSSION_CHANNEL) {
    $c++;
  }
  return $c;
}

sub conductSegment {
  my $self        = shift;
  my $segment     = shift;
  my $instMap     = shift;
  my $loops       = shift;

  printf("%5d) %s:\n",$segment->time,uc($segment->songElement)) if ($VERBOSE);

  my $deferrals = [];
  my $plays     = {};  
  my $DECISION  = 'decisions';
  my $INST      = 'instrument';
  
  #start by getting the drummer...
  #drummer will define the rhythm for everybody else 
  #(assuming there is one).
  my $drummer       = (grep {$_->isDrums()} values %$instMap)[0];  
  my $drummerDecision;
  my $drummerUid;
  
  if ($drummer) {
    $drummerUid = $drummer->uid();
    #note first whether or not the drummer wishes to actually play
    $drummerDecision = $drummer->decideSegment($segment);
    #log her performance either way...
    $self->handlePlay({$ATTR_INSTRUMENT => $drummer,
		       $SONG_SEGMENT    => $segment,
		       $PLAY_LOG        => $plays,
		       $LOOP_ID         => $loops->{$drummerUid}
		      }
		     );
    if (!$plays->{$drummerUid} || !$plays->{$drummerUid}->duration) {
      print Dumper $drummer,$plays->{$drummerUid};
      confess "We tried, yet failed, to get a play from the drummer!";
    }
  }
  
  #now loop through the instruments. 
  #if they are already registered as players, get their plays
  #otherwise, get their initial decision for this segment
  if ($segment->hasPlayers()) {
    #re-zero the drummer's decision
    $drummerDecision = 0;
    foreach my $i (@{$segment->players()}) {
      my $inst = $instMap->{$i};
      if (!$inst) {
	confess "Found unrecognized player $i in segment.";
      }
      printf("\t%s (%s) IN PLAYLIST (follows: %s)\n",
	     $inst->name(),
	     $inst->instrumentClass,
	     $inst->follow() || 'nobody') if ($VERBOSE);

      if ($i eq $drummerUid) {
	#the drummer's in the list of pre-ordained players. Noted...
	$drummerDecision = 1;
	next;
      }

      if ($inst->follow()) {
	push(@$deferrals, {$DECISION => 1, $INST => $inst});
      } else {
	$self->handlePlay({$ATTR_INSTRUMENT => $inst,
			   $SONG_SEGMENT    => $segment,
			   $PLAY_LOG        => $plays,
			   $ATTR_FOLLOW     => $drummerUid,
			   $LOOP_ID         => $loops->{$i}
			  });
      }
    }
  } else {
    foreach my $i (values %{$instMap}) {
      next if ($i->uid eq $drummerUid);
      my $decision = $i->decideSegment($segment);
      printf("\t%s (%s) decides %s Play (follows: %s)\n",
	     $i->name(),
	     $i->instrumentClass,
	     $decision ? 'to' : 'NOT to',
	     $i->follow() || 'nobody') if ($VERBOSE);
      if ($i->follow()) {
	#this person would prefer to follow, so defer for now, noting their decision
	push(@$deferrals, {$DECISION => $decision, $INST => $i});
      } elsif ($decision) {
	#go ahead and fetch the play now
	$self->handlePlay({$ATTR_INSTRUMENT => $i,
			   $SONG_SEGMENT    => $segment,
			   $PLAY_LOG        => $plays,
			   $ATTR_FOLLOW     => $drummerUid,
			   $LOOP_ID         => $loops->{$i->uid}
			  });
      }
    }
  }
  
  #who played?
  if (scalar keys %$plays < 2 && !$drummerDecision) {
    #nobody? Fuck off, you lazy bitches
    my $bass     = (grep {$_->is($BASS_INSTRUMENT)} values %$instMap)[0];
    my $rhythm   = (grep {$_->is($RHYTHM_INSTRUMENT)} values %$instMap)[0];
    my $theme    = pickOne(grep {$_->is($THEME_INSTRUMENT)} values %$instMap);
    
    if ($theme && sometimes) {
      #sometimes just hand it off to a theme
      printf "\t forcing...\n" if ($VERBOSE);
      $self->handlePlay({$ATTR_INSTRUMENT => $theme,
			 $SONG_SEGMENT    => $segment,
			 $PLAY_LOG        => $plays,
			 $ATTR_FOLLOW     => $drummerUid,
			 $LOOP_ID         => $loops->{$theme->uid}
			});
    } else {
      my $hasMusic;
      if ($bass && sometimes) {
	printf "\t forcing...\n" if ($VERBOSE);
	$self->handlePlay({$ATTR_INSTRUMENT => $bass, 
			   $SONG_SEGMENT    => $segment, 
			   $PLAY_LOG        => $plays, 
			   $ATTR_FOLLOW     => $drummerUid,
			   $LOOP_ID         => $loops->{$bass->uid}
			  });
	$hasMusic = 1;
      }
      if ($rhythm && sometimes) {
	printf "\t forcing...\n" if ($VERBOSE);
	$self->handlePlay({$ATTR_INSTRUMENT => $rhythm, 
			   $SONG_SEGMENT    => $segment, 
			   $PLAY_LOG        => $plays, 
			   $ATTR_FOLLOW     => $drummerUid,
			   $LOOP_ID         => $loops->{$rhythm->uid}
			  });
	$hasMusic = 1;
      }
      if (!$hasMusic) {
	#reverse the drummer's decision not to play. Fuck you, drummer
	printf "\treversing drummer's no-play decision\n" if ($VERBOSE);
	$drummerDecision = 1;
      }
    }
  }
  
  #are there any followers who need guidance?
  foreach my $deferral (@$deferrals) {
    my $instrument = $deferral->{$INST};
    my $willPlay   = $deferral->{$DECISION};
    my $followId   = $instrument->follow();
    #this instrument wants to follow someone...
    if ($plays->{$followId}) {
      #...and that someone has played
      printf "\t deferred follow...\n" if ($VERBOSE);
      $self->handlePlay({$ATTR_INSTRUMENT => $instrument, 
			 $SONG_SEGMENT    => $segment,
			 $PLAY_LOG        => $plays
			});
    } elsif ($willPlay) {
      #...and that someone has not played, 
      #but the instrument decided to play anyway
      printf "\t deferred play...\n" if ($VERBOSE);
      $self->handlePlay({$ATTR_INSTRUMENT => $instrument, 
			 $SONG_SEGMENT    => $segment, 
			 $PLAY_LOG        => $plays,
			 $ATTR_FOLLOW     => $drummerUid,
			 $LOOP_ID         => $loops->{$instrument->uid}
			});
    }
  }
  
  #we have everybody's music who's playin'
  #record the plays, clear everybody else's play flags
  foreach my $id (keys %$instMap) {
    if ($plays->{$id} && 
	($drummerDecision || $id ne $drummerUid)) {
      $segment->addPerformance($instMap->{$id},$plays->{$id});
    } else {
      $instMap->{$id}->clearPlayLog();
    }
  }
}


sub conduct {
  my $self        = shift;
  my $args        = shift;
  if (ref($args) ne 'HASH') {
    confess "Bad args passed to conduct. Cannot...conduct.";
  }

  my $composition = $args->{$ATTR_COMPOSITION};
  my $musicMap    = $args->{$ATTR_MUSIC};
  my $instMap     = $args->{$ATTR_INSTRUMENTS};
  my $hook        = $args->{$ATTR_HOOK};
  my $loops       = $args->{$ATTR_LOOPS};

  if (!$composition) {
    confess "No composition--cannot conduct";
  }

  if (!$musicMap) {
    confess "No music--cannot conduct";
  }
  
  if (!$instMap) {
    confess "No instruments--cannot conduct";
  }

  my $song = AutoHarp::MusicBox::Song->new();

  #handle lead/follow roles
  $self->handleFollowing($instMap);
  print "Building song segments...\n" if ($VERBOSE);  
  my $builtSegments = $self->buildSongSegments($composition,
					       $musicMap,
					       $hook);
  print "Conducting segments...\n" if ($VERBOSE);
  foreach my $segment (@$builtSegments) {
    my $segmentLoops = ($loops) ? $loops->{$segment->uid} : {};
    $self->conductSegment($segment,$instMap, $segmentLoops);
    $song->addSegment($segment);
  }
  return $song;
}

#take a composition and build it into song segments 
#with associated plays
sub buildSongSegments {
  my $self        = shift;
  my $composition = shift;
  my $music       = shift;
  my $hook        = shift;
  my $segments = [];

  my $counts = {};
  my $prevTag;
  my $prevTrans;

  my $time = 0;
  for (my $idx = 0; $idx < scalar @$composition; $idx++) {
    my $compElement = $composition->[$idx];
    my $nextElement = $composition->[$idx + 1];
    my $parentMusic = $music->{$compElement->musicTag};
    if (!$compElement->musicTag()) {
      confess "Found composition element with empty music tag for " . $compElement->tag();
    } elsif (!$parentMusic) {
      confess sprintf("Found composition element with an unrecognized music tag '%s' (have %s)",$compElement->musicTag(),join(", ",keys %$music));
    }
    my $segMusic = $parentMusic->clone();
    my $tag      = $compElement->tag();
    my $nextTag  = ($nextElement) ? $nextElement->tag() : $SONG_ELEMENT_END;
    my $isRepeat = ($prevTag && $tag eq $prevTag);
    $counts->{$tag}++ if (!$isRepeat);

    my $firstSegment = AutoHarp::MusicBox::Song::Segment->new();
    $firstSegment->time($time);
    $firstSegment->isRepeat($isRepeat);
    $firstSegment->elementIndex($counts->{$tag});
    $firstSegment->songElement($tag);
    $firstSegment->nextSongElement($nextTag);
    $firstSegment->isSongBeginning(($prevTag) ? 0 : 1);
    $firstSegment->transitionIn($prevTrans);
    $firstSegment->transitionOut($compElement->transition());
    $firstSegment->music($segMusic);
    $firstSegment->uid($compElement->firstHalfUID);
    $firstSegment->hook($hook);
    if ($compElement->hasFirstHalfPerformers) {
      #note who's going to play if it's already been decided
      foreach my $p (@{$compElement->firstHalfPerformers}) {
	$firstSegment->addPerformerId($p);
      }
    }

    push(@$segments, $firstSegment);
    
    $time = $firstSegment->reach();
    if ($segMusic->measures() >= 4 && !($segMusic->measures() % 2)) {
      #We can split this into two, so let's do it
      my $secondSegment = AutoHarp::MusicBox::Song::Segment->new();
      my $secondHalf    = $segMusic->secondHalf();
      $secondSegment->isRepeat($isRepeat);
      $secondSegment->elementIndex($counts->{$tag});
      $secondSegment->songElement($tag);
      $secondSegment->music($secondHalf);
      $secondSegment->hook($hook);
      $secondSegment->nextSongElement($nextTag);
      $secondSegment->isSecondHalf(1);
      $secondSegment->transitionOut($compElement->transition());
      $secondSegment->uid($compElement->secondHalfUID);
      if ($compElement->hasSecondHalfPerformers) {
	foreach my $p (@{$compElement->secondHalfPerformers}) {
	  $secondSegment->addPerformerId($p);
	}
      }
      
      push(@$segments, $secondSegment);
      
      #make the necessary changes to the first segment
      $segMusic->halve();
      $firstSegment->music($segMusic);
      $firstSegment->nextSongElement($tag);
      $firstSegment->transitionIn($ATTR_STRAIGHT_TRANSITION);
      $firstSegment->isFirstHalf(1);
      #set the second segment's time correctly
      $secondSegment->time($firstSegment->reach());
      #adjust the hook if it's longer than the first segment

      if ($hook && $hook->duration() > $firstSegment->duration()) {
	#this hook overlaps the first segment, so give this segment 
	#the rest of it
	$secondSegment->hook($hook->subMusic($firstSegment->duration()));
      }
      $time = $secondSegment->reach();
    } 
    $prevTag   = $tag;
    $prevTrans = $compElement->transition();
  }
  return $segments;
}


sub handlePlay {
  my $self     = shift;
  my $args     = shift;

  my $inst        = $args->{$ATTR_INSTRUMENT};
  my $segment     = $args->{$SONG_SEGMENT};
  my $playLog     = $args->{$PLAY_LOG};
  my $fSuggestion = $args->{$ATTR_FOLLOW};
  my $loop        = ($args->{$LOOP_ID}) ? AutoHarp::Model::Loop->load($args->{$LOOP_ID}) : undef;
  
  my $followId = $inst->follow() || $fSuggestion;
  my $play;
  if ($loop && !$loop->isEmpty()) {
    $inst->playLoop($segment, $loop);
  } else {
    $play = $inst->play($segment, $playLog->{$followId});
    $inst->clearPlayLog();
  }

  if ($play && (!ref($play) || !$play->can('hasNotes'))) {
    print Dumper $play,$inst;
    confess "WHAT THE HELL IS THIS?";
  }
  if ($play && $play->hasNotes()) {
    $playLog->{$inst->id} = $play;
    printf("\t %s playing for %d ticks starting at %d\n",
	   $inst->name,
	   $play->duration,
	   $play->time) if ($VERBOSE);
    my $mt     = $segment->music->clock->measureTime;
    my $emt    = $segment->music->clockAtEnd->measureTime;
    my $buffer = ($inst->isDrums()) ? ($mt * 4) : $mt;
    if (
     	$play->time < ($segment->time - $buffer) ||
     	$play->reach > ($segment->reach() + $emt)
       ) {
      printf "%s is playing this:\n",$inst->id;
      $play->dump;
      printf "for %d to %d\n",$segment->time,$segment->reach;
      $segment->music->dump();
      confess "That seemed bad, so I died";
    }
    if ((scalar grep {$_->pitch < 12} @{$play->notes()}) > 4) {
      printf "%s is playing a buncha crap that has low notes in it\n",$inst->instrumentClass;
      $play->dump();
      confess "That indicates badness, so I died";
    }
    $inst->isPlaying(1);
    return 1;
  }
  return;
}

sub reconstructSong {
  my $self = shift;
  my $args = shift;
  
  if (ref($args) ne 'HASH') {
    confess "Bad args passed to reconstruct. Cannot...reconstruct.";
  }

  my $songSegments = $args->{$ATTR_SONG};
  if (!$songSegments) {
    confess "No song segments passed, cannot reconstruct.";
  }
  $args->{$ATTR_COMPOSITION} = 
    AutoHarp::MusicBox::Song::CompositionFromDataStructure($songSegments);
  return $self->conduct($args);
}

#TODO -- MOVE TO SOME IMPORT WIZARD SOME DAY
sub importFile {
  my $self   = shift;
  my $instrs = $self->SUPER::importFile(@_);
  my $trackInsts;
  for (my $i = 0; $i < scalar @$instrs; $i++) {
    my $inst      = $instrs->[$i];
    my $role      = $inst->role();
    if ($role ne $ATTR_MELODY && $role ne $ATTR_PROGRESSION) {
      #legacy shit
      my $tInfo     = $inst->getTrackInfo();
      $role         = $tInfo->get('segmentMusic');
      if ($role) {
	$inst->deleteTrackInfo('segmentMusic');
	$inst->role($role);
      }
    }
    if ($role) {
      #this is the track which lists the melody or progression
      #stick it in a separate hash and remove it from the track list
      $trackInsts->{$role} = $inst;
      splice(@$instrs,$i,1);
      $i--;
    }
  }
  if (!$trackInsts->{$ATTR_MELODY} || !$trackInsts->{$ATTR_PROGRESSION}) {
    confess "Couldn't find melody or progression tracks--cannot import this file";
  }
  #populate the song log
  my $segments = $trackInsts->{$ATTR_MELODY}->getSongSegmentsFromScore;
  foreach my $seg (@$segments) {
    my $players = [];
    #figure out who was playing then
    if ($seg->duration > 0) {
      foreach my $i (@$instrs) {
	my $isPlaying = $i->hasNotes($seg->time,$seg->reach) || '0';
	$i->playLog($seg->time, $isPlaying);
	$i->segmentLogMsg($seg,($isPlaying) ? "IS playing segment" : "IS NOT playing segment");
	if ($isPlaying) {
	  push(@$players,$i);
	}
      }
      my $prog = $trackInsts->{$ATTR_PROGRESSION}->progression($seg->time,$seg->reach);
      $seg->progression($prog);
      if (!$seg->melody || !$seg->progression) {
	if (!$prog) {
	  print "No prog from this\n";
	  $trackInsts->{$ATTR_PROGRESSION}->dumpScore($seg->time, $seg->reach);
	}
	confess "Not enough music found for segment";
      }
    }
    push(@{$self->{songLog}},{$SONG_SEGMENT => $seg,
			      players      => $players});
  }
  return $instrs;
}

"I'm definitely shaking";

