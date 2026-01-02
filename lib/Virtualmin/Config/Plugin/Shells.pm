package Virtualmin::Config::Plugin::Shells;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';
use Time::HiRes qw( sleep );    # XXX Figure out how to not need this.

our $config_directory;
our (%gconfig, %miniserv);

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Shells', %args);

  return $self;
}

sub actions {
  my $self = shift;

  $self->use_webmin();

  $self->spin();
  sleep 0.3;    # XXX Useless sleep, prevent spin from ending before it starts
  eval {
    my $lref = read_file_lines("/etc/shells");
    my $idx  = indexof("/bin/false", @$lref);
    if ($idx < 0) {

      # XXX Do we need jk_chrootsh here, or is it added by the package?
      push(@$lref, "/bin/false");
      flush_file_lines("/etc/shells");
    }
    $self->done(1);    # OK!
  };
  if ($@) {
    $log->error("Error configuring Shells: $@");
    $self->done(0);
  }
}

1;
