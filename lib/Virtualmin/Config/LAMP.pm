package Virtualmin::Config::LAMP;
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

  # Modern system with firewalld?
  if (-x "/usr/bin/firewall-cmd" || -x "/bin/firewall-cmd") {
    return [
      "Webmin",       "Apache",  "Bind",
      "Dovecot",      "Net",     "AWStats",
      "Postfix",      "MySQL",   "Firewalld",
      "Procmail",     "ProFTPd", "Quotas",
      "SASL",         "Shells",  "Status",
      "Upgrade",      "Usermin", "Virtualmin",
      "ClamAV",       "NTP",     "SpamAssassin",
      "Fail2banFirewalld"
    ];
  }
  else {
    return [
      "Webmin",   "Apache",       "Bind",       "Dovecot",
      "Net",      "AWStats",      "Postfix",    "MySQL",
      "Firewall", "Procmail",     "ProFTPd",    "Quotas",
      "SASL",     "Shells",       "Status",     "Upgrade",
      "Usermin",  "Virtualmin",   "ClamAV",     "NTP",
      "SpamAssassin", "Fail2ban"
    ];
  }
}

1;
