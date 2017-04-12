package Virtualmin::Config::Dummy;
# A list of plugins for testing
use strict;
use warnings;

sub new {
  my ($class, %args) = @_;
  my $self = {};

	return bless $self, $class;
}

sub plugins {
  return (
    "Test",
    "Test2",
  );
}

1;
