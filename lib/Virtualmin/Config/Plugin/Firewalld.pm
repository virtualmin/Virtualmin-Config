package Virtualmin::Config::Plugin::Firewalld;

# Enables firewalld and installs a reasonable set of rules.
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
  my $self = $class->SUPER::new(name => 'Firewalld', %args);

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
  my @services = qw(ssh smtp smtps smtp-submission ftp pop3 pop3s imap imaps http https dns mdns dns-over-tls);
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
      $self->logsystem("$firewall_cmd --set-default-zone public");
      foreach my $s (@services) {
        $self->logsystem("$firewall_cmd --zone=public --add-service=${s}");
        $self->logsystem("$firewall_cmd --zone=public --permanent --add-service=${s}");
      }
      foreach my $s (@ports) {
        $self->logsystem("$firewall_cmd --zone=public --add-port=${s}");
        $self->logsystem("$firewall_cmd --zone=public --permanent --add-port=${s}");
      }
      $self->logsystem("$firewall_cmd --complete-reload");
    }
    $self->done(1);    # OK!
  };
  if ($@) {
    $self->done(0);
  }
}

1;
