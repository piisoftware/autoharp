package AutoHarp::MusicBox::Hook;

use strict;
use AutoHarp::Events::Melody;
use AutoHarp::Constants;
use Carp;

use base qw(AutoHarp::MusicBox::Base);

#Hook is an adapted music box. The hook itself is really a melody
#when asked adapt it to other musics that we're passed, 
#we pass back a music box that's adapted and repeated as necessary

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(@_);
  bless $self,$class;

  $self->unsetProgression();
  return $self;
}

sub theHook {
  return $_[0]->melody();
}

sub subMusic {
  my $self = shift;
  return $self->SUPER::subMusic(@_)->toHook();
}

sub adaptOnto {
  my $self           = shift;
  my $adaptOntoMusic = shift;
  my $gen            = AutoHarp::Generator->new();
  my $adaptee        = $adaptOntoMusic->clone();

  if (!$self->duration()) {
    confess "Tried to adapt a zero-length hook";
  }

  #we'll keep the hook in its original key
  #with its original notes
  #unless we absolutely can't
  my $amel = AutoHarp::Events::Melody->new();
  my $time = $amel->time($adaptee->time());
  while ($time < $adaptee->reach()) {
    my $stc  = $self->clone();
    $stc->time($time);
    my $r = $adaptee->reach();
    my $limit = $r + $adaptee->clockAt($r)->measureTime();
    foreach my $n (grep {$_->time < $limit} @{$stc->melody()->notes()}) {
      my $ourScale   = $stc->scaleAt($n->time)->equivalentMajorScale();
      my $theirScale = $adaptee->scaleAt($n->time)->equivalentMajorScale();
      if (!$ourScale->equals($theirScale) &&
	  $theirScale->isAccidental($n->pitch)) {
	my $dir = ($ourScale->accidentals() > $theirScale->accidentals()) ? 
	  1 : -1;
	$n->pitch($n->pitch + $dir);
      }
      $amel->add($n);
    }
    $time = $stc->reach();
  }
  $adaptee->melody($amel);
  return $adaptee;
}

"Even through the darkest phase, be it thick or thin...";
