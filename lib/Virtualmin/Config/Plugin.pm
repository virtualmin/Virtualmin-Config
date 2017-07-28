package Virtualmin::Config::Plugin;
use strict;
use warnings;
use 5.010_001;
use Time::HiRes qw( sleep );

# Plugin base class, just runs stuff with spinner and status
use Virtualmin::Config;
use Term::ANSIColor qw(:constants);
use Term::Spinner::Color;

# TODO I don't like this, but can't figure out how to put it into
# $self->{spinner}
our $spinner;

our $trust_unknown_referers = 1;
our $error_must_die         = 1;

our $count = 1;

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;

  my $self = {name => $args{name}, depends => $args{depends}, total => $args{total}};
  bless $self, $class;

  return $self;
}

# Plugin short name, used in config definitions
sub name {
  my ($self, $name) = @_;
  if ($name) { $self->{name} = $name }
  return $self->{name};
}

# Return a ref to an array of plugins that have to run before this one.
# Dep resolution is very stupid. Don't do anything complicated.
sub depends {
  my ($self, $name) = @_;
  if ($name) { $self->{depends} = shift }
  return $self->{depends};
}

# Total number of plugins being run for running count
sub total {
  my ($self, $total) = @_;
  if ($total) { $self->{total} = shift }
  return $self->{total};
}

sub spin {
  my $self    = shift;
  my $name    = $self->name();
  my $message = shift // "Configuring " . $name;
  $message = "[" . YELLOW . $count . RESET . "/" . GREEN . $self->total() .
    RESET . "] " . $message;
  my $color_correction = length(YELLOW . RESET . GREEN . RESET);
  $count++;
  $log->info($message);
  $spinner = Term::Spinner::Color->new();
  $message = $message . " " x (79 - length($message) - $spinner->{'last_size'});
  print $message;
  $spinner->auto_start();
}

sub done {
  my $self = shift;
  my $res  = shift;
  $spinner->auto_done();
  if ($res) {

    # Success!
    $log->info("Succeeded");
    $spinner->ok();
  }
  else {
    # Failure!
    $log->warn("Failed");
    $spinner->nok();
  }
}

sub root {
  my $self = shift;

  $ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
  $ENV{'WEBMIN_VAR'}    ||= "/var/webmin";
  $ENV{'MINISERV_CONFIG'} = $ENV{'WEBMIN_CONFIG'} . "/miniserv.conf";
  open(my $CONF, "<", "$ENV{'WEBMIN_CONFIG'}/miniserv.conf") || die RED,
    "Failed to open miniserv.conf", RESET;
  my $root;
  while (<$CONF>) {
    if (/^root=(.*)/) {
      $root = $1;
    }
  }
  close($CONF);
  $root ||= "/usr/libexec/webmin";

  return $root;
}

# logsystem(command)
# Similar to system() or backticks but with logging.
# Runs a single system command, and returns the result code.
sub logsystem {
  my $self = shift;
  my $cmd = shift;

  my $res = `$cmd 2>&1` // "[]";
  $log->info("Code: $? Result: $res");
  return $?;
}

1;
