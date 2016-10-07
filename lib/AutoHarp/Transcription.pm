package AutoHarp::Transcription;

#storing records of AutoHarp Songs since mid-2015

use AutoHarp::Config;
use AutoHarp::Composer;
use AutoHarp::Conductor;
use AutoHarp::Constants;
use AutoHarp::Generator;
use AutoHarp::Instrument;
use AutoHarp::Fuzzy;

use AutoHarp::Model::Loop;
use AutoHarp::Model::Genre;
use AutoHarp::Model::LoopFeedback;
use AutoHarp::Model::LoopAttribute;

use Data::Dumper;
use File::Copy;
use JSON;
use Carp;

use strict;
use base qw(AutoHarp::Class);

my $DEFAULT_BARS = 8;

sub regenerate {
  my $class   = shift;
  my $file    = shift;
  
  if ($file =~ /\.quick$/) {
    return $class->regenerateFromQuickFile($file, @_);
  }
  return $class->regenerateFromJSON($file, @_);
}

sub regenerateFromQuickFile {
  my $class = shift;
  my $file = shift;

  open(QUICK, $file) or die "Couldn't find $file\n";

  my $self = $class->new();
  $self->name(($file =~ /(\w+)\.?\w*$/)[0]);

  my $guide = AutoHarp::Events::Guide->new();
  my $inComp;
  my $composition = [];
  while(<QUICK>) {
    chomp;
    if (AutoHarp::Notation::IsHeader($_)) {
      $guide = AutoHarp::Events::Guide->fromAttributes(AutoHarp::Notation::ParseHeader($_));
    } elsif (/(\w+):\s*(.+)/) {
      my $key = $1;
      my $info = $2;
      if (AutoHarp::Notation::IsProgression($info)) {
	my $progression = AutoHarp::Events::Progression->fromString($info, $guide);
	$self->element($key,
		       AutoHarp::MusicBox::Base->fromProgression
		       ($progression,$guide)
		      );
      } elsif ($key eq $ATTR_HOOK && AutoHarp::Notation::IsMelody($info)) {
	$self->hook(AutoHarp::MusicBox::Hook->fromString($info, $guide));
      } else {
	die "Unrecognized key $key in quickfile $file\n";
      }
    } elsif (/$ATTR_COMPOSITION/) {
      $inComp = 1;
    } elsif (/^\w+$/ && $inComp) {
      my $mTag = $_;
      my $elt  = $self->element($mTag);
      if (!$elt) {
	$elt  = $self->verse();
	$mTag = $SONG_ELEMENT_VERSE;
      }

      if (!$elt) {
	die "Unrecognized song element $_ in quickfile $file\n";
      }
      
      push(@$composition,
	   AutoHarp::Composer::CompositionElement->new
	   ($ATTR_MUSIC_TAG => $mTag,
	    $SONG_ELEMENT => $_,
	   )
	  );
    }
  }
  close(QUICK);

  $self->instruments(AutoHarp::Instrument->band());
  $self->completeMusicBase($guide);
  $self->compose($composition);
  $self->conduct();
  $self->rename();
}

sub regenerateFromJSON {
  my $class    = shift;
  my $file     = shift;
  my $newGenre = shift;

  my $oldGenre;
  
  my $self = $class->new();
  open(DATA, $file) or die "Couldn't find $file\n";
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
    die "Couldn't parse the content in $file into valid json ($@)\n";
  }

  $self->name(($file =~ /(\w+)\.?\w*$/)[0]);
  $self->loops($ds->{$ATTR_LOOPS});

  my $guide; 
  if ($ds->{$ATTR_MUSIC}) {
    while (my ($e,$obj) = each %{$ds->{$ATTR_MUSIC}}) {
      my $se = AutoHarp::MusicBox::Base->fromDataStructure($obj);
      $self->element($e,$se);
      $oldGenre = $se->genre        if ($e eq $SONG_ELEMENT_VERSE || !$oldGenre);
      $guide    = $se->guide->clone if ($e eq $SONG_ELEMENT_VERSE || !$guide);
    }
  }
    
  if (!$oldGenre && !$newGenre) {
    #no old and no new: let's choose one now
    $newGenre = pickOne(AutoHarp::Model::Genre->all());
  }

  if (!$guide) {
    $guide = $self->constructGuideForGenre($newGenre || $oldGenre);
  }

  if ($newGenre) {
    #let's go ahead and pick a new tempo
    #(but don't change the meter, cause that'd be insane)

    my $nc = __chooseClockForGenre($newGenre);

    $guide->genre($newGenre);
    $guide->clock->tempo($nc->tempo);
    
    while (my ($k, $v) = each %{$self->{$SONG_ELEMENT}}) {
      $v->genre($newGenre);
      $v->clock->tempo($nc->tempo);
    }
    
    #and let's get rid of the drum and rhythm loops
    #since they tend to define the feel of the piece
    if ($self->loops) {
      while (my ($k,$insts) = each %{$self->loops}) {
	delete $insts->{$DRUM_LOOP};
	delete $insts->{$RHYTHM_INSTRUMENT};
      }
    }
  }
  
  if ($ds->{$ATTR_HOOK}) {
    my $h = AutoHarp::MusicBox::Hook->fromDataStructure($ds->{$ATTR_HOOK});
    if ($h->hasMelody()) {
      $self->hook($h);
    }
  }
  $self->completeMusicBase($guide);
  if ($ds->{$ATTR_INSTRUMENTS}) {
    $self->instruments({map {$_->uid => $_} 
			map {AutoHarp::Instrument->fromString($_)}
			@{$ds->{$ATTR_INSTRUMENTS}}});
  } else {
    $self->instruments(AutoHarp::Instrument->band());
  }

  $self->compose($ds->{$ATTR_COMPOSITION});
  $self->conduct();
  $self->rename();
}

