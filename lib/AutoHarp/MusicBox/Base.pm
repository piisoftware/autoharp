package AutoHarp::MusicBox::Base;

use AutoHarp::Constants;
use AutoHarp::Events::Guide;
use AutoHarp::MusicBox::Hook;

use MIDI;
use Carp;
use Data::Dumper;
use base qw(AutoHarp::MusicBox);
use JSON;

use strict;

#container for the various musics that we pass around (i.e. melody/progression)

sub new {
  my $class = shift;
  my $args  = {@_};
  my $self  = {$ATTR_GUIDE => 
	       ($args->{$ATTR_GUIDE}) ? $args->{$ATTR_GUIDE}->clone() :
	       AutoHarp::Events::Guide->new(),
	      };
  bless $self,$class;
  if ($args->{$ATTR_MELODY}) {
    $self->melody($args->{$ATTR_MELODY});
  }
  if ($args->{$ATTR_PROGRESSION}) {
    $self->progression($args->{$ATTR_PROGRESSION});
  }
  return $self;
}

sub fromDataStructure {
  my $class = shift;
  my $ds    = shift;
  if (ref($ds) eq 'ARRAY') {
    return $class->fromLegacyDataStructure($ds);
  }

  my $self  = {$ATTR_GUIDE => AutoHarp::Events::Guide->fromString($ds->{$ATTR_GUIDE})};
  my $progStr      = $ds->{$ATTR_PROGRESSION};
  my $trueMeasures = AutoHarp::Notation::CountMeasures($progStr);
  if ($trueMeasures) {
    $self->{$ATTR_GUIDE}->measures($trueMeasures);
  }
  $self->{$ATTR_PROGRESSION} = 
    AutoHarp::Events::Progression->fromString($progStr, $self->{$ATTR_GUIDE});
  if ($ds->{$ATTR_MELODY}) {
    my $ms = (ref($ds->{$ATTR_MELODY}) eq 'ARRAY') ? 
      $ds->{$ATTR_MELODY} : [$ds->{$ATTR_MELODY}];
    my $mel = AutoHarp::Events::Melody->new();
    $mel->time($self->{$ATTR_GUIDE}->time);
    foreach my $m (@$ms) {
      $mel->add(AutoHarp::Events::Melody->fromString($m,$self->{$ATTR_GUIDE}));
    }
    $self->{$ATTR_MELODY} = $mel;
  }
  return bless $self,$class;
}

#use the old, array-based DS for music box bases
sub fromLegacyDataStructure {
  my $class = shift;
  my $ds    = shift;
  my $self  = {};
  my $guide = 
    $self->{$ATTR_GUIDE} = 
      AutoHarp::Events::Guide->fromString(shift(@$ds));
  my $trueMeasures = 0;
  if (scalar @$ds) {
    my $progStr = shift(@$ds);
    $guide->measures(AutoHarp::Notation::CountMeasures($progStr));
    $self->{$ATTR_PROGRESSION} = AutoHarp::Events::Progression->fromString($progStr, $guide);
    $trueMeasures = $self->{$ATTR_PROGRESSION}->measures($guide->clock());
  }
  if (scalar @$ds) {
    my $mel = AutoHarp::Events::Melody->new();
    $mel->time($guide->time);
    foreach my $m (@$ds) {
      $mel->add(AutoHarp::Events::Melody->fromString($m,$guide));
    }
    $self->{$ATTR_MELODY} = $mel;
  }
  return bless $self,$class;
}

sub toDataStructure {
  my $self  = shift;
  my $guide = $self->guide();
  my $ret   = {$ATTR_GUIDE => $guide->toString()};
  if ($self->hasProgression()) {
    $ret->{$ATTR_PROGRESSION} = $self->progression->toString($guide);
  }
  if ($self->hasMelody()) {
    my $ms = $self->melody->toDataStructure($guide);
    $ret->{$ATTR_MELODY} = (scalar @$ms == 1) ? $ms->[0] : $ms;
  }
  return $ret;
}

sub toHook {
  my $self = shift;
  return AutoHarp::MusicBox::Hook->new(%$self);
}

sub guide {
  return $_[0]->objectAccessor($ATTR_GUIDE, $_[1]);
}

sub progression {
  my $self = shift;
  my $arg = shift;
  my $res = $self->objectAccessor($ATTR_PROGRESSION, $arg);
  if ($arg && $res) {
    $res->time($self->time());
    #I'll allow you to set our duration if our guide is empty
    if ($res->duration() > $self->duration()) {
      $self->duration($res->duration());
    }
    $self->setScalesFromProgression();
  }
  return $res;
}

