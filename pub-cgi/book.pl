#!/usr/bin/perl -wT

use CGI ':standard';
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use BandWebsite;
use CGI::Session;
use HTML::Template;
use Date::Manip;
use Mail::Sender;
use WWW::Shorten::TinyURL;

use strict;

my $s = &getSettings;
my $debug = "0";
my $templates = $s->{'template_dir'};
my $cgi = CGI->new;
my $helper = BandWebsite->new({ basedn => $s->{'ldap_base_dn'} });
my $mail_server = $s->{'smtp_host'};
my $default_from = "'".$s->{'short_name'}." Website' <".$s->{'admin_email'}.">";
my $mail_subject = "New booking made on ".$s->{'short_name'}." website";
my $recipients = $s->{'bookings_email'};

my $action = $cgi->param('action'); $action = '' unless defined $action;
my $agree = $cgi->param('agree'); $agree = '' unless defined $agree;
my %params = $cgi->Vars;
my $cookie = '';

# Are we logged in as someone? If not, show the login page
my $session = checkUserLoggedIn($cgi);

my $header = HTML::Template->new(filename => "$templates/header.tmpl");
$header->param(PAGE_TITLE => $s->{'site_name'}." - Book the Band");
my $content = HTML::Template->new(filename => "$templates/book.tmpl");
my $footer = HTML::Template->new(filename => "$templates/footer.tmpl");

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
}
else
{
	$header->param(LOGGED_IN => 0);
	$header->param(LINKS => [ {HREF=>"list_performances.pl",TEXT=>"Public event list"},
								{HREF=>"book.pl", TEXT=>"Book the band"},
								{HREF=>"mailinglist.pl",TEXT=>"Join the mailing list"},
								 ]);
}

