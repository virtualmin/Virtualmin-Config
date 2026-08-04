#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use Cwd qw(abs_path);

BEGIN {
  package Log::Log4perl;
  sub import { }
  sub get_logger { return bless({ }, 'TestLogger'); }
  $INC{'Log/Log4perl.pm'} = 1;

  package TestLogger;
  sub info { }
  sub warn { }
  sub error { }
}

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));
unshift(@INC, File::Spec->catdir($root, 'lib'));
require Virtualmin::Config::Plugin::Quotas;

my $plugin = bless({ }, 'Virtualmin::Config::Plugin::Quotas');

# A disabled but supported filesystem should be enabled, rescanned, and
# verified through Webmin's structured Btrfs quota API.
{
  no warnings qw(redefine once);
  my @status = (
    { 'enabled' => 0, 'supported' => 1 },
    { 'enabled' => 1, 'supported' => 1, 'inconsistent' => 0 },
  );
  my (@enabled, @rescanned);
  local *Virtualmin::Config::Plugin::Quotas::foreign_require = sub { };
  local *quota::btrfs_quota_status = sub { return shift(@status); };
  local *quota::enable_btrfs_quotas = sub {
    @enabled = @_;
    return undef;
  };
  local *quota::rescan_btrfs_quotas = sub {
    @rescanned = @_;
    return undef;
  };

  ok(Virtualmin::Config::Plugin::Quotas::configure_btrfs_quotas(
       $plugin, '/home'),
     'disabled Btrfs quotas are enabled and verified');
  is_deeply(\@enabled, [ '/home', 0 ],
            'installer enables broadly compatible full qgroups');
  is_deeply(\@rescanned, [ '/home', 1 ],
            'installer waits for accounting rescan');
}

# Already-enabled quotas with inconsistent accounting only need a waited
# rescan before their final status is accepted.
{
  no warnings qw(redefine once);
  my @status = (
    { 'enabled' => 1, 'supported' => 1, 'inconsistent' => 1 },
    { 'enabled' => 1, 'supported' => 1, 'inconsistent' => 0 },
  );
  my $rescans = 0;
  local *Virtualmin::Config::Plugin::Quotas::foreign_require = sub { };
  local *quota::btrfs_quota_status = sub { return shift(@status); };
  local *quota::enable_btrfs_quotas = sub { die 'enable should not run'; };
  local *quota::rescan_btrfs_quotas = sub {
    $rescans++;
    return undef;
  };

  ok(Virtualmin::Config::Plugin::Quotas::configure_btrfs_quotas(
       $plugin, '/home'),
     'inconsistent Btrfs accounting is repaired');
  is($rescans, 1, 'inconsistent accounting triggers one waited rescan');
}

# Status-query failures must stop configuration and retain the actionable
# error returned by Webmin.
{
  no warnings qw(redefine once);
  local *Virtualmin::Config::Plugin::Quotas::foreign_require = sub { };
  local *quota::btrfs_quota_status = sub {
    return { 'supported' => 1, 'error' => 'permission denied' };
  };
  local *quota::enable_btrfs_quotas = sub { return undef; };
  local *quota::rescan_btrfs_quotas = sub { return undef; };

  my $ok = eval {
    Virtualmin::Config::Plugin::Quotas::configure_btrfs_quotas(
      $plugin, '/home');
    1;
  };
  ok(!$ok, 'Btrfs status errors fail quota configuration');
  like($@, qr/permission denied/,
       'Btrfs status error remains actionable');
}

# Simple quotas use first-owner accounting, which cannot reliably represent
# restored and reflinked Virtualmin mailbox data. Existing squotas must never
# be disabled implicitly because that would remove all qgroups and limits.
{
  no warnings qw(redefine once);
  my ($enabled, $rescanned) = (0, 0);
  local *Virtualmin::Config::Plugin::Quotas::foreign_require = sub { };
  local *quota::btrfs_quota_status = sub {
    return { 'supported' => 1, 'enabled' => 1, 'mode' => 'squota' };
  };
  local *quota::enable_btrfs_quotas = sub { $enabled++; return undef; };
  local *quota::rescan_btrfs_quotas = sub { $rescanned++; return undef; };

  my $ok = eval {
    Virtualmin::Config::Plugin::Quotas::configure_btrfs_quotas(
      $plugin, '/home');
    1;
  };
  ok(!$ok, 'simple Btrfs quotas are rejected');
  like($@, qr/requires full qgroup accounting/,
       'simple-quota failure explains the required mode');
  is($enabled, 0, 'existing simple quotas are not destructively re-enabled');
  is($rescanned, 0, 'simple quotas are not rescanned as full quotas');
}

done_testing();
