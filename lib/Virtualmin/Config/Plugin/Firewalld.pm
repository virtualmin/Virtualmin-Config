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
  eval {
    my @services = qw(ssh smtp ftp pop3 pop3s imap imaps http https);
    my @tcpports
      = qw(submission domain ftp-data 2222 10000-10010 20000);
    my @udpports = qw(domain);

    foreign_require('init', 'init-lib.pl');
    init::enable_at_boot('firewalld');
    if (init::action_status('iptables')) {
      init::stop_action('iptables');
      init::disable_at_boot('iptables');
    }

    if (has_command('firewall-cmd')) {
      foreach my $s (@services) {
        $self->logsystem("firewall-cmd --quiet --zone=public --add-service=${s}");
        $self->logsystem("firewall-cmd --quiet --zone=public --permanent --add-service=${s}");
      }
      foreach my $p (@tcpports) {
        $self->logsystem("firewall-cmd --zone=public --add-port=${p}/tcp");
        $self->logsystem("firewall-cmd --zone=public --permanent --add-port=${p}/tcp");
      }
      foreach my $p (@udpports) {
        $self->logsystem("firewall-cmd --zone=public --add-port=${p}/udp");
        $self->logsystem("firewall-cmd --zone=public --permanent --add-port=${p}/udp");
      }
      $self->logsystem("firewall-cmd --set-default-zone public");
    }

    $self->done(1);    # OK!
  };
  if ($@) {
    $self->done(0);
  }
}

1;
