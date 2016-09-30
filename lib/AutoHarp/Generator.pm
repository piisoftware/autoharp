package AutoHarp::Generator;

use strict;
use AutoHarp::Fuzzy;
use AutoHarp::Constants;
use AutoHarp::MusicBox::Base;
use AutoHarp::Event::Note;
use AutoHarp::Events::Melody;
use AutoHarp::Events::Progression;
use base qw(AutoHarp::Class);
use Carp;

my $NO_TRUNCATE     = 'dontTruncate';
my $MIN_CHORD_BEATS = 1; #don't generate a chord shorter than a beat
#this is a total guess as to relative weight of notes that we may ignore 
#when guessing what chord goes with what notes
my $CHORD_FIT_RATIO         = 3;
my $FAVORED_CHORD_INTERVALS = [7,9];

#############################
# MUSIC GENERATING ROUTINES #
#############################
sub generateMusic {
  my $self          = shift;
  my $originalGuide = shift;
  my $sourceMusic   = shift;
  
  my $subGuide      = $originalGuide->clone();
  my $subCreator;

  if ($sourceMusic) {
    #take a single phrase of this source music as our guide, 
    $subCreator = $sourceMusic->clone();
    $subCreator->truncate($sourceMusic->phraseDuration());
    $subGuide->measures($subCreator->measures());
  } else {
    if (!$originalGuide->hasKeyChange() && !$originalGuide->hasTimeChange()) {
      my $m = $originalGuide->measures();
      if ($m >= 8 && mostOfTheTime) {
	$m = int($m / 2);
      }
      if ($m >= 4 && !($m % 2) && sometimes) {
	$m = $m / 2;
      }
      $subGuide->measures($m);
    }
    $subCreator = AutoHarp::MusicBox::Base->new($ATTR_GUIDE => $subGuide);
    if (asOftenAsNot) {
      $self->generateMelody($subCreator);
    } else {
      $self->generateChordProgression($subCreator);
    }
  }
  
  #based on the new subset, generate some music
  my $newMusic = AutoHarp::MusicBox::Base->new($ATTR_GUIDE => $subGuide);
  
  if ($subCreator->hasProgression() && 
      (!$subCreator->hasMelody() || asOftenAsNot)) {
    $newMusic->progression($subCreator->progression());
    if (sometimes) {
      $self->melodize($newMusic);
      $self->harmonize($newMusic);
    } else {
      if (asOftenAsNot) {
	$self->shuffleChordProgression($newMusic);
      }
      $self->melodize($newMusic);
    }
  } else {
    $newMusic->melody($subCreator->melody());
    if (asOftenAsNot) {
      #reharmonize, generate new melody for reharmonization
      $self->harmonize($newMusic);
      $newMusic->unsetMelody();
      $self->melodize($newMusic);
    } elsif (asOftenAsNot) {
      #just reharmonize
      $self->harmonize($newMusic);
    } else {
      #harmonize, remelodize, reharmonize
      $self->harmonize($newMusic);
      $self->melodize($newMusic);
      $self->harmonize($newMusic);
    }
  } 
  if (!$newMusic->hasProgression) {
    confess "Music didn't wind up with a progression!";
  } 
  if (!$newMusic->hasMelody) {
    confess "Music didn't wind up with a melody";
  }
  
  #now repeat/truncate until the length of the music is right
  while ($newMusic->measures() < $originalGuide->measures()) {
    my $was = $newMusic->measures();
    $self->repeatMusic($newMusic);

    if ($newMusic->measures() == $was) {
      confess "Repeating music didn't make it any longer!";
    }
  }
  if ($newMusic->measures() > $originalGuide->measures()) {
    $newMusic->measures($originalGuide->measures());
  }

  return $newMusic;
}

sub generateHook {
  my $self        = shift;
  my $music       = shift;
  my $mClone      = $music->clone();
  if (!$music->duration()) {
    #Really. Really?
    return $mClone->toHook();
  }
  #decide how big a hunk we want to work with
  #start with the phrase length
  if ($music->hasPhrases) {
    $mClone->truncate($music->phraseDuration());
  } elsif (mostOfTheTime) {
    #if there's no phrase, most of the time halve it anyway
    $mClone->halve();
  }

  if (!($mClone->measures() % 2) && rarely) {
    #now and again, halve it again
    $mClone->halve();
  }
  if (!$mClone->duration()) {
    die "HOW DID THAT HAPPEN?";
  }

  if (mostOfTheTime && $mClone->hasProgression()) {
    $mClone->unsetMelody();
    my $unit = (mostOfTheTime) ? 1 : pickOne(0,2,4);
    $self->melodize($mClone,{$ATTR_RHYTHM_SPEED => $unit});
  } else {
    if (!$mClone->hasMelody()) {
      $self->generateMelody($mClone);
    }
    #truncate the melody after one measure
    #and send it through the repeater
    $self->melodyRepeater($mClone,$mClone->clock()->measureTime());
  }
  if (!$mClone->melody->hasNotes()) {
    confess "Didn't get any notes when generating a hook!";
  }
  return $mClone->toHook();
}

