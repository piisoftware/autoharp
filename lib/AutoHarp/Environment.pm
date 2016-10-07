package AutoHarp::Environment;

use strict;
use warnings;

use AutoHarp::Transcription;
use AutoHarp::Model::Genre;
use AutoHarp::Model::Loop;
use AutoHarp::Instrument;
use AutoHarp::Constants;
use AutoHarp::Notation;
use AutoHarp::Config;
use AutoHarp::Fuzzy;

use Time::HiRes qw(gettimeofday tv_interval);
use Proc::ProcessTable;
use FileHandle;
use MIDI::Opus;

use POSIX ":sys_wait_h"; 

use Data::Dumper;

use base qw(AutoHarp::Class);

my $MSGS     = 'messages';
my $PLAY_PID = 0;
my $PITCH_WHEEL_OFFSET = 8192;
my $DO_RECONDUCT = 'reconducterate. DO IT.';
my $STASH = 'stash';
my $S_HANDLE;

sub transcription {
  return $_[0]->scalarAccessor('transcription',$_[1]);
}

sub setNeedReconduct {
  $_[0]->{$DO_RECONDUCT} = 1;
}

sub needReconduct {
  $_[0]->{$DO_RECONDUCT};
}

sub reconduct {
  my $self = shift;
  AutoHarp::Conductor->new()->reconduct($self->transcription->song());
  delete $self->{$DO_RECONDUCT};
  $self->enqueueMsg("Reconducted session.");
}

sub startServer {
  my $self = shift;
  $S_HANDLE = FileHandle->new("| fluidsynth -s");
  print $S_HANDLE "load /usr/local/lib/GeneralUser/fluidsynth.sf2\n";
  $S_HANDLE->autoflush(1);

  #sleep(2);
}

sub stopServer {
  my $self = shift;
  $self->stop();  
  undef $S_HANDLE;
}

sub guide {
  my $self = shift;
  if ($self->transcription()) {
    return $self->transcription()->song->scoreCollection()->guide();
  }
  return AutoHarp::Events::Guide->new();
}

sub specifiedArrayOfSegments {
  my $self = shift;
  my $string = shift;
  my $includeAfter = shift;

  my $ret = [];
  my $whatNo   = ($string =~ /^(\d+)$/)[0] || 0;
  my $startIdx =  $whatNo - 1;
  my $segments = $self->transcription()->song()->segments();
  unless ($whatNo) {
    for(my $i = 0; $i < scalar @$segments; $i++) {
      if ($segments->[$i]->songElement eq $string) {
	$startIdx = $i;
	last;
      } 
    }
  }
  
  if ($startIdx >= 0) {
    for ($startIdx..$#$segments) {
      my $seg = $segments->[$_];
      if ($includeAfter ||
	  $startIdx == $_ ||
	  $seg->songElement() eq $string) {
	push(@$ret, $seg);
      }
    }
  }
  return $ret;
}

sub play {
  my $self = shift;
  my $song = shift;
  
  $self->stop();
  
  my $pid = fork();
  if ($pid) {
    $PLAY_PID = $pid;
  } else {
    $self->midiServerPlay($song);
    exit(0);
  }
}

sub midiServerPlay {
  my $self        = shift;
  my $song        = shift;
  my $sc = $song->scoreCollection();

  my $timeMap       = {};
  my $tempo         = $self->guide()->clock()->tempo;
  my $millisPerTick = (60000 / ($TICKS_PER_BEAT * $tempo));
  
  foreach my $track (@{$sc->mixedTracks()}) {
    my $trackTicks = 0;
    foreach my $event (@{$track->events_r}) {
      my $type  = $event->[0];
      my $ticks = $event->[1];
      my $chan  = $event->[2];
      my $val   = $event->[3];
      my $cmd;
      
      $trackTicks += $ticks;
      
      if ($type eq $EVENT_NOTE_ON) {
	$cmd = sprintf("noteon %d %d %d\n",$chan,$val,$event->[4]);
      } elsif ($type eq $EVENT_PITCH_WHEEL) {
	$cmd = sprintf("pitch_bend %d %d\n",$chan,$val + $PITCH_WHEEL_OFFSET);
      } elsif ($type eq $EVENT_NOTE_OFF) {
	$cmd = sprintf("noteoff %d %d\n",$chan,$val);
      } elsif ($type eq $EVENT_CONTROL_CHANGE) {
	$cmd = sprintf("cc %d %d %d\n",$chan,$val,$event->[4]);
      } elsif ($type eq $EVENT_PATCH_CHANGE) {
	$cmd = sprintf("prog %d %d\n",$chan,$val);
      }
      if ($cmd) {
	my $eTime = int($trackTicks * $millisPerTick);
	if ($eTime < 0) {
	  print Dumper $track->events_r;
	  die "WTF?";
	}
	
	$timeMap->{$eTime} ||= [];
	push(@{$timeMap->{$eTime}},$cmd);
      }
    }
  }
  
  #sort into an array of arrays by time
  my $timeData = [map
		  {{
		    time => $_,
		      notes => $timeMap->{$_}
		    }}
		  sort {$a <=> $b} keys %$timeMap
		 ];
  undef $timeMap;
  open(WTF, ">/tmp/wtf");
  foreach my $td (@$timeData) {
    foreach my $key (@{$td->{notes}}) {
      printf WTF "%6d) %s",$td->{time},$key
    }
  }
  close(WTF);
  my $t0        = [gettimeofday()];
  my $next      = shift(@$timeData);
  my $nextTime  = $next->{time};
  my $nextNotes = $next->{notes};
  while (1) {
    if (int(tv_interval($t0) * 1000) >= $nextTime) {
      grep {print $S_HANDLE $_} @{$nextNotes};
      $next      = shift(@$timeData);
      last if (!$next);
      
      $nextTime  = $next->{time};
      $nextNotes = $next->{notes};
    }
    Time::HiRes::usleep(20);
  }
}

