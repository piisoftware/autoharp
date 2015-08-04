package AutoHarp::Events;
use base qw(AutoHarp::Class);

use AutoHarp::Events::Guide;
use AutoHarp::Model::Loop;
use AutoHarp::Constants;
use strict;
use Carp;
use MIDI;

sub new {
  my $class    = shift;
  my $events   = shift;
  my $sawZero;
  my $time;
  my $self     = [];

  if (ref($events)) {
    foreach my $e (@$events) {
      if (ref($e) eq 'ARRAY') {
	eval {
	  $e = AutoHarp::Event->new($e);
	};
	if ($@) {
	  next;
	}
      }
      if (!ref($e) || !$e->isa('AutoHarp::Event')) {
	next;
      }

      next if ($e->isZeroEvent() && $sawZero++);

      push(@$self,$e);
      if (!length($time) || $time > $e->time) {
	$time = $e->time;
      }
    }
  }
  if (!$sawZero) {
    unshift(@$self,AutoHarp::Event->zeroEvent($time));
  }
  bless $self,$class;
  $self->sort();
  return $self;
}

sub fromOpus {
  my $class = shift;
  my $opus  = shift;
  my $ticks = $opus->ticks();
  my $tracks = [];
  my $guideEvents = [];
  my $endTime;
  my $rt = ($ticks != $TICKS_PER_BEAT) ? 
    sub {return int(($TICKS_PER_BEAT * $_[0]) / $ticks)} : undef;
  
  foreach my $t (@{$opus->tracks_r}) {
    my $track = [];
    foreach my $e (@{MIDI::Score::events_r_to_score_r($t->events_r)}) {
      my $eo = AutoHarp::Event->new($e);
      if ($rt) {
	$eo->time($rt->($eo->time));
	$eo->duration($rt->($eo->duration));
      }
      if ($eo->isMusicGuide()) {
	push(@$guideEvents,$eo);
      } elsif ($eo->isMusic()) {
	$endTime = $eo->reach if ($eo->reach > $endTime);
	push(@$track,$eo);
      }
    }
    push(@$tracks,$track) if (scalar @$track);
  }
  my $guide = AutoHarp::Events::Guide->new($guideEvents);
  $guide->setEnd($endTime);
  my $retTracks = [$guide];
  foreach my $t (@$tracks) {
    my $to = $class->new($t);
    push(@$retTracks,$to) if ($to->duration > 0);
  }
  return $retTracks;
}

sub fromFile {
  my $class = shift;
  my $file  = shift;
  my $opus;
  eval {
    $opus  = MIDI::Opus->new({'from_file' => $file});
  };
  if ($@ || !$opus) {
    confess "Couldn't load a valid opus from $file: $@";
  }
  return $class->fromOpus($opus);
}

sub fromArrayOfEvents {
  my $class  = shift;
  my $events = shift;
  my $self   = [];
  my $tZero  = 0;
  if (ref($events) && scalar @$events) {
    my $nTime = $tZero = $events->[0]->time;
    foreach my $e (@$events) {
      next if ($e->isMarker());
      $e->time($nTime);
      $nTime = $e->reach();
      push(@$self,$e);
    }
  }
  bless $self,$class;
  unshift(@$self,AutoHarp::Event->zeroEvent);
  return $self;
}

sub fromScoreEvents {
  my $class     = shift;
  my $events    = shift;
  return $class->new($events);
}

sub fromTextFile {
  my $class = shift;
  my $file = shift;
  open(FILE, "$file") or die "Couldn't read $file: $!";
  my $events = [];
  while(<FILE>) {
    chomp($_);
    eval {
      push(@$events, AutoHarp::Event->fromTextLine($_));
    };
  }
  close(FILE);
  return $class->fromArrayOfEvents($events);
}

sub toTextFile {
  my $self     = shift;
  my $fileName = shift;
  if (!$fileName || !open(FILE, ">$fileName")) {
    die "Can't open $fileName for writing: $!";
  }
  foreach my $e (@$self) {
    print FILE $e->toTextLine();
    print FILE "\n";
  }
  close(FILE);
  return 1;
}

sub type {
  my $self = shift;
  return lc((ref($self) =~ /::(\w+)$/)[0]);
}

sub is {
  my $self = shift;
  my $arg  = shift;
  if ($arg) {
    $arg = "AutoHarp::" . uc(substr($arg,0,1)) . substr($arg,1);
    return $self->isa($arg);
  }
}

sub name {
  my $self = shift;
  foreach my $e (@$self) {
    if ($e->isNameEvent()) {
      return $e->[2];
    }
  }
  return $self->type();
}

