package Virtualmin::Config::Plugin::Apache;
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
  my $self = $class->SUPER::new(name => 'Apache', %args);

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
    foreign_require("init",   "init-lib.pl");
    foreign_require("apache", "apache-lib.pl");

    # Start Apache on boot
    if (-e '/etc/init.d/httpd' or -e '/etc/httpd/conf/httpd.conf') {
      init::enable_at_boot('httpd');
    }
    elsif (-e '/etc/init.d/apache2' or -e '/etc/apache2/apache2.conf') {
      init::enable_at_boot('apache2');
    }
    elsif (-e '/usr/local/etc/rc.d/apache22') {
      init::enable_at_boot('apache22');
    }

    # Make sure nginx isn't starting on boot, even if installed
    if (-d '/etc/nginx') {
      init::disable_at_boot('nginx');
    }

    # Fix up some Debian stuff
    if ($gconfig{'os_type'} eq "debian-linux") {
      if (-e "/etc/init.d/apache") { init::disable_at_boot("apache"); }
      $self->logsystem("a2dissite 000-default");
      $self->logsystem("a2dissite default-ssl.conf");

      if (!-e "/etc/apache2/conf.d/ssl.conf") {
        $self->logsystem("a2enmod ssl");
        `echo Listen 80 > /etc/apache2/ports.conf`;
        `echo Listen 443 >> /etc/apache2/ports.conf`;
      }

      # New Ubuntu doesn't use this.
      unless (-x "/bin/systemctl" || -x "/usr/bin/systemctl") {
        my $fn             = "/etc/default/apache2";
        my $apache2default = read_file_lines($fn) or die "Failed to open $fn!";
        my $idx            = indexof("NO_START=1");
        if ($idx) {
          $apache2default->[$idx] = "NO_START=0";
        }
        flush_file_lines($fn);
      }
    }

    # Handle missing fcgid dir
    if ($gconfig{'os_type'} =~ /debian-linux|ubuntu-linux/) {
      if (!-e "/var/lib/apache2/fcgid") {
        mkdir "/var/lib/apache2/fcgid";
      }
    }

    # On Debian and Ubuntu, enable some modules which are disabled by default
    if ($gconfig{'os_type'} =~ /debian-linux|ubuntu-linux/) {
      my $adir = "/etc/apache2/mods-available";
      my $edir = "/etc/apache2/mods-enabled";
      foreach my $mod (
        "actions",        "suexec",
        "auth_digest",    "dav_svn",
        "ssl",            "dav",
        "dav_fs",         "fcgid",
        "rewrite",        "proxy",
        "proxy_balancer", "proxy_connect",
        "proxy_http",     "slotmem_shm",
        "cgi",            "proxy_fcgi",
        "lbmethod_byrequests"
        )
      {
        if (-r "$adir/$mod.load" && !-r "$edir/$mod.load") {
          symlink("$adir/$mod.load", "$edir/$mod.load");
        }
        if (-r "$adir/$mod.conf" && !-r "$edir/$mod.conf") {
          symlink("$adir/$mod.conf", "$edir/$mod.conf");
        }
      }
      my $fn = "/etc/apache2/suexec/www-data";
      my $apache2suexec = read_file_lines($fn) or die "Failed to open $fn!";
      $apache2suexec->[0] = "/home";
      $apache2suexec->[1] = "public_html";
      flush_file_lines($fn);
    }

    # On Ubuntu 10, PHP is enabled in php5.conf in a way that makes it
    # impossible to turn off for CGI mode!
    foreach my $php5conf (
      "/etc/apache2/mods-available/php5.conf",
      "/etc/apache2/mods-enabled/php5_cgi.conf",
      "/etc/apache2/mods-available/php7.0.conf"
      )
    {
      if ($gconfig{'os_type'} eq 'debian-linux' && -r $php5conf) {
        my $lref = read_file_lines($php5conf);
        foreach my $l (@$lref) {
          if ( $l =~ /^\s*SetHandler/i
            || $l =~ /^\s*php_admin_value\s+engine\s+Off/i)
          {
            $l = "#" . $l;
          }
        }
        flush_file_lines($php5conf);
      }
    }

    # FreeBSD enables almost nothing, by default
    if ($gconfig{'os_type'} =~ /freebsd/) {
      my $fn = "/usr/local/etc/apache22/httpd.conf";
      my $apache22conf = read_file_lines($fn) or die "Failed to open $fn!";
      foreach my $l (@$apache22conf) {
        $l =~ s/#(Include .*httpd-ssl.conf)/$1/;
        $l =~ s/#(Include .*httpd-vhosts.conf)/$1/;
        $l =~ s/#(Include .*httpd-dav.conf)/$1/;
      }
      flush_file_lines($fn);

      # Load mod_fcgid
      open(my $FCGID, ">", "/usr/local/etc/apache22/Includes/fcgid.conf");
      print $FCGID "LoadModule fcgid_module libexec/apache22/mod_fcgid.so\n";
      print $FCGID "<IfModule mod_fcgid.c>\n";
      print $FCGID "  AddHandler fcgid-script .fcgi\n";
      print $FCGID "</IfModule>\n";
      close($FCGID);
    }

    # Comment out config files that conflict
    foreach my $file ("/etc/httpd/conf.d/welcome.conf",
      "/etc/httpd/conf.d/php.conf", "/etc/httpd/conf.d/awstats.conf")
    {
      next if (!-r $file);
      my $lref = read_file_lines($file);
      foreach my $l (@$lref) {
        if ($l !~ /^\s*#/) {
          $l = "#" . $l;
        }
      }
      flush_file_lines($file);
    }

    # Remove default SSL VirtualHost on RH systems
    if (-r '/etc/httpd/conf.d/ssl.conf') {
      my $file                 = '/etc/httpd/conf.d/ssl.conf';
      my $lref                 = read_file_lines($file);
      my $virtual_host_section = 0;
      foreach my $l (@$lref) {
        if ($l !~ /^\s*#/) {
          if ($l =~ /^\s*<VirtualHost/) {
            $virtual_host_section = 1;
          }
          if ($virtual_host_section == 1) {
            $l = "#" . $l;
          }
          if ($l =~ /<\/VirtualHost/) {
            $virtual_host_section = 0;
          }
        }
      }
      flush_file_lines($file);
    }

    # Disable global UserDir option
    my $conf = apache::get_config();
    my ($userdir) = apache::find_directive_struct("UserDir", $conf);
    if ($userdir) {
      apache::save_directive("UserDir", [], $conf, $conf);
      flush_file_lines($userdir->{'file'});
    }

    # Force use of PCI-compliant SSL ciphers
    foreign_require("webmin", "webmin-lib.pl");
    apache::save_directive("SSLProtocol", ["ALL -SSLv2 -SSLv3"], $conf, $conf);
    if (!apache::find_directive("SSLCipherSuite", $conf)) {
      apache::save_directive("SSLCipherSuite",
        ["HIGH:!SSLv2:!ADH:!aNULL:!eNULL:!NULL"],
        $conf, $conf);
    }

    # Turn off server signatures, which aren't PCI compliant
    apache::save_directive("ServerTokens",    ["Minimal"], $conf, $conf);
    apache::save_directive("ServerSignature", ["Off"],     $conf, $conf);
    apache::save_directive("TraceEnable",     ["Off"],     $conf, $conf);
    flush_file_lines();

    if (!apache::is_apache_running()) {
      my $err = apache::start_apache();
      $log->error("Failed to start Apache!") if ($err);
    }

    # Force re-check of installed Apache modules
    unlink($apache::site_file)
      or $log->error("Failed to unlink $apache::site_file");
    $self->done(1);    # OK!
  };
  if ($@) {
    $self->done(0);    # NOK!
  }
}

1;
