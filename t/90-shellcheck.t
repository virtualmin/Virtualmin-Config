use strict;
use warnings;

use File::Spec;
use Test::More;

sub shell_quote {
  my ($value) = @_;
  $value =~ s/'/'"'"'/g;
  return "'$value'";
}

my $shellcheck = $ENV{SHELLCHECK};
if (!$shellcheck) {
  for my $dir (File::Spec->path()) {
    my $candidate = File::Spec->catfile($dir, 'shellcheck');
    if (-x $candidate) {
      $shellcheck = $candidate;
      last;
    }
  }
}

plan skip_all => 'shellcheck not found in PATH' if !$shellcheck;

my @files = glob File::Spec->catfile('packaging', '*.sh');
plan skip_all => 'no packaging scripts found' if !@files;

my $cmd = join(' ', map { shell_quote($_) } ($shellcheck, @files));
my $output = `$cmd 2>&1`;
my $exit = $? >> 8;

is($exit, 0, 'shellcheck packaging scripts');
diag $output if $exit != 0;

done_testing();
