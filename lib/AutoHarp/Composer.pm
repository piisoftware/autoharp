package AutoHarp::Composer;

use strict;
use AutoHarp::MusicBox::Base;
use AutoHarp::Fuzzy;
use AutoHarp::Generator;
use AutoHarp::Constants;
use Carp;

use base qw(AutoHarp::Class);

#Third generation of Magic Alex song arranger. 
#given some music, adds to it as necessary, and 
#puts it together in song order

my $CHORUS_MAX           = 4;
my $TARGET_SEGMENT_COUNT = 12;
my $TRUNCATE             = 'endTheFuckingSong';
my $COMPOSITION          = 'composition';
my $MUSIC                = 'music';
my $DEFAULT_ELT          = 'defaultElement';
my $C_LOG                = 'compositionLog';
my $NEXT_TAG_IDX         = 'nextTagWhatever';

my @SONG_ELEMENTS = (
		     $SONG_ELEMENT_VERSE,
		     $SONG_ELEMENT_CHORUS,
		     $SONG_ELEMENT_BRIDGE,
		     $SONG_ELEMENT_PRECHORUS,
		     $SONG_ELEMENT_INSTRUMENTAL,
		     $SONG_ELEMENT_SOLO,
		     $SONG_ELEMENT_INTRO,
		     $SONG_ELEMENT_OUTRO,
		    );

sub CompositionElement {
  my $args = shift;
  my $comp = CompElement->new();
  $comp->tag($args->{$ATTR_TAG});
  $comp->musicTag($args->{$ATTR_MUSIC});
  $comp->transition($args->{$SONG_ELEMENT_TRANSITION});
  return $comp;
}

sub fromDataStructure {
  my $class = shift;
  my $ds    = shift;
  my $self  = {$C_LOG => $ds->{$C_LOG}};
  my $comp  = $ds->{$COMPOSITION} || [];
  foreach my $l (@$comp) {
    my ($tag,$mTag,$trans) = ($l =~ /(.+)\((.+)\), transition: (.+)/);
    if ($tag && $mTag) {
      push(@{$self->{$MUSIC}{$tag}},$mTag);
      push(@{$self->{$COMPOSITION}}, CompElement->new($tag,$mTag,$trans));
    }
  }
  bless $self,$class;
  return $self;
}

sub toDataStructure {
  my $self = shift;
  return {$C_LOG => $self->{$C_LOG},
	  $COMPOSITION => [map {sprintf("%s(%s), transition: %s",
					$_->tag(),
					$_->musicTag(),
					$_->transition())}
			   @{$self->{$COMPOSITION}}]
	 };
}

sub addMusic {
  my $self      = shift;
  my $music     = shift;
  if (ref($music)) {
    my $tag = $music->tag();
    if (!$tag || !scalar grep {$_ eq $tag} @SONG_ELEMENTS) {
      #this music isn't tagged, or a tag we know about
      #tag it as something we recognize, 
      $tag = $self->nextTag();
    }
    push(@{$self->{$MUSIC}{$tag}},$music->tag);
  }
}

sub nextTag {
  my $self = shift;
  my $idx = $self->{$NEXT_TAG_IDX}++;
  if ($idx >= scalar @SONG_ELEMENTS) {
    $idx = 0;
    $self->{$NEXT_TAG_IDX} = 1;
  }
  return $SONG_ELEMENTS[$idx];
}

sub hasSongElement {
  my $self = shift;
  my $e = shift;
  return exists $self->{$MUSIC}{$e} && scalar @{$self->{$MUSIC}{$e}};
}

