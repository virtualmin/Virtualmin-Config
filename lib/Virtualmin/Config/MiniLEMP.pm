package Virtualmin::Config::MiniLEMP;
use strict;
use warnings;
use 5.010_001;

# A list of plugins for configuring a LAMP stack

sub new {
  my ($class, %args) = @_;
  my $self = {};

  return bless $self, $class;
}

sub plugins {

  # Modern system with systemd?
  if (-x "/usr/bin/systemctl" || -x "/bin/systemctl") {
    return [
      "Webmin",  "Nginx",   "Bind",      "Net",
      "Postfix", "MySQL",   "Firewalld", "Procmail",
      "ProFTPd", "Quotas",  "Shells",    "Status",
      "Upgrade", "Usermin", "Webalizer", "MiniVirtualmin",
      "NTP",     "Fail2banFirewalld"
    ];
  }
  else {
    return [
      "Webmin", "Nginx",    "Bind",     "Net",     "Postfix",
      "MySQL",  "Firewall", "Procmail", "ProFTPd", "Quotas",
      "Shells", "Status",   "Upgrade",  "Usermin", "Virtualmin",
      "NTP",    "Fail2ban"
    ];
  }
}

1;
