package Virtualmin::Config::Plugin::Test;
use strict;
use warnings;
use parent qw(Virtualmin::Config::Plugin);
use 5.010;
use Term::ANSIColor qw(:constants);

our $config_directory;
our %gconfig;
our $error_must_die;
our $trust_unknown_referers;

sub new {
  my $class = shift;
  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Test');

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. XXX Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;
  $trust_unknown_referers = 1;
	open(my $CONF, "<", "$ENV{'WEBMIN_CONFIG'}/miniserv.conf") ||
	die RED, "Failed to open miniserv.conf", RESET;
  use Cwd;
  my $cwd = getcwd();
	my $root = "/usr/libexec/webmin";
	chdir($root);
	push(@INC, $root);
	eval "use WebminCore";
  $0 = "$root/init-system.pl";
  # XXX Somehow get init_config() into $self->config, or something.
	init_config();

	$error_must_die = 1;

  $self->spin("Configuring Test");
  foreign_require("webmin", "webmin-lib.pl");
  get_miniserv_config(\%gconfig);
  use Data::Dumper;
  say Dumper(%gconfig);
  $gconfig{'theme'} = "dummy-theme";
  put_miniserv_config(\%gconfig);
  $self->done(1);
}

1;
