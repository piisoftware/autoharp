package AutoHarp::Model::Loop;

use AutoHarp::Model::LoopAttribute;
use AutoHarp::Model::LoopFeedback;
use AutoHarp::Model::LoopGenre;
use AutoHarp::Model::Genre;

use AutoHarp::Constants;
use AutoHarp::Events::DrumTrack;
use AutoHarp::Events;
use AutoHarp::Clock;
use AutoHarp::Scale;
use MIME::Base64;
use IO::String;
use IO::Pipe;

use MIDI;
use Carp;

use Time::HiRes;

use base qw(AutoHarp::Model);
use strict;

my $TEMPO_MATCH_PCT = .15; #anything within 15%? Extra grotty SWAG right here

sub loadByTypeAndMeter {
  my $class = shift;
  my $type  = shift;
  my $meter = shift;
  return $class->all({type => $type, meter => $meter});
}

sub fromFile {
  my $class   = shift;
  my $file    = shift;
  my $verbose = shift;
  my $events;
  eval {
    $events = AutoHarp::Events->fromFile($file);
  };

  if ($@) {
    print "error importing: $@\n" if ($verbose);
    return;
  }
  if (scalar @$events > 2) {
    print "file contains more than one track, ignoring\n" if ($verbose);
    return;
  }
  
  my $guide = $events->[0];
  my $track = $events->[1];
  #all is well, so grab the midi direct from the file
  open(MIDI, "$file");
  binmode MIDI;
  my ($buf, $data, $n);
  while (($n = read MIDI, $data, 4) != 0) {
    $buf .= $data;
  }
  close(MIDI);
  my $self = $class->new({meter => $guide->clock->meter(),
			  tempo => $guide->clock->tempo(),
			  scale => $guide->scale->key(),
			  midi => encode_base64($buf),
			  type => ($track->isPercussion) ? $DRUM_LOOP : $ATTR_MUSIC
			 }
			);
  return $self;
}

sub fromOpus {
  my $class  = shift;
  my $opus   = shift;
  my $type   = shift;
  my $midiBuffer;

  #open a pipe in order to read (from the opus)
  #and write (to a buffer that we can save to the DB) 
  my $pipe = IO::Pipe->new();
  my $pid = fork();

  if($pid) { 
    # Parent is the reader
    $pipe->reader();
    #Wait for the child to finish
    waitpid($pid, 0);
    #write to the buffer once it's done
    my ($n,$buff);
    while($n = read($pipe,$buff,100)) {
      $midiBuffer .= $buff;
    }
  } else {
    $pipe->writer();
    $opus->write_to_handle($pipe);
    exit(0);
  }

  my $loop   = $class->new();
  my $events = AutoHarp::Events->fromOpus($opus);
  my $guide  = $events->[0];
  
  $loop->type($type || $ATTR_MUSIC);
  $loop->meter($guide->clock->meter);
  $loop->tempo($guide->clock->tempo);
  $loop->scale($guide->scale->key);
  $loop->midi(encode_base64($midiBuffer));
  return $loop;
}

sub isDrumLoop {
  return ($_[0]->type eq $DRUM_LOOP);
}

#for an extremely abstract definition of "match"
sub matchesTempo {
  my $self = shift;
  my $tempo = shift;
  return (abs(1 - $self->tempo / $tempo) <= $TEMPO_MATCH_PCT);
}

sub events {
  my $self = shift;
  my $data = $self->eventSet(@_);
  return ($data) ? $data->[1] : undef;
}

sub guide {
  my $self = shift;
  my $data = $self->eventSet(@_);
  return ($data) ? $data->[0] : undef;
}

sub bars {
  my $self = shift;
  my $val  = shift;
  my $eSet = $self->eventSet();
  my $curr = $eSet->[0]->bars();
  if (length($val) && $val != $curr) {
    $eSet->[0]->bars($val);
    $eSet->[1]->truncateToTime($eSet->[0]->reach());
    my $opus = MIDI::Opus->new({tracks => [map {$_->track} @$eSet],
				ticks => $TICKS_PER_BEAT,
				format => 1});
    my $truncated = ref($self)->fromOpus($opus);
    $self->midi($truncated->midi);
    $curr = $val;
  } 
  return $curr;
}

sub toOpus {
  my $self = shift;
  my $handle = IO::String->new(decode_base64($self->midi));
  return MIDI::Opus->new({'from_handle' => $handle});
}

#some loops come in as channel 0, even if they are meant to be drums
sub toDrumLoop {
  my $self = shift;
  if ($self->isDrumLoop()) {
    return;
  }
  my $eSet = $self->eventSet();
  $eSet->[1]->channel($PERCUSSION_CHANNEL);
  my $opus = MIDI::Opus->new({tracks => [map {$_->track} @$eSet],
			      ticks => $TICKS_PER_BEAT,
			      format => 1});
  my $new = ref($self)->fromOpus($opus);
  $self->midi($new->midi);
  $self->type($DRUM_LOOP);
  return 1;
}

