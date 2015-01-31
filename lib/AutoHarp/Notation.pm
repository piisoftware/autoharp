package AutoHarp::Notation;

use strict;
use AutoHarp::Events::Progression;
use AutoHarp::Events::Guide;
use AutoHarp::Generator;
use AutoHarp::Constants;
use AutoHarp::Events::Melody;
use AutoHarp::MusicBox::Base;
use AutoHarp::Clock;
use AutoHarp::Scale;
use AutoHarp::Fuzzy;
use AutoHarp::Event::Note;

use MIDI;
use Carp;

#a quick and dirty interpretation AutoHarp version of ABC Text notation 
my $MBARS_E = qr([\|]+);
my $NOTE_E = qr([A-Ga-gz]); 
my $CHORD_E = qr(([A-GN][^\/\.\s]*));

my $BASE_OCTAVE       = 4;
my $WHEEL_ABS_MAX     = '8191';
my $REST              = "z";
my $SPACE_CHAR        = ".";
my $STRUM_CHAR        = "/";
my $NO_CHORD          = "NC";
my $DEBUG = 1;
my $BASE_LENGTH       = $TICKS_PER_BEAT;
my $MIN_LENGTH        = $BASE_LENGTH / 4;
 
sub ParseHeader {
  my $header = shift;  my $q;
  my $data = {};
  foreach (split(/,\s*/,$header)) {
    if (/([^:]+):\s*(.+)/) {
      my $key = $1;
      my $d = $2;
      $data->{$key} = $d;
    }
  }
  return $data;
}

sub CreateHeader {
  my $args = {@_};
  my $clock = $args->{$ATTR_CLOCK};
  my $scale = $args->{$ATTR_SCALE};
  my $genre = $args->{$ATTR_GENRE};

  my @s;
  if ($clock) {
    push(@s, sprintf("$ATTR_METER: %s",$clock->meter()));
    push(@s, sprintf("$ATTR_TEMPO: %d",$clock->tempo()));
    push(@s, sprintf("$ATTR_SWING_PCT: %d",$clock->swingPct()));
    push(@s, sprintf("$ATTR_SWING_NOTE: %s",$clock->swingNote()));
  }
  if ($scale) {
    push(@s, sprintf("$ATTR_KEY: %s",$scale->key()));
  }
  if ($genre) {
    push(@s, sprintf("$ATTR_GENRE: %s",$genre->name()));
  }
  return join(", ",@s);
}

sub CountMeasures {
  my $string = shift;
  return scalar @{SplitMeasures($string)};
}

sub SplitMeasures {
  my $string = shift;
  return [grep {/./} split($MBARS_E,$string)];
}

