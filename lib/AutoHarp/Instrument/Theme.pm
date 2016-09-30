package AutoHarp::Instrument::Theme;

use strict;
use AutoHarp::Events::Performance;
use AutoHarp::Constants;
use AutoHarp::Fuzzy;
use Carp;
use base qw(AutoHarp::Instrument);

my $THEME = 'themeMusicYeahBaby';
my $IDENTITY = 'themeIdentity';
my $THEME_TAG    = 'themeTag';

my $HARMONIZER   = 'harmonizer';
my $SLOW_THEME   = 'slowTheme';
my $FAST_THEME   = 'fastTheme';
my $FLOW_THEME   = 'flowTheme';
my $CYMBAL_THEME = 'cymbalTheme';
my $EARWORM_THEME = 'earworm';

my $aVals = {$IDENTITY => [$HARMONIZER,
			   $SLOW_THEME,
			   $FAST_THEME,
			   $FLOW_THEME,
			   $CYMBAL_THEME,
			   $EARWORM_THEME]};

my $VELOCITY_MOD = 2/3; #a swag. Oh yes it is

sub reset {
  my $self = shift;
  delete $self->{$THEME};
  delete $self->{$THEME_TAG};
}

sub attributes {
  return [$IDENTITY]
}

sub attributeValues {
  my $self = shift;
  my $a = shift;
  return $aVals->{$a} || [];
}
  
sub toString {
  my $self = shift;
  return $self->SUPER::toString() . ", $IDENTITY: " . $self->themeIdentity();
}

sub getFollowRequest {
  my $self = shift;
  
  if ($self->is($HARMONIZER)) {
    return pickOne($LEAD_INSTRUMENT,
		   $HOOK_INSTRUMENT,
		   $THEME_INSTRUMENT);
  } elsif (($self->is($FAST_THEME) || $self->is($SLOW_THEME)) 
	   && sometimes) {
    return pickOne($LEAD_INSTRUMENT,
		   $HOOK_INSTRUMENT,
		   $RHYTHM_INSTRUMENT,
		   $DRUM_KIT);
  }
  return;
}

sub is {
  my $self = shift;
  my $what = shift;
  return $self->themeIdentity() eq $what || $self->SUPER::is($what);
}

sub themeIdentity {
  return $_[0]->scalarAccessor($IDENTITY,$_[1]);
}
  
sub choosePatch {
  my $self = shift;
  my $inst = shift;

  #take this opportunity to also choose a theme identity
  if (!$self->themeIdentity()) {
    $self->themeIdentity(pickOne($ATTR_MELODY,
				 $FLOW_THEME,
				 $CYMBAL_THEME,
				 $EARWORM_THEME,
				 $SLOW_THEME,
				 $FAST_THEME,
				 $HARMONIZER
				));
  }
  if (!$inst) {
    #want plinky things if we are fast
    if ($self->is($FAST_THEME) || $self->is($CYMBAL_THEME)) {
      $inst = pickOne('piano',
		      'organ',
		      'guitar',
		      'sitar',
		      'Kalimba',
		      'Shanai',
		      'Koto',
		      'vibraphone',
		      'marimba',
		      'xylophone'
		     );
    } elsif ($self->is($FLOW_THEME)) {
      $inst = pickOne('synth lead',
		      'strings',
		      'pad',
		      'organ',
		      'FX',
		      'reed',
		      'ensemble');
    } else {
      $inst = pickOne('synth lead',
		      'piano',
		      'strings',
		      'chromatic percussion',
		      'ethnic',
		      'ensemble');
    } 
  }
  return $self->SUPER::choosePatch($inst);
}