sub stop {
  my $self = shift;
  if ($PLAY_PID) {
    my $res = waitpid($PLAY_PID,WNOHANG);
    if ($res == 0) {
      kill(15, $PLAY_PID);
      waitpid($PLAY_PID,0);
    }
    $PLAY_PID = 0;
  }
  print $S_HANDLE "reset\n";
}

sub hasMsg {
  return (exists $_[0]->{$MSGS} && scalar @{$_[0]->{$MSGS}});
}

sub enqueueMsg {
  my $self = shift;
  my $msg = shift;
  $self->{$MSGS} ||= [];
  push(@{$self->{$MSGS}},$msg);
}

sub dequeueMsg {
  return shift($_[0]->{$MSGS});
}

sub fileMsgs {
  my $self = shift;
  $self->enqueueMsg(sprintf("MIDI file is %s",$self->transcription->MIDIOut()));
  $self->enqueueMsg(sprintf("JSON file is %s",$self->transcription->JSONOut()));
  $self->enqueueMsg(sprintf("Quickfile is %s",$self->transcription->QuickOut()));
}

#####
#CMDS
#####
sub cmd_load {
  my $self    = shift;
  my $session = shift;
  my $file    = AutoHarp::Config::DataFile($session);
  $self->transcription(AutoHarp::Transcription->regenerate($file));
  $self->enqueueMsg("loaded $file");
}

sub cmd_qload {
  my $self    = shift;
  my $session = shift;
  my $file    = AutoHarp::Config::QuickFile($session);
  $self->transcription(AutoHarp::Transcription->regenerate($file));
  $self->enqueueMsg("loaded $file");
}

sub cmd_save {
  my $self = shift;

  if ($self->needReconduct()) {
    $self->reconduct();
  }
  
  $self->transcription()->write();
  $self->enqueueMsg("saved " . $self->transcription()->name());
  $self->fileMsgs();
}

sub cmd_name {
  my $self = shift;
  my $name = shift;
  if ($name) {
    $self->transcription()->name($name);
    $self->enqueueMsg("renamed session to $name");
  }
  $self->fileMsgs();
}

sub cmd_generate {
  my $self = shift;
  my $genreName = shift;
  my $genre;
  if (!$genreName) {
    $genre = pickOne(AutoHarp::Model::Genre->all());
    $genreName = $genre->name();
  } else {
    $genre = AutoHarp::Model::Genre->loadByName($genreName);
  }
  $self->enqueueMsg("Genre is $genreName");
  my $name = "$genreName-" . time();
  $self->enqueueMsg("Session is called $name");
  $self->transcription(AutoHarp::Transcription->new());

  my $guide = $self->transcription->constructGuideForGenre($genre);
  $self->transcription()->name($name);
  $self->transcription()->instruments(AutoHarp::Instrument->band());
  $self->transcription()->createMusic($guide);
  $self->transcription()->compose();
  $self->transcription()->conduct();
  
  $self->enqueueMsg(AutoHarp::Notation::CreateHeader($ATTR_CLOCK => $guide->clock,
						     $ATTR_GENRE => $genre,
						     $ATTR_SCALE => $guide->scale
						    )
		   );
}

