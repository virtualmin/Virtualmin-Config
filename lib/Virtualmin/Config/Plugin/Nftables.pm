package Virtualmin::Config::Plugin::Nftables;

# Configures the nftables firewall with a reasonable set of rules, managed
# by the Webmin nftables module on all supported systems.
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
  my $self = $class->SUPER::new(name => 'Nftables', %args);

  return $self;
}

sub actions {
  my $self = shift;

  $self->use_webmin();

  $self->spin();
  eval {
    unless (foreign_check("nftables")) {
      $log->info("Cannot configure nftables as Webmin nftables module is not installed");
      $self->done(2);
      return;
    }

    foreign_require("nftables", "nftables-lib.pl");
    if (my $err = nftables::check_nftables()) {
      $log->info("Cannot configure nftables: $err");
      $self->done(2);
      return;
    }

    # Stop and disable competing firewall services so they cannot clobber
    # the Webmin-managed ruleset. The distro nftables service is included,
    # because Webmin installs its own boot action, and, e.g. on Debian the
    # stock /etc/nftables.conf begins with 'flush ruleset' which would wipe
    # our rules if it ran after them at boot
    foreign_require('init', 'init-lib.pl');
    foreach my $service (qw(firewalld iptables netfilter-persistent ufw nftables)) {
      if (init::action_status($service)) {
        init::stop_action($service);
        init::disable_at_boot($service);
      }
    }

    my $err = nftables::save_profile_ruleset(
      'profile_hosting',
      'virtualmin',
      '*'
    );
    die "$err\n" if ($err);

    nftables::create_nftables_init();
    $err = nftables::apply_restore();
    die "$err\n" if ($err);

    $self->done(1);    # OK!
  };
  if ($@) {
    $log->error("Error configuring nftables: $@");
    $self->done(0);
  }
}

1;
