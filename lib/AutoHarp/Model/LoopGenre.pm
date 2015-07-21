package AutoHarp::Model::LoopGenre;

use strict;
use base qw(AutoHarp::Model);

sub CreateTableCommands {
  my $CREATE_LOOP_GENRE_TABLE = <<'STATEMENT';
CREATE TABLE loop_genres (
  id int(11) NOT NULL AUTO_INCREMENT primary key,
  genre_id int(11) NOT NULL,
  loop_id int(11) NOT NULL,
  foreign key (genre_id) references genres(id),
  foreign key (loop_id) references loops(id)
)
STATEMENT
  return $CREATE_LOOP_GENRE_TABLE;
}

"Oh no that Stoner's Down";
