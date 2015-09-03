package AutoHarp::Constants;

use base qw(Exporter);
use Readonly;

@EXPORT = qw(
	      $AH_CLASS
	      $ATTR_AUTOHARP_SONG
	      $ATTR_BARS
	      $ATTR_BUCKET
	      $ATTR_CHANNEL
	      $ATTR_CLOCK
	      $ATTR_COMPOSER
	      $ATTR_COMPOSITION
	      $ATTR_DIRECTORY
	      $ATTR_DURATION
	      $ATTR_EFFECTS
	      $ATTR_FILE
	      $ATTR_FOLLOW
	      $ATTR_GENERATOR
	      $ATTR_GENRE
	      $ATTR_MACHINE_GENRE
	      $ATTR_GUIDE
	      $ATTR_HOOK
	      $ATTR_INSTRUMENT
	      $ATTR_INSTRUMENTS
	      $ATTR_INSTRUMENT_CLASS
	      $ATTR_INSTRUMENT_ROLE
	      $ATTR_INTERVALS
	      $ATTR_KEY
	      $ATTR_LOOPS
	      $ATTR_LOOP_TYPE
	      $ATTR_MELODY
	      $ATTR_METER
	      $ATTR_MIDI_FILE
	      $ATTR_MUSIC
	      $ATTR_NAME
	      $ATTR_NOTE
	      $ATTR_PAN
	      $ATTR_PATCH
	      $ATTR_PATTERN
	      $ATTR_PITCH
	      $ATTR_PROGRESSION
	      $ATTR_RHYTHM_SPEED
	      $ATTR_ROOT_NOTE
	      $ATTR_SCALE
	      $ATTR_SCALE_SPAN
	      $ATTR_SONG
	      $ATTR_START_TIME
	      $ATTR_STRAIGHT_TRANSITION
	      $ATTR_UP_TRANSITION
	      $ATTR_DOWN_TRANSITION
	      $ATTR_TAG
	      $ATTR_TEMPO
	      $ATTR_TIME
	      $ATTR_UID
	      $ATTR_VELOCITY
	      $ATTR_VERBOSE
	      $ATTR_VOLUME
	      $COMP_ELEMENTS
	      $DEFAULT_DIRECTORY
	      $DEFAULT_MIDI_METER
	      $DEFAULT_MIDI_TEMPO
	      $DEFAULT_OCTAVE
	      $DEFAULT_ROOT_PITCH
	      $DRUM_KIT
	      $DRUM_LOOP
	      $DEEP_DRUM_LOOP
	      $GENERATED_DRUM_LOOP
	      $DRUM_RESOLUTION
	      $EVENT_CHANNEL_AFTERTOUCH
	      $EVENT_CHORD
	      $EVENT_CONTROL_CHANGE
	      $EVENT_INSTRUMENT_NAME
	      $EVENT_KEY_AFTERTOUCH
	      $EVENT_KEY_SIGNATURE
	      $EVENT_MARKER
	      $EVENT_NOTE
	      $EVENT_NOTE_OFF
	      $EVENT_NOTE_ON
	      $EVENT_PATCH_CHANGE
	      $EVENT_PITCH_WHEEL
	      $EVENT_REST
	      $EVENT_SET_TEMPO
	      $EVENT_TEXT
	      $EVENT_TIME_SIGNATURE
	      $EVENT_TRACK_NAME
	      $BASS_INSTRUMENT
	      $HOOK_INSTRUMENT
	      $LEAD_INSTRUMENT
	      $PAD_INSTRUMENT
	      $RHYTHM_INSTRUMENT
	      $THEME_INSTRUMENT
	      $TRAINING_CHAOS
	      $TRAINING_EPOCH
	      $TRAINING_LOSS
	      $MAJOR_SCALE_INTERVALS
	      $MAX_TEMPO_BPM
	      $MUSIC_BOX
	      $NOTE_MINIMUM_TICKS
	      $PERCUSSION_CHANNEL
	      $SONG_ELEMENT
	      $SONG_ELEMENT_BEGIN
	      $SONG_ELEMENT_BRIDGE
	      $SONG_ELEMENT_CHORUS
	      $SONG_ELEMENT_END
	      $SONG_ELEMENT_FILL
	      $SONG_ELEMENT_INSTRUMENTAL
	      $SONG_ELEMENT_INTRO
	      $SONG_ELEMENT_LEADIN
	      $SONG_ELEMENT_LEADOUT
	      $SONG_ELEMENT_OUTRO
	      $SONG_ELEMENT_PRECHORUS
	      $SONG_ELEMENT_SOLO
	      $SONG_ELEMENT_TRANSITION
	      $SONG_ELEMENT_VERSE
	      $SONG_SECTION
	      $SONG_SEGMENT
	      $TICKS_PER_BEAT
	      $TICK_LENGTH
	      upCase
	   );

