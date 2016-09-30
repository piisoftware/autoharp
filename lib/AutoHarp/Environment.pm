package AutoHarp::Environment;

use strict;
use warnings;

use AutoHarp::Transcription;
use AutoHarp::Instrument;
use AutoHarp::Fuzzy;
use AutoHarp::Model::Genre;
use AutoHarp::Model::Loop;
use AutoHarp::Constants;
use AutoHarp::Config;

use Proc::ProcessTable;

use MIDI::Opus;
  
use base qw(AutoHarp::Class);

my $MSGS = 'messages';
my $PLAY_PID = 0;

$SIG{CHLD} = sub {
  print "$PLAY_PID CHILD DID A THING. FUCK YOU\n";
  my $proc_table = Proc::ProcessTable->new();
  foreach my $proc (@{$proc_table->table()}) {
    if ($proc->ppid == $PLAY_PID) {
      print "IT EXISTS. DOING NOTHING.\n";
      return;
    }
  }
  print "IT'S GONE. NULLING IT OUT\n";
  $PLAY_PID = 0;
};

sub transcription {
  return $_[0]->scalarAccessor('transcription',$_[1]);
}

sub band {
  my $self = shift;
  $self->{band} ||= AutoHarp::Instrument->band();
  return $self->{band};
}

sub instrument {
  my $self    = shift;
  my $id      = shift;
  my $newInst = shift;
  if ($newInst) {
    $self->band()->{$id} = $newInst;
  }
  return $self->band()->{$id};
}

sub play {
  my $self = shift;
  my $song = shift;
  if ($PLAY_PID) {
    $self->stop();
  }
  my $pid = fork();
  if ($pid) {
    $PLAY_PID = $pid;
  } else {
    my $player = AutoHarp::Config::Player();
    my $tmp = "/tmp/workshop.mid";
    $song->out($tmp, 1);
    exit(system("$player $tmp >/dev/null 2>&1"));
  }
}

sub stop {
  my $self = shift;
  if ($PLAY_PID) {
    $self->enqueueMsg("Stopping...\n");
    _recKill($PLAY_PID);
    $PLAY_PID = 0;
  }
}

sub _recKill {
  my $parent = shift; 
  my $proc_table = Proc::ProcessTable->new();
  my $signal = 15;
  print "KILLING $parent and its children\n";
  foreach my $proc (@{$proc_table->table()}) {
    if ($proc->ppid == $parent) {
      _recKill($proc->pid);
      kill($signal, $proc->pid);
    }
  }
}

sub cleanUp {
  $_[0]->stop();
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
  $self->enqueueMsg("MIDI file is %s\n",$self->transcription->MIDIOut());
  $self->enqueueMsg("JSON file is %s\n",$self->transcription->JSONOut());
  $self->enqueueMsg("Quickfile is %s\n",$self->transcription->QuickOut());
}

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
  $self->transcription()->write();
  $self->enqueueMsg("saved " . $self->transcription()->name());
  $self->fileMsgs();
}

sub cmd_name {
  my $self = shift;
  my $name = shift;
  $self->transcription()->name($name);
  $self->enqueueMsg("renamed session to $name");
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
  $self->transcription()->instruments($self->band());
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
  my $perfSegs = $self->transcription()->song()->segments();
  for (my $i = 0; $i < scalar @$perfSegs; $i++) {
    my $seg  =  $perfSegs->[$i];
    my $perfs = $seg->playerPerformances();
    my @insts = map {$_->{$ATTR_INSTRUMENT}->uid} @$perfs;
    printf "%2d) %10s (%10s): %s\n",($i + 1),$seg->songElement,$seg->musicTag,"(@insts)";
  }
}
    
sub cmd_playfrom {
  return $_[0]->play($_[1],1);
}

sub cmd_play {
  my $self      = shift;
  my $what      = shift;
  my $playToEnd = shift;
  my $song = $self->transcription->song();
  if (!$what) {
    $self->play($song);
  } else {
    my $startIdx = 0;
    my $segments = $song->segments();
    if ($what =~ /^(\d+)/) {
      $startIdx = $1 - 1;
    } else {
      for(my $i = 0; $i < scalar @$segments; $i++) {
	if ($segments->[$i]->songElement eq $what) {
	  $startIdx = $i;
	  last;
	}
      }
    }
    my $subsegs = [$segments->[$startIdx]];
    if ($playToEnd) {
      push(@$subsegs, @$segments[($startIdx + 1)..$#$subsegs]);
    }
    my $subSong = AutoHarp::MusicBox::Song->new();
    $subSong->segments($subsegs);
    $self->play($subSong);
  }
  $self->enqueueMsg(sprintf("Playing%s%s...",($playToEnd) ? ' from ' : '', ($what) ? " $what" : ''));
}

sub cmd_stop {
  $_[0]->stop();
}




"Damn, I wish Abed was Batman.";

