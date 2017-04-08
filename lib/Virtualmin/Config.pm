package Virtualmin::Config;
use strict;
use warnings;
no warnings qw(once); # We've got some globals that effect Webmin behavior
use 5.010_001; # Version shipped with CentOS 6. Nothing older.
use Getopt::Long qw( GetOptionsFromArray );
use Pod::Usage;
use Term::ANSIColor qw(:constants);
use Term::Spinner::Color;

# Guesstimate our terminal size.
my ($lines, $cols) = `stty size`=~/(\d+)\s+(\d+)/?($1,$2):(25,80);
unless ($cols <= 80) { $cols = 80 };

# globals
our (%gconfig, %uconfig, %miniserv, %uminiserv);
our ($root_directory, $config_directory);

$|=1; # No line buffering.

# XXX This should really just be "use Webmin::Core"
# Setup Webmin environment
my $no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
$ENV{'MINISERV_CONFIG'} = $ENV{'WEBMIN_CONFIG'}."/miniserv.conf";
our $trust_unknown_referers = 1;
open(my $CONF, "<", "$ENV{'WEBMIN_CONFIG'}/miniserv.conf") ||
die RED, "Failed to open miniserv.conf", RESET;
my $root;
while(<$CONF>) {
	if (/^root=(.*)/) {
		$root = $1;
	}
}
close($CONF);
$root ||= "/usr/libexec/webmin";
chdir($root);
# Make program appear by name, instead of 'perl' in ps/top
$0 = "virtualminconfig";
push(@INC, $root);
eval "use WebminCore";
init_config();

our $error_must_die = 1;
our $file_cache;

sub new {
  my ($class, %args) = @_;
  my $self = {};

	return bless $self, $class;
}

# Set the Webmin theme and turn on full logging
eval { # try
	print "Setting Webmin theme\n";
	foreign_require("webmin", "webmin-lib.pl");
	$gconfig{'theme'} = "authentic-theme";
	$gconfig{'logfiles'} = 1;
	write_file("$config_directory/config", \%gconfig);
	get_miniserv_config(\%miniserv);
	$miniserv{'preroot'} = "authentic-theme";
	$miniserv{'ssl'} = 1;
	$miniserv{'ssl_cipher_list'} = $webmin::strong_ssl_ciphers;
	put_miniserv_config(\%miniserv);
	restart_miniserv();
	1;
}
or do { # catch
	print "Error occurred while setting Webmin theme: $@\n";
};

# Set the Usermin theme and allow domain-based logins
eval {
	print "Setting Usermin theme\n";
	foreign_require("usermin", "usermin-lib.pl");
	usermin::get_usermin_config(\%uconfig);
	$uconfig{'theme'} = "authentic-theme";
	$uconfig{'gotomodule'} = 'mailbox';
	usermin::put_usermin_config(\%uconfig);
	usermin::get_usermin_miniserv_config(\%uminiserv);
	$uminiserv{'preroot'} = "authentic-theme";
	$uminiserv{'ssl'} = "1";
	$uminiserv{'ssl_cipher_list'} = $webmin::strong_ssl_ciphers;
	$uminiserv{'domainuser'} = 1;
	$uminiserv{'domainstrip'} = 1;
	usermin::put_usermin_miniserv_config(\%uminiserv);
	usermin::restart_usermin_miniserv();

	# Start Usermin at boot
	foreign_require("init", "init-lib.pl");
	init::enable_at_boot("usermin", "Start the Usermin webserver",
			"$usermin::config{'usermin_dir'}/start",
			"$usermin::config{'usermin_dir'}/stop");
	1;
}
or do {
	print "Error occurred while setting Usermin theme: $@\n";
};

# Configure virtual maps in Postfix
eval {
	print "Configuring Postfix\n";
	foreign_require("postfix", "postfix-lib.pl");
	# Debian doesn't get a default main.cf unless apt-get is run
	# interactively.
	if (!-e "/etc/postfix/main.cf" &&
			-e "/usr/share/postfix/main.cf.debian") {
		system("cp /usr/share/postfix/main.cf.debian /etc/postfix/main.cf");
	}
	# FreeBSD doesn't get a default main.cf, or anything else
	if (!-e "/usr/local/etc/postfix/main.cf" &&
			-e "/usr/local/etc/postfix/dist/main.cf") {
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
		postfix::set_current_value("sender_bcc_maps",
				"$maptype:$postetc/bcc");
	}
	postfix::ensure_map("sender_bcc_maps");
	postfix::regenerate_bcc_table() if (defined(postfix::regenerate_bcc_table()));

	# Setup sender dependent map
	if ($postfix::postfix_version >= 2.7) {
		if (!postfix::get_real_value(
					"sender_dependent_default_transport_maps")) {
			postfix::set_current_value(
					"sender_dependent_default_transport_maps",
					"$maptype:$postetc/dependent");
		}
		postfix::ensure_map("sender_dependent_default_transport_maps");
		postfix::regenerate_any_table(
				"sender_dependent_default_transport_maps");
	}

	my $wrapper = "/usr/bin/procmail-wrapper";
	postfix::set_current_value("mailbox_command",
			"$wrapper -o -a \$DOMAIN -d \$LOGNAME", 1);
	postfix::set_current_value("home_mailbox", "Maildir/", 1);
	postfix::set_current_value("inet_interfaces", "all", 1);
	# Add smtp auth stuff to main.cf
	postfix::set_current_value("smtpd_sasl_auth_enable", "yes", 1);
	postfix::set_current_value("smtpd_sasl_security_options", "noanonymous", 1);
	postfix::set_current_value("broken_sasl_auth_clients", "yes", 1);
	postfix::set_current_value("smtpd_recipient_restrictions", "permit_mynetworks permit_sasl_authenticated reject_unauth_destination", 1);
	my $mydest = postfix::get_current_value("mydestination");
	my $myhost = get_system_hostname();
	if ($mydest !~ /\Q$myhost\E/) {
		postfix::set_current_value("mydestination",
				$mydest.", ".$myhost, 1);
	}

	# Turn off limit on mailbox size
	postfix::set_current_value("mailbox_size_limit", "0");

	# Turn off % hack, which breaks user%domain mailboxes
	postfix::set_current_value("allow_percent_hack", "no");

	# And master.cf
	my $master = postfix::get_master_config();
	my ($smtp) = grep { $_->{'name'} eq 'smtp' && $_->{'enabled'} } @$master;
	$smtp || die "Failed to find SMTP postfix service!";
	if ($smtp->{'command'} !~ /smtpd_sasl_auth_enable/) {
		$smtp->{'command'} .= " -o smtpd_sasl_auth_enable=yes";
		postfix::modify_master($smtp);
	}

	# Add submission entry, if missing
	my ($submission) = grep { $_->{'name'} eq 'submission' && $_->{'enabled'} } @$master;
	if (!$submission) {
		$submission = { %$smtp };
		$submission->{'name'} = 'submission';
		postfix::create_master($submission);
	}

	delete($main::file_cache{$postfix::config{'postfix_config_file'}});
	postfix::reload_postfix();

	# Make sure other code knows the Postfix version
	$postfix::postfix_version =
		backquote_command("$postfix::config{'postfix_config_command'} -h mail_version");
	$postfix::postfix_version =~ s/\r|\n//g;
	open_tempfile(my $VER, ">$postfix::module_config_directory/version");
	print_tempfile($VER, $postfix::postfix_version,"\n");
	close_tempfile($VER);

	# Force alias map rebuild if missing
	postfix::regenerate_aliases();
	1;
}
or do {
	print "Error occurred while configuring Postfix: $@\n";
};

