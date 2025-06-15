package Virtualmin::Config::Plugin::Usermin;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %uconfig, %uminiserv);
our $trust_unknown_referers = 1;

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
    foreign_require("init",    "init-lib.pl");
    foreign_require("usermin", "usermin-lib.pl");
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

    $self->done(1);    # OK!
  };
  if ($@) {
    $log->error("Error configuring Usermin: $@");
    $self->done(0);    # NOK!
  }
}

1;
