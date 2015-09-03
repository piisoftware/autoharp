package AutoHarp::Model;
use DBI;
use Carp;
use Data::Dumper;
use AutoHarp::Config;

use strict;

use vars qw($AUTOLOAD);

#base class for Accessing Mysql via AutoHarp

my $SESSION;
my $HAS_UPDATES = 'someStuffChanged';
my $DEFAULT_PK = 'id';
my $COLUMNS = 'columns';
my $COLUMN_NAME_MEMO = {};

sub Select {
  my $statement = shift;
  my $failSilently = shift;
  my $rows = [];
  eval {
    my $h = getSession()->prepare($statement);
    $h->execute();
    my $r;
    while ($r = $h->fetchrow_hashref()) {
      push(@$rows, $r);
    }
  };
  if ($@ && !$failSilently) {
    confess "invalid sql $statement: $@";
  }
  return $rows;
}

sub new {
  my $class = shift;
  my $args = $class->labelArgs(@_);
  my $self = {$COLUMNS => $args};
  return bless $self, $class;
}

sub load {
  my $class = shift;
  my $pkVal = shift;
  my $row = $class->_select({$class->primaryKey() => $pkVal})->[0];
  if (!$row) {
    confess "Found no row for $class with " . $class->primaryKey() . " = $pkVal";
  }
  return bless {$COLUMNS => {%$row}},$class;
}
  
#like "all" below but just returns one row
sub loadBy {
  my $class = shift;
  my $rows = $class->all(@_);
  my $self;
  if ($rows && scalar @$rows >= 1) {
    $self = {%{$rows->[0]}};
  } else {
    $self = {$COLUMNS => {}};
  }
  bless $self,$class;
  return $self;
}

#load a row or create a new one based on the passed conditions
sub loadOrCreate {
  my $class = shift;
  my $self  = $class->loadBy(@_);
  if ($self->isEmpty()) {
    return $class->new(@_);
  } 
  return $self;
}
  
#load everything object of this type 
#for which the stated conditions are true
sub all {
  my $class = shift;
  my $args = $class->labelArgs(@_);
  my $all = [];
  foreach my $r (@{$class->_select($args)}) {
    push(@$all, bless({$COLUMNS => {%$r}},$class));
  }
  return $all;
}

#load object by where clause
sub where {
  my $class = shift;
  my $where = shift;
  my $s = getSession()->prepare(sprintf("select * from %s where %s",
					$class->tableName(),
					$where));
  $s->execute();
  my $wset = [];
  my $r; 
  while ($r = $s->fetchrow_hashref()) {
    push(@$wset,bless({$COLUMNS => {%$r}}, $class));
  }
  return $wset;
}

sub labelArgs {
  my $class = shift;
  my $first = $_[0];
  return (ref($first) eq 'HASH') ? $first : {@_};
}

#override this method to use a different primary key for a row
sub primaryKey {
  return $DEFAULT_PK;
}

sub isEmpty {
  return !scalar keys %{$_[0]->{$COLUMNS}};
}

sub save {
  my $self = shift;
  if ($self->{$COLUMNS}{$self->primaryKey()}) {
    if ($self->{$HAS_UPDATES}) {
      $self->update();
    } else {
      #no op
    }
  } else {
    $self->insert();
  }
  delete $self->{$HAS_UPDATES};
  return 1;
}

sub update {
  my $self = shift;
  my $pk = $self->primaryKey();
  my $u = "update " . $self->tableName() . " set ";
  while (my ($k,$v) = each %{$self->{$COLUMNS}}) {
    next if ($k eq $pk);
    $v =~ s/\'//g;
    $v = "'$v'" unless ($v =~ /^\d+$/);
    $u .= " $k = $v,";
  }
  $u =~ s/,$//;
  $u .= " where $pk = " . $self->{$COLUMNS}{$pk};
  eval {getSession()->do($u)};
  if ($@) {
    confess sprintf("Couldn't update row %s of %s: %s",
		    $self->{$COLUMNS}{$pk},
		    ref($self),
		    $@);
  }
  #reload the row
  
  return 1;
}

