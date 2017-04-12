use Test::More;

require_ok( 'Virtualmin::Config' );

my $bundle = Virtualmin::Config->new(
	bundle 		=> 'Dummy',
);
ok($bundle->{bundle} eq 'Dummy');

my $bundle2 = Virtualmin::Config->new(
	include		=> 'Test',
);
ok($bundle2->{include} eq 'Test');

my $bundle3 = Virtualmin::Config->new(
	bundle		=> 'Dummy',
	exclude		=> 'Test',
);
ok($bundle3->{exclude} eq 'Test');

done_testing();
