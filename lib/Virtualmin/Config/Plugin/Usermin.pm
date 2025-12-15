package Virtualmin::Config::Plugin::Usermin;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %uconfig, %uminiserv);
our $trust_unknown_referers = 1;

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Usermin', %args);

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin.
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
    # No Usermin installed, skip it
    if (!foreign_installed('usermin')) {
      $self->done(2);    # Not installed
      return;
    }
    # Disable Usermin upgrades from UI
    save_module_acl( { upgrade => 0 }, 'root', 'usermin' );
    # Update Usermin configuration
    foreign_require("init");
    foreign_require("usermin");
    usermin::get_usermin_config(\%uconfig);
    $uconfig{'theme'}      = "authentic-theme";
    $uconfig{'gotomodule'} = 'mailbox';
    $uconfig{'ui_show'}    = 'host time';
    usermin::put_usermin_config(\%uconfig);
    usermin::get_usermin_miniserv_config(\%uminiserv);
    $uminiserv{'preroot'}         = "authentic-theme";
    $uminiserv{'ssl'}             = "1";
    $uminiserv{'ssl_cipher_list'} = $webmin::strong_ssl_ciphers;
    $uminiserv{'domainuser'}      = 1;
    $uminiserv{'domainstrip'}     = 1;

    # Enable 2FA
    $uminiserv{'twofactor_provider'} = 'totp';
    $uminiserv{'twofactorfile'}
      ||= "$usermin::config{'usermin_dir'}/twofactor-users";
    $uminiserv{'twofactor_wrapper'}
      = "$usermin::config{'usermin_dir'}/twofactor/twofactor.pl";
    usermin::create_cron_wrapper($uminiserv{'twofactor_wrapper'},
      "twofactor", "twofactor.pl");
    my (%uacl, %umdirs);
    lock_file(usermin::usermin_acl_filename());
    usermin::read_usermin_acl(\%uacl, \%umdirs);
    push(@{$umdirs{'user'}}, 'twofactor');
    usermin::save_usermin_acl("user", $umdirs{'user'});
    unlock_file(usermin::usermin_acl_filename());

    usermin::put_usermin_miniserv_config(\%uminiserv);

    if (init::status_action("usermin")) {
      usermin::restart_usermin_miniserv();
    }
    else {
      usermin::start_usermin();
    }

    # Start Usermin at boot
    foreign_require("init", "init-lib.pl");
    init::enable_at_boot("usermin");

    # More configuration for non-mini stack
    my $mini_stack =
      (defined $self->bundle() && $self->bundle() =~ /mini/i) ?
        ($self->bundle() =~ /LEMP/i ? 'LEMP' : 'LAMP') : 0;

    if (!$mini_stack) {
      # Get the Postfix virtual map file, if Postfix is installed
      my $map;
      if (foreign_installed("postfix")) {
        foreign_require("postfix");
        ($map) = postfix::get_maps_files(
          postfix::get_real_value($postfix::virtual_maps));
      }
      # Setup the Usermin read mail module
      my $cfile = "$usermin::config{'usermin_dir'}/mailbox/config";
      my %mailconfig;
      read_file($cfile, \%mailconfig);
      $mailconfig{'from_map'}         = $map || "/etc/postfix/virtual";
      $mailconfig{'from_format'}      = 1;
      $mailconfig{'mail_system'}      = 4;
      $mailconfig{'pop3_server'}      = 'localhost';
      $mailconfig{'mail_qmail'}       = undef;
      $mailconfig{'mail_dir_qmail'}   = 'Maildir';
      $mailconfig{'server_attach'}    = 0;
      $mailconfig{'send_mode'}        = 'localhost';
      $mailconfig{'nologout'}         = 1;
      $mailconfig{'noindex_hostname'} = 1;
      $mailconfig{'edit_from'}        = 0;
      write_file($cfile, \%mailconfig);

      # Set the mail folders subdir to Maildir
      my $ucfile = "$usermin::config{'usermin_dir'}/mailbox/uconfig";
      my %umailconfig;
      read_file($ucfile, \%umailconfig);
      $umailconfig{'mailbox_dir'} = 'Maildir';
      $umailconfig{'view_html'}   = 2;
      $umailconfig{'view_images'} = 1;
      $umailconfig{'delete_mode'} = 1;

      # Configure the Usermin Mailbox module to display buttons on the top too
      $umailconfig{'top_buttons'} = 2;

      # Configure the Usermin Mailbox module not to display send buttons twice
      $umailconfig{'send_buttons'} = 0;

      # Configure the Usermin Mailbox module to always start with one attachment
      # for type
      $umailconfig{'def_attach'} = 1;

      # Default mailbox name for Sent mail
      $umailconfig{'sent_name'} = 'Sent';
      write_file($ucfile, \%umailconfig);

      # Set the default Usermin ACL to only allow access to the needed modules
      usermin::save_usermin_acl(
        "user",
        [
          "mailbox",  "changepass", "spam",    "filter",
          "language", "forward",    "cron",    "fetchmail",
          "updown",   "schedule",   "filemin", "gnupg"
        ]
      );

      # Update user.acl
      my $afile = "$usermin::config{'usermin_dir'}/user.acl";
      my %uacl;
      read_file($afile, \%uacl);
      $uacl{'root'} = '';
      write_file($afile, \%uacl);

      # Configure the Usermin Change Password module to use Virtualmin's
      # change-password.pl script
      $cfile = "$usermin::config{'usermin_dir'}/changepass/config";
      my %cpconfig;
      read_file($cfile, \%cpconfig);
      $cpconfig{'passwd_cmd'}
        = $config_directory eq "/etc/webmin"
        ? "$root/virtual-server/change-password.pl"
        : "virtualmin change-password";
      $cpconfig{'cmd_mode'} = 1;
      write_file($cfile, \%cpconfig);

      # Also do the same thing for expired password changes
      $cfile = "$usermin::config{'usermin_dir'}/config";
      my %umconfig;
      read_file($cfile, \%umconfig);
      $umconfig{'passwd_cmd'} = "$root/virtual-server/change-password.pl";
      write_file($cfile, \%umconfig);

      # Configure the Usermin Filter module to use the right path for
      # Webmin config files. The defaults are incorrect on FreeBSD, where
      # we install under /usr/local/etc/webmin
      $cfile = "$usermin::config{'usermin_dir'}/filter/config";
      my %ficonfig;
      read_file($cfile, \%ficonfig);
      $ficonfig{'virtualmin_config'} = "$config_directory/virtual-server";
      $ficonfig{'virtualmin_spam'}
        = "$config_directory/virtual-server/lookup-domain.pl";
      write_file($cfile, \%ficonfig);

      # Same for Usermin custom commands
      $cfile = "$usermin::config{'usermin_dir'}/commands/config";
      my %ccconfig;
      read_file($cfile, \%ccconfig);
      $ccconfig{'webmin_config'} = "$config_directory/custom";
      write_file($cfile, \%ccconfig);

      # Same for Usermin .htaccess files
      $cfile = "$usermin::config{'usermin_dir'}/htaccess/config";
      my %htconfig;
      read_file($cfile, \%htconfig);
      $htconfig{'webmin_apache'} = "$config_directory/apache";
      write_file($cfile, \%htconfig);
    }

    $self->done(1);    # OK!
  };
  if ($@) {
    $log->error("Error configuring Usermin: $@");
    $self->done(0);    # NOK!
  }
}

1;
