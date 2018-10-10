package Virtualmin::Config::Plugin::Net;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

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

      # Check to see if we're configured with dhcp.
      my @dhcp = grep { $_->{'dhcp'} } net::boot_interfaces();
      # XXX Check for extra dhcp config files (this is probably unreliable.
      my @dhcpinclude = glob "/etc/dhcp/interfaces.d/*";
      if (@dhcp || @dhcpinclude) {
        $log->warn("Detected DHCP-configured network. This probably isn't ideal.");
        my $lref;
        my $file = '/etc/dhcp/dhclient.conf';
        if (-e $file) {
          $lref = read_file_lines($file);
          if (indexof("prepend domain-name-servers 127.0.0.1;", @{$lref}) < 0) {
            $log->info("Attempting to add name server 127.0.0.1 to dhcp configuration.");
            push(@{$lref}, 'prepend domain-name-servers 127.0.0.1;');
          }
          flush_file_lines($file);
        }

        # Force 127.0.0.1 into name servers in resolv.conf
        # XXX This shouldn't be necessary. There's some kind of bug in net::
        $log->info("Adding name server 127.0.0.1 to resolv.conf. This may be overwritten by DHCP on reboot.");
        my $resolvconf = '/etc/resolv.conf';
        my $rlref      = read_file_lines($resolvconf);
        if (indexof('nameserver 127.0.0.1') < 0) {
          unshift(@{$rlref}, '# Added by Virtualmin.');
          unshift(@{$rlref}, 'nameserver 127.0.0.1');
        }
        flush_file_lines($resolvconf);
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
