#!/usr/bin/perl -wT

use CGI ':standard';
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use Net::LDAP;
use SurreyPoliceBand;
use Date::Manip;
use Scalar::Util qw(looks_like_number);

my $ldap_server = "localhost";
my $ldap_base_dn = "dc=surreypoliceband,dc=org,dc=uk";
my $ldap_bind_dn = "cn=admin,".$ldap_base_dn;
my $ldap_bind_pw = "1amadmin";
my $ldap_port = 389;
my $debug = "0";
my $includes = "/var/www/surreypoliceband/member";
my $member_photo_dir = "/var/www/surreypoliceband/images/members";

my $result;
my $cgi = CGI->new;
my $helper = SurreyPoliceBand->new({ basedn => $ldap_base_dn });
my $sortby = $cgi->param('sortby');
$sortby = 'cn' if not $sortby;				# default to sort by name

# Are we logged in as someone? If not, show the login page
my $session = &checkUserLoggedIn;

my $ldap = Net::LDAP->new($ldap_server.":".$ldap_port) or die "Couldn't connect to LDAP: $!";
my $mesg = $ldap->bind( $ldap_bind_dn, password => $ldap_bind_pw ) or die "Couldn't bind to LDAP: $!";

my $performers = getPerformerList($ldap);
my @sorted_performer_dns;

print header;
printInclude("$includes/header.html");
printInclude("$includes/menubar_report.html");

my $zebra = 1;
print "						<h2>Member Report</h2>\n";
if($sortby eq "cn")
{
	print "						Sort by name | <a href=\"report_members.pl?sortby=instrument\">Sort by instrument</a>\n";
    @sorted_performer_dns = sort { $performers->{$a}->{'cn'} cmp $performers->{$b}->{'cn'} } keys %{$performers};
}
else
{
	print "						<a href=\"report_members.pl?sortby=cn\">Sort by name</a> | Sort by instrument\n\n";
    @sorted_performer_dns = sort { $performers->{$a}->{'spb-instrument'} cmp $performers->{$b}->{'spb-instrument'} } keys %{$performers};
}
print "						<table border='0' cellpadding='2'>\n";
foreach my $dn (@sorted_performer_dns)
{
print STDERR "Printing information for member $dn";
	my $performer_details = {};
	$performer_details = getMemberDetails($ldap, $dn);
	my $cn = $performer_details->{'cn'};
	my $uid = $performer_details->{'uid'};
	my $instrument = $performer_details->{'spb-instrument'};
	my $age = getAge($performer_details->{'spb-dateOfBirth'});
	my $homePhone = $performer_details->{'homePhone'};
	my $mobile = $performer_details->{'mobile'};
	my $houseIdentifierLocation = $performer_details->{'spb-houseIdentifierLocation'};
	my $streetLocation = $performer_details->{'spb-streetLocation'};
	my $boroughLocation = $performer_details->{'spb-boroughLocation'};
	my $townLocation = $performer_details->{'spb-townLocation'};
	my $countyLocation = $performer_details->{'spb-countyLocation'};
	my $postcodeLocation = $performer_details->{'spb-postcodeLocation'};
	my $employee;
	if($performer_details->{'spb-employerName'})
	{
		$employee = $performer_details->{'spb-employerName'};
		$employee .= " (Warranted)" if($performer_details->{'spb-warrantHolder'});
	}
	my $encoded_dn = $cgi->escape($dn);
	my $last_event_attended_dn = getLastAttendedEvent($ldap, $dn);
	print "<tr>
			<td rowspan='1' class='memberlist$zebra'><img src='../../images/members/$uid.jpg' width=100 align='left'/></td>
	                <td colspan='1' align='left' class='memberlist$zebra'><a href=\"member.pl?action=view&member=$encoded_dn\">$cn</a> ($age)<br/>
			Instrument: $instrument<br/>
			Force: $employee<br/>
			Last attended: ";
	if($last_event_attended_dn)
	{
		my $last_event_attended_details = getEventDetails($ldap, $last_event_attended_dn);
		print getTimeDelta($last_event_attended_details->{'spb-date'})." <font size='-2'>(".$last_event_attended_details->{'cn'}.",  ".getRealDate($last_event_attended_details->{'spb-date'}).")</font>";
	}
	else
	{
		print "More than six months ago";
	}
	print "<br/>";
	if($mobile)
	{
		print "Mobile";
		print " / Home" if $homePhone;
		print ":";
		print " $mobile";
		print " / $homePhone" if $homePhone;
		print "<br/>";
	}
	elsif($homePhone)
	{
		print "Home: $homePhone<br/>";
	}
	print "
		Address: $houseIdentifierLocation $streetLocation, $townLocation, $countyLocation $postcodeLocation<br/>
		</td>\n
		</tr>\n";
	if($zebra == 1)
	{
		$zebra = 2;
	}
	else
	{
		$zebra = 1;
	}
}

printInclude("$includes/footer.html");
$mesg = $ldap->unbind;