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
        "Webmin",      "MySQL",        "Nftables",
        "Quotas",      "Shells",       "Virtualmin",
        "Etckeeper",   "Apache",       "AWStats",
        "Fail2ban",    "SSL",
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
        "Postfix",  "Dovecot",      "SASL",
        "Procmail", "SpamAssassin", "ClamAV",
    );
}

# Extra (resourceful) modules
sub full_modules {
    return (
        "ProFTPd", "Usermin",
    );
}

# Replacement logic for modules
sub replacements {
    my ($self, $type) = @_;

    my %r = (
            "Apache" => $type eq 'lemp' ? "Nginx" : "Apache",
    );

    return \%r;
}

sub list {
    my ($self, $type, $subtype) = @_;

    # Get common and optional full modules
    my @modules = common_modules();
    if ($subtype eq 'full') {
        push(@modules, dns_modules());
        push(@modules, mail_modules());
        push(@modules, full_modules());
    }

    # Apply replacements
    my $r = $self->replacements($type);
    @modules = map { exists $r->{$_} ? $r->{$_} : $_ } @modules;
    @modules = grep { defined && length } @modules;

    return \@modules;
}

1;