# Make sure Postfix is started at boot, and sendmail isn't
eval {
	print "Enabling Postfix and disabling Sendmail\n";
	foreign_require("init", "init-lib.pl");
	if ( -e "/usr/sbin/alternatives" ) {
		system("/usr/sbin/alternatives --set mta /usr/sbin/sendmail.postfix");
	}
	if ($gconfig{'os_type'} eq 'freebsd') {
	# Fully disable sendmail in rc.conf
		print "Disabling Sendmail in rc.conf\n";
		my $lref = read_file_lines("/etc/rc.conf");
		foreach my $v ("sendmail_enable",
				"sendmail_submit_enable",
				"sendmail_outbound_enable",
				"sendmail_msp_queue_enable") {
			my $found;
			foreach my $l (@$lref) {
				if ($l =~ /^\Q$v\E\s*=\s*"(\S+)"/i) {
					if ($1 ne "NO") {
						$l = $v.'="NO"';
					}
					$found++;
				}
			}
			push(@$lref, $v.'="NO"') if (!$found);
		}
		flush_file_lines("/etc/rc.conf");

		# Set default mailer to Postfix, in /etc/mail/mailer.conf
		print "Setting default mailer to Postfix\n";
		$lref = &read_file_lines("/etc/mail/mailer.conf");
		foreach my $v ([ "sendmail", "/usr/local/sbin/sendmail" ],
				[ "send-mail", "/usr/local/sbin/sendmail" ],
				[ "mailq", "/usr/local/bin/mailq" ],
				[ "newaliases", "/usr/local/bin/newaliases" ],
				[ "hoststat", "/usr/local/sbin/sendmail" ],
				[ "purgestat", "/usr/local/sbin/sendmail" ]) {
			foreach my $l (@$lref) {
				if ($l =~ /^\Q$v->[0]\E\s+/) {
					$l = $v->[0]."\t".$v->[1];
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

	# Make sure freshclam is not disabled
	my $fcconf = "/etc/sysconfig/freshclam";
	if (-r $fcconf) {
		my $lref = &read_file_lines($fcconf);
		foreach my $l (@$lref) {
			if ($l =~ /^FRESHCLAM_DELAY=disabled/) {
				$l = "#$l";
			}
		}
		flush_file_lines($fcconf);
	}
	1;
}
or do {
	print "Error occurred while enabling Postfix and disabling Sendmail: $@\n";
};

eval {
	print "Configuring Dovecot for POP3 and IMAP\n";
	foreign_require("dovecot", "dovecot-lib.pl");

	# Work out dirs for control and index files
	foreign_require("mount", "mount-lib.pl");
	my $indexes = "";
	my ($homedir) = mount::filesystem_for_dir("/home");
	my ($vardir) = mount::filesystem_for_dir("/var");
	if ($homedir ne $vardir) {
		if (!-d "/var/lib") {
			make_dir("/var/lib", 0755);
		}
		if (!-d "/var/lib/dovecot-virtualmin") {
			make_dir("/var/lib/dovecot-virtualmin", 0755);
		}
		make_dir("/var/lib/dovecot-virtualmin/index", 0777);
		make_dir("/var/lib/dovecot-virtualmin/control", 0777);
		$indexes = ":INDEX=/var/lib/dovecot-virtualmin/index/%u".
			":CONTROL=/var/lib/dovecot-virtualmin/control/%u";
	}

	my $conf = dovecot::get_config();
	if (dovecot::get_dovecot_version() >= 2) {
		dovecot::save_directive($conf, "protocols",
				"imap pop3");
	}
	else {
		dovecot::save_directive($conf, "protocols",
				"imap imaps pop3 pop3s");
	}
	if (dovecot::find("mail_location", $conf, 2)) {
		dovecot::save_directive($conf, "mail_location",
				"maildir:~/Maildir".$indexes);
	}
	else {
		dovecot::save_directive($conf, "default_mail_env",
				"maildir:~/Maildir".$indexes);
	}
	if (dovecot::find("pop3_uidl_format", $conf, 2)) {
		dovecot::save_directive($conf, "pop3_uidl_format",
				"%08Xu%08Xv");
	}
	elsif (dovecot::find("pop3_uidl_format", $conf, 2, "pop3")) {
		dovecot::save_directive($conf, "pop3_uidl_format",
				"%08Xu%08Xv", "pop3");
	}
	dovecot::save_directive($conf, "disable_plaintext_auth", "no");
	my $am = dovecot::find_value("auth_mechanisms", $conf, 2);
	if ($am && $am !~ /login/) {
		$am .= " login";
		&dovecot::save_directive($conf, "auth_mechanisms", $am);
	}
	flush_file_lines();
	print "Enabling Dovecot POP3 and IMAP servers\n";
	init::enable_at_boot("dovecot");
	if (!dovecot::is_dovecot_running()) {
		my $err = dovecot::start_dovecot();
		print STDERR "Failed to start Dovecot POP3/IMAP server!\n" if ($err);
	}
	1;
}
or do {
	print "Error occurred while configuring or enabling Dovecot: $@\n";
};

# ProFTPd
# Enable SFTP
#eval {
#	print "Enabling SFTP on port 2222 in ProFTPd\n";
#	my $fh;
#	# This is crazy. Need to use Webmin to lookup location of proftpd.conf or conf.d,
#	# but, it's not up to date or accurate for several systems, so need to fix.
#	if ( -d '/etc/proftpd/conf.d' ) { open ($fh, '>', '/etc/proftpd/conf.d/sftpd.conf'); }
#	elsif ( -f '/etc/proftd/proftpd.conf' ) { open ($fh, '>>', '/etc/proftpd/proftpd.conf'); }
#	elsif ( -f '/etc/proftpd.conf' ) { open(my $fh, '>>', '/etc/proftpd.conf'); }
#	elsif ( -f '/usr/local/etc/proftpd.conf' ) { open ($fh, '>>', '/usr/local/etc/proftpd.conf'); }
#	else { die "Could not find a proftpd configuration to edit.\n"; }
#	print $fh "\nLoadModule mod_sftp.c\n";
#	print $fh "<IfModule mod_sftp.c>\n\n";
#	print $fh "    SFTPEngine on\n";
#	print $fh "    Port 2222\n";
#	print $fh "    SFTPLog /var/log/proftpd/sftp.log\n\n";
#	print $fh "    SFTPHostKey /etc/ssh/ssh_host_rsa_key\n";
#	print $fh "    SFTPHostKey /etc/ssh/ssh_host_dsa_key\n\n";
#	print $fh "    SFTPAuthorizedUserKeys file:~/.sftp/authorized_keys\n\n";
#	print $fh "    SFTPCompression delayed\n\n";
#	print $fh "</IfModule>\n";
#	close $fh;
#	1;
#}
#or do {
#	print "Error occurred while enabling SFTP in ProFTPd: $@\n";
#};

eval {
	print "Enabling ProFTPd\n";
	init::enable_at_boot("proftpd");
	init::restart_action("proftpd");
	if ($gconfig{'os_type'} eq 'freebsd') {
	# This directory is missing on FreeBSD
		make_dir("/var/run/proftpd", 0755);

		# UseIPv6 doesn't work on FreeBSD
		foreign_require("proftpd", "proftpd-lib.pl");
		my $conf = &proftpd::get_config();
		proftpd::save_directive("UseIPv6", [ ], $conf, $conf);
		flush_file_lines();
	}
	1;
}
or do {
	print "Error occurred while enabling ProFTPd: $@\n";
};

# SASL SMTP authentication
eval {
	print "Enabling SMTP Authentication\n";
	init::enable_at_boot("saslauthd");
	my ($saslinit, $cf, $libdir);
	if ($gconfig{'os_type'} eq "debian-linux" or $gconfig{'os_type'} eq "ubuntu-linux") {
		my $fn="/etc/default/saslauthd";
		my $sasldefault = &read_file_lines($fn) or die "Failed to open $fn!";
		my $idx = &indexof("# START=yes", @$sasldefault);
		if ($idx < 0) {
			$idx = &indexof("START=no", @$sasldefault);
		}
		if ($idx >= 0) {
			$sasldefault->[$idx]="START=yes";
		}
		push(@$sasldefault, "PARAMS=\"-m /var/spool/postfix/var/run/saslauthd -r\"");
		flush_file_lines($fn);
		$cf="/etc/postfix/sasl/smtpd.conf";
		system("mkdir -p -m 755 /var/spool/postfix/var/run/saslauthd");
		system("adduser postfix sasl");
		$saslinit = "/etc/init.d/saslauthd";
	}
	elsif ($gconfig{'os_type'} eq 'solaris') {
		# Use CSW saslauthd
		my $lref = &read_file_lines("/opt/csw/etc/saslauthd.init");
		foreach my $l (@$lref) {
			if ($l =~ /^\#+\s*MECHANISM/) {
				$l = "MECHANISM=pam";
			}
		}
		flush_file_lines("/opt/csw/etc/saslauthd.init");
		$cf = "/opt/csw/lib/sasl2/smtpd.conf";
		$saslinit = "/etc/init.d/cswsaslauthd";
	}
	else {
		# I'm not liking all of this jiggery pokery...need a better way to
		# detect which lib directory to work in.XXX
		if ( $gconfig{'os_type'} eq 'freebsd' ) { $libdir = "/usr/local/lib"; }
		else {
			if ( -e "/usr/lib64" && -e "/usr/lib64/perl" ) { $libdir = "/usr/lib64"; }
			else { $libdir = "/usr/lib"; }
		}
		if ( -e "$libdir/sasl2" ) { $cf="$libdir/sasl2/smtpd.conf"; }
		elsif ( -e "$libdir/sasl" ) { $cf="$libdir/sasl/smtpd.conf"; }
		else { print "No sasl library directory found.  SASL authentication probably won't work"; }
		if ( $gconfig{'os_type'} eq 'freebsd' ) { $saslinit = "/usr/local/etc/rc.d/saslauthd"; }
		else { $saslinit = "/etc/init.d/saslauthd"; }
	}
	if ($cf) {
		if (! -e $cf ) {
			system("touch $cf");
		}
		my $smtpdconf= read_file_lines($cf) or die "Failed to open $cf!";
		my $idx = indexof("", @$smtpdconf);
		if ($idx < 0) {
			push(@$smtpdconf, "pwcheck_method: saslauthd");
			push(@$smtpdconf, "mech_list: plain login");
			flush_file_lines($cf);
		}
		#$cmd = "$saslinit start";
		#proc::safe_process_exec($cmd, 0, 0, *STDOUT, undef, 1);
		init::start_action('saslauthd');
	}
	1;
}
or do {
	print "Error occurred while enabling SMTP authentication: $@\n";
};

# Tell Virtualmin to use Postfix, and enable all features
eval {
	print "Configuring Virtualmin\n";
	my %vconfig = &foreign_config("virtual-server");
	$vconfig{'mail_system'} = 0;
	$vconfig{'aliascopy'} = 1;
	$vconfig{'home_base'} = "/home";
	$vconfig{'spam'} = 1;
	$vconfig{'virus'} = 1;
	$vconfig{'ssl'} = 2;
	$vconfig{'ftp'} = 2;
	$vconfig{'postgresql'} = 1;
	$vconfig{'logrotate'} = 3;
	$vconfig{'default_procmail'} = 1;
	$vconfig{'bind_spfall'} = 0;
	$vconfig{'bind_spf'} = "yes";
	$vconfig{'spam_delivery'} = "\$HOME/Maildir/.spam/";
	$vconfig{'bccs'} = 1;
	if (!defined($vconfig{'plugins'})) {
		$vconfig{'plugins'} = 'virtualmin-dav virtualmin-awstats virtualmin-mailman virtualmin-htpasswd';
	}
	if (-e "/etc/debian_version" || -e "/etc/lsb-release") {
		$vconfig{'proftpd_config'} = 'ServerName ${DOM}	<Anonymous ${HOME}/ftp>	User ftp	Group nogroup	UserAlias anonymous ftp	<Limit WRITE>	DenyAll	</Limit>	RequireValidShell off	</Anonymous>';
	}

	# Make the Virtualmin web directories a bit more secure
	# FreeBSD has a low secondary groups limit..skip this bit.
	# XXX ACLs can reportedly deal with this...needs research.
	unless ( $gconfig{'os_type'} eq 'freebsd' ) {
		if (defined(getpwnam("www-data"))) {
			$vconfig{'web_user'} = "www-data";
		}
		else {
			$vconfig{'web_user'} = "apache";
		}
		$vconfig{'html_perms'} = "0750";
	}
	$vconfig{'php_suexec'} = 2;
	save_module_config(\%vconfig, "virtual-server");

	# Configure the Read User Mail module to look for sub-folders
	# under ~/Maildir
	my %mconfig = foreign_config("mailboxes");
	$mconfig{'mail_usermin'} = "Maildir";
	$mconfig{'from_virtualmin'} = 1;
	save_module_config(\%mconfig, "mailboxes");

	# Setup the Usermin read mail module
	my $cfile = "$usermin::config{'usermin_dir'}/mailbox/config";
	my %mailconfig;
	read_file($cfile, \%mailconfig);
	my ($map) = postfix::get_maps_files(postfix::get_real_value(
				$postfix::virtual_maps));
	$map ||= "/etc/postfix/virtual";
	$mailconfig{'from_map'} = $map;
	$mailconfig{'from_format'} = 1;
	$mailconfig{'mail_system'} = 4;
	$mailconfig{'pop3_server'} = 'localhost';
	$mailconfig{'mail_qmail'} = undef;
	$mailconfig{'mail_dir_qmail'} = 'Maildir';
	$mailconfig{'server_attach'} = 0;
	$mailconfig{'send_mode'} = 'localhost';
	$mailconfig{'nologout'} = 1;
	$mailconfig{'noindex_hostname'} = 1;
	write_file($cfile, \%mailconfig);

	# Set the mail folders subdir to Maildir
	my $ucfile = "$usermin::config{'usermin_dir'}/mailbox/uconfig";
	my %umailconfig;
	read_file($ucfile, \%umailconfig);
	$umailconfig{'mailbox_dir'} = 'Maildir';
	write_file($ucfile, \%umailconfig);

	# Set the default Usermin ACL to only allow access to email modules
	usermin::save_usermin_acl("user",
			[ "mailbox", "changepass", "spam", "filter" ]);

	# Lock down the Usermin file manager and browser to users' homes
	$cfile = "$usermin::config{'usermin_dir'}/file/config";
	my %fileconfig;
	read_file($cfile, \%fileconfig);
	$fileconfig{'home_only'} = 1;
	write_file($cfile, \%fileconfig);
	my $afile = "$usermin::config{'usermin_dir'}/user.acl";
	my %uacl;
	read_file($afile, \%uacl);
	$uacl{'root'} = '';
	write_file($afile, \%uacl);

	# Configure the Usermin Change Password module to use Virtualmin's
	# change-password.pl script
	$cfile = "$usermin::config{'usermin_dir'}/changepass/config";
	my %cpconfig;
	read_file($cfile, \%cpconfig);
	$cpconfig{'passwd_cmd'} =
		$config_directory eq "/etc/webmin" ?
		"$root_directory/virtual-server/change-password.pl" :
		"virtualmin change-password";
	$cpconfig{'cmd_mode'} = 1;
	write_file($cfile, \%cpconfig);

	# Also do the same thing for expired password changes
	$cfile = "$usermin::config{'usermin_dir'}/config";
	my %umconfig;
	read_file($cfile, \%umconfig);
	$umconfig{'passwd_cmd'} =
		"$root_directory/virtual-server/change-password.pl";
	write_file($cfile, \%umconfig);

	# Configure the Usermin Filter module to use the right path for
	# Webmin config files. The defaults are incorrect on FreeBSD, where
	# we install under /usr/local/etc/webmin
	$cfile = "$usermin::config{'usermin_dir'}/filter/config";
	my %ficonfig;
	read_file($cfile, \%ficonfig);
	$ficonfig{'virtualmin_config'} =
		"$config_directory/virtual-server";
	$ficonfig{'virtualmin_spam'} =
		"$config_directory/virtual-server/lookup-domain.pl";
	write_file($cfile, \%ficonfig);

	# Same for Usermin custom commands
	$cfile = "$usermin::config{'usermin_dir'}/commands/config";
	my %ccconfig;
	read_file($cfile, \%ccconfig);
	$ccconfig{'webmin_config'} = "$config_directory/custom";
	write_file($cfile, \%ccconfig);

	# Same for Usermin .htaccess files
	$cfile = "$usermin::config{'usermin_dir'}/htaccess/config";
	my %htconfig;
	read_file($cfile, \%htconfig);
	$htconfig{'webmin_apache'} = "$config_directory/apache";
	write_file($cfile, \%htconfig);

	# Setup the Apache, BIND and DB modules to use tables for lists
	foreach my $t ([ 'apache', 'show_list' ],
			[ 'bind8', 'show_list' ],
			[ 'mysql', 'style' ],
			[ 'postgresql', 'style' ]) {
		my %mconfig = &foreign_config($t->[0]);
		$mconfig{$t->[1]} = 1;
		save_module_config(\%mconfig, $t->[0]);
	}

	# Make the default home directory permissions 750
	my %uconfig = &foreign_config("useradmin");
	if ( $gconfig{'os_type'} eq 'freebsd' ) { $uconfig{'homedir_perms'} = "0751"; }
	else { $uconfig{'homedir_perms'} = "0750"; }
	save_module_config(\%uconfig, "useradmin");
	1;
}
or do {
	print "Error occurred while configuring Virtualmin: $@\n";
};


# Create a global Procmail rule to deliver to ~/Maildir/
eval {
	print "Configuring Procmail\n";
	foreign_require("procmail", "procmail-lib.pl");
	my @recipes = procmail::get_procmailrc();
	my ($defrec, $orgrec);
	foreach my $r (@recipes) {
		if ($r->{'name'} eq "DEFAULT") {
			$defrec = $r;
		}
		elsif ($r->{'name'} eq "ORGMAIL") {
			$orgrec = $r;
		}
	}
	if ($defrec) {
		# Fix up this DEFAULT entry
		$defrec->{'value'} = '$HOME/Maildir/';
		procmail::modify_recipe($defrec);
	}
	else {
		# Prepend a DEFAULT entry
		$defrec = { 'name' => 'DEFAULT',
			'value' => '$HOME/Maildir/' };
		if (@recipes) {
			procmail::create_recipe_before($defrec, $recipes[0]);
		}
		else {
			procmail::create_recipe($defrec);
		}
	}
	if ($orgrec) {
		# Fix up this ORGMAIL entry
		$orgrec->{'value'} = '$HOME/Maildir/';
		procmail::modify_recipe($orgrec);
	}
	else {
		# Prepend a ORGMAIL entry
		$orgrec = { 'name' => 'ORGMAIL',
			'value' => '$HOME/Maildir/' };
		if (@recipes) {
			procmail::create_recipe_before($orgrec, $recipes[0]);
		}
		else {
			procmail::create_recipe($orgrec);
		}
	}
	1;
}
or do {
	print "Error occurred while configuring Procmail: $@\n";
};

# Disable Razor in spamassassin, as it causes SIGPIPE errors
my $razorfile = "/usr/local/etc/mail/spamassassin/v310.pre";
if ($gconfig{'os_type'} eq 'freebsd' && -r $razorfile) {
	eval {
		print "Disabling Razor in SpamAssassin\n";
		my $lref = &read_file_lines($razorfile);
		foreach my $l (@$lref) {
			if ($l =~ /^loadplugin\s+Mail::SpamAssassin::Plugin::Razor2/) {
				$l = "#$l";
			}
		}
		flush_file_lines($razorfile);
		1;
	}
	or do {
		print "Error occurred while disabling Razor: $@\n";
	};
}

# Fix bad paths in Webalizer configuration
eval {
	print "Configuring Webalizer\n";
	&foreign_require("webalizer", "webalizer-lib.pl");
	my $conf = &webalizer::get_config();
	webalizer::save_directive($conf, "IncrementalName", "webalizer.current");
	webalizer::save_directive($conf, "HistoryName", "webalizer.hist");
	webalizer::save_directive($conf, "DNSCache", "dns_cache.db");
	flush_file_lines($webalizer::config{'webalizer_conf'});
	1;
}
or do {
	print "Error occurred while configuring Webalizer: $@\n";
};

# Add /bin/false to the shells file, for use by Virtualmin
eval {
	print "Updating /etc/shells\n";
	my $lref = &read_file_lines("/etc/shells");
	my $idx = &indexof("/bin/false", @$lref);
	if ($idx < 0) {
		push(@$lref, "/bin/false");
		push(@$lref, "/usr/bin/scponly");
		flush_file_lines("/etc/shells");
	}
	1;
}
or do {
	print "Error occurred while updating /etc/shells: $@\n";
};

# Enable MySQL and PostgreSQL at boot time, and perform any initial
# setup
eval {
	print "Enabling MySQL and PostgreSQL\n";
	if ($gconfig{'os_type'} eq "freebsd" ||
			init::action_status("mysql")) {
		init::enable_at_boot("mysql");
	} else {
		init::enable_at_boot("mysqld");
	}
	init::enable_at_boot("postgresql");
	foreign_require("mysql", "mysql-lib.pl");
	if (mysql::is_mysql_running()) {
		mysql::stop_mysql();
	}
	my $conf = mysql::get_mysql_config();
	my ($sect) = grep { $_->{'name'} eq 'mysqld' } @$conf;
	if ($sect) {
		mysql::save_directive($conf, $sect,
				"innodb_file_per_table", [ 1 ]);
		flush_file_lines($sect->{'file'});
	}
	my $err = mysql::start_mysql();
	print STDERR "Failed to start MySQL!\n" if ($err);
	if (foreign_check("postgresql")) {
		foreign_require("postgresql", "postgresql-lib.pl");
		if (!-r $postgresql::config{'hba_conf'}) {
			# Needs to be initialized
			my $err = postgresql::setup_postgresql();
			print STDERR "Failed to setup PostgreSQL!\n" if ($err);
		}
		if (postgresql::is_postgresql_running() == 0) {
			my $err = postgresql::start_postgresql();
			print STDERR "Failed to start PostgreSQL!\n" if ($err);
		}
	}
	1;
}
or do {
	print "Error occurred while enabling MySQL and PostgreSQL: $@\n";
};

# Enable Apache at boot time, and start now
eval {
	print "Enabling Apache\n";
	foreign_require("apache", "apache-lib.pl");
	if (-e "/etc/init.d/httpd") { init::enable_at_boot("httpd"); }
	elsif (-e "/etc/init.d/apache2") { init::enable_at_boot("apache2"); }
	elsif (-e "/usr/local/etc/rc.d/apache22") { init::enable_at_boot("apache22"); }

	# Fix up some Debian stuff
	if ( $gconfig{'os_type'} eq "debian-linux") {
		print "Setting up Debian Apache configuration file\n";
		if (-e "/etc/init.d/apache") { init::disable_at_boot("apache"); }
		system("a2enmod cgi");
		system("a2enmod suexec");
		system("a2enmod actions");
		system("a2enmod fcgid");
		system("a2enmod ssl");
		system("a2enmod dav");
		system("a2enmod lbmethod_byrequests");
		if (!-e "/etc/apache2/conf.d/ssl.conf") {
			print "Enabling mod_ssl\n";
			system("a2enmod ssl");
			`echo Listen 80 > /etc/apache2/ports.conf`;
			`echo Listen 443 >> /etc/apache2/ports.conf`;
		}
		if (-e "/etc/init.d/apache") {
			print "Shutting down Apache 1.3, if running\n";
			my $cmd = "/etc/init.d/apache stop";
			foreign_require("proc", "proc-lib.pl");
			proc::safe_process_exec($cmd, 0, 0, *STDOUT, undef, 1);
		}
		my $fn="/etc/default/apache2";
		my $apache2default = read_file_lines($fn) or die "Failed to open $fn!";
		my $idx = indexof("NO_START=1");
		$apache2default->[$idx]="NO_START=0";
		flush_file_lines($fn);
	}

	# Handle missing fcgid dir
	if ( $gconfig{'os_type'} =~ /debian-linux|ubuntu-linux/) {
		if (!-e "/var/lib/apache2/fcgid") {
			mkdir "/var/lib/apache2/fcgid";
		}
	}

	# On Debian and Ubuntu, enable some modules which are disabled by default
	if ( $gconfig{'os_type'} =~ /debian-linux|ubuntu-linux/) {
		my $adir = "/etc/apache2/mods-available";
		my $edir = "/etc/apache2/mods-enabled";
		foreach my $mod ("actions", "suexec", "auth_digest", "dav_svn",
				"ssl", "dav", "dav_fs", "fcgid", "rewrite", "proxy",
				"proxy_balancer", "proxy_connect", "proxy_http",
				"authz_svn", "slotmem_shm", "cgi") {
			if (-r "$adir/$mod.load" && !-r "$edir/$mod.load") {
				symlink("$adir/$mod.load", "$edir/$mod.load");
			}
			if (-r "$adir/$mod.conf" && !-r "$edir/$mod.conf") {
				symlink("$adir/$mod.conf", "$edir/$mod.conf");
			}
		}
	}

	# On Debian 5.0+ and Ubuntu 10.04+ configure apache2-suexec-custom
	if ((( $gconfig{'real_os_type'} eq 'Debian Linux' ) &&
				( $gconfig{'real_os_version'} >= 5.0 )) ||
			(( $gconfig{'real_os_type'} eq 'Ubuntu Linux' ) &&
			 ( $gconfig{'real_os_version'} >= 10.04))) {
		my $fn = "/etc/apache2/suexec/www-data";
		my $apache2suexec = read_file_lines($fn) or die "Failed to open $fn!";
		$apache2suexec->[0] = "/home";
		flush_file_lines($fn);
	}

	# On Ubuntu 10, PHP is enabled in php5.conf in a way that makes it
	# impossible to turn off for CGI mode!
	foreach my $php5conf ("/etc/apache2/mods-available/php5.conf",
			"/etc/apache2/mods-enabled/php5_cgi.conf",
			"/etc/apache2/mods-available/php7.0.conf") {
		if ($gconfig{'os_type'} eq 'debian-linux' &&
				-r $php5conf) {
			my $lref = read_file_lines($php5conf);
			foreach my $l (@$lref) {
				if ($l =~ /^\s*SetHandler/i ||
						$l =~ /^\s*php_admin_value\s+engine\s+Off/i) {
					$l = "#".$l;
				}
			}
			flush_file_lines($php5conf);
		}
	}

	# FreeBSD enables almost nothing, by default
	if ( $gconfig{'os_type'} =~ /freebsd/) {
		my $fn = "/usr/local/etc/apache22/httpd.conf";
		my $apache22conf = &read_file_lines($fn) or die "Failed to open $fn!";
		foreach my $l (@$apache22conf) {
			$l =~ s/#(Include .*httpd-ssl.conf)/$1/;
			$l =~ s/#(Include .*httpd-vhosts.conf)/$1/;
			$l =~ s/#(Include .*httpd-dav.conf)/$1/;
		}
		flush_file_lines($fn);
		# Load mod_fcgid
		open(my $FCGID, ">/usr/local/etc/apache22/Includes/fcgid.conf");
		print $FCGID "LoadModule fcgid_module libexec/apache22/mod_fcgid.so\n";
		print $FCGID "<IfModule mod_fcgid.c>\n";
		print $FCGID "  AddHandler fcgid-script .fcgi\n";
		print $FCGID "</IfModule>\n";
		close($FCGID);
	}

	# Comment out config files that conflict
	foreach my $file ("/etc/httpd/conf.d/welcome.conf",
			"/etc/httpd/conf.d/awstats.conf") {
		next if (!-r $file);
		my $lref = &read_file_lines($file);
		foreach my $l (@$lref) {
			if ($l !~ /^\s*#/) {
				$l = "#".$l;
			}
		}
		flush_file_lines($file);
	}

	# Disable global UserDir option
	my $conf = apache::get_config();
	my ($userdir) = apache::find_directive_struct("UserDir", $conf);
	if ($userdir) {
		apache::save_directive("UserDir", [ ], $conf, $conf);
		flush_file_lines($userdir->{'file'});
	}

	# Force use of PCI-compliant SSL ciphers
	foreign_require("webmin", "webmin-lib.pl");
	apache::save_directive("SSLProtocol",
			[ "ALL -SSLv2 -SSLv3" ], $conf, $conf);
	if (!apache::find_directive("SSLCipherSuite", $conf)) {
		apache::save_directive("SSLCipherSuite",
				[ "HIGH:!SSLv2:!ADH:!aNULL:!eNULL:!NULL" ],
				$conf, $conf);
	}

	# Turn off server signatures, which aren't PCI compliant
	apache::save_directive("ServerTokens", [ "Minimal" ], $conf, $conf);
	apache::save_directive("ServerSignature", [ "Off" ], $conf, $conf);
	apache::save_directive("TraceEnable", [ "Off" ], $conf, $conf);
	flush_file_lines();

	if (!apache::is_apache_running()) {
		my $err = apache::start_apache();
		print STDERR "Failed to start Apache!\n" if ($err);
	}

	# Force re-check of installed Apache modules
	unlink($apache::site_file);
	1;
}
or do {
	print "Error occurred while enabling Apache: $@\n";
};

# Enable BIND at boot time, start it now, and setup initial config file
eval {
	print "Configuring and enabling BIND\n";
	if (init::action_status("named")) {
		init::enable_at_boot("named");
	}
	elsif (init::action_status("bind9")) {
		init::enable_at_boot("bind9");
	}
	foreign_require("bind8", "bind8-lib.pl");
	my $conffile = bind8::make_chroot($bind8::config{'named_conf'});
	if (!-r $conffile) {
		$bind8::config{'named_conf'} =~ /^(\S+)\/([^\/]+)$/;
		my $conf_directory = $1;
		my $pid_file = $bind8::config{'pid_file'} || "/var/run/named.pid";
		my $pid_dir;

		# Make sure all directories used by BIND exist
		my $chroot = bind8::get_chroot();
		if ($chroot && !-d $chroot) {
			mkdir($chroot, 0755);
		}
		if (!-d bind8::make_chroot($conf_directory)) {
			mkdir(bind8::make_chroot($conf_directory), 0755);
		}
		if ($bind8::config{'master_dir'} &&
				!-d bind8::make_chroot($bind8::config{'master_dir'})) {
			mkdir(bind8::make_chroot($bind8::config{'master_dir'}), 0755);
		}
		if ($bind8::config{'slave_dir'} &&
				!-d bind8::make_chroot($bind8::config{'slave_dir'})) {
			mkdir(bind8::make_chroot($bind8::config{'slave_dir'}), 0777);
		}
		if ($pid_file =~ /^(.*)\//) {
			$pid_dir = $1;
		if (!-d bind8::make_chroot($pid_dir)) {
			mkdir(bind8::make_chroot($pid_dir), 0777);
		}
	}

	# Need to setup named.conf file, with root zone
	open(my $BOOT, ">", "$conffile");
	print $BOOT "options {\n";
	print $BOOT "    directory \"$conf_directory\";\n";
	print $BOOT "    pid-file \"$pid_file\";\n";
	print $BOOT "    allow-recursion { localnets; 127.0.0.1; };\n";
	print $BOOT "    };\n";
	print $BOOT "\n";
	print $BOOT "zone \".\" {\n";
	print $BOOT "    type hint;\n";
	print $BOOT "    file \"$conf_directory/db.cache\";\n";
	print $BOOT "    };\n";
	print $BOOT "\n";
	close($BOOT);
	system("cp $root_directory/bind8/db.cache ".
			bind8::make_chroot("$conf_directory/db.cache"));
	bind8::set_ownership(bind8::make_chroot("$conf_directory/db.cache"));
	bind8::set_ownership($conffile);
	}

	# Remove any options that would make BIND listen on localhost only
	undef(@bind8::get_config_cache);
	my $conf = bind8::get_config();
	my $options = &bind8::find("options", $conf);
	if ($options) {
		bind8::save_directive($options, "allow-query", [ ], 0);
		foreach my $dir ("listen-on", "listen-on-v6") {
			my @listen = bind8::find($dir, $options->{'members'});
			next if (!@listen);
			if ($listen[0]->{'values'}->[0] eq 'port' &&
					$listen[0]->{'values'}->[1] eq '53' &&
					$listen[0]->{'type'} &&
					($listen[0]->{'members'}->[0]->{'name'} eq
					 '127.0.0.1' ||
					 $listen[0]->{'members'}->[0]->{'name'} eq '::1')) {
				$listen[0]->{'members'}->[0]->{'name'} = 'any';
			}
			bind8::save_directive($options, $dir, \@listen, 1);
		}
		bind8::flush_file_lines();
	}

	if (!bind8::is_bind_running()) {
		bind8::start_bind();
	}
	else {
		bind8::restart_bind();
	}
	1;
}
or do {
	print "Error occurred while configuring and enabling BIND: $@\n";
};

# Make sure the system is configured to use itself as a resolver
eval {
	if (foreign_check("net")) {
		print "Configuring resolv.conf to use my DNS server\n";
		foreign_require("net", "net-lib.pl");
		my $dns = net::get_dns_config();
		if (indexof("127.0.0.1", @{$dns->{'nameserver'}}) < 0) {
			unshift(@{$dns->{'nameserver'}}, "127.0.0.1");
			net::save_dns_config($dns);
		}
		# Restart Postfix so that it picks up the new resolv.conf
		foreign_require("virtual-server");
		virtual_server::stop_service_mail();
		virtual_server::start_service_mail();
	}
	1;
}
or do {
	print "Error while configuring resolv.conf to use my DNS server: $@\n";
};

# Create 'mailman' list
eval {
	if (foreign_installed("virtualmin-mailman")) {
		foreign_require("virtualmin-mailman",
				"virtualmin-mailman-lib.pl");
		my @lists = virtualmin_mailman::list_lists();
		my ($mlist) = grep { $_->{'list'} eq 'mailman' } @lists;
		if (!$mlist) {
			# Need to create
			virtualmin_mailman::create_list("mailman", undef,
					"Default mailing list",
					undef,
					"root\@".&get_system_hostname(),
					time().$$);
		}
	}
	1;
}
or do {
	print "Error occurred while creating Mailman default list: $@\n";
};

# Enable scheduled monitoring
eval {
	print "Enabling status monitoring\n";
	foreign_require("status", "status-lib.pl");
	$status::config{'sched_mode'} = 1;
	$status::config{'sched_int'} ||= 5;
	$status::config{'sched_offset'} ||= 0;
	save_module_config(\%status::config, 'status');
	status::setup_cron_job();
	1;
}
or do {
	print "Error occurred while enabling status monitoring: $@\n";
};

# Hide the Upgrade Webmin page, as virtualmin package updates is better.
# Only do on Debian/Ubuntu, where everything is in .debs.
if ($gconfig{'os_type'} eq 'debian-linux') {
	eval {
		print "Hiding the Webmin and Usermin upgrade pages\n";
		my %wacl = ( 'disallow' => 'upgrade' );
		save_module_acl(\%wacl, 'root', 'webmin');
		my %uacl = ( 'upgrade' => 0 );
		save_module_acl(\%uacl, 'root', 'usermin');
		1;
	}
	or do {
		print "Error occurred hiding Webmin upgrade page: $@\n";
	};
}

# Find the filesystem containing /home , and enable quotas on it
eval {
	print STDERR "Enabling quotas on filesystem for /home\n";
	foreign_require("mount", "mount-lib.pl");
	mkdir("/home", 0755) if (!-d "/home");
	my ($dir, $dev, $type, $opts) = mount::filesystem_for_dir("/home");
	mount::parse_options($type, $opts);
	if (running_in_zone() || &running_in_vserver()) {
		print STDERR "Skipping quotas for Vserver or Zones systems\n";
		return;
	}
	elsif ($gconfig{'os_type'} =~ /-linux$/) {
		$mount::options{'usrquota'} = '';
		$mount::options{'grpquota'} = '';
	}
	elsif ($gconfig{'os_type'} =~ /freebsd|netbsd|openbsd|macos/) {
		# Skip if quotas are not enabled--requires a kernel rebuild
		my $quotav = `quota -v`;
		if ( ! $quotav =~ /none$/ ) {
			$mount::options{'rw'} = '';
			$mount::options{'userquota'} = '';
			$mount::options{'groupquota'} = '';
		}
		else {
			print "Skipping quotas: Required kernel support is not enabled.\n";
			return;
		}
	}
	elsif ($gconfig{'os_type'} =~ /solaris/) {
		$mount::options{'quota'} = '';
	}
	else {
		print STDERR "Don't know how to enable quotas on $gconfig{'real_os_type'} ($gconfig{'os_type'})\n";
	}
	$opts = mount::join_options($type);
	my @mounts = mount::list_mounts();
	my $idx;
	for($idx=0; $idx<@mounts; $idx++) {
		last if ($mounts[$idx]->[0] eq $dir);
	}
	mount::change_mount($idx, $mounts[$idx]->[0],
			$mounts[$idx]->[1],
			$mounts[$idx]->[2],
			$opts,
			$mounts[$idx]->[4],
			$mounts[$idx]->[5]);
	my $err = mount::remount_dir($dir, $dev, $type, $opts);
	if ($err) {
		print STDERR "The filesystem $dir could not be remounted with quotas enabled. You may need to reboot your system, and then enable quotas in the Disk Quotas module.\n";
	}
	else {
# Activate quotas
		foreign_require("quota", "quota-lib.pl");
		quota::quotaon($dir, 3);
	}
	1;
}
or do {
	print "Error occurred while enabling quotas on filesystem for /home: $@\n";
};

eval {
	my @tcpports = qw(ssh smtp submission domain ftp ftp-data pop3 pop3s imap imaps http https 2222 10000 20000);
	my @udpports = qw(domain);
	if ($gconfig{'os_type'} =~ /-linux$/) {
		print "Configuring firewall rules\n";
	}
	# And another thing (the Right Thing) for RHEL/CentOS/Fedora/Mandriva/Debian/Ubuntu
	foreign_require("firewall", "firewall-lib.pl");
	my @tables = &firewall::get_iptables_save();
	my @allrules = map { @{$_->{'rules'}} } @tables;
	if (@allrules) {
		my ($filter) = grep { $_->{'name'} eq 'filter' } @tables;
		if (!$filter) {
			$filter = { 'name' => 'filter',
				'rules' => [ ],
				'defaults' => { 'INPUT' => 'ACCEPT',
					'OUTPUT' => 'ACCEPT',
					'FORWARD' => 'ACCEPT' } };
		}
		foreach ( @tcpports ) {
			print "  Allowing traffic on TCP port: $_\n";
			my $newrule = { 'chain' => 'INPUT',
				'm' => [ [ '', 'tcp' ] ],
				'p' => [ [ '', 'tcp' ] ],
				'dport' => [ [ '', $_ ] ],
				'j' => [ [ '', 'ACCEPT' ] ],
			};
			splice(@{$filter->{'rules'}}, 0, 0, $newrule);
		}
		foreach ( @udpports ) {
			print "  Allowing traffic on UDP port: $_\n";
			my $newrule = { 'chain' => 'INPUT',
				'm' => [ [ '', 'udp' ] ],
				'p' => [ [ '', 'udp' ] ],
				'dport' => [ [ '', $_ ] ],
				'j' => [ [ '', 'ACCEPT' ] ],
			};
			splice(@{$filter->{'rules'}}, 0, 0, $newrule);
		}
		firewall::save_table($filter);
		firewall::apply_configuration();
	}
1;
}
or do {
	print "Error occurred while configuring firewall rules: $@\n";
};

# Remove global awstats cron job from ubuntu, as we setup one per domain
eval {
	print "Removing default AWstats cron job\n";
	foreign_require("cron");
	my @jobs = &cron::list_cron_jobs();
	my @dis = grep { $_->{'command'} =~ /\/usr\/share\/awstats\/tools\/(update|buildstatic).sh/ && $_->{'active'} } @jobs;
	if (@dis) {
		foreach my $job (@dis) {
			$job->{'active'} = 0;
			&cron::change_cron_job($job);
		}
	}
	else {
		print "None found, or already disabled\n";
	}
	1;
}
or do {
	print "Error removing AWstats cron job: $@\n";
};

# Attempt to sync clock
if (&has_command("ntpdate-debian")) {
	system("ntpdate-debian >/dev/null 2>&1 </dev/null &");
}

# Force re-detection of supported modules
eval {
	print "Re-checking supported Webmin modules\n";
	foreign_require("webmin", "webmin-lib.pl");
	webmin::build_installed_modules(1);
	1;
}
or do {
	print "Error occurred while detecting supported modules: $@\n";
};

# Turn on caching for downloads by Virtualmin
if (!$gconfig{'cache_size'}) {
	$gconfig{'cache_size'} = 50*1024*1024;
	$gconfig{'cache_mods'} = "virtual-server";
	write_file("$config_directory/config", \%gconfig);
}

1;
