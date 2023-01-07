package Virtualmin::Config::Plugin::Virtualmin;
use strict;
use warnings;
no warnings qw(once);
no warnings 'uninitialized';
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self
    = $class->SUPER::new(name => 'Virtualmin', depends => ['Usermin'], %args);

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. XXX Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;

  use Cwd;
  my $cwd  = getcwd();
  my $root = $self->root();
  chdir($root);
  $0 = "$root/virtual-server/config-system.pl";
  push(@INC, $root);
  eval 'use WebminCore';    ## no critic
  init_config();

  $self->spin();
  eval {
    my %vconfig = foreign_config("virtual-server");
    $vconfig{'mail_system'} = 0;
    $vconfig{'nopostfix_extra_user'} = 1;
    $vconfig{'aliascopy'}   = 1;
    $vconfig{'home_base'}   = "/home";
    $vconfig{'webalizer'}   = 0;
    # XXX If not run as part of bundle, it'll skip doing these mail-related configs, which is maybe sub-optimal
    if (defined $self->bundle() && ($self->bundle() eq "MiniLEMP" || $self->bundle() eq "MiniLAMP")) {
      $vconfig{'spam'}       = 0;
      $vconfig{'virus'}      = 0;
      $vconfig{'postgresql'} = 0;
    }
    elsif (defined $self->bundle()) {
      $vconfig{'spam'}       = 1;
      $vconfig{'virus'}      = 1;
      $vconfig{'postgresql'} = 1;
    }
    $vconfig{'ftp'}              = 0;
    $vconfig{'logrotate'}        = 3;
    $vconfig{'default_procmail'} = 1;
    $vconfig{'bind_spfall'}      = 0;
    $vconfig{'bind_spf'}         = "yes";
    $vconfig{'spam_delivery'}    = "\$HOME/Maildir/.spam/";
    $vconfig{'bccs'}             = 1;
    $vconfig{'reseller_theme'}   = "authentic-theme";
    $vconfig{'append_style'}     = 6;

    if ($self->bundle() eq "LEMP" || $self->bundle() eq "MiniLEMP") {
      $vconfig{'ssl'}                  = 0;
      $vconfig{'web'}                  = 0;
      $vconfig{'backup_feature_ssl'}   = 0;
    }
    elsif (defined $self->bundle()) {
      $vconfig{'ssl'} = 3;
    }
    if (!defined($vconfig{'plugins'})) {
      # Module `virtualmin-htpasswd` is only meant for Apache
      my $vmhtpass = 
          ($self->bundle() ne "LEMP" && $self->bundle() ne "MiniLEMP") ? 'virtualmin-htpasswd' : '';
      if ($self->bundle() eq "MiniLAMP") {
        $vconfig{'plugins'} = $vmhtpass;
      }
      else {
        $vconfig{'plugins'}
          = 'virtualmin-awstats';
        $vconfig{'plugins'}
          .= " $vmhtpass" if ($vmhtpass);
      }
    }
    if (-e "/etc/debian_version" || -e "/etc/lsb-release") {
      $vconfig{'proftpd_config'}
        = 'ServerName ${DOM}	<Anonymous ${HOME}/ftp>	User ftp	Group nogroup	UserAlias anonymous ftp	<Limit WRITE>	DenyAll	</Limit>	RequireValidShell off	</Anonymous>';
    }

    # Make the Virtualmin web directories a bit more secure
    # FreeBSD has a low secondary groups limit..skip this bit.
    # XXX ACLs can reportedly deal with this...needs research.
    unless ($gconfig{'os_type'} eq 'freebsd') {
      if (defined(getpwnam("www-data"))) {
        $vconfig{'web_user'} = "www-data";
      }
      else {
        $vconfig{'web_user'} = "apache";
      }
      $vconfig{'html_perms'} = "0750";
    }

    # Always force PHP-FPM mode
    $vconfig{'php_suexec'} = 3;

    # If system doesn't have Jailkit support, disable it
    if (!has_command('jk_init')) {
      $vconfig{'jailkit_disabled'} = 1;
    }

    # If system doesn't have AWStats support, disable it
    if (foreign_check("virtualmin-awstats")) {
      my %awstats_config = foreign_config("virtualmin-awstats");
      if ($awstats_config{'awstats'} &&
          !-r $awstats_config{'awstats'}) {
        my @plugins = split(/\s/, $vconfig{'plugins'});
        @plugins = grep { $_ ne 'virtualmin-awstats'} @plugins;
        $vconfig{'plugins'} = join(' ', @plugins);
      }
    }

    save_module_config(\%vconfig, "virtual-server");

    # Configure the Read User Mail module to look for sub-folders
    # under ~/Maildir
    my %mconfig = foreign_config("mailboxes");
    $mconfig{'mail_usermin'}    = "Maildir";
    $mconfig{'from_virtualmin'} = 1;
    save_module_config(\%mconfig, "mailboxes");

    # Setup the Usermin read mail module
    foreign_require("usermin", "usermin-lib.pl");
    my $cfile = "$usermin::config{'usermin_dir'}/mailbox/config";
    my %mailconfig;
    read_file($cfile, \%mailconfig);
    foreign_require("postfix", "postfix-lib.pl");
    my ($map)
      = postfix::get_maps_files(
      postfix::get_real_value($postfix::virtual_maps));
    $map ||= "/etc/postfix/virtual";
    $mailconfig{'from_map'}         = $map;
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
    $umailconfig{'view_html'} = 2;
    $umailconfig{'view_images'} = 1;
    # Configure the Usermin Mailbox module to display buttons on the top too
    $umailconfig{'top_buttons'} = 2;
    # Configure the Usermin Mailbox module not to display send buttons twice
    $umailconfig{'send_buttons'} = 0;
    # Configure the Usermin Mailbox module to always start with one attachment for type
    $umailconfig{'def_attach'} = 1;
    write_file($ucfile, \%umailconfig);

    # Set the default Usermin ACL to only allow access to email modules
    usermin::save_usermin_acl("user",
      ["mailbox", "changepass", "spam", "filter", 
       "language", "forward", "cron", "fetchmail", 
       "updown", "schedule", "filemin", "gnupg"]);

    # Lock down the Usermin file manager and browser to users' homes
    $cfile = "$usermin::config{'usermin_dir'}/file/config";
    my %fileconfig;
    read_file($cfile, \%fileconfig);
    $fileconfig{'home_only'} = 1;
    write_file($cfile, \%fileconfig);
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

    # Setup the Apache, BIND and DB modules to use tables for lists
    foreach my $t (
      ['apache',     'show_list'],
      ['bind8',      'show_list'],
      ['mysql',      'style'],
      ['postgresql', 'style']
      )
    {
      my %mconfig = foreign_config($t->[0]);
      $mconfig{$t->[1]} = 1;
      save_module_config(\%mconfig, $t->[0]);
    }

    # Make the default home directory permissions 750
    my %uconfig = foreign_config("useradmin");
    if ($gconfig{'os_type'} eq 'freebsd') {
      $uconfig{'homedir_perms'} = "0751";
    }
    else { $uconfig{'homedir_perms'} = "0750"; }
    save_module_config(\%uconfig, "useradmin");

    # Turn on caching for downloads by Virtualmin
    if (!$gconfig{'cache_size'}) {
      $gconfig{'cache_size'} = 50 * 1024 * 1024;
      $gconfig{'cache_mods'} = "virtual-server";
      write_file("$config_directory/config", \%gconfig);
    }

    # Fix to extend Jailkit [basicshell] paths
    if (has_command('jk_init') && foreign_check('jailkit')) {
      foreign_require('jailkit');
      my $jk_init_conf        = &jailkit::get_jk_init_ini();
      my $jk_basicshell_paths = $jk_init_conf->val('basicshell', 'paths');
      my @jk_basicshell_paths = split(/\s*,\s*/, $jk_basicshell_paths);
      my @jk_params = (
          ['zsh', '/etc/zsh/zshrc', '/etc/zsh/zshenv'],
          ['rbash'],
          ['id', 'groups'],
      );

      JKPARAMS:
      foreach my $jk_params (@jk_params) {
          foreach my $jk_param (@{$jk_params}) {
              if (grep(/^$jk_param$/, @jk_basicshell_paths)) {
                  next JKPARAMS;
              }
          }
          $jk_basicshell_paths .= ", @{[join(', ', @{$jk_params})]}";
      }

      $jk_init_conf->newval('basicshell', 'paths', $jk_basicshell_paths);
      &jailkit::write_jk_init_ini($jk_init_conf);
    }

    # Disable and stop certbot timer
    if (has_command('certbot')) {
      foreign_require('init', 'init-lib.pl');

      # Unit name is differnet on different distros
      my @certbot_units =
        ('certbot-renew.timer', 'certbot.timer');
      foreach my $certbot_unit (@certbot_units) {
        if (init::is_systemd_service($certbot_unit)) {
          init::disable_at_boot($certbot_unit);
          init::stop_action($certbot_unit);
          if (defined(&init::mask_action)) {
            init::mask_action($certbot_unit);
          }
        }
      }
    }

    # Terminal on the new installs
    # is allowed to have colors on
    if (&foreign_check('xterm')) {
      my %xterm_config = foreign_config("xterm");
      $xterm_config{'rcfile'} = 1;
      save_module_config(\%xterm_config, "xterm");
    }

    $self->done(1);    # OK!
  };
  if ($@) {
    $self->done(0);
  }
}

1;
