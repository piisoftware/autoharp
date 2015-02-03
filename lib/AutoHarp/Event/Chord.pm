package AutoHarp::Event::Chord;

use AutoHarp::Constants;
use AutoHarp::Fuzzy;
use AutoHarp::Scale;
use AutoHarp::Event::Note;
use Data::Dumper;
use Carp;
use base qw(AutoHarp::Event::Note);
use strict;

my $ARPEGGIO_OFFSET = 5;
my $CHORD_NAME = 'chordName';
my $ROOT_INTERVAL = 'rootInterval';
my $INTERVAL = 'interval';
my $SPELL_BOTTOM_NOTE = 'spellBottomNote';
my $EMPTY_CHORD = 'Empty Chord!';
my $UNCLASSIFIED = 'unclassified';
my $ROOT_PITCH = 'rootPitch';
my $CHORD_TYPE = 'chordType';
my $MAJOR = 'Major';
my $MINOR = 'Minor';
my $DIMINISHED = 'Diminished';
my $SINGLE_NOTE = 'Single Note';
my $REGEX = 'regex';
my $PITCH_IDX = 4; #pitches are the fifth element of the array
my $STR_IDX = 6; #name of the chord at the sixth element of the array
my $NO_THIRD = 'noThird';
#harnessing the power of regular expressions to match chords
#(I am a badass)
my $CHORD_LOOKUP = 
  [{$REGEX => qr(0(.*)_4(.*)_7(.*)),
    $CHORD_TYPE => $MAJOR}, 
   {$REGEX => qr(0(.*)_3(.*)_8(.*)),
    $CHORD_TYPE => $MAJOR, 
    $ROOT_INTERVAL => 8},
   {$REGEX => qr(0(.*)_5(.*)_9(.*)),
    $CHORD_TYPE => $MAJOR,
    $ROOT_INTERVAL => 5}, 
   {$REGEX => qr(0(.*)_3(.*)_7(.*)),
    $CHORD_TYPE => $MINOR, 
    $CHORD_NAME => 'm', 
    $ROOT_INTERVAL => 0},
   {$REGEX => qr(0(.*)_4(.*)_9(.*)),
    $CHORD_TYPE => $MINOR,
    $CHORD_NAME => 'm', 
    $ROOT_INTERVAL => 9},
   {$REGEX => qr(0(.*)_5(.*)_8(.*)),
    $CHORD_TYPE => $MINOR,
    $CHORD_NAME => 'm', 
    $ROOT_INTERVAL => 5}
  ];

my $DIMINISHED_CHORDS = 
  [
   {$REGEX => qr(0(.*)_3(.*)_6(.*)),
    $CHORD_TYPE => $DIMINISHED,
    $CHORD_NAME => 'dim', 
    $ROOT_INTERVAL => 0},
   {$REGEX => qr(0(.*)_3(.*)_9(.*)),
    $CHORD_TYPE => $DIMINISHED,
    $CHORD_NAME => 'dim', 
    $ROOT_INTERVAL => 9},
   {$REGEX => qr(0(.*)_6(.*)_9(.*)),
    $CHORD_TYPE => $DIMINISHED,
    $CHORD_NAME => 'dim', 
    $ROOT_INTERVAL => 6},
  ];

my $INTERVALS = 
  {0 => {}, #unison; technically a valid interval, but, you know, pointless
   1 => {$CHORD_NAME => 'flat2'},
   2 => {$CHORD_NAME => '2'},
   3 => {$MAJOR => 'minor3'},
   4 => {$MINOR => 'major3', $DIMINISHED => 'major3'},
   5 => {$CHORD_NAME => '4'},
   6 => {$MAJOR => 'flat5', $MINOR => 'flat5'},
   7 => {$DIMINISHED => '5', $NO_THIRD => '5'},
   8 => {$CHORD_NAME => 'flat6'},
   9 => {$CHORD_NAME => '6'},
   10 => {$CHORD_NAME => '7'},
   11 => {$CHORD_NAME => 'major7'},
   13 => {$CHORD_NAME => 'flat9'},
   14 => {$CHORD_NAME => '9'},
   15 => {$MAJOR => 'sharp9'},
   16 => {$MINOR => 'flat11'},
   17 => {$CHORD_NAME => '11'},
   18 => {$CHORD_NAME => 'sharp11'},
   20 => {$CHORD_NAME => 'flat13'},
   21 => {$CHORD_NAME => '13'}
  };

