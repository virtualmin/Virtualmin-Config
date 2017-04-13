package Virtualmin::Config::LAMP;
use strict;
use warnings;
use 5.010;
# A list of plugins for configuring a LAMP stack

sub new {
  my ($class, %args) = @_;
  my $self = {};

	return bless $self, $class;
}

sub plugins {
  return (
    "Webmin"
  );
}

1;
