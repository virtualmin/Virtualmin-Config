package Virtualmin::Config::Plugin::Apache;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;
my $log   = Log::Log4perl->get_logger("virtualmin-config-system");
my $delay = 3;

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
  push(@INC, "$root/vendor_perl");
  eval 'use WebminCore';    ## no critic
  init_config();

  $self->spin();
  eval {
    foreign_require("init");
    foreign_require("apache");

    # Start Apache on boot if disabled
    my @apache_cmds = ('apache2', 'httpd', 'httpd24');
    foreach my $service (@apache_cmds) {
      if (init::action_status($service) == 1) {
        init::enable_at_boot($service);
        last;
      }
    }

    # Disable default Apache sites
    if ($gconfig{'os_type'} eq "debian-linux") {
      $self->logsystem("a2dissite 000-default");
      $self->logsystem("a2dissite default-ssl.conf");
    }

    # Handle missing fcgid dir  (XXXXX no need for this?)
    # if ($gconfig{'os_type'} =~ /debian-linux|ubuntu-linux/) {
    #   if (!-e "/var/lib/apache2/fcgid") {
    #     mkdir "/var/lib/apache2/fcgid";
    #   }
    # }

    # Fix suEXEC path and document root
    my $fn            = "/etc/apache2/suexec/www-data";
    if (-r $fn) {
      my $apache2suexec = read_file_lines($fn);
      $apache2suexec->[0] = "/home";
      $apache2suexec->[1] = "public_html";
      flush_file_lines($fn);
    }
    
    # On Debian and Ubuntu, enable some modules which are disabled by default
    my @apache_mods = (
        "actions",       "suexec",
        "auth_digest",   "ssl",
        "fcgid",         "rewrite",
        "proxy",         "proxy_balancer",
        "proxy_connect", "proxy_http",
        "slotmem_shm",   "cgi",
        "proxy_fcgi",    "lbmethod_byrequests",
        "http2",         "include"
        );
    
      if ($gconfig{'os_type'} =~ /^(debian|ubuntu|suse)-linux$/) {
        # Enable required modules using proper command
        foreach my $mod (@apache_mods) {
            system("a2enmod", "--quiet", $mod)
              unless (system("a2query", "-m", $mod, ">/dev/null", "2>&1") == 0);
        }
      }

    # Configure RH systems
    if ($gconfig{'os_type'} eq 'redhat-linux') {
      # Comment out config files that conflict
      foreach my $file (
        "/etc/httpd/conf.d/welcome.conf",
        "/etc/httpd/conf.d/php.conf",
        "/etc/httpd/conf.d/awstats.conf") {
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
    }

    # Disable global UserDir option
    my $conf = apache::get_config();
    my ($userdir) = apache::find_directive_struct("UserDir", $conf);
    if ($userdir) {
      apache::save_directive("UserDir", [], $conf, $conf);
      flush_file_lines($userdir->{'file'});
    }

    # Force use of PCI-compliant SSL ciphers (Intermediate level)
    apache::save_directive("SSLProtocol", ["-all +TLSv1.2 +TLSv1.3"],
      $conf, $conf);
    apache::save_directive(
      "SSLOpenSSLConfCmd", [ "Curves X25519:prime256v1:secp384r1" ]
      $conf, $conf
    );
    my $SSLCipherSuite = "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-".
                         "SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-".
                         "GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-".
                         "CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-".
                         "AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305";
    apache::save_directive("SSLCipherSuite", [$SSLCipherSuite], $conf, $conf);
    apache::save_directive("SSLHonorCipherOrder", ["Off"], $conf, $conf);
    apache::save_directive("SSLSessionTickets", ["Off"], $conf, $conf);

    # Turn off server signatures, which aren't PCI compliant
    apache::save_directive("ServerTokens",    ["Prod"], $conf, $conf);
    apache::save_directive("ServerSignature", ["Off"],  $conf, $conf);
    apache::save_directive("TraceEnable",     ["Off"],  $conf, $conf);
    flush_file_lines();
    
    # Start Apache if not running
    if (!apache::is_apache_running()) {
      my $err = apache::start_apache();
      $log->error("Failed to start Apache : $err") if ($err);
    }

    # Force re-check of installed Apache modules
    unlink($apache::site_file)
      or $log->error("Failed to unlink $apache::site_file");
    # Flush the cache
    undef(@apache::get_config_cache);
    # Restart Apache
    my $rserr = apache::restart_apache();
    if ($rserr) {
      $log->error("Failed to restart Apache : $rserr");
      $self->done(0);  # NOK!
      return;
    }
    $self->done(1);    # OK!
  };
  if ($@) {
    $self->done(0);    # NOK!
  }
}

1;
