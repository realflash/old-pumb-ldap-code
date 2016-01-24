#!/usr/bin/perl -wT

use CGI ':standard';
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use Net::LDAP;
use BandWebsite;
use CGI::Session;
use HTML::Template;
use Date::Manip;
use Scalar::Util qw(looks_like_number);

use strict;

my $s = &getSettings;
my $debug = "0";
my $templates = $s->{'template_dir'};
my $cgi = CGI->new;
my $helper = BandWebsite->new({ basedn => $s->{'ldap_base_dn'} });

my $ldap = Net::LDAP->new($s->{'ldap_server'}.":".$s->{'ldap_port'}) or die "Couldn't connect to LDAP: $!";
my $lmsg = $ldap->bind( $s->{'ldap_bind_dn'}, password => $s->{'ldap_bind_pw'}) or die "Couldn't bind to LDAP: $!";

my $header = HTML::Template->new(filename => "$templates/header.tmpl");
$header->param(PAGE_TITLE => $s->{'site_name'}." - Performances");
my $content = HTML::Template->new(filename => "$templates/list_performances.tmpl");
my $footer = HTML::Template->new(filename => "$templates/footer.tmpl");

# Are we logged in as someone?
my $session = checkUserLoggedIn($cgi);

if($session)
{
	$header->param(CN => $session->{'cn'});
	$header->param(LOGGED_IN => 1);
	#$content->param(LOGGED_IN => 1);
	my @links = ({HREF=>"list_performances.pl",TEXT=>"Public event list"},
								{HREF=>"list_events.pl",TEXT=>"Show all events"},
								{HREF=>"list_events.pl?type=PERFORMANCE",TEXT=>"Show performances"},
								{HREF=>"list_events.pl?type=SOCIAL",TEXT=>"Show socials"});
	push(@links, {HREF=>"event.pl?action=add",TEXT=>"Add event"}, 
				{HREF=>"delete.pl?type=event", TEXT=>"Delete event"},
				{HREF=>"delete.pl?type=event&action=undelete", TEXT=>"Undelete event"}) if $session->{'groups'}->{'Event Admins'};
	$header->param(LINKS => \@links);
}
else
{
	$header->param(LINKS => [ {HREF=>"list_performances.pl",TEXT=>"Public event list"},
								{HREF=>"book.pl", TEXT=>"Book the band"},
								{HREF=>"mailinglist.pl",TEXT=>"Join the mailing list"},
								 ]);
}

my $show_old = 200;				# how many days worth of old events to see. TODO: make this user selectable
$content->param(PAST_PERF_LIMIT_DAYS => $show_old);
my $today = ParseDate("today");
my $ldap_today = UnixDate($today, "%Y%m%d");
my $yesterday = DateCalc($today, "- 1 days");
my $oldest_event = DateCalc($today, "- ".$show_old." days");
my $future_events = getEventList($ldap, {'from' => UnixDate($today, "%Y%m%d")});	# events from today onwards (including today)
my $past_events = getEventList($ldap, {'from' => UnixDate($oldest_event, "%Y%m%d"), 'to' => UnixDate($yesterday, "%Y%m%d")});	# events from

# 	my $encoded_dn = $cgi->escape($dn);
if(scalar(keys %$future_events) > 0)
{
	$content->param(FUTURE_EVENTS => buildEventList($future_events));
	$content->param(IS_FUTURE => 1);
}

if(scalar(keys %$past_events) > 0)
{
	$content->param(PAST_EVENTS => buildEventList($past_events));
	$content->param(IS_PAST => 1);
}

$lmsg = $ldap->disconnect;

$header->param(IS_IE6 => 1) if(&isIE6);

print header;
print $header->output;
print $content->output;
print $footer->output;

sub buildEventList 
{
		my $eventlist = $_[0];

		my @events;

		my @date_sorted_event_dns = sort { $eventlist->{$a}->{'spb-date'} <=> $eventlist->{$b}->{'spb-date'} } keys %{$eventlist};
		foreach my $dn (@date_sorted_event_dns)
		{
			my $ed = $eventlist->{$dn};
			next if $ed->{'spb-eventType'} ne "PERFORMANCE";			# don't bother showing anything other than performances
			my $hi = $ed->{'spb-houseIdentifierLocation'};
			push(@events, { ANCHOR_NAME => $ed->{'spb-websiteAnchorName'},
							CN => $ed->{'spb-displayName'},
							DISPLAY_DATE => getRealDate($ed->{'spb-date'}),
							TIME => $ed->{'spb-time'},
							DESCRIPTION => $ed->{'description'},
							HOUSE_IDENTIFIER => $hi,
							STREET => $ed->{'spb-streetLocation'},
							TOWN => $ed->{'spb-townLocation'},
							COUNTY => $ed->{'spb-countyLocation'},
							POSTCODE => $ed->{'spb-postcodeLocation'},
							DISPLAY_AS_NUMBER => looks_like_number($hi) });
		}
		return \@events;
}
