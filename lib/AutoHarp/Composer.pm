package AutoHarp::Composer;

use strict;
use AutoHarp::Composer::CompositionElement;
use AutoHarp::MusicBox::Base;
use AutoHarp::Generator;
use AutoHarp::Constants;
use AutoHarp::Fuzzy;
use Carp;


use base qw(AutoHarp::Class);

#Third generation of Magic Alex song arranger. 
#given some music, adds to it as necessary, and 
#puts it together in song order

my $CHORUS_MAX           = 4;
my $TARGET_SEGMENT_COUNT = 12;
my $TRUNCATE             = 'endTheFuckingSong';
my $COMPOSITION          = 'composition';
my $DEFAULT_MUSIC_TAG    = 'defaultElement';
my $C_LOG                = 'compositionLog';
my $NEXT_TAG_IDX         = 'nextTagWhatever';

sub fromDataStructure {
  my $class = shift;
  my $ds    = shift;
  my $self  = {$C_LOG => $ds->{$C_LOG}};
  my $comp  = $ds->{$COMPOSITION} || [];
  foreach my $l (@$comp) {
    my ($mTag,$se,$trans) = ($l =~ /(.+)\((.+)\), transition: (.+)/);
    if ($mTag && $se) {
      $self->{$ATTR_MUSIC}{$mTag} = 1;
      push(@{$self->{$COMPOSITION}}, AutoHarp::Composer::CompositionElement->new($mTag, $se, $trans));
    }
  }
  bless $self,$class;
  return $self;
}

sub toDataStructure {
  my $self = shift;
  return {$C_LOG => $self->{$C_LOG},
	  $COMPOSITION => [map {sprintf("%s(%s), transition: %s",
					$_->musicTag(),
					$_->songElement(),
					$_->transition())}
			   @{$self->{$COMPOSITION}}]
	 };
}

sub clearMusicTags {
  my $self = shift;
  $self->{$ATTR_MUSIC} = {};
}

sub addMusicTag {
  my $self = shift;
  my $tag  = shift;
  if (ref($tag)) {
    $tag = $tag->tag();
  }
  $self->{$ATTR_MUSIC}{$tag} = 1;
}

sub hasMusicTag {
  my $self = shift;
  my $e = shift;
  return exists $self->{$ATTR_MUSIC}{$e}
}

sub nextSongElement {
  my $self = shift;
  my $idx = $self->{$NEXT_TAG_IDX}++;
  if ($idx >= scalar @$SONG_ELEMENTS) {
    $idx = 0;
    $self->{$NEXT_TAG_IDX} = 1;
  }
  return $SONG_ELEMENTS->[$idx];
}

#number of times in the song so far we've done a particular part
#e.g. verse/chorus/bridge  
sub songElementCount {
  my $self    = shift;
  my $element = shift;
  my $count   = 0;
  my $in;
  foreach my $e (map {$_->songElement} @{$self->composition}) {
    $count++ if ($e eq $element && $in ne $e);
    $in = $e;
  }
  return $count;
}

sub sectionCount {
  my $self = shift;
  return ($self->{$COMPOSITION}) ? scalar @{$self->{$COMPOSITION}} : 0;
}

sub compose {
  my $self = shift;
  if (!$self->hasMusic()) {
    confess "Attempted to compose without first setting any music";
  }
  
  $self->{$COMPOSITION} = [];
  $self->{$C_LOG}       = [];
  my $prev;
  while(1) {
    my $next        = $self->decideNextSongElement($prev);
    my $nextElement = ($next) ? $next->songElement() : $SONG_ELEMENT_END;
    if ($prev) {
      $prev->transition($self->decideTransition($prev->songElement(),
						$nextElement));
    }
    if ($next) {
      $self->addToComposition($next);
      $prev = $next;
    } else {
      last;
    }
  }
  return 1;
}

sub composition {
  my $self = shift;
  $self->{$COMPOSITION} ||= [];
  return [@{$self->{$COMPOSITION}}];
}

#fetch performance segments for this composition
sub performanceSegments {
  my $self = shift;
  my $args = shift;
  my $counts = {};
  my $time = $args->{$ATTR_TIME} || 0;
  
  my $prevElt;
  foreach my $compElt (@{$self->{$COMPOSITION}}) {
    my $isRepeat = 0;
    if ($prevElt) {
      $prevElt->nextSongElement($compElt->songElement());
      $compElt->transitionIn($prevElt->transitionOut);
      $isRepeat = ($compElt->songElement() eq $prevElt->songElement()); 
    } else {
      $compElt->isSongBeginning(1);
    }
    if (!$compElt->hasMusicBox()) {
      $compElt->musicBox($args->{$compElt->musicTag()});
      if (!$compElt->hasMusicBox()) {
	confess sprintf("Could not find music box for %s, cannot build performance segments",$compElt->musicTag());
      }
    }
    $counts->{$compElt->songElement}++ if (!$isRepeat);
    $compElt->elementIndex($counts->{$compElt->songElement});
    $compElt->time($time);
    $time = $compElt->reach();
    
    $prevElt = $compElt;
  }
  if ($prevElt) {
    $prevElt->nextSongElement($SONG_ELEMENT_END);
  }
  return [map {@{$_->performanceSegments($args)}} @{$self->{$COMPOSITION}}];
}

