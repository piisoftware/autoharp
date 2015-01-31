package AutoHarp::Instrument::DrumKit;

use MIDI;
use strict;
use AutoHarp::Event::Note;
use AutoHarp::Event::Chord;
use AutoHarp::Fuzzy;
use AutoHarp::Constants;
use AutoHarp::Events::DrumTrack;
use Carp;
use Data::Dumper;

use base qw(AutoHarp::Instrument);

my $DOWNBEAT_PATTERN = 'downbeatPattern';

sub choosePatch {
  my $self = shift;
  confess "Do not invoke DrumKit.\nUse 'DrumLoop' instead.\nDrumKit is hateful and sucks too much to live.\n";
}

sub name {
  return 'Drum Kit';
}

sub isDrums {
  return 1;
}

sub reset {
  my $self = shift;
  delete $self->{$DOWNBEAT_PATTERN};
}

#keep track of the pattern we're playing
#especially important in odd tempos
sub downbeatPattern {
  my $self = shift;
  my $clock = shift;
  my $bPer  = $clock->beatsPerMeasure();
  if (!$self->{$DOWNBEAT_PATTERN} || !$self->{$DOWNBEAT_PATTERN}{$bPer}) {
    $self->{$DOWNBEAT_PATTERN}{$bPer} = __buildPattern($bPer);
  }
  return $self->{$DOWNBEAT_PATTERN}{$bPer};
}

sub __buildPattern {
  my $len = shift;
  my $p;
  if (asOftenAsNot) {
    while (!($len % 3) || $len > 4) {
      $p .= "3-";
      $len -= 3;
    }
    while ($len > 0) {
      $p .= "2-";
      $len -= 2;
    }
  } else {
    while (!($len % 2) || $len > 3) {
      $p .= "2-";
      $len -= 2;
    }
    $p .= "3-";
  }
  $p =~ s/\-$//;
  #scramble it a little  
  while(sometimes) {
    my @split = split("-",$p);
    my $i = int(rand(scalar @split));
    my $j = int(rand(scalar @split));
    my $p = splice(@split,$i,1);
    splice(@split,$j,0,$p);
    $p = join("-",@split);
  }
  return $p;
}

######
#BEATS
###### 
#Actually handles anything even
sub four {
  my $self          = shift;
  my $clock         = shift;
  my $m             = shift;
  my $beat          = AutoHarp::Events::DrumTrack->new();
  my $bLen          = $clock->beatTime;
  my $beats         = $clock->beatsPerMeasure();
  
  my $time = 0;
  foreach my $b (1..$beats) {
    my $hat  = ($m % 2 || $b % $beats) ? __closedHat() : __openHat();
    $hat->time($time + $bLen / 2);
    $hat->velocity(softVelocity());
    $beat->add([($b % 2) ? __kick($time) : __snare($time),
		__closedHat($time),
		$hat]);
    if ($b == 1) {
      if (rarely) {
	#add a soft kick right before the half-way point kick
	$beat->add(__softerKick($time + ($bLen/2)));
      }
    } elsif ($b % 2) {
      if (rarely) {
	#right before middle beats
	$beat->add(__softerKick($time - ($bLen/2)));
      }
      if (asOftenAsNot) {
	#and one after
	$beat->add(__softKick($time + ($bLen/2)));
      }
    } elsif ($b == $beats) {
      if (sometimes) {
	#pickup to the next measure
	$beat->add(__softKick($time + ($bLen/2)));
      }
    }
    $time += $bLen;
  }
  return $beat;
}

sub waltz {
  my $self     = shift;
  my $clock    = shift;
  my $measure  = shift;
  return $self->three($clock, $measure);
}

sub march {
  my $self     = shift;
  my $clock    = shift;
  my $measure  = shift;
  return $self->twoSnare($clock,$measure);
}

sub five {
  my $self     = shift;
  my $clock    = shift;
  my $measure  = shift;
  my $bLen     = $clock->beatTime();
  my $hLen     = $bLen / 2;
  my $beat     = AutoHarp::Events::DrumTrack->new();
  my $time     = 0;
  $beat->add(__kick($time));
  $beat->add(__closedHat($time));
  $time += $bLen;
  $beat->add(__kick($time));
  $beat->add(__closedHat($time));
  $beat->add(__softKick($time + $hLen));
  $time += $bLen; 
  $beat->add(__snare($time));
  $beat->add(__closedHat($time));
  $time += $bLen;
  $beat->add(__kick($time));
  $beat->add(__closedHat($time));
  $beat->add(__softKick($time + $hLen));
  $time += $bLen; 
  $beat->add(__snare($time));
  if ($measure % 4) {
    $beat->add(__closedHat($time));
  } elsif (asOftenAsNot) {
    $beat->add(__openHat($time));
  } else {
    $beat->add(__closedHat($time));
    $beat->add(__openHat($time + $hLen,softVelocity()));
  }
  return $beat;
}

