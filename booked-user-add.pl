=head1 NAME

booked-user-add.pl - create a new Booked Scheduler user

=head1 SYNOPSIS

    booked-user-add.pl [OPTION] ... LOGIN PASSWD FIRST_NAME LAST_NAME MAIL [LANG TIMEZONE PHONE ORG POSITION] ...

=head1 DESCRIPTION

This script creates a new Booked Scheduler user.

=head1 OPTIONS

=over 4

=item --url=URL

Access to URL.

=item -u USER, --user=USER

Use USER as administrator's login name.

=item -p PASSWORD, --password=PASSWORD

Set administrator's password to PASSWORD.

=item --csv=FILE

Read data from FILE.

=item -l FILE, --log=FILE

Write log to FILE.

=item --verbose

Print verbosely.

=item --help

Print this help.

=back

=head1 EXAMPLE

    perl booked-user-add.pl --url=http://www.gnr.com/booked \
        -u admin -p password \
        axl jungle Axl Rose a.rose@gnr.com \
        America/Chicago 0120-777-777 GnR Vocal \
        slash november Slash - slash@gnr.com \
        America/Chicago 0120-999-999 GnR Guitar

=head1 AUTHOR

Takeshi Nakamura <taqueci.n@gmail.com>

=head1 COPYRIGHT

Copyright (C) 2016 Takeshi Nakamura. All Rights Reserved.

=cut

use strict;
use warnings;

use Carp;
use Encode qw(encode decode);
use File::Basename;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev gnu_compat);
use HTTP::Request;
use JSON;
use LWP::UserAgent;
use Pod::Usage;
my $HAVE_CSV_XS = eval("use Text::CSV_XS; 1");

my $PROGRAM = basename $0;
my $ENCODING = ($^O eq 'MSWin32') ? 'cp932' : 'utf-8';

my $DEFAULT_URL = 'http://localhost';
my $DEFAULT_LANG = 'en_us';
my $DEFAULT_TIMEZONE = 'America/Chicago';

my $BOOKED_API_AUTH = 'Web/Services/Authentication/Authenticate';
my $BOOKED_API_USER = 'Web/Services/Users';
my $BOOKED_API_SIGNOUT = 'Web/Services/Authentication/SignOut';

_main(@ARGV) or exit 1;

exit 0;


my $p_message_prefix = "";
my $p_log_file;
my $p_is_verbose = 0;
my $p_encoding = 'utf-8';

sub p_decode {
	return decode($p_encoding, shift);
}

sub p_encode {
	return encode($p_encoding, shift);
}

sub p_message {
	my @msg = ($p_message_prefix, @_);

	print STDERR map {p_encode($_)} @msg, "\n";
	p_log(@msg);
}

sub p_warning {
	my @msg = ("*** WARNING ***: ", $p_message_prefix, @_);

	print STDERR map {p_encode($_)} @msg, "\n";
	p_log(@msg);
}

sub p_error {
	my @msg = ("*** ERROR ***: ", $p_message_prefix, @_);

	print STDERR map {p_encode($_)} @msg, "\n";
	p_log(@msg);
}

sub p_verbose {
	my @msg = @_;

	print STDERR map {p_encode($_)} @msg, "\n" if $p_is_verbose;
	p_log(@msg);
}

sub p_log {
	my @msg = @_;

	return unless defined $p_log_file;

	open my $fh, '>>', $p_log_file or die "$p_log_file: $!\n";
	print $fh map {p_encode($_)} @msg, "\n";
	close $fh;
}

sub p_set_encoding {
	$p_encoding = shift;
}

sub p_set_message_prefix {
	my $prefix = shift;

	defined $prefix or croak 'Invalid argument';

	$p_message_prefix = $prefix;
}

sub p_set_log {
	my $file = shift;

	defined $file or croak 'Invalid argument';

	$p_log_file = $file;
}

sub p_set_verbose {
	$p_is_verbose = (!defined($_[0]) || ($_[0] != 0));
}

sub p_exit {
	my ($val, @msg) = @_;

	print STDERR map {p_encode($_)} @msg, "\n";
	p_log(@msg);

	exit $val;
}

sub p_error_exit {
	my ($val, @msg) = @_;

	p_error(@msg);

	exit $val;
}