#number of times in the song so far we've done a particular part
#e.g. verse/chorus/bridge  
sub songElementCount {
  my $self    = shift;
  my $element = shift;
  my $count   = 0;
  my $in;
  foreach my $e (map {$_->tag} @{$self->composition}) {
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
  my $prevElement;
  while(1) {
    my $nextElement = $self->decideNextElement($prevElement);
    my $nextTag     = ($nextElement) ? $nextElement->tag() : $SONG_ELEMENT_END;
    if ($prevElement) {
      $prevElement->transition($self->decideTransition($prevElement->tag(),
						       $nextTag));
    }
    if ($nextElement) {
      push(@{$self->{$COMPOSITION}},$nextElement);
      $prevElement = $nextElement;
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

sub hasComposition {
  my $self = shift;
  return scalar @{$self->composition};
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

sub decideNextElement {
  my $self         = shift;
  my $prevElement  = shift;
  my $prevTag      = ($prevElement) ? $prevElement->tag() : 
    $SONG_ELEMENT_BEGIN;

  my $soFar     = $self->songElementCount($prevTag);
  my $didBridge = $self->songElementCount($SONG_ELEMENT_BRIDGE);
  my $didSolo   = $self->songElementCount($SONG_ELEMENT_SOLO);
  my $chorusCt  = $self->songElementCount($SONG_ELEMENT_CHORUS);
  my $wasChorus = ($prevTag eq $SONG_ELEMENT_CHORUS);
  my $wasRepeat    = ($prevTag && 
		      scalar @{$self->{$COMPOSITION}} > 1 &&
		      $self->{$COMPOSITION}->[-2]->tag eq $prevTag);

  #truncate now?
  if (!$self->{$TRUNCATE} && 
      scalar @{$self->{$COMPOSITION}} > $TARGET_SEGMENT_COUNT) {
    $self->{$TRUNCATE} = asOftenAsNot;
  }

  my $nextTag;
  my $decisionStr;

 LOOKAHEADBLOCK:
  {
    if ($prevTag eq $SONG_ELEMENT_BEGIN) {
      if (almostAlways) {
	$nextTag = $SONG_ELEMENT_INTRO;
	$decisionStr = "begin to intro";
	last LOOKAHEADBLOCK;
      }
    }
    
    if ($prevTag eq $SONG_ELEMENT_PRECHORUS) {
      #well, that's an easy one
      if (unlessPigsFly) {
	$nextTag = $SONG_ELEMENT_CHORUS;
	$decisionStr = "Prechorus to chorus ";
	last LOOKAHEADBLOCK;
      }
    }
    
    if ($prevTag eq $SONG_ELEMENT_INTRO) {
      #sometimes continue the intro
      if (sometimes) {
	$nextTag = $SONG_ELEMENT_INTRO;
	$decisionStr = "Continue intro";
	last LOOKAHEADBLOCK;
      } elsif (almostAlways) {
	#otherwise almost always go to the verse
	$nextTag = $SONG_ELEMENT_VERSE;
	$decisionStr = "Go from intro to verse";
	last LOOKAHEADBLOCK;
      }
    }
      
    #from the outro we can only end or do the outro again
    if ($prevTag eq $SONG_ELEMENT_OUTRO) {
      if (($wasRepeat && almostAlways) || (!$wasRepeat && mostOfTheTime)) {
	$nextTag = $SONG_ELEMENT_END;
	$decisionStr = "outro to end";
	last LOOKAHEADBLOCK;
      }
      $decisionStr = "repeat outro";
      $nextTag = $SONG_ELEMENT_OUTRO;
      last LOOKAHEADBLOCK;
    }
	
    if ($self->{$TRUNCATE}) {
      #cut off the song. 
      if (!$wasChorus && $chorusCt < $CHORUS_MAX) {
	if ($self->hasSongElement($SONG_ELEMENT_PRECHORUS) && 
	    ($prevTag ne $SONG_ELEMENT_PRECHORUS || rarely)) {
	  $decisionStr = "Truncation triggered, going to last chorus, starting at prechorus";
	  $nextTag = $SONG_ELEMENT_PRECHORUS;
	} else {
	  $nextTag = $SONG_ELEMENT_CHORUS;
	  $decisionStr = "Truncation triggered, going to last chorus";
	}
      } elsif ((!$wasChorus && mostOfTheTime) || ($wasChorus && sometimes)) {
	$nextTag = $SONG_ELEMENT_CHORUS;
	$decisionStr = "Truncation triggered, song staying alive by repeating last chorus";
      } elsif (rarely) {
	$nextTag = $SONG_ELEMENT_OUTRO;
	$decisionStr = "Truncation-based outro";
      } else {
	$nextTag = $SONG_ELEMENT_END;
	$decisionStr = "Truncation-based end";
      }
      last LOOKAHEADBLOCK;
    }

    #coming out of the verse
    if ($prevTag eq $SONG_ELEMENT_VERSE) {
      if ($soFar == 1) {
	#as often as not, repeat the first verse
	if (!$wasRepeat && asOftenAsNot) {
	  $nextTag = $SONG_ELEMENT_VERSE;
	  $decisionStr = "second verse immediately after first";
	  last LOOKAHEADBLOCK;
	}
      } 
      if ($soFar > 1 && !$didBridge && rarely) {
	#possibly go to the bridge here
	$nextTag = $SONG_ELEMENT_BRIDGE;
	$decisionStr = "Bridge after second verse";
	last LOOKAHEADBLOCK;
      } 
      if (almostAlways) {
	#otherwise, almost always go into the prechorus or chorus
	if ($self->hasSongElement($SONG_ELEMENT_PRECHORUS)) {
	  $decisionStr = "Prechorus after verse";
	  $nextTag = $SONG_ELEMENT_PRECHORUS;
	} else {
	  $decisionStr = "Chorus after verse";
	  $nextTag = $SONG_ELEMENT_CHORUS;
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
	  $nextTag = $SONG_ELEMENT_CHORUS;
	  $decisionStr = "Repeat last chorus";
	  last LOOKAHEADBLOCK;
	} 
	if (mostOfTheTime) {
	  $nextTag = $SONG_ELEMENT_END;
	  $decisionStr = "End song after last chorus";
	} else {
	  $decisionStr = "Outro after last chorus";
	  $nextTag = $SONG_ELEMENT_OUTRO;
	}
	last LOOKAHEADBLOCK;
      }
      
      #first chorus
      if ($soFar == 1) {
	if (mostOfTheTime) {
	  $nextTag = $SONG_ELEMENT_INSTRUMENTAL;
	  $decisionStr = "Instrumental after first chorus";
	  last LOOKAHEADBLOCK;
	} 
      } else {
	#not the first chorus
	if (!$didBridge && asOftenAsNot) {
	  $nextTag = $SONG_ELEMENT_BRIDGE;
	  $decisionStr = "Bridge after chorus $soFar";
	  last LOOKAHEADBLOCK;
	} 
	if ((!$didSolo && mostOfTheTime) || ($didSolo && almostNever)) {
	  $nextTag = $SONG_ELEMENT_SOLO;
	  $decisionStr = "Solo after chorus $soFar";
	  last LOOKAHEADBLOCK;
	}
      }
    } #coming out of a chorus
    
    #coming out of the solo
    if ($prevTag eq $SONG_ELEMENT_SOLO) {
      if ((!$wasRepeat && asOftenAsNot) || ($wasRepeat && rarely)) {
	#more soloing! 
	$nextTag = $SONG_ELEMENT_SOLO;
	$decisionStr = "Repeat Solo";
	last LOOKAHEADBLOCK;
      } 
      if (sometimes) {
	#go straight into the chorus
	$nextTag = $SONG_ELEMENT_CHORUS;
	$decisionStr = "Chorus after solo";
	last LOOKAHEADBLOCK;
      }
    }
      
    #otherwise...
    if (!$didBridge && rarely) {
      $nextTag = $SONG_ELEMENT_BRIDGE;
      $decisionStr = "Fallback: Bridge";
      last LOOKAHEADBLOCK;
    } elsif (!$didSolo && rarely) {
      $nextTag = $SONG_ELEMENT_SOLO;
      $decisionStr = "Fallback: Solo";
      last LOOKAHEADBLOCK;
    } elsif ($prevTag ne $SONG_ELEMENT_VERSE && almostAlways) {
      $decisionStr = "Fallback: Verse";
      $nextTag = $SONG_ELEMENT_VERSE;
      last LOOKAHEADBLOCK;
    } elsif (!$wasChorus && almostAlways) {
      $nextTag = $SONG_ELEMENT_CHORUS;
      $decisionStr = "Fallback: Chorus";
      last LOOKAHEADBLOCK;
    }
    $decisionStr = "NO DECISION MADE";
  }			
  #END LOOKAHEAD BLOCK
  $self->compositionLog(sprintf("TO %-12s BASIS: %s",
				$nextTag,
				$decisionStr));
  
  if (!$nextTag || $nextTag eq $SONG_ELEMENT_END) {
    #thy song has ended
    delete $self->{$TRUNCATE};
    return;
  }
  my $eltIdx = ($nextTag eq $prevTag) ? $soFar : $soFar + 1;
  my $m = $self->findMusic($nextTag, $eltIdx);

  return CompElement->new($nextTag,$m);
}


sub hasMusic {
  my $self = shift;
  return ($self->{$MUSIC} && scalar keys %{$self->{$MUSIC}});
}

sub findMusic {
  my $self    = shift;
  my $tag     = shift;
  my $idx     = shift;
  my $musics  = $self->{$MUSIC}{$tag} || $self->defaultMusics();

  if (!$musics || !scalar @$musics) {
    confess "No music to choose from for $tag. Cannot compose!";
  }

  if (scalar @$musics > 1 && 
      scalar @$musics <= $idx) {
    #we have multiple of whatever this is.
    #and we're asking for the nth of that, so return that instead
    return $musics->[$idx - 1];
  }
  return $musics->[0];
}

sub defaultMusics {
  my $self = shift;
  my $musics = [];
  if ($self->hasMusic) {
    if (!$self->{$DEFAULT_ELT}) {
      foreach my $elt (@SONG_ELEMENTS) {
	if ($self->{$MUSIC}{$elt}) {
	  #take the first one we get. 
	  #Occassionally, we might change our mind
	  $self->{$DEFAULT_ELT} = $elt;
	  last if (mostOfTheTime);
	}
      }
      if (!$self->{$DEFAULT_ELT}) { 
	print Dumper [keys %{$self->{$MUSIC}}];
	confess "Couldn't find a default music!";
      }
    }
    $musics = $self->{$MUSIC}{$self->{$DEFAULT_ELT}};
  }
  return $musics;
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

package CompElement;

use base qw(AutoHarp::Class);
use AutoHarp::Constants;

sub new {
  my $class = shift;
  my $self = {};
  $self->{tag}      = shift;
  $self->{musicTag} = shift;
  $self->{trans}    = shift;
  bless $self,$class;
}

sub musicTag {
  return $_[0]->scalarAccessor('musicTag',$_[1]);
}

sub tag {
  return $_[0]->scalarAccessor('tag',$_[1]);
}

sub transition {
  return $_[0]->scalarAccessor('trans',$_[1],$ATTR_STRAIGHT_TRANSITION);
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

"That stoner should know better...";