my $HOME = $ENV{HOME};
Readonly::Scalar $AH_CLASS => 'AUTOHARP_CLASS';
Readonly::Scalar $AH_DATA  => 'AUTOHARP_DATA';

Readonly::Scalar $DEFAULT_DIRECTORY        => "$HOME/autoharp";
Readonly::Scalar $DEFAULT_OCTAVE           => 4;
Readonly::Scalar $DEFAULT_ROOT_PITCH       => 48; #C4, octave below middle C
Readonly::Scalar $DEFAULT_MIDI_METER       => "4/4";
Readonly::Scalar $DEFAULT_MIDI_TEMPO       => 120;
Readonly::Scalar $EVENT_CHANNEL_AFTERTOUCH => 'channel_after_touch';
Readonly::Scalar $EVENT_CHORD              => 'chord';
Readonly::Scalar $EVENT_CONTROL_CHANGE     => 'control_change';
Readonly::Scalar $EVENT_KEY_AFTERTOUCH     => 'key_after_touch';
Readonly::Scalar $EVENT_KEY_SIGNATURE      => 'key_signature';
Readonly::Scalar $EVENT_INSTRUMENT_NAME    => 'instrument_name';
Readonly::Scalar $EVENT_MARKER             => 'marker';
Readonly::Scalar $EVENT_NOTE               => 'note';
Readonly::Scalar $EVENT_NOTE_OFF           => 'note_off';
Readonly::Scalar $EVENT_NOTE_ON            => 'note_on';
Readonly::Scalar $EVENT_PATCH_CHANGE       => 'patch_change';
Readonly::Scalar $EVENT_PITCH_WHEEL        => 'pitch_wheel_change';
Readonly::Scalar $EVENT_REST               => 'REST';
Readonly::Scalar $EVENT_SET_TEMPO          => 'set_tempo';
Readonly::Scalar $EVENT_TEXT               => 'text_event';
Readonly::Scalar $EVENT_TIME_SIGNATURE     => 'time_signature';
Readonly::Scalar $EVENT_TRACK_NAME         => 'track_name';
Readonly::Scalar $MAJOR_SCALE_INTERVALS    => [2,2,1,2,2,2,1];
Readonly::Scalar $MAX_TEMPO_BPM            => 500;
Readonly::Scalar $TICK_LENGTH              => 'length';
Readonly::Scalar $TICKS_PER_BEAT           => 240;
Readonly::Scalar $TRAINING_CHAOS           => 'training_chaos';
Readonly::Scalar $TRAINING_EPOCH           => 'training_epoch';
Readonly::Scalar $TRAINING_LOSS            => 'training_loss';
Readonly::Scalar $NOTE_MINIMUM_TICKS       => $TICKS_PER_BEAT / 4; #16th in 4/4

