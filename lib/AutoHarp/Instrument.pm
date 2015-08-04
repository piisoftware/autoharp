package AutoHarp::Instrument;

use AutoHarp::Constants;
use AutoHarp::Generator;
use AutoHarp::Event;
use AutoHarp::Scale;
use AutoHarp::Clock;
use AutoHarp::Fuzzy;
use JSON;
use MIDI;
use Carp;
use Data::Dumper;
use strict;

use base qw(AutoHarp::Class);

#assist in getting an instrument from MIDI based on random params
#or strings or whatever

our $instrumentFamilies = 
  {piano => [0..7],
   'chromatic percussion' => [8..15],
   organ => [16..20],
   accordion => [21..23], #not really--also harmonica
   guitar => [24..31],
   'acoustic guitar' => [24..25],
   'electric guitar' => [26..28],
   'rock guitar' => [29..30],
   'guitar harmonics' => [31..31],
   bass => [32..39],
   strings => [40..46],
   timpani => [47..47],
   ensemble => [48..55],
   brass => [56..63],
   reed => [64..71],
   pipe => [72..79],
   'synth lead' => [80..87],
   'synth pad' => [88..95],
   'synth effects' => [96..103],
   'ethnic' => [104..111],
   'percussion' => [112..119],
   'sound effects' => [120..127]
  };

my $INSTRUMENTS_THAT_SOUND_LIKE_ASS =
  {
   109 => 'fuck you, bagpipe',
  };

sub new {
  my $class = shift;
  my $args  = {@_};

  my $self;
  if ($args->{track}) {
    $self = $class->fromTrack($args->{track});
  } else {
    my $iClass;
    if ($args->{$ATTR_INSTRUMENT_CLASS}) {
      $iClass = $args->{$ATTR_INSTRUMENT_CLASS};
      $class = __translateToClassName($iClass);
      if (!$class) {
	confess "$iClass was not a valid instrument class";
      }
    } 
    
    my $patch   = $args->{$ATTR_PATCH};
    my $inst    = $args->{$ATTR_INSTRUMENT};
    $inst     ||= $_[0] if (!$inst && (scalar @_) == 1);
    $self = {
	     $ATTR_INSTRUMENT_CLASS => $iClass,
	     $ATTR_UID => ($class =~ /::(\w+)$/)[0] . "_" . int(rand(10000))
	    };
    bless $self, $class;
    if ($patch && $MIDI::number2patch{$patch}) {
      $self->patch($patch);
    }
    $self->choosePatch($inst);
  }
  return $self;
}

sub fromTrack {
  my $class = shift;
  my $track = shift;
  my $self   = {};
  my $channel;
  if (ref($track)) {    
    my $score = MIDI::Score::events_r_to_score_r($track->events_r);
    foreach my $e (@$score) {
      if ($e->[0] eq $EVENT_PATCH_CHANGE) {
	$self->{$ATTR_PATCH} = $e->[3];
	$channel = $e->[2];
	last;
      } 
    }
  }
  if ($channel eq $PERCUSSION_CHANNEL) {
    return $class->new($ATTR_INSTRUMENT_CLASS => $DRUM_LOOP, %$self);
  }
  bless $self,$class;
  return $self;
}

sub fromString {
  my $class  = shift;
  my $string = shift;
  my %attrs  = split(/[\:\,] /,$string);
  my $self = $class->new(
			 $ATTR_INSTRUMENT_CLASS => $attrs{$ATTR_INSTRUMENT_CLASS},
			 $ATTR_INSTRUMENT => $attrs{$ATTR_PATCH}
			);
  delete $attrs{$ATTR_PATCH};
  delete $attrs{$ATTR_INSTRUMENT_CLASS};
  while (my ($k,$v) = each %attrs) {
    $self->{$k} = $v;
  }
  return $self;
}

#return a map of band instruments
sub band {
  my $class = shift;
  my $band = {};
  my @i = ($DRUM_LOOP,
	   $BASS_INSTRUMENT,
	   $RHYTHM_INSTRUMENT,
	   $PAD_INSTRUMENT,
	   $LEAD_INSTRUMENT,
	   $HOOK_INSTRUMENT);
  my $themes = pickOne(1,2,3);
  for (1..$themes) {
    push(@i, $THEME_INSTRUMENT);
  }
  foreach my $i (@i) {
    my $inst = $class->new($ATTR_INSTRUMENT_CLASS => $i); 
    my $uid  = $i;
    while (exists $band->{$uid}) {
      $uid .= "1" if ($uid !~ /\d+$/);
      $uid++;
    }
    $inst->uid($uid);
    $band->{$uid} = $inst;
  }
  return $band;
}

