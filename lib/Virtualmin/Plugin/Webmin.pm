package Virtualmin::Config::Plugin::Webmin;
use strict;
use warnings;
use parent 'Virtualmin::Config::Plugin';

sub new {
  my $class = shift;
  # inherit from Plugin
  my $self = $class->SUPER->new();

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. XXX Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;

  $self->spin("Configuring Webmin");
  eval { # try
    foreign_require("webmin", "webmin-lib.pl");
    $gconfig{'theme'} = "authentic-theme";
    $gconfig{'logfiles'} = 1;
    write_file("$config_directory/config", \%gconfig);
    get_miniserv_config(\%miniserv);
    $miniserv{'preroot'} = "authentic-theme";
    $miniserv{'ssl'} = 1;
    $miniserv{'ssl_cipher_list'} = $webmin::strong_ssl_ciphers;
    put_miniserv_config(\%miniserv);
    restart_miniserv();
  }
  or do { # catch
    $self->done(0); # Something failed
  }
  $self->done(1); # OK!

  1;
}