sub hasComposition {
  my $self = shift;
  return scalar @{$self->composition};
}

sub addToComposition {
  my $self = shift;
  my $elt = shift;
  my $idx = shift;
  if ($idx != undef && $idx < scalar @{$self->{$COMPOSITION}}) {
    splice(@{$self->{$COMPOSITION}},$idx,0,$elt);
    if ($idx > 0) {
      $elt->transition($self->{$COMPOSITION}->[$idx - 1]->transition);
    }
  } else {
    push(@{$self->{$COMPOSITION}}, $elt);
  }
}


sub moveElementUp {
  my $self = shift;
  my $idx = shift;
  if ($idx > 0 && $idx < scalar @{$self->{$COMPOSITION}}) {
    my $one = $self->{$COMPOSITION}[$idx];
    my $two = $self->{$COMPOSITION}[$idx - 1];
    my $ot = $one->transition();
    $one->transition($two->transition);
    $two->transition($ot);
    $self->{$COMPOSITION}[$idx] = $two;
    $self->{$COMPOSITION}[$idx - 1] = $one;
  }
}

sub moveElementDown {
  my $self = shift;
  my $idx = shift;
  if ($idx < $#{$self->{$COMPOSITION}}) {
    my $one = $self->{$COMPOSITION}[$idx];
    my $two = $self->{$COMPOSITION}[$idx + 1];
    my $ot = $one->transition();
    $one->transition($two->transition);
    $two->transition($ot);
    $self->{$COMPOSITION}[$idx] = $two;
    $self->{$COMPOSITION}[$idx + 1] = $one;
  }
}

sub removeElement {
  my $self = shift;
  my $idx = shift;
  if ($idx < scalar @{$self->{$COMPOSITION}}) {
    my $gone = splice(@{$self->{$COMPOSITION}},$idx,1);
    if ($idx > 0) {
      $self->{$COMPOSITION}[$idx - 1]->transition($gone->transtion());
    }
  }
}

sub compositionLog {
  my $self = shift;
  my $line = shift;
  $self->{$C_LOG} ||= [];
  if ($line) {
    push(@{$self->{$C_LOG}},$line);
  }
  return [@{$self->{$C_LOG}}];
}

