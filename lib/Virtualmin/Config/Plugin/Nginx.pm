package Virtualmin::Config::Plugin::Nginx;
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
  my $self = $class->SUPER::new(name => 'Nginx', %args);

  return $self;
}

sub actions {
  my $self = shift;
  $self->use_webmin();

  $self->spin();
  sleep 0.3;
  eval {

    # Stop configuration when a service command fails to avoid false success
    my $run_systemctl = sub {
      my ($command, $description) = @_;
      $self->logsystem("systemctl $command") == 0
        || die "Failed to $description";
    };

    $run_systemctl->("enable nginx.service", "enable Nginx");
    $run_systemctl->("restart nginx.service", "restart Nginx");

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
      $run_systemctl->("daemon-reload", "reload systemd");
      $run_systemctl->("enable nginx.timer", "enable the Nginx timer");
      $run_systemctl->("restart nginx.timer", "restart the Nginx timer");
    }

    $self->done(1);    # OK!
  };
  if ($@) {
    $log->error("Error configuring Nginx: $@");
    $self->done(0);
  }
}

1;
