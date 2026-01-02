package Virtualmin::Config::Plugin::Mailman;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Mailman', %args);

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. TODO Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;

  $self->use_webmin();

  if (foreign_check("mailman")) {
    $self->spin();
    eval {
      my $err;              # We should handle errors better here.
      foreign_require("virtualmin-mailman", "virtualmin-mailman-lib.pl");
      my @lists = virtualmin_mailman::list_lists();
      my ($mlist) = grep { $_->{'list'} eq 'mailman' } @lists;
      if (!$mlist) {

        # Need to create
        virtualmin_mailman::create_list(
          "mailman", undef, "Default mailing list",
          undef,
          "root\@" . get_system_hostname(),
          time() . $$
        );
      }

      $self->done(0);
    };
    if ($@) {
      $log->error("Error configuring Mailman: $@");
      $self->done(1);
    }
  }
}

1;
