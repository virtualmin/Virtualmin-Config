package Virtualmin::Config::Plugin::Test;
use strict;
use warnings;
use 5.010;
use Term::ANSIColor qw(:constants);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our %gconfig;
our $error_must_die;
our $trust_unknown_referers;
our $root;

sub new {
  my $class = shift;
  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Test');

  $ENV{'WEBMIN_CONFIG'} = "t/data/etc/webmin";
  $ENV{'WEBMIN_VAR'} ||= "t/data/var/webmin";
  $ENV{'MINISERV_CONFIG'} = $ENV{'WEBMIN_CONFIG'}."/miniserv.conf";

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. XXX Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;
  $trust_unknown_referers = 1;
  my $root = $self->root();
  chdir($root);
  push(@INC, $root);
  #use lib $root;
  eval 'use WebminCore'; ## no critic
  use Cwd;
  my $cwd = getcwd();
  $0 = $cwd . "/init-system.pl";
  # XXX Somehow get init_config() into $self->config, or something.
  init_config();

  $error_must_die = 1;

  $self->spin("Configuring Test");
  foreign_require("webmin", "webmin-lib.pl");
  get_miniserv_config(\%gconfig);
  $gconfig{'theme'} = "dummy-theme";
  put_miniserv_config(\%gconfig);
  $self->done(1);
}

1;
