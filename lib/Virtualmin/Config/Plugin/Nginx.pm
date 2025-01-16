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
  sleep 0.3;
  eval {

    $self->logsystem("systemctl enable nginx.service");
    $self->logsystem("systemctl restart nginx.service");

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
    my $systemd_path = "/etc/systemd/system";
    if (-d $systemd_path) {
      write_file_contents($systemd_path . "/nginx.timer",
        "[Unit]\n" .
        "Description=Start Nginx after boot\n" .
        "PartOf=nginx.service\n\n" .
        "[Timer]\n" .
        "OnActiveSec=15\n" .
        "Unit=nginx.service\n\n" .
        "[Install]\n" .
        "WantedBy=multi-user.target\n");
      $self->logsystem("systemctl daemon-reload");
      $self->logsystem("systemctl enable nginx.timer");
      $self->logsystem("systemctl restart nginx.timer");
    }

    $self->done(1);    # OK!
  };
  if ($@) {
    $self->done(0);
  }
}

1;
