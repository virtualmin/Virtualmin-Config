use Test::More;
use 5.010;

require_ok('Virtualmin::Config::Plugin::Quotas');

{
  package Local::QuotaPlugin;

  sub new {
    my ($class, @results) = @_;
    return bless({commands => [], results => \@results}, $class);
  }

  sub logsystem {
    my ($self, $command) = @_;
    push(@{$self->{'commands'}}, $command);
    return shift(@{$self->{'results'}});
  }
}

no warnings qw(once redefine);

my ($foreign_module, $installed_package, $kernel_version);
local *Virtualmin::Config::Plugin::Quotas::backquote_command =
  sub { return "$kernel_version\n"; };
local *Virtualmin::Config::Plugin::Quotas::foreign_require =
  sub { $foreign_module = $_[0]; };
local *software::update_system_install = sub {
  $installed_package = $_[0];
  return $_[0];
};
local *Virtualmin::Config::Plugin::Quotas::capture_function_output_tempfile =
  sub {
    my ($function, @args) = @_;
    my @result = $function->(@args);
    return ('', \@result);
  };
local *Virtualmin::Config::Plugin::Quotas::html_strip = sub {
  my $output = $_[0];
  $output =~ s/<[^>]+>//g;
  return $output;
};
local *Virtualmin::Config::Plugin::Quotas::html_unescape = sub {
  my $output = $_[0];
  $output =~ s/&#39;/'/g;
  return $output;
};

subtest 'package output is converted from HTML to plain text' => sub {
  my $output = <<'EOF';
Installing with <tt>apt-get install quota</tt> ..
<pre data-installer>Sourcing file `/etc/default/grub&#39;
done
</pre>
EOF

  is(
    Virtualmin::Config::Plugin::Quotas::package_output_to_text($output),
    "Installing with apt-get install quota ..\n" .
      "Sourcing file `/etc/default/grub'\ndone"
  );
};

subtest 'existing module needs no package installation' => sub {
  %Virtualmin::Config::Plugin::Quotas::gconfig =
    (real_os_type => 'Ubuntu Linux');
  $foreign_module = undef;
  $installed_package = undef;
  $kernel_version = '6.8.0-124-generic';
  my $plugin = Local::QuotaPlugin->new(0);

  ok(Virtualmin::Config::Plugin::Quotas::load_quota_module($plugin));
  is($foreign_module, undef);
  is($installed_package, undef);
  is_deeply($plugin->{'commands'}, ['modprobe quota_v2']);
};

subtest 'missing Ubuntu generic module installs matching packages' => sub {
  %Virtualmin::Config::Plugin::Quotas::gconfig =
    (real_os_type => 'Ubuntu Linux');
  $foreign_module = undef;
  $installed_package = undef;
  $kernel_version = '6.8.0-124-generic';
  my $plugin = Local::QuotaPlugin->new(256, 0);

  ok(Virtualmin::Config::Plugin::Quotas::load_quota_module($plugin));
  is($foreign_module, 'software');
  is(
    $installed_package,
    'linux-modules-extra-6.8.0-124-generic linux-image-extra-virtual'
  );
  is_deeply(
    $plugin->{'commands'},
    ['modprobe quota_v2', 'modprobe quota_v2']
  );
};

subtest 'missing Ubuntu cloud module installs only versioned package' => sub {
  %Virtualmin::Config::Plugin::Quotas::gconfig =
    (real_os_type => 'Ubuntu Linux');
  $foreign_module = undef;
  $installed_package = undef;
  $kernel_version = '6.8.0-1050-aws';
  my $plugin = Local::QuotaPlugin->new(256, 0);

  ok(Virtualmin::Config::Plugin::Quotas::load_quota_module($plugin));
  is($foreign_module, 'software');
  is($installed_package, 'linux-modules-extra-6.8.0-1050-aws');
  is_deeply(
    $plugin->{'commands'},
    ['modprobe quota_v2', 'modprobe quota_v2']
  );
};

subtest 'missing non-Ubuntu module preserves existing behavior' => sub {
  %Virtualmin::Config::Plugin::Quotas::gconfig =
    (real_os_type => 'Debian Linux');
  $foreign_module = undef;
  $installed_package = undef;
  $kernel_version = '6.8.0-124-generic';
  my $plugin = Local::QuotaPlugin->new(256);

  ok(Virtualmin::Config::Plugin::Quotas::load_quota_module($plugin));
  is($foreign_module, undef);
  is($installed_package, undef);
  is_deeply($plugin->{'commands'}, ['modprobe quota_v2']);
};

done_testing();