sub playDecision {
  my $self     = shift;
  my $segment  = shift;

  if ($self->follow()) {
    #don't care right now, I follow
    return;
  } elsif ($self->is($ATTR_MELODY)) {
    #whenever the segment & the music agree 
    #e.g. it's the verse and the music is the verse
    return ($segment->musicTag() eq $segment->songElement());
  }

  if ($self->isPlaying()) {
    if ($segment->wasComeDown()) {
      return;
    } elsif ($segment->isChange()) {
      return ($self->{$THEME_TAG} eq $segment->musicTag()) ? rarely : 0;
    }
    return 1;
  }
  
  #this is the music we were generated from, and it has come back
  if ($self->{$THEME_TAG}) {
    if ($self->{$THEME_TAG} eq $segment->musicTag()) {
      return ($segment->isSecondHalf ||
	      $segment->isRepeat ||
	      $segment->elementIndex >= 3
	     ) ? mostOfTheTime : sometimes;
    }
    #no match. We not play
    return;
  }

  if ($segment->elementIndex() == 1 && 
      !$segment->isSecondHalf() &&
      !$segment->isRepeat()
     ) {
    #don't usually play at the introduction of something 
    return epicallySeldom;
  }

  #come in on the second verse?
  return sometimes if ($segment->isVerse() && $segment->elementIndex() == 2);
  #come in at the second half of something?
  return sometimes if ($segment->isSecondHalf);
  #come in when something repeats  
  return asOftenAsNot if ($segment->isRepeat());

  #otherwise, pretty much no
  return epicallySeldom;
}

sub play {
  my $self        = shift;
  my $segment     = shift;
  my $followMusic = shift;

  if ($self->is($ATTR_MELODY)) {
    return ($segment->musicBox()->hasMelody()) ? 
      $segment->musicBox()->melody()->clone() : undef;
  } elsif ($self->is($CYMBAL_THEME)) {
    return $self->cymbalPlay($segment,$followMusic);
  } elsif ($self->follow() && $followMusic) {
    return ($self->is($HARMONIZER)) ? 
      $self->harmonyPlay($segment,$followMusic) :
	$self->followPlay($segment,$followMusic);
  } 

  if (!$segment->musicBox->hasProgression) {
    #there is nothing that can be done for you
    return;
  }

  if (!$self->{$THEME}) {
    my $func = $self->themeIdentity() . "Create";
    $self->{$THEME}     = $self->$func($segment,$followMusic);
    $self->{$THEME_TAG} = $segment->musicTag();
  }

  my $adapted = $self->{$THEME}->adaptOnto($segment->musicBox());
  $adapted->time($segment->time);
  return $adapted->melody();
}

sub harmonyPlay {
  my $self             = shift;
  my $segment          = shift;
  my $thingToHarmonize = shift;

  my $play = AutoHarp::Events::Performance->new();
  $play->time($segment->time);

  my $harmony;
  my $keepAll = $segment->isSecondHalf();
  #start by whatevering everything
  if (sometimes) {
    $keepAll = 1;
    $harmony = $thingToHarmonize->double();
  } elsif (sometimes) {
    #thirds
    $harmony = $thingToHarmonize->harmonize($segment->musicBox->guide,2);
  } elsif (asOftenAsNot) {
    #fourth under
    $harmony = $thingToHarmonize->harmonize($segment->musicBox->guide,-3);
  } else {
    #octave
    $harmony = $thingToHarmonize->harmonize($segment->musicBox->guide,7);
    $keepAll = 1;
  }

  #then decide what to keep
  if ($keepAll) {
    #double, octave, or this is the second half? Go for it
    $play->add($harmony);
  } elsif ($segment->musicBox()->hasPhrases()) {
    #start harmonizing after the first phrase
    my $startAdd = $segment->time() + $segment->musicBox->phraseDuration();
    $play->add($harmony->subMelody($startAdd,$harmony->reach()));
  } else {
    foreach my $n (@{$harmony->notes()}) {
      my $clock = $segment->musicBox->clockAt($n->time);
      if ($clock->isOnTheBeat($n->time) || sometimes) {
	$play->add($n);
      }
    }
  }
  __adjustVelocity($play);
  return $play;
}

