package Virtualmin::Config::Plugin::Dovecot;
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
  my $self = $class->SUPER::new(name => 'Dovecot', %args);

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
    foreign_require("init",    "init-lib.pl");
    foreign_require("dovecot", "dovecot-lib.pl");

    # Work out dirs for control and index files
    foreign_require("mount", "mount-lib.pl");
    my $indexes   = "";
    my ($homedir) = mount::filesystem_for_dir("/home");
    my ($vardir)  = mount::filesystem_for_dir("/var");
    if ($homedir ne $vardir) {
      if (!-d "/var/lib") {
        make_dir("/var/lib", oct(755));
      }
      if (!-d "/var/lib/dovecot-virtualmin") {
        make_dir("/var/lib/dovecot-virtualmin", oct(755));
      }
      make_dir("/var/lib/dovecot-virtualmin/index",   oct(777));
      make_dir("/var/lib/dovecot-virtualmin/control", oct(777));
      $indexes = ":INDEX=/var/lib/dovecot-virtualmin/index/%u"
        . ":CONTROL=/var/lib/dovecot-virtualmin/control/%u";
    }

    my $conf = dovecot::get_config();
    dovecot::save_directive($conf, "protocols", "imap pop3");
    if (dovecot::find("mail_location", $conf, 2)) {
      dovecot::save_directive($conf, "mail_location",
        "maildir:~/Maildir" . $indexes);
    }
    else {
      dovecot::save_directive($conf, "default_mail_env",
        "maildir:~/Maildir" . $indexes);
    }
    if (my $uidl_format = dovecot::find("pop3_uidl_format", $conf, 2)) {
      dovecot::save_directive($conf, "pop3_uidl_format", $uidl_format->{value});
    }
    dovecot::save_directive($conf, "disable_plaintext_auth", "no");
    my $am = dovecot::find_value("auth_mechanisms", $conf, 2);
    if ($am && $am !~ /login/) {
      $am .= " login";
      dovecot::save_directive($conf, "auth_mechanisms", $am);
    }
    flush_file_lines();

    #print "Enabling Dovecot POP3 and IMAP servers\n";
    init::enable_at_boot("dovecot");
    if (init::status_action('dovecot') != 1) {
      init::start_action('dovecot');
    }
    $self->done(1);    # OK!
  };
  if ($@) {
    $log->error("Failed to configure Dovecot: $@");
    $self->done(0);
  }
}

1;
