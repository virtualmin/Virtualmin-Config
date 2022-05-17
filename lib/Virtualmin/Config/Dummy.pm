package Virtualmin::Config::Dummy;

# A list of plugins for testing
use strict;
use warnings;
use 5.010;

sub new {
  my ( $class, %args ) = @_;
  my $self = {};

  return bless $self, $class;
}

sub plugins {
  return [ "Test", "Test2", ];
}

1;
