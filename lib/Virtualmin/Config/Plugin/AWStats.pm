package Virtualmin::Config::Plugin::AWStats;
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
  my $self = $class->SUPER::new(name => 'AWStats', %args);

  return $self;
}

sub actions {
  my $self = shift;

  $self->use_webmin();

  $self->spin();
  sleep 0.2;                # XXX Pause to allow spin to start.
  eval {
    # Remove cronjobs for awstats on Debian/Ubuntu
    foreign_require("cron");
    my @jobs = cron::list_cron_jobs();
    my @dis  = grep {
      $_->{'command'}
        =~ /\/usr\/share\/awstats\/tools\/(update|buildstatic)\.sh/
        && $_->{'active'}
    } @jobs;
    if (@dis) {
      foreach my $job (@dis) {
        $job->{'active'} = 0;
        cron::change_cron_job($job);
      }
    }

    # Comment out cron job for awstats on CentOS/RHEL
    my $file = '/etc/cron.hourly/awstats';
    if (-r $file) {
      my $lref = read_file_lines($file);
      foreach my $l (@$lref) {
        if ($l !~ /^\s*#/) {
          $l = "#" . $l;
        }
      }
      flush_file_lines($file);
    }
  };
  if ($@) {
    $self->done(0);
  }
  else {
    # If system doesn't have AWStats support, disable it
    if (foreign_check("virtualmin-awstats")) {
      my %awstats_config = foreign_config("virtualmin-awstats");
      if ($awstats_config{'awstats'} && !-r $awstats_config{'awstats'}) {
        $self->done(2);    # Not installed!
      }
      else {
        $self->done(1);    # OK
      }
    }
    else {
      $self->done(2);      # Not installed!
    }
  }
}

1;