my $numberSubs = 
  {
   two => 2,
   second => 2,
   third => 3,
   fourth => 4,
   four => 4,
   five => 5,
   fifth => 5,
   six => 6,
   sixth => 6,
   seven => 7,
   seventh => 7,
   nine => 9,
   ninth => 9,
   eleven => 11,
   eleventh => 11,
   thirteen => 13,
   thirteenth => 13
  };

my $IDENTIFIED_CHORDS = {};

sub new {
  my $class     = shift;
  my $self      = [$EVENT_CHORD,0,0,0,[],0];
  bless $self,$class;

  foreach my $e (@_) {
    if (ref($e)) {
      $self->[1] ||= $e->[1];
      $self->[2] ||= $e->[2];
      $self->[3] ||= $e->[3];
      $self->[5] ||= $e->[5];
      my $p = (ref($e->[4]) eq 'ARRAY') ? $e->[4] : [$e->[4]];
      foreach (@$p) {
	$self->addPitch($_);
      }
    } else {
      $self->addPitch($e);
    }
  }
  $self->[5] ||= softVelocity();

  return $self;
}

sub fromString {
  my $class     = shift;
  my $string    = shift;
  my $duration  = shift;
  my $velocity  = shift;
  my $time      = shift;
  $string =~ s/\s+//g;

  my $bassNote;
  if ($string =~ /(.+)over(.+)/i) {
    $string = $1;
    $bassNote = AutoHarp::Event::Note->fromString($2);
    if (!$bassNote) {
      #this was bunk. Screw you 
      confess "Invalid chord specification $string";
    }
  }
  
  my $self = $class->new();
  $self->duration($duration);
  if ($velocity) {
    $self->velocity($velocity);
  } else {
    $self->velocity(mediumVelocity);
  }
  $self->time($time || 0);
  
  #create a type string to determine the kind of chord this is
  my ($rootNoteStr, $modifier, $typeStr) = ($string =~ /^([A-G])([b\#]*)(.*)$/);
  if (!$rootNoteStr) {
    confess "Cannot parse $string as a chord";
  }
  my $origTypeStr = $typeStr;
  $rootNoteStr   .= $modifier if ($modifier);
  $typeStr        = lc(__subNumbers($typeStr));
  
  #set type and additional pitches of chord
  my $type = $MAJOR;
  my $pitches = [4,7];

  #strip off "major" if it's not talking about an interval
  if ($typeStr =~ s/^(maj|major)([^\do])/$2/) {
    #do nothing else, just don't make this chord something it isn't
  } elsif ($typeStr =~ /^(minor|min|m)([^a]|\z)/) {
    $typeStr =~ s/$1//;
    $type = $MINOR;
    $pitches = [3,7];
  } elsif ($typeStr =~ /^(dim|diminished)/) {
    $typeStr =~ s/$1//;
    $type = $DIMINISHED;
    $pitches = [3,6];
  }
  #split the rest of the chord into tokens and parse them
  foreach my $token (grep {$_} split(/(\D*1?\d)/,$typeStr)) {
    my ($word,$interval) = ($token =~ /(\D+)?(\d+)/);
    if ($word =~ /^maj/) {
      $word = 'major';
    } elsif ($word =~ /^m(in)?(or)?/) {
      $word = 'minor';
    } elsif ($word =~ /^f/) {
      $word = 'flat';
    } elsif ($word =~ /^sharp/) {
      $word = 'sharp';
    } else {
      undef $word;
    }
    $token = "$word$interval";
    foreach my $int (keys %$INTERVALS) {
      my $name = $INTERVALS->{$int}{$type} || $INTERVALS->{$int}{$CHORD_NAME};
      if ($name && $token eq $name) {
	push(@$pitches, $int);
	last;
      } elsif ($token eq $INTERVALS->{$int}{$NO_THIRD}) {
	push(@$pitches, $int);
	#this interval dictates removing the third of the chord.
	shift(@$pitches);
	#buh-bye third
	last;
      } 
    }
  }
  
  #we should now know pitches and type, so we just need a root note
  my $rootNote = AutoHarp::Event::Note->fromString($rootNoteStr);
  if ($rootNote) {
    $self->addPitch($rootNote->pitch);
    if ($bassNote) {
      my $bPitch = $bassNote->pitch();
      if ($bPitch > $rootNote->pitch) {
	$bPitch -= $ATTR_SCALE_SPAN;
      }
      $self->addPitch($bPitch);
    }
    foreach my $p (@$pitches) {
      $self->addPitch($rootNote->pitch + $p);
    }
    #we now know this guy's name, so use it in the future
    # my $pitches = $self->[$PITCH_IDX];
    # shift(@$pitches) if ($bassNote);
    # $IDENTIFIED_CHORDS->{__chordKey($pitches)} = 
    #   {
    #    $CHORD_NAME => $origTypeStr,
    #    $CHORD_TYPE => $type
    #   };
    return $self;
  } 
  confess "No valid root note from $string";
}

sub clone {
  my $self   = shift;
  my $clone = [@{$self}];
  $clone->[$PITCH_IDX] = [@{$self->[$PITCH_IDX]}];
  bless $clone, ref($self);
  return $clone;
}

sub pitch {
  my $self = shift;
  my $arg = shift;
  if (length($arg)) {
    $self->addPitch($arg);
  }
  return $self->SUPER::pitch();
}

sub pitches {
  my $self = shift;
  return $self->[$PITCH_IDX];
}

sub setPitches {
  my $self = shift;
  my $pitches = shift;
  if (ref($pitches)) {
    $self->[$PITCH_IDX] = [];
    foreach my $p (@$pitches) {
      $self->addPitch($p);
    }
  }
}

sub hasPitch {
  my $self = shift;
  my $pitch = shift;
  return scalar grep {$_ eq $pitch} @{$self->pitches};
}

sub addNote {
  my $self = shift;
  my $note = shift;
  if (ref($note) && $note->can('pitch')) {
    my $pitch = $note->pitch;
    if (!ref($pitch)) {
      $pitch = [$pitch];
    }
    foreach (@$pitch) {
      $self->addPitch($_);
    }
  }
}

sub addPitch {
  my $self  = shift;
  my $pitch = shift;
  my $ps = $self->[$PITCH_IDX];
  if ($MIDI::number2note{$pitch}) {
    #clear the chord's name. It'll get repopulated if we ask for it again
    $self->[$STR_IDX] = undef;
    for (my $i = $#$ps; $i >= 0; $i--) {
      if ($pitch == $ps->[$i]) {
	#thanks, we got you
	return;
      } elsif ($pitch > $ps->[$i]) {
	splice(@$ps,$i + 1,0,$pitch);
	return;
      }
    }
    unshift(@$ps,$pitch);
  } else {
    confess "Attempted to add $pitch to chord";
  }
}
    
sub subtractPitch {
  my $self = shift;
  my $pitch = shift;
  for(my $i = 0; $i < scalar @{$self->[$PITCH_IDX]}; $i++) {
    if ($self->[$PITCH_IDX][$i] == $pitch) {
      #clear the chord name before altering it
      $self->[$STR_IDX] = undef;
      splice(@{$self->[$PITCH_IDX]},$i,1);
      last;
    }
  }
}

#become this other chord. DO IT
sub become {
  my $self = shift;
  my $otherChord = shift;
  if ($otherChord) {
    $self->[$PITCH_IDX] = [@{$otherChord->pitches()}];
    $self->[$STR_IDX] = $otherChord->toString();
  }
}

sub getNoteByPitch {
  my $self  = shift;
  my $pitch = shift;
  my $mod   = shift;
  $mod = 1 if (!length($mod));

  if ($pitch) {
    foreach my $p (@{$self->pitches}) {
      if ($pitch == $p || 
	  ($mod && 
	   (($pitch % $ATTR_SCALE_SPAN) == ($p % $ATTR_SCALE_SPAN)))) {
	return $self->toNote($p);
      }
    } 
  }
  #that pitch is not in this chord
  return;
}

sub toNote {
  my $self = shift;
  my $pitch = shift;
  if (!length($pitch) || $pitch < 0) {
    my $data = $self->identify();
    $pitch = $data->{$ROOT_PITCH};
  }
  my $n = $self->clone();
  $n->[0] = $EVENT_NOTE;
  $n->[$PITCH_IDX] = $pitch;
  return AutoHarp::Event::Note->new($n);
}

sub toNotes {
  my $self = shift;
  my $notes = [];
  foreach my $p (@{$self->[$PITCH_IDX]}) {
    push(@$notes,$self->toNote($p));
  }
  return $notes;
}

sub isTriad {
  my $self = shift;
  return (scalar @{$self->[$PITCH_IDX]} == 3);
}

sub toDefaultOctave {
  return (shift)->octave($DEFAULT_OCTAVE);
}

sub octave {
  my $self      = shift;
  my $octave    = shift;

  my $rp    = $self->root()->pitch();
  my $nando = $MIDI::number2note{$rp};
  if (!$nando) {
    confess $self->toString() . " has a totally invalid root note!";
  }
  $nando =~ s/(\d+)/$octave/;
  my $newPitch = $MIDI::note2number{$nando};
  if (!$newPitch && $nando ne 'C0') {
    confess "$octave was an invalid octave to set upon this chord";
  }
  my $diff = $newPitch - $rp;
  if ($diff % 12) {
    confess "That. Just. Totally. Didn't. Work. From $rp to $newPitch using octave value $octave";
  }
  for(my $i = 0; $i < @{$self->[$PITCH_IDX]}; $i++) {
    $self->[$PITCH_IDX][$i] += $diff;
  }
}

sub arpeggiateUpward {
  my $self = shift;
  my $speed = shift || $ARPEGGIO_OFFSET;
  my $time = $self->time;
  my $notes = $self->toNotes();
  foreach my $n (@$notes) {
    $n->time($time);
    $n->duration($n->reach - $time);
    $time += $speed;
  }
  return $notes;
}

sub arpeggiateDownward {
  my $self = shift;
  my $speed = shift || $ARPEGGIO_OFFSET;
  my $time = $self->time;
  my $notes = $self->toNotes();
  foreach my $n (reverse @$notes) {
    $n->time($time);
    $n->duration($n->reach - $time);
    $time += $speed;
  }
  return $notes;
}

sub root {
  my $self = shift;
  my $data = $self->identify();
  return $self->toNote($data->{$ROOT_PITCH});
}

sub bass {
  my $self = shift;
  return $self->toNote($self->[$PITCH_IDX][0]);
}

sub bassPitch {
  return $_[0]->bass()->pitch();
}

sub third {
  my $self      = shift;
  my $data      = $self->identify();
  my $rootPitch = $data->{$ROOT_PITCH};
  my $steps;
  if ($data->{$CHORD_TYPE} eq $MAJOR) {
    $steps = 4;
  } elsif ($data->{$CHORD_TYPE} eq $DIMINISHED || 
	   $data->{$CHORD_TYPE} eq $MINOR) {
    $steps = 3;
  } else {
    foreach my $p (@{$self->pitches}) {
      my $int = ($p - $rootPitch) % $ATTR_SCALE_SPAN;
      if ($int >= 3 && $int <=4) {
	$steps = $int;
      }
    }
    #outta luck. No third for you
  }
  return $self->toNote($rootPitch + $steps);
}

sub fifth {
  my $self   = shift;
  my $data   = $self->identify();
  my $rPitch = $data->{$ROOT_PITCH};
  my $steps  = ($data->{$CHORD_TYPE} eq $DIMINISHED) ? 6 : 7;
  return $self->toNote($rPitch + $steps);
}

sub toString {
  my $self = shift;
  if (!$self->[$STR_IDX]) {
    my $data = $self->identify();
    my $root = $self->toNote($data->{$ROOT_PITCH});
    my $str =  $data->{$CHORD_NAME};
    if ($root) {
      $str = uc($root->letter) . $str;
      if ($data->{$SPELL_BOTTOM_NOTE}) {
	$str .= " over " . $self->bass->letter;
      }
    } 
    $self->[$STR_IDX] = $str;
  }
  return $self->[$STR_IDX];
}

sub chordType {
  my $self = shift;
  my $data = $self->identify();
  return $data->{$CHORD_TYPE};
}

sub isMajor { 
  return ((shift)->chordType eq $MAJOR);
}

sub isMinor {
  return ((shift)->chordType eq $MINOR);
}

sub isDiminished {
  return ((shift)->chordType eq $DIMINISHED);
}

sub isUnclassified {
  return ((shift)->chordType eq $UNCLASSIFIED)
}

sub rootLetter {
  my $self = shift;
  my $root = $self->root();
  return ($root) ? uc($root->letter) : undef;
}

sub rootPitch {
  my $self = shift;
  my $data = $self->identify();
  return $data->{$ROOT_PITCH};
}

sub toNotesString {
  my $self = shift;
  return join(" ",map {$MIDI::number2note{$_}} @{$self->pitches});
}

#return the "scale number" of the chord 
#in the given scale, e.g. I, ii, iii, whatever
sub toScaleNumber {
  my $self = shift;
  my $scale = shift;

  if ($scale) {
    my $data = $self->identify();
    if ($self->isScaleTriad($scale,$data)) {
      return $scale->scaleIndex($data->{$ROOT_PITCH}) + 1;
    }
  }
  return 0;
}

sub isScaleTriad {
  my $self  = shift;
  my $scale = shift;
  if ($scale) {
    my $data  = shift || $self->identify();
    my $rootPitch = $data->{$ROOT_PITCH};
    my $expThird  = $scale->steps($rootPitch, 2);
    my $expFifth  = $scale->steps($rootPitch, 4);
    return ($self->getNoteByPitch($expThird,1) && $self->getNoteByPitch($expFifth,1));
  }
  return;
}

sub inScale {
  my $self = shift;
  my $scale = shift;
  if ($scale) {
    foreach my $p (@{$self->pitches}) {
      if ($scale->isAccidental($p)) {
	return;
      }
    }
    return 1;
  }
  return;
}

sub noteAndOctave {
  my $data = $_[0]->identify();
  my $n2n = $MIDI::number2note{$data->{$ROOT_PITCH}};
  my ($note,$oct) = ($n2n =~ /(\D+)(\d+)/);
  $note =~ s/s/\#/;
  return $note . $oct;
}

sub value {
  return (shift)->toString();
}

sub chordType {
  my $self = shift;
  my $data = $self->identify();
  return $data->{$CHORD_TYPE};
}

#returns true same letter/type chords
#e.g. C7 is "like" C Major7
sub isAlike {
  my $self = shift;
  my $chord = shift;
  return ($chord && 
	  $chord->letter eq $self->letter &&
	  $chord->chordType eq $self->chordType);
}

#returns true if the other chord is reasonably
#a substitution for the other chord
#e.g. Aminor for C
sub isSubstitution {
  my $self = shift;
  my $chord = shift;
  my $scale = shift || AutoHarp::Scale->fromChord($self);
  #new chord must have two notes in common and at least one other note in the scale
  return 1 if ($chord && $self->isAlike($chord));
  
  if ($chord && $scale) {
    my $inChord = 0;
    my $inScale = 0;
    foreach my $p (@{$chord->pitches}) {
      if ($self->getNoteByPitch($p)) {
	$inChord++;
      } elsif (!$scale->isAccidental($p)) {
	$inScale++;
      }
    }
    return ($inChord >= 3 || ($inChord == 2 && $inScale > 0));
  }
  return;
}

#a feeble, mind-blowingly complicated method of 
#transforming notes to chord name
#opaque, but as good as I can do
sub identify {
  my $self       = shift;
  my $isSubChord = shift;

  #clear the current chord name, if set
  $self->[$STR_IDX] = undef;
  
  my $pitches    = [@{$self->[$PITCH_IDX]}];
  if (scalar @$pitches >= 3) {
    my $data = __chordCache($pitches);
    if (!$data && scalar @$pitches > 3 && !$isSubChord) {
      #if we haven't yet, try to identify a known chord 
      #over the root note
      my $subChord = $self->clone;
      shift(@{$subChord->[$PITCH_IDX]});
      my $subData  = $subChord->identify(1);
      if ($subData && $subData->{$CHORD_TYPE} ne $UNCLASSIFIED) {
	$subData->{$SPELL_BOTTOM_NOTE} = 1;
	return $subData;
      } 
    }
    if (!$data) {
      #nothing? Force the issue
      $data = __chordCache($pitches,1);
    }
    return $data
  } elsif (scalar @$pitches == 2) {
    my $interval = __normalizeInterval(@$pitches);
    return {$CHORD_NAME => __nameInterval($interval),
	    $CHORD_TYPE => $INTERVAL,
	    $ROOT_PITCH => $pitches->[0]
	   };
  } elsif (scalar @$pitches == 1) {
    my $bass = $self->bass;
    return {$CHORD_NAME => $bass->letter . " note",
	    $ROOT_PITCH => $pitches->[0],
	    $CHORD_TYPE => $SINGLE_NOTE
	   }
  }
  return {$CHORD_NAME => $EMPTY_CHORD,
	  $ROOT_PITCH => undef,
	  $CHORD_TYPE => $UNCLASSIFIED
	 }
}

sub __nameInterval {
  my $noType = 'NO_TYPE';
  my $int = shift;
  my $type = shift || $noType;

  return if (!$int || !exists $INTERVALS->{$int});
  my $name = $INTERVALS->{$int}{$CHORD_NAME} || $INTERVALS->{$int}{$type};
  if (!$name && $type eq $noType) {
    foreach my $type (keys %{$INTERVALS->{$int}}) {
      #there isn't a well defined name for this interval
      #and we aren't looking for a specific type
      #so just take the first one we find
      $name = $INTERVALS->{$int}{$type};
      last;
    }
  }
  return $name;
}

sub __normalizeInterval {
  my $pitchOne = shift;
  my $pitchTwo = shift;
  my $toSingleScale = shift;
  my $gap     = $pitchTwo - $pitchOne;
  if (!exists $INTERVALS->{$gap}) {
    $gap %= ($ATTR_SCALE_SPAN * 2);
  }
  if ($toSingleScale || !exists $INTERVALS->{$gap}) {
    $gap %= $ATTR_SCALE_SPAN;
  }
  return $gap;
}

sub __chordKey {
  my $pitches       = shift;
  my $toSingleScale = shift;
  my @intervals;
  my $first         = $pitches->[0];
  foreach (@$pitches) {
    push(@intervals,__normalizeInterval($first, $_, $toSingleScale));
  }
  return join("_",@intervals);
}

sub __chordCache {
  my $pitches   = shift;
  my $force     = shift;
  my $rootPitch = $pitches->[0];
  my $chordKey  = __chordKey($pitches,$force);
  if (!$IDENTIFIED_CHORDS->{$chordKey}) {
    my @patterns = @$CHORD_LOOKUP;
    if ($force) {
      #if we're forcing the issue, add diminished chords into the mix
      push(@patterns, @$DIMINISHED_CHORDS);
    }
    foreach my $cData (@patterns) {
      my $regex = $cData->{$REGEX};
      my @m = ($chordKey =~ /$regex/);
      if (scalar @m) {
	#we matched a chord pattern; grab any additional notes
	my $name = $cData->{$CHORD_NAME};
	my $chordType = $cData->{$CHORD_TYPE};
	#this is the index of the basic chord pattern where the
	#root note was not the lowest one, so maybe 
	#adjust up the necessary inteval
	$rootPitch += $cData->{$ROOT_INTERVAL};
	#add the name of each interval, if necessary to the name of the chord
	foreach my $str (@m) {
	  foreach my $interval (grep {$_} split("_",$str)) {
	    $name .= __nameInterval($interval, $chordType);
	  }
	}
	$IDENTIFIED_CHORDS->{$chordKey} = {$CHORD_NAME => $name,
					   $CHORD_TYPE => $chordType,
					  };
	last;
      }
    }
  }
  if (!$IDENTIFIED_CHORDS->{$chordKey} && $force) {
    #We tried and tried and got nothing, but we must get something. 
    #Make the first note the root and just name the intervals
    my $name;
    foreach (grep {$_ > 0} split(/_/,$chordKey)) {
      $name .= __nameInterval($_);
    }
    $IDENTIFIED_CHORDS->{$chordKey} = {$CHORD_NAME => $name,
				       $ROOT_PITCH => $rootPitch,
				       $CHORD_TYPE => $UNCLASSIFIED
				      };
  }
  if ($IDENTIFIED_CHORDS->{$chordKey}) {
    my $ret = {%{$IDENTIFIED_CHORDS->{$chordKey}}};
    $ret->{$ROOT_PITCH} = $rootPitch;
    return $ret;
  }
  return;
}

sub dump {
  my $self    = shift;
  my @copy = @$self; 
  @copy[4] = $self->toString();
  printf "[%-13s %6d %4d %2s %-10s %3d]",@copy;
  foreach my $p (@{$self->pitches}) {
    print " $MIDI::number2note{$p}";
  }
  print "\n";
}

#turn words like ninth/nine into 9
sub __subNumbers {
  my $str = shift;
  while (my ($k,$v) = each %$numberSubs) {
    $str =~ s/$k/$v/ig;
    $str =~ s/(\d+)(st|nd|rd|th)/$1/g;
  }
  return $str;
}

"I ripped off the chords from Bron-Y-Aur";