sub generateMelody {
  my $self      = shift;
  my $music     = shift;
  my $startNote = shift;
  my $prevNote  = shift;

  if (!$music->duration) {
    return $music->melody(AutoHarp::Events::Melody->new());
  }

  my $time      = $music->time();
  my $melody    = AutoHarp::Events::Melody->new();
  $melody->time($time);
  my $clock = $music->clockAt($time);
  my $scale = $music->scaleAt($time);

  if ($startNote) {
    my $s = $startNote->clone();
    $s->time($time);
    $melody->add($s);
    $time = $s->reach();
    $prevNote = $startNote;
  }
  while ($time < $music->reach()) {
    $clock = $music->clockAt($time);
    $scale = $music->scaleAt($time);
    #make a new note and give it the previous values in the melody
    #we will use them to generate a new note
    my $n = ($prevNote) ? $prevNote->clone() : AutoHarp::Event::Note->new();
    $n->time($time);
    my $pitch = $self->generatePitch({$ATTR_MUSIC => $music,
				      $ATTR_PITCH => $n->pitch,
				      $ATTR_TIME  => $time});
    my $duration = $self->generateDuration({$ATTR_MUSIC => $music,
					    $ATTR_PITCH => $n->pitch,
					    $ATTR_DURATION => $n->duration,
					    $ATTR_TIME => $time});
    if ($pitch < 0) {
      #generator elected to rest here. 
      $time += $duration;
      next;
    }
    $n->pitch($pitch);
    $n->duration($duration);
    $self->setNoteVelocity({$ATTR_NOTE => $n, $ATTR_CLOCK => $clock});
    if ($n->reach > $music->reach) {
      #if we overshoot, sometimes round off the last thing
      if (sometimes) {
	my $newDur = $n->duration - ($n->reach - $music->reach);
	$n->duration($newDur);
      } elsif (asOftenAsNot) {
	#sometimes just bail
	last;
      } 
      #sometimes just let it ring
    }
    $melody->add($n);
    $prevNote = $n;
    $time = $n->reach();
  }
  return $music->melody($melody);
}

#TODO: Generate a chord progression via that website
#Allow the key to change in the middle or whatever
sub generateChordProgression {
  my $self     = shift;
  my $music    = shift;
  my $source   = shift;
  if (!$music->duration()) {
    return $music->progression(AutoHarp::Events::Progression->new());
  }
  my $temp     = $music->cloneWithGuide();
  
  if (ref($source) && $source->hasMelody()) {
    $temp->melody($source->melody());
    #if the source isn't long enough, extend it
    if ($source->melody()->duration < $temp->duration()) {
      $temp->truncate($source->melody()->duration());
      $temp->duration($music->duration());
    } 
  } else {
    $self->generateMelody($temp);
  }
 
  return $music->progression($self->harmonize($temp));
}

sub shuffleChordProgression {
  my $self  = shift;
  my $music = shift;
  my $prog  = $music->progression();
  my $newProgression = AutoHarp::Events::Progression->new();
  if ($prog && $prog->hasChords()) {
    my $chords = $prog->chords();
    my $patternLen = scalar @$chords;
    #start with two. A repeated chord is not a pattern

  CHORD_LOOP:
    for(my $i = 2; $i <= int($patternLen / 2); $i++) {
      if ($chords->[0]->chordType eq $chords->[$i]->chordType &&
	  $chords->[0]->letter eq $chords->[$i]->letter) {
	#if these chords match, see if the chords to this point match the
	#chords afterwards. If yes, we've found a pattern
	for (my $j = $i + 1; $j < scalar @$chords; $j++) {
	  if ($chords->[$j - $i]->chordType ne $chords->[$j]->chordType ||
	      $chords->[$j - $i]->letter ne $chords->[$j]->letter) {
	    #nope, not a pattern
	    next CHORD_LOOP;
	  }
	}
	#if we're here, we must have found a pattern
	$patternLen = $i;
	last;
      }
    }
    my @order = (0..$patternLen - 1);
    shuffle(\@order);
    my $addee = 0;
    for (my $j = 0; $j < scalar @$chords; $j++) {
      my $sIdx   = $j % $patternLen;
      my $addon  = int($j / $patternLen) * $patternLen;
      #take the chord from the shuffled ordering and put it here.
      my $pIdx = $order[$sIdx] + $addon;
      my $chord = $chords->[$pIdx]->clone;
      #set its time and duration from the chord that was here
      $chord->time($chords->[$j]->time());
      $chord->duration($chords->[$j]->duration());
      $newProgression->add($chord);
    }
    #now and then, keep the old last chord of the progression 
    #as the new last chord of the progression. 
    if (sometimes) {
      $newProgression->replaceChord($chords->[-1],-1);
    }
    $music->progression($newProgression);
  }
  return $newProgression;
}