Readonly::Scalar $ATTR_AUTOHARP_SONG       => 'AutoHarpSong';
Readonly::Scalar $ATTR_BARS                => 'bars';
Readonly::Scalar $BASS_INSTRUMENT          => 'bass';
Readonly::Scalar $ATTR_BUCKET              => 'bucket';
Readonly::Scalar $ATTR_CHANNEL             => 'channel';
Readonly::Scalar $ATTR_CLOCK               => 'clock';
Readonly::Scalar $ATTR_LOOP_TYPE           => 'loop_type';
Readonly::Scalar $ATTR_LOOPS               => 'loops';
Readonly::Scalar $THEME_INSTRUMENT         => 'theme';
Readonly::Scalar $ATTR_COMPOSER            => 'composer';
Readonly::Scalar $ATTR_COMPOSITION         => 'composition';
Readonly::Scalar $ATTR_DIRECTORY           => 'directory';
Readonly::Scalar $DRUM_KIT                 => 'drumKit';
Readonly::Scalar $DRUM_LOOP                => 'drumLoop';
Readonly::Scalar $DEEP_DRUM_LOOP           => 'deepDrumLoop';
Readonly::Scalar $GENERATED_DRUM_LOOP      => 'generatedDrumLoop';
Readonly::Scalar $DRUM_RESOLUTION          => $TICKS_PER_BEAT / 8; #32nds
Readonly::Scalar $ATTR_DURATION            => 'duration';
Readonly::Scalar $ATTR_EFFECTS             => 'effects';
Readonly::Scalar $ATTR_FILE                => 'file';
Readonly::Scalar $ATTR_FOLLOW              => 'follow';
Readonly::Scalar $ATTR_GENERATOR           => 'generator';
Readonly::Scalar $ATTR_GENRE               => 'genre';
Readonly::Scalar $ATTR_MACHINE_GENRE       => 'Ex Machina';
Readonly::Scalar $ATTR_GUIDE               => 'guide';
Readonly::Scalar $HOOK_INSTRUMENT          => 'hook';
Readonly::Scalar $ATTR_HOOK                => 'hook';
Readonly::Scalar $ATTR_INSTRUMENT          => 'instrument';
Readonly::Scalar $ATTR_INSTRUMENTS         => 'instruments';
Readonly::Scalar $ATTR_INSTRUMENT_CLASS    => 'instrumentClass';
Readonly::Scalar $ATTR_INSTRUMENT_ROLE     => 'instrumentRole';
Readonly::Scalar $ATTR_INTERVALS           => 'intervals';
Readonly::Scalar $ATTR_KEY                 => 'key';
Readonly::Scalar $LEAD_INSTRUMENT          => 'lead';
Readonly::Scalar $ATTR_MELODY              => 'melody';
Readonly::Scalar $ATTR_METER               => 'meter';
Readonly::Scalar $ATTR_MIDI_FILE           => 'MIDIFile';
Readonly::Scalar $ATTR_MUSIC               => 'music';
Readonly::Scalar $ATTR_NAME                => 'name';
Readonly::Scalar $ATTR_NOTE                => 'note';
Readonly::Scalar $PAD_INSTRUMENT           => 'pad';
Readonly::Scalar $ATTR_PAN                 => 'pan';
Readonly::Scalar $ATTR_PATTERN             => 'pattern';
Readonly::Scalar $ATTR_PATCH               => 'patch';
Readonly::Scalar $ATTR_PITCH               => 'pitch';
Readonly::Scalar $ATTR_PROGRESSION         => 'progression';
Readonly::Scalar $RHYTHM_INSTRUMENT        => 'rhythm';
Readonly::Scalar $ATTR_RHYTHM_SPEED        => 'rhythmSpeed';
Readonly::Scalar $ATTR_ROOT_NOTE           => 'root';
Readonly::Scalar $ATTR_SCALE               => 'scale';
Readonly::Scalar $ATTR_SCALE_SPAN          => 12;
Readonly::Scalar $ATTR_SONG                => 'song';
Readonly::Scalar $ATTR_START_TIME          => 'startTime';
Readonly::Scalar $ATTR_STRAIGHT_TRANSITION => 'straight';
Readonly::Scalar $ATTR_UP_TRANSITION       => 'up';
Readonly::Scalar $ATTR_DOWN_TRANSITION     => 'down';
Readonly::Scalar $ATTR_TAG                 => 'tag';
Readonly::Scalar $ATTR_TEMPO               => 'tempo';
Readonly::Scalar $ATTR_TIME                => 'time';
Readonly::Scalar $ATTR_UID                 => 'uid';
Readonly::Scalar $ATTR_VELOCITY            => 'velocity';
Readonly::Scalar $ATTR_VERBOSE             => 'verbose';
Readonly::Scalar $ATTR_VOLUME              => 'volume';
Readonly::Scalar $PERCUSSION_CHANNEL       => 9;

Readonly::Scalar $MUSIC_BOX                   => 'MusicBox';
Readonly::Scalar $SONG_SECTION                => 'section';
Readonly::Scalar $COMP_ELEMENTS               => 'composition_elements';
Readonly::Scalar $SONG_ELEMENT                => 'element';
Readonly::Scalar $SONG_ELEMENT_BEGIN          => 'begin';
Readonly::Scalar $SONG_ELEMENT_BRIDGE         => 'bridge';
Readonly::Scalar $SONG_ELEMENT_CHORUS         => 'chorus';
Readonly::Scalar $SONG_ELEMENT_END            => 'end';
Readonly::Scalar $SONG_ELEMENT_FILL           => 'fill';
Readonly::Scalar $SONG_ELEMENT_INSTRUMENTAL   => 'instrumental';
Readonly::Scalar $SONG_ELEMENT_INTRO          => 'intro';
Readonly::Scalar $SONG_ELEMENT_LEADIN         => 'leadIn';
Readonly::Scalar $SONG_ELEMENT_LEADOUT        => 'leadOut';
Readonly::Scalar $SONG_ELEMENT_OUTRO          => 'outro';
Readonly::Scalar $SONG_ELEMENT_PRECHORUS      => 'prechorus';
Readonly::Scalar $SONG_ELEMENT_SOLO           => 'solo';
Readonly::Scalar $SONG_ELEMENT_TRANSITION     => 'transition';
Readonly::Scalar $SONG_ELEMENT_VERSE          => 'verse';
Readonly::Scalar $SONG_SEGMENT                => 'songSegment';


sub upCase {
  my $arg = shift;
  return uc(substr($arg,0,1)) . substr($arg,1);
}

"Can't go on saying the same things";
