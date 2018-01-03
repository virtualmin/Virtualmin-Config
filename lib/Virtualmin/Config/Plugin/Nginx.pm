package Virtualmin::Config::Plugin::Nginx;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';
use Time::HiRes qw( sleep );    # XXX Figure out how to not need this.

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Nginx', %args);

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
  sleep 0.3;    # XXX Useless sleep, prevent spin from ending before it starts
  eval {
    foreign_require('init', 'init-lib.pl');

    init::enable_at_boot('nginx');
    init::start_action('nginx');

    my %vconfig = &foreign_config("virtual-server");
    $vconfig{'web'}                  = 0;
    $vconfig{'ssl'}                  = 0;
    $vconfig{'avail_virtualmin-dav'} = '';
    $vconfig{'backup_feature_ssl'}   = 0;

    $vconfig{'plugins'}
      = 'virtualmin-awstats virtualmin-htpasswd virtualmin-nginx virtualmin-nginx-ssl';
    save_module_config(\%vconfig, "virtual-server");

    $self->done(1);    # OK!
  };
  if ($@) {
    $self->done(0);
  }
}

1;