sub melodize {
  my $self  = shift;
  my $music = shift;
  my $args  = shift || {};
  if (ref($music) !~ /AutoHarp/) {
    print Dumper $music;
    confess "WTF IS THIS: " . ref($music);
  }
  if (!$music->duration() || 
      !$music->hasProgression() || 
      !$music->progression()->hasChords() ||
      !$music->progression()->duration
     ) {
    $music->dump();
    confess "Cannot melodize something with no chord progression";
  }

  my $speed = abs($args->{$ATTR_RHYTHM_SPEED});
  my $canMuck;
  if (!($speed > 0)) {
    $canMuck = 1;
    $speed = pickOne(1,2,4);
  }
  my $melody      = AutoHarp::Events::Melody->new();
  my $time        = $melody->time($music->time());

  foreach my $c (@{$music->progression->chords()}) {
    $time         = $c->time();
    my $scale     = $music->scaleAt($time);
    my $clock     = $music->clockAt($time);
    my $last      = $melody->endNote();
    my $lastPitch = ($last) ? $last->pitch() : undef;
    my $noteLen   = $clock->beatTime() / $speed;

    while ($time < $c->reach()) {
      my $next = AutoHarp::Event::Note->new();
      $next->time($time);
      my $d = $noteLen;

      if ($canMuck && rarely) {
	if (asOftenAsNot) {
	  $d = $clock->beatTime() / pickOne(3,1.5,.5);
	} else {
	  $d = ($noteLen <= $NOTE_MINIMUM_TICKS) ? 
	    $noteLen * 2 : $noteLen / 2;
	}
      }
      $next->duration($d);

      my $isStart = ($time == $c->time());
      my $p;
      my $did;
      if (($isStart && almostAlways) ||
	  (!$isStart && mostOfTheTime)) {
	$p = pickOne(@{$c->pitches});
      } else {
	$p = $self->generatePitch({$ATTR_MUSIC => $music,
				   $ATTR_TIME  => $time,
				   $ATTR_PITCH => $lastPitch,
				   $NO_TRUNCATE => 1
				  });
      }
      #possibly normalize this a bit
      if ($lastPitch && $p != -1) {
	if ($p > $lastPitch) {
	  while ($p - $lastPitch > $scale->scaleSpan() && almostAlways) {
	    $p -= $scale->scaleSpan();
	  }
	} 
	if ($p < $lastPitch) {
	  while ($lastPitch - $p > $scale->scaleSpan() && almostAlways) {
	    $p += $scale->scaleSpan();
	  }
	}
      }
      if ($p >= 0) {
	$next->pitch($p);
	$self->setNoteVelocity({$ATTR_NOTE => $next, $ATTR_CLOCK => $clock});
	$melody->add($next);
      }
      $time = $next->reach();
    }
  }

  $music->melody($melody);
  my $cDur = $music->progression->chords()->[0]->duration();
  my $repeatDur = (asOftenAsNot) ? $cDur : $music->clock->measureTime();
  if ($music->duration >= ($repeatDur * 2) && sometimes) {
    #well, that was awesome. Now we're going to throw most of it away
    #in favor of a repeating melody made from the first measure or chord length
    $self->melodyRepeater($music, $repeatDur);
  } 
  return $music->melody();
}

