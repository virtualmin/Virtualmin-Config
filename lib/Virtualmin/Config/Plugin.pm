package Virtualmin::Config::Plugin;
use strict;
use warnings;
use 5.010;

# Plugin base class, just runs stuff with spinner and status
use Virtualmin::Config;
use Term::Spinner::Color;

# XXX I don't like this, but can't figure out how to put it into
# $self->{spinner}
our $spinner;

sub new {
  my ($class, %args) = @_;
  my $self = {
    name    => $args{'name'} || '',
    depends => $args{'depends'} || [],
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
  $spinner = Term::Spinner::Color->new();
  #print $message . " " x (80 - length($message) - $spinner->{'frame_length'});
  print $message . " " x (80 - length($message));
  $spinner->auto_start();
}

sub done {
  my $self = shift;
  my $res = shift;
  $spinner->auto_done();
  if ($res) {
    # Success!
    $spinner->ok();
  }
  else {
    # Failure!
    $spinner->nok();
  }
}

1;
