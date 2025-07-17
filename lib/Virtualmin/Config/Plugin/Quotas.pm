package Virtualmin::Config::Plugin::Quotas;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

$| = 1;

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Quotas', %args);

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
  push(@INC, "$root/vendor_perl");
  eval 'use WebminCore';    ## no critic
  init_config();

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
    elsif ($gconfig{'os_type'} =~ /-linux$/) {
      $mount::options{'usrquota'} = '';
      $mount::options{'grpquota'} = '';
      $mount::options{'quota'}    = '';
    }
    elsif ($gconfig{'os_type'} =~ /freebsd|netbsd|openbsd|macos/) {

      # Skip if quotas are not enabled--requires a kernel rebuild
      my $quotav = `quota -v`;
      if (!$quotav =~ /none$/) {
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

        my $grubby_cmd = &has_command('grubby');
        my $grub_def_file = "/etc/default/grub";
        my $grub_generate_config = sub {
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
              $cmd .= " --update-bls-cmdline" if ($have_bls_flag);
              $self->logsystem($cmd);
            }
        };
        
        # Use grubby command to enable user and group quotas
        if (-x $grubby_cmd) {
          $self->logsystem(
            "$grubby_cmd --update-kernel=ALL --args=rootflags=uquota,gquota"
          );
          # Generate a new actual config file
          &$grub_generate_config();
        }
        # Update configuration manually
        elsif (-r $grub_def_file) {
          my %grub;
          &read_env_file($grub_def_file, \%grub) || ($res = 0);
          my $v = $grub{'GRUB_CMDLINE_LINUX'};
          if (defined($v) && $v !~ /rootflags=.*?(?:uquota|gquota)/) {
            if ($v =~ /rootflags=(\S+)/) {
              $v =~ s/rootflags=(\S+)/rootflags=$1,uquota,gquota/;
            }
            else {
              $v .= " rootflags=uquota,gquota";
            }
            $grub{'GRUB_CMDLINE_LINUX'} = $v;
            &write_env_file($grub_def_file, \%grub);

            # Generate a new actual config file
            &$grub_generate_config();
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
      $self->logsystem("modprobe quota_v2");
      $self->logsystem("quotacheck -vgum $dir");
      $self->logsystem("quotaon -av");
      $res = 1;
    }
    $self->done($res);    # Maybe OK!
  };
  if ($@) {
    $log->error("Error configuring quotas: $@");
    $ENV{'QUOTA_FAILED'} = '1';
    $self->done(2);       # 2 is a non-fatal error
  }
}

1;