sub harmonize {
  my $self        = shift;
  my $music       = shift;
  my $allowRests  = shift;

  my $melody      = $music->melody();
  my $duration    = $music->duration();
  my $progression = AutoHarp::Events::Progression->new();
  if (!$melody) {
    #I cannot harmonize the air, bitch;
    return $self->generateChordProgression($music);
    #actually I guess I can. 
  }

  $progression->time($music->time());
  #group the notes into measures, then "compute" each measure
  my $measures  = $music->eachMeasure();
  my $pattern;
  my $lastChord;
  my $mTime;
  my $str;
  for (my $mIdx = 0; $mIdx < scalar @$measures; $mIdx++) {
    my $sTime     = $measures->[$mIdx];
    $str .= "$sTime,";
    my $clock     = $music->clockAt($sTime);
    my $scale     = $music->scaleAt($sTime);
    if ($mTime != $clock->measureTime) {
      $mTime      = $clock->measureTime();
      undef $pattern;
    }
    my $minCTime  = $MIN_CHORD_BEATS * $clock->beatTime();
    my $mEnd      = $sTime + $mTime;
    my $chordEnd  = $mEnd;
    my $force     = 0;
    if ($pattern) {
      #If we've established a pattern, let's try real hard 
      #to hit it over and over again
      #unless we're on a fourth measure. Then maybe abandon it
      if (($mIdx % 4 == 3 && sometimes) || ($mIdx % 4 != 3 && almostAlways)) {
	$chordEnd  = $sTime + $pattern;
	$force     = 1;
      }
    }
    #sanity check to prevent...insanity
    my $tooMuch = 3 * (int($mTime / $minCTime) + 1);
    my @sanity;

    while ($progression->reach() < $mEnd) {
      my $sString = sprintf("CALC START: %d, CALC END: %d, MEAS START: %d, MEAS END: %d, PATTERN: %d, SPACE LEFT: %d",
			    $sTime,
			    $chordEnd,
			    $measures->[$mIdx],
			    $mEnd,
			    $pattern,
			    $chordEnd - $sTime
			   );
      push(@sanity, $sString);
      if (scalar @sanity >= $tooMuch || ($chordEnd - $sTime < $minCTime)) {
	print "ORIGINAL MELODY: \n";
	$melody->subMelody($measures->[$mIdx], $mEnd)->dump();
	print "CURRENT PROGRESSION: \n";
	$progression->dump();
	print "ORIGINAL TIMES: $measures->[$mIdx], $mEnd\n";
	print "CURRENT TIMES: $sTime $chordEnd\n";
	foreach (@sanity) {
	  print "$_\n";
	}
	confess "Tripped the sanity checks";
      }

      #Start by figuring out what the set of notes is
      #prefer no overlaps--try to base chords 
      #only on notes that start in this block
      my $cNotes   = $melody->subMelody($sTime, $chordEnd, 1);
      if (!$cNotes->hasNotes()) {
	#if that leaves us with nothing, allow fragments
	$cNotes = $melody->subMelody($sTime,$chordEnd);
	$sanity[-1] .= "- allowed fragments at $sTime to $chordEnd";
      }
      
      if (!$cNotes->hasNotes()) {
	#there is still nothing in this block...do one of three things
	if ($progression->chords()->[-1]) {
	  #copy the previous chord to the requested end
	  my $newCh  = $progression->chords()->[-1]->clone();
	  $newCh->time($sTime);
	  $newCh->duration($chordEnd - $sTime);
	  $progression->add($newCh);
	  ($sTime,$chordEnd) = ($chordEnd,$mEnd);
	  $sanity[-1] .= sprintf("- added new chord at %d, ending at %d",
				 $newCh->time(),
				 $newCh->reach());
	  next;
	} elsif ($allowRests) {
	  #if there's nothing here and we allow it,
	  #put a rest in the progression
	  if ($mEnd - $chordEnd < $minCTime) {
	    #if there's not enough space, skip ahead to the next measure
	    $sanity[-1] .= sprintf("- added rest");
	    last;
	  } 
	  #otherwise, try and find something in last fragment of the measure
	  ($sTime,$chordEnd) = ($chordEnd,$mEnd);
	  $sanity[-1] .= " - Allow rests, new start: $sTime new end: $chordEnd";
	  next;
	} else {
	  #otherwise, just put a single note melody 
	  #using the scale root, and we'll go ahead and work with that
	  my $n = AutoHarp::Event::Note->new($scale->rootPitch(),
				       $chordEnd - $sTime,
				       hardVelocity(),
				       $sTime
				      );
	  $n->velocity(hardVelocity());
	  $cNotes = AutoHarp::Events::Melody->new([$n]);
	  $sanity[-1] .= sprintf(" - Use single root note from %d to %d",$cNotes->getNote(0)->time, $cNotes->getNote(0)->reach());
	}
      }
      
      my $chords = $self->computeChords($cNotes,$scale,$force);

      if (!scalar @$chords) {
	if ($force) {
	  print "MELODY\n";
	  $melody->dump();
	  print "NOTES\n";
	  $cNotes->dump();
	  confess "Got no chords for melody between $sTime and $chordEnd, even though we forced it";
	}

	#no chord found...take drastic measures
	#pop at least one Note
	$cNotes->popNote();
	$sanity[-1] .= sprintf(" - Popped note for space, new reach is %d",$cNotes->reach());
	while ($chordEnd - $cNotes->reach < $minCTime) {
	  #and pop notes off the melody until we get enough space 
	  #that a chord can go in the space we're not using
	  $cNotes->popNote();
	  $sanity[-1] .= sprintf(" - Popped note for space, new reach is %d",$cNotes->reach());
	}

	#set the new chord end to where this melody now comes out
	$chordEnd = $cNotes->reach();

	if ($chordEnd - $sTime < $minCTime) {
	  #now we're too short
	  #expand out to the end of the measure and force the issue
	  $force     = 1;
	  $chordEnd  = $mEnd;
	  $sanity[-1] .= sprintf(" - Too short, forcing");
	}
	next;
      }
      
      my $chord;
      #take a walk through the chords and choose one
      foreach (@$chords) {
	#favor not repeating chords
	if ($_->equals($lastChord) && almostAlways) {
	  next;
	}
	if (mostOfTheTime) {
	  $chord = $_;
	  last;
	}
      }
      if (!$chord) {
	#if we didn't choose anything, take the first one
	$chord = shift(@$chords);
      }
      $sanity[-1] .= sprintf(" - SELECTED: %s, covering %d to %d",$chord->toString(),$chord->time,$chord->reach);
      $chord->time($sTime);
      my $chordDuration = $chordEnd - $sTime;
      my $messyBit      = $chordDuration % $NOTE_MINIMUM_TICKS;
      if ($messyBit) {
	#we don't do chords lengths this granular
	$chordDuration -= $messyBit;
	if ($chordDuration < $minCTime) {
	  $chordDuration += $NOTE_MINIMUM_TICKS;
	}
      }
      $chord->duration($chordDuration);
      $progression->add($chord);
      $lastChord = $chord->clone;
      #if we haven't filled up the measure yet, generate another chord
      if ($chord->reach < $mEnd) {
	$sTime    = $chord->reach();
	$chordEnd = $mEnd;
	if ($chordEnd - $sTime < $minCTime) {
	  print "PROG\n";
	  $progression->dump();
	  print "SUBMELODY:\n";
	  $cNotes->dump();
	  print "CHORD JUST GENERATED:\n";
	  $chord->dump();
	  confess "ONCE AGAIN, YOU HAVE SCREWED SOMETHING UP";
	}
	if ($chord->time == $music->time) {
	  #if this is the first chord through 
	  #and we selected a sub-measure long chord
	  #let's establish that as the chord pattern
	  $pattern = $chord->duration;
	}
	redo;
      }
    } #END COMPUTEBLOCK
  } #END MEASURELOOP
  return $music->progression($progression);
}

