package Virtualmin::Config::Plugin::Webmin;
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
  my $self = $class->SUPER::new(name => 'Webmin', %args);

  return $self;
}

# Actions method performs whatever configuration is needed for this
# plugin. TODO Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;

  $self->use_webmin();

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
    # Mailboxes configuration
    my $mini_stack =
      (defined $self->bundle() && $self->bundle() =~ /mini/i) ?
        ($self->bundle() =~ /LEMP/i ? 'LEMP' : 'LAMP') : 0;
    # Configure the Read User Mail module to look for sub-folders
    # under ~/Maildir
    if (!$mini_stack) {
      my %mconfig = foreign_config("mailboxes");
      $mconfig{'mail_usermin'}    = "Maildir";
      $mconfig{'from_virtualmin'} = 1;
      $mconfig{'spam_buttons'} = 'list,mail';
      save_module_config(\%mconfig, "mailboxes");
    }
    $self->done(1);    # OK!
  };
  if ($@) {
    $log->error("Error configuring Webmin: $@");
    $self->done(0);    # NOK!
  }
}

1;