sub decideNextSongElement {
  my $self         = shift;
  my $prevObj      = shift;
  my $prevElement  = ($prevObj) ? $prevObj->songElement() : 
    $SONG_ELEMENT_BEGIN;

  my $soFar     = $self->songElementCount($prevElement);
  my $didBridge = $self->songElementCount($SONG_ELEMENT_BRIDGE);
  my $didSolo   = $self->songElementCount($SONG_ELEMENT_SOLO);
  my $chorusCt  = $self->songElementCount($SONG_ELEMENT_CHORUS);
  my $wasChorus = ($prevElement eq $SONG_ELEMENT_CHORUS);
  my $wasRepeat    = ($prevElement && 
		      scalar @{$self->{$COMPOSITION}} > 1 &&
		      $self->{$COMPOSITION}->[-2]->songElement eq $prevElement);

  #truncate now?
  if (!$self->{$TRUNCATE} && 
      scalar @{$self->{$COMPOSITION}} > $TARGET_SEGMENT_COUNT) {
    $self->{$TRUNCATE} = asOftenAsNot;
  }

  my $nextElement;
  my $decisionStr;

 LOOKAHEADBLOCK:
  {
    if ($prevElement eq $SONG_ELEMENT_BEGIN) {
      if (almostAlways) {
	$nextElement = $SONG_ELEMENT_INTRO;
	$decisionStr = "begin to intro";
	last LOOKAHEADBLOCK;
      }
    }
    
    if ($prevElement eq $SONG_ELEMENT_PRECHORUS) {
      #well, that's an easy one
      if (unlessPigsFly) {
	$nextElement = $SONG_ELEMENT_CHORUS;
	$decisionStr = "Prechorus to chorus ";
	last LOOKAHEADBLOCK;
      }
    }
    
    if ($prevElement eq $SONG_ELEMENT_INTRO) {
      #sometimes continue the intro
      if (sometimes) {
	$nextElement = $SONG_ELEMENT_INTRO;
	$decisionStr = "Continue intro";
	last LOOKAHEADBLOCK;
      } elsif (almostAlways) {
	#otherwise almost always go to the verse
	$nextElement = $SONG_ELEMENT_VERSE;
	$decisionStr = "Go from intro to verse";
	last LOOKAHEADBLOCK;
      }
    }
      
    #from the outro we can only end or do the outro again
    if ($prevElement eq $SONG_ELEMENT_OUTRO) {
      if (($wasRepeat && almostAlways) || (!$wasRepeat && mostOfTheTime)) {
	$nextElement = $SONG_ELEMENT_END;
	$decisionStr = "outro to end";
	last LOOKAHEADBLOCK;
      }
      $decisionStr = "repeat outro";
      $nextElement = $SONG_ELEMENT_OUTRO;
      last LOOKAHEADBLOCK;
    }
	
    if ($self->{$TRUNCATE}) {
      #cut off the song. 
      if (!$wasChorus && $chorusCt < $CHORUS_MAX) {
	if ($self->hasMusicTag($SONG_ELEMENT_PRECHORUS) && 
	    ($prevElement ne $SONG_ELEMENT_PRECHORUS || rarely)) {
	  $decisionStr = "Truncation triggered, going to last chorus, starting at prechorus";
	  $nextElement = $SONG_ELEMENT_PRECHORUS;
	} else {
	  $nextElement = $SONG_ELEMENT_CHORUS;
	  $decisionStr = "Truncation triggered, going to last chorus";
	}
      } elsif ((!$wasChorus && mostOfTheTime) || ($wasChorus && sometimes)) {
	$nextElement = $SONG_ELEMENT_CHORUS;
	$decisionStr = "Truncation triggered, song staying alive by repeating last chorus";
      } elsif (rarely) {
	$nextElement = $SONG_ELEMENT_OUTRO;
	$decisionStr = "Truncation-based outro";
      } else {
	$nextElement = $SONG_ELEMENT_END;
	$decisionStr = "Truncation-based end";
      }
      last LOOKAHEADBLOCK;
    }

    #coming out of the verse
    if ($prevElement eq $SONG_ELEMENT_VERSE) {
      if ($soFar == 1) {
	#as often as not, repeat the first verse
	if (!$wasRepeat && asOftenAsNot) {
	  $nextElement = $SONG_ELEMENT_VERSE;
	  $decisionStr = "second verse immediately after first";
	  last LOOKAHEADBLOCK;
	}
      } 
      if ($soFar > 1 && !$didBridge && rarely) {
	#possibly go to the bridge here
	$nextElement = $SONG_ELEMENT_BRIDGE;
	$decisionStr = "Bridge after second verse";
	last LOOKAHEADBLOCK;
      } 
      if (almostAlways) {
	#otherwise, almost always go into the prechorus or chorus
	if ($self->hasMusicTag($SONG_ELEMENT_PRECHORUS)) {
	  $decisionStr = "Prechorus after verse";
	  $nextElement = $SONG_ELEMENT_PRECHORUS;
	} else {
	  $decisionStr = "Chorus after verse";
	  $nextElement = $SONG_ELEMENT_CHORUS;
	}
	last LOOKAHEADBLOCK;
      }
    }
    
    #coming out of the chorus
    if ($wasChorus) {
      #last chorus
      if ($soFar >= $CHORUS_MAX) {
	if (!$wasRepeat && mostOfTheTime) {
	  #repeat the last chorus
	  $nextElement = $SONG_ELEMENT_CHORUS;
	  $decisionStr = "Repeat last chorus";
	  last LOOKAHEADBLOCK;
	} 
	if (mostOfTheTime) {
	  $nextElement = $SONG_ELEMENT_END;
	  $decisionStr = "End song after last chorus";
	} else {
	  $decisionStr = "Outro after last chorus";
	  $nextElement = $SONG_ELEMENT_OUTRO;
	}
	last LOOKAHEADBLOCK;
      }
      
      #first chorus
      if ($soFar == 1) {
	if (mostOfTheTime) {
	  $nextElement = $SONG_ELEMENT_INSTRUMENTAL;
	  $decisionStr = "Instrumental after first chorus";
	  last LOOKAHEADBLOCK;
	} 
      } else {
	#not the first chorus
	if (!$didBridge && asOftenAsNot) {
	  $nextElement = $SONG_ELEMENT_BRIDGE;
	  $decisionStr = "Bridge after chorus $soFar";
	  last LOOKAHEADBLOCK;
	} 
	if ((!$didSolo && mostOfTheTime) || ($didSolo && almostNever)) {
	  $nextElement = $SONG_ELEMENT_SOLO;
	  $decisionStr = "Solo after chorus $soFar";
	  last LOOKAHEADBLOCK;
	}
      }
    } #coming out of a chorus
    
    #coming out of the solo
    if ($prevElement eq $SONG_ELEMENT_SOLO) {
      if ((!$wasRepeat && asOftenAsNot) || ($wasRepeat && rarely)) {
	#more soloing! 
	$nextElement = $SONG_ELEMENT_SOLO;
	$decisionStr = "Repeat Solo";
	last LOOKAHEADBLOCK;
      } 
      if (sometimes) {
	#go straight into the chorus
	$nextElement = $SONG_ELEMENT_CHORUS;
	$decisionStr = "Chorus after solo";
	last LOOKAHEADBLOCK;
      }
    }
      
    #otherwise...
    if (!$didBridge && rarely) {
      $nextElement = $SONG_ELEMENT_BRIDGE;
      $decisionStr = "Fallback: Bridge";
      last LOOKAHEADBLOCK;
    } elsif (!$didSolo && rarely) {
      $nextElement = $SONG_ELEMENT_SOLO;
      $decisionStr = "Fallback: Solo";
      last LOOKAHEADBLOCK;
    } elsif ($prevElement ne $SONG_ELEMENT_VERSE && almostAlways) {
      $decisionStr = "Fallback: Verse";
      $nextElement = $SONG_ELEMENT_VERSE;
      last LOOKAHEADBLOCK;
    } elsif (!$wasChorus && almostAlways) {
      $nextElement = $SONG_ELEMENT_CHORUS;
      $decisionStr = "Fallback: Chorus";
      last LOOKAHEADBLOCK;
    }
    $decisionStr = "NO DECISION MADE";
  }			
  #END LOOKAHEAD BLOCK
  $self->compositionLog(sprintf("TO %-12s BASIS: %s",
				$nextElement,
				$decisionStr));
  
  if (!$nextElement || $nextElement eq $SONG_ELEMENT_END) {
    #thy song has ended
    delete $self->{$TRUNCATE};
    return;
  }
  my $eltIdx = ($nextElement eq $prevElement) ? $soFar : $soFar + 1;
  my $mTag = ($self->{$ATTR_MUSIC}{$nextElement}) ? $nextElement : $self->defaultMusicTag();

  return AutoHarp::Composer::CompositionElement->new($mTag, $nextElement);
}


