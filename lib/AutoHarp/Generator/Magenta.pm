package AutoHarp::Generator::Magenta;

use strict;
use AutoHarp::Fuzzy;
use AutoHarp::Constants;
use Carp;


use base qw(AutoHarp::Generator);

my $TEMP_DIR  = "/tmp/ahgen";
my $TEMP_FILE = "$TEMP_DIR/tempmel.mid";
my $CONFIGS   = [qw(attention_rnn
		    basic_rnn
		    lookback_rnn)];

my $MAG_DIR = "$ENV{HOME}/workplace/magfiles";
my $STEPS   = "steps";
my $CHORDS  = "chords";

my $MELODY_CMD = "melody_rnn_generate --output_dir=$TEMP_DIR --config CONFIG --bundle_file $MAG_DIR/CONFIG.mag --num_outputs=1 --num_steps=STEPS";

my $MELODIZE_CMD = "improv_rnn_generate --config=chord_pitches_improv --bundle_file=$MAG_DIR/chord_pitches_improv.mag --output_dir=$TEMP_DIR --num_outputs=1 --backing_chords=\"CHORDS\" --steps_per_chord=STEPS";

sub generateMusic {
  my $self          = shift;
  my $guide         = shift;
  my $sourceMusic   = shift;

  #based on the new subset, generate some music
  my $newMusic = AutoHarp::MusicBox::Base->new($ATTR_GUIDE => $guide);

  if ($sourceMusic && $sourceMusic->hasMelody() &&$sourceMusic->hasProgression()) {
    if ($guide->duration <= $sourceMusic->duration() && sometimes) {
      #take the existing chord progression, magenta melodize it,
      #and re-harmonize that
      $newMusic->progression($sourceMusic->progression());
      $self->melodize($newMusic);
      $newMusic->unsetProgression();
    } else {
      #take the existing melody as the seed melody,
      #and continue in an rnn way from there
      $sourceMusic->melody->toFile("$TEMP_FILE");
      my $steps   = ($sourceMusic->bars() + $guide->bars()) * 16;
      my $file    = _generateMIDIFile($MELODY_CMD, 
				      {
				       $ATTR_MIDI_FILE => "$TEMP_FILE",
				       $STEPS => $steps
				      });
      my $totalMel  = AutoHarp::Events::Melody->fromFile($file);
      if (system("rm $file")) {
	croak "Cleanup of $file failed: $!\n";
      }
      
      my $mel = $totalMel->subMelody($sourceMusic->duration, $sourceMusic->duration + $guide->duration);
      $mel->time($guide->time);
      $newMusic->melody($mel);
    }
  } else {
    $self->generateMelody($newMusic);
  }
  $self->harmonize($newMusic);
  return $newMusic;
}

sub generateMelody {
  my $self      = shift;
  my $music     = shift;
  my $startNote = shift;

  if (!$music->duration()) {
    return $music->melody($AutoHarp::Events::Melody->new());
  }

  my $seedPitch = ($startNote) ? $startNote->pitch() : 
    $self->generatePitch({$ATTR_MUSIC => $music, $ATTR_TIME => $music->time});
  my $steps   = 16 * $music->bars;
  
  my $file = _generateMIDIFile($MELODY_CMD,
			       {$ATTR_PITCH => $seedPitch, $STEPS => $steps}
			      );
  my $mel  = AutoHarp::Events::Melody->fromFile($file);
  if (system("rm $file")) {
    croak "Cleanup of $file failed: $!\n";
  }
  $mel->time($music->time);
  return $music->melody($mel);
}

