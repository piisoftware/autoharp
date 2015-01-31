package AutoHarp::MusicBox;

use base qw(AutoHarp::Class);
use AutoHarp::Constants;
use AutoHarp::Clock;
use AutoHarp::Scale;
use strict;

my $METADATA  = 'metadata';

#container class for bits of music and songs

sub name {
  my $self = shift;
  my $name = shift;
  if ($name) {
    $self->{$ATTR_NAME} = $name;
  } elsif (!$self->{$ATTR_NAME}) {
    $self->{$ATTR_NAME} = "Music Box " . $self->uid;
  }
  return $self->{$ATTR_NAME};
}

sub uid {
  my $self = shift;
  my $arg  = shift;
  if ($arg) {
    $self->{$ATTR_UID} = $arg;
  } elsif (!$self->{$ATTR_UID}) {
    $self->{$ATTR_UID} = time() . "_" . int(rand(1000));
  }
  return $self->{$ATTR_UID};
}

sub slotName {
  my $self     = shift;
  my $slotName = shift;
  return $self->scalarAccessor('slotName',$slotName);
}

sub cacheName {
  my $self = shift;
  return $self->scalarAccessor('cacheName',@_);
}

sub metadata {
  my $self = shift;
  my $key = shift;
  my $val = shift;
  $self->{$METADATA} ||= {};
  if ($key) {
    if (length($val)) {
      $self->{$METADATA}{$key} = $val;
    }
    return $self->{$METADATA}{$key};
  }
  return;
}

sub tag {
  return $_[0]->scalarAccessor($ATTR_TAG,$_[1]);
}

sub tags {
  my $self = shift;
  return (exists $self->{$METADATA}) ? [sort keys %{$self->{$METADATA}}] : [];
}
  
sub hasMetadata {
  my $self = shift;
  return exists $self->{$METADATA} && scalar keys %{$self->{$METADATA}};
}

sub deleteMetadata {
  my $self = shift;
  my $key  = shift;
  delete $self->{$METADATA}{$key};
}

sub clearMetadata {
  my $self = shift;
  delete $self->{$METADATA};
}

sub time {
  return 0;
}

sub duration {
  return 0;
}

sub reach {
  return 0;
}

sub clock {
  my $self = shift;
  my $time = $self->time();
  return $self->clockAt($time);
}

sub scale {
  my $self = shift;
  my $time = $self->time();
  return $self->scaleAt($time);
}

sub clockAtEnd {
  my $self = shift;
  my $r = $self->reach();
  return $self->clockAt($r);
}

sub scaleAtEnd {
  my $self = shift;
  my $r = $self->reach();
  return $self->scaleAt($r);
}

sub clockAt {
  return AutoHarp::Clock->new();
}

sub scaleAt {
  return AutoHarp::Scale->new();
}

sub tracks {
  return [];
}

sub eachMeasure {
  return [0];
}

sub measures {
  return 0;
}

sub export {
  my $self     = shift;
  my $fileName = shift;
  my $opus = MIDI::Opus->new({format => 1,
			      ticks => $TICKS_PER_BEAT,
			      tracks => $self->tracks(1)});
  $opus->write_to_file($fileName);
  return 1;
}

#how long will this music play?
sub durationInSeconds {
  return 0;
}

sub MMSS {
  my $self = shift;
  my $secs = int($self->durationInSeconds());
  my $mins = int($secs / 60) || '0'; 
  my $remains = $secs % 60 || '0'; 
  if (length($remains) == 1) {
    $remains = "0" . $remains;
  }
  return "$mins:$remains";
}

sub hasPickup {
  return;
}

"Meet me at the wrecking ball"
