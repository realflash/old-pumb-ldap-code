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

my $showOnlyType = $cgi->param('type'); $showOnlyType = '' unless defined $showOnlyType;
my $title = "";

my $header = HTML::Template->new(filename => "$templates/header.tmpl");
my $content = HTML::Template->new(filename => "$templates/list_events.tmpl", global_vars => 1);
my $footer = HTML::Template->new(filename => "$templates/footer.tmpl");

# Are we logged in as someone?
my $session = checkUserLoggedIn($cgi);

if($session)
{
	$header->param(CN => $session->{'cn'});
	$header->param(LOGGED_IN => 1);
	my @links = ({HREF=>"list_performances.pl",TEXT=>"Public event list"},
								{HREF=>"list_events.pl",TEXT=>"Show all events"},
								{HREF=>"list_events.pl?type=PERFORMANCE",TEXT=>"Show performances"},
								{HREF=>"list_events.pl?type=SOCIAL",TEXT=>"Show socials"});
	if($session->{'groups'}->{'Event Admins'})
	{
		#logMsg("User ".$session->{'cn'}." is an Event Admin");
		push(@links, {HREF=>"event.pl?action=add",TEXT=>"Add event"}, 
				{HREF=>"delete.pl?type=event", TEXT=>"Delete event"},
				{HREF=>"delete.pl?type=event&action=undelete", TEXT=>"Undelete event"});
		$content->param(IS_EVENT_ADMIN => 1);
	}
	if($session->{'groups'}->{'Membership Admins'})
	{
		#logMsg("User ".$session->{'cn'}." is an Event Admin");
		$content->param(IS_MEMBER_ADMIN => 1);
	}
	$header->param(LINKS => \@links);
}
else
{
	print redirect(buildLoginPageURL($cgi));		# bounce the user to the login page, adding the source so that they can be brought back once
													# they are authenticated
}

# set the title
if($showOnlyType eq "PERFORMANCE") { $title = "List of all performances" }
elsif($showOnlyType eq "SOCIAL") { $title = "List of all social events" }
elsif($showOnlyType eq "REHEARSAL") { $title = "List of all rehearsals" }
else { $title = "List of all events" }
$content->param(TITLE => $title);
$header->param(PAGE_TITLE => $s->{'site_name'}." - $title");

# must be authenticated if we are still executing. Carry on!
# Set up an LDAP connection
my $ldap = Net::LDAP->new($s->{'ldap_server'}.":".$s->{'ldap_port'}) or die "Couldn't connect to LDAP: $!";
my $lmsg = $ldap->bind( $s->{'ldap_bind_dn'}, password => $s->{'ldap_bind_pw'}) or die "Couldn't bind to LDAP: $!";

my $zebra = 1;
my $colour_number = $zebra;
my $reached_today = 0;
my $events = getEventList($ldap);
my @date_sorted_event_dns = sort { $events->{$b}->{'spb-date'} <=> $events->{$a}->{'spb-date'} } keys %{$events};
my $today = UnixDate(ParseDate("today"), "%Y%m%d");

my @events;
foreach my $dn (@date_sorted_event_dns)
{
	my $event_details = $events->{$dn};
	my $displayName = $event_details->{'spb-displayName'};
	my $date = $event_details->{'spb-date'};
	my $display_date = getRealDate($date);
	my $eventType = $event_details->{'spb-eventType'};
	my $encoded_dn = $cgi->escape($dn);
	my $intendanceReq = 1 if $event_details->{'spb-intendanceRequiredDate'};

	next if($showOnlyType && $showOnlyType ne $eventType);		# if we have told to show only a certain type of event, and this event doesn't
																# match that type, skip to the next one

	if($date == $today)
	{ 
		$colour_number = 3;		# the event is today. Highlight it in yellow
		$reached_today = 1;
	}
	else
	{
		$colour_number = $zebra;	# otherwise stick to the standard to greys
		if(!$reached_today && $date < $today)		# working our way backwards, we have gone past today without encountering an event
		{ 											# that is today. Push an extra element into the array to trigger the printing of a 
			push(@events, { IS_TODAY_ROW => 1, DISPLAY_DATE => getRealDate($today) }); 	# today row for ease of reference
			$reached_today = 1;
		}
	}

	push(@events, { COLOUR_NUMBER => $colour_number, ENCODED_DN => $encoded_dn, DISPLAY_NAME => $displayName, DISPLAY_DATE => $display_date,
					INTENDANCE_REQ => $intendanceReq });

	if($zebra eq 1)
	{
		$zebra = 2;
	}
	else
	{
		$zebra = 1;
	}
}
$content->param(EVENTS => \@events);
$lmsg = $ldap->disconnect;

$header->param(IS_IE6 => 1) if(&isIE6);

print header;
print $header->output;
print $content->output;
print $footer->output;