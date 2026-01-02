package Virtualmin::Config::Plugin::Etckeeper;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our (%gconfig, %miniserv);

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Etckeeper', %args);

  return $self;
}

sub actions {
  my $self = shift;

  $self->use_webmin();

  $self->spin();

  # Configure etckeeper on RHEL
  if (&has_command('etckeeper')) {
    if ($gconfig{'os_type'} eq 'redhat-linux' ||
        $gconfig{'os_type'} eq "suse-linux") {
      $self->logsystem("etckeeper init");
      $self->logsystem("systemctl enable etckeeper.timer");
      $self->logsystem("systemctl start etckeeper.timer");
    }
    $self->done(1);         # OK!
  }
  else {
    $self->done(2);         # Not installed but should have been
  }
}

1;

