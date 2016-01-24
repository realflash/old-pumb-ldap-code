#!/usr/bin/perl -wT

use CGI ':standard';
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use Net::LDAP;
use BandWebsite;
use CGI::Session;
use HTML::Template;
use Mail::Sender;

my $s = &getSettings;
my $debug = "0";
my $templates = $s->{'template_dir'};
my $cgi = CGI->new;
my $helper = BandWebsite->new({ basedn => $s->{'ldap_base_dn'} });
my $identifier = $cgi->param('uid');

my $header = HTML::Template->new(filename => "$templates/header.tmpl");
$header->param(LINKS => [ {HREF=>"forgotten.pl",TEXT=>"Reset my password"},
							 ]);
my $content = HTML::Template->new(filename => "$templates/resetpwd.tmpl");
my $footer = HTML::Template->new(filename => "$templates/footer.tmpl");

# Are we logged in as someone?
my $session = checkUserLoggedIn($cgi);
if($session)
{
	# Get some details for us
	$header->param(CN => $session->{'cn'});
	$header->param(LOGGED_IN => 1);
}
else
{
	$header->param(LOGGED_IN => 0);
}

# Find out if the provided identifier(s) are real or not
my $ldap = Net::LDAP->new($s->{'ldap_server'}.":".$s->{'ldap_port'}) or die "Couldn't connect to LDAP: $!";
my $mesg = $ldap->bind( $s->{'ldap_bind_dn'}, password => $s->{'ldap_bind_pw'} ) or die "Couldn't bind to LDAP: $!";

my @ids = split(/,/, $cgi->param('uid'));

foreach my $id (@ids)
{

my ($confirmed_DN, $confirmed_UID, $err) = verifyLoginUid($ldap,$id);

if($confirmed_DN)
{
	# Find the complete list of email addresses for the user
	my $member_details = getMemberDetails($ldap, $confirmed_UID);
	# Generate a new password for the user
	my $new_pwd = generate_random_string(8);
	$crypt_pwd = "{crypt}".crypt($new_pwd,"km");
	# Set the new password
	$result = $ldap->modify($confirmed_DN, replace => { 'userPassword' => $crypt_pwd, 'pwdReset' => 'TRUE' },);
	$result->code && die "Failed to modify entry: ", $result->error;
	# send the email
	my $email_content = HTML::Template->new(filename => "$templates/resetemail.tmpl");
	$email_content->param(SITE_NAME => $s->{'site_name'});
	$email_content->param(ADMIN_EMAIL => $s->{'admin_email'});
	$email_content->param(CN => $member_details->{'cn'});
	$email_content->param(UID => $confirmed_UID);
	$email_content->param(PWD => $new_pwd);
	$email_content->param(MAIL => HTMLTemplatiseArray($member_details->{'mail'}, "ADDRESS"));
	if($err eq "multipleuids")
	{
		$email_content->param(MULTIPLEMATCHES => 1);
	}
	if($debug)
	{
		logMsg("Password for $confirmed_UID now $new_pwd ($crypt_pwd)");
	}
	else
	{	
		# Open a Mail::Sender object to send email with
		my $sender = new Mail::Sender({ smtp => $s->{'smtp_host'}, from => $s->{'admin_email'}, on_errors => 'die'}) unless $debug;
		foreach my $mail (@{$member_details->{'mail'}})
		{
			logMsg("Password for $confirmed_UID now $new_pwd ($crypt_pwd) - emailing to $mail");
			eval
			{
				$sender->MailMsg({ subject => "New password for ".$s->{'site_name'}." website", to => $mail, msg => $email_content->output }) unless $debug;
			};
			if ($@)
			{
				die "Failed to send the message: $@\n";
			}
		}
		$sender->Close unless $debug;
	}
	setResult(1, undef);
}
else
{
	setResult(0, "unknown");
}

}
$mesg = $ldap->disconnect;

$header->param(IS_IE6 => 1) if(&isIE6);

print header;
print $header->output;
print $content->output;
print $footer->output;

sub HTMLTemplatiseArray
{
	my $array = $_[0];
	my $key = $_[1];
	my @result;	

	foreach my $item (@$array)
	{
		push(@result, { ADDRESS => $item });
	}
	return \@result;
}

sub setResult
{
	my $result = $_[0];
	my $reason = $_[1];
	my $error = $_[2];

	if($result)
	{	
		$header->param(PAGE_TITLE => $s->{'site_name'}." - Password reset suceeded");
		$content->param(SUCCESS => 1);
	}
	else
	{
		$header->param(PAGE_TITLE => $s->{'site_name'}." - Password reset failed");
		$content->param(SUCCESS => 0);
	}
}
