package Virtualmin::Config::Stack;
use strict;
use warnings;
use 5.010_001;

# A stack for configuring inside plugins

sub new {
  my ($class, %args) = @_;
  my $self = {};
  return bless $self, $class;
}

# Common modules for all stacks
sub common_modules {
    return (
        "Webmin",      "Bind",      "Postfix",
        "MySQL",       "Firewall",  "Procmail",
        "Quotas",      "Shells",    "Status",
        "Upgrade",     "Usermin",   "Virtualmin",
        "Dovecot",     "SASL",      "Etckeeper",
        "Apache"
    );
}

# Extra full stack modules
sub full_modules {
    return (
        "ProFTPd",      "AWStats", "ClamAV",
        "SpamAssassin", "Fail2ban"
    );
}

# Replacement logic for modules
sub replacements {
    my ($type) = @_;

    # Modern system with Firewalld?
    my $firewalld =
        grep { -x "$_/firewall-cmd" } split(/:/, "/usr/bin:/bin:$ENV{PATH}");

    # Define replacements
    return {
        "Firewall" => $firewalld ? "Firewalld" : "Firewall",
        "Fail2ban" => $firewalld ? "Fail2banFirewalld" : "Fail2ban",
        "Apache"   => $type eq 'lemp' ? "Nginx" : "Apache",
    };
}

sub list {
    my ($self, $type, $full) = @_;

    # Get common and optional full modules
    my @modules = common_modules();
    push(@modules, full_modules()) if ($full);

    # Apply replacements
    my %replacements = %{ replacements($type) };
    @modules = map { $replacements{$_} // $_ } @modules;

    return \@modules;
}

1;
