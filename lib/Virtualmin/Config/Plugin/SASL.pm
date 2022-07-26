package Virtualmin::Config::Plugin::SASL;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';
use Time::HiRes qw( sleep );    # XXX Figure out how to not need this.

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'SASL', %args);

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
  sleep 0.3;
  eval {
    my $res = 1;
    foreign_require("init", "init-lib.pl");
    init::enable_at_boot("saslauthd");
    my ($saslinit, $cf, $libdir);
    if ( $gconfig{'os_type'} eq "debian-linux"
      or $gconfig{'os_type'} eq "ubuntu-linux")
    {
      # Update saslauthd default to start on boot
      my $fn          = "/etc/default/saslauthd";
      my $sasldefault = read_file_lines($fn) or die "Failed to open $fn!";
      my $idx         = indexof("# START=yes", @$sasldefault);
      my $idx2        = grep {/START=/} @$sasldefault;
      if ($idx < 0) {
        $idx = indexof("START=no", @$sasldefault);
      }
      if ($idx >= 0) {
        $sasldefault->[$idx] = "START=yes";
      }
      if (!$idx2) {
        push(@{$sasldefault}, "START=yes");
      }

      # Substitute options and params if already in file
      foreach my $l (@$sasldefault) {
        if ($l =~ /OPTIONS/) {
          $l = 'OPTIONS="-c -m /var/spool/postfix/var/run/saslauthd -r"';
        }
        if ($l =~ /PARAMS/) {
          $l = 'PARAMS="-m /var/spool/postfix/var/run/saslauthd -r"';
        }
      }

      # Add them, if not
      if (!grep {/OPTIONS/} @$sasldefault) {
        push(@$sasldefault,
          'OPTIONS="-c -m /var/spool/postfix/var/run/saslauthd -r"');
      }
      if (!grep {/PARAMS/} @$sasldefault) {
        push(@$sasldefault,
          'PARAMS="-m /var/spool/postfix/var/run/saslauthd -r"');
      }
      flush_file_lines($fn);
      $cf = "/etc/postfix/sasl/smtpd.conf";
      $self->logsystem("mkdir -p -m 755 /var/spool/postfix/var/run/saslauthd");
      $self->logsystem("adduser postfix sasl");
      $saslinit = "/etc/init.d/saslauthd";
    }
    elsif ($gconfig{'os_type'} eq 'solaris') {

      # Use CSW saslauthd
      my $lref = read_file_lines("/opt/csw/etc/saslauthd.init");
      foreach my $l (@$lref) {
        if ($l =~ /^\#+\s*MECHANISM/) {
          $l = "MECHANISM=pam";
        }
      }
      flush_file_lines("/opt/csw/etc/saslauthd.init");
      $cf       = "/opt/csw/lib/sasl2/smtpd.conf";
      $saslinit = "/etc/init.d/cswsaslauthd";
    }
    else {
      # I'm not liking all of this jiggery pokery...need a better way to
      # detect which lib directory to work in.XXX
      if ($gconfig{'os_type'} eq 'freebsd') { $libdir = "/usr/local/lib"; }
      else {
        if (-e "/usr/lib64" && -e "/usr/lib64/perl") { $libdir = "/usr/lib64"; }
        else                                         { $libdir = "/usr/lib"; }
      }
      if    (-e "/etc/sasl2/smtpd.conf") { $cf = "/etc/sasl2/smtpd.conf"; }
      elsif (-e "$libdir/sasl2")         { $cf = "$libdir/sasl2/smtpd.conf"; }
      elsif (-e "$libdir/sasl")          { $cf = "$libdir/sasl/smtpd.conf"; }
      else {
#print "No sasl library directory found.  SASL authentication probably won't work";
        $res = 0;
      }
      if ($gconfig{'os_type'} eq 'freebsd') {
        $saslinit = "/usr/local/etc/rc.d/saslauthd";
      }
      else { $saslinit = "/etc/init.d/saslauthd"; }
    }
    if ($cf) {
      if (!-e $cf) {
        $self->logsystem("touch $cf");
      }
      my $smtpdconf = read_file_lines($cf) or die "Failed to open $cf!";
      my $idx       = indexof("", @$smtpdconf);
      if ($idx < 0) {
        push(@$smtpdconf, "pwcheck_method: saslauthd");
        push(@$smtpdconf, "mech_list: plain login");
        flush_file_lines($cf);
      }

      #$cmd = "$saslinit start";
      #proc::safe_process_exec($cmd, 0, 0, *STDOUT, undef, 1);
      init::start_action('saslauthd');
    }

    # Update flags to use realm as part of username
    my $saslconfig = "/etc/sysconfig/saslauthd";
    if (-r $saslconfig) {
      my $lref = read_file_lines($saslconfig);
      foreach my $l (@$lref) {
        if ($l =~ /^\s*FLAGS=\s*$/) {
          $l = "FLAGS=\"-r\"";
        }
        elsif ($l =~ /^\s*FLAGS="(.*)"$/ && $l !~ /-r/) {
          $l = "FLAGS=\"$1 -r\"";
        }
      }
      flush_file_lines($saslconfig);
    }

    $self->done(1);    # OK!
  };
  if ($@) {
    $self->done(0);
  }
}

1;
