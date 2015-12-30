package AutoHarp::Transcription;

#storing records of AutoHarp Songs since mid-2015

use AutoHarp::Config;
use AutoHarp::Composer;
use AutoHarp::Conductor;
use AutoHarp::Constants;
use AutoHarp::Generator;
use AutoHarp::Instrument;
use AutoHarp::Model::Loop;
use AutoHarp::Model::Genre;
use AutoHarp::Model::LoopFeedback;
use AutoHarp::Model::LoopAttribute;

use File::Copy;
use JSON;
use Carp;

use strict;
use base qw(AutoHarp::Class);

sub regenerate {
  my $class   = shift;
  my $session = shift;
  my $genre   = shift;
  my $self = $class->new();
  if (!-f $session) {
    $session = AutoHarp::Config::DataFile($session);
  }
  open(DATA, $session) or die "Couldn't find $session\n";
  my $str;
  while (<DATA>) {
    $str .= $_;
  }
  close(DATA);
  my $ds;
  eval {
    $ds = JSON->new->decode($str);
  }; 
  if ($@ || !$ds) {
    die "Couldn't parse the content in $session into valid json ($@)\n";
  }
  $self->name(($session =~ /(\w+)\.?\w*$/)[0]);
  if ($ds->{$ATTR_MUSIC}) {
    while (my ($e,$obj) = each %{$ds->{$ATTR_MUSIC}}) {
      $self->element($e,AutoHarp::MusicBox::Base->fromDataStructure($obj));
    }
  }
  if ($ds->{$ATTR_HOOK}) {
    my $h = AutoHarp::MusicBox::Hook->fromDataStructure($ds->{$ATTR_HOOK});
    if ($h->hasMelody()) {
      $self->hook($h);
    }
  }
  $self->completeMusicBase($genre);
  if ($ds->{$ATTR_INSTRUMENTS}) {
    $self->instruments({map {$_->uid => $_} 
			map {AutoHarp::Instrument->fromString($_)}
			@{$ds->{$ATTR_INSTRUMENTS}}});
  } else {
    $self->instruments(AutoHarp::Instrument->band());
  }

  my $conductor = AutoHarp::Conductor->new();
  my $song;
  if ($ds->{$ATTR_SONG}) {
    $song = $conductor->reconstructSong({$ATTR_SONG => $ds->{$ATTR_SONG},
					 $ATTR_MUSIC => $self->{$SONG_ELEMENT},
					 $ATTR_INSTRUMENTS => $self->instruments,
					 $ATTR_HOOK => $self->hook,
					 $ATTR_LOOPS => $ds->{$ATTR_LOOPS}
					}
				       );

  } else {
    my $composer = AutoHarp::Composer->new();
    while (my ($k,$v) = each %{$self->{$SONG_ELEMENT}}) {
      $composer->addMusic($v);
    }
    $composer->compose();
    $song = $conductor->conduct({$ATTR_COMPOSITION => $composer->composition(),
				 $ATTR_MUSIC => $self->{$SONG_ELEMENT},
				 $ATTR_INSTRUMENTS => $self->instruments(),
				 $ATTR_HOOK => $self->hook});
  }
  $self->song($song);
  #find a new name for this transcription
  my $oldJSON = $self->JSONOut();
  my $newName = $self->name();
  while (-f $oldJSON) {
    my $idx = ($newName =~ /(\d+)$/)[0];
    if ($idx) {
      $idx++;
      $newName =~ s/\d+$/$idx/;
    } else {
      $newName .= "_1";
    }
    $oldJSON = AutoHarp::Config::DataFile($newName);
  }
  #set the name here, rather than calling the function
  #that way we don't accidentally rename the existing file
  $self->{$ATTR_NAME} = $newName;
  $self->{$ATTR_LOOPS} = $ds->{$ATTR_LOOPS};
  return $self;
}

