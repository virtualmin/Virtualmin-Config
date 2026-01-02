package Virtualmin::Config::Plugin::MySQL;
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
  my $self = $class->SUPER::new(name => 'MySQL', %args);

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. TODO Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;

  $self->use_webmin();

  $self->spin();
  eval {
    foreign_require("init");
    if (init::action_status("mariadb")) {
      init::enable_at_boot("mariadb");
    }
    elsif ($gconfig{'os_type'} eq "freebsd" || init::action_status("mysql")) {
      init::enable_at_boot("mysql");
    }
    else {
      init::enable_at_boot("mysqld");
    }
    foreign_require("mysql");
    if (!mysql::is_mysql_running()) {
      mysql::start_mysql();
    }
    $self->done(1);
  };
  if ($@) {
    $log->error("Error configuring MySQL/MariaDB: $@");
    $self->done(0);
  }
}

1;
