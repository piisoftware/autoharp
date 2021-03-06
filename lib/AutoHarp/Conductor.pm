package AutoHarp::Conductor;

use strict;
use AutoHarp::MusicBox::Song;
use AutoHarp::Fuzzy;
use AutoHarp::Constants;
use AutoHarp::Instrument;
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
  my $loops       = shift || {};
  
  printf("%5d) %s: (%s)\n",
	 $segment->time,
	 uc($segment->songElement),
	 $segment->description()
	) if ($VERBOSE);

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
    my $dLoop   = $loops->{$drummerUid};
    #note first whether or not the drummer wishes to actually play
    $drummerDecision = $dLoop || $drummer->decideSegment($segment);

    #log her performance either way...
    $self->handlePlay({$ATTR_INSTRUMENT => $drummer,
		       $SONG_SEGMENT    => $segment,
		       $PLAY_LOG        => $plays,
		       $LOOP_ID         => $dLoop
		      }
		     );
    if (!$plays->{$drummerUid} || !$plays->{$drummerUid}->duration) {
      print Dumper $drummer,$plays->{$drummerUid};
      confess "We tried, yet failed, to get a play from the drummer!";
    }
  }
  
 
  foreach my $i (values %{$instMap}) {
    next if ($i->uid eq $drummerUid);
    my $loop = $loops->{$i->uid};
    my $decision = $loop || $i->decideSegment($segment);
    
    if ($i->follow()) {
      #this person would prefer to follow, so defer for now, noting their decision
      push(@$deferrals, {$DECISION => $decision, $INST => $i});
    } elsif ($decision) {
      #go ahead and fetch the play now
      $self->handlePlay({$ATTR_INSTRUMENT => $i,
			 $SONG_SEGMENT    => $segment,
			 $PLAY_LOG        => $plays,
			 $ATTR_FOLLOW     => $drummerUid,
			 $LOOP_ID         => $loop
			});
    } elsif ($VERBOSE) {
      printf("\t%s(%s) decided NOT TO PLAY\n",$i->name,$i->instrumentClass);
    }
  }
  
  #who played?
  if (scalar keys %$plays < 2 && !$drummerDecision) {
    #Fuck off, you lazy bitches
    my $bass     = (grep {$_->is($BASS_INSTRUMENT)} values %$instMap)[0];
    my $rhythm   = (grep {$_->is($RHYTHM_INSTRUMENT)} values %$instMap)[0];
    my $theme    = pickOne(grep {$_->is($THEME_INSTRUMENT)} values %$instMap);
    
    if ($theme && sometimes) {
      #sometimes just hand it off to a theme
      printf("\t forcing %s...\n",$theme->name) if ($VERBOSE);
      $self->handlePlay({$ATTR_INSTRUMENT => $theme,
			 $SONG_SEGMENT    => $segment,
			 $PLAY_LOG        => $plays,
			 $ATTR_FOLLOW     => $drummerUid
			});
    } else {
      my $hasMusic;
      if ($bass && sometimes) {
	printf("\t forcing %s...\n",$bass->name) if ($VERBOSE);
	$self->handlePlay({$ATTR_INSTRUMENT => $bass, 
			   $SONG_SEGMENT    => $segment, 
			   $PLAY_LOG        => $plays, 
			   $ATTR_FOLLOW     => $drummerUid
			  });
	$hasMusic = 1;
      }
      if ($rhythm && sometimes) {
	printf("\t forcing %s...\n",$rhythm->name) if ($VERBOSE);
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
    #clear everybody's play log and then log who played
    $instMap->{$id}->clearPlayLog();
    if ($plays->{$id} && 
	($drummerDecision || $id ne $drummerUid)) {
      $segment->addPerformance($instMap->{$id},$plays->{$id});
      $instMap->{$id}->isPlaying(1);
    }
  }
}

sub reconduct {
  my $self = shift;
  my $song = shift;

  #do a pre-pass to get all the instruments
  my $instMap = {};
  foreach my $segment (@{$song->segments()}) {
    foreach my $pId (grep {!exists $instMap->{$_}} @{$segment->players}) {
      $instMap->{$pId} = $segment->player($pId);
      #clear everybody's play flags to start
      $instMap->{$pId}->isPlaying(0);
    }
  }
  my $drummer = $instMap->{$DRUM_LOOP};
  if (!$drummer) {
    print Dumper $instMap;
    die "WTF? Where's the drummer?";
  }
  
  foreach my $segment (@{$song->segments()}) {
    printf("%5d) %s: (%s)\n",
	   $segment->time,
	   uc($segment->songElement),
	   $segment->description()
	  ) if ($VERBOSE);
    my $plays = {};
    if (!$segment->hasPerformanceForPlayer($DRUM_LOOP)) {
      if ($VERBOSE) {
	printf("\t%s (%s) being regenerated at %d\n",
	       $drummer->name,
	       $drummer->instrumentClass,
	       $segment->time);
      }
      $self->handlePlay({$ATTR_INSTRUMENT => $drummer,
			 $SONG_SEGMENT    => $segment,
			 $PLAY_LOG        => $plays
			}
		       );
    }
    my $replaceDrums = 0;
    foreach my $pId (@{$segment->players()}) {
      my $inst = $segment->player($pId);
      if ($segment->hasPerformanceForPlayer($pId)) {
	if ($VERBOSE) {
	  printf("\t%s (%s) already playing at %d\n",
		 $inst->name,
		 $inst->instrumentClass,		 
		 $segment->time);
	}
      } elsif ($pId eq $DRUM_LOOP) {
	#the drummer was playing, and doesn't have a play already
	$replaceDrums = 1;
      } else {
	if ($VERBOSE) {
	  printf("\t%s (%s) newly playing at %d\n",
		 $inst->name,
		 $inst->instrumentClass,
		 $segment->time);
	}
	#go ahead and fetch the play now
	$self->handlePlay({$ATTR_INSTRUMENT => $inst,
			   $SONG_SEGMENT    => $segment,
			   $PLAY_LOG        => $plays,
			   $ATTR_FOLLOW     => $drummer->uid
			  });
      }
    }
    while (my ($id, $inst) = each %$instMap) {
      $inst->isPlaying(0);
      if ($plays->{$id} && ($id ne $DRUM_LOOP || $replaceDrums)) {
	$inst->isPlaying(1);
	$segment->addPerformance($inst, $plays->{$id});
      }
    }
  }
}

sub conduct {
  my $self        = shift;
  my $args        = shift;
  if (ref($args) ne 'HASH') {
    confess "Bad args passed to conduct. Cannot...conduct.";
  }

  my $composer    = $args->{$ATTR_COMPOSER};
  my $musicMap    = $args->{$ATTR_MUSIC};
  my $instMap     = $args->{$ATTR_INSTRUMENTS};
  my $hook        = $args->{$ATTR_HOOK};
  my $loops       = $args->{$ATTR_LOOPS};

  if (!$composer) {
    confess "No composer--cannot conduct";
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
  print "Getting performance segments...\n" if ($VERBOSE);  
  my $pSegs = $composer->performanceSegments({$ATTR_BARS => $args->{$ATTR_BARS},
					      $ATTR_HOOK => $args->{$ATTR_HOOK},
					      %$musicMap});
  print "Conducting segments...\n" if ($VERBOSE);
  foreach my $segment (@$pSegs) {
    my $segmentLoops = ($loops) ? $loops->{$segment->uid} : {};

    if ($segment->hasHook()) {
      if ($segment->time != $segment->musicBox->time ||
	  $segment->time != $segment->hook->time) {
	confess sprintf("HERE! WTF: %d,%d,%d\n",$segment->time,
			$segment->musicBox->time,
			$segment->hook->time);
      }
    }
    $self->conductSegment($segment,$instMap, $segmentLoops);
    $song->addSegment($segment);
  }
  return $song;
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
  my $wasLoop = 0;
  if ($loop && !$loop->isEmpty()) {
    $wasLoop = 1;
    $play = $inst->playLoop($segment, $loop);
  } else {
    $play = $inst->play($segment, $playLog->{$followId});
  }

  if ($play && (!ref($play) || !$play->can('hasNotes'))) {
    print Dumper $play,$inst;
    confess "WHAT THE HELL IS THIS?";
  }
  
  if ($play && $play->hasNotes()) {
    $playLog->{$inst->id} = $play;
    if ($VERBOSE) {
      printf("\t%s (%s) %s at %d\n",
	     $inst->name,
	     $inst->instrumentClass,
	     ($loop) ? "repeated loop " . $loop->id : "played",
	     $play->time);
    } 
    
    my $mt     = $segment->musicBox->clock->measureTime;
    my $emt    = $segment->musicBox->clockAtEnd->measureTime;
    my $buffer = ($inst->isDrums()) ? ($mt * 4) : $mt;
    if (
     	$play->time < ($segment->time - $buffer) ||
     	$play->reach > ($segment->reach() + $emt)
       ) {
      printf "%s is playing this:\n",$inst->id;
      $play->dump;
      printf "for %d to %d\n",$segment->time,$segment->reach;
      $segment->musicBox->dump();
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

"I'm definitely shaking";

