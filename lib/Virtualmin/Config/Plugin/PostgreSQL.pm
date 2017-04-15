package Virtualmin::Config::Plugin::PostgreSQL;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);

sub new {
  my $class = shift;
  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'PostgreSQL');

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
  eval 'use WebminCore'; ## no critic
  init_config();

  if (foreign_check("postgresql")) {
    $self->spin();
		foreign_require("postgresql", "postgresql-lib.pl");
		if (!-r $postgresql::config{'hba_conf'}) {
			# Needs to be initialized
			my $err = postgresql::setup_postgresql();
		}
		if (postgresql::is_postgresql_running() == 0) {
			my $err = postgresql::start_postgresql();
		}
    if ($err) { $self->done(0); } # Something went wrong
    else { $self->done(1); } # OK!
  }
}

1;
