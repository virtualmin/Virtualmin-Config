package Virtualmin::Config::Plugin::ClamAV;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';
use Time::HiRes qw( sleep );

our $config_directory;
our (%gconfig, %miniserv);

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'ClamAV', %args);

  return $self;
}

sub actions {
  my $self = shift;

  $self->use_webmin();

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

    # A newly installed freshclam daemon updates in the background. On EL 10,
    # clamd can be started before that first download finishes and then fails
    # because there are no usable databases. Always seed the database
    # synchronously before relying on the updater daemon. Both main and daily
    # (.cvd, .cld or a legacy .inc directory) are required, as the Debian
    # clamav-daemon unit refuses to start without either of them
    foreign_require('init');
    my $has_databases = sub {
      foreach my $db ('main', 'daily') {
        my @found = grep { -e "/var/lib/clamav/$db.$_" } ('cvd', 'cld', 'inc');
        return 0 if (!@found);
      }
      return 1;
    };
    # On a fresh EL install, RPM can create the database directory before
    # the clamupdate system account exists and leave it owned by root, which
    # stops freshclam from ever writing a database. Fix this regardless of
    # whether any databases were shipped by a package, as they are left owned
    # by root too
    my @clamupdate = getpwnam('clamupdate');
    my @dbdir = stat('/var/lib/clamav');
    if (@clamupdate && @dbdir &&
        ($dbdir[4] != $clamupdate[2] || $dbdir[5] != $clamupdate[3])) {
      set_ownership_permissions($clamupdate[2], $clamupdate[3], undef,
                                '/var/lib/clamav') ||
        die "Unable to set ownership on the ClamAV database directory";
    }
    if (!$has_databases->() && has_command('freshclam')) {
      # Stop a running updater daemon so the one-off run can take its lock
      my $freshclam_running =
        init::status_action('clamav-freshclam') == 1;
      if ($freshclam_running) {
        my ($ok, $out) = init::stop_action('clamav-freshclam');
        $ok || die "Unable to stop the ClamAV updater daemon: $out";
      }
      my $freshclam_status = $self->logsystem("freshclam");
      # Restore the updater daemon regardless of the outcome
      my ($started, $start_out) = (1, '');
      ($started, $start_out) = init::start_action('clamav-freshclam')
        if ($freshclam_running);
      $freshclam_status == 0 ||
        die "Unable to download the initial ClamAV database";
      $has_databases->() || die "No ClamAV database was downloaded";
      $started || die "Unable to start the ClamAV updater daemon: $start_out";
    }
    elsif (!init::action_status('clamav-freshclam')) {
      if (has_command('freshclam')) {
        $self->logsystem("freshclam");
      }
    }
    else {
      # Restart daemon to refresh the database in background,
      # it will have higher chances of avoiding post-install
      # false positive errors on Debian systems
      if (init::status_action('clamav-freshclam') == 1) {
        # Restart it only if currently running
        $self->run_service_action('restart', 'clamav-freshclam');
      }
      else {
        # When the updater is stopped, refresh synchronously without
        # changing its runtime state
        if (has_command('freshclam')) {
          $self->logsystem("freshclam");
        }
      }
    }

    $self->done(1);    # OK!
  };
  if ($@) {
    $log->error("Failed to configure ClamAV: $@");
    $self->done(0);
  }
}

sub tests {
  my $self = shift;

  $self->use_webmin();

  # RHEL/CentOS/Fedora
  # Start clamd@scan and run clamdscan just to prime the damned thing.
  foreign_require("init", "init-lib.pl");
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
      # Stop the daemon before reporting the result, so that a failed
      # test scan does not leave it running
      my $scan_status =
        $self->logsystem("clamdscan --quiet - < /etc/webmin/miniserv.conf");
      if (init::action_status('clamd@scan')) {
        init::stop_action('clamd@scan');
      }
      elsif (init::action_status('clamd')) {
        init::stop_action('clamd');
      }
      $scan_status == 0 || die "ClamAV test scan failed";
    }
    elsif ($gconfig{'os_type'} eq 'debian-linux') {
      init::enable_at_boot('clamav-daemon');
      init::start_action('clamav-daemon');
      sleep 60;
      my $scan_status =
        $self->logsystem("clamdscan --quiet - < /etc/webmin/miniserv.conf");
      init::stop_action('clamav-daemon');
      $scan_status == 0 || die "ClamAV test scan failed";
    }
    else {
      # No test scan is available for this OS, so do not claim success
      $log->warn("ClamAV test is not supported on this operating system");
      $self->done(2);
      return;
    }
    $self->done(1);
  };
  if ($@) {
    $log->error("Failed to test ClamAV: $@");
    $self->done(0);
  }
}

1;
