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
  my $s = Term::Spinner::Color->new();
  print $message . " " x (80 - $message - $s{'frame_length'});
  $s->auto_start();
}

sub done {
  my $self = shift;
  my $res = shift;
  if $res {
    # Success!
    $s->auto_done();
    $s->ok();
    print "\n";
  }
  else {
    # Failure!
    $s->auto_done();
    $s->nok();
    print "\n";
  }
}
1;
