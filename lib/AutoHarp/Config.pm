package AutoHarp::Config;

use FindBin qw($Bin);
use strict;
my $HOME            = $ENV{HOME} || $ENV{HOMEPATH};
my $DS              = ($^O =~ /MSWin/) ? chr(92) : "/";
my $INI_FILE        = "$HOME${DS}.autoharp-config";
my $DB_ROOT         = $ENV{AUTOHARP_DB_ROOT} || "$Bin${DS}db";
my $GENRE_DB_ROOT   = "$DB_ROOT${DS}genres";
my $GENRE_FILE_ROOT = "$DB_ROOT${DS}loops";

sub MidiDirectory {
  my $dir = _fromConfig('MIDI') || 'midi';
  if (!-d $dir) {
    mkdir($dir);
  }
  return $dir;
}

sub DataDirectory {
  my $dir = _fromConfig('JSON') || 'json';
  if (!-d $dir) {
    mkdir($dir);
  }
  return $dir;
}

sub MidiFile {
  my $fileName = shift;
  $fileName =~ s/\.\w+$//;
  $fileName =~ s/\s//g;
  my $dir = MidiDirectory();
  return "$dir$DS$fileName.midi";
}

sub DataFile {
  my $fileName = shift;
  $fileName =~ s/\.\w+$//;
  $fileName =~ s/\s//g;
  my $dir = DataDirectory();
  return "$dir$DS$fileName.json";
}

sub GenreDBRoot {
  #take from environment, if set
  mkdir($DB_ROOT) if (!-d $DB_ROOT);
  mkdir($GENRE_DB_ROOT) if (!-d $GENRE_DB_ROOT);
  return $GENRE_DB_ROOT;
}

sub DBUser {
  return _fromConfig('DBUSER');
}

sub DBPwd {
  return _fromConfig('DBPASSWORD');
}

sub GenreFileRoot {
  mkdir($DB_ROOT) if (!-d $DB_ROOT);
  mkdir($GENRE_FILE_ROOT) if (!-d $GENRE_FILE_ROOT);
  return $GENRE_FILE_ROOT;
}

sub GenreDBFile {
  my $fileName = shift;
  $fileName .= ".json" if ($fileName !~ /\.json/);
  return GenreDBRoot() . "${DS}$fileName";
}

sub GenreLoopFile {
  my $fileName = shift;
  return GenreFileRoot() . "${DS}$fileName";
}

sub Player {
  return $ENV{MIDI_PLAYER} || _fromConfig('PLAYER');
}

sub Play {
  my $song = shift;
  my $was  = $song->file();
  my $player = Player();
  if ($song && $player) {
    my $tmp = $ENV{TEMP} || "/tmp"; 
    $tmp .= "${DS}ah.midi";
    #attempt to do a little mixing
    $song->out($tmp,1);
    if (-f $tmp) {
      return !system("$player $tmp");
    } elsif (-f $was) {
      return !system("$player $was");
    }
  }
  return;
}

sub PlayOpus {
  my $opus = shift;
  my $player = Player();
  if ($player) {
    my $tmp = $ENV{TEMP} || "/tmp"; 
    $tmp .= "${DS}ah.midi";
    $opus->write_to_file($tmp);
    return !system("$player $tmp");
  }
  return;
}

sub _fromConfig {
  my $key = shift;

  if (open(INIFILE, "$INI_FILE")) {
    while(<INIFILE>) {
      chomp();
      if (/$key: (.+)/) {
	return $1;
      }
    }
    close(INIFILE);
  }
  return;
}

"All the other kids with their pumped up kicks";