sub computeChords {
  my $self      = shift;
  my $melody    = shift;
  my $scale     = shift;
  my $force     = shift;

  my $nMap      = {};
  my $scaleSpan = $scale->scaleSpan();
  my $chords    = [];
  my $octave    = 4 * $scaleSpan; #(arbitrary choice, actual octave doesn't matter)
  my $bestFit   = {fit => 0};
  my $CHORD     = 'chord';
  my $FIT       = 'fit';

  #weight the first note in the sequence more highly
  my $factor    = 4;
  foreach my $musicEvent (@{$melody->notes()}) {
    #make a map of pitches normalized in octave 
    foreach my $n (@{$musicEvent->toNotes()}) {
      my $key = ($n->pitch % $scaleSpan) + $octave;
      $nMap->{$key} += ($n->duration * $factor);
      $factor = 1;
    }
  }
  foreach my $pitch (sort {$nMap->{$b} <=> $nMap->{$a}} keys %$nMap) {
    #go through the pitches and look at the chords in the scale where
    #that pitch is found and see where we have a good fit
    foreach my $chord (@{$scale->chordsForPitch($pitch)}) {
      if ($chord->isUnclassified()) {
	$chord->dump();
	confess $scale->key() . " scale produced unclassified chord for $MIDI::number2note{$pitch}";
      }
      if (!$chord->getNoteByPitch($pitch)) {
	$chord->dump();
	confess $scale->key() . " scale produced chord for $pitch that doesn't contain it";
      }
      #skip this if we've already looked at it
      next if scalar grep {$chord->equals($_->{$CHORD})} @$chords;
      $chord->velocity(softVelocity());
      my $rootPitch    = $chord->rootPitch();
      my $weightFactor = 1;
      if ($chord->isScaleTriad($scale) && almostAlways) {
	#if we have a I,IV,V,or VI chord in the scale, we like it a lot. 
	#For this is rock and roll
	my $id = $chord->toScaleNumber($scale);
	if ($id == 1 || $id == 5) { 
	  $weightFactor = 1.3;
	} elsif ($id == 4) {
	  $weightFactor = 1.2;
	} elsif ($id == 6) {
	  $weightFactor = 1.1;
	}
      } elsif ($chord->isDiminished()) {
	#fuck diminished chords
	$weightFactor = .9;
      }

      #map the chord into the same octave
      my $chordMap = {map {($octave + ($_->pitch % $scaleSpan)) => 1} @{$chord->toNotes()}};
      #how well does this chord weigh in?
      my $inWeight  = 0;
      my $outWeight = 0;
      while (my ($pitch, $weight) = each %$nMap) {
	my $found = $chordMap->{$pitch};
	# this has, like, never worked
 	# if (!$found && $chord->isTriad()) {
	#   #this note is not in the chord
	#   #would adding it to the chord make us happy? 
	#   foreach my $int (@$FAVORED_CHORD_INTERVALS) {
	#     my $note = $scale->steps($rootPitch,$int);
	#     if ($note % $scaleSpan == $pitch % $scaleSpan) {
	#       #Yeah!
	#       if (asOftenAsNot) {
	# 	$chord->addPitch($note);
	#       }
	#       $found = 1;
	#       last;
	#     }
	#   }
	# }
	if ($found) {
	  $inWeight += $weight;
	} else {
	  $outWeight += $weight;
	}
      }
      $outWeight ||= 1;
      my $fit = $inWeight / $outWeight;
      if ($fit > $bestFit->{$FIT}) {
	$bestFit->{$FIT}   = $fit;
	$bestFit->{$CHORD} = $chord;
      }
      if ($fit >= $CHORD_FIT_RATIO) {
	$chord->toDefaultOctave();
	push(@$chords,{chord => $chord, fit => $fit * $weightFactor});
      }
    }
  }
  if ($force && !scalar @$chords && $bestFit->{$CHORD}) {
    $bestFit->{$CHORD}->toDefaultOctave;
    push(@$chords, $bestFit);
  }
  #return the chords sorted in order of best fit
  return [map {$_->{$CHORD}} @$chords];
}

