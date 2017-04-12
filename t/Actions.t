use Test::More;
# Test actions in the Dummy bundle, on a test data set

require_ok( 'Virtualmin::Config' );

$ENV{'WEBMIN_CONFIG'} = "t/data/etc/webmin";
$ENV{'WEBMIN_VAR'} = "t/data/var/webmin";
$ENV{'MINISERV_CONFIG'} = $ENV{'WEBMIN_CONFIG'}."/miniserv.conf";

my $bundle = Virtualmin::Config->new(
	bundle 		=> 'Dummy',
);

ok($bundle->run());

done_testing();
