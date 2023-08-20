package Virtualmin::Config::Plugin::ClamAV;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';
use Time::HiRes qw( sleep );

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'ClamAV', %args);

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
  sleep 0.2;                # XXX Pause to allow spin to start.
  eval {
    # Make sure freshclam is not disabled
    my $fcconf = "/etc/sysconfig/freshclam";
    if (-r $fcconf) {
      my $lref = read_file_lines($fcconf);
      foreach my $l (@$lref) {
        if ($l =~ /^FRESHCLAM_DELAY=disabled/) {
          $l = "#$l";
        }
      }
      flush_file_lines($fcconf);
    }

    # Remove idiotic Example line from clamd scan.conf
    my $scanconf = "/etc/clamd.d/scan.conf";
    if (-r $scanconf) {
      my $lref = read_file_lines($scanconf);
      foreach my $l (@$lref) {
        if ($l =~ /^Example/) {
          $l = "#$l";
        }
        $l =~ s/#+\s*(LocalSocket\s.*)$/$1/;
      }
      flush_file_lines($scanconf);
    }

    # Do not run freshclam if there is a daemon
    foreign_require('init');
    if (!init::action_status('clamav-freshclam')) {
      if (has_command('freshclam')) {
        $self->logsystem("freshclam");
      }
    }
    else {
      # Restart daemon to refresh the database in background,
      # it will have higher chances of avoiding post-install
      # false positive errors on Debian systems
      if (init::action_status('clamav-freshclam') == 2) {

        # Restart it only if already running
        init::restart_action('clamav-freshclam');
      }
      elsif (init::action_status('clamav-freshclam') == 1) {

        # We have a daemon but it's not running, then run
        # freshclam to avoid issues on RHEL system (dumb!)
        if (has_command('freshclam')) {
          $self->logsystem("freshclam");
        }
      }
    }

    $self->done(1);    # OK!
  };
  if ($@) {
    $self->done(0);
  }
}

sub tests {
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

  # RHEL/CentOS/Fedora
  # Start clamd@scan and run clamdscan just to prime the damned thing.
  foreign_require("init", "init-lib.pl");
  $self->done(1);
  eval {
    if ($gconfig{'os_type'} eq 'redhat-linux') {
      if (init::action_status('clamd@scan')) {
        init::enable_at_boot('clamd@scan');
        init::start_action('clamd@scan');
      }
      elsif (init::action_status('clamd')) {
        init::enable_at_boot('clamd');
        init::start_action('clamd');
      }
      sleep 60;    # XXX This is ridiculous. But, clam is ridiculous.
          # If RHEL/CentOS/Fedora, the clamav packages don't work, by default.
      if (!-e '/etc/clamd.conf') {
        eval { symlink('/etc/clamd.d/scan.conf', '/etc/clamd.conf'); };
      }
      my $res = `clamdscan --quiet - < /etc/webmin/miniserv.conf`;
      if ($res) { die 1; }
      if (init::action_status('clamd@scan')) {
        init::stop_action('clamd@scan');
      }
      elsif (init::action_status('clamd')) {
        init::stop_action('clamd');
      }
    }
    elsif ($gconfig{'os_type'} eq 'debian-linux') {
      init::enable_at_boot('clamav-daemon');
      init::start_action('clamav-daemon');
      sleep 60;
      $self->logsystem("clamdscan --quiet - < /etc/webmin/miniserv.conf");
      init::stop_action('clamav-daemon');
    }
    $self->done(0);
  };
  if ($@) {
    $self->done(0);
  }
}

1;
