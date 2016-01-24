#!/usr/bin/perl -wT

use CGI ':standard';
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use Net::LDAP;
use BandWebsite;
use CGI::Session;
use HTML::Template;

use strict;

my $s = &getSettings;
my $debug = "0";
my $templates = $s->{'template_dir'};
my $cgi = CGI->new;
my $helper = BandWebsite->new({ basedn => $s->{'ldap_base_dn'} });
my $message_text = $cgi->param('msg'); $message_text = '' unless defined $message_text;
my $action = $cgi->param('action'); $action = '' unless defined $action;
my $pass = $cgi->param('pass'); $pass = '' unless defined $pass;
my $pass2 = $cgi->param('pass2'); $pass2 = '' unless defined $pass2;
my $home = $s->{'home'};
my $maxpasslength = $s->{'max_pass_length'};
my $minpasslength = $s->{'min_pass_length'};

my $header = HTML::Template->new(filename => "$templates/header.tmpl");
$header->param(PAGE_TITLE => $s->{'site_name'}." - Update password");
my $content = HTML::Template->new(filename => "$templates/updatepwd.tmpl");
my $footer = HTML::Template->new(filename => "$templates/footer.tmpl");

# Are we logged in as someone?
my $session = checkUserLoggedIn($cgi);

if($session)
{
	$header->param(CN => $session->{'cn'});
	$header->param(LOGGED_IN => 1);
	$content->param(LOGGED_IN => 1);
	if($action eq "update")
	{
		if(length($pass) > $maxpasslength) { $message_text = 'passtoolong'; }
		elsif(length($pass) < $minpasslength) { $message_text = 'passtooshort'; }
		elsif($pass ne $pass2) { $message_text = 'passnomatch'; }
		else
		{
			my $crypt_pwd = "{crypt}".crypt($pass,"km");
			# Set the new password
			my $ldap = Net::LDAP->new($s->{'ldap_server'}.":".$s->{'ldap_port'}) or die "Couldn't connect to LDAP: $!";
			my $lmsg = $ldap->bind($s->{'ldap_bind_dn'}, password => $s->{'ldap_bind_pw'}) or die "Couldn't bind to LDAP: $!";
			# replace the password. This automatically removes pwdReset if it exists (in OpenLDAP, anyway)
			$lmsg = $ldap->modify($session->{'authenticated_dn'}, replace => { 'userPassword' => $crypt_pwd });
			$lmsg->code && die "Failed to modify entry: ", $lmsg->error;
			$lmsg = $ldap->disconnect;
			$content->param(SUCCESS => 1);
		}
	}
	if($message_text eq "passnomatch") { $message_text = "The passwords you provided did not match. Enter the same password twice to confirm your new password."; }
	if($message_text eq "passtoolong") { $message_text = "The password you provided was too long. Your password must be less than $maxpasslength characters long."; }
	if($message_text eq "passtooshort") { $message_text = "The password you provided was too short. Your password must be at least $minpasslength characters long."; }
	$content->param(MSG => $message_text);
	$content->param(MAX_PASS_LENGTH => $maxpasslength);
}
else
{
	$header->param(LINKS => [ {HREF=>"login.pl",TEXT=>"Log in"},
							 ]);
	$content->param(LOGGED_IN => 0);
}

$header->param(IS_IE6 => 1) if(&isIE6);

print header;
print $header->output;
print $content->output;
print $footer->output;