sub six {
  my $self      = shift;
  my $clock     = shift;
  my $measure   = shift;
  my $firstBit  = $self->three($clock,$measure);
  my $secondBit = $self->threeSnare($clock,$measure);
  #add a pickup kick on the last beat
  my $k = __softKick($clock->beatTime * 2);
  
  $secondBit->add(__softKick($clock->beatTime * 2));
  $firstBit->time(0);
  $secondBit->time($clock->measureTime / 2);
  $firstBit->add($secondBit);
  return $firstBit;
}

sub ten {
  my $self     = shift;
  my $clock    = shift;
  my $measure  = shift;
  my $first    = $self->five($clock,$measure);
  my $second   = $self->five($clock,$measure);
  $first->time(0);
  $second->time($clock->measureTime / 2);
  $first->add($second);
  return $first;
}

sub twelve {
  my $self    = shift;
  my $clock   = shift;
  my $measure = shift;
  my $first   = $self->three($clock,$measure);
  my $second  = $self->threeSnare($clock,$measure);
  my $third   = $self->three($clock,$measure);
  my $fourth  = $self->threeSnare($clock,$measure);
  $first->time(0);
  $second->time($clock->measureTime / 4);
  $third->time($clock->measureTime / 2);
  $fourth->time($clock->measureTime * .75);
  $first->add($second);
  $first->add($third);
  $first->add($fourth);
  return $first;
}
  
#generic beat based on a pattern, e.g. 2-2-3 for 7/8
sub patterned {
  my $self     = shift;
  my $clock    = shift;
  my $measure  = shift;
  my $pattern  = $self->downbeatPattern($clock);
  my $beat     = AutoHarp::Events::DrumTrack->new();
  my $time = 0;
  my @pat = split("-",$pattern);
  for (my $i = 0; $i < scalar @pat; $i++) {
    my $next;
    my $b = $pat[$i];
    my $n = $pat[$i + 1];
    if ($b == 2) {
      $next = ($b == $n) ? $self->two($clock, $measure) :
	$self->twoSnare($clock,$measure);
    } elsif ($b == 3) {
      $next = ($b == $n) ? $self->three($clock, $measure) :
	$self->threeSnare($clock, $measure);
    } elsif ($b == 4) {
      $next = $self->four($clock, $measure);
    } else {
      confess "Encountered unparseable pattern: $pattern";
    }
    $next->time($time);
    $beat->add($next);
    $time += $b * $clock->beatTime();
  }
  return $beat;
}

sub two {
  my $self    = shift;
  my $clock   = shift;
  my $measure = shift;
  my $beat    = AutoHarp::Events::DrumTrack->new();
  my $hat     = ($measure % 4) ? __closedHat($clock->beatTime) : __openHat($clock->beatTime);
  $beat->add([__kick(0),__closedHat(0)]);
  $beat->add($hat);
  if (!($measure % 4)) {
    $beat->add(__softKick($clock->beatTime / 2));
  }
  return $beat;
}

sub twoSnare {
  my $self  = shift;
  my $clock = shift;
  my $measure = shift;
  my $beat = $self->two($clock,$measure);
  $beat->add(__snare($clock->beatTime()));
  return $beat;
}

sub three {
  my $self    = shift;
  my $clock   = shift;
  my $measure = shift;
  my $beat    = AutoHarp::Events::DrumTrack->new();
  $beat->add([__kick(0),__closedHat(0)]);
  $beat->add(__closedHat($clock->beatTime));
  $beat->add(($measure % 4) ? __closedHat($clock->beatTime * 2) : __openHat($clock->beatTime * 2));
  return $beat;
}

  
sub threeSnare {
  my $self   = shift;
  my $clock  = shift;
  my $measure = shift;
  my $beat    = AutoHarp::Events::DrumTrack->new();
  $beat->add([__snare(0),__closedHat(0)]);
  $beat->add(__closedHat($clock->beatTime));
  $beat->add(($measure % 4) ? __closedHat($clock->beatTime * 2) : __openHat($clock->beatTime * 2));
  return $beat;
}
 
