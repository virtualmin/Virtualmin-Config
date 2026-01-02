package Virtualmin::Config::Plugin::Firewalld;

# Enables firewalld and installs a reasonable set of rules.
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Firewalld', %args);

  return $self;
}

sub actions {
  my $self = shift;

  $self->use_webmin();

  $self->spin();
  my @services
    = qw(ssh smtp smtps smtp-submission ftp pop3 pop3s imap imaps http https dns mdns dns-over-tls);
  my @ports = qw(20/tcp 2222/tcp 10000-10100/tcp 20000/tcp 49152-65535/tcp);
  eval {
    foreign_require('init', 'init-lib.pl');
    init::enable_at_boot('firewalld');
    if (init::action_status('iptables')) {
      init::stop_action('iptables');
      init::disable_at_boot('iptables');
    }
    init::start_action('firewalld');

    my $firewall_cmd = has_command('firewall-cmd');
    if ($firewall_cmd) {
      my $default_zone = `$firewall_cmd --get-default-zone`;
      chomp($default_zone);
      $default_zone = 'public' if ($default_zone !~ /^[A-Za-z0-9_-]+$/);
      $self->logsystem("$firewall_cmd --set-default-zone $default_zone");
      foreach my $s (@services) {
        $self->logsystem("$firewall_cmd --zone=$default_zone --add-service=${s}");
        $self->logsystem(
          "$firewall_cmd --zone=$default_zone --permanent --add-service=${s}");
      }
      foreach my $s (@ports) {
        $self->logsystem("$firewall_cmd --zone=$default_zone --add-port=${s}");
        $self->logsystem(
          "$firewall_cmd --zone=$default_zone --permanent --add-port=${s}");
      }
      $self->logsystem("$firewall_cmd --complete-reload");
    }
    $self->done(1);    # OK!
  };
  if ($@) {
    $log->error("Error configuring Firewalld: $@");
    $self->done(0);
  }
}

1;