sub eventSet {
  my $self    = shift;
  my $verbose = shift;
  my $eventSet;
  eval {
    my $handle = IO::String->new(decode_base64($self->midi));
    my $opus = MIDI::Opus->new({'from_handle' => $handle});
    if ($self->isDrumLoop()) {
      $eventSet = AutoHarp::Events::DrumTrack->fromOpus($opus);
    } else {
      $eventSet = AutoHarp::Events::Melody->fromOpus($opus);
    }
  };
  if ($@ && $verbose) {
    print "Couldn't generate events from loop: $@";
  }
  return $eventSet;
}

#get the clock from this loop's metadata
sub getClock {
  my $self = shift;
  return AutoHarp::Clock->new($ATTR_METER => $self->meter(),
			      $ATTR_TEMPO => $self->tempo());
}

sub getScale {
  my $self = shift;
  return AutoHarp::Scale->new($ATTR_KEY => $self->key());
}

sub addToGenre {
  my $self = shift;
  my $genre = shift;
  my $lg = AutoHarp::Model::LoopGenre->loadOrCreate({loop_id => $self->id, 
						     genre_id => $genre->id});
  return $lg->save();
}

sub addAttribute {
  my $self = shift;
  my $attr = shift;
  my $val  = shift;
  if ($attr && length($val)) {
    my $attrVal = AutoHarp::Model::LoopAttribute->loadOrCreate
      (
       {loop_id => $self->id,
	attribute => $attr,
	value => $val}
      );
    return $attrVal->save();
  }
  confess "Cannot add attributes without, you know, attributes";
}

sub removeAttribute {
  my $self = shift;
  my $attr = shift;
  my $count = 0;
  if ($attr) {
    my $all = AutoHarp::Model::LoopAttribute->all({loop_id => $self->id,
						   attribute => $attr});
    foreach my $r (@$all) {
      $r->delete();
      $count++;
    }
  }
  return $count;
}

sub getSongElements {
  my $self = shift;
  return [map {$_->value} @{$self->getAttributes($SONG_ELEMENT)}];
}

sub getBuckets {
  my $self = shift;
  return [map {$_->value} @{$self->getAttributes($ATTR_BUCKET)}];
}

sub getSongAffiliations {
  my $self = shift;
  return [map {$_->value} @{$self->getAttributes($ATTR_SONG)}];
}

sub matchesSongElement {
  my $self = shift;
  my $elt  = shift;
  return ($elt && scalar grep {$elt eq $_} @{$self->getSongElements()});
}

sub isFill {
  my $self = shift;
  return $self->matchesSongElement($SONG_ELEMENT_FILL);
}

sub getAttributes {
  my $self = shift;
  my $attr = shift;
  my $args = {loop_id => $self->id};
  if ($attr) {
    $args->{attribute} = $attr;
  }
  return AutoHarp::Model::LoopAttribute->all($args);
}

sub genres {
  my $self = shift;
  return [
	  map {AutoHarp::Model::Genre->load($_->genre_id)}
	  @{AutoHarp::Model::LoopGenre->all({loop_id => $self->id})}
	 ];
}

sub matchesGenre {
  my $self = shift;
  my $genre = shift;
  return (scalar grep {$_->id == $genre->id} @{$self->genres});
}

#this loop came out of the machine, 
#and belongs to no other genre
sub isMachined {
  my $gs = $_[0]->genres();
  return (scalar @$gs == 1 && $gs->[0]->name eq $ATTR_MACHINE_GENRE);
}

sub delete {
  my $self = shift;
  #delete all loopGenres...
  foreach my $lg (@{AutoHarp::Model::LoopGenre->all(loop_id => $self->id)}) {
    $lg->delete();
  }
  #and all loopAttributes...
  foreach my $la (@{AutoHarp::Model::LoopAttribute->all(loop_id => $self->id)}) {
    $la->delete();
  }
  #and all loopFeedback
  foreach my $lf (@{AutoHarp::Model::LoopFeedback->all(loop_id => $self->id)}) {
    $lf->delete();
  }
  return $self->SUPER::delete();
}

sub CreateTableCommands {
  my $CREATE_LOOPS_TABLE = <<'STATEMENT';
CREATE TABLE loops (
  id int(11) NOT NULL AUTO_INCREMENT primary key,
  midi longblob,
  meter varchar(5),
  tempo smallint,
  scale tinytext,
  type tinytext
)
STATEMENT
  return $CREATE_LOOPS_TABLE;
}

"Alexander you forgot to be in time";
