#!/usr/bin/perl -wT

use CGI ':standard';
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use BandWebsite;
use CGI::Session;
use HTML::Template;

my $s = &getSettings;
my $debug = "0";
my $templates = $s->{'template_dir'};
my $cgi = CGI->new;
my $helper = BandWebsite->new({ basedn => $s->{'ldap_base_dn'} });

# Are we logged in as someone? If not, show the login page
my $session = checkUserLoggedIn($cgi);

my $header = HTML::Template->new(filename => "$templates/header.tmpl");
my $content = HTML::Template->new(filename => "$templates/front.tmpl");
my $footer = HTML::Template->new(filename => "$templates/footer.tmpl");

if($session)
{
	# Get some details for us
	$header->param(CN => $session->{'cn'});
	$header->param(LOGGED_IN => 1);
	# Everyone is allowed to access this section now, so that they can view the member list
#	push(@links, {HREF=>"list_members.pl",TEXT=>"Member"}) if $session->{'groups'}->{'Membership Admins'};
}
else
{
	$header->param(LOGGED_IN => 0);
}
my @links = ({HREF=>"about.pl",TEXT=>"About the band"},
		{HREF=>"mailinglist.pl",TEXT=>"Join the mailing list"},
		{HREF=>"book.pl", TEXT=>"Book the band"},
		);
$header->param(LINKS => \@links);
$header->param(IS_IE6 => 1) if(&isIE6);
$header->param(PAGE_TITLE => $s->{'site_name'}." - Home");

print header;
print $header->output;
print $content->output;
print $footer->output;
