use Test::More skip_all => "Needs Webmin installed";
use 5.010;
# Test actions in the Dummy bundle, on a test data set
require_ok( 'Virtualmin::Config' );

use Cwd;
my $cwd = getcwd();

$ENV{'WEBMIN_CONFIG'} = $cwd . "/t/data/etc/webmin";
$ENV{'WEBMIN_VAR'} = $cwd . "/t/data/var/webmin";
$ENV{'MINISERV_CONFIG'} = $ENV{'WEBMIN_CONFIG'}."/miniserv.conf";

# Copy a test config file
use File::Copy;
copy ("$cwd/t/data/etc/webmin/miniserv.conf.orig", "$cwd/t/data/etc/webmin/miniserv.conf");

s
ok( $bundle->{bundle} eq 'Dummy', "Bundle is Dummy" );

ok( $bundle->run(), "Config->run()" );

ok( file_changed(), "Config file changed" );

# Check to be sure the change within the actions in Test.pm plugin were applied
sub file_changed {
  open(my $miniserv, "<", "$cwd/t/data/etc/webmin/miniserv.conf") ||
    die "Cannot open miniserv.conf";
  while (<$miniserv>) {
    return $_ if /dummy-theme/;
  }
}

done_testing();
