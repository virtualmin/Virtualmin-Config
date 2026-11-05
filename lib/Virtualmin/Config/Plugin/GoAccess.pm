package Virtualmin::Config::Plugin::GoAccess;
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
  my $self = $class->SUPER::new(name => 'GoAccess', %args);

  return $self;
}

# Point the GoAccess module at the installed parser, and keep the plugin
# enabled in Virtualmin only when reports can be generated on this system.
sub actions {
  my $self = shift;

  $self->use_webmin();

  $self->spin();
  eval {
    my $binary;
    if (foreign_check("virtualmin-goaccess")) {
      my %mconfig = foreign_config("virtualmin-goaccess");
      if ($mconfig{'goaccess'} && -x $mconfig{'goaccess'}) {
        $binary = $mconfig{'goaccess'};
      }
      else {
        # The package may install the parser outside the module's default path
        $binary = has_command("goaccess");
        if ($binary) {
          $mconfig{'goaccess'} = $binary;
          lock_file("$config_directory/virtualmin-goaccess/config");
          save_module_config(\%mconfig, "virtualmin-goaccess");
          unlock_file("$config_directory/virtualmin-goaccess/config");
        }
      }
    }

    if ($binary) {
      $self->done(1);    # OK
    }
    else {
      # Without the module or its parser, Virtualmin must not offer reports
      lock_file("$config_directory/virtual-server/config");
      my %vconfig = foreign_config("virtual-server");
      my @plugins = grep { $_ ne 'virtualmin-goaccess' }
        split(/\s+/, $vconfig{'plugins'} || '');
      $vconfig{'plugins'} = join(' ', @plugins);
      save_module_config(\%vconfig, "virtual-server");
      unlock_file("$config_directory/virtual-server/config");
      $log->warn("GoAccess is not installed on this system, skipping configuration.");
      $self->done(2);    # Not installed!
    }
  };
  if ($@) {
    $log->error("Error configuring GoAccess: $@");
    $self->done(0);
  }
}

1;
