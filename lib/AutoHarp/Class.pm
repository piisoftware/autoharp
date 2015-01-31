package AutoHarp::Class;
use JSON;
use Carp;
use strict;
use Data::Dumper;
use AutoHarp::Constants;

use Scalar::Util qw(blessed);
use Class::Load qw(is_class_loaded);

#base class for Magic Alex modules

sub new {
  my $class = shift;
  my $args  = $_[0];
  if (ref($args) ne 'HASH') {
    $args = {@_};
  }
  return bless $args, $class;
}

sub requireClass {
  my $class = shift;
  my $mod   = $class;
  $mod =~ s|::|/|g;
  my $evalOk = 0;
  eval {
    require "$mod.pm";
    $evalOk++;
  };
  return $evalOk;
}

sub fromDataStructure {
  my $class = shift;
  my $ds    = shift;
  my ($newClass,$ref) = _deserializeAHDS($ds);
  my $self = DataStructureToObject($ref,@_);
  bless $self,($newClass) ? $newClass : $class;
  return $self;
}

sub toDataStructure {
  my $self = shift;
  if ($self->isa('ARRAY')) {
    return [ref($self), [map {ObjectToDataStructure($_,@_)} @$self]];
  } elsif ($self->isa('HASH')) {
    my $ds = {map {$_ => ObjectToDataStructure($self->{$_}, @_)} keys %$self};
    $ds->{$AH_CLASS} = ref($self);
    return $ds;
  }
}

sub ObjectToDataStructure {
  my $obj = shift;
  if (blessed($obj) && $obj->isa('AutoHarp::Class')) {
    return $obj->toDataStructure(@_);
  } elsif (ref($obj) eq 'ARRAY') {
    return [map {ObjectToDataStructure($_,@_)} @$obj];
  } elsif (ref($obj) eq 'HASH') {
    return {map {$_ => ObjectToDataStructure($obj->{$_},@_)} keys %$obj};
  }
  return $obj;
}

sub DataStructureToObject {
  my $ds = shift;
  if (_isAHDS($ds)) {
    my ($class,$ref) = _deserializeAHDS($ds);
    return $class->fromDataStructure($ref,@_);
  } elsif (ref($ds) eq 'ARRAY') { 
    return [map {DataStructureToObject($_,@_)} @$ds];
  } elsif (ref(%$ds) eq 'HASH') {
    return {map {$_ => DataStructureToObject($ds->{$_},@_)} %$ds};
  }
  return $ds;
}

sub clone {
  my $self  = shift;
  return bless _recCopy({%$self}),ref($self);
}

sub dump {
  my $self = shift;
  print $self->toString(@_);
  print "\n";
}

sub toString {
  my $self = shift;
  return JSON->new()->pretty()->encode($self->toDataStructure(@_));
}
  
sub _deserializeAHDS {
  my $ds = shift;
  my $ref;
  my $class;
  if (_isAHDS($ds) eq 'ARRAY') {
    if (_isAHDS($ds->[1]) eq 'ARRAY') {
      confess sprintf("Received double-encoded serialized AHDS object (outer: %s, inner %s)",$ds->[0],$ds->[1]->[0]);
    }
    $class = $ds->[0];
    $ref = $ds->[1];
  } elsif (_isAHDS($ds) eq 'HASH') {
    $class = $ds->{$AH_CLASS};
    $ref = $ds;
    delete $ref->{$AH_CLASS};
  } else {
    $class = '';
  }
  if ($class && !is_class_loaded($class)) {
    requireClass($class);
  }
  return ($class,$ds);
}

sub _isAHDS {
  my $d = shift;
  return ((ref($d) eq 'ARRAY' && $d->[0] =~ /^AutoHarp/) ||
	  (ref($d) eq 'HASH' && $d->{$AH_CLASS})) ? ref($d) : undef;
}

sub _recCopy {
  my $thing = shift;
  
  if (!ref($thing) || ref($thing) eq 'CODE') {
    return $thing;
  } elsif (ref($thing) eq 'HASH') {
    return {map {$_ => _recCopy($thing->{$_})} keys %$thing};
  } elsif (ref($thing) eq 'ARRAY') {
    return [map {_recCopy($_)} @$thing];
  } elsif (ref($thing) && $thing->can('clone')) {
    return $thing->clone;
  }
  
  return $thing;
}

sub objectAccessor {
  my $self     = shift;
  my $attr     = shift;
  my $isa      = shift;
  my $val      = shift;
  #make sure $isa is Modulified
  $isa = uc(substr($isa,0,1)) . substr($isa,1);
  $isa = "AutoHarp::$isa" if ($isa !~ /AutoHarp::/);
  if ($val) {
    if (ref($val) =~ /AutoHarp/ && $val->isa($isa)) {
      $self->{$attr} = $val->clone;
    } else {
      confess "Attempt to set object accessor $attr with non $isa object " . ref($val);
    }
  }
  return $self->{$attr};
}
    
sub scalarAccessor {
  my $self = shift;
  my $attr = shift;
  my $val  = shift;
  my $default = shift;
  if (length($val)) {
    $self->{$attr} = $val;
  }
  if (length($default) && !length($self->{$attr})) {
    $self->{$attr} = $default;
  }
  return $self->{$attr};
}

"I accept that this will come as some surprise";
