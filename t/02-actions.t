use Test::More;
use 5.010;

# Test actions in the Dummy bundle, on a test data set
require_ok('Virtualmin::Config');

use Cwd;
my $cwd = getcwd();

SKIP: {
  skip "Webmin isn't installed.", 3
    if (!-e "/usr/libexec/webmin/web-lib-funcs.pl");

  $ENV{'WEBMIN_CONFIG'}   = $cwd . "/t/data/etc/webmin";
  $ENV{'WEBMIN_VAR'}      = $cwd . "/t/data/var/webmin";
  $ENV{'MINISERV_CONFIG'} = $ENV{'WEBMIN_CONFIG'} . "/miniserv.conf";

# Copy a test config file
  use File::Copy;
  copy(
    "$cwd/t/data/etc/webmin/miniserv.conf.orig",
    "$cwd/t/data/etc/webmin/miniserv.conf"
  );

  my $bundle = Virtualmin::Config->new(bundle => 'Dummy', log => '/dev/null');
  ok($bundle->{bundle} eq 'Dummy', "Bundle is Dummy");

  ok($bundle->run(), "Config->run()");

  ok(file_changed(), "Config file changed");

  clean_up();

# Check to be sure the change within the actions in Test.pm plugin were applied
  sub file_changed {
    open(my $miniserv, "<", "$cwd/t/data/etc/webmin/miniserv.conf")
      || die "Cannot open miniserv.conf";
    while (<$miniserv>) {
      return $_ if /dummy-theme/;
    }
  }

  sub clean_up {
    if (-e "$cwd/t/data/etc/webmin/miniserv.conf") {
      unlink "$cwd/t/data/etc/webmin/miniserv.conf";
    }
  }

}
done_testing();
