use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;
use File::Temp qw(tempdir);

require_ok('Virtualmin::Config::Plugin::GoAccess');

my $tmp = tempdir(CLEANUP => 1);

# run_goaccess_plugin(module-installed, configured-path, found-path)
# Runs the plugin with mocked Webmin functions and returns the saved module
# configurations and the reported result.
sub run_goaccess_plugin
{
  my ($installed, $configured, $found) = @_;
  my (%saved, @done, @locks);
  my $plugin = bless({}, 'Virtualmin::Config::Plugin::GoAccess');

  local $Virtualmin::Config::Plugin::GoAccess::config_directory = '/etc/webmin';
  local *Virtualmin::Config::Plugin::GoAccess::use_webmin = sub { };
  local *Virtualmin::Config::Plugin::GoAccess::lock_file = sub {
    push(@locks, "lock $_[0]");
  };
  local *Virtualmin::Config::Plugin::GoAccess::unlock_file = sub {
    push(@locks, "unlock $_[0]");
  };
  local *Virtualmin::Config::Plugin::GoAccess::spin = sub { };
  local *Virtualmin::Config::Plugin::GoAccess::done = sub {
    my ($self, $status) = @_;
    push(@done, $status);
  };
  local *Virtualmin::Config::Plugin::GoAccess::foreign_check = sub {
    return $installed;
  };
  local *Virtualmin::Config::Plugin::GoAccess::foreign_config = sub {
    my ($module) = @_;
    return (goaccess => $configured) if ($module eq 'virtualmin-goaccess');
    return (plugins => 'virtualmin-goaccess virtualmin-nginx');
  };
  local *Virtualmin::Config::Plugin::GoAccess::has_command = sub { $found };
  local *Virtualmin::Config::Plugin::GoAccess::save_module_config = sub {
    my ($config, $module) = @_;
    # Every save must happen while its own config file is locked
    is($locks[-1], "lock /etc/webmin/$module/config",
       "$module is locked before saving");
    $saved{$module} = { %$config };
  };
  $plugin->actions();

  return { saved => \%saved, done => \@done, locks => \@locks };
}

# The configured parser works, so nothing needs to change
my $ok = run_goaccess_plugin(1, $^X, undef);
is_deeply($ok->{saved}, {}, 'working parser path leaves configuration alone');
is_deeply($ok->{done}, [1], 'working parser reports success');

# The parser lives somewhere else, so the module is pointed at it
my $moved = run_goaccess_plugin(1, "$tmp/missing", '/usr/local/bin/goaccess');
is($moved->{saved}{'virtualmin-goaccess'}{'goaccess'}, '/usr/local/bin/goaccess',
   'missing configured parser is replaced by the installed one');
ok(!exists($moved->{saved}{'virtual-server'}),
   'relocated parser keeps the plugin enabled');
is_deeply($moved->{done}, [1], 'relocated parser reports success');
is_deeply($moved->{locks},
   ['lock /etc/webmin/virtualmin-goaccess/config',
    'unlock /etc/webmin/virtualmin-goaccess/config'],
   'module configuration lock is released after saving');

# No parser at all, so the plugin is removed from Virtualmin
my $absent = run_goaccess_plugin(1, "$tmp/missing", undef);
is($absent->{saved}{'virtual-server'}{'plugins'}, 'virtualmin-nginx',
   'missing parser disables the plugin');
ok(!exists($absent->{saved}{'virtualmin-goaccess'}),
   'missing parser leaves the module configuration alone');
is_deeply($absent->{done}, [2], 'missing parser is reported as not installed');
is_deeply($absent->{locks},
   ['lock /etc/webmin/virtual-server/config',
    'unlock /etc/webmin/virtual-server/config'],
   'Virtualmin configuration lock is released after saving');

# The Webmin module itself is missing
my $nomodule = run_goaccess_plugin(0, undef, '/usr/bin/goaccess');
is($nomodule->{saved}{'virtual-server'}{'plugins'}, 'virtualmin-nginx',
   'missing module disables the plugin');
is_deeply($nomodule->{done}, [2], 'missing module is reported as not installed');

done_testing();