sub hasProgression {
  return ref($_[0]->{$ATTR_PROGRESSION});
}

sub melody {
  my $self = shift;
  my $arg  = shift;
  if ($arg && $arg->isa('AutoHarp::Events::Melody')) {
    my $c = $arg->clone();
    $c->time($self->time);
    $self->{$ATTR_MELODY} = $c;
  }
  return $self->{$ATTR_MELODY};
}

sub hasMelody {
  return ref($_[0]->{$ATTR_MELODY});
}

sub set {
  my $self = shift;
  my $key  = shift;
  my $val  = shift;
  if ($key && $self->can($key)) {
    return $self->$key($val);
  }
  return;
}

sub get {
  my $self = shift;
  my $key  = shift;
  if ($key && $self->can($key)) {
    return $self->$key();
  }
  return;
}

sub parts {
  my $self = shift;
  my $ret  = [];
  foreach my $m (@{$self->music()}) {
    push(@$ret,$m->clone());
  }
}

sub clone {
  my $self = shift;
  my $clone = $self->SUPER::clone();
  #for the purposes of a music box, clone keeps the same uid
  #same music == same essential self
  $clone->uid($self->uid());
  return $clone;
}

sub cloneWithGuide {
  my $self = shift;
  return ref($self)->new($ATTR_GUIDE => $self->guide);
}

sub unsetProgression {
  delete $_[0]->{$ATTR_PROGRESSION};
}

sub unsetMelody {
  delete $_[0]->{$ATTR_MELODY};
}

sub clear {
  my $self = shift;
  my $part = shift;
  delete $self->{$part};
}

sub clearMusic {
  my $self = shift;
  $self->unsetProgression();
  $self->unsetMelody();
}

sub hasMusic {
  my $self = shift;
  return ($self->hasProgression || $self->hasMelody);
}

sub music {
  my $self = shift;
  my $ret  = [];
  push(@$ret, $self->melody()) if ($self->hasMelody()); 
  push(@$ret, $self->progression()) if ($self->hasProgression);
  return $ret;
}

#does this music have any notes before time 0?
sub hasPickup {
  my $self = shift;
  return ($self->hasMelody() && $self->melody->soundingTime() < $self->time());
}

#make this music twice as long by repeating it
sub repeat {
  my $self = shift;
  my $d = $self->guide->duration();
  $self->guide->repeat();
  foreach my $m (@{$self->music}) {
    $m->repeat($d);
  }
}

#cut this music down to its first half
sub halve {
  my $self = shift;
  return $self->truncate($self->duration() / 2);
}

#return the second half of this music
sub secondHalf {
  my $self = shift;
  my $m    = $self->subMusic(($self->reach - $self->time) / 2);
  $m->tag($self->tag);
  return $m;
}

sub tracks {
  my $self    = shift;
  my $tracks = [];
  my $channel = 0;

  push(@$tracks, $self->guide->track({$ATTR_CHANNEL => $channel++}));
  push(@$tracks, $self->{$ATTR_GUIDE}->metronomeTrack());
  foreach my $m (@{$self->music()}) {
    my $c;
    if ($m->channel() == $PERCUSSION_CHANNEL) {
      $c = $m->channel();
    } else {
      $c = $channel++;
    }
    push(@$tracks, $m->track({$ATTR_CHANNEL => $c}));
  }
  return $tracks;
}

sub truncate {
  my $self     = shift;
  my $duration = shift;
  $duration = ($self->{$ATTR_GUIDE}->duration()) if (!length($duration));
  foreach my $m (@{$self->music()}) {
    if ($m->duration > $duration) {
      $m->truncate($duration);
    }
  }
  if ($self->{$ATTR_GUIDE}->duration > $duration) {
    $self->{$ATTR_GUIDE}->truncate($duration);
  } 
}

sub getMusicForMeasures {
  my $self = shift;
  my $from = shift;
  my $to   = shift;
  if ($from >= 1 && $to >= $from) {
    my $measures = $self->eachMeasure();
    my $startTime = $measures->[$from - 1];
    my $endTime   = ($to < scalar @$measures) ? $measures->[$to] : $self->reach();
    return $self->subMusic($startTime,$endTime);
  }
  confess "Invalid values $from and $to passed to getMusicForMeasures";
}

sub subMusic {
  my $self  = shift;
  my $from  = shift;
  my $to    = shift;
  my $new   = AutoHarp::MusicBox::Base->new();
  $new->guide($self->guide->subList($from,$to));
  if ($self->hasProgression()) {
    $new->progression($self->{$ATTR_PROGRESSION}->subMelody($from,$to));
  }
  $new->melody($self->melody->subMelody($from,$to));
  return $new;
}

