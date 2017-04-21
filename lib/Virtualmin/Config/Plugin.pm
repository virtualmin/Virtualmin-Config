package Virtualmin::Config::Plugin;
use strict;
use warnings;
use 5.010;

# Plugin base class, just runs stuff with spinner and status
use Virtualmin::Config;
use Term::ANSIColor qw(:constants);
use Term::Spinner::Color;

# TODO I don't like this, but can't figure out how to put it into
# $self->{spinner}
our $spinner;
our $trust_unknown_referers = 1;
our $error_must_die = 1;

sub new {
  my ($class, %args) = @_;

  my $self = {
    name    => $args{name},
    depends => $args{depends},
  };
  bless $self, $class;

  return $self;
}

# Plugin short name, used in config definitions
sub name {
  my ($self. $name) = @_;
  if ( $name ) { $self->{name} = $name }
  return $self->{name};
}

# Return a ref to an array of plugins that have to run before this one.
# Dep resolution is very stupid. Don't do anything complicated.
sub depends {
  my ($self, $name) = @_;
  if ( $name ) { $self->{'depends'} = shift }
  return $self->{'depends'};
}

sub spin {
  my $self = shift;
  my $message = shift // "Configuring " . $self->name();
  $spinner = Term::Spinner::Color->new();
  print $message . " " x (79 - length($message) - $spinner->{'last_size'});
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

sub root {
  my $self = shift;

  $ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	$ENV{'MINISERV_CONFIG'} = $ENV{'WEBMIN_CONFIG'}."/miniserv.conf";
	open(my $CONF, "<", "$ENV{'WEBMIN_CONFIG'}/miniserv.conf") ||
	  die RED, "Failed to open miniserv.conf", RESET;
	my $root;
	while(<$CONF>) {
		if (/^root=(.*)/) {
			$root = $1;
		}
	}
	close($CONF);
	$root ||= "/usr/libexec/webmin";

  return $root;
}

1;
