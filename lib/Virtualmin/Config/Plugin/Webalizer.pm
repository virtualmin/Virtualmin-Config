package Virtualmin::Config::Plugin::Webalizer;
use strict;
use warnings;
use 5.010;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Webalizer', %args);

  return $self;
}

sub actions {
  my $self = shift;
  
  $self->use_webmin();

  $self->spin();

  if (has_command("webalizer")) {
    eval {
      foreign_require("webalizer", "webalizer-lib.pl");
      my $conf = webalizer::get_config();
      webalizer::save_directive($conf, "IncrementalName", "webalizer.current");
      webalizer::save_directive($conf, "HistoryName",     "webalizer.hist");
      webalizer::save_directive($conf, "DNSCache",        "dns_cache.db");
      flush_file_lines($webalizer::config{'webalizer_conf'});
      $self->done(1);    # OK!
    };
    if ($@) {
      $log->error("Error configuring Webalizer: $@");
      $self->done(0);
    }
  }
  else {
    $log->error("Webalizer is not installed on this system, skipping configuration.");
    $self->done(2);
  }
}

1;