sub toString {
  my $self = shift;
  return "$ATTR_UID: " . $self->uid() . 
    ", $ATTR_INSTRUMENT_CLASS: " . $self->instrumentClass() . 
      ", $ATTR_PATCH: " . $self->name();
}

sub instrumentClass {
  return $_[0]->{$ATTR_INSTRUMENT_CLASS};
}

#is this a known sub-class of instrument?
sub __translateToClassName {
  my $module = upCase(shift);
  my $class;
  while ($module =~ /\s+(\w)/) {
    my $cw = uc($1);
    $module =~ s/\s+$1/$cw/g;
  }
  my $req = "AutoHarp::Instrument::$module";
  if (AutoHarp::Class::requireClass($req)) {
    $class   = $req;
    return $class;
  } else {
    confess "Couldn't require $req: $@";
  }
  return;
}

sub choosePatch {
  my $self   = shift;
  my $string = shift;
  my @candidates;

  if ($string) {
    #see if this is a family or a patch name;
    if ($MIDI::patch2number{$string}) {
      return $self->patch($MIDI::patch2number{$string});
    } elsif ($instrumentFamilies->{lc($string)}) {
      return $self->patch(pickOne($instrumentFamilies->{lc($string)}));
    }
    #noooo. loop through and find all the instruments that match-ish
    my $test  = lc($string);
    $test =~ s/\W//g;
    foreach my $inst (keys %MIDI::patch2number) {
      #do our best to guess 
      my $k = lc($inst);
      $k =~ s/\W//g;
      if ($k =~ /$test/) {
	push(@candidates,$MIDI::patch2number{$inst});
      }
    }
    if (!scalar @candidates) {
      confess "Unable to instantiate a valid instrument from string $string";
    }
  }
  my $patch = (scalar @candidates) ? pickOne(@candidates)
    : pickOne([keys %MIDI::number2patch]);
  return $self->patch($patch);
}

sub name {
  return $MIDI::number2patch{$_[0]->patch};
}

sub is {
  my $self = shift;
  my $is   = shift;
  my $obj  = uc(substr($is,0,1)) . substr($is,1);
  return (ref($self) =~ /$is/i || 
	  $self->name =~ /$is/i ||
	  $self->isa("AutoHarp::Instrument::$obj")
	 );
}

sub isDrums {
  return;
}

sub id {
  return $_[0]->uid($_[1]);
}

sub uid {
  return $_[0]->scalarAccessor($ATTR_UID,$_[1]);
}

sub status {
  my $self = shift;
  return sprintf "%-25s ID: %-15s PATCH #: %3d",
    $self->name(),
      $self->id(),
	$self->patch();
}

sub patch {
  my $self = shift;
  my $arg = shift;
  $self->scalarAccessor($ATTR_PATCH, $arg, 0);
}

sub reset {
  my $self = shift;
  #no op for us
}

#I am playing right now
sub isPlaying {
  return $_[0]->scalarAccessor('isPlaying',$_[1]);
}

sub getFollowRequest {
  #i have no following requests
  return;
}

sub follow {
  return $_[0]->scalarAccessor($ATTR_FOLLOW,$_[1]);
}

sub decideSegment {
  my $self         = shift;
  my $segment      = shift;

  if (!$segment->music) {
    confess "Passed a segment without music! Why did that happen?";
  } elsif ($self->isPlaying() && !$segment->isChange()) {
    #all instruments keep playing if they were playing and 
    #we're still in the same part of the song
    return 1;
  }
  #otherwise, leave it to the individual instruments
  return $self->playDecision($segment);
}

#designed to be overridden--other instruments decide this in different ways
sub playDecision {
  confess "WHAT ARE YOU ASKING ME FOR? I AM DUMB";
}

#clear the flags that let us know if we were 
#or are going to play
sub clearPlayLog {
  my $self = shift;
  $self->isPlaying(0);
}

#decide the notes to be played and play them
sub play {
  confess "WHAT ARE YOU ASKING ME FOR? SERIOUSLY, I AM SERIOUSLY DUMB";
}

