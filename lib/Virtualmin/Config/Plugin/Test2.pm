package Virtualmin::Config::Plugin::Test2;
use strict;
use warnings;
use 5.010;
use parent qw(Virtualmin::Config::Plugin);

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Test2', depends => ['Test'], %args);

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. XXX Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;

  $self->spin();
  eval {    # try
    sleep 1;
  } or do {    # catch
    $self->done(0);    # Something failed
  };
  $self->done(1);      # OK!
}

1;
