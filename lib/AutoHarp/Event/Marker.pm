package AutoHarp::Event::Marker;

use AutoHarp::Constants;
use Carp;
use base qw(AutoHarp::Event::Text);
use strict;

sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);
  $self->[0] = $EVENT_MARKER;
  return bless $self,$class;
}

"Kid tested, motherfucker";
