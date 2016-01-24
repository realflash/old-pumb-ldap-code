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
my $content = HTML::Template->new(filename => "$templates/list_members.tmpl", global_vars => 1);
my $footer = HTML::Template->new(filename => "$templates/footer.tmpl");

# Are we logged in as someone?
my $session = checkUserLoggedIn($cgi);

if($session)
{
	$header->param(CN => $session->{'cn'});
	$header->param(LOGGED_IN => 1);
	my @links = ({HREF=>"list_members.pl",TEXT=>"Show all members"}, {HREF=>"report_membership.pl",TEXT=>"Contact Sheet"});
	if($session->{'groups'}->{'Membership Admins'})
	{
		# TODO: Don't show performer details to non-performers
		#logMsg("User ".$session->{'cn'}." is an Event Admin");
		push(@links, {HREF=>"member.pl?action=add",TEXT=>"Add member"}, 
				{HREF=>"delete.pl?type=member", TEXT=>"Delete member"},
				{HREF=>"delete.pl?type=member&action=undelete", TEXT=>"Undelete member"});
		$content->param(IS_MEMBERSHIP_ADMIN => 1);
	}
	$header->param(LINKS => \@links);
}
else
{
	print redirect(buildLoginPageURL($cgi));		# bounce the user to the login page, adding the source so that 
								# they can be brought back once they are authenticated
}

# set the title
#if($showOnlyType eq "PERFORMANCE") { $title = "List of all performances" }
#elsif($showOnlyType eq "SOCIAL") { $title = "List of all social events" }
#elsif($showOnlyType eq "REHEARSAL") { $title = "List of all rehearsals" }
#else { $title = "List of all events" }
$title = "List of all members";
$content->param(TITLE => $title);
$header->param(PAGE_TITLE => $s->{'site_name'}." - $title");

# must be authenticated if we are still executing. Carry on!
# Set up an LDAP connection
my $ldap = Net::LDAP->new($s->{'ldap_server'}.":".$s->{'ldap_port'}) or die "Couldn't connect to LDAP: $!";
my $lmsg = $ldap->bind( $s->{'ldap_bind_dn'}, password => $s->{'ldap_bind_pw'}) or die "Couldn't bind to LDAP: $!";

my $zebra = 1;
my $colour_number = $zebra;
my $users = getUserList($ldap);
my @firstName_sorted_user_cns = sort { $users->{$a} cmp $users->{$b} } keys %{$users};
my $balances = getUserSubBalance($ldap);
my @user_list;
foreach my $cn (@firstName_sorted_user_cns)
{
	my $dn = $users->{$cn};
	my $subBalance = $balances->{$dn};
	my $encoded_dn = $cgi->escape($dn);
	my $highlight = 0;

	#next if($showOnlyType && $showOnlyType ne $eventType);		# if we have told to show only a certain type of event, and this 
																# event doesn't match that type, skip to the next one

	if($subBalance < 0)
	{ 
		$highlight = 1;		# the event is today. Highlight it in yellow
	}
	$colour_number = $zebra;	# otherwise stick to the standard to greys

	push(@user_list, { COLOUR_NUMBER => $colour_number, ENCODED_DN => $encoded_dn, HIGHLIGHT => $highlight, DISPLAY_NAME => $cn,
						SUB_BALANCE => $subBalance });

	if($zebra eq 1)
	{
		$zebra = 2;
	}
	else
	{
		$zebra = 1;
	}
}
$content->param(USERS => \@user_list);
$lmsg = $ldap->disconnect;

$header->param(IS_IE6 => 1) if(&isIE6);

print header;
print $header->output;
print $content->output;
print $footer->output;