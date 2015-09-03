package AutoHarp::GrooveTemplate;

use AutoHarp::Constants;
use Carp;

use base qw(AutoHarp::Class);

use strict;

my $EVENTS = 'events';
my $GUIDE  = 'guide';
my $OFFSET = 'offset';
my $REL_VEL = 'relativeVelocity';
#how much of a beat we'll still consider groove
#(e.g. 8 => 32nd note in 4/4. This may or may not be right)
#TODO: be smarter about this?
my $MAX_SWING_DIVISOR = 8;

sub fromGuideAndEvents {
  my $class  = shift;
  my $guide  = shift;
  my $events = shift;

  my $eClone   = $events->clone();
  my $gClone   = $guide->clone();
  $eClone->time(0);
  $gClone->time(0);

  return bless {$EVENTS => $eClone, 
		$GUIDE => $gClone}, $class;
}

sub fromLoop {
  my $class = shift;
  my $loop  = shift;
  return $class->fromGuideAndEvents(@{$loop->eventSet()});
}

sub getGrooveSet {
  my $self       = shift;
  my $applicant  = shift;
  
  my $clone      = $self->{$EVENTS}->clone();
  my $guideClone = $self->{$GUIDE}->clone();

  #build a groove guide from a very fine grid (trying 64th notes)
  #the groove might not be built on this
  #(e.g. it might have triplets or something),
  #but that shouldn't matter.

  $clone->time($applicant->time);
  $guideClone->time($applicant->time);
  while ($clone->reach() < $applicant->reach()) {
    $clone->repeat($guideClone->duration());
    $guideClone->repeat();
  }
  if ($clone->reach() > $applicant->reach()) {
    $guideClone->setEnd($applicant->reach());
    $clone->truncateToTime($guideClone->reach());
  }

  #build a groove set out of this new clone
  my $gSet = GrooveSet->new($clone, $guideClone);
  if ($applicant->time % $gSet->resolution()) {
    confess sprintf("Trying to apply a groove to events that start at %d. Resolution is %d, so that won't work",$applicant->time,$gSet->resolution);
  }
  $gSet->buildGrid();
  return $gSet;
}

sub applyGroove {
  my $self       = shift;
  my $applyTo    = shift;

  my $atMaxVel;
  grep {$atMaxVel < $_ && ($atMaxVel = $_)}
    map {$_->velocity()} 
    @{$applyTo->notes()}; 
  my $groove     = $self->getGrooveSet($applyTo);
  foreach my $ev (@{$applyTo->notes()}) {
    #find the grid marker for this event,
    #and use it to set time and velocity (assuming we have opinions on the matter)
    my $gm = $groove->gridMarker($ev->time);
    my $wt = $ev->time();
    my $wv = $ev->velocity();
    $ev->time($gm->time);
    if ($gm->velocity()) {
      $ev->velocity(int(($gm->velocity() / $groove->maxVelocity()) * $atMaxVel));
    }
    printf "GROOVE: %4d => %4d, velocity: %3d => %3d\n",$wt,$ev->time,$wv,$ev->velocity();
  }
  #and we're done. In the end, surprisingly easy
  return 1;
}

"'I might be old but I'm someone new,' she said";

package GrooveMarker;

use AutoHarp::Constants;
use Carp;

use base qw(AutoHarp::Class);

my $RES = 'resolution';

sub new {
  my $class    = shift;
  my $time     = shift;
  my $vel      = shift;
  my $res      = shift;
  return bless {$ATTR_TIME => $time,
		$ATTR_VELOCITY => $vel,
		$RES => $res
	       }, $class;
}

sub time {
  return $_[0]->scalarAccessor($ATTR_TIME,$_[1]);
}

sub resolution {
  return $_[0]->scalarAccessor($RES, $_[1]);
}

sub isSittingBack {
  return $_[0]->scalarAccessor('isSittingBack', $_[1]);
}

sub gridTime {
  return $_[0]->time() + $_[0]->offset();
}

sub offset {
  my $self = shift;
  my $sb   = $self->sitBackOffset();
  my $p    = $self->pushOffset();
  if ($p < $sb) {
    return $p;
  }
  return $sb * -1;
  # if ($self->isSittingBack()) {
  #   return -1 * $self->sitBackOffset();
  # }
  # return $self->pushOffset();
}

sub pushOffset {
  my $self = shift;
  my $mod  = $self->sitBackOffset;
  return ($mod) ? $self->resolution - $mod : 0;
}

