package Virtualmin::Config::Plugin;
use strict;
use warnings;

# Plugin base class, just runs stuff with spinner and status
use Virtualmin::Config;
use Term::Spinner::Color;

sub new {
  my ($class, %args) = @_;
  my $self = {
    name    => $args{'name'} || '',
    depends => $args{'depends'} || '',
  };

  return bless $self, $class;
}

# Plugin short name, used in config definitions
sub name {
  my $self = shift;
  if(@_) { $self->{'name'} = shift }
  return $self->{'name'};
}

# Return a ref to an array of plugins that have to run before this one.
# Dep resolution is very stupid. Don't do anything complicated.
sub depends {
  my $self = shift;
  if (@_) { $self->{'depends'} = shift }
  return $self->{'depends'};
}

sub spin {
  my $self = shift;
  my $message = shift // "Configuring $self->{'name'}";
  $self->{s} = Term::Spinner::Color->new();
  print $message . " " x (80 - $message - $self->{s}->{'frame_length'});
  $self->{s}->auto_start();
}

sub done {
  my $self = shift;
  my $res = shift;
  if ($res) {
    # Success!
    $self->{s}->auto_done();
    $self->{s}->ok();
  }
  else {
    # Failure!
    $self->{s}->auto_done();
    $self->{s}->nok();
  }
}
1;
