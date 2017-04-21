package Virtualmin::Config::LAMP;
use strict;
use warnings;
use 5.010;
# A list of plugins for configuring a LAMP stack

sub new {
  my ($class, %args) = @_;
  my $self = {};

	return bless $self, $class;
}

sub plugins {
  return [
    "Webmin",
    "Apache",
    "Bind",
    "Dovecot",
    "Net",
    "AWStats",
    "Postfix",
    "MySQL",
    "Firewall",
    "Procmail",
    "ProFTPd",
    "Quotas",
    "SASL",
    "Shells",
    "Status",
    "Upgrade",
    "Usermin",
    "Webalizer",
    "Virtualmin",
    "Extra"
  ];
}

1;
