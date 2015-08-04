package AutoHarp::Instrument::DrumLoop;

use MIDI;
use strict;
use AutoHarp::Event::Note;
use AutoHarp::Event::Chord;
use AutoHarp::Fuzzy;
use AutoHarp::Constants;
use AutoHarp::Events::DrumTrack;
use AutoHarp::Notation;
use AutoHarp::Model::Genre;
use AutoHarp::Model::Loop;

use Carp;
use Data::Dumper;

use base qw(AutoHarp::Instrument);

my $LOOPS = 'loops';

#Total swags, based on nothing. TODO: TUNE THIS.
my $GENRE_WEIGHT            = 5;
my $TEMPO_WEIGHT            = 10;
my $BUCKET_WEIGHT           = 3;
my $SONG_AFFILIATION_WEIGHT = 20;
my $SONG_ELEMENT_WEIGHT     = 20;
my $FILL_WEIGHT             = -25;

sub choosePatch {
  my $self = shift;
  $self->patch(0);
}

sub name {
  return 'Drum Loop';
}

sub isDrums {
  return 1;
}

sub reset {
  my $self = shift;
  delete $self->{$LOOPS};
}

sub playDecision {
  my $self      = shift;
  my $segment   = shift;

  my $wasPlaying = $self->isPlaying();
  my $playNextSegment;
  if ($wasPlaying) {
    $playNextSegment = unlessPigsFly;
  } elsif ($segment->songElement() eq $SONG_ELEMENT_INTRO) {
    $playNextSegment = mostOfTheTime;
  } else {
    $playNextSegment = almostAlways;
  }
  return $playNextSegment;
}

sub patterns {
  my $self = shift;
  my $ret = [];
  while (my ($t,$td) = each %{$self->{$LOOPS}}) {
    while (my ($g,$gd) = each %$td) {
      push(@$ret,{$ATTR_TAG => $t,
		  $ATTR_FILE => $gd->{$ATTR_FILE}});
    }
  }
  return $ret;
}

sub play {
  my $self     = shift;
  my $segment  = shift;
  my $duration = $segment->duration();

  #TODO: This all assumes one clock per segment 
  #(i.e. no meter changes. Tempo changes would be okay)
  #Fix in the future, maybe.
  my $tag     = $segment->musicTag(); #chorus, verse, whatever
  if (!$tag) {
    confess "Drum Loop got a segment without a song element tag. Cannot have that";
  }
  my $clock = $segment->music->clock();  
  my $loop  = $self->{$LOOPS}{$tag};
  if (!$loop) {
    $loop = $self->selectLoop($segment);
    $self->{$LOOPS}{$tag} = $loop;
  }
  my $base  = $loop->events();
  if (!$base) {
    print Dumper $loop;
    confess "Unable to produce a drum track from loop";
  }
  my $beat  = AutoHarp::Events::DrumTrack->new();
  my $t     = $beat->time($segment->time());
  my $start = $t;
  while ($beat->measures($clock) < $segment->measures()) {
    #make sure to strip off any lead-in after the first repeat
    my $b   = ($t == $segment->time) ? 
      $base->clone() : 
	$base->subMelody($base->time,$base->reach);
    my $was = $b->time($t);
    eval {
      $beat->add($b);
      $t = $beat->time + ($beat->measures($clock) * $clock->measureTime());
    };
    if ($@ || $t <= $was) {
      print JSON->new()->pretty()->encode($base);
      print "BASE\n";
      $b->dump();
      print "BEAT\n";
      $beat->dump();
      confess sprintf("Bad things happening when constructing the beat ($@)");
    }
  }
  #truncate as necessary 
  if ($beat->duration() > $segment->duration()) {
    $beat->truncate($segment->duration());
  }
    
  if (!$self->isPlaying() && !$beat->hasLeadIn()) {
    #did I start playing just now? Can I find a pickup?
    my $pickup = $self->findLeadIn($segment);
    if ($pickup) {
      my $pTrack = $pickup->events();
      my $pMeas = $pTrack->measures($segment->music->clock);
      if ($pMeas > 1 && unlessPigsFly) {
	$pTrack->time(0);
	#cut this down to its last measure. Or 2.
	my $diff = pickOne(1,1,1,2);
	$pTrack = $pTrack->subMelody(($pMeas - $diff) * $clock->measureTime);
	#pTrack is now $diff measures long
	$pMeas = $diff;
      }
      $pTrack->time($segment->time - ($pMeas * $clock->measureTime));
      $beat->add($pTrack);
    }
  }
  $self->handleTransition($segment,$beat);
  return $beat;
}

