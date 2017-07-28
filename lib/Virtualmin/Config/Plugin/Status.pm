package Virtualmin::Config::Plugin::Status;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Status', %args);

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. XXX Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;

  use Cwd;
  my $cwd  = getcwd();
  my $root = $self->root();
  chdir($root);
  $0 = "$root/virtual-server/config-system.pl";
  push(@INC, $root);
  eval 'use WebminCore';    ## no critic
  init_config();

  $self->spin();
  eval {
    foreign_require("status", "status-lib.pl");
    $status::config{'sched_mode'} = 1;
    $status::config{'sched_int'}    ||= 5;
    $status::config{'sched_offset'} ||= 0;
    save_module_config(\%status::config, 'status');
    status::setup_cron_job();
    $self->done(1);         # OK!
  };
  if ($@) {
    $self->done(0);
  }
}

1;
