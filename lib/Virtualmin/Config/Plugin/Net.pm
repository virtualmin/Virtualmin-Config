package Virtualmin::Config::Plugin::Net;
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
  my $self = $class->SUPER::new(name => 'Net', %args);

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. XXX Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;

  use Cwd;
  my $cwd  = getcwd();
  my $root = $self->root();
  chdir($root);
  $0 = "$root/virtual-server/config-system.pl";
  push(@INC, $root);
  eval 'use WebminCore';    ## no critic
  init_config();

  $self->spin();
  eval {
    if (foreign_check("net")) {
      foreign_require("net", "net-lib.pl");
      my $dns = net::get_dns_config();
      if (indexof("127.0.0.1", @{$dns->{'nameserver'}}) < 0) {
        unshift(@{$dns->{'nameserver'}}, "127.0.0.1");
        net::save_dns_config($dns);
      }

      # Check to see if we're configured with dhcp
      my @dhcp = grep { $_->{'dhcp'} } net::boot_interfaces();
      if (@dhcp) {
        log_debug("Detected DHCP-configured network. This isn't ideal.");
        my $lref;
        if (-e '/etc/dhcp/dhclient.conf') {
          $lref = read_file_lines('/etc/dhcp/dhclient.conf');
          if (indexof("prepend domain-name-servers 127.0.0.1;", @{$lref}) < 0) {
            log_debug("Adding name server 127.0.0.1 to dhcp configuration.");
            push ( @{$lref}, 'prepend domain-name-servers 127.0.0.1;' );
          }
        }
      }
      # Restart Postfix so that it picks up the new resolv.conf
      foreign_require("virtual-server");
      virtual_server::stop_service_mail();
      virtual_server::start_service_mail();
    }
    $self->done(1);    # OK!
  };
  if ($@) {
    $self->done(0);
  }
}

1;
