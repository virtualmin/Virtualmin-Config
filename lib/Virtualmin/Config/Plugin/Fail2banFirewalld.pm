package Virtualmin::Config::Plugin::Fail2banFirewalld;

# Enables fail2ban and sets up a reasonable set of rules.
# This is currently identical to Fail2ban, with a different depends.
# We could make the dependency resolution in Config smarter to re-merge it
# back to one file. This will do for now.
use strict;
use warnings;
no warnings qw(once numeric);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(
    name    => 'Fail2banFirewalld',
    depends => ['Firewalld'],
    %args
  );

  return $self;
}

sub actions {
  my $self = shift;

  $self->use_webmin();

  $self->spin();

  # Is firewalld actually installed?
  my $firewalld = grep { -x "$_/firewall-cmd" }
                  split(/:/, "/usr/bin:/bin:".($ENV{'PATH'} // ''));
  unless ($firewalld) {
    foreign_require('init');
    init::stop_action('fail2ban');
    init::disable_at_boot('fail2ban');
    $log->info("Firewalld not installed, stopping and disabling Fail2ban");
    $self->add_postinstall_message(
      "Firewalld could not be installed because it conflicts with the ".
      "installed 'cloud-init' package on this OS. Fail2ban requires a working ".
      "firewall and has been disabled.",
      "log_info"
    ) if (defined($ENV{'VIRTUALMIN_INSTALL_TEMPDIR'}));
    $self->done(2);
    return;
  }

  eval {
    if (has_command('fail2ban-server')) {

      foreign_require('init', 'init-lib.pl');
      init::enable_at_boot('fail2ban');

      # Create a jail.local with some basic config
      create_fail2ban_jail($self);
      create_fail2ban_firewalld();

      # Setup custom Usermin jail
      if (foreign_installed('usermin')) {
        create_fail2ban_usermin_jail();
      }

      # Switch backend to use systemd to avoid failure on fail2ban starting when
      # actual log file is missing e.g.: Failed during configuration: Have not
      # found any log file for [name] jail
      &foreign_require('fail2ban');
      my $jfile = "$fail2ban::config{'config_dir'}/jail.conf";
      my @jconf = &fail2ban::parse_config_file($jfile);
      my @lconf
        = &fail2ban::parse_config_file(&fail2ban::make_local_file($jfile));
      &fail2ban::merge_local_files(\@jconf, \@lconf);
      my $jconf = &fail2ban::parse_config_file($jfile);
      my ($def) = grep { $_->{'name'} eq 'DEFAULT' } @jconf;
      &fail2ban::lock_all_config_files();
      &fail2ban::save_directive("backend", 'systemd', $def);
      &fail2ban::unlock_all_config_files();

      # Restart fail2ban
      init::restart_action('fail2ban');
      $self->done(1);
    }
    else {
      $self->done(2);    # Not available, as in Oracle 9
    }
  };
  if ($@) {
    $log->error("Error configuring Fail2ban: $@");
    $self->done(0);      # NOK!
  }
}

sub create_fail2ban_jail {
  my $self = shift;
  # Postfix addendum
  my $postfix_jail_extra = "";

  my $is_debian = $gconfig{'real_os_type'} =~ /debian/i;
  my $is_ubuntu = $gconfig{'real_os_type'} =~ /ubuntu/i;
  my $debian10_or_older = $is_debian && $gconfig{'real_os_version'} <= 10;
  my $ubuntu20_or_older = $is_ubuntu && int($gconfig{'real_os_version'}) <= 20;

  if ($debian10_or_older || $ubuntu20_or_older) {
    $postfix_jail_extra = "\nbackend = auto\nlogpath = /var/log/mail.log";
  }
  elsif ($is_debian || $is_ubuntu) {
    $postfix_jail_extra
      = "\nbackend = systemd\njournalmatch = _SYSTEMD_UNIT=postfix\@-.service";
  }

  # Proftpd addendum
  my $proftpd_jail_extra = "";
  if ($is_debian || $is_ubuntu) {
    $proftpd_jail_extra
      = "\nbackend = auto\nlogpath = /var/log/proftpd/proftpd.log";
  }
  elsif ($gconfig{'os_type'} eq 'redhat-linux') {
    $proftpd_jail_extra = "\nprefregex =\n";
    $proftpd_jail_extra
      .= 'failregex = \(\S+\[<HOST>\]\)[: -]+ USER \S+: no such user found from \S+ \[[0-9.]+\] to \S+:\S+\s*$'
      . "\n";
    $proftpd_jail_extra
      .= '            \(\S+\[<HOST>\]\)[: -]+ USER \S+ \(Login failed\):.*\s+$'
      . "\n";
    $proftpd_jail_extra
      .= '            \(\S+\[<HOST>\]\)[: -]+ Maximum login attempts \([0-9]+\) exceeded, connection refused.*\s+$'
      . "\n";
    $proftpd_jail_extra
      .= '            \(\S+\[<HOST>\]\)[: -]+ SECURITY VIOLATION: \S+ login attempted\.\s+$'
      . "\n";
    $proftpd_jail_extra
      .= '            \(\S+\[<HOST>\]\)[: -]+ Maximum login attempts \(\d+\) exceeded\s+$';
  }
my $mini_stack =
      (defined $self->bundle() && $self->bundle() =~ /mini/i) ?
        ($self->bundle() =~ /LEMP/i ? 'LEMP' : 'LAMP') : 0;
my $proftpd_block = $mini_stack ? '' :
    "[proftpd]\n" .
    "enabled = true\nport = ftp,ftp-data,ftps,ftps-data,2222$proftpd_jail_extra\n\n";
my $usermin_block = foreign_installed('usermin') && -d '/etc/fail2ban/filter.d'
  ? "\n\n[usermin-auth]\nenabled = true\njournalmatch = ".
    "_SYSTEMD_UNIT=usermin.service"
  : '';

  open(my $JAIL_LOCAL, '>', '/etc/fail2ban/jail.local');
  print $JAIL_LOCAL <<EOF;
[dovecot]
enabled = true

[postfix]
enabled = true

[postfix-sasl]
enabled = true$postfix_jail_extra

${proftpd_block}[sshd]
enabled = true

[webmin-auth]
enabled = true
journalmatch = _SYSTEMD_UNIT=webmin.service${usermin_block}

EOF

  close $JAIL_LOCAL;
}

sub create_fail2ban_firewalld {
  if (has_command('firewall-cmd')
    && !-e '/etc/fail2ban/jail.d/00-firewalld.conf')
  {
    open(my $FIREWALLD_CONF, '>', '/etc/fail2ban/jail.d/virtualmin-firewalld.conf');
    print $FIREWALLD_CONF <<EOF;
# This file was created by the Virtualmin installer to enable the use of
# Firewalld rich rules with Fail2ban
[DEFAULT]
banaction = firewallcmd-rich-rules
banaction_allports = firewallcmd-rich-rules
EOF
    close $FIREWALLD_CONF;
  }
}

# Custom jail for Usermin, to protect against brute-force attacks on the login
# page
sub create_fail2ban_usermin_jail {
  return if (!-d '/etc/fail2ban/filter.d');
  open(my $USERMIN_JAIL, '>', '/etc/fail2ban/filter.d/usermin-auth.conf');
  print $USERMIN_JAIL <<'EOF';
# Fail2Ban filter for usermin
# created by Virtualmin installer

[INCLUDES]

before = common.conf

[Definition]

_daemon = usermin

failregex = ^%(__prefix_line)sNon-existent login as .+ from <HOST>\s*$
            ^%(__prefix_line)sInvalid login as .+ from <HOST>\s*$

ignoreregex =
EOF
  close $USERMIN_JAIL;
}

1;
