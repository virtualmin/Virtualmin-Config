use strict;
use warnings;
no warnings 'once';
use Test::More;

require_ok('Virtualmin::Config::Plugin::Nginx');

# A failed restart must stop configuration and report plugin failure
my @commands;
my @statuses = (0, 256);
my @results;
my $config_saved = 0;
{
  no warnings 'redefine';
  local *Virtualmin::Config::Plugin::use_webmin = sub { return 1; };
  local *Virtualmin::Config::Plugin::spin = sub { return; };
  local *Virtualmin::Config::Plugin::done = sub {
    my ($self, $result) = @_;
    push(@results, $result);
  };
  local *Virtualmin::Config::Plugin::logsystem = sub {
    my ($self, $command) = @_;
    push(@commands, $command);
    return shift(@statuses);
  };
  local *Virtualmin::Config::Plugin::Nginx::sleep = sub { return; };
  local *Virtualmin::Config::Plugin::Nginx::foreign_config = sub { return; };
  local *Virtualmin::Config::Plugin::Nginx::save_module_config = sub {
    $config_saved++;
  };

  my $plugin = Virtualmin::Config::Plugin::Nginx->new(total => 1);
  $plugin->actions();
}

is_deeply(
  \@commands,
  ["systemctl enable nginx.service", "systemctl restart nginx.service"],
  "Nginx configuration stops after a failed restart"
);
is_deeply(\@results, [0], "failed restart reports plugin failure");
is($config_saved, 0, "Virtualmin configuration is not saved after failure");

done_testing();
