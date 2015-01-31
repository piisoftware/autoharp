package AutoHarp::Event::Text;

use AutoHarp::Constants;
use base qw(AutoHarp::Event);
use Carp;
use JSON;
use strict;

sub new {
  my $class = shift;
  my $text = shift;
  my $time = shift;
  my $self = [];
  if (ref($text) eq 'ARRAY') {
    $time = $text->[1];
    $text = $text->[2];
  } elsif (ref($text) eq 'HASH') {
    #convert to JSON and store
    $text = to_json($text);
  } elsif (ref($text)) {
    die "Invalid text to Text event constructor";
  } 
  $time ||= 0;
  return bless [$EVENT_TEXT, $time, $text],$class;
}

sub text {
  my $self = shift;
  my $arg = shift;
  if (length($arg)) {
    $self->[2] = $arg;
  }
  return $self->[2];
}

sub value {
  return ($_[0]->text($_[1]));
}

sub data {
  my $self = shift;
  my $arg = shift;
  if (ref($arg) eq 'HASH' || ref) {
    $self->[2] = to_json($arg);
  }
  my $data;
  eval {
    $data = from_json($self->[2]);
  };
  if ($@) {
    $data = {text => $self->[2]};
  }
  return $data;
}

"love, love is a verb";
