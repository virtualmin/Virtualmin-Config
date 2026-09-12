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

    # Stop and disable firewall services that can replace the nftables
    # ruleset managed through the standard service.
    foreign_require('init', 'init-lib.pl');
    my @services = qw(firewalld iptables netfilter-persistent ufw);
    foreach my $service (@services) {
      if (init::action_status($service)) {
        $self->run_service_action('stop', $service);
        init::disable_at_boot($service);
      }
    }

    my $err = nftables::save_profile_ruleset(
      nftables::profile_base_table_name('virtualmin'),
      'virtualmin',
      '*'
    );
    die "$err\n" if ($err);

    $err = nftables::apply_restore();
    die "$err\n" if ($err);

    # Enable boot loading only after the saved configuration applies.
    nftables::enable_nftables_at_boot();

    $self->done(1);    # OK!
  };
  if ($@) {
    $log->error("Error configuring nftables: $@");
    $self->done(0);
  }
}

1;
