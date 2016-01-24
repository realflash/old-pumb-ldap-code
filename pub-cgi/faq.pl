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
$header->param(PAGE_TITLE => $s->{'site_name'}." - FAQ");
$header->param(LINKS => [ {HREF=>"about.pl#band",TEXT=>"The band"},
							{HREF=>"about.pl#music",TEXT=>"The music"},
							{HREF=>"about.pl#members",TEXT=>"The members"},
							{HREF=>"about.pl#events",TEXT=>"The events"},
							{HREF=>"faq.pl",TEXT=>"FAQ"},
							 ]);
my $content = HTML::Template->new(filename => "$templates/faq.tmpl");
my $footer = HTML::Template->new(filename => "$templates/footer.tmpl");

if($session)
{
	$header->param(CN => $session->{'cn'});
	$header->param(LOGGED_IN => 1);
}
else
{
	$header->param(LOGGED_IN => 0);
}

$header->param(IS_IE6 => 1) if(&isIE6);

print header;
print $header->output;
print $content->output;
print $footer->output;