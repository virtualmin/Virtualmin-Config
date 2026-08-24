use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;

require_ok('Virtualmin::Config::Plugin');

my $plugin = Virtualmin::Config::Plugin->new(name => 'Test');

{
  local *init::start_action = sub { return (1, 'started'); };
  ok($plugin->run_service_action('start', 'example'),
    'successful service action returns true');
}

{
  local *init::restart_action = sub { return (0, " address in use\n"); };
  eval { $plugin->run_service_action('restart', 'example'); };
  like($@, qr/^Failed to restart example: address in use/,
    'failed service action includes the command output');
}

eval { $plugin->run_service_action('invalid', 'example'); };
like($@, qr/^Unsupported service action 'invalid'/,
  'unsupported service action fails explicitly');

done_testing();
