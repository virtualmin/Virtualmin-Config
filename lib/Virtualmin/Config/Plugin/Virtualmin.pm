package Virtualmin::Config::Plugin::Virtualmin;
use strict;
use warnings;
no warnings qw(once);
no warnings 'uninitialized';
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);
our (%config, $module_config_file);
our $trust_unknown_referers = 1;

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self
    = $class->SUPER::new(name => 'Virtualmin', %args);

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
  push(@INC, "$root/vendor_perl");
  eval 'use WebminCore';    ## no critic
  init_config();

  $self->spin();
  eval {
    my $mini_stack =
      (defined $self->bundle() && $self->bundle() =~ /mini/i) ?
        ($self->bundle() =~ /LEMP/i ? 'LEMP' : 'LAMP') : 0;
    foreign_require("virtual-server");
    lock_file($module_config_file);
    $virtual_server::config{'mail_system'}          = 0;
    $virtual_server::config{'nopostfix_extra_user'} = 1;
    $virtual_server::config{'aliascopy'}            = 1;
    $virtual_server::config{'home_base'}            = "/home";
    $virtual_server::config{'webalizer'}            = 0;
    $virtual_server::config{'postgresql'}           = 0;
    $virtual_server::config{'ftp'}                  = 0;
    $virtual_server::config{'logrotate'}            = 3;
    $virtual_server::config{'bind_spfall'}          = 0;
    $virtual_server::config{'bind_spf'}             = "yes";
    $virtual_server::config{'bccs'}                 = 1;
    $virtual_server::config{'reseller_theme'}       = "authentic-theme";
    $virtual_server::config{'append_style'}         = 6;

    # For mini stack
    if ($mini_stack) {
      $virtual_server::config{'mail_system'} = 99;
      $virtual_server::config{'spam'}        = 0;
      $virtual_server::config{'virus'}       = 0;
      $virtual_server::config{'dns'}         = 0;
      $virtual_server::config{'mail'}        = 0;
    }
    elsif (defined $self->bundle()) {
      $virtual_server::config{'spam'}       = 1;
      $virtual_server::config{'virus'}      = 1;
      $virtual_server::config{'default_procmail'} = 1,
      $virtual_server::config{'spam_delivery'}    = "\$HOME/Maildir/.spam/"
    }

    if (defined $self->bundle() && $self->bundle() =~ /LEMP/i) {
      $virtual_server::config{'ssl'}                = 0;
      $virtual_server::config{'web'}                = 0;
      $virtual_server::config{'backup_feature_ssl'} = 0;
    }
    elsif (defined $self->bundle()) {
      $virtual_server::config{'ssl'} = 3;
    }

    # Enable extra default modules
    my @plugins = split /\s+/, ($virtual_server::config{'plugins'} || '');
    push(@plugins, 'virtualmin-awstats', 'virtualmin-htpasswd');
    if ($virtual_server::virtualmin_pro) {
      push(@plugins, 'virtualmin-wp-workbench');
    }
    $virtual_server::config{'plugins'} = join(' ', unique(@plugins));
    
    if ((!$mini_stack) &&
        (-e "/etc/debian_version" || -e "/etc/lsb-release")) {
      $virtual_server::config{'proftpd_config'}
        = 'ServerName ${DOM}	<Anonymous ${HOME}/ftp>	User ftp	Group nogroup	UserAlias anonymous ftp	<Limit WRITE>	DenyAll	</Limit>	RequireValidShell off	</Anonymous>';
    }

    # Make the Virtualmin web directories a bit more secure
    # FreeBSD has a low secondary groups limit..skip this bit.
    # XXX ACLs can reportedly deal with this...needs research.
    unless ($gconfig{'os_type'} eq 'freebsd') {
      if (defined(getpwnam("www-data"))) {
        $virtual_server::config{'web_user'} = "www-data";
      }
      else {
        $virtual_server::config{'web_user'} = "apache";
      }
      $virtual_server::config{'html_perms'} = "0750";
    }

    # Always force PHP-FPM mode
    $virtual_server::config{'php_suexec'} = 3;

    # If system doesn't have Jailkit support, disable it
    if (!has_command('jk_init')) {
      $virtual_server::config{'jailkit_disabled'} = 1;
    }

    # If system doesn't have AWStats support, disable it
    if (foreign_check("virtualmin-awstats")) {
      my %awstats_config = foreign_config("virtualmin-awstats");
      if ($awstats_config{'awstats'} && !-r $awstats_config{'awstats'}) {
        my @plugins = split(/\s/, $virtual_server::config{'plugins'});
        @plugins = grep { $_ ne 'virtualmin-awstats' } @plugins;
        $virtual_server::config{'plugins'} = join(' ', @plugins);
      }
    }

    # Enable DKIM at install time
    if (!$mini_stack && -r "/etc/opendkim.conf") {
      my $dkim = virtual_server::get_dkim_config();
      if (ref($dkim) && !$dkim->{'enabled'}) {
        $dkim->{'selector'} = virtual_server::get_default_dkim_selector();
        $dkim->{'sign'} = 1;
        $dkim->{'enabled'} = 1;
        $dkim->{'extra'} = [ get_system_hostname() ];
        virtual_server::push_all_print();
        virtual_server::set_all_null_print();
        my $ok = virtual_server::enable_dkim($dkim, 1, 2048);
        virtual_server::pop_all_print();
        if ($ok) {
          $virtual_server::config{'dkim_enabled'} = 1;
        }
      }
    }

    # Try to request SSL certificate for the hostname
    if (defined($ENV{'VIRTUALMIN_INSTALL_TEMPDIR'}) &&
        !$virtual_server::config{'default_domain_ssl'} &&
        !$virtual_server::config{'wizard_run'})
    {
      my ($ok, $error) = virtual_server::setup_virtualmin_default_hostname_ssl();
      write_file_contents("$ENV{'VIRTUALMIN_INSTALL_TEMPDIR'}/virtualmin_ssl_host_status",
                          "SSL certificate request for the hostname : $ok : @{[html_strip($error)]}");
      if ($ok) {
        mkdir("$ENV{'VIRTUALMIN_INSTALL_TEMPDIR'}/virtualmin_ssl_host_success");
      }
      else {
        virtual_server::delete_virtualmin_default_hostname_ssl();
      }
    }

    # Save Virtualmin configuration after all changes are made
    save_module_config(\%virtual_server::config);
    unlock_file($module_config_file);

    # Configure the Read User Mail module to look for sub-folders
    # under ~/Maildir
    if (!$mini_stack) {
      my %mconfig = foreign_config("mailboxes");
      $mconfig{'mail_usermin'}    = "Maildir";
      $mconfig{'from_virtualmin'} = 1;
      $mconfig{'spam_buttons'} = 'list,mail';
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
      $umailconfig{'view_html'}   = 2;
      $umailconfig{'view_images'} = 1;
      $umailconfig{'delete_mode'} = 1;

      # Configure the Usermin Mailbox module to display buttons on the top too
      $umailconfig{'top_buttons'} = 2;

      # Configure the Usermin Mailbox module not to display send buttons twice
      $umailconfig{'send_buttons'} = 0;

      # Configure the Usermin Mailbox module to always start with one attachment for type
      $umailconfig{'def_attach'} = 1;

      # Default mailbox name for Sent mail
      $umailconfig{'sent_name'} = 'Sent';
      write_file($ucfile, \%umailconfig);

      # Set the default Usermin ACL to only allow access to email modules
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

    # Setup the Apache, BIND and DB modules to use tables for lists
    foreach my $t (
      ['apache',     'show_list'],
      ['bind8',      'show_list'],
      ['mysql',      'style'],
      ['postgresql', 'style']
      )
    {
      next if (!foreign_check($t->[0]));
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
      my @jk_params           = (
        ['zsh', '/etc/zsh/zshrc', '/etc/zsh/zshenv'],
        ['rbash'], ['id', 'groups'],
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
      my @certbot_units = ('certbot-renew.timer', 'certbot.timer');
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

    # Add PHP alias so users could execute
    # specific to virtual server PHP version
    my $profiled = "/etc/profile.d";
    if (-d $profiled) {
      my $profiledphpalias = "$profiled/virtualmin-phpalias.sh";
      my $phpalias
        = "php=\`which php 2>/dev/null\`\n"
        . "if \[ -x \"\$php\" \]; then\n"
        . "  alias php='\$\(phpdom=\"bin/php\" ; \(while [ ! -f \"\$phpdom\" ] && [ \"\$PWD\" != \"/\" ]; do cd \"\$\(dirname \"\$PWD\"\)\" || \"\$php\" ; done ; if [ -f \"\$phpdom\" ] ; then echo \"\$PWD/\$phpdom\" ; else echo \"\$php\" ; fi\)\)'\n"
        . "fi\n";
      write_file_contents($profiledphpalias, $phpalias);
    }

    # OpenSUSE PHP related fixes
    if ($gconfig{'os_type'} eq "suse-linux") {
      $self->logsystem("mv /etc/php8/fpm/php-fpm.conf.default /etc/php8/fpm/php-fpm.conf >/dev/null 2>&1");
    }

    # Disable mod_php in package managers
    if ($gconfig{'os_type'} =~ /debian-linux|ubuntu-linux/) {
      # Disable libapache2-mod-php* in Ubuntu/Debian
      my $fpref = $gconfig{'real_os_type'} =~ /ubuntu/i ? 'ubuntu' : 'debian';
      my $apt_pref_dir = "/etc/apt/preferences.d";
      if (!-d $apt_pref_dir) {
        # Create the directory if it doesn't exist
        make_dir($apt_pref_dir, oct(755));
      }
      # Create a file to restrict libapache2-mod-php* packages
      $self->logsystem(
        "echo \"Package: libapache2-mod-php*\nPin: release *\nPin-Priority: -1\" > ".
          "$apt_pref_dir/$fpref-virtualmin-restricted-packages");
    } else {
      # Disable php and php*-php in RHEL and derivatives
      my $dnf_conf = "/etc/dnf/dnf.conf";
      if (-f $dnf_conf) {
        lock_file($dnf_conf);
        my $lref = read_file_lines($dnf_conf);
        my $lnum;
        foreach my $i (0 .. $#$lref) {
          # If main section is found
          if ($lref->[$i] =~ /^\[main\]/) {
              $lnum = $i;
          }
          # If exclude= line is found, don't add another one
          if ($lref->[$i] =~ /^exclude=/) {
              $lnum = undef;
          }
        }
        # Add exclude= line if it's not
        # found right after [main]
        if (defined($lnum)) {
          $lref->[$lnum] .= "\nexclude=php php*-php";
        }
        flush_file_lines($dnf_conf);
        unlock_file($dnf_conf);
      }
    }

    $self->done(1);    # OK!
  };
  if ($@) {
    $log->error("Error configuring Virtualmin: $@");
    $self->done(0);
  }
}

1;