sub compose {
  my $self = shift;
  my $ds = shift;
  if ($ds && scalar @$ds) {
    $self->{$ATTR_COMPOSER} = AutoHarp::Composer->fromDataStructure($ds);
  } else {
    $self->{$ATTR_COMPOSER} = AutoHarp::Composer->new();
    while (my ($k,$v) = each %{$self->{$SONG_ELEMENT}}) {
      $self->{$ATTR_COMPOSER}->addMusicTag($k);
    }
    $self->{$ATTR_COMPOSER}->compose();
  }
}

sub conduct {
  my $self = shift;
  my $conductor = AutoHarp::Conductor->new();
  my $song = $conductor->conduct({$ATTR_COMPOSER => $self->{$ATTR_COMPOSER},
				  $ATTR_MUSIC => $self->{$SONG_ELEMENT},
				  $ATTR_INSTRUMENTS => $self->instruments(),
				  $ATTR_HOOK => $self->hook,
				  $ATTR_LOOPS => $self->loops,
				 });
  $self->song($song);
}

sub rename {
  my $self = shift;
  #find a new name for this transcription
  my $oldJSON = $self->JSONOut();
  my $oldQuick = $self->QuickOut();
  
  my $newName = $self->name();
  while (-f $oldJSON || -f $oldQuick) {
    my $idx = ($newName =~ /(\d+)$/)[0];
    if ($idx) {
      $idx++;
      $newName =~ s/\d+$/$idx/;
    } else {
      $newName .= "_1";
    }
    $oldJSON  = AutoHarp::Config::DataFile($newName);
    $oldQuick = AutoHarp::Config::QuickFile($newName);
  }
  #set the name here, rather than calling the function
  #that way we don't accidentally rename the existing file
  $self->{$ATTR_NAME} = $newName;
  return $self;
}

sub constructGuideForGenre {
  my $self  = shift;
  my $genre = shift;
  my $clock = __chooseClockForGenre($genre);
  my $scale = __chooseScale();
  return AutoHarp::Events::Guide->fromAttributes($ATTR_BARS => $DEFAULT_BARS,
						 $ATTR_CLOCK => $clock,
						 $ATTR_SCALE => $scale,
						 $ATTR_GENRE => $genre
						);
}

sub createMusic {
  return $_[0]->completeMusicBase($_[1]);
}

sub completeMusicBase {
  my $self  = shift;
  my $guide = shift;

  my $gen   = AutoHarp::Generator->new();
  my $genre = $guide->genre();
  
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
      $base->genre($genre);
      #TODO--detect requested re-keyings?
    };
    if ($@) {
      confess "Couldn't reconstruct $k: $@\n";
    }
  }
  my $hook = $self->hook();
  my $source = ($hook) ? $hook->clone() : undef;

  foreach my $elt ($SONG_ELEMENT_VERSE,
		   $SONG_ELEMENT_CHORUS,
		   $SONG_ELEMENT_BRIDGE) {
    if (!$self->element($elt)) {
      my $m = $gen->generateMusic($guide,$source);
      $m->tag($elt);
      $m->genre($genre) if ($genre);
      $self->element($elt, $m);
      $source ||= $m;
    } elsif (!$source) {
      $source = $self->element($elt);
    }
  }
  if (!$hook) {
    $self->hook($gen->generateHook($source));
  }
  $self->{$ATTR_GUIDE} = $guide;
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

