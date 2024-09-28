package Virtualmin::Config::Plugin;
use strict;
use warnings;
use 5.010_001;
use POSIX;
use Virtualmin::Config;
use Time::HiRes qw( sleep );
use feature 'state';
use Term::ANSIColor qw(:constants colored);
use utf8;
use open ':std', ':encoding(UTF-8)';

our $trust_unknown_referers = 1;
our $error_must_die         = 1;

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;

  my $self = {
    name    => $args{name},
    depends => $args{depends},
    total   => $args{total},
    bundle  => $args{bundle}
  };
  bless $self, $class;

  return $self;
}

# Plugin short name, used in config definitions
sub name {
  my ($self, $name) = @_;
  if ($name) { $self->{name} = $name }
  return $self->{name};
}

# Return a ref to an array of plugins that have to run before this one.
# Dep resolution is very stupid. Don't do anything complicated.
sub depends {
  my ($self, $name) = @_;
  if ($name) { $self->{depends} = shift }
  return $self->{depends};
}

# Total number of plugins being run for running count
sub total {
  my ($self, $total) = @_;
  if ($total) { $self->{total} = shift }
  return $self->{total};
}

sub bundle {
  my ($self, $bundle) = @_;
  if ($bundle) { $self->{bundle} = shift }
  return $self->{bundle};
}

sub spin {
  state $count = 1;
  my $self    = shift;
  my $name    = $self->name();
  my $message = shift // "Configuring " . format_plugin_name($name);
  $log->info($message);
  spinner("new");
  $message
    = "["
    . YELLOW
    . $count
    . RESET . "/"
    . GREEN
    . $self->total()
    . RESET . "] "
    . $message;
  my $color_correction = length(YELLOW . RESET . GREEN . RESET);
  $count++;
  $message = $message
    . " " x (79 - length($message) - spinner("lastsize") + $color_correction);
  print $message;
  spinner("auto_start");
}

sub done {
  my $self = shift;
  my $res  = shift;
  spinner('auto_done');
  if ($res == 1) {

    # Success!
    $log->info("Succeeded");
    spinner("ok");
  }
  elsif ($res == 2) {

    # Not quite OK
    $log->warn("Non-fatal error");
    spinner("meh");
  }
  else {
    # Failure!
    $log->warn("Failed");
    spinner("nok");
  }
}

sub root {
  my $self = shift;

  $ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
  $ENV{'WEBMIN_VAR'}    ||= "/var/webmin";
  $ENV{'MINISERV_CONFIG'} = $ENV{'WEBMIN_CONFIG'} . "/miniserv.conf";
  open(my $CONF, "<", "$ENV{'WEBMIN_CONFIG'}/miniserv.conf") || die RED,
    "Failed to open miniserv.conf", RESET;
  my $root;
  while (<$CONF>) {
    if (/^root=(.*)/) {
      $root = $1;
    }
  }
  close($CONF);
  $root ||= "/usr/libexec/webmin";

  return $root;
}

# format_plugin_name(plugin-name)
# Alters plugin name depending on the system software
sub format_plugin_name {
  my $name = shift;

  # Variations of database
  my $db = -x "/usr/bin/mariadb" ? "MariaDB" : "MySQL";
  if ($name eq 'MySQL') {
    $name = $db;
  }
  return $name;
}

# logsystem(command)
# Similar to system() or backticks but with logging.
# Runs a single system command, and returns the result code.
sub logsystem {
  my $self = shift;
  my $cmd  = shift;

  my $res = `$cmd 2>&1` // "[]";
  $log->info("Code: $? Result: $res");
  return $?;
}

sub spinner {
  my ($cmd) = @_;
  state $slastsize = 3;
  state $pos       = 1;
  state $schild;
  state $whitecolor;

  # Do we have shades of white?
  if (!$whitecolor) {
    my $colors = `tput colors 2>&1`;
    $whitecolor = 'white';
    $whitecolor = 'bright_white' if ($colors && $colors > 8);
  }

  # Is new spinner
  $slastsize = 3, $pos = 1, $schild = undef, return if ($cmd eq 'new');

  my $sseq = [
    qw(▒▒▒ █▒▒ ██▒ ███ ▒██ ▒▒█ ▒▒▒)];
  my $sbksp = chr(0x08);
  my $start = sub {
    print "\x1b[?25l";
    $slastsize = 3;
    print colored("$sseq->[0]", 'cyan');
  };
  my $done = sub { print $sbksp x $slastsize; print "\x1b[?25h"; };
  my $ok   = sub { say colored(" ✔ ", "$whitecolor on_green"); };
  my $meh  = sub { say colored(" ⚠ ", "$whitecolor on_yellow"); };
  my $nok  = sub { say colored(" ✘ ", "$whitecolor on_red"); };

  my $next = sub {
    print $sbksp x $slastsize;
    print colored("$sseq->[$pos]", 'cyan');
    $pos       = ++$pos % scalar @{$sseq};
    $slastsize = length($sseq->[$pos]);
  };

  # Fork and run spinner asynchronously, until signal received.
  my $auto_start = sub {
    my $ppid = $$;
    system('stty -echo 1>/dev/null 2>&1');
    my $pid  = fork();
    die("Failed to fork progress indicator.\n") unless defined $pid;

    if ($pid) {    # Parent
      $schild = $pid;
      return;
    }
    else {         # Kid stuff
      &$start();
      my $exists;
      while (1) {
        sleep 0.2;
        &$next();

        # Check to be sure parent is still running, if not, die
        $exists = kill 0, $ppid;
        unless ($exists) {
          &$done();
          exit 0;
        }
        $exists = "";
      }
      exit 0;    # Should never get here?
    }
  };

  my $auto_done = sub {
    kill 'KILL', $schild;
    system('stty echo 1>/dev/null 2>&1');
    my $pid = wait();
    &$done();
  };

  # Returns
  &$auto_start()    if ($cmd eq 'auto_start');
  &$auto_done()     if ($cmd eq 'auto_done');
  &$ok()            if ($cmd eq 'ok');
  &$meh()           if ($cmd eq 'meh');
  &$nok()           if ($cmd eq 'nok');
  return $slastsize if ($cmd eq 'lastsize');
}

1;
