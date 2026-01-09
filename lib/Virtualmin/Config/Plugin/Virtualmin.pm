package Virtualmin::Config::Plugin::Virtualmin;
use strict;
use warnings;
no warnings qw(once);
no warnings 'uninitialized';
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);
our (%config, $module_name, $module_config_file);

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self
    = $class->SUPER::new(name => 'Virtualmin', %args);

  return $self;
}

sub actions {
  my $self = shift;

  $self->use_webmin();

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

    # Save Virtualmin configuration after all changes are made
    save_module_config(\%virtual_server::config, $module_name);
    unlock_file($module_config_file);

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
