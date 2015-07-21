package AutoHarp::Model::LoopAttribute;

use strict;
use base qw(AutoHarp::Model);

sub loadByAttributeValue {
  my $class = shift;
  my $attr = shift;
  my $val = shift;
  return $class->all({attribute => $attr, value => $val});
}

sub CreateTableCommands {
  my $CREATE_LOOP_ATTRIBUTES_TABLE = <<'STATEMENT';
CREATE TABLE loop_attributes (
  id int(11) NOT NULL AUTO_INCREMENT primary key,
  loop_id int(11) NOT NULL,
  attribute tinytext NOT NULL,
  value text,
  foreign key (loop_id) references loops(id)
)
STATEMENT
  return $CREATE_LOOP_ATTRIBUTES_TABLE;
}

"She lights the room when the day is dark.";