sub followPlay {
  my $self     = shift;
  my $segment  = shift;
  my $toFollow = shift;
  
  my $music    = $segment->musicBox();

  if ($toFollow->isPercussion()) {
    #pick a drum and follow that
    my $opts = $toFollow->split();
    #prefer one with a lot of notes--we may filter out some in a minute
    my $choice;
    while (my ($d,$track) = each %$opts) {
      $choice = $track->clone() 
	if (!$choice || scalar {@$track->notes()} > scalar {@$choice->notes()});
    }
    #these notes and durations won't be right
    my $prevPitch;
    foreach my $n (@{$choice->notes()}) {
      $n->duration($NOTE_MINIMUM_TICKS);
      my $c = ($music->hasProgression()) ? 
	$music->progression->chordAt($n->time) : undef;
      
      if (!$c || sometimes) {
	my $pitch = -1;
	while ($pitch == -1) {
	  $pitch = AutoHarp::Generator->new()->
	    generatePitch({$ATTR_MUSIC => $segment->musicBox(),
			   $ATTR_TIME => $n->time,
			   $ATTR_PITCH => $prevPitch
			  });
	  $n->pitch($pitch);
	}
      } else {
	$n->pitch(pickOne($c->pitches()));
      }
      $prevPitch = $n->pitch();
    }
  }
  my $perf = AutoHarp::Events::Performance->new();
  $perf->time($segment->time);
  my $seen = {};
  my $octave = pickOne(5,6,7);
  my $lastOne;
  foreach my $n (@{$toFollow->notes()}) {
    next if ($seen->{$n->time}++);
    my $new = $n->clone();
    $new->octave($octave);
    if ($self->is($FAST_THEME)) {
      $perf->add($new);
    } else {
      my $clock = $music->clockAt($n->time);
      if (!$lastOne || $n->time >= $lastOne + $clock->beatTime()) {
	$perf->add($new);
	$lastOne = $n->time;
      }
    }
  }
  __adjustVelocity($perf);
  return $perf;
}

sub cymbalPlay {
  my $self    = shift;
  my $segment = shift;
  my $drums   = shift;
  #find the most prevalent cymbals 
  my $ct;
  my $cymbal;
  my $split = $drums->split();
  foreach my $k (grep {/(Hi-Hat|Cymbal)/} keys %$split) {
    my $hits = scalar @{$split->{$k}->notes()};
    if ($hits > $ct) {
      $ct = $hits;
      $cymbal = $k;
    }
  }
  if ($ct) {
    my $perf = AutoHarp::Events::Performance->new();
    $perf->time($segment->time);
    if (!$self->{$THEME}) {
      #grab a fast theme to be our theme
      $self->{$THEME} = $self->themeCreate($segment,4);
      $self->{$THEME_TAG} = $segment->musicTag();
    }
    my $theme = $self->{$THEME};
    my $notes = $theme->adaptOnto($segment->musicBox())->melody();
    foreach my $c (@{$split->{$cymbal}->notes()}) {
      my $n = pickOne($notes->notesAt($c->time));
      if ($n) {
	my $cnote = $n->clone();
	$cnote->time($c->time);
	$perf->add($cnote);
      }
    }
    __adjustVelocity($perf);
    return $perf;
  }
  return;
}

#create these as hooks, 
#which will allow us to adapt it to 
#whatever chord progression we wish
sub slowThemeCreate {
  my $self    = shift;
  my $segment = shift;
  return $self->themeCreate($segment,pickOne(1,.5));
}

sub fastThemeCreate {
  my $self    = shift;
  my $segment = shift;
  my $clock   = $segment->musicBox->clock();
  my $isFast  = $clock->tempo > 100;
  my $speed   = ((!$isFast && almostAlways) ||
		 ($isFast && rarely)) ? 2 : 4;
  my $theme = $self->themeCreate($segment,$speed);
  #sometimes truncate the notes
  if ($speed == 2 && asOftenAsNot) {
    grep {$_->duration($_->duration / 2)} @{$theme->melody()->notes()}
  }
  return $theme;
}
 