sub cmd_list {
  my $self = shift;

  if ($self->needReconduct()) {
    $self->reconduct();
    
  }
  
  my $perfSegs = $self->transcription()->song()->segments();
  for (my $i = 0; $i < scalar @$perfSegs; $i++) {
    my $seg  =  $perfSegs->[$i];
    my $perfs = $seg->playerPerformances();
    my @insts = sort map {$_->{$ATTR_INSTRUMENT}->uid} @$perfs;
    printf "%2d) %12s (%6s): %s\n",($i + 1),$seg->songElement,$seg->musicTag,"(@insts)";
  }
}

sub cmd_play {
  my $self      = shift;
  my $what      = shift;
  my $who       = shift;

  if ($self->needReconduct()) {
    $self->reconduct();
  }
  
  my $song = $self->transcription->song();
  if (!$what) {
    $self->play($song);
  } else {
    my $segs = $self->specifiedArrayOfSegments($what, 1);
    if (!scalar @$segs) {
      die "Couldn't find $what";
    }
    my $subSong = AutoHarp::MusicBox::Song->new();
    foreach my $s (@$segs) {
      my $c = $s->clone();
      if ($who) {
	foreach my $p (@{$c->players()}) {
	  if ($p ne $who) {
	    $c->nukePerformer($p);
	  }
	}
      }
      if ($c->hasPerformances) {
	$subSong->addSegment($c);
      }
    }
    
    if (!scalar @{$subSong->segments()}) {
      die "filtering for player $who resulted in no music!";
    }
    print "SUBSONG:\n";
    foreach my $s (@{$subSong->segments()}) {
      printf "%d => %d\n",$s->time,$s->reach();
    }
    $self->play($subSong);
  }
  $self->enqueueMsg(sprintf("Playing%s from %s...",($who) ? " $who" : "", $what || 'start'));
}

sub cmd_stop {
  $_[0]->stop();
}

sub cmd_instruments {
  my $self = shift;
  my $insts = $self->transcription()->instruments();
  foreach my $ik (sort keys %$insts) {
    printf "%8s) %s",
      $ik,
      $insts->{$ik}->name();
    if ($insts->{$ik}->is($THEME_INSTRUMENT)) {
      printf " (%s)",$insts->{$ik}->themeIdentity();
    }
    print "\n";
  }
}

sub cmd_patch {
  my $self = shift;
  my $key  = shift;
  my $new  = join(" ",@_);
  my $inst = $self->transcription()->instruments()->{$key};
  if ($new) {
    my $was = $inst->patch();
    my $is  = $inst->choosePatch($new);
    if ($was == $is) {
      $self->enqueueMsg("$new did nothing.");
    } else {
      $self->setNeedReconduct();
    }      
  }
  $self->enqueueMsg(sprintf("%s's patch is %s",$key,
			    $MIDI::number2patch{$inst->patch()}
			   ));
}

sub cmd_stash {
  my $self = shift;
  my $what = shift;
  my $where = shift;
  if ($what) {
    if (!$where) {
      $where = 'A';
      while (exists $self->{$STASH}{$where}) {
	$where = chr(ord($where) + 1);
      }
    }
    my $thingToStash;
    if (AutoHarp::Notation::IsProgression($what)) {
      $thingToStash = AutoHarp::Event::Progression->fromString($what,
							       $self->guide);
    } elsif (AutoHarp::Notation::IsMelody($what)) {
      $thingToStash = AutoHarp::Event::Melody->fromString($what,
							  $self->guide);
    } elsif ($what =~ /^(\d+)$/) {
      $thingToStash = AutoHarp::Model::Loop->load($1)->events();
    } else {
      $self->enqueueMsg("Don't know how to stash a $what");
      return;
    }
    $thingToStash->dump();
    $self->{$STASH}{$where} = $thingToStash;
    $self->enqueueMsg(sprintf"%s(%s) stashed in slot $where");
  }
}

