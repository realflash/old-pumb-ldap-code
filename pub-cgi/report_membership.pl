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

my $sortby = $cgi->param('sortby'); $sortby = '' unless defined $sortby;
my $title = "";

my $header = HTML::Template->new(filename => "$templates/header.tmpl");
my $content = HTML::Template->new(filename => "$templates/report_members.tmpl", global_vars => 1);
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
		#$content->param(IS_MEMBERSHIP_ADMIN => 1);
	}
	$header->param(LINKS => \@links);
}
else
{
	print redirect(buildLoginPageURL($cgi));		# bounce the user to the login page, adding the source so that 
								# they can be brought back once they are authenticated
}

# set the title
$title = "Member Contact Sheet";
$content->param(TITLE => $title);
$header->param(PAGE_TITLE => $s->{'site_name'}." - $title");

# must be authenticated if we are still executing. Carry on!
# Set up an LDAP connection
my $ldap = Net::LDAP->new($s->{'ldap_server'}.":".$s->{'ldap_port'}) or die "Couldn't connect to LDAP: $!";
my $lmsg = $ldap->bind( $s->{'ldap_bind_dn'}, password => $s->{'ldap_bind_pw'}) or die "Couldn't bind to LDAP: $!";

my $zebra = 1;
my $colour_number = $zebra;
my $uids = getUserUidList($ldap);
my @unsorted_users = ();
foreach my $uid (keys %$uids)
{
	my $dn = $uids->{$uid};
	my $details = getMemberDetails($ldap, $dn);
	$details->{'encoded_dn'} = $cgi->escape($dn);
	$details->{'age'} = getAge($details->{'spb-dateOfBirth'});
 
	# some of the details are multi-value and cannot be used directly. Turn array refs where contents are text to 
	# array refs where contents are hash refs so that they can be read by HTML::Template
	my $instruments = $details->{'spb-instrument'};
	my @html_instruments = ();
	foreach my $instrument (@$instruments)
	{
	    push (@html_instruments, { INSTRUMENT => $instrument });
	}
	$details->{'spb-instrument'} = \@html_instruments;
	my $roles = $details->{'employeeType'};
	my @html_roles = ();
	foreach my $role (@$roles)
	{
	    push (@html_roles, { ROLE => $role });
	}
	$details->{'employeeType'} = \@html_roles;
	my $mails = $details->{'mail'};
	my @html_mails = ();
	foreach my $mail (@$mails)
	{
	    push (@html_mails, { MAIL => $mail });
	}
	$details->{'mail'} = \@html_mails;

	# now we have added and modded stuff for HTMLTEMPLATE, push into the results loop
	push(@unsorted_users, $details);

}	

my @sorted_users = ();
if($sortby eq 'instrument')
{
      @sorted_users = sort { $a->{'spb-instrument'}[0] cmp $b->{'spb-instrument'}[0] } @unsorted_users;
}
else
{
      @sorted_users = sort { $a->{'cn'} cmp $b->{'cn'} } @unsorted_users;
}

foreach my $user (@sorted_users)
{
	$user->{'colour_number'} = $zebra;
	if($zebra eq 1)
	{
		$zebra = 2;
	}
	else
	{
		$zebra = 1;
	}
}

$content->param(USERS => \@sorted_users);
$lmsg = $ldap->disconnect;

$header->param(IS_IE6 => 1) if(&isIE6);

print header;
print $header->output;
print $content->output;
print $footer->output;