package Virtualmin::Config::Plugin::ClamAV;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';
use Time::HiRes qw( sleep );

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

sub new {
  my $class = shift;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'ClamAV');

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
  $0 = "$root/init-system.pl";
  push(@INC, $root);
  eval 'use WebminCore';    ## no critic
  init_config();

  $self->spin();
  sleep 0.2;                # XXX Pause to allow spin to start.
  eval {
    # Make sure freshclam is not disabled
    my $fcconf = "/etc/sysconfig/freshclam";
    if (-r $fcconf) {
            my $lref = &read_file_lines($fcconf);
            foreach my $l (@$lref) {
                    if ($l =~ /^FRESHCLAM_DELAY=disabled/) {
                            $l = "#$l";
                    }
            }
            flush_file_lines($fcconf);
    }
    system("freshclam --quiet");

    # Start clamd@scan and run clamdscan just to prime the damned thing.
    # XXX Make this work on Debian/Ubuntu, too.
    system('systemctl start clamd@scan');
    sleep 30; # XXX THis is ridiculous. But, clamd is ridiculous.
    my $res = `clamdscan --quiet --config-file=/etc/clamd.d/scan.conf /etc/webmin/miniserv.conf`;
    system('systemctl stop clamd@scan');
    # If RHEL/CentOS/Fedora, the clamav packages don't work, by default.
    if ( ! -e '/etc/clamd.conf' ) {
      eval { symlink('/etc/clamd.d/scan.conf', 'etc/clamd.conf'); }
    }
    if ($res) { die 1; }
    $self->done(1);    # OK!
  };
  if ($@) {
    $self->done(0);
  }
}

1;
