package Virtualmin::Config::Plugin::SpamAssassin;
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
  my $self = $class->SUPER::new(name => 'SpamAssassin', %args);

  return $self;
}

sub actions {
  my $self = shift;

  $self->use_webmin();

  $self->spin();
  sleep 0.3;    # XXX Useless sleep, prevent spin from ending before it starts
  eval {
    foreign_require("init", "init-lib.pl");

    # Stop it, so a default install is small. Can be enabled during wizard.
    foreach my $service (qw(spamassassin spamd)) {
      init::disable_at_boot($service);
      $self->run_service_action('stop', $service)
        if (init::status_action($service) == 1);
    }
    $self->done(1);    # OK!
  };
  if ($@) {
    $log->error("Error configuring SpamAssassin: $@");
    $self->done(0);
  }
}

1;
