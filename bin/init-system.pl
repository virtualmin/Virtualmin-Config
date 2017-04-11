#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use Virtualmin::Config;

sub main {
  my ( $argv ) = @_;
  my %opt;
  my (@include, @exclude);
  my $bundle;
  GetOptions( \%opt,
    'help|h',
    'bundle|b=s',
    'include|i=s{1,}' => \@include,
    'exclude|x=s{1,}' => \@exclude,
  );
  pod2usage(0) if $opt{help};
  $opt{bundle} ||= "LAMP";

  #my $bundle = Virtualmin::Config->new(
  #  bundle    => $opt{bundle},
  #  include   => $opt{include},
  #  exclude   => $opt{exclude},
  #);

  use Data::Dumper;
  if (@include) { print Dumper(@include)};
  if (@exclude) { print Dumper(@exclude)};
  return 0;
}

exit main( \@ARGV );

=head1 NAME

init-system

=head1 SYNOPSIS

    # virtualmin init-system --bundle LEMP

=head1 ARGUMENTS

=item --bundle

A set of confguraion options, to initialize the system for use as a Virtualmin
system. Default plugin bundle is "LAMP", which configures Apache, as well as
a variety of other components.

The other commonly used bundle is "LEMP", which replaces Apache with nginx.

=item --include

Include an additional plugin. Works with or without a bundle specified.

If you are re-configuring a component after a system is in production, beware
that it may break configuration. It will only change the configuration options
that the plugin specifies...it does not "reset" the component to a default
state.

Multiple plugins can be included, but using multiple C<--include> options.

If not bundle is specified, only the included plugins will be used. Plugins
other than those specified may be installed to resolve dependencies. Dependency
resolution cannot be overriden.

=item --exclude

Exclude a plugin from either the default bundle, if no  bundle is specified,
or from the bundle specified.

=head1 EXIT CODES

Returns 0 on success, 1 on failure.

=head1 LICENSE AND COPYRIGHT

Licensed under the GPLv3. Copyright 2017, Joe Cooper <joe@virtualmin.com>
