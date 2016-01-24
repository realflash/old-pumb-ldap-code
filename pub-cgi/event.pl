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

my $action = $cgi->param('action'); $action = 'add' unless defined $action;
my $event = $cgi->unescape($cgi->param('event')); $event = '' unless defined $event;
my %params = $cgi->Vars;
my $message = '';

my $header = HTML::Template->new(filename => "$templates/header.tmpl");
my $content = HTML::Template->new(filename => "$templates/event.tmpl");
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
	push(@links, {HREF=>"event.pl?action=add",TEXT=>"Add event"}, 
				{HREF=>"delete.pl?type=event", TEXT=>"Delete event"},
				{HREF=>"delete.pl?type=event&action=undelete", TEXT=>"Undelete event"}) if $session->{'groups'}->{'Event Admins'};
	$header->param(LINKS => \@links);
	$content->param(ESCAPED_EVENT => $cgi->escape($event));
}
else
{
	print redirect(buildLoginPageURL($cgi));		# bounce the user to the login page, adding the source so that they 
													# can be brought back once they are authenticated
}

# must be authenticated if we are still executing. Carry on!
# Set up an LDAP connection
my $ldap = Net::LDAP->new($s->{'ldap_server'}.":".$s->{'ldap_port'}) or die "Couldn't connect to LDAP: $!";
my $lmsg = $ldap->bind( $s->{'ldap_bind_dn'}, password => $s->{'ldap_bind_pw'}) or die "Couldn't bind to LDAP: $!";

my $event_details = {};						# init the details of the event as an empty hash

