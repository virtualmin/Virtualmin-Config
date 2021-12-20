package Virtualmin::Config::Plugin::Webalizer;
use strict;
use warnings;
use 5.010;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';
use Cwd;

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Webalizer', %args);

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. XXX Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;
  my $cwd  = getcwd();
  my $root = $self->root();
  chdir($root);
  $0 = "$root/virtual-server/config-system.pl";
  push(@INC, $root);
  eval 'use WebminCore';    ## no critic
  init_config();

  $self->spin();

  if (has_command("webalizer")) {
    eval {
      foreign_require("webalizer", "webalizer-lib.pl");
      my $conf = webalizer::get_config();
      webalizer::save_directive($conf, "IncrementalName", "webalizer.current");
      webalizer::save_directive($conf, "HistoryName",     "webalizer.hist");
      webalizer::save_directive($conf, "DNSCache",        "dns_cache.db");
      flush_file_lines($webalizer::config{'webalizer_conf'});
      $self->done(1);         # OK!
    };
    if ($@) {
      $self->done(0);
    }
  } else {
      print "\nWebalizer package is not available for installation on this distro";
      print " " x 13;
      $self->done(2);
  }
}

1;