sub time {
  my $self = shift;
  my $arg  = shift;
  if (length($arg) && $arg != $self->{$ATTR_GUIDE}->time) {
    my $was   = $self->{$ATTR_GUIDE}->time;
    my $is    = $self->{$ATTR_GUIDE}->time($arg);
    my $delta = $is - $was;
    foreach my $m (@{$self->music()}) {
      $m->time($m->time + $delta);
    }
  } 
  return $self->{$ATTR_GUIDE}->time;
}

sub soundingTime {
  my $self = shift;
  return ($self->hasPickup()) ? $self->melody->soundingTime : $self->time;
}

sub duration {
  my $self = shift;
  my $arg  = shift;
  if (length($arg)) {
    $self->guide->setDuration($arg);
  }
  return $self->{$ATTR_GUIDE}->duration;
}

sub reach {
  my $self = shift;
  my $arg  = shift; 
  if (length($arg)) {
    confess "Reach of a piece of music cannot be set directly";
  }
  return $self->{$ATTR_GUIDE}->reach;
}

sub eachMeasure {
  return (shift)->guide->eachMeasure();
}

sub measures {
  my $self = shift;
  my $arg = shift;
  if (length($arg)) {
    return $self->setMeasures($arg);
  }
  return $self->{$ATTR_GUIDE}->measures();
}

sub bars {
  return $_[0]->measures($_[1]);
}

#how long will this music play?
sub durationInSeconds {
  my $self = shift;
  my $secs = 0;
  foreach (@{$self->eachMeasure()}) {
    my $clock = $self->clockAt($_);
    $secs += $clock->ticks2seconds($clock->measureTime());
  }
  return $secs;
}

sub setMeasures {
  my $self = shift;
  my $arg  = shift;
  if ($arg) {
    my $oldDuration = $self->{$ATTR_GUIDE}->duration();
    $self->{$ATTR_GUIDE}->setMeasures($arg);
    if ($oldDuration < $self->{$ATTR_GUIDE}->duration()) {
      $self->truncate();
    }
    return 1;
  }
  return;
}

sub append {
  my $self = shift;
  my $music = shift;
  if (ref($music) && $music->isa('AutoHarp::MusicBox::Base')) {
    my $appendee = $music->clone;
    $appendee->time($self->reach);
    return $self->add($appendee);
  }
  return;
}

sub add {
  my $self  = shift;
  my $music = shift;
  if (ref($music) && $music->isa('AutoHarp::MusicBox::Base')) {
    my $addee = $music->clone();
    if ($addee->hasProgression && $self->hasProgression()) {
      $self->{$ATTR_PROGRESSION}->add($addee->progression);
    }
    if ($addee->hasMelody()) {
      if (!$self->hasMelody()) {
	#make an empty melody at the correct time so we can add this
	my $empty = AutoHarp::Melody->new();
	$empty->time($self->time);
	$self->melody($empty);
      }
      $self->melody->add($addee->melody);
    }
    #set the guides correctly
    $self->guide->add($addee->guide());
    if ($addee->reach() > $self->reach()) {
      $self->guide->setEnd($addee->reach());
    }
  }
}

#allows a global set-tempo, returns tempo at time 0
sub tempo {
  my $self = shift;
  return $self->{$ATTR_GUIDE}->tempo(@_);
}

sub genre {
  my $self = shift;
  return $self->{$ATTR_GUIDE}->genre(@_);
}

#Guide convenience methods
sub setClock {
  my $self = shift;
  return $self->{$ATTR_GUIDE}->setClock(@_);
}

sub setScale {
  my $self = shift;
  return $self->{$ATTR_GUIDE}->setScale(@_);
}

sub scales {
  my $self = shift;
  return $self->{$ATTR_GUIDE}->scales();
}

sub clockAt {
  my $self = shift;
  return $self->{$ATTR_GUIDE}->clockAt(@_);
}

sub scaleAt {
  my $self = shift;
  my $scale = $self->{$ATTR_GUIDE}->scaleAt(@_);
  #we may have differing opinions than MIDI on what the scale is here
  #e.g. the scale may come back as C Major, but we might call it F Lydian
  #since it starts from an F Chord. 
  if ($self->hasProgression()) {
    my $chord = $self->progression->chordAt($scale->time());
    if ($chord) {
      foreach my $betterScale (@{AutoHarp::Scale->allScalesForChord($chord)}) {
	if ($betterScale->equals($scale)) {
	  #this scale better represents us here
	  return $betterScale;
	}
      }
    }
  }
  return $scale;
}

