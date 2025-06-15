package Virtualmin::Config::Plugin::Upgrade;
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
  my $self = $class->SUPER::new(name => 'Upgrade', %args);

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
  push(@INC, "$root/vendor_perl");
  eval 'use WebminCore';    ## no critic
  init_config();

  $self->spin();
  eval {
    my %wacl = ('disallow' => 'upgrade');
    save_module_acl(\%wacl, 'root', 'webmin');
    my %uacl = ('upgrade' => 0);
    save_module_acl(\%uacl, 'root', 'usermin');
    $self->done(1);         # OK!
  };
  if ($@) {
    $log->error("Error configuring Upgrade: $@");
    $self->done(0);
  }
}

1;
