package AutoHarp::Event::Note;

use AutoHarp::Constants;
use Carp;
use MIDI;
use strict;
use base qw(AutoHarp::Event);

# 0 => 'note'
# 1 => start Time
# 2 => duration
# 3 => channel
# 4 => pitch
# 5 => velocity

sub new {
  my $class = shift;
  my ($pitch, $len, $velocity,$time) = @_;
  my $self;
  if (ref($pitch) && scalar @$pitch) {
    $self = [@{$pitch}[0..5]];
    $self->[0] = $EVENT_NOTE;
  } else {
    $self = [$EVENT_NOTE,
	     $time, 
	     int($len), 
	     0, 
	     int($pitch), 
	     int($velocity)
	    ];
  }
  bless $self, $class;
  return $self;
}

sub fromString {
  my $class   = shift;
  my $val     = shift;
  $val =~ s/\s//g;
  my ($note,$accident,$number) = 
    ($val =~ /^([a-g])(\D*)(\d+)?$/i);
  my $pitchOffset = 0;
  $accident = 's' if ($accident =~ /(sharp|\#)/i);
  if (lc($accident) eq 'flat' || lc($accident) eq 'b') {
    #flat me!
    $accident = "";
    $pitchOffset = 1;
  }
  $number ||= 4;
  my $noteStr = "$note$accident$number";
  if (exists $MIDI::note2number{$noteStr}) {
    my $pitch = $MIDI::note2number{$noteStr} - $pitchOffset;
    return $class->new($pitch,@_);
  }
  confess "$val was an invalid note";
}

sub toNote {
  return (shift)->clone;
}

#produce the note in array context (useful for handling along with chords)
sub toNotes {
  my $self = shift;
  return [$self];
}

sub duration {
  my $self = shift;
  my $arg  = shift;
  if ($arg > 0) {
    $self->[2] = $arg;
  }
  return $self->[2];
}

sub channel {
  my $self = shift;
  my $arg  = shift;
  if (length($arg) && $arg >= 0) {
    $self->[3] = $arg;
  }
  return $self->[3];
}

sub pitch {
  my $self = shift;
  my $arg  = shift;
  if (length($arg) && $arg >= 0 && $arg <= 127) {
    $self->[4] = $arg;
  }
  return $self->[4];
}

sub value {
  return ($_[0]->pitch($_[1]));
}

#returns any C as 0, any C# as 1, any D as 2, etc...
sub modPitch {
  my $self = shift;
  return ($self->[4] % 12);
}

#returns the hertz frequency of the given pitch, 
#using A4 = 440hz
sub frequency {
  my $self = shift;
  my $n = $self->pitch - $MIDI::note2number{'A4'};
  return sprintf("%.3f",(2 ** $n) * 440);
}

sub noteAndOctave {
  my $n2n = $MIDI::number2note{(shift)->pitch};
  my ($note,$oct) = ($n2n =~ /(\D+)(\d+)/);
  $note =~ s/s/\#/;
  return $note . $oct;
}

sub letter {
  return ((shift)->noteAndOctave =~ /(\D+)/)[0];
}

sub drum {
  return $MIDI::notenum2percussion{$_[0]->pitch};
}

sub isKickDrum {
  my $self = shift;
  return ($self->drum() =~ /Bass/);
}

sub isSnare {
  my $self = shift;
  return ($self->drum() =~ /Snare/);
}

sub octave {
  my $self = shift;
  my $arg = shift;
  my $n = $MIDI::number2note{$self->pitch};
  if (length($arg)) {
    $n =~ s/(\d+)/$arg/;
    if (!$MIDI::note2number{$n}) {
      confess "Tried to set note to invalid octave $arg";
    }
    $self->pitch($MIDI::note2number{$n});
  }
  return ($n =~ /(\d+)/)[0];
}

sub velocity {
  my $self = shift;
  my $arg  = shift;
  if (length($arg) && $arg >= 0 && $arg <= 127) {
    $self->[5] = $arg;
  }
  return $self->[5];
}

#returns the velocity scaled between 0-9 (used in notation)
sub velocity2Digit {
  my $self = shift;
  return int($self->velocity() * 10 / 128);
}

#sets the velocity with a digit between 0-9 (as above)
sub digit2Velocity {
  my $self = shift;
  my $arg  = shift;
  if ($arg >= 0 && $arg <= 9) {
    return $self->velocity(int((128/10) * $arg) + int(rand(12)) + 1);
  }
}

sub isHard {
  return (shift)->velocity() > 107;
}

sub isMedium {
  my $self = shift;
  return $self->velocity() > 73 && !$self->isHard();
}

sub isSoft {
  my $self = shift;
  return $self->velocity() <= 73 && !$self->isSofter();
}

sub isSofter {
  return (shift)->velocity() <= 50;
}

sub toString {
  return lc((shift)->noteAndOctave());
}

sub dump {
  my $self = shift;
  if ($self->isPercussion()) {
    printf "[%4s %6d %4d %2d %20s %3d]\n",
      @$self[0..3],
	$self->drum(),
	  $self->[5];
  } else {
    my @copy = @$self; 
    $copy[4] = lc($MIDI::number2note{$copy[4]}) || $copy[4] . "!";
    printf "[%-14s %5d %4d %2s %3s %3d]\n",@copy;
  }
}

"Our house. In the middle of our street";

