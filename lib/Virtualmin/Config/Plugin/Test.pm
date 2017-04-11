package Virtualmin::Config::Plugin::Test;
use strict;
use warnings;
use parent 'Virtualmin::Config::Plugin';

sub new {
  my $class = shift;
  # inherit from Plugin
  my $self = $class->SUPER->new(name => 'Test');

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. XXX Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;

  $self->spin("Configuring Test");
  eval { # try
    sleep 5;
  }
  or do { # catch
    $self->done(0); # Something failed
  };
  $self->done(1); # OK!
}

1;
