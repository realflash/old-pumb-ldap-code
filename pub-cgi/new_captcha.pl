#!/usr/bin/perl -wT

use CGI ':standard';
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use BandWebsite;
#use CGI::Session;
use HTML::Template;
#use Mail::Sender;
#use Authen::Captcha;

use strict;

my $s = &getSettings;
my $debug = "0";
my $templates = $s->{'template_dir'};
my $cgi = CGI->new;
my $helper = BandWebsite->new({ basedn => $s->{'ldap_base_dn'} });

my $out = HTML::Template->new(filename => "$templates/new_captcha.tmpl");

my ($md5sum, $image) = $helper->getCaptcha;		# call our helper function in BandWebsite. Returns the path to the 
						# image and the sum
$out->param(CAPTCHA_IMG => $image, CAPTCHA_SUM => $md5sum);

print header;
print $out->output;