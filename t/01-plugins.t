# Test whether plugin pruning and dependency resolution Works
use Test::More;
use 5.010;

require_ok('Virtualmin::Config');

my $bundle = Virtualmin::Config->new(bundle => 'Dummy');

my @plugins = $bundle->_gather_plugins();
ok(
  map {
    grep {/Test/}
      @{$_}
  } @plugins
);
ok(
  map {
    grep {/Test2/}
      @{$_}
  } @plugins
);

my $include  = Virtualmin::Config->new(include => ['Test']);
my @plugins2 = $include->_gather_plugins();
ok(
  map {
    grep {/^Test$/}
      @{$_}
  } @plugins2
);
ok(scalar @plugins2 == 1);

my $depends  = Virtualmin::Config->new(include => ['Test2']);
my @plugins3 = $depends->_gather_plugins();
my @resolved = $depends->_order_plugins(@plugins3);
ok(grep {/^Test2$/} @resolved);
ok(grep {/^Test$/} @resolved);    # did the dependency get pulled in?

done_testing();
