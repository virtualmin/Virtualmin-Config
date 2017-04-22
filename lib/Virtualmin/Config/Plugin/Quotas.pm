package Virtualmin::Config::Plugin::Quotas;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

sub new {
  my $class = shift;
  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Quotas');

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. XXX Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;

  use Cwd;
  my $cwd = getcwd();
  my $root = $self->root();
  chdir($root);
  $0 = "$root/init-system.pl";
  push(@INC, $root);
  eval 'use WebminCore'; ## no critic
  init_config();

  $self->spin();
  eval {
  foreign_require("mount", "mount-lib.pl");
	mkdir("/home", 0755) if (!-d "/home");
	my ($dir, $dev, $type, $opts) = mount::filesystem_for_dir("/home");
	mount::parse_options($type, $opts);
	if (running_in_zone() || &running_in_vserver()) {
		#print STDERR "Skipping quotas for Vserver or Zones systems\n";
		return;
	}
	elsif ($gconfig{'os_type'} =~ /-linux$/) {
		$mount::options{'usrquota'} = '';
		$mount::options{'grpquota'} = '';
	}
	elsif ($gconfig{'os_type'} =~ /freebsd|netbsd|openbsd|macos/) {
		# Skip if quotas are not enabled--requires a kernel rebuild
		my $quotav = `quota -v`;
		if ( ! $quotav =~ /none$/ ) {
			$mount::options{'rw'} = '';
			$mount::options{'userquota'} = '';
			$mount::options{'groupquota'} = '';
		}
		else {
			#print "Skipping quotas: Required kernel support is not enabled.\n";
			return;
		}
	}
	elsif ($gconfig{'os_type'} =~ /solaris/) {
		$mount::options{'quota'} = '';
	}
	else {
		#print STDERR "Don't know how to enable quotas on $gconfig{'real_os_type'} ($gconfig{'os_type'})\n";
	}
	$opts = mount::join_options($type);
	my @mounts = mount::list_mounts();
	my $idx;
	for($idx=0; $idx<@mounts; $idx++) {
		last if ($mounts[$idx]->[0] eq $dir);
	}
	mount::change_mount($idx, $mounts[$idx]->[0],
			$mounts[$idx]->[1],
			$mounts[$idx]->[2],
			$opts,
			$mounts[$idx]->[4],
			$mounts[$idx]->[5]);
	my $err = mount::remount_dir($dir, $dev, $type, $opts);
	if ($err) {
		print STDERR "\nThe filesystem $dir could not be remounted with quotas enabled. You may need to reboot your system, and then enable quotas in the Disk Quotas module.\n";
	}
	else {
  # Activate quotas
		foreign_require("quota", "quota-lib.pl");
		quota::quotaon($dir, 3);
	}
  $self->done(1); # OK!
  };
  if ($@) {
    $self->done(0);
  }
}

1;
