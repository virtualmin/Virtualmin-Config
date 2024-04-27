package Virtualmin::Config::Plugin::Nginx;
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
  my $self = $class->SUPER::new(name => 'Nginx', %args);

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
    foreign_require('init', 'init-lib.pl');

    init::enable_at_boot('nginx');
    init::start_action('nginx');

    my %vconfig = foreign_config("virtual-server");
    $vconfig{'web'}                  = 0;
    $vconfig{'ssl'}                  = 0;
    $vconfig{'avail_virtualmin-dav'} = '';
    $vconfig{'backup_feature_ssl'}   = 0;

    if ($self->bundle() && $self->bundle() eq "MiniLEMP") {
      $vconfig{'plugins'} = 'virtualmin-nginx virtualmin-nginx-ssl';
    }
    else {
      $vconfig{'plugins'}
        = 'virtualmin-awstats virtualmin-nginx virtualmin-nginx-ssl';
    }
    save_module_config(\%vconfig, "virtual-server");

    # Fix Nginx to start correctly after reboot
    my $tmp = transname();
    write_file_contents($tmp, "[Unit]\nStartLimitBurst=2\nStartLimitIntervalSec=15\n\n[Service]\nRestart=on-failure\nRestartSec=5s\nSuccessExitStatus=SIGKILL");
    $self->logsystem("systemd-run --collect --pty --service-type=oneshot --setenv=SYSTEMD_EDITOR=tee --system -- sh -c 'systemctl edit --force --system -- nginx.service < $tmp'");
    $self->logsystem("systemctl daemon-reload");
    $self->logsystem("systemctl restart nginx.service");

    $self->done(1);    # OK!
  };
  if ($@) {
    $self->done(0);
  }
}

1;
