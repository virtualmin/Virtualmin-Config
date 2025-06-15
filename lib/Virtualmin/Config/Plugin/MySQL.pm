package Virtualmin::Config::Plugin::MySQL;
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
  my $self = $class->SUPER::new(name => 'MySQL', %args);

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. TODO Needs to make a backup so changes can be reverted.
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
    foreign_require("init", "init-lib.pl");
    if (init::action_status("mariadb")) {
      init::enable_at_boot("mariadb");
    }
    elsif ($gconfig{'os_type'} eq "freebsd" || init::action_status("mysql")) {
      init::enable_at_boot("mysql");
    }
    else {
      init::enable_at_boot("mysqld");
    }
    foreign_require("mysql", "mysql-lib.pl");
    if (mysql::is_mysql_running()) {
      mysql::stop_mysql();
    }
    my $conf = mysql::get_mysql_config();
    my ($sect) = grep { $_->{'name'} eq 'mysqld' } @$conf;
    if ($sect) {
      mysql::save_directive($conf, $sect, "innodb_file_per_table", [1]);
      flush_file_lines($sect->{'file'});
    }
    my $err = mysql::start_mysql();
    $self->done(1);
  };
  if ($@) {
    $log->error("Error configuring MySQL/MariaDB: $@");
    $self->done(0);
  }
}

1;
