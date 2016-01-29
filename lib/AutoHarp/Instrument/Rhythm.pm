package AutoHarp::Instrument::Rhythm;

use strict;
use base qw(AutoHarp::Instrument);
use Carp;
use Data::Dumper;
use AutoHarp::Constants;
use AutoHarp::Fuzzy;
use AutoHarp::Event::Note;
use AutoHarp::Events::Performance;

my $RHYTHM_PATTERN = 'rhythmPattern';
my $PLAY_VARS      = 'playVariables';

my $OFFBEAT        = 'offBeat';
my $FOLLOW_HATS    = 'followHats';
my $CHORD_TYPE     = 'chordType';
my $OCTAVE         = 'octave';
my $WENT_CRAZY     = 'wentCrazy';

my $DOUBLE_STOP = 'doubleStop';

my $REGGAE      = 'Reggae';
my $FUNK        = 'Funk';
my $JAZZ        = 'Jazz';
my $BIG_EASY    = 'Big Easy';

my $VELOCITY_MOD = 1/2; #to be fudged?

sub choosePatch {
  my $self  = shift;
  my $inst  = shift;
  if (!$inst) {
    $inst = pickOne('acoustic guitar','piano','organ','strings');
  }
  $self->SUPER::choosePatch($inst);
}

sub toString {
  my $self = shift;
  return $self->SUPER::toString(). ", " .
    join(", ",map {"PV_$_: $self->{$PLAY_VARS}{$_}"} keys %{$self->{$PLAY_VARS}});
}

sub fromString {
  my $class = shift;
  my $self = $class->SUPER::fromString(@_);
  my @varKeys = grep {/^PV_/} keys %$self;
  foreach my $k (@varKeys) {
    my $pv = ($k =~ /PV_(.+)/)[0];
    $self->{$PLAY_VARS}{$pv} = $self->{$k};
    delete $self->{$k};
  }
  return $self;
}
      
sub reset {
  my $self = shift;
  delete $self->{$RHYTHM_PATTERN};
  delete $self->{$PLAY_VARS};
}

sub playDecision {
  my $self    = shift;
  my $segment = shift;

  if ($segment->isIntro()) {
    return asOftenAsNot;
  } elsif ($segment->isVerse() && $segment->elementIndex == 2) {
    return sometimes;
  }
  return almostAlways;
}

sub playVariables {
  my $self = shift;
  return $self->{$PLAY_VARS} || {};
}

sub play {
  my $self    = shift;
  my $segment = shift;
  my $follow  = shift;
  my $music   = $segment->musicBox();

  if (!$music->hasProgression()) {
    #I have nothing I can do for you
    return;
  }

  my $loop = $self->{$RHYTHM_PATTERN}{$music->tag()}
    ||= $self->buildLoop($segment,$follow);

  my $perf = $loop->clone();
  $perf->time($segment->time);
  return $perf;
}

#the basis upon which we decide our type of rhythm
sub setPlayVariables {
  my $self      = shift;
  my $genreName = shift;
  #variables:
  #off-beat (reggae and sometimes jazz or funk) or on-beat (everything else)
  my $offBeat  = (($genreName =~ /$REGGAE/i && unlessPigsFly) ||
		  ($genreName =~ /($FUNK|$JAZZ|$BIG_EASY)/ && rarely) ||
		  almostNever);
  my $octave    = pickOne(4,5,6);  
  my $chordType = $EVENT_CHORD;

  #type -- note, double-stop, full chord
  my $isGuitar  = $self->is('guitar');
  #follow smalls (hats or incidentals)
  #or follow bigs (kicks and snares)
  my $followHats = 0;
  if ($isGuitar && asOftenAsNot) {
    $chordType = (almostAlways) ? $EVENT_NOTE : $DOUBLE_STOP;
    $followHats = 1;
  } elsif (!$isGuitar && rarely) {
    $chordType = (almostAlways) ? $DOUBLE_STOP : $EVENT_NOTE;
    $followHats = 1;
  }
  $self->{$PLAY_VARS} = {$OFFBEAT => $offBeat,
			 $CHORD_TYPE => $chordType,
			 $OCTAVE => $octave,
			 $FOLLOW_HATS => $followHats,
			};
}

