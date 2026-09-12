use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;

require_ok('Virtualmin::Config::Plugin::Nftables');

sub run_nftables_plugin
{
  my ($apply_error) = @_;
  my (@stopped, @disabled, @profile, @order, @done);
  my $plugin = bless({}, 'Virtualmin::Config::Plugin::Nftables');

  local *Virtualmin::Config::Plugin::Nftables::use_webmin = sub { };
  local *Virtualmin::Config::Plugin::Nftables::spin = sub { };
  local *Virtualmin::Config::Plugin::Nftables::done = sub {
    my ($self, $status) = @_;
    push(@done, $status);
  };
  local *Virtualmin::Config::Plugin::Nftables::foreign_check = sub { 1 };
  local *Virtualmin::Config::Plugin::Nftables::foreign_require = sub { };
  local *Virtualmin::Config::Plugin::Nftables::run_service_action = sub {
    my ($self, $action, $service) = @_;
    push(@stopped, $service) if ($action eq 'stop');
    return 1;
  };
  local *init::action_status = sub { 1 };
  local *init::disable_at_boot = sub { push(@disabled, $_[0]); };
  local *nftables::check_nftables = sub { return; };
  local *nftables::profile_base_table_name = sub {
    return 'webmin_profile_hosting';
  };
  local *nftables::save_profile_ruleset = sub {
    @profile = @_;
    push(@order, 'save');
    return;
  };
  local *nftables::apply_restore = sub {
    push(@order, 'apply');
    return $apply_error;
  };
  local *nftables::enable_nftables_at_boot = sub {
    push(@order, 'system-boot');
  };
  $plugin->actions();

  return {
    stopped  => \@stopped,
    disabled => \@disabled,
    profile  => \@profile,
    order    => \@order,
    done     => \@done,
  };
}

my $system = run_nftables_plugin();
is_deeply(
  $system->{stopped},
  [qw(firewalld iptables netfilter-persistent ufw)],
  'system-service mode leaves nftables running'
);
is_deeply(
  $system->{disabled},
  [qw(firewalld iptables netfilter-persistent ufw)],
  'system-service mode leaves nftables enabled'
);
is_deeply(
  $system->{profile},
  ['webmin_profile_hosting', 'virtualmin', '*'],
  'system-service mode uses the prefixed profile table name'
);
is_deeply(
  $system->{order},
  [qw(save apply system-boot)],
  'system service is enabled only after a successful apply'
);
is_deeply($system->{done}, [1], 'system-service setup succeeds');

my $invalid = run_nftables_plugin('invalid ruleset');
is_deeply(
  $invalid->{order},
  [qw(save apply)],
  'failed apply does not enable the system service'
);
is_deeply($invalid->{done}, [0], 'failed apply reports setup failure');

done_testing();