sub transition {
  my $self    = shift;
  my $segment = shift;
  my $music   = shift;
  if ($segment->transitionIsDown) {
    #handle come-downs
    if ($music->is($ATTR_MELODY)) {
      my $clock = $segment->music->clockAtEnd();
      #on a come-down transition, truncate the melody instead of playing out
      my $trunc = $clock->beatTime * (2 + asOftenAsNot);
      $music->truncateToTime($segment->reach - $trunc);
      #extend the last note
      my $n = $music->getNote(-1);
      if ($n) {
	$n->duration($n->duration + ($trunc / 2));
      }
    }
  }
}

#FROM MIDI.pm
# @number2patch{0 .. 127} = (   # The General MIDI map: patches 0 to 127
# #0: Piano
#  "Acoustic Grand", "Bright Acoustic", "Electric Grand", "Honky-Tonk",
#  "Electric Piano 1", "Electric Piano 2", "Harpsichord", "Clav",
# # Chrom Percussion
#  "Celesta", "Glockenspiel", "Music Box", "Vibraphone",
#  "Marimba", "Xylophone", "Tubular Bells", "Dulcimer",

# #16: Organ
#  "Drawbar Organ", "Percussive Organ", "Rock Organ", "Church Organ",
#  "Reed Organ", "Accordion", "Harmonica", "Tango Accordion",
# # Guitar
#  "Acoustic Guitar(nylon)", "Acoustic Guitar(steel)",
#  "Electric Guitar(jazz)", "Electric Guitar(clean)",
#  "Electric Guitar(muted)", "Overdriven Guitar",
#  "Distortion Guitar", "Guitar Harmonics",

# #32: Bass
#  "Acoustic Bass", "Electric Bass(finger)",
#  "Electric Bass(pick)", "Fretless Bass",
#  "Slap Bass 1", "Slap Bass 2", "Synth Bass 1", "Synth Bass 2",
# # Strings
#  "Violin", "Viola", "Cello", "Contrabass",
#  "Tremolo Strings", "Orchestral Strings", "Orchestral Strings", "Timpani",

# #48: Ensemble
#  "String Ensemble 1", "String Ensemble 2", "SynthStrings 1", "SynthStrings 2",
#  "Choir Aahs", "Voice Oohs", "Synth Voice", "Orchestra Hit",
# # Brass
#  "Trumpet", "Trombone", "Tuba", "Muted Trumpet",
#  "French Horn", "Brass Section", "SynthBrass 1", "SynthBrass 2",

# #64: Reed
#  "Soprano Sax", "Alto Sax", "Tenor Sax", "Baritone Sax",
#  "Oboe", "English Horn", "Bassoon", "Clarinet",
# # Pipe
#  "Piccolo", "Flute", "Recorder", "Pan Flute",
#  "Blown Bottle", "Skakuhachi", "Whistle", "Ocarina",

# #80: Synth Lead
#  "Lead 1 (square)", "Lead 2 (sawtooth)", "Lead 3 (calliope)", "Lead 4 (chiff)",
#  "Lead 5 (charang)", "Lead 6 (voice)", "Lead 7 (fifths)", "Lead 8 (bass+lead)",
# # Synth Pad
#  "Pad 1 (new age)", "Pad 2 (warm)", "Pad 3 (polysynth)", "Pad 4 (choir)",
#  "Pad 5 (bowed)", "Pad 6 (metallic)", "Pad 7 (halo)", "Pad 8 (sweep)",

# #96: Synth Effects
#  "FX 1 (rain)", "FX 2 (soundtrack)", "FX 3 (crystal)", "FX 4 (atmosphere)",
#  "FX 5 (brightness)", "FX 6 (goblins)", "FX 7 (echoes)", "FX 8 (sci-fi)",
# # Ethnic
#  "Sitar", "Banjo", "Shamisen", "Koto",
#  "Kalimba", "Bagpipe", "Fiddle", "Shanai",

# #112: Percussive
#  "Tinkle Bell", "Agogo", "Steel Drums", "Woodblock",
#  "Taiko Drum", "Melodic Tom", "Synth Drum", "Reverse Cymbal",
# # Sound Effects
#  "Guitar Fret Noise", "Breath Noise", "Seashore", "Bird Tweet",
#  "Telephone Ring", "Helicopter", "Applause", "Gunshot",
# );
"With friends like that who has need of any friends?";

