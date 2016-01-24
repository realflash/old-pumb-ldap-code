#!/usr/bin/perl -wT

use CGI ':standard';
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use CGI::Session;
use BandWebsite;

my $s = &getSettings;
my $home = $s->{'home'};

my $session = new CGI::Session() or die CGI::Session->errstr;
$session->delete();
print redirect(-uri => $home);