sub cmd_swap {
  my $self = shift;
  my $what = shift;
  my $withWhat = shift;

  my $swapees  = [];
  my $segments = $self->transcription()->song()->segments();
  my $idx      = ($what =~ /^(\d+)$/)[0];
  $idx--;
  
  for (my $i = 0; $i < scalar @$segments; $i++) {
    if ($i == $idx) {
      push(@$swapees,$segments->[$i]);
    } elsif ($segments->[$i]->songElement eq $what ||
	     $segments->[$i]->musicTag eq $what
	    ) {
      push(@$swapees,$segments->[$i]);
    }
  }
  if (!scalar @$swapees) {
    die "$what didn't give me anything";
  }
  if (!$self->{$STASH}{$withWhat}) {
    die "$withWhat isn't stashed";
  }
  my $withObj = $self->{$STASH}{$withWhat};
  my $subWith = $withObj->clone();
  $subWith->time(0);
  foreach my $s (@$swapees) {
    my $dur         = $s->musicBox->duration();
    my $bitToPlugIn = $subWith->subList(0,$dur);
    if (ref($withObj) =~ /$ATTR_PROGRESSION/) {
      $s->musicBox->progression($bitToPlugIn);
    } else {
      $s->musicBox->melody($bitToPlugIn);
    }

    if ($subWith->duration() > $dur) {
      $subWith = $subWith->subList($dur);
    } else {
      $subWith = $withObj->clone();
    }
    $subWith->time(0);

  }
  $self->setNeedReconduct();
  $self->enqueueMsg(sprintf("Swapped %s with contents of stash %s in %s segments",
			    ref($withObj),
			    $withWhat,
			    scalar @$swapees));
}

sub cmd_insert {
  my $self  = shift;
  my $what  = shift;
  my $where = shift;

  my $idx     = $what - 1;
  my $segment = $self->transcription->song->segments()->[$idx];
  my $new = $segment->clone();
  $self->transcription()->song->spliceSegment($segment->clone(),$where - 1);
  $self->setNeedReconduct();
  $self->enqueueMsg(sprintf("Copied %s into position %d",
			    $segment->musicBox->songElement(),
			    $where));
}

sub cmd_repeat {
  my $self = shift;
  my $what = shift;
  $self->cmd_insert($what, $what + 2);
  $self->cmd_insert($what + 1, $what + 3);
}

sub cmd_rethink {
  my $self  = shift;
  my $key   = shift;
  my $where = shift;
  my $segments = ($where) ? $self->specifiedArrayOfSegments($where) : $self->transcription()->song->segments();
  my $did = 0;
  foreach my $s (@$segments) {
    if ($s->hasPerformanceForPlayer($key)) {
      $s->clearPerformanceForPlayer($key);
      $did++;
    }
  }
  $self->setNeedReconduct();
  $self->enqueueMsg(sprintf("Zapped plays for %s in %d segment(s)",$key,$did));
  $self->enqueueMsg("Play or save to reconduct new performances");
}

sub cmd_silence {
  my $self  = shift;
  my $key   = shift;
  my $where = shift;
  my $segments = ($where) ? $self->specifiedArrayOfSegments($where) : $self->transcription()->song->segments();
  my $did = 0;
  foreach my $s (@$segments) {
    if ($s->hasPerformanceForPlayer($key)) {
      $s->nukePerformer($key);
      $did++;
    }
  }
  $self->enqueueMsg(sprintf("Silenced %s in %d segment(s)",$key,$did));
}

sub cmd_compel {
  my $self  = shift;
  my $key   = shift;
  my $where = shift;
  my $segments = ($where) ? $self->specifiedArrayOfSegments($where) : $self->transcription()->song->segments();
  my $did = 0;
  my $inst = $self->transcription()->instruments()->{$key};
  foreach my $s (@$segments) {
    if (!$s->hasPerformanceForPlayer($key)) {
      $s->addPerformer($inst);
      $did++;
    }
  }
  $self->setNeedReconduct();
  $self->enqueueMsg(sprintf("Compelled %s to play in %d segment(s)",$key,$did));
  $self->enqueueMsg("Play or save to reconduct new performances");
}

sub cmd_rerhythm {
  my $self  = shift;
  my $where = shift;
  $self->cmd_rethink($DRUM_LOOP,$where);
  $self->cmd_rethink($BASS_INSTRUMENT,$where);
  $self->cmd_rethink($RHYTHM_INSTRUMENT,$where);  
}

sub cmd_chords {
  my $self = shift;
  my $what = shift;
  my $seen = {};
  foreach my $seg (@{$self->transcription->song->segments()}) {
    if (!$what ||
	$what eq $seg->songElement() ||
	$what eq $seg->musicTag()) {
      my $str = $seg->musicBox()->progression->toString($seg->musicBox()->guide());
      if (!$seen->{$seg->musicTag()}{$seg->musicTag()}++) {
	printf "%s: %s\n",$seg->musicTag(),$str;
      }
    }
  }
}

sub cmd_dump {
  my $self = shift;
  my $what = shift;
  my $segments = ($what) ? $self->specifiedArrayOfSegments($what) :
    $self->transcription()->song->segments();
  if (!scalar @$segments) {
    die "$what didn't give me any segments";
  }
  
  foreach my $s (@$segments) {
    $s->dump();
  }
}
  
"Damn, I wish Abed was Batman.";

