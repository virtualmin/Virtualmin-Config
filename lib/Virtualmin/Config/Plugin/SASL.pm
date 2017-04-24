package Virtualmin::Config::Plugin::SASL;
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
  my $self = $class->SUPER::new(name => 'SASL');

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
  $0 = "$root/init-system.pl";
  push(@INC, $root);
  eval 'use WebminCore';    ## no critic
  init_config();

  $self->spin();
  eval {
    my $res = 1;
    foreign_require("init", "init-lib.pl");
    init::enable_at_boot("saslauthd");
    my ($saslinit, $cf, $libdir);
    if ( $gconfig{'os_type'} eq "debian-linux"
      or $gconfig{'os_type'} eq "ubuntu-linux")
    {
      my $fn          = "/etc/default/saslauthd";
      my $sasldefault = &read_file_lines($fn) or die "Failed to open $fn!";
      my $idx         = &indexof("# START=yes", @$sasldefault);
      if ($idx < 0) {
        $idx = &indexof("START=no", @$sasldefault);
      }
      if ($idx >= 0) {
        $sasldefault->[$idx] = "START=yes";
      }
      push(@$sasldefault,
        "PARAMS=\"-m /var/spool/postfix/var/run/saslauthd -r\"");
      flush_file_lines($fn);
      $cf = "/etc/postfix/sasl/smtpd.conf";
      system("mkdir -p -m 755 /var/spool/postfix/var/run/saslauthd");
      system("adduser postfix sasl");
      $saslinit = "/etc/init.d/saslauthd";
    }
    elsif ($gconfig{'os_type'} eq 'solaris') {

      # Use CSW saslauthd
      my $lref = &read_file_lines("/opt/csw/etc/saslauthd.init");
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
        system("touch $cf");
      }
      my $smtpdconf = read_file_lines($cf) or die "Failed to open $cf!";
      my $idx = indexof("", @$smtpdconf);
      if ($idx < 0) {
        push(@$smtpdconf, "pwcheck_method: saslauthd");
        push(@$smtpdconf, "mech_list: plain login");
        flush_file_lines($cf);
      }

      #$cmd = "$saslinit start";
      #proc::safe_process_exec($cmd, 0, 0, *STDOUT, undef, 1);
      init::start_action('saslauthd');
    }

    $self->done(1);    # OK!
  };
  if ($@) {
    $self->done(0);
  }
}

1;
