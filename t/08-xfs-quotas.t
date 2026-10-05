use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;

BEGIN {
  # Keep the mount-option tests independent of logging and host setup.
  package Log::Log4perl;
  sub import { }
  sub get_logger { return bless({}, 'XfsQuotaTestLogger'); }
  $INC{'Log/Log4perl.pm'} = 1;

  package XfsQuotaTestLogger;
  our @errors;
  sub error { push(@errors, $_[1]); }

  package main;
  *CORE::GLOBAL::mkdir = sub { return 1; };
}

require_ok('Virtualmin::Config::Plugin::Quotas');

# configured_options(type, options)
# Run quota setup through the fstab write, stopping before host changes.
sub configured_options {
  my ($type, $options) = @_;
  my (@saved, @remounted);
  local %Virtualmin::Config::Plugin::Quotas::gconfig =
    (os_type => 'redhat-linux');
  local %mount::options;
  local @XfsQuotaTestLogger::errors;
  local $ENV{'QUOTA_FAILED'};

  # Replace Webmin and system operations with an in-memory root mount.
  local *Virtualmin::Config::Plugin::Quotas::use_webmin = sub { };
  local *Virtualmin::Config::Plugin::Quotas::spin = sub { };
  local *Virtualmin::Config::Plugin::Quotas::done = sub { };
  local *Virtualmin::Config::Plugin::Quotas::foreign_require = sub { };
  local *Virtualmin::Config::Plugin::Quotas::running_in_zone = sub { 0 };
  local *Virtualmin::Config::Plugin::Quotas::running_in_vserver = sub { 0 };
  local *mount::filesystem_for_dir = sub {
    return ('/', '/dev/test-root', $type, $options);
  };
  local *mount::parse_options = sub {
    %mount::options = map {
      my ($key, $value) = split(/=/, $_, 2);
      ($key, $value // '');
    } split(/,/, $_[1]);
  };
  local *mount::join_options = sub {
    return join(',', map {
      $_ . (length($mount::options{$_}) ? "=$mount::options{$_}" : '');
    } sort keys %mount::options);
  };
  local *mount::list_mounts = sub {
    return (['/', 'UUID=test-root', $type, $options, 0, 'yes']);
  };
  local *mount::change_mount = sub { @saved = @_; };
  local *mount::remount_dir = sub {
    @remounted = @_;
    die "Stopped before remount and bootloader changes\n";
  };

  # The controlled stop prevents any remount, GRUB update, or quota command.
  my $plugin = bless({}, 'Virtualmin::Config::Plugin::Quotas');
  $plugin->actions();
  is_deeply(\@XfsQuotaTestLogger::errors,
    ["Error configuring quotas: Stopped before remount and bootloader changes\n"],
    'setup reaches the remount boundary without an earlier error');
  is_deeply([@saved[0..3, 5..6]],
    [0, '/', 'UUID=test-root', $type, 0, 'yes'],
    'fstab device and non-option fields are preserved');
  is_deeply(\@remounted, ['/', '/dev/test-root', $type, $saved[4]],
    'remount receives the same options as fstab');
  return $saved[4];
}

# Cover fresh setup, old installer output, and kernel-reported aliases.
my @cases = (
  ['disabled quotas', 'rw,noquota,relatime', 'gquota,relatime,rw,uquota'],
  ['redundant aliases',
    'grpquota,attr2,rw,logbsize=32k,quota,usrquota,relatime,seclabel,logbufs=8,inode64',
    'attr2,gquota,inode64,logbsize=32k,logbufs=8,relatime,rw,seclabel,uquota'],
  ['native aliases', 'rw,uquota,gquota', 'gquota,rw,uquota'],
  ['accounting without enforcement', 'rw,uqnoenforce,gqnoenforce',
    'gquota,rw,uquota'],
  ['existing project quotas', 'rw,usrquota,grpquota,prjquota',
    'gquota,pquota,rw,uquota'],
);
for my $case (@cases) {
  subtest $case->[0] => sub {
    my $options = configured_options('xfs', $case->[1]);
    is($options, $case->[2], 'XFS uses only native quota aliases');
    is(configured_options('xfs', $options), $options,
      'repeated configuration does not add quota aliases');
  };
}

# Ext filesystems still need their existing generic quota mount options.
subtest 'ext4 retains generic quota setup' => sub {
  is(configured_options('ext4', 'rw,relatime'),
    'grpquota,quota,relatime,rw,usrquota',
    'ext4 quota options are unchanged');
};

done_testing();
