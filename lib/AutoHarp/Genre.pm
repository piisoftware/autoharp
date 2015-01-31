package AutoHarp::Genre;

use AutoHarp::Constants;
use AutoHarp::Config;
use AutoHarp::Fuzzy;
use Carp;
use JSON;

use base qw(AutoHarp::Class);
use strict;


#a genre (by name, e.g. "funk") and its attributes
my $DB_ROOT  = AutoHarp::Config::GenreDBRoot();
my $DATA     = 'data';
my $PATTERNS = 'patterns';
my $TEMPO_MATCH_PCT = .15; #anything within 15%? Extra grotty SWAG right here
my $ATTRS = [$ATTR_BARS,
	     $ATTR_METER,
	     $ATTR_TEMPO,
	     $ATTR_SWING_NOTE, 
	     $ATTR_SWING_PCT, 
	     $ATTR_FILE,
	     $ATTR_TAG
	    ];

sub ValidGenre {
  my $genre = shift;
  return (-f AutoHarp::Config::GenreDBFile(__genreToKey($genre)));
}

sub Genres {
  my $gs = [];
  if (opendir(DIR, $DB_ROOT)) {
    foreach my $f (grep {s/\.json//} readdir(DIR)) {
      push(@$gs,__keyToGenre($f));
    }
  }

  if (!scalar @$gs) {
    confess "There are no genres! Have you seeded this program yet (see the README file)?"
  }

  return $gs;
}

sub new {
  my $class  = shift;
  my $genre  = shift;
  my $create = shift;
  my $self  = {};
  if ($genre) {    
    my $key = $self->{key} = __genreToKey($genre);
    if (!ValidGenre($genre) && !$create) {
      print "$genre is an unrecognized genre. Valid genres are:\n";
      print join("\n",@{Genres()});
      print "\n";
      die "\n";
    }
  }
  bless $self,$class;
  $self->read();
  return $self;
}

sub fromClock {
  my $class = shift;
  my $clock = shift;
  my @options;
  foreach my $g (@{$class->Genres()}) {
    my $test = $class->new($g);
    foreach my $p (@{$test->getPatterns()}) {
      my $pc = AutoHarp::Clock->new(%$p);
      if ($clock->meter() eq $pc->meter() &&
	  abs(($pc->tempo / $clock->tempo()) - 1) < $TEMPO_MATCH_PCT) {
	if ($p->{$ATTR_TAG} eq $SONG_ELEMENT_VERSE) {
	  push(@options, $test);
	  last;
	}
      }
    }
  }
  return pickOne(@options) ||
    $class->new(pickOne($class->Genres()));
}

sub DESTROY {
  my $self = shift;
  untie %{$self->{$DATA}};
}

#suggest a tempo and meter for this genre
sub suggestClock {
  my $self = shift;

  my $basePattern = pickOne(grep {$_->{$ATTR_TAG} eq $SONG_ELEMENT_VERSE} 
			    @{$self->getPatterns()});
  my $tempo       = $basePattern->{$ATTR_TEMPO};
  #muck with it by 10% or so
  $tempo = $tempo + (plusMinus() * int(rand(.1 * $tempo)));
  delete $basePattern->{$ATTR_SWING_PCT};
  delete $basePattern->{$ATTR_SWING_NOTE};

  if (asOftenAsNot) {
    #very light swing sounds good. Everything else sounds crap
    $basePattern->{$ATTR_SWING_PCT} = int(rand(5)) + 5;
    #TODO: eighth note swing just don't work right now--
    #requires some significant work
    $basePattern->{$ATTR_SWING_NOTE} = 'sixteenth'; 
  }
    
  return AutoHarp::Clock->new($ATTR_TEMPO => $tempo,
			      $ATTR_METER => $basePattern->{$ATTR_METER},
			      $ATTR_SWING_PCT => $basePattern->{$ATTR_SWING_PCT},
			      $ATTR_SWING_NOTE => $basePattern->{$ATTR_SWING_NOTE}
			     );
}

sub getPatterns {
  my $self = shift;
  return [@{$self->{$PATTERNS}}];
}

#find a loop in this genre that matches our criterion
sub findLoop {
  my $self    = shift;
  my $clock   = shift;
  my $tag     = shift;
  my @options;
  foreach my $p (@{$self->getPatterns()}) {
    my $t = $p->{$ATTR_TAG};
    if ($t eq $SONG_ELEMENT_LEADIN || 
	$t eq $SONG_ELEMENT_LEADOUT ||
	!-f AutoHarp::Config::GenreLoopFile($p->{$ATTR_FILE})
       ) {
      #can't use these as loops
      next;
    }
    my $pc = AutoHarp::Clock->new(%$p);
    if ($clock->meter() eq $pc->meter() &&
	abs(($pc->tempo / $clock->tempo()) - 1) < $TEMPO_MATCH_PCT) {
      #this matches, more or less...can we have it?
      if (!$tag ||
	  $t eq $tag ||
	  $t eq $SONG_ELEMENT_VERSE ||
	  ($t eq $SONG_ELEMENT_CHORUS && rarely) ||
	  almostNever) {
	push(@options,$p);
      } 
    }
  }
  return pickOne(@options);
}

sub findFill {
  my $self = shift;
  my $clock = shift;
  my @fills;
  foreach my $f (
		 grep {$_->{$ATTR_TAG} eq $SONG_ELEMENT_FILL} 
		 @{$self->{$PATTERNS}}
		) {
    my $fc = AutoHarp::Clock->new(%$f);
    if ($clock->meter eq $fc->meter &&
	abs(($fc->tempo / $clock->tempo()) - 1) < $TEMPO_MATCH_PCT) {
      push(@fills, $f);
    }
  }
  return pickOne(@fills);
}

sub findLeadIn {
  my $self  = shift;
  my $clock = shift;
  my @leadIns;
  foreach my $l (grep {$_->{$ATTR_TAG} eq $SONG_ELEMENT_LEADIN}
		 @{$self->{$PATTERNS}}) {
    my $lc = AutoHarp::Clock->new(%$l);
    if ($clock->meter eq $lc->meter &&
	abs(($lc->tempo / $clock->tempo()) - 1) < $TEMPO_MATCH_PCT) {
      push(@leadIns, $l);
    }
  }
  return pickOne(@leadIns);
}
  
sub name {
  return __keyToGenre($_[0]->{key});
}

sub read {
  my $self = shift;
  my $key  = shift || $self->{key};
  if (open(F,AutoHarp::Config::GenreDBFile($key))) {
    my $d;
    while(<F>) {
      $d .= $_;
    }
    close(F);
    eval {
      $self->{$PATTERNS} = JSON->new()->decode($d);
    };
    if ($@) {
      confess "Couldn't read " . $self->name() . ": $!";
    }
  }
  $self->{$PATTERNS} ||= [];
}

sub save {
  my $self = shift;
  my $f = AutoHarp::Config::GenreDBFile($self->{key});
  open(F, ">$f") or die "Couldn't save, couldn't open $f for writing: $!";
  print F JSON->new()->pretty()->encode($self->{$PATTERNS});
  close(F);
}

sub addPattern {
  my $self    = shift;
  my $toAdd   = shift;
  my $noCheck = shift;
  if (!$noCheck) {
    my $file = $toAdd->{$ATTR_FILE};
    my $tracks;
    eval {
      #does this file make a valid drum track
      $tracks = AutoHarp::Events::DrumTrack->fromFile($file);
    };
    if ($@ || !$tracks) {
      confess "Data did not contain a valid percussion track ($@)";
    }; 
 }
  return push(@{$self->{$PATTERNS}},{map {$_ => $toAdd->{$_}} @$ATTRS});
}

sub __genreToKey {
  my $key = shift;
  return join
    ("", 
     map {uc(substr($_,0,1)) . lc(substr($_,1))} 
     split(/\s+/,$key)
    );
}

sub __keyToGenre {
  my $key = shift;
  $key =~ s/(\w)([A-Z])/$1 $2/g;
  return $key;
}

#wonky == measures in the middle that have nothing in them
sub __patternIsWonky {
  my $pattern = shift;
  my @counts;
  while (my ($d,$str) = each %$pattern) {
    my $ms = AutoHarp::Notation::SplitMeasures($str);
    for (my $i = 0; $i < scalar @$ms; $i++) {
      $counts[$i] += scalar grep {/\d/} split("",$ms->[$i]);
    }
  }
  my $stage = 0;
  foreach (@counts) {
    if ($_) {
      if ($stage == 2) {
	return 1;
      }
      $stage = 1;
    } elsif ($stage) {
      $stage = 2;
    }
  }
  return;
}
