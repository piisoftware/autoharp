package AutoHarp::Model::LoopFeedback;

use strict;
use base qw(AutoHarp::Model);

sub CreateTableCommands {
  my $CREATE_LOOP_FEEDBACK_TABLE = <<'STATEMENT';
CREATE TABLE loop_feedback (
  id int(11) NOT NULL AUTO_INCREMENT primary key,
  loop_id int(11) NOT NULL,
  is_liked tinyint(1) DEFAULT FALSE,
  foreign key (loop_id) references loops(id)
)
STATEMENT
  return $CREATE_LOOP_FEEDBACK_TABLE;
}

"This young old master in the prime of his life";
