package Virtualmin::Config::Dummy;
# A list of plugins for configuring a LAMP stack

sub new {
  my ($class, %args) = @_;
  my $self = {};

	return bless $self, $class;
}

sub plugins {
  return [
    "Test"
  ];
}
