package Virtualmin::Config::Plugin::Procmail;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Procmail', %args);

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
    $self->done(0);
  }
}

1;
