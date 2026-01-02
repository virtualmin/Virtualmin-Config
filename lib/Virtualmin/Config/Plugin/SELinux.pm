package Virtualmin::Config::Plugin::SELinux;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';
use Time::HiRes qw( sleep );    # XXX Figure out how to not need this.

our $config_directory;
our (%gconfig, %miniserv);

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'SELinux', %args);

  return $self;
}

sub actions {
  my $self = shift;

  $self->use_webmin();

  if (!-x "/usr/sbin/setsebool") {
    log->info("SELinux doesn't seem to be installed. Skipping.");
    return 1;
  }

  $self->spin();
  sleep 0.3;    # XXX Useless sleep, prevent spin from ending before it starts
  eval {

    $self->done(1);    # OK!
  };
  if ($@) {
    $log->error("Error configuring SELinux: $@");
    $self->done(0);
  }
}

1;
