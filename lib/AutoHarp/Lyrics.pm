package AutoHarp::Lyrics;

use Lingua::EN::Rhyme::Dictionary qw/%dict %reversedict/;
use AutoHarp::Constants;
use AutoHarp::Fuzzy;

require Exporter;

use strict;

#you bet your damn ass I got lyrics

my $LYRIC_DIR = "$ENV{HOME}/workplace/lyrics";

sub GetLyricSheetForGuide {
  my $guide = shift;
  my $seen  = {}
}

our @ISA =qw/Exporter/;
our @EXPORT=qw/variants pronounce syllables accent endrhyme beginrhyme visualrhyme/;
our @EXPORT_OK=qw/endsylrhyme beginsylrhyme/;
our %EXPORT_TAGS= ( default => [qw(variants pronounce syllables accent endrhyme beginrhyme visualrhyme)]);
our $VERSION=0.01;

sub pronounce {
  my $word=$_[0];
  $word.="($_[1])" if defined ($_[1]) and $_[1]>1;
  return defined($dict{uc($word)})? $dict{uc($word)} : "** unknown word **";
}

sub syllables {
  my $pron=pronounce(uc($_[0]),$_[1]);
  $_=$pron;
  my @match=/([012])/g;
  my $rv=@match;
  return ($rv) if !($pron=~/unknown word/);
}

sub accent {
  my $pron=pronounce(uc($_[0]),$_[1]);
  $_=$pron;
  my @match=/([012])/g;
  return wantarray()?@match:join('',@match);
}

sub sylpron {
  $_=$_[0];
  my @match=/([012])/g;
  my $rv=@match;
  return $rv;
}

sub beginrhyme {
  my ($word,$variant,$syl) = @_;
  my $pron=pronounce(uc($word),$variant);
  $pron=$word if ($word =~ / /);
  my $syllab=sylpron($pron);
  $syl=$syllab if (!defined($syl))||($syl>$syllab);
  my @result=();
  for (my $i=$syl; $i>0; $i--) {
    @result = beginsylrhyme ($word,$variant,$i);
    if (@result) {
      return wantarray()? @result: $result[int(rand(@result))];
    }
  }
  return wantarray()?():"";
} 

sub variants {
  my $word=uc(shift);
  my $answer=2;
  return 0 if !defined($dict{$word});
  while (defined($dict{"${word}($answer)"})) {
    $answer++
  } 
  $answer--;
  return $answer;
}

sub visualrhyme {
  my $word=uc(shift);
  my $letters=shift;
  $letters=length($word)-1 if (!defined($letters));
  my @results=();
  for (my $i=$letters; $i>0; $i--) {
    foreach (keys %dict) {
       push (@results,$_) if length($_)>$i and (substr($word,-$i) eq substr($_,-$i)) and $word ne $_ and $_ !~ /\(\d\)/;
    }
    if (@results) {
      return wantarray()?@results:$results[int(rand(@results))];
    }
  }
  return wantarray()?():"";
}


sub endrhyme {
  my ($word,$variant,$syl) = @_;
  my $pron=pronounce(uc($word),$variant);
  $pron=$word if ($word =~ / /);
  my $syllab=sylpron($pron);
  $syl=$syllab if (!defined($syl))||($syl>$syllab); 
  
  my @result=();
  for (my $i=$syl; $i>0; $i--) {
    @result = endsylrhyme($word,$variant,$i) ;
    if (@result) {
      return wantarray()? @result : $result[int(rand(@result))];
    }
  } 
  return wantarray()? (): "";
}

sub endsylrhyme {
  my ($word,$variant,$syl) = @_;
  $word=uc($word);
  my $pron = pronounce ($word,$variant);
  $pron=$word if ($word=~/ /);
  if ($pron=~ /^\*\*/) {
    return wantarray()? ():"";
  }
  $pron =~ /\b(\w+\d)\b/;
  $pron = substr($pron,$-[0]);
  my @resultarray=();
  my $syllab=sylpron($pron);
  while (defined($syl) and $syl<$syllab and $syl>0) {
    $pron =~ /\b(\w+\d)\b/; #skip a vowel
    $pron = substr($pron,$+[0]) if defined($+[0]);
    $pron =~ /\b(\w+\d)\b/; #strip consonants in front of it
    $pron = substr($pron,$-[0]) if defined($-[0]);
    $syllab = sylpron($pron);
  }
  foreach (keys %reversedict) {
    push(@resultarray,$reversedict{$_}) if /$pron$/ and $reversedict{$_}!~/^$word(\(\d\))?$/;
  }
  if (@resultarray) {
    return wantarray()? @resultarray : $resultarray[int(rand(@resultarray))];
   } else {
     return wantarray()? ():"";
   } 
}

