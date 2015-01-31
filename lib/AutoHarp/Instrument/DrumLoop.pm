package AutoHarp::Instrument::DrumLoop;

use MIDI;
use strict;
use AutoHarp::Event::Note;
use AutoHarp::Event::Chord;
use AutoHarp::Fuzzy;
use AutoHarp::Constants;
use AutoHarp::Events::DrumTrack;
use AutoHarp::Notation;
use AutoHarp::Genre;

use Carp;
use Data::Dumper;

use base qw(AutoHarp::Instrument);

my $PATTERNS = 'patterns';
my $TALK = !$ENV{AUTOHARP_QUIET};

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
  delete $self->{$PATTERNS};
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
  while (my ($t,$td) = each %{$self->{$PATTERNS}}) {
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
  my $genre    = $segment->genre() || AutoHarp::Genre->new('Rock');

  #TODO: This all assumes on clock per segment 
  #(i.e. no meter changes. Tempo changes would be okay)
  #Fix in the future, maybe.
  my $gname = $genre->name();
  my $tag   = $segment->musicTag();
  if (!$tag) {
    confess "Drum Loop got a segment without a music tag. Cannot have that";
  }
  my $clock = $segment->music->clock();  
  my $loop  = $self->{$PATTERNS}{$tag}{$gname} || $genre->findLoop($clock,$tag);
  if (!$loop) {
    #crud. Gotta force it
    my @options;
    foreach my $p (grep {$_->{$ATTR_TAG} ne $SONG_ELEMENT_LEADIN} 
		   @{$genre->getPatterns()}) {
      my $pc = AutoHarp::Clock->new(%$p);
      if ($clock->meter() eq $pc->meter()) {
	push(@options,{pattern => $p,
		       tempoDiff => abs($pc->tempo - $clock->tempo)}
	    );
      } 
    }
    my $td;
    foreach my $o (grep {-f AutoHarp::Config::GenreLoopFile($_)} @options) {
      #find the closest match.
      if (!$td || $td > $o->{tempoDiff}) {
	$loop = $o->{pattern};
	$td   = $o->{tempoDiff};
      }
    }
    if (!$loop) {
      my $err = sprintf("Got no loop for %s (%s, %s %d bpm). I cannot play in this genre and meter",
			$genre->name,
			$tag,
			$clock->meter(),
			$clock->tempo());
      confess $err;
    }
  }
  $self->{$PATTERNS}{$tag}{$gname} ||= $loop;
  my $beat  = AutoHarp::Events::DrumTrack->new();
  my $base  = __trackFromGenrePattern($loop);
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
    my $pickup = __trackFromGenrePattern($genre->findLeadIn($clock));
    if ($pickup && mostOfTheTime) {
      my $measures = $pickup->measures($clock);
      $pickup->time($segment->time - ($measures * $clock->measureTime));
      $beat->add($pickup);
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
  } elsif ($segment->transitionOutIsUp() && $segment->genre()) {
    my $f = $segment->genre->findFill($segment->music->clockAtEnd());
    if ($f) {
      my $fill      = __trackFromGenrePattern($f);
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
  } else {
    #straight transition.
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

sub __trackFromGenrePattern {
  my $pattern = shift;
  my $track;
  if ($pattern) {
    my $file = AutoHarp::Config::GenreLoopFile($pattern->{$ATTR_FILE});
    if (!$file || !-f $file) {
      confess "Received invalid pattern containing $file, which doesn't exist!";
    }
    eval {
      my $file = 
      my $ts = AutoHarp::Events::DrumTrack->fromFile($file);
      my $g = shift(@$ts);
      $track = shift(@$ts);
    };
    if ($@ || 
	!$track || 
	!$track->isa('AutoHarp::Events::DrumTrack') ||
	!$track->duration) {
      confess "Error loading drum track from $file ($@). Probably you want to nuke that file from your loop library";
    }
  }
  return $track;
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
