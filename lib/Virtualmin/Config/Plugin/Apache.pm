package Virtualmin::Config::Plugin::Apache;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

my $delay = 2;

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

    # Start Apache on boot if disabled
    foreign_require("init");
    my @apache_cmds = ('apache2', 'httpd', 'httpd24');
    foreach my $service (@apache_cmds) {
      if (init::action_status($service) == 1) {
        init::enable_at_boot($service);
        last;
      }
    }

    # Load Apache module
    foreign_require("apache");

    # On Debian and Ubuntu, enable some modules which are disabled by default
    my @apache_mods = qw(
      suexec ssl slotmem_shm rewrite proxy_http proxy_fcgi
      proxy_connect proxy_balancer proxy lbmethod_byrequests
      include http2 cgid fcgid auth_digest actions
    );
    # Configure Debian/Ubuntu and SUSE systems
    if ($gconfig{'os_type'} =~ /^(debian|ubuntu|suse)-linux$/) {
      # Enable required modules using proper command
      $self->logsystem("a2enmod --quiet @apache_mods ; sleep $delay");
      # Disable default Apache sites
      $self->logsystem("a2dissite --quiet 000-default default-ssl ; sleep $delay");
      # Fix suEXEC path and document root
      my $fn            = "/etc/apache2/suexec/www-data";
      if (-r $fn) {
        my $apache2suexec = read_file_lines($fn);
        $apache2suexec->[0] = "/home";
        $apache2suexec->[1] = "public_html";
        flush_file_lines($fn);
      }
      # Restart Apache to apply changes
      apache::restart_apache();
    }
    # Configure RH systems
    elsif ($gconfig{'os_type'} eq 'redhat-linux') {
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
      "SSLOpenSSLConfCmd", [ "Curves X25519:prime256v1:secp384r1" ],
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

    # Clear module cache to ensure changes take effect
    apache::clear_apache_modules_cache();

    # Restart Apache because it might not be running
    apache::restart_apache();

    $self->done(1);    # OK!
  };
  if ($@) {
    $log->error("Failed to configure Apache : $@");
    $self->done(0);    # NOK!
  }
}

1;
