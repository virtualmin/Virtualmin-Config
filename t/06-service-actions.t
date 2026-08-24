use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;

require_ok('Virtualmin::Config::Plugin');

my $plugin = Virtualmin::Config::Plugin->new(name => 'Test');

{
  local *init::start_action = sub { return (1, 'started'); };
  local *init::status_action = sub { return 1; };
  ok($plugin->run_service_action('start', 'example'),
    'successful service action returns true');
}

{
  local *init::restart_action = sub { return (0, " address in use\n"); };
  eval { $plugin->run_service_action('restart', 'example'); };
  like($@, qr/^Failed to restart example: address in use/,
    'failed service action includes the command output');
}

{
  local *init::start_action = sub { return (1, ''); };
  local *init::status_action = sub { return 0; };
  eval { $plugin->run_service_action('start', 'example'); };
  like($@, qr/^Failed to start example: example is not running/,
    'successful command with a stopped service reports failure');
}

{
  local *init::stop_action = sub { return (1, ''); };
  local *init::status_action = sub { return 1; };
  eval { $plugin->run_service_action('stop', 'example'); };
  like($@, qr/^Failed to stop example: example is still running/,
    'successful command with a running service reports failure');
}

eval { $plugin->run_service_action('invalid', 'example'); };
like($@, qr/^Unsupported service action 'invalid'/,
  'unsupported service action fails explicitly');

done_testing();
