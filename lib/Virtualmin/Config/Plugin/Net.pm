package Virtualmin::Config::Plugin::Net;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);

sub new {
  my $class = shift;
  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Net');

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. XXX Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;

  use Cwd;
  my $cwd = getcwd();
  my $root = $self->root();
  chdir($root);
  $0 = "$root/init-system.pl";
  push(@INC, $root);
  eval 'use WebminCore'; ## no critic
  init_config();

  $self->spin();
  if (foreign_check("net")) {
		print "Configuring resolv.conf to use my DNS server\n";
		foreign_require("net", "net-lib.pl");
		my $dns = net::get_dns_config();
		if (indexof("127.0.0.1", @{$dns->{'nameserver'}}) < 0) {
			unshift(@{$dns->{'nameserver'}}, "127.0.0.1");
			net::save_dns_config($dns);
		}
		# Restart Postfix so that it picks up the new resolv.conf
		foreign_require("virtual-server");
		virtual_server::stop_service_mail();
		virtual_server::start_service_mail();
	}
  $self->done(1); # OK!
}

1;
