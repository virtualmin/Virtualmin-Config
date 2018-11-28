package Virtualmin::Config::Plugin::Limits;
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
  my $self = $class->SUPER::new(name => 'Limits', %args);

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
  eval 'use WebminCore';    ## no critic
  init_config();

  $self->spin();
  eval {
    # Do we have /etc/sysctl.d?
    if (-d '/etc/sysctl.d') {
      open(my $fh, '>', '/etc/sysctl.d/10-virtualmin.conf')
        or die 'Unable to open /etc/sysctl.d/10-virtualmin.conf for writing';
      print $fh '# Increase inotify limit, for noticron';
      print $fh
        '# If, for some reason, you have more than a few thousand files';
      print $fh '# in /etc, increase this value (will use more memory).';
      print $fh 'fs.inotify.max_user_watches = 32768';
      close $fh;
    }
    elsif (-e '/etc/sysctl.conf') {    # sysctl.d, stick it into sysctl.conf
      open(my $fh, '+<', '/etc/sysctl.conf')
        or die 'Unable to open /etc/sysctl.conf for editing';
      my $skip;
      while (my $line = <$fh>) {
        if ($line =~ /fs.inotify.max_user_watches/) {
          $log->warning('Found existing configuration: $line');
          $log->warning('Cowardly refusing to overwrite it.');
          $skip = 1;
        }
      }
      unless ($skip) {
        print $fh 'fs.inotify.max_user_watches = 32768';
      }
      close $fh;
    }
  };
  if ($@) {
    $self->done(0);
  }
}

1;

=pod

=head1 Virtualmin::Config::Plugin::Limits

Modify limits in sysctl.conf or sysctl.d.

=head1 SYNOPSIS

virtualmin config-system --include Limits

=head1 LICENSE AND COPYRIGHT

Licensed under the GPLv3. Copyright 2017, Joe Cooper <joe@virtualmin.com>

=cut

