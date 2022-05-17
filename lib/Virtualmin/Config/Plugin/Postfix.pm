package Virtualmin::Config::Plugin::Postfix;
use strict;
use warnings;
no warnings qw(once);
use parent 'Virtualmin::Config::Plugin';

our $config_directory;
our (%gconfig, %miniserv);
our $trust_unknown_referers = 1;

my $log = Log::Log4perl->get_logger("virtualmin-config-system");

sub new {
  my ($class, %args) = @_;

  # inherit from Plugin
  my $self = $class->SUPER::new(name => 'Postfix', depends => [], %args );

  return $self;
}

# actions method performs whatever configuration is needed for this
# plugin. XXX Needs to make a backup so changes can be reverted.
sub actions {
  my $self = shift;

  use Cwd;
  my $cwd  = getcwd();
  my $root = $self->root();
  chdir($root);
  $0 = "$root/virtual-server/config-system.pl";
  push(@INC, $root);
  eval 'use WebminCore';    ## no critic
  init_config();

  $self->spin();
  eval {
    foreign_require("init",    "init-lib.pl");
    foreign_require("postfix", "postfix-lib.pl");

    # Alibaba Cloud images have a broken network config (no IPv6 lo)
    # that causes postconf to error out.
    {
      my $err
        = `sed -i "s/^inet_interfaces = localhost/inet_interfaces = all/" /etc/postfix/main.cf 2>&1`;
      if ($err) {
        $log->warning(
          "Something is wrong with the Postfix /etc/postfix/main.cf. Is it missing?"
        );
      }
    }

    # Debian doesn't get a default main.cf unless apt-get is run
    # interactively.
    if (!-e "/etc/postfix/main.cf" && -e "/usr/share/postfix/main.cf.debian") {
      system("cp /usr/share/postfix/main.cf.debian /etc/postfix/main.cf");
    }

    # FreeBSD doesn't get a default main.cf, or anything else
    if (!-e "/usr/local/etc/postfix/main.cf"
      && -e "/usr/local/etc/postfix/dist/main.cf")
    {
      system("cp /usr/local/etc/postfix/dist/* /usr/local/etc/postfix/");
    }

    my $postetc = $postfix::config{'postfix_config_file'};
    $postetc =~ s/\/[^\/]+$//;
    my @maptypes = `$postfix::config{'postfix_config_command'} -m`;
    chop(@maptypes);
    my $maptype = indexof("hash", @maptypes) >= 0 ? "hash" : "dbm";
    if (!postfix::get_real_value("virtual_alias_maps")) {
      postfix::set_current_value("virtual_alias_maps",
        "$maptype:$postetc/virtual", 1);
    }
    postfix::ensure_map("virtual_alias_maps");
    postfix::regenerate_virtual_table();

    # Setup BCC map
    if (!postfix::get_real_value("sender_bcc_maps")) {
      postfix::set_current_value("sender_bcc_maps", "$maptype:$postetc/bcc");
    }
    postfix::ensure_map("sender_bcc_maps");
    postfix::regenerate_bcc_table()
      if (defined(postfix::regenerate_bcc_table()));

    # Setup sender dependent map
    my ($major, $minor) = split(/\./, $postfix::postfix_version);
    if (($major >= 2 && $minor >= 7) || $major >= 3) {
      if (!postfix::get_real_value("sender_dependent_default_transport_maps")) {
        postfix::set_current_value("sender_dependent_default_transport_maps",
          "$maptype:$postetc/dependent");
      }
      postfix::ensure_map("sender_dependent_default_transport_maps");
      postfix::regenerate_any_table("sender_dependent_default_transport_maps");
    }

    my $wrapper = "/usr/bin/procmail-wrapper";
    postfix::set_current_value("mailbox_command",
      "$wrapper -o -a \$DOMAIN -d \$LOGNAME", 1);
    postfix::set_current_value("home_mailbox",    "Maildir/", 1);
    postfix::set_current_value("inet_interfaces", "all",      1);

    # Add smtp auth stuff to main.cf
    postfix::set_current_value("smtpd_sasl_auth_enable",      "yes",         1);
    postfix::set_current_value("smtpd_tls_security_level",    "may",         1);
    postfix::set_current_value("smtpd_sasl_security_options", "noanonymous", 1);
    postfix::set_current_value("broken_sasl_auth_clients",    "yes",         1);
    postfix::set_current_value("smtpd_recipient_restrictions",
      "permit_mynetworks permit_sasl_authenticated reject_unauth_destination",
      1);
    my $mydest = postfix::get_current_value("mydestination");
    my $myhost = get_system_hostname();

    if ($mydest !~ /\Q$myhost\E/) {
      postfix::set_current_value("mydestination", $mydest . ", " . $myhost, 1);
    }

    # Opportunistic encryption for outgoing mail
    my $seclvl = 
      compare_version_numbers($postfix::postfix_version, "2.11") >= 0 ?
        "dane" : "may";
    postfix::set_current_value("smtp_tls_security_level", $seclvl, 1);
    if ($seclvl eq "dane") {
      postfix::set_current_value("smtp_dns_support_level", "dnssec", 1);
      postfix::set_current_value("smtp_host_lookup", "dns", 1);
    }

    # Turn off limit on mailbox size
    postfix::set_current_value("mailbox_size_limit", "0");

    # Turn off % hack, which breaks user%domain mailboxes
    postfix::set_current_value("allow_percent_hack", "no");

    # And master.cf
    my $master = postfix::get_master_config();
    my ($smtp) = grep { $_->{'name'} eq 'smtp' && $_->{'enabled'} } @$master;
    $smtp || die "Failed to find SMTP postfix service!";
    if ( $smtp->{'command'} !~ /smtpd_sasl_auth_enable/
      || $smtp->{'command'} !~ /smtpd_tls_security_level/)
    {
      $smtp->{'command'} .= " -o smtpd_sasl_auth_enable=yes"
        if ($smtp->{'command'} !~ /smtpd_sasl_auth_enable/);
      $smtp->{'command'} .= " -o smtpd_tls_security_level=may"
        if ($smtp->{'command'} !~ /smtpd_tls_security_level/);
      postfix::modify_master($smtp);
    }

    # Add submission entry, if missing
    my ($submission)
      = grep { $_->{'name'} eq 'submission' && $_->{'enabled'} } @$master;
    if (!$submission) {
      $submission = {%$smtp};
      $submission->{'name'} = 'submission';
      postfix::create_master($submission);
    }

    # Add smtps entry, if missing
    my ($smtps) = grep { $_->{'name'} eq 'smtps' && $_->{'enabled'} } @$master;
    if (!$smtps) {
      $smtps = {%$smtp};
      $smtps->{'name'} = 'smtps';
      $smtps->{'command'} .= " -o smtpd_tls_wrappermode=yes";
      postfix::create_master($smtps);
    }

    delete($main::file_cache{$postfix::config{'postfix_config_file'}});
    postfix::reload_postfix();

    # Make sure other code knows the Postfix version
    $postfix::postfix_version = backquote_command(
      "$postfix::config{'postfix_config_command'} -h mail_version");
    $postfix::postfix_version =~ s/\r|\n//g;
    open_tempfile(my $VER, ">$postfix::module_config_directory/version");
    print_tempfile($VER, $postfix::postfix_version, "\n");
    close_tempfile($VER);

    # Force alias map rebuild if missing
    postfix::regenerate_aliases();

    foreign_require("init", "init-lib.pl");
    if (-e "/usr/sbin/alternatives") {
      system("/usr/sbin/alternatives --set mta /usr/sbin/sendmail.postfix");
    }
    if ($gconfig{'os_type'} eq 'freebsd') {

      # Fully disable sendmail in rc.conf
      print "Disabling Sendmail in rc.conf\n";
      my $lref = read_file_lines("/etc/rc.conf");
      foreach my $v (
        "sendmail_enable",          "sendmail_submit_enable",
        "sendmail_outbound_enable", "sendmail_msp_queue_enable"
        )
      {
        my $found;
        foreach my $l (@$lref) {
          if ($l =~ /^\Q$v\E\s*=\s*"(\S+)"/i) {
            if ($1 ne "NO") {
              $l = $v . '="NO"';
            }
            $found++;
          }
        }
        push(@$lref, $v . '="NO"') if (!$found);
      }
      flush_file_lines("/etc/rc.conf");

      # Set default mailer to Postfix, in /etc/mail/mailer.conf
      print "Setting default mailer to Postfix\n";
      $lref = read_file_lines("/etc/mail/mailer.conf");
      foreach my $v (
        ["sendmail",   "/usr/local/sbin/sendmail"],
        ["send-mail",  "/usr/local/sbin/sendmail"],
        ["mailq",      "/usr/local/bin/mailq"],
        ["newaliases", "/usr/local/bin/newaliases"],
        ["hoststat",   "/usr/local/sbin/sendmail"],
        ["purgestat",  "/usr/local/sbin/sendmail"]
        )
      {
        foreach my $l (@$lref) {
          if ($l =~ /^\Q$v->[0]\E\s+/) {
            $l = $v->[0] . "\t" . $v->[1];
          }
        }
      }
      flush_file_lines("/etc/mail/mailer.conf");
    }
    init::enable_at_boot("postfix");
    init::disable_at_boot("sendmail");
    init::disable_at_boot("exim4");
    if (foreign_check("sendmail")) {
      foreign_require("sendmail", "sendmail-lib.pl");
      if (sendmail::is_sendmail_running()) {
        sendmail::stop_sendmail();
      }
    }
    system("killall -9 sendmail >/dev/null 2>&1");
    system("newaliases");
    if (!postfix::is_postfix_running()) {
      my $err = postfix::start_postfix();
      print STDERR "Failed to start Postfix!\n" if ($err);
    }

    $self->done(1);    # OK!
  };
  if ($@) {
    $self->done(0);
  }
}

1;
