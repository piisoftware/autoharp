package AutoHarp::Composer::CompositionElement;

use base qw(AutoHarp::Class);
use AutoHarp::Composer::PerformanceSegment;
use AutoHarp::Constants;
use Carp;

#absent other information, split composition elements into 4 bar chunks.
#assuming, obviously, that we can
my $DEFAULT_BAR_SPLIT = 4;
my $TRANS_IN          = 'transitionIn';
my $TRANS_OUT         = 'transitionOut';
my $ELEMENT_INDEX     = 'elementIndex';
my $NEXT_ELT          = 'nextElt';

sub new {
  my $class         = shift;
  my $musicTag      = shift;
  my $elt           = shift;
  my $transitionOut = shift;
  return bless {$ATTR_TAG => $musicTag, $SONG_ELEMENT => $elt, $TRANS_OUT => $transitionOut}, $class;
}

sub isSongBeginning {
  return $_[0]->scalarAccessor('beginning',$_[1]);
}

sub time {
  my $self = shift;
  my $time = shift;
  if ($time != undef) {
    $self->{$ATTR_TIME} = $time;
    if ($self->hasMusicBox()) {
      $self->musicBox->time($time);
    }
    if ($self->hasHook()) {
      $self->hook->time($time);
    }
  }
  return $self->{$ATTR_TIME} || 0;
}

sub reach {
  my $self = shift;
  return $self->time + $self->duration();
}

sub duration {
  my $self = shift;
  return ($self->hasMusicBox()) ? $self->musicBox()->duration : 0;
}

sub durationInSeconds {
  my $self       = shift;
  return ($self->hasMusicBox()) ? $self->musicBox->durationInSeconds() : 0;
}

sub musicTag {
  my $self = shift;
  my $tag  = shift;
  if ($tag) {
    if ($self->hasMusicBox) {
      $self->musicBox($tag);
    }
    $self->{$ATTR_TAG} = $tag;
  }
  return $self->{$ATTR_TAG};
}

sub songElement {
  return $_[0]->scalarAccessor($SONG_ELEMENT, $_[1], 'songElement');
}

sub isRepeat {
  return $_[0]->scalarAccessor($IS_REPEAT, $_[1], 'isRepeat');
}

sub elementIndex {
  return $_[0]->scalarAccessor($ELEMENT_INDEX, $_[1], 'elementIndex');
}

sub measures {
  my $self = shift;
  return ($self->hasMusicBox) ? $self->musicBox->measures() : 0;
}

sub bars {
  return $_[0]->measures();
}

sub genre {
  my $self = shift;
  return ($self->hasMusicBox) ? $self->musicBox->genre : undef;
}

sub nextSongElement {
  my $self = shift;
  my $elt   = shift;
  if ($elt) {
    $self->{$NEXT_ELT} = $elt;
  }
  return $self->{$NEXT_ELT};
}

sub transitionIn {
  my $self = shift;
  my $tr   = shift;
  if ($tr) {
    $self->{$TRANS_IN} = $tr;
  }
  return $self->{$TRANS_IN} || $ATTR_STRAIGHT_TRANSITION;
}

sub transitionOut {
  my $self = shift;
  my $tr   = shift;
  if ($tr) {
    $self->{$TRANS_OUT} = $tr;
  }
  return $self->{$TRANS_OUT} || $ATTR_STRAIGHT_TRANSITION;
}

sub transition {
  return $_[0]->transitionOut($_[1]);
}

sub musicBox {
  my $self     = shift;
  my $musicBox = shift;
  if (ref($musicBox)) {
    if ($musicBox->tag() && $self->musicTag() ne $musicBox->tag()) {
      confess sprintf("Set unmatched music for Composition Element: %s versus %s",
		      $self->musicTag(),$musicBox->tag());
    }
    $self->{$ATTR_MUSIC} = $musicBox->clone;
    $self->{$ATTR_MUSIC}->time($self->time);
    $self->{$ATTR_MUSIC}->tag($self->musicTag());
  }
  return $self->{$ATTR_MUSIC};
}

sub hasMusicBox {
  return ref($_[0]->{$ATTR_MUSIC});
}

sub clearHook {
  my $self = shift;
  delete $self->{$ATTR_HOOK};
}

sub hook {
  my $self = shift;
  my $hook = shift;
  if (ref($hook)) {
    $self->{$ATTR_HOOK} = $hook->clone();
    $self->{$ATTR_HOOK}->time($self->time);
  }
  return $self->{$ATTR_HOOK};
}

sub hasHook {
  return (ref($_[0]->{$ATTR_HOOK}));
}

sub performanceSegments {
  my $self = shift;
  my $args = shift || {};
  my $segIdx        = 0;
  my $splitIntoBars = $args->{$ATTR_BARS}  || $DEFAULT_BAR_SPLIT;
  my $box           = $args->{$ATTR_MUSIC} || $self->musicBox();
  my $hook          = $args->{$ATTR_HOOK}  || $self->hook();
  
  if (!$box) {
    confess "No music box to build segments. Cannot continue";
  }

  my $boxClone  = $box->clone;
  my $hookClone = ($hook) ? $hook->clone : undef;
  my $time     = $self->time;
  my $isRepeat = 0;

  my $pSegs = [];
  while($boxClone->duration() > 0) {
    my $segmentBars = ($boxClone->bars() % $splitIntoBars) ? $boxClone->bars() : $splitIntoBars;
    my $segmentMusic = $boxClone->getMusicForMeasures(1,$segmentBars);
    $boxClone = $boxClone->subMusic($segmentMusic->reach(), $boxClone->reach());
    
    my $nextSegment = AutoHarp::Composer::PerformanceSegment->fromParent($self);
    $nextSegment->time($time);
    $nextSegment->musicBox($segmentMusic);
    $nextSegment->isRepeat($self->isRepeat());
    $nextSegment->elementIndex($self->elementIndex());
    $nextSegment->segmentIndex($segIdx++);
    $nextSegment->songElement($self->songElement());
    $nextSegment->nextSongElement($self->songElement());
    $nextSegment->transitionIn($ATTR_STRAIGHT_TRANSITION);
    $nextSegment->transitionOut($ATTR_STRAIGHT_TRANSITION);

    if ($hookClone) {
      $nextSegment->hook($hookClone);
      
      #clip off the hook if it's longer than a single performance segment
      if ($hookClone->duration() > $segmentMusic->duration()) {
	$hookClone = $hookClone->subMusic($hookClone->time + $segmentMusic->duration());
      } else {
	#otherwise, start it again
	$hookClone = $hook->clone;
      }
    }

    push(@$pSegs,$nextSegment);
    $time = $nextSegment->reach;
  }
  $pSegs->[0]->transitionIn($self->transitionIn);
  $pSegs->[0]->isSongBeginning($self->isSongBeginning);
  $pSegs->[-1]->transitionOut($self->transitionOut);
  return $pSegs;
}

sub segmentCount {
  return scalar @{$self->songSegments};
}

sub hasFirstHalfPerformers {
  return ($_[0]->{fhp} && scalar @{$_[0]->{fhp}});
}

sub hasSecondHalfPerformers {
  return ($_[0]->{shp} && scalar @{$_[0]->{shp}});
}

sub firstHalfPerformers {
  return $_[0]->scalarAccessor('fhp',$_[1]);
}

sub secondHalfPerformers {
  return $_[0]->scalarAccessor('shp',$_[1]);
}

sub firstHalfUID {
  return $_[0]->scalarAccessor('fuid',$_[1]);
}

sub secondHalfUID {
  return $_[0]->scalarAccessor('suid',$_[1]);
}

"That stoner should know better...";