#figure out where we're going and create a little lead-in
sub leadInForMusic {
  my $self    = shift;
  my $music   = shift;
  my $note    = shift;

  if (!$note) {
    $note = $music->scale()->root();
    $note->time($music->time());
  }

  #watch this, bitches:
  #I pick a duration
  my $dur  = $note->duration + (int(rand(4)) + 1) * $music->clock->beatTime();
  #clone a piece of the music that's that length
  my $iMus = $music->subMusic($music->time, $music->time + $dur);
  #generate a melody starting on the note on which I want to end up
  $self->generateMelody($iMus,$note);
  #create a new melody by reversing that...
  my $new  = $iMus->melody()->reverse();
  #pop off the last note (which is now the root I want to end up at)
  $new->popNote();
  $new->time($note->time - $new->duration());
  #and that becomes my lead-in
  return $new;
}

######################################
# NOTE ATTRIBUTE GENERATING ROUTINES #
######################################

sub generatePitch {
  my $self = shift;
  my $args = shift;
  my $music     = $args->{$ATTR_MUSIC};
  my $prevPitch = $args->{$ATTR_PITCH};
  my $when      = $args->{$ATTR_TIME};
  my $scale     = $music->scaleAt($when);
  my $clock     = $music->clockAt($when);
  my $dir       = (rand(128) < $prevPitch) ? -1 : 1;
  
  my $onBeat    = $clock->isOnTheBeat($when);
  my $rootPitch = $scale->rootPitch();
  
  #don't truncate short things. 
  #We might be trying to get seed melodies
  $args->{$NO_TRUNCATE} ||= ($music->measures() < 4);

  if (!$prevPitch) {
    #most of the time start with root or 5th
    if (mostOfTheTime) {
      return pickOne($rootPitch,
		     $rootPitch + $scale->scaleSpan(),
		     $rootPitch - $scale->scaleSpan(),
		     $scale->steps($rootPitch,4),
		     $scale->steps($rootPitch,-3));
    }
    #if we're still here, start from the root pitch of the scale
    $prevPitch = $rootPitch;
  } elsif ($prevPitch >= 0 && !$args->{$NO_TRUNCATE}) {
    #if this isn't the start (obvi...)
    #as we near the end of the phrase and we're 
    #more or less at a good stopping point
    #increase the likelihood of resting
    my $time2End = $music->timeToEndOfPhrase($when);
    my $goodStop = $onBeat || $clock->isOnTheBeat($when + ($clock->beatTime / 2));
    if ($goodStop && 
	($time2End < $clock->measureTime() && rarely) ||
	($time2End < $clock->beatTime() * 2 && sometimes) ||
	($time2End < $clock->measureTime() && asOftenAsNot)) {
      return -1;
    }
  }
  
  if ($scale->isAccidental($prevPitch) && almostAlways) {
    #if we're on an accidental, almost always treat it as such
    #i.e. go to the next semitone
    return $prevPitch + $dir;
  }

  if ($onBeat || asOftenAsNot) {
    if (asOftenAsNot) {
      #50% of the time, stay on the same note or go one pentatonic step
      return $scale->pentatonicSteps($prevPitch,pickOne(0,$dir));
    }
    if (asOftenAsNot) {
      #most of the rest of the time go two or three
      return $scale->pentatonicSteps($prevPitch,pickOne($dir * 2, $dir * 3));
    }
    if (sometimes) {
      #maybe do 4 pentatonic steps or an octave
      return $scale->pentatonicSteps($prevPitch,pickOne($dir * 4, $dir * 5));
    }
  }
  
  if ($prevPitch >= 0 && rarely) {
    #rest
    return -1;
  }
  
  #we're still here, so we're probably off beat
  if (mostOfTheTime) {
    #move zero, one, or two steps in the scale
    return pickOne($prevPitch,
		   $scale->steps($prevPitch,$dir), #step in the scale
		   $scale->steps($prevPitch,$dir * 2), #two steps in the scale
		  );
  }
  #we're still here, so we can do something weird. 
  #are we near a blue note or the alt 7th?
  my $pUp = $prevPitch + 1;
  my $pDn = $prevPitch - 1;
  if (($scale->isBlueNote($pUp) || $scale->isAltSeventh($pUp)) && almostAlways) {
    return $pUp;
  }
  if (($scale->isBlueNote($pDn) || $scale->isAltSeventh($pDn)) && almostAlways) {
    return $pDn;
  }
  #still here? Return nearest root or fifth
  return pickOne($scale->nearestRoot($prevPitch,$dir),
		 $scale->nearestFifth($prevPitch,$dir));
}

