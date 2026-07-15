package Virtualmin::Config::Plugin::Quotas;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

$| = 1;

our $config_directory;
our (%gconfig, %miniserv);

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Quotas', %args);

  return $self;
}

sub actions {
  my $self = shift;

  $self->use_webmin();

  $self->spin();
  eval {
    my $res = 1;
    foreign_require("mount", "mount-lib.pl");
    mkdir("/home", 0755) if (!-d "/home");
    my ($dir, $dev, $type, $opts) = mount::filesystem_for_dir("/home");

    # Remove noquota, if it is present
    $opts = join(',', grep { !/noquota/ } (split(/,/, $opts)));

    mount::parse_options($type, $opts);
    if (running_in_zone() || running_in_vserver()) {

      #print STDERR "Skipping quotas for Vserver or Zones systems\n";
      return;
    }
    elsif ($type eq 'btrfs') {
      # Check if Btrfs quotas are already enabled
      my $quota_status = `btrfs qgroup show $dir 2>&1`;
      if ($quota_status =~ /ERROR.*not enabled/) {
          # Enable Btrfs quotas
          $self->logsystem("btrfs quota enable $dir");
      }
      $res = 1;  # Indicate success
    }
    elsif ($gconfig{'os_type'} =~ /-linux$/) {
      $mount::options{'usrquota'} = '';
      $mount::options{'grpquota'} = '';
      $mount::options{'quota'}    = '';
    }
    elsif ($gconfig{'os_type'} =~ /freebsd|netbsd|openbsd|macos/) {

      # Skip if quotas are not enabled--requires a kernel rebuild
      my $quotav = `quota -v`;
      if ($quotav !~ /none$/) {
        $mount::options{'rw'}         = '';
        $mount::options{'userquota'}  = '';
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
    if ($type eq 'btrfs') {
        # No need to remount or activate quotas for Btrfs
        $res = 1;  # Indicate success
    }
    else {
      $opts = mount::join_options($type);
      my @mounts = mount::list_mounts();
      my $idx;
      for ($idx = 0; $idx < @mounts; $idx++) {
        last if ($mounts[$idx]->[0] eq $dir);
      }
      mount::change_mount(
        $idx,
        $mounts[$idx]->[0],
        $mounts[$idx]->[1],
        $mounts[$idx]->[2],
        $opts,
        $mounts[$idx]->[4],
        $mounts[$idx]->[5]
      );
      my $err = mount::remount_dir($dir, $dev, $type, $opts);
      if ($type ne "ext4" || $err) {
        my $xfs   = $type eq 'xfs';
        my $smsg1 = "\b" x 7 . " " x 7;
        my $smsg2 = " " x ($xfs ? 26 : 34);
        my $msg1
          = "\nThe filesystem $dir could not be remounted with quotas enabled.\n";
        my $msg2
          = $xfs
          ? "You will need to reboot your system to enable quotas."
          : "You may need to reboot your system, and/or enable quotas\nmanually in Webmin/System/Disk Quotas module.";
        $res = 2;
        my $prt_std_err = 1;
        if ($xfs) {
          # Update configuration
          my $grub_def_file = "/etc/default/grub";
          if (-r $grub_def_file) {
            my %grub;
            &read_env_file($grub_def_file, \%grub) || ($res = 0);
            my $k;
            if (exists($grub{'GRUB_CMDLINE_LINUX_DEFAULT'})) {
              $k = 'GRUB_CMDLINE_LINUX_DEFAULT';
            }
            elsif (exists($grub{'GRUB_CMDLINE_LINUX'})) {
              $k = 'GRUB_CMDLINE_LINUX';
            }
            my $v = defined($k) ? $grub{$k} : undef;
            if (defined($v) && $v !~ /rootflags=.*?(?:u(?:sr)?|g(?:rp)?)quota/) {
              if ($v =~ /rootflags=(\S+)/) {
                $v =~ s/rootflags=(\S+)/rootflags=$1,uquota,gquota/;
              }
              else {
                $v .= " rootflags=uquota,gquota";
              }
              $grub{$k} = $v;
              &write_env_file($grub_def_file, \%grub);

              # Use grubby command to enable user and group quotas
              my $grubby_cmd = &has_command('grubby');
              if ($grubby_cmd && -x $grubby_cmd) {
                # Update all kernel entries
                $self->logsystem(
                  "$grubby_cmd --update-kernel=ALL --args=rootflags=uquota,gquota"
                );
              } else {
                # Generate a new actual config file
                my $grub_conf_file = "/boot/grub2/grub.cfg";
                my $grub_conf_cmd = "grub2-mkconfig";
                if (!-r $grub_conf_file) {
                  $grub_conf_file = "/boot/grub/grub.cfg";
                  $grub_conf_cmd = "grub-mkconfig";
                }
                # Always regenerate the real GRUB config in /boot,
                # never the EFI stub.
                my $have_bls = -d "/boot/loader/entries";
                my $have_bls_flag = 0;
                if ($grub_conf_cmd eq 'grub2-mkconfig' && $have_bls) {
                  # Detect BLS support
                  my $help = `$grub_conf_cmd --help 2>&1`;
                  $have_bls_flag = ($help =~ /--update-bls-cmdline/);
                }
                if (-r $grub_conf_file) {
                  &copy_source_dest($grub_conf_file, "$grub_conf_file.orig");
                  my $cmd = "$grub_conf_cmd -o $grub_conf_file";
                  $cmd .= " --update-bls-cmdline" if $have_bls_flag;
                  $self->logsystem($cmd);
                }
              }
            }
            else {
              $res         = 1;
              $prt_std_err = 0;
            }
          }
        }
        if ($prt_std_err && $res) {
          print $smsg1;
          print $msg1;
          print $msg2;
          print $smsg2;
        }
      }
      else {
        # Activate quotas
        if (load_quota_module($self)) {
          $self->logsystem("quotacheck -vgum $dir");
          $self->logsystem("quotaon -av");
          $res = 1;
        }
        else {
          $log->error("Unable to load the quota_v2 kernel module");
          $res = 2;
        }
      }
    }
    $self->done($res);    # Maybe OK!
  };
  if ($@) {
    $log->error("Error configuring quotas: $@");
    $ENV{'QUOTA_FAILED'} = '1';
    $self->done(2);       # 2 is a non-fatal error
  }
}

sub load_quota_module {
  my $self = shift;

  # The module is normally already available. Minimal Ubuntu images may omit
  # the matching linux-modules-extra package, so install it on demand.
  return 1 if (!$self->logsystem("modprobe quota_v2"));

  # Preserve the existing behavior everywhere except Ubuntu. Some kernels
  # provide quota support without exposing quota_v2 as a loadable module.
  return 1 if (($gconfig{'real_os_type'} // '') !~ /ubuntu/i);

  my $kernel = backquote_command("uname -r 2>/dev/null");
  $kernel =~ s/\s+$//;
  if ($kernel !~ /^[A-Za-z0-9][A-Za-z0-9.+~-]*$/) {
    $log->error("Unable to determine the running Ubuntu kernel version");
    return 0;
  }

  foreign_require("software");
  if (!defined(&software::update_system_install)) {
    $log->error("No system package installation API is available");
    return 0;
  }

  my @packages = ("linux-modules-extra-$kernel");

  # Keep the extra modules installed on future generic kernel upgrades too.
  # Cloud and other kernel flavors have different tracking packages and are
  # intentionally left to their platform package management.
  push(@packages, "linux-image-extra-virtual") if ($kernel =~ /-generic$/);

  my $packages = join(' ', @packages);
  $log->info("Installing missing quota kernel module packages $packages");
  my ($output) = capture_function_output_tempfile(
    \&software::update_system_install, $packages
  );
  $output = package_output_to_text($output);
  $log->info("Package installation output: $output") if ($output);

  return !$self->logsystem("modprobe quota_v2");
}

sub package_output_to_text {
  my $output = shift;
  return '' if (!$output);

  # Package installation APIs return output formatted for Webmin pages.
  # Strip that markup before decoding entities so literal command output is
  # preserved in the plain-text Virtualmin Config log.
  $output = html_unescape(html_strip($output));
  $output =~ s/^\s+//;
  $output =~ s/\s+$//;
  return $output;
}

1;
