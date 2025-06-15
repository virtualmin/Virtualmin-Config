package Virtualmin::Config::Plugin::SpamAssassin;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';
use Time::HiRes qw( sleep );    # XXX Figure out how to not need this.

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'SpamAssassin', %args);

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
  push(@INC, "$root/vendor_perl");
  eval 'use WebminCore';    ## no critic
  init_config();

  $self->spin();
  sleep 0.3;    # XXX Useless sleep, prevent spin from ending before it starts
  eval {
    foreign_require("init", "init-lib.pl");

    # Stop it, so a default install is small. Can be enabled during wizard.
    init::disable_at_boot("spamassassin");
    init::stop_action("spamassassin");
    init::disable_at_boot("spamd");
    init::stop_action("spamd");
    $self->done(1);    # OK!
  };
  if ($@) {
    $log->error("Error configuring SpamAssassin: $@");
    $self->done(0);
  }
}

1;
