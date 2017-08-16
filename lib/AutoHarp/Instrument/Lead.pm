package AutoHarp::Instrument::Lead;

use Carp;
use strict;
use AutoHarp::Fuzzy;
use AutoHarp::Constants;
use base qw(AutoHarp::Instrument);

my $WHEEL_ABS_MAX     = '8191';

sub initPatchChannel {
  my $class = shift;
  my $inst  = shift;
  my $fFunc = sub {return {$ATTR_PATCH => 
			   AutoHarp::Instrument::getInstrumentFromString(@_)}};
  if ($inst) {
    return $fFunc->($inst);
  } elsif (mostOfTheTime) {
    return $fFunc->(pickOne('Synth Lead','kalimba','piano','Violin','ethnic','Acoustic Guitar'));
  } 
  return $fFunc->();
}

sub playDecision {
  my $self = shift;
  my $seg = shift;
  
  my $is = $self->isPlaying();
  if ($seg->songElement eq $SONG_ELEMENT_SOLO) {
    return 1;
  } elsif ($seg->songElement eq $SONG_ELEMENT_INSTRUMENTAL) {
    return $is || asOftenAsNot;
  } elsif ($seg->songElement eq $SONG_ELEMENT_CHORUS && $seg->isRepeat()) {
    return $is || asOftenAsNot;
  } elsif ($seg->songElement eq $SONG_ELEMENT_OUTRO) {
    return $is || mostOfTheTime;
  }
  return;
}

sub play {
  my $self    = shift;
  my $segment = shift;
  my $follow  = shift;
  my $solo = AutoHarp::Events::Melody->new();
  $solo->time($segment->time);
  if ($segment->musicBox->hasProgression()) {
    #split the prog into chords and melodize each one with a different 
    #rhythm split
    my $speed;
    my $music = $segment->musicBox;
    my $gen = AutoHarp::Generator::Magenta->new();
    foreach my $c (@{$music->progression->chords()}) {
      if (!$speed || sometimes) {
	$speed = pickOne(2,4,3);
      }
      $solo->add($gen->melodize(
				$music->subMusic($c->time, $c->reach),
				{$ATTR_RHYTHM_SPEED => $speed}
			       ));
    }
    if (!scalar @{$solo->notes}) {
      confess "lead instrument didn't produce any notes for progression of length " . $music->progression->duration;
    }
    #go through the notes in this play and replace half or whole steps
    #with portamentos
    for(my $i = 0; $i < $#$solo; $i++) {
      my $n = $solo->[$i];
      my $p = $solo->[$i+1];
      if ($n->isNote() && 
	  $p->isNote() && 
	  $n->pitch != $p->pitch && 
	  abs($n->pitch - $p->pitch) < 3 &&
	  mostOfTheTime) {
	my $wDiff = int((($n->pitch - $p->pitch) / 2) * $WHEEL_ABS_MAX);
	my $ticksToFlipIn = int($n->duration / 4);
	my $steps = int($wDiff / $ticksToFlipIn);
	my @porta;
	my $t    = $p->time - $ticksToFlipIn;
	my $pSet = $steps;
	foreach (0..$ticksToFlipIn) {
	  push(@porta,[$EVENT_PITCH_WHEEL,
		       $t + $_,
		       0,
		       $pSet]);
	  $pSet += $steps;
	}
	#add an aftertouch at the end to ease note decay
	push(@porta,[$EVENT_CHANNEL_AFTERTOUCH,
		     $p->time,
		     0,
		     $p->velocity()]);
	#and set the porta level back to zero
	push(@porta,[$EVENT_PITCH_WHEEL,
		     $p->reach,
		     0,
		     0]);
	#splice out the second note
	splice(@$solo,$i+1,1);
	#add all that crud
	$solo->add([@porta]);
	#adjust the iterator to the next note
	$i += scalar @porta;
      }
    }
    return $solo;
  }
  #no progression. I not know what to play
  return;
}

"The way you slap my face just fills me with desire";