sub completeMusicBase {
  my $self  = shift;
  my $genre = shift;
  my $gen = AutoHarp::Generator->new();
  my $guide;

  my $source;
  while (my ($k, $base) = each %{$self->{$SONG_ELEMENT}}) {
    eval {
      $base->tag($k);
      if ($base->hasProgression()) {
	if (!$base->hasMelody()) {
	  $gen->melodize($base);
	} 
      } else {
	if (!$base->hasMelody()) {
	  $gen->generateMelody($base);
	} 
	$gen->harmonize($base);
      }
      $base->genre($genre) if ($genre);
      $guide ||= $base->guide()->clone();
      #TODO--detect requested re-keyings?
    };
    if ($@) {
      confess "Couldn't reconstruct $k: $@\n";
    }
  }
  my $hook = $self->hook();
  if (!$hook && !$guide) {
    confess "Got no source music of any kind. Can't regenerate";
  }
  my $source;
  if ($hook) {
    my $bars;
    if ($guide) {
      $bars = $guide->measures();
      $bars *= 2 while ($bars < 8);
    } else {
      $bars = 8;
    }
    $source  = $hook->clone();
    $guide   = $hook->guide->clone();
    $guide->measures($bars);
  }

  foreach my $elt ($SONG_ELEMENT_VERSE,
		   $SONG_ELEMENT_CHORUS,
		   $SONG_ELEMENT_BRIDGE) {
    if (!$self->element($elt)) {
      my $m = $gen->generateMusic($guide,$source);
      $m->tag($elt);
      $m->genre($genre) if ($genre);
      $self->element($elt, $m);
      $source ||= $m;
    } 
    $source ||= $self->element($elt);
  }
  if (!$hook) {
    $self->hook($gen->generateHook($source));
  }
}

sub verse {
  my $self = shift;
  return $self->element($SONG_ELEMENT_VERSE, @_);
}

sub chorus {
  my $self = shift;
  return $self->element($SONG_ELEMENT_CHORUS, @_);
}

sub bridge {
  my $self = shift;
  return $self->element($SONG_ELEMENT_BRIDGE, @_);
}

sub hook {
  my $self = shift;
  return $self->objectAccessor($ATTR_HOOK, @_);
}

sub song {
  my $self = shift;
  return $self->objectAccessor($ATTR_SONG, @_);
}

sub instruments {
  my $self = shift;
  my $insts = shift;
  if (ref($insts) eq 'HASH') {
    $self->{$ATTR_INSTRUMENTS} = $insts;
  }
  return $self->{$ATTR_INSTRUMENTS};
}

sub element {
  my $self = shift;
  my $elt_name = shift;
  my $elt_val = shift;
  if ($elt_name) {
    if (ref($elt_val)) {
      $self->{$SONG_ELEMENT}{$elt_name} = $elt_val;
    }
    return $self->{$SONG_ELEMENT}{$elt_name};
  }
  return;
}

sub name {
  my $self = shift;
  my $name = shift;
  if (!$self->{$ATTR_NAME}) {
    if ($self->song()) {
      $self->{$ATTR_NAME} = $self->song()->name();
    }
  }
  if ($name) {
    if ($self->{$ATTR_NAME}) {
      #we gotta move everything!
      my $midiNew = AutoHarp::Config::MidiFile($name);
      my $midiOld = $self->MIDIOut();
      if (-f $midiOld) {
	File::Copy::move($midiOld,$midiNew);
      }
      my $jsonNew = AutoHarp::Config::DataFile($name);
      my $jsonOld = $self->JSONOut();
      if (-f $jsonOld) {
	File::Copy::move($jsonOld,$jsonNew);
      }
      #get all the loops in this song and change their names as well
      foreach my $la (@{AutoHarp::Model::LoopAttribute->all({attribute => $ATTR_AUTOHARP_SONG, value => $self->{$ATTR_NAME}})}) {
	$la->value($name);
	$la->save();
      }
    }
    $self->{$ATTR_NAME} = $name;
  }
  return $self->{$ATTR_NAME};
}