sub buildLoop {
  my $self             = shift;
  my $segment          = shift;
  my $guidePerformance = shift;
  my $music            = $segment->musicBox();
  my $progression      = $segment->musicBox->progression;
  my $genreName        = ($segment->genre()) ? 
    $segment->genre()->name : 'Ex Machina';
  
  my $loop = AutoHarp::Events::Performance->new();
  $loop->time($segment->time());

  if (!$self->{$PLAY_VARS}) {
    $self->setPlayVariables($genreName);
  }
  #off-beat (reggae and sometimes jazz or funk) or on-beat (everything else)
  my $offBeat  = $self->{$PLAY_VARS}{$OFFBEAT};
  my $octave = $self->{$PLAY_VARS}{$OCTAVE};
  my $chordType = $self->{$PLAY_VARS}{$CHORD_TYPE};
  my $followHats = $self->{$PLAY_VARS}{$FOLLOW_HATS};

  $self->{$PLAY_VARS}{$WENT_CRAZY} = 0;
  if (almostNever) {
    $self->{$PLAY_VARS}{$OFFBEAT} = $offBeat = !$offBeat;
  } elsif (almostNever) {
    $octave += plusMinus();
    $self->{$PLAY_VARS}{$WENT_CRAZY}++;
  } elsif (almostNever) {
    $chordType = pickOne($EVENT_CHORD,$EVENT_NOTE,$DOUBLE_STOP);
    if ($chordType eq $EVENT_NOTE && almostAlways) {
      $followHats = 1;
    } 
    $self->{$PLAY_VARS}{$WENT_CRAZY}++;
  } 

  if ($offBeat) {
    #offbeat doesn't require looking at the drums
    foreach my $m (@{$music->eachMeasure()}) {
      my $clock = $music->clockAt($m);
      my $bTime = $clock->beatTime();
      foreach my $b (1..$clock->beatsPerMeasure()) {
	my $time = $m + ($b * $bTime) - ($bTime / 2);
	my $pChord = $progression->chordAt($time);
	next if (!$pChord);
	foreach my $n (@{$pChord->toNotes()}) {
	  $n->octave($octave);
	  $n->velocity(hardVelocity() * $VELOCITY_MOD);
	  $n->time($time);
	  $n->duration($bTime / 2);
	  $loop->add($n);
	}
      }
    }
    return $loop;
  }

  
  #gets an array of measure times for the given loop
  my $rhythmGuide = $self->buildRhythmGuide($segment,$guidePerformance,$followHats);
  my $pattern;
  my $soundingUntil;
  my $lastPitch;
  for(my $i = 0; $i < scalar @$rhythmGuide; $i++) {
    my $this  = $rhythmGuide->[$i];
    my $next  = $rhythmGuide->[$i + 1];

    next if (!$this->isNote());

    my $time  = $this->time;
    my $vel   = $this->velocity;

    if ($soundingUntil > $segment->time && $time < $soundingUntil) {
      #we're still hitting a previous chord. 
      #Add some aftertouch, but no new note
      $loop->add([$EVENT_CHANNEL_AFTERTOUCH,
		  $time,
		  0,
		  $vel]);
      next;
    }

    my $pChord = $progression->chordAt($time);
    next if (!$pChord);

    my $clock      = $music->clockAt($time);
    my $toNextBeat = $clock->toNextBeat($time);
    my $toNextNote = ($next) ? $next->time - $time : $clock->beatTime();
    my $duration   = ($toNextNote < $toNextBeat) ? $toNextNote : $toNextBeat;
    $duration = $NOTE_MINIMUM_TICKS if ($duration < $NOTE_MINIMUM_TICKS);

    if ($time == $pChord->time &&
	($pattern || ($chordType eq $EVENT_CHORD && asOftenAsNot))) {
      #we're on the first hit of the chord. 
      #Let's hold it for a bit
      my $chordDur = $pChord->duration();
      if ($pattern) {
	$duration = ($pattern <= $chordDur) ? $pattern : $chordDur;
      } else {
	while ($duration < $chordDur && mostOfTheTime) {
	  my $a = ($toNextNote < $toNextBeat) ? $toNextNote : $toNextBeat;
	  $duration += $a;
	}
	$pattern = $duration;
      }
    }
    
    $soundingUntil = $time + $duration;

    if ($soundingUntil > $segment->reach() + $NOTE_MINIMUM_TICKS) {
      confess sprintf("Rhythm overshot the end of the segment.\nPattern len: %d\nnote duration: %d\nnote going from %d to %d\nsegment %d to %d,chose lesser of %d and %d\n",
		      $pattern, 
		      $duration, 
		      $time,
		      $soundingUntil,
		      $segment->time(),
		      $segment->reach(),
		      $toNextBeat,
		      $toNextNote);
    }
    my $notes = [];
    #start with all the notes in the chord. 
    #We may ignore them 
    #or filter a few out
    foreach my $n (@{$pChord->toNotes()}) {
      $n->octave($octave);
      $n->velocity($vel);
      $n->time($time);
      $n->duration($duration);
      push(@$notes,$n);
    }

    if ($chordType eq $EVENT_NOTE) {
      if ($time == $pChord->time && almostAlways) {
	#we're right on the start of the chord, pick the root note
	my $root = $pChord->root();
	$root->octave($octave);
	$root->velocity($vel);
	$root->time($time);
	$root->duration($duration);
	$notes = [$root];
	$lastPitch = $root->pitch();
      } else {
	#make it something interesting
	$notes = [pickOne(@$notes)];
	my $pitch = AutoHarp::Generator->new()->
	  generatePitch({$ATTR_MUSIC => $segment->musicBox(),
			 $ATTR_PITCH => $lastPitch,
			 $ATTR_TIME => $time});
	if ($pitch > -1) {
	  $notes->[0]->pitch($pitch);
	}
	$lastPitch = $notes->[0]->pitch;
      }
    } elsif ($chordType eq $DOUBLE_STOP) {
      #pick two
      while (scalar @$notes > 2) {
	my $buhBye = int(rand(scalar @$notes));
	splice(@$notes,$buhBye,1);
      }
    }
    foreach my $n (@$notes) {
      $loop->add($n);
    }
  }
  return $loop;
}

