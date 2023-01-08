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
    if (has_command('fail2ban-server')) {
      
      foreign_require('init', 'init-lib.pl');
      init::enable_at_boot('fail2ban');

      # Create a jail.local with some basic config
      create_fail2ban_jail();
      create_fail2ban_firewalld();

      # Switch backend to use systemd to avoid failure on
      # fail2ban starting when actual log file is missing
      # e.g.: Failed during configuration: Have not found any log file for [name] jail
      &foreign_require('fail2ban');
      my $jfile = "$fail2ban::config{'config_dir'}/jail.conf";
      my @jconf = &fail2ban::parse_config_file($jfile);
      my @lconf = &fail2ban::parse_config_file(&fail2ban::make_local_file($jfile));
      &fail2ban::merge_local_files(\@jconf, \@lconf);
      my $jconf = &fail2ban::parse_config_file($jfile);
      my ($def) = grep { $_->{'name'} eq 'DEFAULT' } @jconf;
      &fail2ban::lock_all_config_files();
      &fail2ban::save_directive("backend", 'systemd', $def);
      &fail2ban::unlock_all_config_files();

      # Restart fail2ban
      init::restart_action('fail2ban');
      $self->done(1);
    } else {
      $self->done(2); # Not available, as in Oracle 9
    }
  };
  if ($@) {
    $self->done(0);    # NOK!
  }
}

sub create_fail2ban_jail {
  my $backend = "";
  $backend = "\nbackend = auto"
    if ($gconfig{'os_type'} eq "debian-linux");
  open(my $JAIL_LOCAL, '>', '/etc/fail2ban/jail.local');
  print $JAIL_LOCAL <<EOF;
[dovecot]
enabled = true

[postfix]
enabled = true

[postfix-sasl]
enabled = true$backend

[proftpd]
enabled = true

[sshd]
enabled = true

[webmin-auth]
enabled = true

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