#qsorts the object by time and type, in place
sub sort {
  my $self = shift;
  if (scalar @$self > 50) {
    #at this level it pays to do a pass through to see if we're already sorted
    my $okay = 1;
    for(my $i = 0; $i < $#$self; $i++) {
      if ($self->[$i + 1]->lessThan($self->[$i])) {
	$okay = 0;
	last;
      }
    }
    if ($okay) {
      #already sorted!
      return 1;
    }
  }
  for (my $i = 0; $i < $#$self; $i++) {
    for (my $j = $i + 1; $j < scalar @$self; $j++) {
      if ($self->[$j]->lessThan($self->[$i])) {
	($self->[$i],$self->[$j]) = ($self->[$j],$self->[$i]);
      }
    }
  }
}

sub clone {
  my $self = shift;
  return bless [map {$_->clone()} @$self], ref($self);
}

sub subList {
  my $self = shift;
  my $from = shift;
  my $to   = shift;
  if (!$to) {
    $to = $self->reach;
  }
  my $s = ref($self)->new([AutoHarp::Event->zeroEvent($from)]);
  if ($from < $to) {
    foreach my $e (@$self) {
      next if ($e->time < $from);
      next if ($e->isMarker());
      last if ($e->time >= $to);
      $s->add($e->clone);
    }
  }
  return $s;
}

sub truncate {
  my $self     = shift;
  my $duration = shift;
  my $noBreak  = shift;
  return $self->truncateToTime($self->time() + $duration, $noBreak);
}

sub truncateToTime {
  my $self     = shift;
  my $newReach = shift;
  my $noBreak  = shift;
  for (my $i = 0; $i < scalar @$self; $i++) {
    #DON'T CROSS THE STREAMS
    next if ($self->[$i]->isZeroEvent());
    if ($self->[$i]->time > $newReach) {
      #remove all later than this. 
      splice(@$self,$i);
      last;
    } elsif ($self->[$i]->reach > $newReach) {
      my $newDur = $self->[$i]->duration - ($self->[$i]->reach - $newReach);
      if ($noBreak || $newDur <= 0) {
	splice(@$self,$i,1);
	$i--;
      } else {
	$self->[$i]->duration($newDur);
      }
    }
  }
}

#remove all events from the given interval and shift up the rest of the events
sub splice {
  my $self = shift;
  my $from = shift;
  my $to = shift;
  if ($to < $from) {
    confess "Invalid params to event list splice: $from to $to";
  }
  for (my $i = 0; $i < scalar @$self; $i++) {
    next if ($self->[$i]->isZeroEvent());
    if ($self->[$i]->time >= $from) {
      if ($self->[$i]->time < $to) {
	splice(@$self,$i,1);
	$i--;
      } else {
	my $t = $self->[$i]->time;
	$self->[$i]->time($t - ($to - $from));
      }
    }
  }
  return 1;
}

#double up this series of events
sub repeat {
  my $self  = shift;
  my $rDur  = shift || $self->duration();
  my $rT    = $rDur + $self->time;
  my $repeat = [];
  my $end = scalar @$self;
  for (my $i = 0; $i < $end; $i++) {
    my $new = $self->[$i]->clone();
    last if ($new->time >= $rT);
    my $nT  = $self->[$i]->time + $rDur;
    $new->time($nT);
    $self->add($new);
  }
}

#remove from the back
sub pop {
  my $self = shift;
  return pop(@$self);
}

sub time {
  my $self = shift;
  my $arg  = shift;
  my $zeroEvent = $self->findZeroEvent();
  if ($zeroEvent) {
    if (length($arg) && $arg != $zeroEvent->time) {
      my $delta = $arg - $zeroEvent->time;
      foreach (@$self) {
	my $t = $_->time;
	$_->time($t + $delta);
      }
    }
    return $zeroEvent->time;
  }
  confess ref($self) . " didn't have a zero event! Not a valid events list";
  return;
}

#shift the zero event, leave everything else as-is
sub moveZero {
  my $self      = shift;
  my $newZero   = shift;
  $self->findZeroEvent()->time($newZero);
  return $self->sort();
}
    
sub toZero {
  return (shift)->time(0);
}

sub hasTime {
  return length((shift)->time) ? 1 : 0;
}

sub duration {
  my $self = shift;
  my $arg    = shift;
  if (length($arg)) {
    confess "An event list's duration cannot be set directly";
  }
  return (scalar @$self) ? $self->reach - $self->[0]->time : 0;
}

