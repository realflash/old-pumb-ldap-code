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

my $action = $cgi->param('action'); $action = 'delete' unless defined $action;
my $type = $cgi->param('type'); $type = 'event' unless defined $type;
my $entity = $cgi->unescape($cgi->param('entity')); $entity = '' unless defined $entity;
my %params = $cgi->Vars;
my $message = '';
my $title = '';
my $authorised = 0;

my $header = HTML::Template->new(filename => "$templates/header.tmpl");
my $content = HTML::Template->new(filename => "$templates/delete.tmpl");
my $footer = HTML::Template->new(filename => "$templates/footer.tmpl");

# Are we logged in as someone?
my $session = checkUserLoggedIn($cgi);

if($session)
{
	$header->param(CN => $session->{'cn'});
	$header->param(LOGGED_IN => 1);
	if($type eq 'event')
	{
		my @links = ({HREF=>"list_performances.pl",TEXT=>"Public event list"},
									{HREF=>"list_events.pl",TEXT=>"Show all events"},
									{HREF=>"list_events.pl?type=PERFORMANCE",TEXT=>"Show performances"},
									{HREF=>"list_events.pl?type=SOCIAL",TEXT=>"Show socials"});
		if($session->{'groups'}->{'Event Admins'})
		{
			push(@links, {HREF=>"event.pl?action=add",TEXT=>"Add event"}, 
						{HREF=>"delete.pl?type=event", TEXT=>"Delete event"},
						{HREF=>"delete.pl?type=event&action=undelete", TEXT=>"Undelete event"});
			$header->param(LINKS => \@links);
			$content->param(IS_ADMIN => 1);
			$authorised = 1;
		}
	}
	elsif($type eq 'member')
	{
		my @links = ({HREF=>"list_members.pl",TEXT=>"Show all members"}, {HREF=>"report_membership.pl",TEXT=>"Contact Sheet"});
		if($session->{'groups'}->{'Membership Admins'})
		{
			push(@links, {HREF=>"member.pl?action=add",TEXT=>"Add member"}, 
					{HREF=>"delete.pl?type=member", TEXT=>"Delete member"},
					{HREF=>"delete.pl?type=member&action=undelete", TEXT=>"Undelete member"});
			$header->param(LINKS => \@links);
			$content->param(IS_ADMIN => 1);
			$authorised = 1;
		}
	}
}
else
{
	print redirect(buildLoginPageURL($cgi));		# bounce the user to the login page, adding the source so that they can be 
													# brought back once they are authenticated
}

if($authorised)
{
	# must be authenticated and in the right group if we are still executing. Carry on!
	# Set up an LDAP connection
	my $ldap = Net::LDAP->new($s->{'ldap_server'}.":".$s->{'ldap_port'}) or die "Couldn't connect to LDAP: $!";
	my $lmsg = $ldap->bind( $s->{'ldap_bind_dn'}, password => $s->{'ldap_bind_pw'}) or die "Couldn't bind to LDAP: $!";
	my $ou = '';	

	if(not $entity)
	{
		if($action eq "delete")
		{
			$title .= "Delete";
			$content->param(IS_DELETE => 1);
			$ou = "current";
		}
		elsif($action eq "undelete")
		{
			$title .= "Undelete";
			$content->param(IS_UNDELETE => 1);
			$ou = "deleted";
		}
		else
		{
			die "Don't know action $action";
		}

		if($type eq "member")
		{
			my $users = getUserList($ldap, $ou);
			my @cn_sorted_user_dns = sort keys %{$users};
			my @userlist;
			foreach my $cn (@cn_sorted_user_dns)
			{
				my $encoded_dn = $cgi->escape($users->{$cn});
				push(@userlist, { ENCODED_DN => $encoded_dn, DISPLAY_NAME => $cn });	
			}
			$content->param(ENTITY_LIST => \@userlist);
			$title .= " Member";
			$content->param(IS_USER => 1);
		}
		elsif($type eq "event")
		{
			my $today = UnixDate(ParseDate("today"), "%Y%m%d");
			my $events = getEventList($ldap, { 'from' => $today }, $ou);
			my @date_sorted_event_dns = sort { $events->{$b}->{'spb-date'} <=> $events->{$a}->{'spb-date'} } keys %{$events};
			my @eventlist;
			foreach my $dn (@date_sorted_event_dns)
			{
				my $event_details = $events->{$dn};
				my $displayName = $event_details->{'spb-displayName'};
				my $display_date = getRealDate($event_details->{'spb-date'});
				my $encoded_dn = $cgi->escape($dn);
				push(@eventlist, { ENCODED_DN => $encoded_dn, DISPLAY_NAME => $displayName, DISPLAY_DATE => $display_date });
			}
			$content->param(ENTITY_LIST => \@eventlist);
			$title .= " Event";
			$content->param(IS_EVENT => 1);
		}
		else
		{
			die "Don't know how to handle entity type $type";
		}

		$header->param(PAGE_TITLE => $s->{'site_name'}." - $title");
	}
	else
	{
		my ($from, $to) = '';
		my @newdnparts = split(/,/, $entity);	# should give us (cn/uid, people/events, current/deleted, pub, org, uk)
		if($action eq "delete")
		{
			$title .= "Delete";
			$newdnparts[2] = "ou=deleted";
		}
		elsif($action eq "undelete")
		{
			$title .= "Undelete";
			$newdnparts[2] = "ou=current";
		}
		my $newdn = join(',', @newdnparts);
		my $newrdn = $newdnparts[0];				# the RDN is the first bit, uid=gibbsi etc
		my @newsuperiorparts = @newdnparts[1..scalar(@newdnparts)-1];
		my $newsuperior = join(',', @newsuperiorparts);
		logMsg("New DN: $newdn New RDN: $newrdn New superior: $newsuperior");
	
		# found out where the entity is currently and run checks
		my $exists_in_from = entryExists($ldap, $entity);
		my $exists_in_to = entryExists($ldap, $newdn);
		if(not $exists_in_from)
		{
			die "Can't find $entity to $action it";
		}
		if($exists_in_to && $exists_in_from)
		{
			die "Entity exists in both source and destination locations.\nSource: $entity\nDestination: $newdn";
		}
		if($exists_in_to)
		{
			die "Destination $newdn already exists";
		}

		# all is well. Try the move
		$lmsg = $ldap->moddn($entity, newsuperior => $newsuperior, deleteoldrdn => 1, newrdn => $newrdn);
		$lmsg->code && die $lmsg->error;

		# good. Move worked.
		my $cn = '';
		if($newdnparts[1] eq "ou=people")
		{
			my $ed = getEventDetails($ldap, $newdn);
			$cn = $ed->{'cn'};
			logMsg("CN: $cn");
			$content->param(MOVED => $cn, IS_USER => 1);
			$title .= " User";
		}
		elsif($newdnparts[1] eq "ou=events")
		{
			my $md = getMemberDetails($ldap, $newdn);
			$cn = $md->{'cn'};
			logMsg("CN: $cn");
			$content->param(MOVED => $cn, IS_EVENT => 1);
			$title .= " Event";
		}
		else
		{
			die "Don't know how to handle moved entity type $newdnparts[1]";
		}

		if($action eq "delete")
		{
			$content->param(IS_DELETE => 1);
		}
		elsif($action eq "undelete")
		{
			$content->param(IS_UNDELETE => 1);
		}

		$header->param(PAGE_TITLE => $s->{'site_name'}." - $title");
	}

	$lmsg = $ldap->disconnect;
}

$header->param(IS_IE6 => 1) if(&isIE6);

print header;
print $header->output;
print $content->output;
print $footer->output;