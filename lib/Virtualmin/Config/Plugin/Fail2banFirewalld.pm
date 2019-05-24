package Virtualmin::Config::Plugin::Fail2banFirewalld;

# Enables fail2ban and sets up a reasonable set of rules.
# This is currently identical to Fail2ban, with a different depends.
# We could make the dependency resolution in Config smarter to re-merge it
# back to one file. This will do for now.
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

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

    my $err;
    if (has_command('fail2ban-server')) {

      # Create a jail.local with some basic config
      my $err = create_fail2ban_jail();
      create_fail2ban_firewalld();

      # Fix systemd unit for firewalld
      if ($gconfig{'os_type'} =~ /debian-linux|ubuntu-linux/) {
        $self->logsystem(
          'cp /lib/systemd/system/fail2ban.service /etc/systemd/system/');
        $self->logsystem('touch /var/log/mail.warn');
        my $fail2ban_service_ref
          = read_file_lines('/etc/systemd/system/fail2ban.service');
        foreach my $l (@$fail2ban_service_ref) {
          if ($l =~ /^\s*After=/) {
            $l = "After=network.target firewalld.service";
          }
        }
        flush_file_lines('/etc/systemd/system/fail2ban.service');
        $self->logsystem('systemctl daemon-reload');
      }
    }

    init::restart_action('fail2ban');
    $self->done(1);
  };
  if ($@) {
    $self->done(0);    # NOK!
  }
}

sub create_fail2ban_jail {
  open(my $JAIL_LOCAL, '>', '/etc/fail2ban/jail.local');
  print $JAIL_LOCAL <<EOF;
[sshd]

enabled = true
port    = ssh

[ssh-ddos]

enabled = true
port    = ssh,sftp
filter  = sshd-ddos

[webmin-auth]

enabled = true
port    = 10000

[proftpd]

enabled  = true
port     = ftp,ftp-data,ftps,ftps-data

[postfix]

enabled  = true
port     = smtp,465,submission

[dovecot]

enabled = true
port    = pop3,pop3s,imap,imaps,submission,465,sieve

[postfix-sasl]

enabled  = true
port     = smtp,465,submission,imap,imaps,pop3,pop3s

EOF

  close $JAIL_LOCAL;
}

sub create_fail2ban_firewalld {
  if (has_command('firewall-cmd')
    && !-e '/etc/fail2ban/jail.d/00-firewalld.conf')
  {
    # Apply firewalld actions by default
    open(my $FIREWALLD_CONF, '>', '/etc/fail2ban/jail.d/00-firewalld.conf');
    print $FIREWALLD_CONF <<EOF;
# This file created by Virtualmin to enable firewalld-cmd actions by
# default. It can be removed, if you use a different firewall.
[DEFAULT]
banaction = firewallcmd-ipset
EOF
    close $FIREWALLD_CONF;
  }    # XXX iptables-multiport is default on CentOS, double check others.
}

1;