sub sitBackOffset {
  my $self = shift;
  if (!$self->resolution) {
    confess "You ain't set the resolution yet";
  }
  return $self->time % $self->resolution;
}

sub velocity {
  return $_[0]->scalarAccessor($ATTR_VELOCITY, $_[1]);  
}

"Keeping her safe until her return";

package GrooveSet;

use Carp;
use AutoHarp::Constants;
use base qw(AutoHarp::Class);

my $SET = 'set';
my $VELOCITY_SET = 'vSet';
my $OFFSET_SET = 'oSet';

my $GRID = 'grid';
my $DEFAULT_RESOLUTION = $NOTE_MINIMUM_TICKS / 4;
my $MAX_VEL = 'maxVelocity';

sub new {
  my $class  = shift;
  my $events = shift;
  my $guide  = shift;
  my $self   = {
		$SET => [],
		$ATTR_GUIDE => $guide
	       };
  if ($events) {
    foreach my $n (@{$events->notes()}) {
      push(@{$self->{$SET}}, GrooveMarker->new($n->time, $n->velocity));
    }
  }
  return bless $self,$class;
}

sub guide {
  return $_[0]->objectAccessor($ATTR_GUIDE, $_[1]);
}

sub add {
  my $self = shift;
  my $gm = shift;
  push(@{$self->{$SET}}, $gm);
}

sub maxVelocity {
  return $_[0]->scalarAccessor($MAX_VEL, $_[1]);
}

sub resolution {
  return $_[0]->scalarAccessor('resolution', $_[1], $DEFAULT_RESOLUTION);
}

sub gridMarker {
  my $self = shift;
  my $time = shift;
  if (!exists $self->{$GRID}) {
    confess "YOU DIDN'T CALCULATE THE FREAKING GRID BEFORE YOU ASKED FOR IT";
  }
  #find the nearest grid time to this time and return that marker
  my $behind = $time % $self->resolution();
  my $ahead  = $self->resolution() - $behind;
  my $gTime  = ($behind > $ahead) ? $time + $ahead : $time - $behind;

  if (exists $self->{$GRID}{$gTime}) {
    return $self->{$GRID}{$gTime};
  }
  #none exists--manufacuture one
  if ($gTime % $self->resolution()) {
    confess sprintf("For time %d you asked for a marker at %d. Why would you do this?",$time,$gTime);
  }

  return $self->extrapolateGridMarker($gTime);
}

sub isSittingBack {
  return $_[0]->scalarAccessor('sb',$_[1]);
}

sub buildGrid {
  my $self  = shift;
  my $guide = $self->guide();
  my $res   = $self->resolution();
  
  my $beforeOffsets;
  my $afterOffsets;
  my $beforeCt;
  my $maxVel;
  
  foreach my $marker (@{$self->{$SET}}) {
    $marker->resolution($res);
    push(@$beforeOffsets, $marker->pushOffset());
    push(@$afterOffsets, $marker->sitBackOffset());
    if ($marker->pushOffset() > $marker->sitBackOffset()) {
      $beforeCt++;
    }
    $maxVel = $marker->velocity() if ($maxVel < $marker->velocity());
  }
  $self->maxVelocity($maxVel);
  
  my ($bMean, $bStdDev) = __meanAndStdDev($beforeOffsets);
  my ($aMean, $aStdDev) = __meanAndStdDev($afterOffsets);
  my $mean;
  my $isSittingBack;
  if ($bMean < $aMean &&
      $bStdDev <= $aStdDev) {
    $isSittingBack = 0;
    $mean = $bMean;
  } elsif ($aMean < $bMean &&
	   $aStdDev <= $bStdDev) {
    $mean = $aMean;
    $isSittingBack = 1;
  } else {
    #offset mean and std dev failed us. Use whichever is closer
    my $afterCt = scalar @{$self->{$SET}} - $beforeCt;
    $mean        = ($beforeCt > $afterCt) ? $bMean : $aMean;
    $isSittingBack = ($beforeCt > $afterCt) ? 0 : 1;
  }
  $self->isSittingBack($isSittingBack);

  #second pass--build the grid once our groove direction is determined,
  #get a collection of velocities and offsets to fill in our grid later
  foreach my $gm (@{$self->{$SET}}) {
    $gm->isSittingBack($isSittingBack);
    my $gt = $gm->gridTime();
    if (!(exists $self->{$GRID}{$gt}) ||
	abs($gm->offset) < abs($self->{$GRID}{$gt}->offset)) {
      $self->{$GRID}{$gt} = $gm;
      $self->{$VELOCITY_SET}{$gt} = $gm->velocity();
      $self->{$OFFSET_SET}{$gt}   = $gm->offset();
    }
  }
  return 1;
}

