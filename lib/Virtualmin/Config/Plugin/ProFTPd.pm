package Virtualmin::Config::Plugin::ProFTPd;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

sub new {
  my $class = shift;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'ProFTPd');

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
    foreign_require("init", "init-lib.pl");
    init::enable_at_boot("proftpd");
    init::restart_action("proftpd");
    if ($gconfig{'os_type'} eq 'freebsd') {

      # This directory is missing on FreeBSD
      make_dir("/var/run/proftpd", oct(755));
    }

    # UseIPv6 doesn't work on FreeBSD
    foreign_require("proftpd", "proftpd-lib.pl");
    my $conf = &proftpd::get_config();
    proftpd::save_directive("UseIPv6", [], $conf, $conf);
    flush_file_lines();

    $self->done(1);    # OK!
  };
  if ($@) {
    $self->done(0);    # NOK!
  }
}

1;