sub generateBeat {
  my $self     = shift;
  my $segment  = shift;
  my $music    = $segment->music();
  my $measures = $music->eachMeasure();
  my $beat     = AutoHarp::Events::DrumTrack->new();
  $beat->time($measures->[0]);
  for(my $i = 0; $i < scalar @$measures; $i++) {
    my $mTime    = $measures->[$i];
    my $measure  = $i + 1;
    my $clock    = $music->clockAt($mTime);
    my $bpMeas   = $clock->beatsPerMeasure();
    my $next;
    for ($bpMeas) {
      ($_ eq 2)  && do {$next = $self->march($clock,$measure); last;};
      ($_ eq 3)  && do {$next = $self->waltz($clock,$measure); last;};
      ($_ eq 4)  && do {$next = $self->four($clock,$measure); last;};
      ($_ eq 5)  && do {$next = $self->five($clock,$measure); last;};
      ($_ eq 6)  && do {$next = $self->six($clock,$measure); last;};
      ($_ eq 10) && do {$next = $self->ten($clock,$measure); last;};
      ($_ eq 12) && do {$next = $self->twelve($clock,$measure); last;};
      $next = $self->patterned($clock,$measure);
    }
    $next->time($mTime);
    $beat->add($next);
  }

  if (!$self->isPlaying()) {
    #did I start playing just now? I probably want to play some sort of pickup
    if (almostAlways) {
      my $clock = $music->clock();
      my $len   = pickOne(1,2) * $clock->beatTime();
      my $fill  = $self->fill($clock,$len);
      $fill->time($segment->time - $len);
      $beat->add($fill);
    }
  }
  return $beat;
}

sub playDecision {
  my $self      = shift;
  my $segment   = shift;

  my $wasPlaying = $self->isPlaying();
  my $playNextSegment;
  if ($wasPlaying) {
    $playNextSegment = unlessPigsFly;
  } elsif ($segment->songElement() eq $SONG_ELEMENT_INTRO) {
    $playNextSegment = asOftenAsNot;
  } else {
    $playNextSegment = mostOfTheTime;
  }
  return $playNextSegment;
}

sub transition {
  my $self      = shift;
  my $segment   = shift;
  my $beat      = shift;

  my $clock     = $segment->music->clockAtEnd();
  my $bTime     = $clock->beatTime;
  my $bPer      = $clock->beatsPerMeasure();
  my $fill      = AutoHarp::Events::DrumTrack->new();
  my $fillTime  = 0;
  if ($segment->transitionOutIsDown()) {
    #whatever we do, leave a measure's worth of space for a come-down
    $fillTime = $clock->measureTime();
    if (almostAlways) {
      #come down transition--tick off the beats and do a lead in
      my $tick = __tickDrum();
      my $time = 0;
      for (1..($bPer - 1)) {
	$tick->time($time);
	$fill->add($tick);
	$time += $bTime;
      }
    } 
    if (asOftenAsNot) {
      #single hit on the last beat
      $fill->add(__fillDrum($fillTime - $bTime));
    } elsif (almostAlways) {
      #go with a one-beat fill
      my $subFill = $self->fill($clock,$bTime);
      $subFill->time($fillTime - $bTime);
      $fill->add($subFill);
    }
  } else {
    if ($segment->isSongBeginning()) {
      $fillTime = (mostOfTheTime) ? $bTime : (often) ? 0 : 'random';
    } elsif ($segment->transitionOutIsUp) {
      $fillTime = (almostAlways) ? $clock->measureTime : 'random';
    } else {
      $fillTime = (sometimes) ? 'random' : $bTime;
    }
    if ($fillTime) {
      $fill = $self->fill($clock, ($fillTime > 0) ? $fillTime : undef);
    }
  }

  if ($fillTime > 0) {
    #cut everything off the beat to make space for the fill
    my $tTime = $segment->reach() - $fillTime;
    #and add the fill
    $beat->truncateToTime($tTime);
    $fill->time($tTime);
    $beat->add($fill);
  }

  if (!$segment->isSongBeginning() && almostAlways) {
    #put in a cymbal crash at the start of this segment
    $beat->add(__crash($segment->time()));
  }
}