sub write {
  my $self        = shift;
  my $sessionName = $self->name(shift);
  my $song        = $self->song();
  my $loops       = {};

  if (!$sessionName) {
    confess "Need a session name!";
  }

  #go through the song and save all the loops that we might later be interested in
  my $machineGenre = AutoHarp::Model::Genre->loadOrCreate({name => $ATTR_MACHINE_GENRE});
  $machineGenre->save();

  if (!$ENV{AUTOHARP_NO_LOOPS}) {
    foreach my $seg (@{$song->segments}) {
      my $guide = $seg->music->guide();
      my $segGenre = $seg->genre();
      foreach my $ppData (@{$seg->playerPerformances}) {
	my $inst = $ppData->{$ATTR_INSTRUMENT};
	my $play = $ppData->{$ATTR_MELODY};
	if ($self->{$ATTR_LOOPS} &&
	    exists $self->{$ATTR_LOOPS}{$seg->uid} &&
	    $self->{$ATTR_LOOPS}{$seg->uid}{$inst->uid}) {
	  #this is already a loop--no need to write it
	  next;
	}
	if ($inst->is($THEME_INSTRUMENT) 
	    || $inst->is($LEAD_INSTRUMENT)
	    || $inst->is($HOOK_INSTRUMENT)
	    || $inst->is($RHYTHM_INSTRUMENT)
	    || $inst->isDrums()) {
	  my $loop = $play->transcribe($guide);
	  $loop->type(($inst->isDrums()) ? $GENERATED_DRUM_LOOP : $inst->instrumentClass());
	  $loop->save();
	  $loop->addToGenre($machineGenre);
	  if ($segGenre) {
	    $loop->addToGenre($segGenre);
	  }
	  $loop->addAttribute($ATTR_AUTOHARP_SONG, $sessionName);
	  $loops->{$seg->uid}{$inst->uid} = $loop->id();
	}
      }
    }
  }

  my $outJson = $self->JSONOut();
  my $outMIDI = $self->MIDIOut();
  $song->out($outMIDI);
  open(FILE, ">$outJson") or confess "Couldn't open $outJson for writing: $!\n";
  my $mData = {map {$_ => $self->{$SONG_ELEMENT}{$_}->toDataStructure()} 
	       keys %{$self->{$SONG_ELEMENT}}
	      }; 

  my $sData = $song->toDataStructure();
  my $hData = $self->hook()->toDataStructure();
  my $outData = 
    {
     $ATTR_MUSIC => $mData, 
     $ATTR_HOOK => $hData,
     $ATTR_INSTRUMENTS => 
     [
      map {$_->toString()} 
      sort {$a->uid cmp $b->uid} 
      values %{$self->{$ATTR_INSTRUMENTS}}
     ],
     $ATTR_SONG => $sData,
     $ATTR_LOOPS => $loops
    };
  print FILE JSON->new()->pretty()->canonical()->encode($outData);
  close(FILE);
  return 1;
}

sub nuke {
  my $self = shift;
  unlink($self->JSONOut);
  unlink($self->MIDIOut);
  #mark the loops as unliked
  foreach my $la (@{AutoHarp::Model::LoopAttribute->all({attribute => $ATTR_AUTOHARP_SONG, value => $self->name})}) {
    my $f = AutoHarp::Model::LoopFeedback->new({loop_id => $la->loop_id});
    $f->is_liked(0);
    $f->save();
  }
}

sub like {
  my $self = shift;
  #mark the loops as liked! Huzzah!
  foreach my $la (@{AutoHarp::Model::LoopAttribute->all({attribute => $ATTR_AUTOHARP_SONG, value => $self->name})}) {
    my $f = AutoHarp::Model::LoopFeedback->new({loop_id => $la->loop_id});
    $f->is_liked(1);
    $f->save();
  }
}

sub JSONOut {
  return AutoHarp::Config::DataFile($_[0]->name);
}

sub MIDIOut {
  return AutoHarp::Config::MidiFile($_[0]->name);
}

"I am afraid you don't hold my best interest";
