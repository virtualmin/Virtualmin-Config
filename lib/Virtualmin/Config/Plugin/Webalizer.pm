package Virtualmin::Config::Plugin::Webalizer;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);

sub new {
  my $class = shift;
  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Webalizer');

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. XXX Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;

  use Cwd;
  my $cwd = getcwd();
  my $root = $self->root();
  chdir($root);
  $0 = "$root/init-system.pl";
  push(@INC, $root);
  eval 'use WebminCore'; ## no critic
  init_config();

  $self->spin();
  foreign_require("webalizer", "webalizer-lib.pl");
	my $conf = &webalizer::get_config();
	webalizer::save_directive($conf, "IncrementalName", "webalizer.current");
	webalizer::save_directive($conf, "HistoryName", "webalizer.hist");
	webalizer::save_directive($conf, "DNSCache", "dns_cache.db");
	flush_file_lines($webalizer::config{'webalizer_conf'});
  $self->done(1); # OK!
}

1;