sub play {
  my $self     = shift;
  my $segment  = shift;
  my $duration = $segment->duration;
  my $beat = $self->generateBeat($segment);
  $self->transition($segment,$beat);
  #set the note channel so that others
  #people recognize these notes as drums
  $beat->channel($self->channel());
  return $beat;
}

sub fill {
  my $self     = shift;
  my $clock    = shift;
  my $duration = shift;
  if (!$duration) {
    #generate number of beats of fill if not specified
    while($duration < $clock->measureTime) {
      $duration += $clock->beatTime;
      last if (asOftenAsNot);
    }
  }
    
  my $fDrum = __fillDrum();
  my $fill  = AutoHarp::Events::DrumTrack->new();
  my $sixt  = $clock->beatTime / 4;
  my $time  = 0;
  my $toggle = 0;
  while ($time < $duration) {
    my $note = $fDrum->clone();
    $note->time($time);
    if ($toggle) {
      $note->velocity(mediumVelocity());
      $toggle = 0;
    } else {
      $toggle = 1;
    }
    if (rarely) {
      #it's a rest
    } else {
      $fill->add($note);
    }
    if (sometimes) {
      #sometimes swap drums
      $fDrum = __fillDrum();
    }
    $time += $sixt;
  }
  return $fill;
}

sub __dN {
  my $pitch = shift;
  my $time  = shift;
  my $vel   = shift || hardVelocity();
  my $n =  AutoHarp::Event::Note->new($pitch,$NOTE_MINIMUM_TICKS,$vel,$time);
  return $n;
}

sub __snare {
  return __dN(38,@_);
}

sub __kick {
  return __dN(36,@_);
}

sub __softKick {
  my $k = __kick(@_);
  $k->velocity(softVelocity());
  return $k;
}
  
sub __softerKick {
  my $k = __kick(@_);
  $k->velocity(softerVelocity());
  return $k;
}

sub __closedHat {
  return __dN(42,@_);
}

sub __openHat {
  return __dN(46,@_);
}

sub __pedalHat {
  return __dN(44,@_);
}

sub __highTom {
  return __dN(50,@_);
}

sub __lowTom {
  return __dN(45,@_);
}

sub __midTom {
  return __dN(47,@_);
}

sub __crash {
  return __dN((asOftenAsNot) ? 49 : 57, @_);
}

sub __ride {
  return __dN(51, @_);
}

sub __fillDrum {
  return pickOne(__lowTom,__midTom,__highTom,__snare);
}

sub __tickDrum {
  return pickOne(__closedHat, __openHat, __ride, __pedalHat, __kick);
}

"Loosen your ties";

#FROM MIDI.pm 
# @notenum2percussion{35 .. 81} = 
#   (
#    35, 'Acoustic Bass Drum', 
#    36, 'Bass Drum 1',
#    37, 'Side Stick',
#    38, 'Acoustic Snare',
#    39, 'Hand Clap',
#    40, 'Electric Snare',
#    41, 'Low Floor Tom',
#    42, 'Closed Hi-Hat',
#    43, 'High Floor Tom',
#    44, 'Pedal Hi-Hat',
#    45, 'Low Tom',
#    46, 'Open Hi-Hat',
#    47, 'Low-Mid Tom',
#    48, 'Hi-Mid Tom',
#    49, 'Crash Cymbal 1',
#    50, 'High Tom',
#    51, 'Ride Cymbal 1',
#    52, 'Chinese Cymbal',
#    53, 'Ride Bell',
#    54, 'Tambourine',
#    55, 'Splash Cymbal',
#    56, 'Cowbell',
#    57, 'Crash Cymbal 2',
#    58, 'Vibraslap',
#    59, 'Ride Cymbal 2',
#    60, 'Hi Bongo',
#    61, 'Low Bongo',
#    62, 'Mute Hi Conga',
#    63, 'Open Hi Conga',
#    64, 'Low Conga',
#    65, 'High Timbale',
#    66, 'Low Timbale',
#    67, 'High Agogo',
#    68, 'Low Agogo',
#    69, 'Cabasa',
#    70, 'Maracas',
#    71, 'Short Whistle',
#    72, 'Long Whistle',
#    73, 'Short Guiro',
#    74, 'Long Guiro',
#    75, 'Claves',
#    76, 'Hi Wood Block',
#    77, 'Low Wood Block',
#    78, 'Mute Cuica',
#    79, 'Open Cuica',
#    80, 'Mute Triangle',
#    81, 'Open Triangle',
#   );
