# Configure SSL for the hostname
package Virtualmin::Config::Plugin::SSL;
use strict;
use warnings;
no warnings qw(once);
no warnings 'uninitialized';
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);
our (%config, $module_config_file);

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;
  my $self = $class->SUPER::new(name => 'SSL', depends => ['Virtualmin'], %args);
  return $self;
}

sub actions {
  my $self = shift;

  $self->use_webmin();

  $self->spin();
  eval {
    foreign_require("virtual-server");

    my $rs = 2;

    # Delete any existing SSL cert for the hostname if present
    virtual_server::delete_virtualmin_default_hostname_ssl()
        if ($virtual_server::config{'default_domain_ssl'});

    # Try to request and set up an SSL certificate for the hostname
    my ($ok, $error) = virtual_server::setup_virtualmin_default_hostname_ssl();

    # Write status to log
    my $ok_text = $ok ? "Successful" : "Failed";
    $log->info("SSL certificate request for the hostname : ".
               "$ok_text : @{[html_strip($error)]}");
    
    # Delete unless successful
    if ($ok) {
        $rs = 1;
        # Pass status to installer if running in that mode
        my $installer_tmp_dir = $ENV{'VIRTUALMIN_INSTALL_TEMPDIR'};
        if (defined($installer_tmp_dir)) {
            mkdir("$installer_tmp_dir/virtualmin_ssl_host_success");
        }
    }
    else {
        virtual_server::delete_virtualmin_default_hostname_ssl();
    }

    $self->done($rs);    # Maybe OK!
  };
  if ($@) {
    $log->error("Error configuring SSL for the hostname: $@");
    $self->done(0);
  }
}

1;