sub loops {
  $_[0]->scalarAccessor($ATTR_LOOPS,$_[1]);
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
      my $quickNew = AutoHarp::Config::QuickFile($name);
      my $quickOld = $self->QuickOut();
      if (-f $quickOld) {
	File::Copy::move($quickOld, $quickNew);
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
      my $guide = $seg->musicBox->guide();
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

  $self->loops($loops);
  $song->out($self->MIDIOut());
  $self->writeJSONFile();
  eval {
    $self->writeQuickFile();
  };
  if ($@) {
    print "WHAT THE FUCKING FUCK?: $@\n";
  }	   
}

sub writeJSONFile {
  my $self  = shift;
  my $outJson = $self->JSONOut();
  open(FILE, ">$outJson") or confess "Couldn't open $outJson for writing: $!\n";
  my $mData = {map {$_ => $self->{$SONG_ELEMENT}{$_}->toDataStructure()} 
	       keys %{$self->{$SONG_ELEMENT}}
	      }; 
  my $cData = [];
  foreach my $s (@{$self->song()->segments()}) {
    if ($s->segmentIndex == 0) {
      my $c = 
      push(@$cData,AutoHarp::Composer::CompositionElement->fromPerformanceSegment($s));
    } else {
      $cData->[-1]->addSegmentUid($s->uid);
      $cData->[-1]->transitionOut($s->transitionOut);
    }
  }

  my $outData = 
    {
     $ATTR_MUSIC => $mData, 
     $ATTR_HOOK => $self->hook()->toDataStructure(),
     $ATTR_INSTRUMENTS => 
     [
      map {$_->toString()} 
      sort {$a->uid cmp $b->uid} 
      values %{$self->{$ATTR_INSTRUMENTS}}
     ],
     $ATTR_COMPOSITION => [map {$_->toDataStructure()} @$cData],
     $ATTR_LOOPS => $self->loops()
    };
  print FILE JSON->new()->pretty()->canonical()->encode($outData);
  close(FILE);
  return 1;
}

sub writeQuickFile {
  my $self = shift;
  my $outQuick = $self->QuickOut();
  open(Q, ">$outQuick") or confess "Couldn't open $outQuick for writing: $!\n";
  my $verse = $self->verse();
  printf Q "%s\n",AutoHarp::Notation::CreateHeader($ATTR_CLOCK => $verse->clock(),
						   $ATTR_SCALE => $verse->scale(),
						   $ATTR_GENRE => $verse->genre());
  
  while (my ($k,$box) = each %{$self->{$SONG_ELEMENT}}) {
    printf Q "%s: %s\n",$k,$box->progression->toString($box->guide);
  }
  if ($self->hook) {
    printf Q "%s: %s\n",$ATTR_HOOK,$self->hook->toString();
  }
  print Q "$ATTR_COMPOSITION:\n";
  foreach my $s (@{$self->song()->segments()}) {
    if ($s->segmentIndex == 0) {
      printf Q "%s\n",$s->songElement;
    }
  }
  close(Q);
}
  
sub nuke {
  my $self = shift;
  unlink($self->JSONOut);
  unlink($self->MIDIOut);
  unlink($self->QuickOut);
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

sub QuickOut {
  return AutoHarp::Config::QuickFile($_[0]->name);
}

sub __chooseClockForGenre {
  my $genre = shift;
  if ($genre) {
    return $genre->suggestClock();
  }
  my $loop = pickOne(AutoHarp::Model::Loop->all({type => $DRUM_LOOP}));
  return AutoHarp::Clock->new($ATTR_METER => $loop->meter,
			      $ATTR_TEMPO => $loop->tempo);
}

sub __chooseScale {
  #key frequency taken from hooktheory.com
  my @wheel = map {{pct => $_->[0], key => $_->[1]}} ([26, 'C'],
						      [12, 'G'],
						      [10, 'E flat'],
						      [9, 'F'],
						      [8, 'D'],
						      [8, 'A'],
						      [7, 'E'], 
						      [7, 'D flat'],
						      [5, 'B flat'],
						      [4, 'A flat'],
						      [2, 'B'],
						      [2, 'F sharp']);
  my $seed = int(rand() * 100);
  my $pct  = 0;
  my $key;
  foreach my $w (@wheel) {
    $pct += $w->{pct};
    if ($seed < $pct) {
      $key = $w->{key};
      last;
    }
  }
  $key ||= $wheel[0]->{key};
  my $scale = AutoHarp::Scale->new($key);
  if (sometimes) {
    #go minor
    $scale->toRelativeMinor();
  }
  return $scale;
}

"I am afraid you don't hold my best interest";