sub insert {
  my $self = shift;
  my $pk = $self->primaryKey();
  my $columns = "(";
  my $values = "(";
  while (my ($k,$v) = each %{$self->{$COLUMNS}}) {
    next if ($k eq $pk);
    $columns .= "$k,";
    $v =~ s/\'//g;
    if ($v =~ /^\d+$/) {
      $values .= "$v,";
    } else {
      $values .= "'$v',";
    }
  }
  $columns =~ s/,$/\)/;
  $values  =~ s/,$/\)/;
  my $i = "insert into " . $self->tableName() . " $columns values $values";
  my $h = getSession()->prepare($i);
  my $pkVal;
  eval {
    $h->execute();
    $pkVal = $self->{$COLUMNS}{$pk} = $h->{mysql_insertid};
    if (!$pkVal) {
      confess "Statement\n$i\n created no primary key value\n";
    }
  }; 
  if ($@) {
    confess "Failed to insert new row: $@";
  }
  my $new = ref($self)->load($pkVal);
  $self->{$COLUMNS} = $new->{$COLUMNS};
  return 1;
}

sub delete {
  my $self = shift;
  my $pk = $self->primaryKey();
  eval {
    getSession()->do(sprintf("delete from %s where %s = %d",
			     $self->tableName(),
			     $pk,
			     $self->{$COLUMNS}{$pk}));
  };
  if ($@) {
    confess "Couldn't delete row! $@";
  }
  delete $self->{$COLUMNS}{$pk};
  return 1;
}

sub getSession {
  if (!$SESSION || !$SESSION->ping) {
    my $dsn = "dbi:mysql:autoharp;host=localhost";
    eval {
      $SESSION = DBI->connect($dsn, AutoHarp::Config::DBUser(), AutoHarp::Config::DBPwd());
    };
    if ($@) {
      confess "Couldn't connect to DB via $dsn ($@).\nMake sure DBUSER and DBPASSWORD are set correctly in your config file";
    }
  }
  return $SESSION;
}

sub getColumnNames {
  my $self = shift;
  my $tname = $self->tableName();
  if (!$COLUMN_NAME_MEMO->{$tname}) {
    my $sth = getSession->prepare("SELECT * FROM $tname WHERE 1=0");
    $sth->execute();
    $COLUMN_NAME_MEMO->{$tname} = [@{$sth->{NAME}}];
    $sth->finish();
  }
  return $COLUMN_NAME_MEMO->{$tname};
}

sub tableName {
  my $self = shift;
  my $name = lc(($self->CreateTableCommands() =~ /create\W*table\W*(\w+)/i)[0]);
  if (!$name) {
    my $class = ref($self) || $self;
    confess "Cannot acquire table name for $class from create table commands";
  }
  return $name;
}

sub Install {
  my $class = shift;
  my $drop  = shift;
  my $sess  = getSession();
  #does it exist?
  my $tname = $class->tableName();
  my $eh = $sess->prepare('Show tables');
  $eh->execute();
  my @t;
  while (@t = $eh->fetchrow_array()) {
    if (lc($t[0]) eq lc($tname)) {
      if (!$drop) {
	#this table already exists
	return;
      }
      eval {$sess->do("drop table $tname");};
      if ($@) {
	confess "Couldn't drop $tname: $@";
      }
      last;
    }
  };
  $eh->finish();
  eval {$sess->do($class->CreateTableCommands())};
  if ($@) {
    confess "Couldn't create table $tname: $@";
  }
  return 1;
}
  
sub CreateTableCommands {
  my $class = shift;
  confess "$class must override CreateTableCommands";
}

sub _select {
  my $class = shift;
  my $args = shift || {};
  my $statement = "select * from " . $class->tableName();
  my $and = "where";
  while (my ($k,$v) = each %$args) {
    $v =~ s/\'//g;
    if ($v !~ /^\d+$/) {
      $v = "'$v'";
    }
    $statement .= " $and $k = $v";
    $and = "and";
  }
  my $s = getSession()->prepare($statement);
  $s->execute();
  my $rset = [];
  my $r; 
  while ($r = $s->fetchrow_hashref()) {
    push(@$rset,$r);
  }
  if (!scalar @$rset && $statement =~ /element\s+\=/) {
    confess "FUCK YOU $statement";
  }
  return $rset;
}

sub DESTROY {
  #fuck you, destroy
}

sub AUTOLOAD {
  my $self   = shift;
  my $val    = shift;
  my $method = ($AUTOLOAD =~ /::([^:]+)$/)[0];
  if (scalar grep {$method eq $_} @{$self->getColumnNames()}) {
    if (length($val)) {
      if ($method eq $self->primaryKey()) {
	confess "Primary key cannot be set in code";
      }
      $self->{$HAS_UPDATES} = ($val ne $self->{$COLUMNS}{$method});
      $self->{$COLUMNS}{$method} = $val;
    }
    return $self->{$COLUMNS}{$method};
  }
  printf "Valid columns for %s:\n",ref($self) || $self;
  print join("\n",@{$self->getColumnNames});
  print "\n";
  confess "Attempted to call unknown method $method on " . ref($self);
}

"Season of trouble, so long";