sub generateDuration {
  my $self    = shift;
  my $args    = shift;
  my $music   = $args->{$ATTR_MUSIC};
  my $when    = $args->{$ATTR_TIME};
  my $prevDur = $args->{$ATTR_DURATION};
  my $pitch   = $args->{$ATTR_PITCH};

  my $clock   = $music->clockAt($when);
  my $scale   = $music->scaleAt($when);

  my $wasRest      = $pitch < 0;
  my $onBeat       = $clock->isOnTheBeat($when);
  my $beatFraction = $clock->beatFraction($when);
  my $toNextBeat   = $clock->toNextBeat($when);
  my $isPent       = $scale->isPentatonic($pitch);
  my $isAccident   = $scale->isAccidental($pitch);

  $prevDur ||= $clock->beatTime();
  my $wasDotted    = $clock->isDotted($prevDur);
  my $wasTriplet   = $clock->isTriplet($prevDur);
  
  #first, housekeeping: 
  #if we're in the middle of a triplet, continue it
  if ($wasTriplet && !$onBeat) {
    return $prevDur;
  }

  #handle resting
  if ($pitch < 0) {
    my $time2End = $music->timeToEndOfPhrase($when);
    my $goodStop = $onBeat || $clock->isOnTheBeat($when + ($clock->beatTime / 2));
    #should we just quit here? 
    if ($goodStop && $time2End < $clock->measureTime() && unlessPigsFly) {
      #yes. A thousand times yes
      return $time2End;
    }
    if (!$onBeat) {
      #use the rest to get us back on beat
      return $toNextBeat if (almostAlways);
    } elsif (almostAlways) {
      #if we're on beat, almost always return a full beat rest
      return $clock->beatTime();
    }
  }
  
  #handle dotted notes
  if ($wasDotted && !$onBeat) {
    if ($prevDur < $clock->beatTime()) {
      if (almostAlways) {
	#almost always complete the short ones
	return int($prevDur * 1/3);
      } else {
	#otherwise, repeat them
	return $prevDur;
      }
    } else {
      if (asOftenAsNot) {
	#take us to the next beat
	return $toNextBeat;
      }
      if (rarely) {
	#now and again repeat it
	return $prevDur;
      }
    }
  }

  if ($clock->subBeat($when, $prevDur) > 1 && almostAlways) {
    #repeat 8th/16th notes if they take us further along in the beat
    return $prevDur;
  }
  
  if ($isAccident) {
    #accidental. Start with the shortest thing I can have
    my $len = $NOTE_MINIMUM_TICKS;
    while (almostNever) {
      #maybe increase it
      $len *= 2;
    }
    return $len;
  }
  
  if (!$isPent && mostOfTheTime) {
    #opt for short when we're off the pentatonic scale
    if (mostOfTheTime) {
      return $clock->beatTime() / 2;
    }
    return $clock->beatTime() / 4;
  }

  #fallback stuff
  if (sometimes) {
    return pickOne($clock->beatTime(),
		   $clock->beatTime() / 2);
  }
  if (sometimes) {
    return pickOne($clock->beatTime() / 4,
		   $clock->beatTime() * 1.5,
		   $clock->beatTime() * 3/4, #dotted eighth
		   $clock->beatTime() * 3, #dotted half
		  );
  }
  if ($onBeat) {
    if (rarely) {
      return pickOne($clock->beatTime * 4, #whole
		     $clock->beatTime * 2  #half
		    );
    } 
    if (almostNever) {
      #only start a triplet if we're on a beat, 
      #also, don't start a triplet
      return $clock->beatTime() / 3;
    }
  }
  return $clock->beatTime();
}

sub setNoteVelocity {
  my $self  = shift;
  my $args  = shift;
  
  my $note  = $args->{$ATTR_NOTE};
  my $clock = $args->{$ATTR_CLOCK};
  my $when  = $note->time;


  #start from medium
  $note->velocity(mediumVelocity());

  #hit accents harder
  if ($clock->isAccentBeat($when)) {
    return $note->velocity(hardVelocity());
  }
  
  #if there's a subbeat, base it on that
  my $subBeat  = $clock->subBeat($when,$note->duration);
  if ($subBeat) {
    if (!($subBeat % 4)) {
      $note->velocity(softerVelocity());
    } elsif (!($subBeat % 2)) {
      $note->velocity(softVelocity());
    } elsif (!($subBeat % 3)) {
      $note->velocity(int((mediumVelocity() + softVelocity()) / 2));
    }
  }
  #otherwise we're happy
  return 1;
}

