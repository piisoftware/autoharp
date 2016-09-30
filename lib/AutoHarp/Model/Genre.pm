package AutoHarp::Model::Genre;

use AutoHarp::Model::Loop;
use AutoHarp::Model::LoopGenre;
use AutoHarp::Constants;
use AutoHarp::Config;
use AutoHarp::Fuzzy;
use Carp;
use JSON;

use base qw(AutoHarp::Model);
use strict;

#a genre (by name, e.g. "funk") and its attributes
my $PATTERNS = 'patterns';

sub ValidGenre {
  my $genre = shift;
  foreach my $g (@{Genres()}) {
    if (lc($genre) eq lc($g->name)) {
      return $g->name;
    } else {
      my $tg = lc($genre);
      my $te = lc($g->name);
      $tg =~ s/\W//g;
      $te =~ s/\W//g;
      if ($tg eq $te) {
	return $g->name;
      }
    }
  }
  return;
}

sub Genres {
  return AutoHarp::Model::Genre->all();
}

sub loadByName {
  my $class  = shift;
  my $genre  = shift;
  return $class->loadBy(name => $genre);
}

#suggest a tempo and meter for this genre
sub suggestClock {
  my $self = shift;

  my $basePattern = pickOne(@{$self->getDrumLoops()});

  if (!$basePattern) {
    confess $self->name . " doesn't have drum any loops? Why is it a genre?";
  }
  
  my $tempo       = ($basePattern) ? $basePattern->tempo : 120;
  #muck with it by 10% or so
  $tempo = $tempo + (plusMinus() * int(rand(.1 * $tempo)));

  return AutoHarp::Clock->new($ATTR_TEMPO => $tempo,
			      $ATTR_METER => $basePattern->meter
			     );
}

sub getLoops {
  my $self = shift;
  my $type = shift;
  my $args = {genre_id => $self->id};
  my $lgs = AutoHarp::Model::LoopGenre->all($args);
  return [grep {!$type || $_->type eq $type} 
	  map {AutoHarp::Model::Loop->load($_->loop_id)}
	  @$lgs];
}

sub getDrumLoops {
  return $_[0]->getLoops($DRUM_LOOP);
}

sub addLoop {
  my $self    = shift;
  my $toAdd   = shift;
  my $lg = AutoHarp::Model::LoopGenre->loadOrCreate({genre_id => $self->id,
						     loop_id => $toAdd->id});
  return $lg->save();
}

sub delete {
  my $self = shift;
  #delete all loopGenres first 
  foreach my $lg (@{AutoHarp::Model::LoopGenre->all(genre_id => $self->id)}) {
    $lg->delete();
  }
  return $self->SUPER::delete();
}

sub CreateTableCommands {
  my $CREATE_GENRE_TABLE = <<'STATEMENT';
CREATE TABLE genres (
  id int(11) NOT NULL AUTO_INCREMENT primary key,
  name tinytext NOT NULL,
  description mediumtext
)
STATEMENT
  return $CREATE_GENRE_TABLE;
}