sub beginsylrhyme {
  my ($word,$variant,$syl) = @_;
  $word=uc($word);
  my $pron = pronounce ($word,$variant);
  $pron=$word if ($word=~/ /);
  if ($pron=~ /^\*\*/) {
    return wantarray()? ():"";
  }
  $pron = reverse $pron;
  $pron =~ /\b(\d\w+)\b/;
  $pron = substr($pron,$-[0]);
  my @resultarray=();
  my $syllab=syllables($word,$variant);
  while (defined($syl) and $syl<$syllab and $syl>0) {
    $pron =~ /\b(\d\w+)\b/; #skip a vowel
    $pron = substr($pron,$+[0]) if defined($+[0]);
    $pron =~ /\b(\d\w+)\b/; #strip consonants in front of it
    $pron = substr($pron,$-[0]) if defined($-[0]);
    $syllab = sylpron($pron);
  }
  $pron=reverse $pron;
  foreach (keys %reversedict) {
    push(@resultarray,$reversedict{$_}) if /^$pron/ and $reversedict{$_}!~/^$word(\(\d\))?$/;
  }
  if (@resultarray) {
    return wantarray()? @resultarray : $resultarray[int(rand(@resultarray))];
   } else {
     return wantarray()? ():"";
   } 
}

=head1 NAME

Lingua::EN::Rhyme - Finds rhymes for English words.

=head1 SYNOPSIS

    use Lingua::EN::Rhyme;
    my $rhyme=endrhyme('orange');
    my @rhymelist=endrhyme('orange');
    $rhyme=beginrhyme('project',2,1); #Pronunciation 2, one syllable only
    my $accentuation=accent('abortionist');
    my $pronunciation=pronounce('project',2);

=head1 DESCRIPTION

To the joy of would-be poets everywhere, this module seeks to ease the 
load of finding the perfect rhyme. The dictionary used is the freely
distributable CMU Pronouncing dictionary, and is contained in the module
Lingua::EN::Rhyme::Dictionary.

=head2 Default Export

C<endrhyme> - You must specify a word, and optionally the number of the variant
desired and the maximum number of syllables to match. Given these parameters,
a list of the "best" matches will be created. If called in array context,
this array is returned, while in scalar context a random entry from the list
is given. You may optionally provide a phonetic transcription following the
CMU style instead of a word. In this case, the value of the variant would be
ignored.

C<beginrhyme> - Usage is the same as endrhyme, but matches the beginning of the
words. Here "silver" would be a rhyme for "sylvan", for instance.

C<visualrhyme> - Looks for words having the same ending letters as the 
word provided. You may optionally provide a maximum number of letters to match.
Here you do not specify a variant, because we are basing this on spelling,
not pronunciation.

C<pronounce> - Returns the pronunciation of the word. You may optionally 
provide the number of the variant.

C<variants> - Returns the number of variants in the dictionary for the 
word provided.

C<accent> - Returns either an array or a string containing the accentuation
values of the word (and optionally variant) values provided. Here, 0 means
unaccented, 1 is primary stress, and 2 is secondary stress.

C<syllables> - Returns the number of syllables in the word (and optionally
variant).

=head2 Optional Exports

The following two routines are used internally by Lingua::EN::Rhyme, but may
be exported for use in the calling program if desired.

C<endsylrhyme> - Here you must specify word, variant, and number of syllables.
Returns word(s) that rhyme in EXACTLY the number of syllables requested.

C<beginsylrhyme> - The same, for beginning rhymes.

=head1 HISTORY

	Revision 0.01	2001/05/28	Mark Polo
	Initial revision

=head1 COPYRIGHT

Copyright 2001 by Mark Polo

=head1 LICENSE

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHOR BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

=cut

1;
