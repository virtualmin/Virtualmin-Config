package Virtualmin::Config::Plugin::Test;
use strict;
use warnings;
use 5.010;
use Term::ANSIColor qw(:constants);
use parent 'Virtualmin::Config::Plugin';

sub new {
  my $class = shift;
  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Test');
  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. TODO Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;
  use Cwd;
  my $cwd = getcwd();
  my $root = $self->root();
  chdir($root);
  $0 = "$root/init-system.pl";
  push(@INC, $root);
  #use lib $root;
  eval 'use WebminCore'; ## no critic
  $ENV{'WEBMIN_CONFIG'} = $cwd . "/t/data/etc/webmin";
  $ENV{'WEBMIN_VAR'} ||= $cwd . "/t/data/var/webmin";
  $ENV{'MINISERV_CONFIG'} = $ENV{'WEBMIN_CONFIG'}."/miniserv.conf";
  # TODO Somehow get init_config() into $self->config, or something.
  init_config();

  $self->spin();
  eval {
    foreign_require("webmin", "webmin-lib.pl");
    my %gconfig;
    get_miniserv_config(\%gconfig);
    $gconfig{'theme'} = "dummy-theme";
    put_miniserv_config(\%gconfig);
    $self->done(1);
  };
  if ($@) {
    $self->done(0);
  }
}

1;
