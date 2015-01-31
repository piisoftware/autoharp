package AutoHarp::Fuzzy;

use base qw(Exporter);
use strict qw(vars subs);
use vars qw(@EXPORT);

@EXPORT = qw(unlessPigsFly
	     almostAlways
	     mostOfTheTime
	     often
	     asOftenAsNot
	     sometimes
	     rarely
	     almostNever
	     epicallySeldom
	     about
	     pickOne
	     plusMinus
	     betweenZeroAnd
	     hardVelocity
	     mediumVelocity
	     softVelocity
	     softerVelocity
	     shuffle
	   );

my $fudge;

BEGIN {
  $fudge = int(rand(10)) / 100;
  if (rand() < .5) {
    $fudge *= -1;
  }
}

sub fudgeFactor {
  return $fudge;
}

sub pickOne {
  my $choices = $_[0];
  if (ref($choices) ne 'ARRAY') {
    $choices = [@_];
  }
  return $choices->[int(rand(scalar @$choices))];
}

sub plusMinus {
  return (rand() < .5) ? 1 : -1;
}

sub about {
  my $amt  = shift;
  my $dir  = (rand() < .5 + $fudge) ? -1 : 1;
  return (abs($amt) >= 10) ? 
    $amt + ($dir * int(rand($amt * .1))) :
      $amt + ($dir * rand($amt));
}

sub almostAlways {
  return (rand() < (.95 + $fudge)) ? 1 : 0;
}

sub unlessPigsFly {
  return almostAlways || almostAlways;
}

sub mostOfTheTime {
  return (rand() < (.8 + $fudge)) ? 1 : 0;
}

sub often {
  return (rand() < (.6 + $fudge)) ? 1 : 0;
}

sub asOftenAsNot {
  return (rand() < (.5 + $fudge)) ? 1 : 0;
}

sub sometimes {
  return (rand() < (.3 + $fudge)) ? 1 : 0;
}

sub rarely {
  return (rand() < (.1 + $fudge)) ? 1 : 0;
}

sub almostNever {
  return (rand() < (.05 + $fudge)) ? 1 : 0;
}

sub epicallySeldom {
  return almostNever && almostNever;
}

sub hardVelocity {
  return 117 + (plusMinus() * int(rand(10)));
}

sub mediumVelocity {
  return 96 + (plusMinus() * int(rand(10)));
}

sub softVelocity {
  return 63 + (plusMinus() * int(rand(10)));
}

sub softerVelocity {
  return 31 + (plusMinus() * int(rand(10)))
}

sub shuffle {
  my $array = shift;
  my $i = scalar @$array;
  while (--$i) {
    my $j = int(rand($i + 1));
    @$array[$i,$j] = @$array[$j,$i];
  }
}

"Oh my god it's so state of the art";