sub extrapolateGridMarker {
  my $self     = shift;
  my $gridTime = shift;

  my $guide    = $self->guide();
  my $offsets  = $self->{$OFFSET_SET};
  my $velos    = $self->{$VELOCITY_SET};
  my $maxVel   = $self->maxVelocity();
  
  my $foundVelocity;
  my $foundOffset;
  my $foundIt = 0;
  my $measures = $guide->eachMeasure();

  #look through other measures to find an offset and a note velocity
  my $timeInMeasure;
  grep {$gridTime >= $_ && ($timeInMeasure = $gridTime - $_)} @$measures;
  print "Looking for grid marker for $gridTime (measure time $timeInMeasure)...\n";
  foreach my $mt (@$measures) {
    my $subTime = $timeInMeasure + $mt;
    if (exists $offsets->{$subTime}) {
      $foundVelocity = $velos->{$subTime};
      $foundOffset   = $offsets->{$subTime};
      printf "\tFound velocity of %d, offset of %d for Grid Time %d in measure %d\n",
	$foundVelocity,$foundOffset,$gridTime,$mt;
      $foundIt = 1;
      last;
    }
  }
  
  if (!$foundIt) {
    #no? Try the same place in other beats
    foreach my $mt (@$measures) {
      my $mClock  = $guide->clockAt($mt);
      my $beatMod = $timeInMeasure % $mClock->beatTime();
      for(my $b = $beatMod;
	  $b < $mClock->measureTime();
	  $b += $mClock->beatTime()) {
	my $bTime = $mt + $b;
	if (exists $offsets->{$bTime}) {
	  $foundOffset   = $offsets->{$bTime};
	  $foundVelocity = $velos->{$bTime};
	  printf "Found velocity of %d, offset of %d for Grid Time %d in beat %d of measure %d (time %d)\n",$foundVelocity,$foundOffset,$gridTime,$b,$mt,$bTime;
	  $foundIt = 1;
	  last;
	}
      }
      last if ($foundIt);
    }
  }
  #if we haven't figured out velocity by now, we have no opinion on the matter
  #we'll try one more extrapolation to figure out offset
  if (!$foundIt) {
    $foundVelocity = 0;
    
    my $fore = 0;
    my $foreTime = 0;
    my $aft  = 0;
    my $aftTime = 0;
    
    foreach my $t (sort {$a <=> $b} keys %$offsets) {
      if ($t < $gridTime) {
	$fore = $offsets->{$t};
	$foreTime = $t;
      } elsif ($t > $gridTime) {
	$aft = $offsets->{$t};
	$aftTime = $t;
	last;
      }
    }
    
    if ($foreTime != $aftTime) {
      my $distanceFore = $gridTime - $foreTime;
      my $distanceAft  = $aftTime - $foreTime;
      my $norm         = $distanceFore + $distanceAft;
      
      my $foreWeight   = 1 - ($distanceFore / $norm);
      my $aftWeight    = 1 - $foreWeight;
      $foundOffset     = int(($fore * $foreWeight) + ($aft * $aftWeight));
      printf "As a last resort, calculated offset of %d for %d by weighing offset of %d at %d and %d at %d\n",$foundOffset,$gridTime,$fore,$foreTime,$aft,$aftTime;
    } else {
      print "ALL WAYS OF CALCULATING AN OFFSET FAILED FOR $gridTime!\n";
    }
  }
  my $gm = GrooveMarker->new($gridTime + $foundOffset, $foundVelocity);
  $self->{$GRID}{$gridTime} = $gm;
  $self->{$OFFSET_SET}{$gridTime}   = $foundOffset;
  $self->{$VELOCITY_SET}{$gridTime} = $foundVelocity;
  return $gm;
}

sub __meanAndStdDev {
  my $set      = shift;
  if (!scalar @$set) {
    return (0,0);
  }
  my $mean;
  my $variance;
  grep {$mean += $_} @$set;
  $mean = int($mean / scalar @$set);
  grep {$variance += (($_ - $mean) ** 2)} @$set;
  $variance = int($variance / scalar @$set);
  my $stdDev = int(sqrt($variance));
  return ($mean,$stdDev);
}

"Feel it all around";
