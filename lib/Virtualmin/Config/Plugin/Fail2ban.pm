package Virtualmin::Config::Plugin::Fail2ban;
# Enables fail2ban and sets up a reasonable set of rules.
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
  my $self = $class->SUPER::new(name => 'Fail2ban');

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. XXX Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;
  my $err;

  # XXX Webmin boilerplate.
  use Cwd;
  my $cwd  = getcwd();
  my $root = $self->root();
  chdir($root);
  $0 = "$root/virtual-server/config-system.pl";
  push(@INC, $root);
  eval 'use WebminCore';    ## no critic
  init_config();
  # End of Webmin boilerplate.

  $self->spin();
  eval {
    foreign_require('init', 'init-lib.pl');
    init::enable_at_boot('fail2ban');

    if (has_command('fail2ban-server')) {
      # Create a jail.local with some basic config
      create_fail2ban_jail();
      create_fail2ban_firewalld();
    }

    init::restart_action('fail2ban');
    $self->done(1);
  };
  if ($@) {
    $self->done(0);    # NOK!
  }
}

sub create_fail2ban_jail {
  if (-e "/etc/fail2ban/jail.local") {
    die "Fail2ban already has local configuration. Will not overwrite.";
  }
  open(my $JAIL_LOCAL, '>', '/etc/fail2ban/jail.local');
print $JAIL_LOCAL <<EOF;
[sshd]

enabled = true
port    = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s

[ssh-ddos]

enabled = true
port    = ssh,sftp
filter  = sshd-ddos
log_path = %{sshd_log}s

[webmin-auth]

enabled = true
port    = 10000
logpath = %(syslog_authpriv)s
backend = %(syslog_backend)s

[proftpd]

enabled  = true
port     = ftp,ftp-data,ftps,ftps-data
logpath  = %(proftpd_log)s
backend  = %(proftpd_backend)s

[postfix]

enabled  = true
port     = smtp,465,submission
logpath  = %(postfix_log)s
backend  = %(postfix_backend)s

[dovecot]

enabled = true
port    = pop3,pop3s,imap,imaps,submission,465,sieve
logpath = %(dovecot_log)s
backend = %(dovecot_backend)s

[postfix-sasl]

enabled  = true
port     = smtp,465,submission,imap3,imaps,pop3,pop3s
logpath  = %(postfix_log)s
backend  = %(postfix_backend)s

EOF

close $JAIL_LOCAL;
}

sub create_fail2ban_firewalld {
  if ( has_command('firewall-cmd') &&
       ! -e '/etc/fail2ban/jail.d/00-firewalld.conf') {
    # Apply firewalld actions by default
    open (my $FIREWALLD_CONF, '>', '/etc/fail2ban/jail.d/00-firewalld.conf');
    print $FIREWALLD_CONF <<EOF;
# This file created by Virtualmin to enable firewalld-cmd actions by
# default. It can be removed, if you use a different firewall.
[DEFAULT]
banaction = firewallcmd-ipset
EOF
    close $FIREWALLD_CONF;
  } # XXX iptables-multiport is default on CentOS, double check others.
}

1;