sub _main {
	local @ARGV = @_;

	p_set_message_prefix("$PROGRAM: ");

	my %opt = (url => $DEFAULT_URL, encoding => $ENCODING);
	GetOptions(\%opt, 'url=s', 'user|u=s', 'password|p=s',
			   'csv|c=s', 'encoding|e=s',
			   'log|l=s', 'verbose', 'help') or exit 1;

	p_set_encoding($opt{encoding});
	p_set_log($opt{log}) if defined $opt{log};
	p_set_verbose(1) if $opt{verbose};

	pod2usage(-exitval => 0, -verbose => 2, -noperldoc => 1) if $opt{help};

	$opt{csv} or @ARGV > 4 or p_error_exit(1, 'Invalid arguments');

	my $user = $opt{csv} ? _read_csv($opt{csv}) : _read_args(@ARGV) or return 0;

	# Remove trailing slash.
	$opt{url} =~ s/\/$//;

	p_verbose("Accessing to $opt{url}");
	my $s = _auth($opt{url}, $opt{user}, $opt{password}) or return 0;

	p_verbose("Adding users");
	_create_users($opt{url}, $s->{uid}, $s->{token}, $user) or return 0;
			 
	_sign_out($opt{url}, $s->{uid}, $s->{token});

	p_verbose("Completed!\n");

	return 1;
}

sub _read_csv {
	my $file = shift;
	my @data;
	my $fh;

	unless ($HAVE_CSV_XS) {
		p_error("Please install Perl module 'Text::CSV_XS'");

		return undef;
	}

	unless (open $fh, $file) {
		p_error("$file: $!");

		return undef;
	}

	my $csv = Text::CSV_XS->new({binary => 1});

	# Ignore index row.
	$csv->getline($fh);

	while (my $c = $csv->getline($fh)) {
		push @data, _user_data(map {p_decode($_)} @$c);
	}

	close $fh;

	return \@data;
}

sub _read_args {
	my @arg = map {p_decode($_)} @_;
	my @data;

	while (@arg > 0) {
		my ($login, $passwd, $fname, $lname, $mail, $lang, $tz,
			$phone, $org, $pos) = @arg;

		# Eat arguments.
		shift @arg for 1 .. 10;
		
		push @data, _user_data($login, $passwd, $fname, $lname, $mail,
							   $lang, $tz, $phone, $org, $pos);
	}

	return \@data;
}

sub _auth {
	my ($url, $user, $passwd) = @_;

	my $json = encode_json({username => $user // _read_stdin('User: '),
							password => $passwd // _read_stdin('Password: ')});

	my $r = _post("$url/$BOOKED_API_AUTH", $json) or return undef;

	unless ($r->is_success) {
		p_error(decode('utf-8', $r->status_line));

		return undef;
	}
	
	my $p = decode_json($r->content);

	unless ($p->{isAuthenticated}) {
		p_error($p->{message});

		return undef;
	}

	return {uid => $p->{userId}, token => $p->{sessionToken}};
}

sub _create_users {
	my ($url, $uid, $token, $user) = @_;
	my $nerr = 0;

	foreach my $u (@$user) {
		my $name = _user_name($u);
		
		p_verbose("Adding user $name");
		# Don't forget trailing slash!
		my $r = _post("$url/$BOOKED_API_USER/", _user_json($u), $uid, $token);

		unless ($r->is_success) {
			p_error("$name: ", decode('utf-8', $r->status_line));
			p_error("$name: ", $_) foreach _err_msg($r->content);

			$nerr++;
		}
	}

	return $nerr == 0;
}

sub _sign_out {
	my ($url, $uid, $token) = @_;

	my $json = encode_json({userId => $uid, sessionToken => $token});

	_post("$url/$BOOKED_API_SIGNOUT", $json, $uid, $token);

	return 1;
}

sub _post {
	my ($url, $json, $uid, $token) = @_;

	p_log(decode('utf-8', $json));

	my $req = HTTP::Request->new(POST => $url);

	$req->content_type('application/json');
	$req->content($json);

	$req->header('X-Booked-SessionToken' => $token, 'X-Booked-UserId' => $uid);

	my $agent = LWP::UserAgent->new();

	return $agent->request($req);
}

sub _user_data {
	return [map {$_ ? $_ : undef} @_];
}

sub _user_name {
	return shift->[0];
}

sub _user_json {
	my $user = shift;
	my %data;

	my @key = ('userName', 'password', 'firstName', 'lastName', 'emailAddress',
			   'language', 'timezone', 'phone', 'organization', 'position');
	
	$data{$key[$_]} = $user->[$_] for 0 .. $#key;

	$data{language} //= $DEFAULT_LANG;
	$data{timezone} //= $DEFAULT_TIMEZONE;
	
	return encode_json(\%data);
}

sub _err_msg {
	my $content = shift;

	my $c = decode('utf-8', $content);

	# Remove BOM.
	$c =~ s/\x{feff}//;

	return @{decode_json($c)->{errors}};
}

sub _read_stdin {
	print shift;

	my $input = <STDIN>;
	chomp $input;

	return $input;
}