if($action eq "edit" || $action eq "add")
{
	# First set the defaults for the fields, which will be overwritten in an edit, but apply to an add
	my ($intendance_checked, $subCharged, $description, $anchorName, $time) = "";
	my $next_thursday = ParseDate("next thursday");
	my $dayOfEvent = UnixDate($next_thursday, "%d");
	my $monthOfEvent = UnixDate($next_thursday, "%m");
	my $yearOfEvent = UnixDate($next_thursday, "%Y");
	my $subPrice = "1.00";
	my $hourOfEvent = 19;
	my $minuteOfEvent = 45;
	my $title = "Add new event";
	my $displayName = "Rehearsal";
	my $houseIdentifierLocation = "Surrey Police Headquarters";
	my $streetLocation = "Mount Browne, Sandy Lane";
	my $boroughLocation;
	my $townLocation = "Guildford";
	my $countyLocation = "Surrey";
	my $postcodeLocation = "GU1 1HG";
	my $next_action = "write";
	my $eventType = "REHEARSAL";
	$header->param(PAGE_TITLE => $s->{'site_name'}." - Add Event");

	
	# Overwrite these values with the correct ones if we are doing an edit rather than an add
	$event_details = getEventDetails($ldap, $event) if $event;		# overwrite the hash with real details if 
										# we have been passed the DN of a event to work with
	if($action eq "edit")
	{
		$eventType = $event_details->{'spb-eventType'};
		my $doe = $event_details->{'spb-date'};
		$dayOfEvent = substr($doe,6,2);
		$monthOfEvent = substr($doe,4,2);
		$yearOfEvent = substr($doe,0,4);
		$houseIdentifierLocation = $event_details->{'spb-houseIdentifierLocation'};
		$streetLocation = $event_details->{'spb-streetLocation'};
		$boroughLocation = $event_details->{'spb-boroughLocation'};
		$townLocation = $event_details->{'spb-townLocation'};
		$countyLocation = $event_details->{'spb-countyLocation'};
		$postcodeLocation = $event_details->{'spb-postcodeLocation'};
		$subPrice = $event_details->{'spb-subPrice'};
		$description = $cgi->unescape($event_details->{'description'});
		$displayName = $event_details->{'spb-displayName'};
		$subCharged = $event_details->{'spb-subCharged'};
		$anchorName = $event_details->{'spb-websiteAnchorName'};
		$time = $event_details->{'spb-time'};
		$hourOfEvent = substr($time,0,2);
		$minuteOfEvent = substr($time,2,2);

		$title = "Details for event ".$event_details->{'spb-displayName'};
		$next_action = "update";
		$header->param(PAGE_TITLE => $s->{'site_name'}." - Edit Event $displayName");
	}
	
	$content->param(IS_EDIT => 1);			# let the template know it should display the edit half not the view half

	if($eventType eq "PERFORMANCE")	{ $content->param(IS_PERFORMANCE => 1);	}
	elsif($eventType eq "REHEARSAL") { $content->param(IS_REHEARSAL => 1); }
	elsif($eventType eq "SOCIAL") {	$content->param(IS_SOCIAL => 1); }
	else {	die "Bad event type data '$eventType'";	}

	my @days;
	for(my $i = 1; $i <= 31; $i++)
	{
		my $padded = '';
		if($i < 10)	{ $padded = "0$i"; }
		else { $padded = $i; }
		my $selected = 1 if $i == $dayOfEvent;
		push(@days, { DAY => $i, PADDED_DAY => $padded, SELECTED => $selected });
	}

	my @months;
	foreach my $month (qw(January February March April May June July August September October November December))
	{
		my $month_number = getMonthNumber($month);
		my $selected = 1 if $month_number eq $monthOfEvent;
		push(@months, { MONTH => $month, MONTH_NUMBER => $month_number, SELECTED => $selected });
	}

	my @years;
	my $this_year = UnixDate(ParseDate("today"), "%Y");
	for(my $i = $this_year - 1; $i <= $this_year + 10; $i++)
	{
		my $selected = 1 if $i eq $yearOfEvent;
		push(@years, { YEAR => $i, SELECTED => $selected });
	}

	my @hours;
	for(my $i = 0; $i <= 23; $i++)
	{
		my $padded = '';
		if($i < 10)	{ $padded = "0$i"; }
		else { $padded = $i; }
		my $selected = 1 if $i == $hourOfEvent;
		push(@hours, { PADDED_HOUR => $padded, SELECTED => $selected });
	}

	my @minutes;
	foreach my $minute (qw(00 05 10 15 20 25 30 35 40 45 50 55))
	{
		my $selected = 1 if $minute == $minuteOfEvent;
		push(@minutes, { MINUTE => $minute, SELECTED => $selected });
	}

	$header->param(PAGE_TITLE => $s->{'site_name'}." - $title");
	$content->param(TITLE => $title, NEXT_ACTION => $next_action, EVENT_TYPE_LBL => getAttributeDisplayName('spb-eventType'),
					DISP_NAME_LBL => getAttributeDisplayName('spb-displayName'), DISP_NAME => $displayName,
					DATE_LBL => getAttributeDisplayName('spb-date'), EVENT_DAY => \@days, EVENT_MONTH => \@months, EVENT_YEAR => \@years,
					TIME_LBL => getAttributeDisplayName('spb-time'), EVENT_HOUR => \@hours, EVENT_MINUTE => \@minutes,
					SUBS_LBL => getAttributeDisplayName('spb-subPrice'), SUBS => $subPrice, SUB_CHARGED => $subCharged,
					HI_LBL => getAttributeDisplayName('spb-houseIdentifierLocation'), HI => $houseIdentifierLocation,
					STREET_LBL => getAttributeDisplayName('spb-streetLocation'), STREET => $streetLocation,
					BOROUGH_LBL => getAttributeDisplayName('spb-boroughLocation'), BOROUGH => $boroughLocation,
					TOWN_LBL => getAttributeDisplayName('spb-townLocation'), TOWN => $townLocation,
					COUNTY_LBL => getAttributeDisplayName('spb-countyLocation'), COUNTY => $countyLocation,
					POSTCODE_LBL => getAttributeDisplayName('spb-postcodeLocation'), POSTCODE => $postcodeLocation,
					DESCRIPTION_LBL => getAttributeDisplayName('description'), DESCRIPTION => $description,
					ANCHOR_NAME => $anchorName
					);
}
elsif($action eq "write" || $action eq "update" || $action eq "view")
{
	my ($cn, $subPrice, $date, $time, $eventType, $doe, $title, $anchorName, @atts, @delete_all); 

	$eventType = $params{'spb-eventType'};
	my $yoe = $params{'na-yearOfEvent'}; $yoe = '' unless defined $yoe;
	my $moe = $params{'na-monthOfEvent'}; $moe = '' unless defined $moe;
	my $dayoe = $params{'na-dayOfEvent'}; $dayoe = '' unless defined $dayoe;
	$doe = $yoe.$moe.$dayoe;
	my $hoe = $params{'na-hourOfEvent'}; $hoe = '' unless defined $hoe;
	my $minoe = $params{'na-minuteOfEvent'}; $minoe = '' unless defined $minoe;
	$time = $hoe.$minoe;
	
	if($action eq "write")
	{
		if($eventType eq "REHEARSAL")
		{
			$cn = $params{'spb-displayName'}." ".$doe;
		}
		else
		{
			$cn = $params{'spb-displayName'};
			$anchorName = generateAnchorName($cn);
		}

		$event = "cn=$cn,ou=events,ou=current,".$s->{'ldap_base_dn'};
	}

	if($action eq "write" || $action eq "update")
	{
		
		
		# TODO: Lat and Long of address
		@atts = ('spb-date' => $doe, 'spb-time' => $time);
		foreach my $param (keys %params)
		{
			if($param =~ /na-[a-zA-Z0-9]+/ || $param eq "action" || $param eq "event")
			{ 
				#print STDERR "$param - not an att"; 
			} 
			elsif($param =~ /^([a-zA-Z-]+)([0-9]+)$/)
			{
				#print STDERR "$param - $1";
			}
			else
			{
				#logMsg("$param - adding $param (value:'".$cgi->unescape($params{$param})."')");
				if($params{$param})
				{
					push @atts, $param => $params{$param};
				}
				else
				{
					die "Field '".getAttributeDisplayName($param)."' cannot be empty. Please go back and enter a value.\n\n" if not attributeOptional($param);
				}
		
			}
		}

		# Add optional atts if they exist, otherwise add them to the list of values to be deleted if they are in LDAP
		foreach my $att (@{getOptionalAttributes()})
		{
			#print STDERR "Checking to see if att $att exists in entry $event\n";
			if(length($params{$att}) < 1) { push @delete_all, $att if $action eq "update" && attributeExists($ldap, $event, $att); }
		}
	}
	
	if($action eq "write")
	{
		# Add stuff that is only required for creating events, not modifying them
		if($eventType eq "PERFORMANCE")
		{
			push @atts, 'cn' => $cn, 'objectClass' => [qw(spbEvent spbLocation)], 'spb-websiteAnchorName' => $anchorName;
		}
		else
		{
			push @atts, 'cn' => $cn, 'objectClass' => [qw(spbEvent spbLocation)];
		}
		
		# Add the event entry to the directory
		$lmsg = $ldap->add($event, attrs => \@atts) unless $debug;
		$lmsg->code && die "Failed to add entry: ", $lmsg->error unless $debug;
	}
	
	if($action eq "update")
	{
		# Modify the user entry to the directory
		$lmsg = $ldap->modify($event, replace => \@atts, delete => \@delete_all) unless $debug;
		$lmsg->code && die "Failed to modify entry: ", $lmsg->error unless $debug;
	}
	
	if($action eq "write" || $action eq "update")
	{
		# since we were successful, set a cookie to mark that we did it already for this user. This will help prevent browser refreshes adding users
		my $cookie = setCookieForUser($cn) unless $debug;
	
		print header(-cookie => $cookie);
		
		# Print a message to say all is well
		$message = "Changes saved";
	}

	# ------------- Now a view -----------------
	my $ed = getEventDetails($ldap, $event) if $event;		# overwrite the hash with the new or updated details
	$title = "Details for event ".$ed->{'spb-displayName'};
	my $hi = $ed->{'spb-houseIdentifierLocation'};
	$eventType = $ed->{'spb-eventType'};
	$header->param(PAGE_TITLE => $s->{'site_name'}." - View Event $title");
	$content->param(TITLE => $title, 
					EVENT_TYPE_LBL => getAttributeDisplayName('spb-eventType'), EVENT_TYPE => getValueDisplayName($eventType),
					DISP_NAME_LBL => getAttributeDisplayName('spb-displayName'), DISP_NAME => $ed->{'spb-displayName'},
					DATE_LBL => getAttributeDisplayName('spb-date'), DATE => getRealDate($ed->{'spb-date'}), 
					DATE_DELTA => getTimeDelta($ed->{'spb-date'}), DISPLAY_AS_NUMBER => looks_like_number($hi),
					TIME_LBL => getAttributeDisplayName('spb-time'), TIME =>  getRealTime($ed->{'spb-time'}),
					SUBS_LBL => getAttributeDisplayName('spb-subPrice'), SUBS => $ed->{'spb-subPrice'},
					HI_LBL => getAttributeDisplayName('spb-houseIdentifierLocation'), HI => $hi,
					STREET_LBL => getAttributeDisplayName('spb-streetLocation'), STREET => $ed->{'spb-streetLocation'},
					BOROUGH_LBL => getAttributeDisplayName('spb-boroughLocation'), BOROUGH => $ed->{'spb-boroughLocation'},
					TOWN_LBL => getAttributeDisplayName('spb-townLocation'), TOWN => $ed->{'spb-townLocation'},
					COUNTY_LBL => getAttributeDisplayName('spb-countyLocation'), COUNTY => $ed->{'spb-countyLocation'},
					POSTCODE_LBL => getAttributeDisplayName('spb-postcodeLocation'), POSTCODE => $ed->{'spb-postcodeLocation'},
					DESCRIPTION_LBL => getAttributeDisplayName('description'), DESCRIPTION => $ed->{'description'},
					ANCHOR_NAME_LBL => getAttributeDisplayName('spb-websiteAnchorName'), ANCHOR_NAME => $ed->{'spb-websiteAnchorName'},
					HOME => $s->{'home'}
					);
	if($eventType eq "PERFORMANCE")	{ $content->param(IS_PERFORMANCE => 1);	}
	elsif($eventType eq "REHEARSAL") { $content->param(IS_REHEARSAL => 1); }
	elsif($eventType eq "SOCIAL") {	$content->param(IS_SOCIAL => 1); }
	else {	die "Bad event type data '$eventType'";	}

}

$lmsg = $ldap->disconnect;

$header->param(IS_IE6 => 1) if(&isIE6);

print header;
print $header->output;
print $content->output;
print $footer->output;