sub repeatMusic {
  my $self = shift;
  my $music = shift;
  if (asOftenAsNot) {
    #half the time, repeat it whole hog
    return $music->repeat();
  }
  #otherwise, pick something interesting
  my $toRun = pickOne(sub {
			#reharmonize
			my $second = $music->clone();
			$self->harmonize($second);
			return $music->append($second);
		      },
		      sub {
			#extend by copying,
			#reharmonizing,
			#and using the melody repeater
			my $second = $music->clone();
			$self->harmonize($second);
			$second->unsetMelody();
			$music->append($second);
			return $self->melodyRepeater($music,$second->duration());
		      },
		      sub {
			#chord substitute
			my $second = $music->clone();
			foreach my $c (@{$second->progression()->chords()}) {
			  $self->chordSubstitution($c,
						   $second->scaleAt($c->time),
						   $c->reach == $second->reach
						  );
			}
			return $music->append($second);
		      }
		     );
  return $toRun->();
}

#takes whatever fragment of melody is in the music you pass
#and repeats it as many times as it will fit in that music,
#transposing as necessary
sub melodyRepeater {
  my $self        = shift;
  my $music       = shift;
  my $repeatLen   = shift;

  if (!$music->hasMelody()) {
    #NOOOOOOOOOOOO
    return;
  }

  if (!$repeatLen) {
    my $clock    = $music->clockAt($music->melody->reach());
    my $toNext   = $clock->toNextBeat($music->melody->reach());
    $repeatLen   = $music->melody->duration() + $toNext;
  }
  if ($repeatLen >= $music->duration()) {
    #nothing to see here. Please move along
    return;
  }
  my $repeatMelody = $music->melody->subMelody($music->time, $music->time + $repeatLen);
  if (!$repeatMelody->hasNotes) {
    #nothing to repeat!
    $music->dump();
    confess "Trying to repeat music at duration of $repeatLen resulted in no notes to repeat!";
  }

  my $newMelody   = AutoHarp::Events::Melody->new();
  $newMelody->time($music->time);
  $newMelody->add($repeatMelody);
  my $reps       = $music->duration / $repeatLen;  
  if ($reps == 0) {
    $music->dump();
    confess "Something wrong in melody repeater land when trying to repeat a fragement of $repeatLen";
  }

  my $prog  = $music->progression();
  my $rTime = $repeatLen;
  my $holyFuck;
  while ($music->time + $rTime < $music->reach()) {
    foreach my $originalNote (@{$repeatMelody->notes()}) {
      my $newNote   = $originalNote->clone();
      my $newTime   = $originalNote->time + $rTime;
      my $scaleThen = $music->scaleAt($originalNote->time);
      my $scaleNow  = $music->scaleAt($newTime);
      my $chordThen = ($prog) ? $prog->chordAt($originalNote->time) : undef;
      my $chordNow  = ($prog) ? $prog->chordAt($newTime) : undef;
      if ($chordThen && $chordNow) {
	#move the notes relative to their chords
	#if the pitch is 17 scale steps above its chord's root
	#put the new note in the same position relative to its own chord
	my $oSteps = $scaleThen->scaleStepsBetween($originalNote->pitch,
						   $chordThen->rootPitch());
	#we'll force shit into key if it's weird (hence the int func)
	my $newPitch = $scaleNow->steps($chordNow->rootPitch(),int($oSteps));
	$newNote->pitch($newPitch);
      } else {
	$newNote->pitch($originalNote->pitch);
	$scaleThen->transposeEventToScale($newNote,$scaleNow,1);
      }
      $newNote->time($newTime);
      $newMelody->add($newNote);
      last if ($newNote->reach() > $music->reach());
    }
    $rTime += $repeatLen;
  }
  
  return $music->melody($newMelody);
}

sub chordSubstitution {
  my $self        = shift;
  my $chord       = shift;
  my $scale       = shift;
  my $endOfPhrase = shift;
  if (!$chord->isScaleTriad) {
    #nooooo thank you. Will end badly
    return;
  }

  if ($endOfPhrase && 
      $chord->isSubstitution($scale->dominantV()) &&
      mostOfTheTime) {
    #love me some dominant sevenths at the ends of my phrases
    return $chord->become($scale->dominantV());
  }
	
  my $root  = $chord->root()->pitch;
  my $fifth = $chord->fifth()->pitch;
  my $do = pickOne(sub {
		     #take the root and stick it at the seventh
		     #when minor, gives us the relative major
		     $chord->subtractPitch($root);
		     $chord->addPitch($scale->steps($fifth,2));
		     if (sometimes) {
		       #sometimes add the major seventh
		       $chord->addPitch($scale->steps($chord->fifth->pitch,2));
		     }
		   },
		   sub {
		     #put a note in two steps under the root
		     #when major, gives us the relative minor
		     $chord->addPitch($scale->steps($root,-2));
		     #sometimes, remove the fifth 
		     if (sometimes) {
		       $chord->subtractPitch($fifth);
		     }
		     #but a lot of the time, keep it
		   }
		  );
  return $do->();
}

"Never gonna give you Toy Story 2";
