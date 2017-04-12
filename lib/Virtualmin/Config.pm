package Virtualmin::Config;
use strict;
use warnings;
no warnings qw(once); # We've got some globals that effect Webmin behavior
use 5.010_001; # Version shipped with CentOS 6. Nothing older.
use Getopt::Long qw( GetOptionsFromArray );
use Pod::Usage;
use Module::Load;
use List::Util qw(all);
use Term::ANSIColor qw(:constants);
use Term::Spinner::Color;

# globals
our (%gconfig, %uconfig, %miniserv, %uminiserv);
our ($root_directory, $config_directory);
our ($trust_unknown_referers, $no_acl_check, $error_must_die, $file_cache);

sub new {
  my ($class, %args) = @_;
  my $self = {};

  $self->{bundle} = $args{bundle};
  $self->{include} = $args{include};
  $self->{exclude} = $args{exclude};
	# Guesstimate our terminal size.
	#my ($lines, $cols) = `stty size`=~/(\d+)\s+(\d+)/?($1,$2):(25,80);
	#unless ($cols <= 80) { $cols = 80 };

	return bless $self, $class;
}

# Gathered plugins are processed
sub run {
	my $self = shift;

	$|=1; # No line buffering.

	# setup Webmin
	# XXX This should really just be "use Webmin::Core"
	# Setup Webmin environment
	$no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	$ENV{'MINISERV_CONFIG'} = $ENV{'WEBMIN_CONFIG'}."/miniserv.conf";
	$trust_unknown_referers = 1;
	open(my $CONF, "<", "$ENV{'WEBMIN_CONFIG'}/miniserv.conf") ||
	die RED, "Failed to open miniserv.conf", RESET;
	my $root;
	while(<$CONF>) {
		if (/^root=(.*)/) {
			$root = $1;
		}
	}
	close($CONF);
	$root ||= "/usr/libexec/webmin";
	chdir($root);
	# Make program appear by name, instead of 'perl' in ps/top
	$0 = "virtualmin-config";
	push(@INC, $root);
	eval "use WebminCore";
	init_config();
	# XXX Somehow get init_config() into $self->config, or something.

	$error_must_die = 1;

	my @plugins = $self->_gather_plugins();
	@plugins = $self->_topo_sort(@plugins);
	for (@plugins) {
		my $pkg = "Virtualmin::Config::Plugin::$_";
		load $pkg;
		my $plugin = $pkg->new();
		$pkg->actions();
	}
}

# Merges the selected bundle, with any extra includes, and removes excludes
sub _gather_plugins {
	my $self = shift;
  my @plugins;

  # If bundle specified, load it up.
  if ($self->{bundle}) {
    my $pkg = "Virtualmin::Config::$self->{bundle}";
	  load $pkg;
    my $bundle = $pkg->new();
    # Ask the bundle for a list of plugins
    @plugins = $bundle->plugins();
  }

	# Check with the command arguments
	if ($self->{'include'}) {
		for my $include ($self->{'include'}) {
			push (@plugins, $include) unless grep( /^$include$/, @plugins );
		}
	}

	# Check for excluded plugins
	if ($self->{'exclude'}) {
		for my $exclude ($self->{'exclude'}) {
			my @dix = reverse(grep { $plugins[$_] eq $exclude } 0..$#plugins);
			for (@dix) {
				splice(@plugins, $_, 1);
			}
		}
	}

	return @plugins;
}

# Take the gathered list of plugins and sort them to resolve deps
sub _order_plugins {
	my $self = shift;
	my @plugins = shift;
	my %plugin_details; # Will hold an array of hashes containing name/depends
	# Load up @plugin_details with name and dependency list
	for my $plugin_name (@plugins) {
		my $pkg = "Virtualmin::Config::Plugin::$plugin_name";
		load $pkg;
		my $plugin = $pkg->new();
		$plugin_details{$plugin->{'name'}} = $plugin->{'depends'};
	}
	return _topo_sort(%plugin_details);
}

# Topological sort on dependencies
sub _topo_sort {
	my %deps = @_;

	my %ba;
	while ( my ( $before, $afters_aref ) = each %deps ) {
		unless ( @{$afters_aref} ) {
			$ba{$before} = {};
		}
		for my $after ( @{ $afters_aref } ) {
			$ba{$before}{$after} = 1 if $before ne $after;
			$ba{$after} ||= {};
		}
	}
	my @rv;
	while ( my @afters = sort grep { ! %{ $ba{$_} } } keys %ba ) {
		push @rv, @afters;
		delete @ba{@afters};
		delete @{$_}{@afters} for values %ba;
	}

	return _uniq(@rv);
}

# uniq so we don't have to import List::MoreUtils
sub _uniq {
  my %seen;
  return grep { !$seen{$_}++ } @_;
}

1;
