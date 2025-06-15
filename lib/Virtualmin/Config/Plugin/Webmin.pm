package Virtualmin::Config::Plugin::Webmin;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Webmin', %args);

  return $self;
}

# Actions method performs whatever configuration is needed for this
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
    # Configure status module
    foreign_require("status");
    $status::config{'sched_mode'} = 1;
    $status::config{'sched_int'}    ||= 5;
    $status::config{'sched_offset'} ||= 0;
    lock_file("$config_directory/status/config");
    save_module_config(\%status::config, 'status');
    unlock_file("$config_directory/status/config");
    status::setup_cron_job();
    # Disable Webmin upgrades from UI
    save_module_acl( { disallow => 'upgrade' }, 'root', 'webmin' );
    # Update Webmin configuration
    foreign_require("webmin");
    $gconfig{'nowebminup'}   = 1;
    $gconfig{'theme'}        = "authentic-theme";
    $gconfig{'mobile_theme'} = "authentic-theme";
    $gconfig{'logfiles'}     = 1;
    lock_file("$config_directory/config");
    write_file("$config_directory/config", \%gconfig);
    unlock_file("$config_directory/config");
    # Configure miniserv
    get_miniserv_config(\%miniserv);
    $miniserv{'preroot'}            = "authentic-theme";
    $miniserv{'ssl'}                = 1;
    $miniserv{'ssl_cipher_list'}    = $webmin::strong_ssl_ciphers;
    $miniserv{'twofactor_provider'} = 'totp';
    put_miniserv_config(\%miniserv);
    webmin::build_installed_modules(1);
    $self->logsystem("/etc/webmin/restart-by-force-kill > /dev/null 2>&1");
    $self->done(1);    # OK!
  };
  if ($@) {
    $log->error("Error configuring Webmin: $@");
    $self->done(0);    # NOK!
  }
}

1;
