#!/usr/bin/perl -wT

use CGI ':standard';
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use Net::LDAP;
use BandWebsite;
use CGI::Session;
use HTML::Template;
use Date::Manip;

use strict;

my $s = &getSettings;
my $debug = "0";
my $templates = $s->{'template_dir'};
my $cgi = CGI->new;
my $helper = BandWebsite->new({ basedn => $s->{'ldap_base_dn'} });

my $title = "Pay My Subs";

my $header = HTML::Template->new(filename => "$templates/header.tmpl");
my $content = HTML::Template->new(filename => "$templates/paymysubs.tmpl", global_vars => 1);
my $footer = HTML::Template->new(filename => "$templates/footer.tmpl");

# Are we logged in as someone?
my $session = checkUserLoggedIn($cgi);

if($session)
{
	$header->param(CN => $session->{'cn'});
	$header->param(LOGGED_IN => 1);
	my @links = ({HREF=>"paymysubs.pl",TEXT=>"Pay My Subs"});
	$header->param(LINKS => \@links);
}
else
{
	print redirect(buildLoginPageURL($cgi));		# bounce the user to the login page, adding the source so that 
								# they can be brought back once they are authenticated
}

$content->param(TITLE => $title);
$header->param(PAGE_TITLE => $s->{'site_name'}." - $title");

# must be authenticated if we are still executing. Carry on!
# Set up an LDAP connection
my $ldap = Net::LDAP->new($s->{'ldap_server'}.":".$s->{'ldap_port'}) or die "Couldn't connect to LDAP: $!";
my $lmsg = $ldap->bind( $s->{'ldap_bind_dn'}, password => $s->{'ldap_bind_pw'}) or die "Couldn't bind to LDAP: $!";

my $member_details = getMemberDetails($ldap, $session->{'authenticated_uid'});

$lmsg = $ldap->disconnect;

my $phone = $member_details->{'homePhone'};
$phone =~ s/^0//;

$content->param(GIVEN_NAME => $member_details->{'givenName'}, SN => $member_details->{'sn'}, 
  HI => $member_details->{'spb-houseIdentifierLocation'}, STREET => $member_details->{'spb-streetLocation'},
  BOROUGH => $member_details->{'spb-boroughLocation'}, TOWN => $member_details->{'spb-townLocation'},
  COUNTY => $member_details->{'spb-countyLocation'}, POSTCODE => $member_details->{'spb-postcodeLocation'},
  PHONE => $phone);

$header->param(IS_IE6 => 1) if(&isIE6);

print header;
print $header->output;
print $content->output;
print $footer->output;