sub hasMusic {
  my $self = shift;
  return (exists $self->{$ATTR_MUSIC} && scalar keys %{$self->{$ATTR_MUSIC}});
}

sub defaultMusicTag() {
  my $self = shift;
  if (!$self->{$DEFAULT_MUSIC_TAG}) {
    if ($self->hasMusic) {
      my $lastDitch;
      foreach my $elt (@$SONG_ELEMENTS) {
	if ($self->{$ATTR_MUSIC}{$elt}) {
	  #take the first one we get. 
	  #Occassionally, we might change our mind
	  $lastDitch = $self->{$DEFAULT_MUSIC_TAG} = $elt;
	  last if (mostOfTheTime);
	}
      }
      $self->{$DEFAULT_MUSIC_TAG} ||= $lastDitch;
    } else {
      confess "You haven't set any music yet";
    } 
  }    
  return $self->{$DEFAULT_MUSIC_TAG};
}

sub decideTransition {
  my $self        = shift;
  my $from        = shift;
  my $to          = shift;
  
  my $up   = $ATTR_UP_TRANSITION;
  my $down = $ATTR_DOWN_TRANSITION;

  #calculate transition weight
  if ($from eq $to) {
    if ($to eq $SONG_ELEMENT_CHORUS && almostAlways) {
      return $up;
    } 
  } elsif ($to eq $SONG_ELEMENT_OUTRO) {
    return $up if (mostOfTheTime);
  } elsif ($to eq $SONG_ELEMENT_END) {
    if (asOftenAsNot) {
      return $up;
    }
  } elsif ($to eq $SONG_ELEMENT_CHORUS) {
    return $up if (asOftenAsNot);
  } elsif ($from ne $to && 
	   ($from eq $SONG_ELEMENT_CHORUS || 
	    $from eq $SONG_ELEMENT_INTRO ||
	    $from eq $SONG_ELEMENT_SOLO)
	  )  {
    return $down if (mostOfTheTime);
  }
  return $ATTR_STRAIGHT_TRANSITION;
}

"I'm definitely shaking";

