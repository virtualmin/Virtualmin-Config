package Virtualmin::Config::Plugin::Webmin;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

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
  eval 'use WebminCore';    ## no critic
  init_config();

  $self->spin();
  eval {
    foreign_require("webmin", "webmin-lib.pl");
    $gconfig{'nowebminup'}   = 1;
    $gconfig{'theme'}        = "authentic-theme";
    $gconfig{'mobile_theme'} = "authentic-theme";
    $gconfig{'logfiles'}     = 1;
    write_file("$config_directory/config", \%gconfig);
    get_miniserv_config(\%miniserv);
    $miniserv{'preroot'}         = "authentic-theme";
    $miniserv{'ssl'}             = 1;
    $miniserv{'ssl_cipher_list'} = $webmin::strong_ssl_ciphers;
    put_miniserv_config(\%miniserv);
    webmin::build_installed_modules(1);
    system("/etc/webmin/restart-by-force-kill > /dev/null 2>&1");
    $self->done(1);    # OK!
  };
  if ($@) {
    $self->done(0);    # NOK!
  }
}

1;