sub buildRhythmGuide {
  my $self     = shift;
  my $segment  = shift;
  my $follow   = shift;
  my $useHats  = shift;

  my $rhythmGuide = AutoHarp::Events::DrumTrack->new();
  $rhythmGuide->time($segment->time);
  my $clock = $segment->musicBox->clock();
  my @drums;
  my $hits = ($follow) ? $follow->split() : {};
  if ($follow && $follow->time == $segment->time) {
    @drums     = ($useHats) ? grep {/Hat/i} keys %$hits :
      grep {/(Snare|Open Hi-Hat)/i} keys %$hits;

    while (!scalar @drums) {
      #got nothin? Choose somethin' random
      @drums = grep {asOftenAsNot} keys %$hits;
    }
  }

  
  if (@drums) {
    foreach my $drum (@drums) {
      foreach my $note (@{$hits->{$drum}->notes()}) {
	my $g = $note->clone();
	#pitch doesn't matter, make it the same everywhere so 
	#we don't accidentally add a double hit someplace
	$g->pitch($DEFAULT_ROOT_PITCH);
	$g->velocity($note->velocity() * $VELOCITY_MOD);
	$rhythmGuide->add($g);
      }
    }
    #we might need to prune a little if we are large with the drum stuff
    my $last;
    my $space = ($useHats) ? $clock->beatTime / 4 : $clock->beatTime / 2;
    for(my $i = 0; $i < scalar @$rhythmGuide; $i++) {
      my $h = $rhythmGuide->[$i];
      next if (!$h->isNote());
      if ($last && ($h->time - $last->time) < $space) {
	splice(@$rhythmGuide,$i,1);
	$i--;
      } else {
	$last = $h;
      }
    }
  } else {
    #gotta fudge it.
    my $gen = AutoHarp::Generator->new();
    if ($useHats) {
      my $fakeHat = ($clock->tempo() < 95) ? 
	$clock->beatTime() / 4 : $clock->beatTime() / 2;
      my $t = $segment->time();
      while ($t < $segment->reach()) {
	my $fakeNote = AutoHarp::Event::Note->new();
	$fakeNote->pitch($DEFAULT_ROOT_PITCH);
	$fakeNote->duration($DRUM_RESOLUTION);
	$fakeNote->time($t);
	$gen->setNoteVelocity({$ATTR_NOTE => $fakeNote,
			       $ATTR_CLOCK => $clock});
	$rhythmGuide->add($fakeNote);
	$t += $fakeHat;
      }
    } else {
      #just do the chords. Got nothin' else
      foreach my $c (@{$segment->musicBox->progression->chords()}) {
	my $n = $c->root();
	$n->velocity(mediumVelocity() * $VELOCITY_MOD);
	$rhythmGuide->add($n);
      }
    }
  }
  if (!$rhythmGuide->hasNotes()) {
    $follow->dump();
    confess "Got no hits on which to base rhythm track\n";
  }
  return $rhythmGuide;
}


"I find you holding your head in your hands";
