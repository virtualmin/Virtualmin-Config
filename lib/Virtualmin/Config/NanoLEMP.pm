package Virtualmin::Config::NanoLEMP;
use strict;
use warnings;
use 5.010_001;

# A list of plugins for configuring a nano LEMP stack

sub new {
  my ($class, %args) = @_;
  my $self = {};

  return bless $self, $class;
}

sub plugins {
  my ($self, $stack) = @_;
  return $stack->list('lemp', 'nano');
}

1;