sub melodize {
  my $self = shift;
  my $music = shift;

  my $prog = $music->progression;

  #find out the gcd of chord lengths
  #to determine how to represent this
  #chord progression to the rnn
  # (most of the time this should be the full bar length,
  #  because this program is already keen
  #  to construct one-chord-per-bar melodies)
  
  my @lens = map {$_->duration()} @{$music->progression->chords()};
  my $mTime  = $music->clock()->measureTime();
  my $minGcd = $mTime / 16;
  my $gcd = 0; 
  if (scalar(@lens) > 1) {
    $gcd = _gcd($lens[0],$lens[1]);
    for (my $i = 2; $i < scalar @lens; $i++) {
      $gcd = _gcd($gcd,$lens[$i]);
    }
  } else {
    $gcd = $lens[0];
  }

  if (!$gcd || $gcd % $minGcd) {
    $music->progression->dump();
    confess "Calculated gcd for these chords as $gcd. I'm pretty sure that shouldn't happen, based on the way I harmonize stuff in this program";
  }
  
  my $stepsPerChord = ($mTime / $gcd) * 16;
  my $chordProgStr;
  for(my $i = $music->time; $i < $music->reach; $i += $gcd) {
    $chordProgStr .= $music->progression->chordAt($i)->toString();
    $chordProgStr .= " ";
  }
  #kill the trailing space
  chop($chordProgStr);
  my $seedPitch = $self->generatePitch({$ATTR_MUSIC => $music,
					$ATTR_TIME => $music->time});
   my $file = _generateMIDIFile($MELODIZE_CMD,
				{$ATTR_PITCH => $seedPitch,
				 $STEPS => $stepsPerChord,
				 $CHORDS => $chordProgStr
				}
			       );
  
  my $mel  = AutoHarp::Events::Melody->fromFile($file);
  if (system("rm $file")) {
    croak "Cleanup of $file failed: $!\n";
  }
  $mel->time($music->time);
  return $music->melody($mel);
}

sub _generateMIDIFile {
  my $makeCmd = shift;
  my $args    = shift;
  my $config  = shift || pickOne($CONFIGS);
  
  my $seedPitch = $args->{$ATTR_PITCH};
  my $steps = $args->{$STEPS};
  my $midiFile = $args->{$ATTR_MIDI_FILE};
  my $chords = $args->{$CHORDS};
  
  if ($midiFile) {
    $makeCmd .= " --primer_midi $midiFile";
  } elsif ($seedPitch) {
    $makeCmd .= " --primer_melody \"[$seedPitch]\"";
  }
  
  $makeCmd =~ s/CONFIG/$config/g;
  $makeCmd =~ s/STEPS/$steps/;
  $makeCmd =~ s/CHORDS/$chords/;
  
  print "Running: $makeCmd\n";
  if (system($makeCmd)) {
    croak "That, like, totally failed.\n";
  }
  
  opendir(MIDI, $TEMP_DIR) or croak "Couldn't open $TEMP_DIR: $!\n";
  my $now = 2 / (24 * 60 * 60); #should be less than two seconds old
  my $file = (grep {/\.mid/ && (-M "$TEMP_DIR/$_") < $now} readdir(MIDI))[0];
  if (!$file || !(-f "$TEMP_DIR/$file")) {
    croak "Couldn't retrieve generated midi file '$TEMP_DIR/$file'";
  }
  
  return "$TEMP_DIR/$file";
}

sub oldMelodize {
  my $self  = shift;
  my $music = shift;
  
  #this was my first guess. Saving it in case it turns out to be useful:
  
  #melodize it algorithmically,
  #then use that as the seed
  #split the resulting melody in half and use the second half

  my $seedMel = $self->SUPER::melodize($music, @_);
  if (asOftenAsNot) {
    return $music->melody($seedMel)
  }
  $seedMel->toFile($TEMP_FILE);
  my $steps   = $music->bars() * 2 * 16;
  my $file    = _generateMIDIFile($MELODY_CMD, 
				  {$ATTR_MIDI_FILE => "$TEMP_FILE",
				   $STEPS => $steps});
  my $resMel  = AutoHarp::Events::Melody->fromFile($file);
  
  if (system("rm $file")) {
    croak "Cleanup of $file failed: $!\n";
  }

  my $mel = $resMel->subMelody(($resMel->reach - $resMel->time) / 2, $resMel->reach);
  $mel->time($music->time);
  $mel->time($music->time);

  return $music->melody($mel);
}

sub _gcd {
  my ($a, $b) = @_;
  ($a,$b) = ($b,$a) if $a > $b;
  while ($a) {
    ($a, $b) = ($b % $a, $a);
  }
  return $b;
}