sub reach {
  my $self = shift;
  my $arg    = shift;
  if (length($arg)) {
    confess "An event list's reach cannot be set directly";
  }
  if (scalar @$self) {
    my $r = $self->[0]->reach || 0;
    grep {$_->reach > $r && ($r = $_->reach)} @$self;
    return $r;
  }
  return 0;
}

#how many measures is this track in the given clock?
sub measures {
  my $self = shift;
  my $clock = shift;
  if (!$clock) {
    confess "Need a clock to count measures of a " . ref($self);
  }
  my $trueDuration = $self->reach() - $self->time();
  my $m = int($trueDuration / $clock->measureTime());
  if ($trueDuration % $clock->measureTime()) {
    $m++;
  }
  return $m;
}

sub track {
  my $self    = shift;
  my $args    = shift;
  my $obj     = $self->clone();
  if (ref($args)) {
    $obj->channel($args->{$ATTR_CHANNEL});
  }
  return MIDI::Track->new({ 'events' => $obj->export() });
}

#return me as an array of my events, sans my markers
#with which you may not fuck
sub events {
  my $self = shift;
  return [grep {!$_->isMarker} @$self];
}

sub add {
  my $self = shift;
  my $what = _toEventList(shift);
  if (!$what) {
    #I CANNOT ADD YOU! BEGGONE!
    return;
  }
  #otherwise...walk through my array and see where I should add things
  my $selfIdx  = 0;
  my $addeeIdx = 0;
  my $channel  = $self->channel();
  my $were = $self->reach();
  while ($addeeIdx < scalar @$what && $selfIdx < @$self) {
    while ($addeeIdx < scalar @$what &&
	   $what->[$addeeIdx]->lessThan($self->[$selfIdx])) {
      if ($self->eventCanBeAdded($what->[$addeeIdx])) {
	my $c = $what->[$addeeIdx]->clone();
	$c->channel($channel);
	splice(@$self,$selfIdx,0,$c);
      }
      $addeeIdx++;
    }
    $selfIdx++;
  }
  #get any that occur after $self's time has ended
  if ($addeeIdx < scalar @$what) {
    foreach my $c (map {$_->clone()} 
		   grep {$self->eventCanBeAdded($_)} 
		   @{$what}[$addeeIdx..$#$what]) {
      $c->channel($channel);
      push(@$self,$c);
    }
  }
  return 1;
}

#can this event be added to our list
#(exists to be overridden by child classes)
sub eventCanBeAdded {
  my $self  = shift;
  my $event = shift;
  #don't add any markers, We have them already
  return !($event->isMarker);
}

sub find {
  my $self      = shift;
  my $e         = shift;
  my $matchTime = shift;
  if (ref($e)) {
    return (grep {$_->equals($e) &&
		    (!$matchTime || $_->time == $e->time)
		  } @$self)[0];
  }
  return;
}

sub findByType {
  my $self = shift;
  my $type = shift;
  if ($type) {
    return (grep {$_->type eq $type} @$self)[0];
  }
  return;
}

sub findZeroEvent {
  my $self = shift;
  return (grep {$_->isZeroEvent} @$self)[0];
}

sub findAll {
  my $self = shift;
  my $e = shift;
  my $all = [];
  if (ref($e)) {
    for (my $i = 0; $i < scalar @$self; $i++) {
      push(@$all, $self->[$i]) if ($self->[$i]->equals($e));
    }
  }
  return $all;
}

sub findAtTime {
  return $_[0]->find($_[1],1);
}
  
sub remove {
  my $self      = shift;
  my $e         = shift;
  my $matchTime = shift;
  if (ref($e)) {
    for (my $i = 0; $i < scalar @$self; $i++) {
      if ($self->[$i]->equals($e) &&
	  (!$matchTime || $self->[$i]->time == $e->time)) {
	splice(@$self,$i,1);
	$i--;
      }
    }
  }
}

sub removeAtTime {
  return $_[0]->remove($_[1],1);
}

sub removeType {
  my $self = shift;
  my $type = shift;
  my $time = shift;
  my $rbt  = length($time);
  if ($type) {
    for (my $i = 0; $i < scalar @$self; $i++) {
      if ($self->[$i]->type eq $type && (!$rbt || $time == $self->[$i]->time)) {
	splice(@$self,$i,1);
	$i--;
      }
    }
  }
}

#even up borders of this event list
sub quantize {
  confess "NEVER CALL THIS. IT DOESN'T WORK";
  my $self  = shift;
  my $quant = shift || $NOTE_MINIMUM_TICKS;
  if ($quant) {
    foreach my $n (@$self) {
      my $t    = $n->time();
      my $mod  = $t % $quant;
      my $diff = $quant - $mod;
      #skip if we're already square on
      next if (!$mod || !$diff);
      #if the overshoot (the mod) is greater than the distance to the next quantity...
      if ($mod > $diff) {
	#move the note up to the next beat
	$t += $diff;
      } else {
	#otherwise, slide it back to the previous one
	$t -= $mod;
      }
      $n->time($t);
    }
  }
}

#returns the list as MIDI events without marker events
sub export {
  my $self = shift;
  my $ret = [];
  my $minT;
  foreach my $e (@$self) {
    next if ($e->isMarker());
    $minT = $e->time if ($e->time < $minT || !length($minT));
    if ($e->isNotes()) {
      foreach my $n (@{$e->toNotes()}) {
	push(@$ret,[@$n]);
      }
    } else {
      push(@$ret, [@$e]);
    }
  }
  if ($minT < 0) {
    $self->dump;
    confess "Encountered negative time values while translating score to events!";
  }
  return MIDI::Score::score_r_to_events_r($ret);
}

sub channel {
  my $self = shift;
  my $arg = shift;
  if (length($arg)) {
    grep {$_->channel($arg)} @$self;
    return $arg;
  }
  my @c = grep {$_->isMusic()} @$self;
  return (scalar @c) ? $c[0]->channel() : 0;
}

sub isPercussion {
  return ($_[0]->channel() eq $PERCUSSION_CHANNEL);
}

#generate a relatively idempotent id for this event list
#that stays constant as long as the events stay constant
sub id {
  my $self = shift;
  my $id   = 0;
  grep {$id ^= (length($_->type) + $_->time + length($_->value))} @$self;
  return "EVENTS_$id";
}

sub append {
  my $self = shift;
  my $thing = shift;
  if (ref($thing) && $thing->can('time')) {
    $thing = $thing->clone;
    $thing->time($self->reach);
    return $self->add($thing);
  } else {
    $thing = _toEventList($thing);
    if (!$thing) {
      return;
    }
    foreach my $t (@$thing) {
      $t = $t->clone();
      $t->time($self->reach());
      $self->add($t);
    }
  }
}

sub dump {
  my $self = shift;
  foreach my $n (@$self) {
    $n->dump;
  }
}

#write this as a loop to the database
sub transcribe {
  my $self  = shift;
  my $guide = shift;
  if (!$guide) {
    confess "Transcribing to DB requires a guide along with the events";
  }
  my $cGuide = $guide->clone();
  #whack off any intro (notes before the 0 of this track)
  #Later we might decide to save them. TODO: That?
  my $bars   = $self->measures($guide->clock);
  my $cTrack = $self->subList($self->time,$self->reach());
  my $clorge = $cTrack->clone();
  $cGuide->time(0);
  $cTrack->time(0);
  my $clodge = $cTrack->clone();
  my $op   = MIDI::Opus->new({format => 1,
			      ticks => $TICKS_PER_BEAT,
			      tracks => [$cGuide->track, $cTrack->track]
			     });
  my $loop = AutoHarp::Model::Loop->fromOpus($op);
  if ($loop->events()->measures($guide->clock) != $bars) {
    print "WAS\n";
    $self->dump();
    print "\nGOT\n";
    $loop->events()->dump();
    print "\nALSO\n";
    $clorge->dump();
    print "\nAND THEN\n";
    $clodge->dump();
    
    confess sprintf "Writing a %d measure events resulted in a %d measure loop",
      $bars,
	$loop->events()->measures($guide->clock);
  }
  if ($self->isPercussion()) {
    $loop->type($DRUM_LOOP);
  }
  #make sure we don't already have this in the database
  my $exists = AutoHarp::Model::Loop->loadBy({midi => $loop->midi,
					      type => $loop->type});
  if ($exists->isEmpty()) {
    $loop->save();
    return $loop;
  } 
  return $exists;
}

sub _toEventList {
  my $what = shift;
  if (!ref($what)) {
    return;
  }
  if (ref($what) eq 'ARRAY') {
    if (!ref($what->[0])) {
      return (ref($what) eq 'ARRAY') ? [AutoHarp::Event->new($what)] : [$what];
    } else {
      return AutoHarp::Events->new($what);
    }
  } elsif ($what->isa('AutoHarp::Event')) {
    #as above
    return [$what];
  } elsif ($what->isa('AutoHarp::Events')) {
    return $what;
  }
  #dunno what this was. Can't add it
  return;
}

"Some people just want to fill the world with silly love songs."
