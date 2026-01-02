package Virtualmin::Config::Plugin::Procmail;
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
  my $self = $class->SUPER::new(name => 'Procmail', %args);

  return $self;
}

sub actions {
  my $self = shift;

  $self->use_webmin();

  $self->spin();
  eval {
    foreign_require("procmail", "procmail-lib.pl");
    my @recipes = procmail::get_procmailrc();
    my ($defrec, $orgrec);
    foreach my $r (@recipes) {
      if ($r->{'name'}) {
        if ($r->{'name'} eq "DEFAULT") {
          $defrec = $r;
        }
        elsif ($r->{'name'} eq "ORGMAIL") {
          $orgrec = $r;
        }
      }
    }
    if ($defrec) {

      # Fix up this DEFAULT entry
      $defrec->{'value'} = '$HOME/Maildir/';
      procmail::modify_recipe($defrec);
    }
    else {
      # Prepend a DEFAULT entry
      $defrec = {'name' => 'DEFAULT', 'value' => '$HOME/Maildir/'};
      if (@recipes) {
        procmail::create_recipe_before($defrec, $recipes[0]);
      }
      else {
        procmail::create_recipe($defrec);
      }
    }
    if ($orgrec) {

      # Fix up this ORGMAIL entry
      $orgrec->{'value'} = '$HOME/Maildir/';
      procmail::modify_recipe($orgrec);
    }
    else {
      # Prepend a ORGMAIL entry
      $orgrec = {'name' => 'ORGMAIL', 'value' => '$HOME/Maildir/'};
      if (@recipes) {
        procmail::create_recipe_before($orgrec, $recipes[0]);
      }
      else {
        procmail::create_recipe($orgrec);
      }
    }
    $self->done(1);    # OK!
  };
  if ($@) {
    $log->error("Error configuring Procmail: $@");
    $self->done(0);
  }
}

1;