if($action eq "showform" && $agree) 
{	# show the form to add the details of the event
	my $today = ParseDate("today");

	my @days;
	push(@days, { DAY => '', SELECTED => 1 });
	for(my $i = 1; $i <= 31; $i++)
	{
		my $padded = '';
		if($i < 10)	{ $padded = "0$i"; }
		else { $padded = $i; }
		push(@days, { DAY => $i, PADDED_DAY => $padded, SELECTED => 0 });
	}

	my @months;
	push(@months, { MONTH => '', SELECTED => 1 });
	foreach my $month (qw(January February March April May June July August September October November December))
	{
		my $month_number = getMonthNumber($month);
		push(@months, { MONTH => $month, MONTH_NUMBER => $month_number, SELECTED => 0 });
	}

	my @years;
	push(@years, { YEAR => '', SELECTED => 1 });
	my $this_year = UnixDate($today, "%Y");
	for(my $i = $this_year - 1; $i <= $this_year + 10; $i++)
	{
		push(@years, { YEAR => $i, SELECTED => 0 });
	}

	my @hours;
	push(@hours, { PADDED_HOUR => '', SELECTED => 1 });
	for(my $i = 0; $i <= 23; $i++)
	{
		my $padded = '';
		if($i < 10)	{ $padded = "0$i"; }
		else { $padded = $i; }
		push(@hours, { PADDED_HOUR => $padded, SELECTED => 0 });
	}

	my @minutes;
	push(@minutes, { MINUTE => '', SELECTED => 1 });
	foreach my $minute (qw(00 05 10 15 20 25 30 35 40 45 50 55))
	{
		push(@minutes, { MINUTE => $minute, SELECTED => 0 });
	}

	# find the earliest date that the person can book for (two months from now)
	my $date_restriction = DateCalc($today, "+ 2 months");

	$content->param(IS_SHOWFORM => 1);
	$content->param(TITLE => "Book the Band",
					EVENT_DAY => \@days, EVENT_MONTH => \@months, EVENT_YEAR => \@years, EVENT_LIMIT => getRealDate(getLdapDate($date_restriction)),
					EVENT_HOUR => \@hours, EVENT_MINUTE => \@minutes,
					);

}
elsif($action eq "add")
{	# add a new event
	$content->param(IS_ATTEMPTED => 1);
	my ($cn, $event, $date, $time, $timeOnSite, $eventType, $doe, $title, $anchorName, @atts, @delete_all); 

	$cn = $params{'spb-displayName'};
	if(checkCookieForUser($cn))
	{
		$content->param(IS_REPEAT => 1);
	}
	else
	{
		$anchorName = generateAnchorName($cn);
		$doe = $params{'na-yearOfEvent'}.$params{'na-monthOfEvent'}.$params{'na-dayOfEvent'};
		$time = $params{'na-hourOfEvent'}.$params{'na-minuteOfEvent'};
		$timeOnSite = $params{'na-hourOnSite'}.$params{'na-minuteOnSite'};
		
	
		$event = "cn=$cn,ou=events,ou=current,".$s->{'ldap_base_dn'};
		my $encoded_event = $cgi->escape($event);
	
		# TODO: Lat and Long of address
		@atts = ('spb-date' => $doe, 'spb-time' => $time, 'spb-timeOnSite' => $timeOnSite, 'spb-eventType' => "PERFORMANCE",
				'cn' => $cn, 'objectClass' => [qw(spbEvent spbLocation)], 'spb-websiteAnchorName' => $anchorName, 
				'spb-eventStatus' => "REQUESTED", 'spb-subPrice' => "0");
		foreach my $param (keys %params)
		{
			if($param =~ /na-[a-zA-Z0-9]+/ || $param eq "action")	# discount the params that begin with na - they are not attributes
			{														# to be used directly but must be worked on first. Added above 
	#			logMsg("$param - not an att"); 
			} 
			elsif($param =~ /^([a-zA-Z-]+)([0-9]+)$/)	# forgotten why this is here
			{
				logMsg("$param - $1");
			}
			else										# otherwise the param should directly match an LDAP attribute so we just add it
			{											# TODO: Sanitise?
	#			logMsg("$param - adding $param with value ".$params{$param});
				if($params{$param})
				{
					push @atts, $param => $params{$param};
				}
				else
				{	# TODO: JavaScript validation
					die "Field '".getAttributeDisplayName($param)."' cannot be empty. Please go back and enter a value.\n\n" if not attributeOptional($param);
				}
			}
		}
	
		# Set up an LDAP connection
		my $ldap = Net::LDAP->new($s->{'ldap_server'}.":".$s->{'ldap_port'}) or die "Couldn't connect to LDAP: $!";
		my $lmsg = $ldap->bind( $s->{'ldap_bind_dn'}, password => $s->{'ldap_bind_pw'}) or die "Couldn't bind to LDAP: $!";
		
		# Add the event entry to the directory
		$lmsg = $ldap->add($event, attrs => \@atts) unless $debug;
		$lmsg->code && die "Failed to add entry: ", $lmsg->error unless $debug;
	
		# Close the LDAP connection
		$lmsg = $ldap->disconnect;
	
		# since we were successful, set a cookie to mark that we did it already for this user. This will help prevent browser refreshes adding multiples
		$cookie = setCookieForUser($cn) unless $debug;
	
		eval
		{
			my $body = "A new booking request has been made on the ".$s->{'short_name'}." website by ".$params{'spb-requesterName'}." for the band to attend the event \"$cn\". For the full details, and to take the next step (approving the event), visit the URL below.

";
			my $url = makeashorterlink($s->{'home'}."/cgi-bin/event.pl?action=view&event=$encoded_event");
			$body .= $url;

			my $sender = new Mail::Sender {smtp => $mail_server, on_errors => 'die', from => $default_from };
			if($params{'spb-requesterEmail'})
			{
				$sender->Open({to => $recipients, subject => $mail_subject, replyto => "\'".$params{'spb-requesterName'}."\' <".$params{'spb-requesterEmail'}.">" });
			}
			else
			{
				$sender->Open({to => $recipients, subject => $mail_subject });
			}
			$sender->SendLineEnc($body);
			$sender->Close();
		};
		if ($@)
		{
			die "Failed to send the message: $@\n";
		}

		$content->param(IS_SUCCESS => 1);
	}
}
else
{	# show the initial page with the terms and conditions
	$content->param(TITLE => "Book the Band");
}

$header->param(IS_IE6 => 1) if(&isIE6);

if($cookie)
{
	print header(-cookie => $cookie);
}
else
{
	print header;
}
print $header->output;
print $content->output;
print $footer->output;