sub String2Melody {
  my $string = shift;
  my $guide  = _handleGuide(shift);
  my $melody = AutoHarp::Events::Melody->new();
  $melody->time($guide->time);

  #note now if we have a lead in (e.g. there are notes before the first bar)
  my $hasLeadIn     = ($string !~ /^\|/);
  my @measures      = grep {/./} split($MBARS_E,$string);
  my $clock         = $guide->clock();
  my $guideMeasures = $guide->eachMeasure();
  my $generator     = AutoHarp::Generator->new();

  if ($hasLeadIn) {
    #throw a lead-in measure on the front to handle this
    #the lead-in probably isn't a whole measure long, 
    #but we'll fix it at the end
    unshift(@$guideMeasures, $guide->time - $clock->measureTime);
  }
  while (scalar @measures > scalar @$guideMeasures) {
    my $l = $guideMeasures->[-1];
    push(@$guideMeasures,$l + $guide->clockAtEnd()->measureTime);
  }
  my $lastNote;
  my $inSlur;
  my $mTime;
  for(my $mIdx = 0; $mIdx < scalar @measures; $mIdx++) {
    my $measure = $measures[$mIdx];
    $mTime      = $guideMeasures->[$mIdx];
    $clock      = $guide->clockAt($mTime);
    my $scale   = $guide->scaleAt($mTime);
    my $nextMeasureStart = $mTime + $clock->measureTime;

    $measure =~ s/\s+//g;
    #split the notes into letter notes plus stuff, 
    #then look for additional data
    my @data = split(/($NOTE_E)/,$measure);
    foreach (my $i = 0; $i < scalar @data; $i++) {
      my $element = $data[$i];
      my $note = ($element =~ /^($NOTE_E)$/)[0];

      #if no note in this chunk, skip to the next chunk
      next if (!$note);
      
      my $pre = ($i > 0 && $data[$i - 1] !~ /^$NOTE_E$/) ?
	$data[$i - 1] : undef;
      my $post = ($i < $#data && $data[$i + 1] !~ /^$NOTE_E$/) ? 
	$data[$i + 1] : undef;
      
      my $duration = _string2Time("$note$post");

      if ($note eq $REST) {
	$mTime += $duration;
	next;
      }
      #printf "TO M(%4d): Dealing with $pre $element $post\n",$mTime;

      my $octave = $BASE_OCTAVE;
      if ($note eq uc($note)) {
	$octave--;
      } 
      if ($post =~ /^(,+)/) {
	$octave -= length($1);
      }
      if ($post =~ /^(\'+)/) {
	$octave += length($1);
      }
      my $pitch = $MIDI::note2number{uc($note) . $octave};
      if (!length($pitch)) {
	confess "invalid note and octave designation $note$post";
      }
      if ($pre =~ /\^$/) {
	$pitch++;
      } elsif ($pre =~ /_$/) {
	$pitch--;
      }
      my $n = AutoHarp::Event::Note->new($pitch,$duration);
      $n->time($mTime);
      $generator->setNoteVelocity({$ATTR_NOTE => $n, $ATTR_CLOCK => $clock});

      $mTime = $n->reach();
      #printf "\tpreliminary note: %s %d at %d\n",$n->toString(),$n->duration(),$n->time;
      #handle slurs
      my $weSlurred;
      if (length($inSlur) && $lastNote && $lastNote->duration) {
	#print "\tin a slur, stand by...";
	#we're slurring. Instead of adding a new note, 
	#extend the old note and hit the portamento lever
	my $portaDiff = int((($n->pitch - $lastNote->pitch) / 2) * $WHEEL_ABS_MAX);
	my $destination = $inSlur + $portaDiff;
	if (abs($destination) <= $WHEEL_ABS_MAX) {
	  #yes! we can accomodate you
	  $weSlurred = 1;
	  my $oldDur   = $lastNote->duration();
	  my $oldReach = $lastNote->reach();
	  $lastNote->duration($oldDur  + $n->duration);
	  #printf "\tinstead of adding that note, extending %s at %d from %d to %d\n",$lastNote->toString(),$lastNote->time,$oldDur,$lastNote->duration();

	  #add aftertouch to alleviate the note decay
	  $melody->add([$EVENT_CHANNEL_AFTERTOUCH,
			$n->time,
			0,
			$n->velocity]);
	  if ($portaDiff != 0) {
	    #do our slur at the last quarter of the note,
	    #trying to get at least 20 ticks to do stuff
	    my $span   = ($oldDur > 80) ? $oldDur / 4 :
	      ($oldDur > 40) ? 20 : $oldDur / 2;
	    my $step   = int($portaDiff / $span);
	    my $startT = $oldReach - $span;
	    my $pSet   = $inSlur + $step;
	    for (0..($span - 1)) {
	      $melody->add([$EVENT_PITCH_WHEEL,
			    $startT + $_,
			    0,
			    $pSet]);
	      $pSet += $step;
	    }
	    $melody->add([$EVENT_PITCH_WHEEL,
			  $startT + $span,
			  0,
			  $portaDiff]);
	    $inSlur = $portaDiff;
	  }
	} else {
	  #we canna portamento that far!
	  if ($inSlur != 0) {
	    #must otherwise reset the portamento lever
	    my $end = ($lastNote) ? $lastNote->reach() : $n->time;
	    $melody->add([$EVENT_PITCH_WHEEL,
			  $end,
			  0,
			  0]);
	    $inSlur = 0;
	  }
	}
      } 
      
      #are we stopping or starting slurring?
      if ($pre =~ /\(/) {
	#yes!
	#print "Starting a slur\n";
	$inSlur = 0;
      } 
      if ($post =~ /\)/) {
	if ($inSlur != 0) {
	  $melody->add([$EVENT_PITCH_WHEEL,
			$mTime,
			0,
			0]);
	}   
	#print "Ending a slur\n";
	undef $inSlur;
      }
      
      if (!$weSlurred) {
	#print "\tAdding note as calculated\n";
	$melody->add($n);
	$lastNote = $melody->notes()->[-1];
      } else {	
	#print "\tNot adding anything new for that\n";
      }
    } #end of a measure
    
    if ($lastNote && $mTime < $nextMeasureStart) {
      #print "Doing funky fill-up action at $mTime\n";
      #you didn't give us enough time to fill the measure
      my $cutoff = $nextMeasureStart - $clock->measureTime();
      #I'm going to assume you wanted to nudge this up to the end
      #(e.g. that this is a pickup to the next measure)
      my $delta = $nextMeasureStart - $mTime;
      foreach (@{$melody->events}) {
	if ($_->time >= $cutoff) {
	  $_->time($_->time + $delta);
	}
      }
    }
  } 
  return $melody;
}

sub String2Progression {
  my $string      = shift;
  my $guide       = _handleGuide(shift);
  my $progression = AutoHarp::Events::Progression->new();
  my $mTime       = $guide->time() || 0;
  $progression->time($mTime);

  my @measures     = grep {/\S/} split(/\s*$MBARS_E\s*/,$string);
  foreach my $measure (@measures) {
    my $tTime = 0;
    my $clock = $guide->clockAt($mTime);
    my @tokens = grep {/\S/ && (s/\s+//g || 1)} split($CHORD_E,$measure);
    while (scalar @tokens) {
      my $chord = shift(@tokens);
      if ($chord eq $SPACE_CHAR || $chord eq $STRUM_CHAR) {
	confess sprintf("Bad measure %s\n\tfound in progression string %s\n",$measure,$string);
      }
      if ($tokens[0] eq 'over') {
	#multiple token chord (e.g. "Bm7 over A")
	$chord .= " " . shift(@tokens) . " " . shift(@tokens);
      }
      my $timeStr  = ($tokens[0] =~ /^[A-G]/) ? "" : shift(@tokens);
      my $duration = _string2ChordTime($timeStr,$mTime);
      $tTime += $duration;
      if ($chord ne $NO_CHORD) {
	my $newChord = AutoHarp::Event::Chord->fromString($chord);
	if (!$newChord) {
	  confess "Couldn't produce a valid chord from $chord\nin:\n$measure\n$string";
	}
	$newChord->time($mTime);
	$newChord->duration($duration);
	$progression->add($newChord);
      } 
      $mTime += $duration;
    }
    if ($tTime != $clock->measureTime()) {
      confess "Measure '$measure' in\n$string\nhas an incorrect number of beats (has $tTime, wants " . $clock->measureTime();
    }
  }
  return $progression;
}

sub String2DrumTrack {
  my $string    = shift;
  my $guide     = shift;
  my $drumPitch = shift || $MIDI::percussion2notenum{'Acoustic Bass Drum'};

  my $drumTrack = AutoHarp::Events::DrumTrack->new();
  $drumTrack->time($guide->time);
  
  $string =~ s/\s+//g;
  
  my @measures   = grep {/\S/} split(/$MBARS_E/,$string);
  my $mCount     = scalar @measures;
  my $hasLeadIn  = ($string !~ /^\|/);
  $mCount-- if ($hasLeadIn);
  
  if (!$guide) {
    $guide = AutoHarp::Events::Guide->new();
    $guide->measures($mCount);
  } elsif ($guide->measures() < $mCount) {
    $guide = $guide->clone();
    $guide->measures($mCount);
  }
  
  my $guideMeasures = $guide->eachMeasure();
  my $clock         = $guide->clock();
  my $ticksPer      = ($hasLeadIn) ? length($measures[1]) : length($measures[0]);
  my $resolution    = ($ticksPer) ? $clock->measureTime / $ticksPer : 
    $DRUM_RESOLUTION;
  
  if ($hasLeadIn) {
    #throw a lead-in measure on the front to handle this
    #the lead-in probably isn't a whole measure long, 
    #but we'll fix it at the end
    unshift(@$guideMeasures, $guide->time - $clock->measureTime);
  }

  my $mTime;
  for(my $mIdx = 0; $mIdx < scalar @$guideMeasures; $mIdx++) {
    my $measure    = $measures[$mIdx];
    
    $mTime         = ($mIdx < scalar @$guideMeasures) ?
      $guideMeasures->[$mIdx] : $mTime + $clock->measureTime;
    my $nextMeasureStart = $mTime + $clock->measureTime();

    foreach my $char (split('',$measure)) {
      if ($char ne $SPACE_CHAR) {
	my $hObj = AutoHarp::Event::Note->new();
	$hObj->time($mTime);
	$hObj->pitch($drumPitch);
	$hObj->digit2Velocity($char);
	$hObj->duration($resolution);
	$drumTrack->add($hObj);
      } 
      $mTime += $resolution;
    }
    if ($mTime != $nextMeasureStart) {
      #you gave us not enough/too much to fill the measure
      my $cutoff = $nextMeasureStart - $clock->measureTime();
      #I'm going to assume you wanted to nudge this up to the end
      #(e.g. that this is a pickup to the next measure)
      my $delta = $nextMeasureStart - $mTime;
      foreach (@{$drumTrack->events}) {
	if ($_->time >= $cutoff) {
	  $_->time($_->time + $delta);
	}
      }
    }
    #set up the next resolution, in case it changes
    $clock       = $guide->clockAt($nextMeasureStart);
    $ticksPer    = length($measures[$mIdx + 1]);
    $resolution  = int($clock->measureTime / $ticksPer) if ($ticksPer);
  }
  return $drumTrack;
}

sub Melody2String {
  my $melody   = shift;
  my $guide    = _handleGuide(shift,$melody);

  my $ms       = $guide->eachMeasure();
  my $notes    = $melody->notes();
  my $nextNote = shift(@$notes);
  my $reach    = _calculateStartReach($melody);
  my $string;

  if ($melody->hasLeadIn()) {
    unshift(@$ms,$reach);
  } else {
    $string = "|";
  }
  if ($melody->reach() > $ms->[-1]) {
    #melody extends beyond this guide, so throw measures on there 
    #until we cover it
    my $clock = $guide->clockAtEnd();
    while ($ms->[-1] < $melody->reach()) {
      push(@$ms,$ms->[-1] + $clock->measureTime());
    }
  }

  my $inSlur;
  for(my $i = 0; $i < scalar @$ms; $i++) {
    my $mTime = $ms->[$i];
    my $clock = $guide->clockAt($mTime);
    my $scale = $guide->scaleAt($mTime);
    my $nextMeasure = ($ms->[$i + 1]) ? 
      $ms->[$i + 1] : 
	$mTime + $clock->measureTime();    
    
    while ($nextNote && $nextNote->time < $nextMeasure) {
      my $duration = $nextNote->duration();
      #printf "TO S(%4d): Dealing with %s, %d at %d\n",$reach,$nextNote->toString(),$duration,$nextNote->time;
      if ($nextNote->time > $reach) {
	#print "\tAdding rest first\n";
	$string .=  _note2String(undef, $scale, $nextNote->time - $reach);
      } elsif ($nextNote->time < $mTime) {
	#this note is tied from the previous measure
	$duration = $nextNote->duration - ($mTime - $nextNote->time); 
	#printf "\tShortening to %d since it started before this measure\n",$duration;
      } 
      if ($nextNote->reach() > $nextMeasure) {
	#this note extends onto the next measure and will need to be tied
	$string .= "(" if (!$inSlur);
	my $start = ($nextNote->time < $mTime) ? $mTime : $nextNote->time;
	$duration = $nextMeasure - $start;
	#printf "\tStarting a slur for it and shortening it to %d\n",$duration;
	$inSlur = 1;
      }
      my $nstr = _note2String($nextNote,$scale,$duration,$inSlur);
      $string .= $nstr;
      #printf "\tresulting string => $nstr\n";

      if ($nextNote->reach() > $nextMeasure) {
	#this note reaches over the next measure, so keep it 
	#and move to the next measure.
	$reach = $nextMeasure;
	last;
      } else {
	if ($nextNote->time < $mTime) {
	  #need to tie this note off now
	  $inSlur = 0;
	  $string .= ")";
	  #print "\tAlso ending slur\n";
	}
	$reach     = $nextNote->reach();
	$nextNote  = shift(@$notes);
      }
    }
    #Any resting needed at the end of this measure?
    if ($reach < $nextMeasure) {
      #printf "Adding some resting at the end of the measure\n";
      $string .= _note2String(undef,$scale,$nextMeasure - $reach);
      $reach = $nextMeasure;
    }
    $string .= "|";
    if (!$nextNote) {
      last;
    }
  }
  return $string;
}

sub DrumTrack2String {
  my $track      = shift;
  my $guide      = _handleGuide(shift,$track);
  my $resolution = shift || $DRUM_RESOLUTION;

  my $string  = "";
  my $ms      = $guide->eachMeasure();

  if ($track->hasLeadIn()) {
    unshift(@$ms,$track->soundingTime());
  } else {
    $string = "|";
  }
  my $hits     = $track->notes();
  my $nextHit  = shift(@$hits);
  my $reach    = _calculateStartReach($track);
  my $hadHit;
  for(my $i = 0; $i < scalar @$ms; $i++) {
    my $mTime = $ms->[$i];
    my $clock = $guide->clockAt($mTime);
    my $nextMeasure = ($ms->[$i + 1]) ? 
      $ms->[$i + 1] : 
	$mTime + $clock->measureTime();    
    #go through each measure and put a hit or a space 
    #at each tick (16th's in 4/4 in the program's current granularity)
    while ($mTime < $nextMeasure) {
      my $ceil  = int($mTime + ($resolution / 3));
      my $floor = int($mTime - ($resolution / 3));
      if ($nextHit && $nextHit->time < $ceil && $nextHit->time > $floor) {
	$hadHit++;
	$string .= $nextHit->velocity2Digit();
	$nextHit = shift(@$hits);
      } else {
	$string .= $SPACE_CHAR;
      }
      while ($nextHit && $nextHit->time < $ceil) {
	#we'll never get this dude, so skip him
	$nextHit = shift(@$hits);
      }
      $mTime += $resolution;
    }
    $string .= "|";
  }
  if (!$hadHit) {
    #this has no hits, so save our called the trouble
    return;
  }
  return $string;
}

sub Progression2String {
  my $progression = shift;
  my $guide       = _handleGuide(shift,$progression);
  my $string      = "|";
  my $ms          = $guide->eachMeasure();
  my $reach       = $guide->time();
  for(my $i = 0; $i < scalar @$ms; $i++) {
    my $mTime = $ms->[$i];
    my $clock = $guide->clockAt($mTime);
    my $scale = $guide->scaleAt($mTime);
    my $nextMeasure = ($ms->[$i + 1]) ? 
      $ms->[$i + 1] : 
	$mTime + $clock->measureTime();    
    my $chords = $progression->chordsInInterval($mTime,$nextMeasure);

    my $measureStr;

    if (!scalar @$chords) {
      #nothing in this measure, so mark off no chord
      $measureStr .= $NO_CHORD . _chordTime2String($mTime,$nextMeasure) . "|";
      next;
    }
    foreach my $c (@$chords) {
      if ($c->time > $ms->[$i]) {
	#add a space if we're not right at the measure
	$string .= " ";
      }
      if ($c->time > $mTime) {
	#chord gap
	$string .= $NO_CHORD;
	$string .= _chordTime2String($mTime,$c->time);
	$mTime   = $c->time;
      }
      $string .= $c->toString();
      my $min  = ($c->time < $mTime) ? $mTime : $c->time;
      my $max  = ($nextMeasure < $c->reach()) ? $nextMeasure : $c->reach();
      if ($max - $min < $BASE_LENGTH / 2) {
	print "PROG\n";
	$progression->dump();
	print "CHORD\n";
	$c->dump();
	confess "Cannot represent that chord in music notation";
      }
      $string .= _chordTime2String($min,$max);
      $mTime   = $c->reach();
    }
    #pick up the "no chord at the end of the measure" edge case
    if ($mTime < $nextMeasure) {
      $string .= " $NO_CHORD";
      $string .= _chordTime2String($mTime,$nextMeasure);
    }
    $string .= "|";
  }
  return $string;
}

sub _note2String {
  my $note     = shift;
  my $scale    = shift;
  my $duration = shift;
  my $inSlur   = shift;

  my $str;
  my $sharp;
  my $octave;
  
  if ($note) {
    ($str,$sharp,$octave) = ($MIDI::number2note{$note->pitch} =~ /^([A-G])(s)?(\d+)/);
  } else {
    $str = $REST;
    $octave = $BASE_OCTAVE;
  }
  
  if ($note) {
    if ($sharp) {
      if ($scale->isFlatScale()) {
	#write this as the thing above it flat
	$str = "_" . ($MIDI::number2note{$note->pitch + 1} =~ /^([A-G])/)[0];
      } else {
	$str = "^$str";
      }
    } elsif ($scale->isAccidental($note->pitch)) {
      #add a natural to note the accidentalness of this
      $str = "=$str";
    }
  }
  
  if ($octave >= $BASE_OCTAVE) {
    $str = lc($str);
  }

  if ($octave > $BASE_OCTAVE) {
    $str .= "'" x ($octave - $BASE_OCTAVE);
  } elsif ($octave < $BASE_OCTAVE - 1) {
    $str .= "," x ($BASE_OCTAVE - $octave - 1);
  }
  
  if ($duration == $BASE_LENGTH) {
    return $str;
  } 
  
  my $big   = int($duration / $BASE_LENGTH);
  my $small = $duration % $BASE_LENGTH;
  my $needParens;
  my $noteStr;
  if ($small && $BASE_LENGTH % $small) {
    #this bit is a dotted eighth or some shit
    #just break it up into bits using the greatest common factor;
    my $gcf    = _gcf($small,$BASE_LENGTH);
    if ($gcf == 1) {
      confess "Can't represent duration of $duration for $str";
    }
    my $bits   = $BASE_LENGTH / $gcf;
    my $needed = $small / $gcf;
    $noteStr = "$str/$bits" x $needed;
    $needParens = 1;
  } elsif ($small) {
    $noteStr = "$str/" . ($BASE_LENGTH / $small);
  }
  
  if ($big) {
    $big = "" if ($big == 1);
    if ($noteStr) {
      $noteStr = "$str$big$noteStr";
      $needParens = 1;
    } else {
      $noteStr = "$str$big";
    }
  }
  if ($needParens && !$inSlur) {
    $noteStr = "($noteStr)";
  }
  return $noteStr;
}

sub _gcf {
  my ($x, $y) = @_;
  ($x, $y) = ($y, $x % $y) while $y;
  return $x;
}

sub _string2Time {
  my $string   = shift;
  my @notes    = split(/($NOTE_E)/,$string);
  my $duration = 0;
  
  #these calculations might look slightly weird. e.g.
  #If I see "a/3", I will first add a base time for the a, 
  #then subtract off base time - 1/3 base time 
  #(== 2/3 base time) to correct it
  foreach my $n (@notes) {
    if ($n =~ /^$NOTE_E$/) {
      $duration += $BASE_LENGTH;
    } elsif ($n =~ m|/(\d+)?|) {
      my $factor = $1 || 2;
      $duration -= ($BASE_LENGTH - ($BASE_LENGTH / $factor));
    } elsif ($n =~ /(\d+)/) {
      $duration += ($BASE_LENGTH * $1 - $BASE_LENGTH);
    }
  }
  return $duration;
}

#returns time markers for chords
sub _chordTime2String {
  my $from     = shift;
  my $to       = shift;
  my $duration = $to - $from;
  if ($duration < $BASE_LENGTH / 2) {
    confess "Cannot represent an interval smaller than half a beat in a progression";
  }
  my $beats    = $duration / $BASE_LENGTH;
  if (int($beats) != $beats) {
    my $beat_fraction = $from / $BASE_LENGTH;
    my $subticks      = int(($duration % $BASE_LENGTH) / $MIN_LENGTH);
    if (int($beat_fraction) == $beat_fraction) {
      #we're on an even beat, so do the /'s first, then the dots
      my $str;
      if (int($beats) > 1) {
	$str = " $STRUM_CHAR" x (int($beats) - 1);
      } elsif (int($beats) == 1 && $subticks > 0) {
	#this is going to be ambiguous, so do the whole thing in dots
	$subticks += ($BASE_LENGTH / $MIN_LENGTH) - 1;
      } else {
	#this is a short chord starting on an even beat, 
	#so its name represents a subtick
	$subticks--;
      }
      return $str . $SPACE_CHAR x ($subticks);
    } else {
      #we're on an off-beat, so do the subticks first, then the strums
      return $SPACE_CHAR x ($subticks - 1) .
	" $STRUM_CHAR" x int($beats);
    }
  } else {
    return " $STRUM_CHAR" x (int($beats) - 1);
  }
}

#undoes the above
sub _string2ChordTime {
  my $str = shift;
  my $when = shift;
  $str =~ s/\s//g;

  if (!$str) {
    #a chord with no subsequent markers is a beat long
    return $BASE_LENGTH;
  }

  my $small = ($str =~ /([$SPACE_CHAR]+)/)[0];
  my $big   = ($str =~ /([$STRUM_CHAR]+)/)[0];
  
  my $time  = (length($small) * $MIN_LENGTH) +
    (length($big) * $BASE_LENGTH);

  #was the name of the chord itself a small tick or a big one?
  if ($when % $BASE_LENGTH) {
    #it's off beat, so it must be small
    $time += $MIN_LENGTH;
  } else {
    if ($str =~ /^[$SPACE_CHAR]/) {
      #it's not an off beat, but the next thing's a dot, so it's small  
      $time += $MIN_LENGTH;
    } else {
      $time += $BASE_LENGTH;
    }
  }
  return $time;
}

sub _calculateStartReach {
  my $melody = shift;
  if ($melody->hasLeadIn()) {
    return $melody->soundingTime();
  }
  return $melody->time();
}

sub _handleGuide {
  my $guide = shift;
  my $track = shift;
  if ($DEBUG && !$guide || !$guide->isa('AutoHarp::Events::Guide')) {
    confess "Notation called without a music guide.";
  }
  if ($track && $guide->time != $track->time) {
    confess "Notation called with guide and track that do not have the same zero. Badness will surely ensue!";
  }
  return $guide || AutoHarp::Events::Guide->new();
}

"You make me feel my soul";