sub themeCreate {
  my $self    = shift;
  my $segment = shift;
  my $speed   = shift;
  my $clock   = $segment->musicBox->clock();
  
  #create a measure of some stuff
  my $subMusic = $segment->musicBox->subMusic($segment->time,
					   $segment->time + $clock->measureTime);
  #melodize it with even beats or half notes...
  AutoHarp::Generator->new()->melodize($subMusic,{$ATTR_RHYTHM_SPEED => $speed});

  if (!$subMusic->melody()->hasNotes()) {
    $subMusic->dump();
    confess "Didn't generate any notes in themeCreate at speed $speed!";
  }
  #toy with the velocity
  __adjustVelocity($subMusic->melody());

  #and turn it into a hook
  return $subMusic->toHook();
}

#flow theme sounds a note with each chord
sub flowThemeCreate {
  my $self    = shift;
  my $segment = shift;
  my $music   = $segment->musicBox();

  my $perf = AutoHarp::Events::Melody->new();
  $perf->time($segment->time);
  my $octave = pickOne(5,6,7);

  my $prevPitch;
  my $gen  = AutoHarp::Generator->new();
  my $lastPitch;
  foreach my $c (@{$music->progression->chords()}) {
    #generate as long as the phrase so that we repeat with it
    last if ($c->time >= $music->time + $music->phraseDuration());
    my $s   = $music->scaleAt($c->time);
    my $note = pickOne($c->toNotes());
    if (sometimes) {
      my $int = $s->steps($note->pitch,pickOne(5,6,8)); #6th, 7th or 9th
      $note->pitch($int);
    }
    $note->octave($octave);
    #possibly normalize a little
    if ($lastPitch) {
      if ($lastPitch > $note->pitch && 
	  $lastPitch - $note->pitch > ($s->scaleSpan / 2)) {
	$note->octave($octave + 1);
      } elsif ($lastPitch < $note->pitch &&
	       $note->pitch - $lastPitch > ($s->scaleSpan / 2)) {
	$note->octave($octave - 1);
      }
    }
    $lastPitch = $note->pitch;
    $perf->add($note);
  }
  __adjustVelocity($perf);
  my $pm = $music->subMusic($music->time,$perf->reach());
  $pm->melody($perf);
  return $pm->toHook();
}

#earworm is a couple of notes repeated over and over again
sub earwormCreate {
  my $self      = shift;
  my $segment   = shift;
  my $clock     = $segment->musicBox->clock();
  my $model     = $segment->musicBox->subMusic($segment->time,
					    $segment->time + $clock->measureTime);
  my $mel       = AutoHarp::Generator->new()->generateMelody($model);
  #we'll divvy the beats into quarters, and determine a random start and end
  #within a single measure
  $mel->time(0);
  my $earworm   = AutoHarp::Events::Melody->new();
  $earworm->time(0);
  my $fuckingSanity = 0;
  my $bpm       = $clock->beatsPerMeasure();
  my $octave = pickOne(4,5,6);
  while (!$earworm->duration) {
    if ($fuckingSanity++ > 10) {
      confess "EARWORM SUCKS!";
    }

    my $startQ    = int(rand(($bpm - 1) * 4) + 1);
    my $headRoom  = (($bpm + 1) * 4) - $startQ; 
    my $endQ      = $headRoom - int(rand($headRoom) / 2);
    my $startT    = $startQ * ($clock->beatTime / 4);
    my $endT      = $endQ * ($clock->beatTime / 4);
    foreach my $n (grep {$_->reach > $startT &&
			   $_->time < $endT} @{$mel->notes()}) {
      if ($n->time < $startT) {
	$n->time($startT);
	$n->duration($n->duration - ($startT - $n->time));
      } 
      if ($n->reach > $endT) {
	$n->duration($n->duration - ($n->reach - $endT));
      }
      $n->octave($octave);
      $earworm->add($n);
    }
  }
  __adjustVelocity($earworm);
  $model->melody($earworm);
  return $model->toHook();
}

#could happen if we don't have the thing the harmonizer wants to follow
sub harmonizerCreate {
  my $self = shift;
  return $self->flowThemeCreate(@_);
}

sub __adjustVelocity {
  my $thing = shift;
  #toy with the velocity
  foreach my $n (@{$thing->notes()}) {
    $n->velocity(int($n->velocity * $VELOCITY_MOD));
  }
}

"Yeah you took a stand next to 'The Man Who Used to Hunt Cougars for Bounty'";
