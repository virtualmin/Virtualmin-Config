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

# Common modules for all stacks (excluding DNS, mail and extra)
sub common_modules {
    return (
        "Webmin",      "MySQL",     "Firewall",
        "Quotas",      "Shells",    "Status",
        "Upgrade",     "Usermin",   "Virtualmin",
        "Etckeeper",   "Apache"
    );
}

# Modules related to DNS
sub dns_modules {
    return (
        "Bind"
    );
}

# Modules related to mail
sub mail_modules {
    return (
        "Postfix", "Dovecot", "SASL", "Procmail"
    );
}

# Extra (resourceful) modules
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
    my ($self, $type, $subtype) = @_;

    # Get common and optional full modules
    my @modules = common_modules();
    push(@modules, dns_modules())  if ($subtype ne 'nano');
    push(@modules, mail_modules()) if ($subtype !~ /\b(?:micro|nano)\b/);
    push(@modules, full_modules()) if ($subtype eq 'full');

    # Apply replacements
    my %replacements = %{ replacements($type) };
    @modules = map { $replacements{$_} // $_ } @modules;

    return \@modules;
}

1;
