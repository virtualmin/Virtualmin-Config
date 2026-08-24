package Virtualmin::Config::Plugin::PostgreSQL;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'PostgreSQL', %args);

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. TODO Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;

  $self->use_webmin();

  $self->spin();

  if (foreign_check("postgresql")) {
    eval {
      foreign_require("postgresql");
      if (!-r $postgresql::config{'hba_conf'}) {

        # Needs to be initialized
        my $err = postgresql::setup_postgresql();
        die "Failed to initialize PostgreSQL: $err" if ($err);
      }
      if (postgresql::is_postgresql_running() == 0) {
        my $err = postgresql::start_postgresql();
        die "Failed to start PostgreSQL: $err" if ($err);
      }

      $self->done(1); # success
    };
    if ($@) {
      $log->error("Error configuring PostgreSQL: $@");
      $self->done(0); # failure
    }
  } else {
    $log->info("PostgreSQL Webmin module has not been installed yet, ".
               "skipping configuration.");
    $self->done(2); # warning, skipped
  }
}

1;