#do any massaging of the last measure
sub handleTransition {
  my $self      = shift;
  my $segment   = shift;
  my $beat      = shift;

  my $clock     = $segment->music->clockAtEnd();
  my $bTime     = $clock->beatTime;
  my $bPer      = $clock->beatsPerMeasure();
  
  my $fillTime  = 0;
  my $loop = $self->{$LOOPS}{$segment->musicTag()};
  if ($segment->transitionOutIsDown()) {
    #take some shit out
    my $beatsToAlter = int(rand($bPer)) + 1;
    my $timeToAlter  = $segment->reach() - ($beatsToAlter * $bTime);
    my $save;
    if (asOftenAsNot) {
      #get rid of all but kicks
      $save = 'Bass';
    } elsif (asOftenAsNot) {
      #get rid of all but hats
      $save = 'Hat';
    } else {
      #get rid of all but hats and kicks
      $save = ['Bass','Hat'];
    }
    $beat->pruneExcept($save,$timeToAlter);
  } elsif ($segment->transitionOutIsUp()) {
    my $f = $self->findFill($segment);
    if ($f) {
      my $fill      = $f->events();
      my $measures  = $fill->measures($clock);
      if ($measures > 1 && unlessPigsFly) {
	#just take the last measure or two of this
	my $l = pickOne(1,2);
	$fill = $fill->subMelody($fill->time + 
				 (($measures - $l) * $clock->measureTime));
	$measures = $l;
      }
      my $fillStart = $segment->reach() - ($measures * $clock->measureTime);
      $fill->time($fillStart);
      $beat->truncateToTime($fillStart);
      $beat->add($fill);
    }
  } elsif ($loop->events()->measures($clock) != $segment->measures()) {
    #straight transition, and this loop isn't naturally the same length 
    #as this segment. 
    #assume there's no transition there, and we need to create one
    my $snare = pickOne($beat->snares());
    if (!$snare) {
      my $drums = $beat->split();
      #if no snares, try and find something else of interest
      foreach my $key (keys %$drums) {
	if ($key =~ /Tom/ || 
	    $key =~ /High/ || 
	    $key =~ /Hi / ||
	    $key =~ /Clap/) {
	  $snare = $MIDI::percussion2notenum{$key};
	  last;
	}
      }
    }
    if ($snare) {
      my $snareTime = $segment->reach() - ($bTime * (int(rand(2)) + 1));
      #go through and get the hi-hats in this time
      my $hats = $beat->prune('Hat',$snareTime);
      #mostly add them back in as snare hits 
      #because why not?
      foreach my $h (grep {mostOfTheTime} @$hats) {
	$h->pitch($snare);
	if (!$beat->hasHitAtTime($h)) {
	  $beat->add($h);
	} 
      }
    }
  }
  return 1;
}

