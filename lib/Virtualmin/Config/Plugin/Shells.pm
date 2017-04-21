package Virtualmin::Config::Plugin::Shells;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

sub new {
  my $class = shift;
  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Shells');

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
  my $lref = &read_file_lines("/etc/shells");
	my $idx = &indexof("/bin/false", @$lref);
	if ($idx < 0) {
    # XXX Do we need jk_chrootsh here, or is it added by the package?
		push(@$lref, "/bin/false");
		flush_file_lines("/etc/shells");
	}
  $self->done(1); # OK!
}

1;
