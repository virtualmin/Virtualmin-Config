package Virtualmin::Config::Plugin::Firewall;
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
  my $self = $class->SUPER::new(name => 'Firewall', %args);

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
    my @tcpports
      = qw(ssh smtp submission smtps domain ftp ftp-data pop3 pop3s imap imaps http https 2222 10000:10100 20000 49152:65535);
    my @udpports = qw(domain);

    foreign_require("firewall", "firewall-lib.pl");
    my @tables   = firewall::get_iptables_save();
    my @allrules = map { @{$_->{'rules'}} } @tables;
    if (@allrules) {
      my ($filter) = grep { $_->{'name'} eq 'filter' } @tables;
      if (!$filter) {
        $filter = {
          'name'  => 'filter',
          'rules' => [],
          'defaults' =>
            {'INPUT' => 'ACCEPT', 'OUTPUT' => 'ACCEPT', 'FORWARD' => 'ACCEPT'}
        };
      }
      foreach (@tcpports) {

        $log->info("Allowing traffic on TCP port: $_\n");
        my $newrule = {
          'chain' => 'INPUT',
          'm'     => [['', 'tcp']],
          'p'     => [['', 'tcp']],
          'dport' => [['', $_]],
          'j'     => [['', 'ACCEPT']],
        };
        splice(@{$filter->{'rules'}}, 0, 0, $newrule);
      }
      foreach (@udpports) {

        $log->info("Allowing traffic on UDP port: $_\n");
        my $newrule = {
          'chain' => 'INPUT',
          'm'     => [['', 'udp']],
          'p'     => [['', 'udp']],
          'dport' => [['', $_]],
          'j'     => [['', 'ACCEPT']],
        };
        splice(@{$filter->{'rules'}}, 0, 0, $newrule);
      }
      firewall::save_table($filter);
      firewall::apply_configuration();
    }
    $self->done(1);    # OK!
  };
  if ($@) {
    $self->done(0);
  }
}

1;
