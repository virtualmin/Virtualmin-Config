package Virtualmin::Config::Stack;
use strict;
use warnings;
use 5.010_001;
use parent 'Virtualmin::Config::Plugin';

# A stack for configuring inside plugins

sub new {
  my ($class, %args) = @_;
  my $self = {};
  return bless $self, $class;
}

# Common modules for all stacks (excluding DNS, mail and extra)
sub common_modules {
    return (
        "Webmin",      "MySQL",        "Firewall",
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

    $self->use_webmin();

    my $log = Log::Log4perl->get_logger("virtualmin-config-system");
    
    # Modern system with Firewalld?
    my $firewalld =
        grep { -x "$_/firewall-cmd" }
        split(/:/, "/usr/bin:/bin:".($ENV{'PATH'} // ''));
    $log->info("Checking for firewalld package: ".($firewalld ? "found" : "not found"));
    
    my %r = (
            "Apache" => $type eq 'lemp' ? "Nginx" : "Apache",
    );

    # If firewalld package could be installed, use it
    if ($firewalld && foreign_check("firewalld")) {
        $r{"Firewall"} = "Firewalld";
        $r{"Fail2ban"} = "Fail2banFirewalld";
    }
    # If firewall Webmin module is manually installed, use it
    elsif (foreign_check("firewall")) {
        $r{"Firewall"} = "Firewall";
        $r{"Fail2ban"} = "Fail2ban";
    }
    else {
        $r{"Firewall"} = undef;   # otherwise remove both
        $r{"Fail2ban"} = undef;   # otherwise remove both
        $log->info("Neither the firewalld package nor the Webmin firewall ".
                   "module is installed, skipping Fail2ban");
    }

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