sub phraseDuration {
  my $self = shift;
  if ($self->hasProgression() && $self->progression->hasChords()) {
    my $chCt = $self->progression->phraseLength(1);
    my $pd = 0;
    for (0..$chCt - 1) {
      $pd += $self->progression->chords->[$_]->duration;
    }
    if (!$pd) {
      confess "Don't think this should happen. Count was $chCt";
    }
    return $pd;
  }
  return $self->duration();
}

sub hasPhrases {
  my $self = shift;
  return ($self->duration() > 0 &&
	  $self->duration >= $self->phraseDuration() * 2);
}

#how far is the given time from the end of a phrase in this music?
sub timeToEndOfPhrase {
  my $self  = shift;
  my $when  = shift;
  if ($when >= $self->reach()) {
    return 0;
  }
  my $pd    = $self->phraseDuration();
  my $toPhraseEnd = $self->time + $pd;
  while ($when > $toPhraseEnd) {
    $toPhraseEnd += $pd;
    if ($toPhraseEnd > $self->reach()) {
      $toPhraseEnd = $self->reach();
      last;
    }
  }
  return $toPhraseEnd - $when;
}

sub setScalesFromProgression {
  my $self   = shift;
  if ($self->hasProgression() && $self->progression->hasChords()) {
    $self->guide->clearScales();
    my $chords = $self->progression()->chords();
    #we start from the first chord--
    #wlog let it be C Major. C Major can be a chord in a 
    #C, F, or G major scale. We'll try each of those and see how far we get
    #if we ever get to the end of the progression, we're done. 
    #otherwise we start at the first non-conforming chord and start again
    #e.g. a progression of 
    #C G D E B C G D
    #will give us keys of C Lydian (G major), then E Major, then C Lydian again
    #we'll also prefer modes of the previous chords to entirely new modes
    #e.g. a progression of
    #C Am F G Am D7 G C
    #will switch from C Major to C Lydian at the D7, rather than going to D Major
    my $conformsTo = 0;
    my $first = $chords->[0];
    my $scales = [];
    my $seen = {};
    while ($conformsTo < $#$chords) {
      #printf "%s at %d\n",$first->toString,$conformsTo;
      if (!$seen->{$first->toString()}++) {
	#print "\tnew, so adding three scales for it.\n";
	push(@$scales, @{AutoHarp::Scale->allScalesForChord($first)});
      }
      my $scale;
      my $max        = $conformsTo;
      my $conformItr = -1;
      foreach my $s (@$scales) {
	#printf "checking from %s against %s\n",$first->toString(),$s->key();
	for (my $j = $conformsTo + 1; $j < scalar @$chords; $j++) {
	  #printf "\tchecking against %s",$chords->[$j]->toString();
	  if ($chords->[$j]->inScale($s)) {
	    #print "...ok\n";
	    $conformItr = $j;
	  } else {
	    #this chord isn't in this scale. Bail here.
	    #print "...nope\n";
	    last;
	  }
	}
	if ($conformItr > $max) {
	  #printf "%s got to %d, so taking that\n",$s->key(),$conformItr;
	  #if this one got farther than anybody else so far, it wins
	  $scale = $s;
	  $max   = $conformItr;
	  if ($conformItr == $#$chords) {
	    #we're at the end of the progression, so we're done
	    last;
	  }
	}
      }
      #printf "Checked all the scales we have\n";
      if (!$scale) {
	#this chord doesn't even conform to its primary scale
	#it's C over F# or Gmflat11 or some shit. Use its primary scale anyway
	$scale = AutoHarp::Scale->fromChord($first);
	$max++;
      }
      if ($max == $conformsTo) {
	grep {print $_->key . "\n"} @$scales;
	confess "We got stuck at " . $first->toString();
      }
      #set this scale at the time of the first chord
      $self->setScale($scale,$first->time);
      #set the conforming iterator to as far as we got
      $conformsTo = $max;
      #get the next non-conforming chord
      #we might be done at this point, but if so we'll bail out of the loop
      $first = $chords->[$conformsTo + 1];
      if ($first) {
	#printf "Starting again from %s\n\n",$first->toString();
      } else {
	#print "All done\n";
      }
    }
  }
  return 1;
}

sub toString {
  my $self = shift;
  my $str  = sprintf("guide==>\n\t%s\n",$self->guide->toString());
  
  foreach my $m (@{$self->music()}) {
    $str .= sprintf("%s==>\n\t%s\n",$m->type,$m->toString($self->guide));
  }
  return $str;
}

"Meet me at the wrecking ball"
