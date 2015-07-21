package AutoHarp::Model::Loop;

use AutoHarp::Model::LoopAttribute;
use AutoHarp::Model::LoopGenre;
use AutoHarp::Model::Genre;

use AutoHarp::Constants;
use AutoHarp::Events::DrumTrack;
use AutoHarp::Events;
use AutoHarp::Clock;
use AutoHarp::Scale;
use IO::String;
use MIME::Base64;
use Carp;

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
  my $tracks;
  eval {
    $tracks = AutoHarp::Events->fromFile($file);
  };

  if ($@) {
    print "error importing: $@\n" if ($verbose);
    return;
  }
  if (scalar @$tracks > 2) {
    print "file contains more than one track, ignoring" if ($verbose);
    return;
  }
  
  my $guide = $tracks->[0];
  my $track = $tracks->[1];
  #all is well, so grab the midi direct from the file
  open(MIDI, "$file");
  binmode MIDI;
  my ($buf, $data, $n);
  while (($n = read MIDI, $data, 4) != 0) {
    $buf .= $data;
  }
  close(MIDI);
  my $self = $class->new({bars => $guide->bars(),
			  meter => $guide->clock->meter(),
			  tempo => $guide->clock->tempo(),
			  scale => $guide->scale->key(),
			  midi => encode_base64($buf),
			  type => ($track->isPercussion) ? $DRUM_LOOP : $ATTR_MUSIC
			 }
			);
  return $self;
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

sub track {
  my $self    = shift;
  my $verbose = shift;
  my $track;
  eval {
    my $handle = IO::String->new(decode_base64($self->midi));
    my $opus = MIDI::Opus->new({'from_handle' => $handle});
    my $tracks;
    if ($self->isDrumLoop()) {
      $tracks = AutoHarp::Events::DrumTrack->fromOpus($opus);
    } else {
      $tracks = AutoHarp::Events->fromOpus($opus);
    }
    $track = $tracks->[1];
  };
  if ($@ && $verbose) {
    print "Couldn't generate track from loop: $@";

  }
  return $track;
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
  return $self->SUPER::delete();
}

sub CreateTableCommands {
  my $CREATE_LOOPS_TABLE = <<'STATEMENT';
CREATE TABLE loops (
  id int(11) NOT NULL AUTO_INCREMENT primary key,
  bars tinyint,
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
