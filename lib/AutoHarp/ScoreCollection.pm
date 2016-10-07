package AutoHarp::ScoreCollection;

use AutoHarp::Constants;
use AutoHarp::Events;
use AutoHarp::Instrument;
use AutoHarp::Scale;
use AutoHarp::Generator;
use AutoHarp::Clock;
use AutoHarp::Fuzzy;

use MIDI;
use strict;
use Carp;
use Data::Dumper; 
use base qw(AutoHarp::Class);

my $SCORES = 'scores';
my $DUNNO = 'DUNNO!';

my $SCORE_SORTER = {$ATTR_GUIDE => 0,
		    $DRUM_LOOP => 1,
		    $BASS_INSTRUMENT => 2,
		    $RHYTHM_INSTRUMENT => 3,
		    $PAD_INSTRUMENT => 4,
		    $HOOK_INSTRUMENT => 5,
		    $LEAD_INSTRUMENT => 6,
		    $THEME_INSTRUMENT => 7,
		    $DUNNO => 8
		   };

sub fromFile {
  my $class  = shift;
  my $file   = shift;
  my $scores = AutoHarp::Events->fromFile($file);
  my $self   = {$ATTR_GUIDE => shift(@$scores),
		$SCORES => $scores
	       };
  return bless $self,$class;
}

sub scores {
  $_[0]->scalarAccessor($SCORES,$_[1],[]);
}

sub guide {
  $_[0]->scalarAccessor($ATTR_GUIDE,$_[1]);
}

sub hasScores {
  my $self = shift;
  return (exists $self->{$SCORES} && scalar @{$self->{$SCORES}});
}

sub mixedTracks {
  my $self = shift;
  return $self->tracks(1);
}

sub tracks {
  my $self = shift;
  my $doMix = shift;
  my $tracks = [];
  
  if ($self->guide()) {
    push(@$tracks, {t => $self->guide->track(), k => $ATTR_GUIDE});
  }
  if ($self->hasScores()) {
    foreach my $score (@{$self->scores()}) {
      my $inst = AutoHarp::Instrument->fromEvents($score,$self->guide());
      if ($doMix) {
	$score->setVolume(50);
	if ($inst && $inst->isDrums) {
	  $score->setVolume(60);
	} elsif ($inst && $inst->is($BASS_INSTRUMENT)) {
	  $score->setVolume(35);
	} elsif ($inst && $inst->is($PAD_INSTRUMENT)) {
	  $score->setVolume(45);
	} elsif ($inst && $inst->is($RHYTHM_INSTRUMENT)) {
	  $score->setPan(-10);
	} elsif ($inst && $inst->is($LEAD_INSTRUMENT)) {
	  $score->setVolume(55);
	} elsif ($inst && $inst->is($HOOK_INSTRUMENT)) {
	  $score->setPan(10);
	} else {
	  $score->setPan((pickOne(12.5, -12.5)) * (pickOne(2,3,4)));
	}
      }
      if ($inst) {
	$score->instrumentName($inst->toString());
	$score->trackName($inst->name);
      }
      
      push(@$tracks,
	   {t => $score->track(),
	    k => ($inst) ? $inst->instrumentClass : $DUNNO
	   });
    }
  }
  return [map {$_->{t}}
	  sort {$SCORE_SORTER->{$a->{k}} <=> $SCORE_SORTER->{$b->{k}}}
	  @$tracks];
}

sub opus {
  my $self = shift;
  my $mix  = shift;
  return MIDI::Opus->new( {
			   format => 1,
			   ticks => $TICKS_PER_BEAT,
			   tracks => ($mix) ? $self->mixedTracks() : $self->tracks()
			  } );
}

sub demoOut {
  my $self = shift;
  return $self->out("/tmp/sc.mid",1);
}

sub out {
  my $self   = shift;
  my $output = shift;
  my $mix    = shift;
  if ($output) {
    my $file;
    if (-d $output) {
      $output =~ s|/$||;
      $file = $output . "/" . $self->uid() . ".mid";
    } else {
      $file = $output;
    }
    eval {
      my $o = $self->opus($mix);
      $o->write_to_file($file);
    };
    if ($@) {
      confess "Write to opus failed: $@";
    }
    return $output;
  }
  return;
}

"We have fought on, like, seventy-five different fronts.";