sub selectLoop {
  my $self = shift;
  my $segment = shift;
  
  #get the set of drum loops that match by type and meter
  my $loops = AutoHarp::Model::Loop->loadByTypeAndMeter($DRUM_LOOP,
							$segment->music->clock->meter);
  #go through the existing loops, if any, and create some weights 
  #based on bucket, song affiliation, and genre
  my $weights;
  foreach my $l (values %{$self->{$LOOPS}}) {
    foreach my $b (@{$l->getBuckets()}) {
      $weights->{$ATTR_BUCKET}{$b}++;
    }
    foreach my $g (@{$l->genres()}) {
      $weights->{$ATTR_GENRE}{$g->id}++;
    }
    foreach my $s (@{$l->getSongAffiliations}) {
      $weights->{$ATTR_SONG}{$s}++;
    }
  }
  my $segmentGenreId = ($segment->genre) ? $segment->genre->id : 0;

  #TODO: Like, evolve machine learning to do this:
  #loop through the available choices that matched our meter.
  #weigh ones that match what we've got heavier than those that don't. 
  #Weights defined up top
  my @options;
  my $totalScores;
  foreach my $l (@$loops) {
    my $score;

    #if the segment has a genre, require that we match it
    my $genreMatch = !$segmentGenreId;
    foreach my $g (@{$l->genres}) {
      if ($g->id == $segmentGenreId) {
	$genreMatch = 1;
      }
      $score += $weights->{$ATTR_GENRE}{$g->id} * $GENRE_WEIGHT;
    }
    next if (!$genreMatch);
    
    if ($l->matchesTempo($segment->music->clock->tempo())) {
      $score += $TEMPO_WEIGHT;
    }
    foreach my $b (@{$l->getBuckets()}) {
      $score += $weights->{$ATTR_BUCKET}{$b} * $BUCKET_WEIGHT;
    }
    foreach my $s (@{$l->getSongAffiliations}) {
      if ($weights->{$ATTR_SONG}{$s}) {
	$score += $weights->{$ATTR_SONG}{$s} * $SONG_AFFILIATION_WEIGHT;
	if ($l->matchesSongElement($segment->songElement())) {
	  $score += $SONG_ELEMENT_WEIGHT * $weights->{$ATTR_SONG}{$s};
	}
      }
    }
    if ($l->isFill()) {
      #this is probably negative. Right? RIGHT?
      $score += $FILL_WEIGHT;
    }
    if ($score > 0) {
      push(@options, [$score,$l]);
      $totalScores += $score;
    }
  }
  if (scalar @options) {
    #pick randomly based on weights of available options
    my $r          = rand();
    my $rangeStart = 0;
    for (my $i = 0; $i < scalar @options; $i++) {
      my $w = $options[$i][0] / $totalScores;
      if ($r >= $rangeStart && $r < ($rangeStart + $w)) {
	return $options[$i][1];
      }
    }
  }
  if (scalar @$loops) {
    #dangit--nothing weighted matched. Just pick something in the same meter
    return pickOne($loops);
  }
  confess sprintf ("Cannot play in %s meter with genre %s. No drum loops found",
		   $segment->music->clock->meter,
		   ($segmentGenreId) ? $segment->genre->name : 'unset');
}

sub findLoopBySegmentAndElement {
  my $self    = shift;
  my $segment = shift;
  my $element = shift;
  my $eMap = {map {$_->loop_id => 1} @{AutoHarp::Model::LoopAttribute->loadByAttributeValue($SONG_ELEMENT, $element)}};
  my $loop    = $self->{$LOOPS}{$segment->musicTag};  
  
  my @definites;
  my @maybes;
  my $attrs = {};
  if ($loop) {
    $attrs->{$ATTR_SONG} = {map {$_ => 1} @{$loop->getSongAffiliations}};
    $attrs->{$ATTR_BUCKET} = {map {$_ => 1} @{$loop->getBuckets}};
    $attrs->{$ATTR_TEMPO} = $loop->getClock()->tempo;
  }
  foreach my $eLoop (grep {$eMap->{$_->id}} 
		     @{AutoHarp::Model::Loop->loadByTypeAndMeter
			 ($DRUM_LOOP, $segment->music->clock->meter)
		       }) {
    if (scalar grep {$attrs->{$ATTR_SONG}{$_}} @{$eLoop->getSongAffiliations()}) {
      #yo. Strong affiliation
      push(@definites,$eLoop);
    } else {
      my $bucketsInCommon = scalar 
	grep {$attrs->{$ATTR_BUCKET}{$_}} 
	  @{$eLoop->getBuckets()};
      if ($bucketsInCommon > 1 && $eLoop->matchesTempo($attrs->{$ATTR_TEMPO})) {
	#a couple of buckets and tempo, so yes
	push(@definites, $eLoop);
      } else {
	push(@maybes,$eLoop);
      }
    }
  }
  if (scalar @definites && unlessPigsFly) {
    return pickOne(@definites);
  } 
  return pickOne(@maybes);
}

sub findFill {
  my $self = shift;
  my $segment = shift;
  return $self->findLoopBySegmentAndElement($segment,$SONG_ELEMENT_FILL);
}

sub findLeadIn {
  my $self    = shift;
  my $segment = shift;
  return $self->findLoopBySegmentAndElement($segment, $SONG_ELEMENT_INTRO);
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
