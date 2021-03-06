package BandWebsite;

use strict;
require Net::LDAP;
require Exporter;
use vars qw($VERSION @ISA @EXPORT);
use Date::Manip;
use CGI::Cookie;
use CGI ':standard';
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use Scalar::Util qw(looks_like_number);
use CGI::Session;
use Storable;
use File::Spec::Functions;
use Net::LDAP::Constant qw(LDAP_CONTROL_PASSWORDPOLICY);
use Net::LDAP::Control::PasswordPolicy;
use Authen::Captcha;

@ISA = qw(Exporter);
@EXPORT = qw(getMemberDetails getEventList trim ltrim rtrim getUserList getMonthNumber loadInclude printInclude getEventDetails getAge 
		getRealDate getRealTime getLdapDate getEventAttendees getEventIntendedAttendees getEventIntendedAbsentees 
		getEventIntentions getEventPayers getUserUidList getPerformerList capitalise sanitiseString checkCookieForUser 
		setCookieForUser generate_random_string generate_names entryExists attributeExists capitaliseFirstLetter
		getAttributeDisplayName attributeOptional getOptionalAttributes getViewMemberHTML setUserSubBalance getUserSubBalance
		getTimeDelta chargeSubs wasUserMember markAllEventsPaid getValueDisplayName isIE6 getBrowser checkUserLoggedIn
		verifyLoginUid attemptLogin buildLoginPageURL generateAnchorName getUserDN getLastAttendedEvent getSettings logMsg
		getCaptcha checkCaptcha);
$VERSION = '0.03';

require Net::LDAP;

my $ldap_base_dn;
my @optional_atts= qw(spb-boroughLocation spb-requesterBoroughLocation spb-requesterOrgName spb-requesterWebsite spb-requesterFreeText homePhone mobile description spb-websiteAnchorName spb-employerName);
my $admin_email = "webmaster\@policeunityband.org.uk";
my $settingsfile = "/usr/lib/cgi-bin/pub.settings";
my $logmessageprefix = "PUB";

sub new {
	my $package = shift;
	my $conn_details = shift;
	$ldap_base_dn = $conn_details->{'basedn'};

	return bless({}, $package);
}

sub getCaptcha
{
	my $s = &getSettings;
	my $captcha_db = $s->{'captcha_db_dir'};
	my $captcha_images = $s->{'captcha_image_dir'};
	my $captcha = Authen::Captcha->new(
	    data_folder => $captcha_db,
	    output_folder => $captcha_images,
	    );
	my $md5sum = $captcha->generate_code(5);
	# Now we have $captcha_images/$md5sum.png on the filesystem
	return $md5sum, "/images/captcha/$md5sum.png";
}

sub checkCaptcha
{
	my $captcha_code = shift;
	my $captcha_sum = shift;

	my $s = &getSettings;
	my $captcha_db = $s->{'captcha_db_dir'};
	my $captcha_images = $s->{'captcha_image_dir'};
	my $captcha = Authen::Captcha->new(
	    data_folder => $captcha_db,
	    output_folder => $captcha_images,
	    );
	my $valid = $captcha->check_code($captcha_code, $captcha_sum);
	# Now we have $captcha_images/$md5sum.png on the filesystem
	return $valid;
}

sub isIE6
{
	return 1 if &getBrowser eq "IE6";
}

sub getBrowser
{
	my $browser = "";
	my $ua_string = $ENV{'HTTP_USER_AGENT'};
	if($ua_string =~ /MSIE 6/)
	{
			$browser = "IE6";
	}
}

sub logMsg
{
	my $msg = $_[0];
	my ($source, $scriptpath) = caller;
	my ($volume, $directories, $filename) = File::Spec->splitpath($scriptpath);

	my $now = UnixDate("now", "[%a %b %d %T %Y]");
	
	print STDERR "$now [$logmessageprefix] {$filename,$source} $msg\n";
}

# Return the settings - LDAP, template dirs, etc.
sub getSettings
{
	return retrieve $settingsfile;
}

# Return the ldap date and DN of the last event attended, checking only the last six months
sub getLastAttendedEvent
{
	my $ldap = $_[0];
	my $member = $_[1];
	
	my $today = ParseDate("today");											# Get today's date
	my $today_ldap_format = UnixDate($today, "%Y%m%d");						# Put it in my LDAP format
	my $sixmonth_date = UnixDate(DateCalc($today, ParseDateDelta("6 months ago")), "%Y%m%d");	# Get the date six months ago
	my $join_date = getMemberDetails($ldap, $member)->{'na-joinDate'};		# Find out when the user joined
	my $eventList;
	my $recent_joiner = 0;											# A hash ref of relevant events 
	if($join_date >= $sixmonth_date) { $eventList = getEventList($ldap, {'from' => $join_date, 'to' => $today_ldap_format}); $recent_joiner = 1; }	# The user joined less than six months ago
	else { $eventList = getEventList($ldap, {'from' => $sixmonth_date, 'to' => $today_ldap_format}); }				# The user joined more than six months ago
	my @date_sorted_event_dns = sort { $eventList->{$b}->{'spb-date'} <=> $eventList->{$a}->{'spb-date'} } keys %{$eventList};	# Sort the list of events by date
	foreach my $event (@date_sorted_event_dns)
	{
 		if(grep /$member/, @{getEventAttendees($ldap, $event)})
		{
			return $event;	# got a match, end the foreach early and return the details
		}
	}
	
	# If we got here we didn't get a match. The user hasn't been in more than six months, 
	return 0;
}

# Create an anchor name from the CN to use for unqiue URL for the event - pulic events only as they are listed. No uniqueness checking !!!
sub generateAnchorName
{
	my $cn = $_[0];		# First param is the CN the event will be created with 
	my $an = lc($cn);	# lower case
	$an =~ s/\s//g;		# no spaces
	#print STDERR $an;
	return $an;		# return
}

# Redirect the user to the login page
sub buildLoginPageURL
{
	my $cgi = $_[0];		# The $cgi object

	my $url = "login.pl?";		# The name of the login page

	my $source = $cgi->url(-absolute=>1); 	# the relative URL we were called from
	my %params = $cgi->Vars;		# the params we had, as a hash
	$params{'msg'} = 'loginreq';	# add a param to tell login.pl that the user needs to authenticate
	$params{'source'} = $cgi->escape($source); # add a param to tell login.pl where the user was before
	foreach my $param (keys %params)
	{
#		print STDERR "adding param $param with value ".$params{$param};
		$url .= "&".$param."=".$params{$param};
	}
#	print STDERR $url;
	return($url);
}

# Has the user previously logged in? 0 for no, userid for yes
sub checkUserLoggedIn
{
	my $cgi = $_[0];	# First param is the $cgi object passed in by the referring script. Keep these params so we can determine where to send the user next

	# Are we logged in as someone? If not, show the login page
	my $session = new CGI::Session() or die CGI::Session->errstr;
	my $uid = $session->param('authenticated_uid');
	if(!$uid)
	{
		return undef;
	}
	else
	{
		#print STDERR "Auth'd as: ".$session->param('authenticated_uid');
		return $session->param_hashref;
	}
}

# Take a string that was provided by the user as an identifier and check it relates to a known individual. If it does,
# return a DN and a uid for that individual.
sub verifyLoginUid
{
	my $ldap=$_[0];
	my $login_uid = $_[1];

	my $confirmed_UID = undef;

	my $userDNs = getUserUidList($ldap);			# TODO: search for a single user, not all of them
	my $confirmed_DN = $userDNs->{$login_uid};		# Assume it was a userID
	if(not $confirmed_DN)				# Otherwise look for an email address
	{
#		print STDERR "No DN found for uid $login_uid; searching email addresses";
		my $result = $ldap->search(base => "ou=People,ou=Current,".$ldap_base_dn, 
					filter => "(&(objectClass=spbPerson)(mail=$login_uid))", 
					attrs => ['uid']);
#		print STDERR $result->count." entries with that email address found";
		if($result->count < 1)
		{
			print STDERR "No DN found for mail $login_uid";
			return (undef, undef, "wronguserpass");
		}
		elsif($result->count > 1)
		{
			print STDERR "WARN: Multiple uids found for mail $login_uid";
			$confirmed_DN = $result->entry(0)->dn;
			$confirmed_UID = $result->entry(0)->get_value('uid');
			return($confirmed_DN, $confirmed_UID, "multipleuids");
		}
		else
		{
			$confirmed_DN = $result->entry(0)->dn;
			$confirmed_UID = $result->entry(0)->get_value('uid');
#			print STDERR "Found DN $confirmed_DN for mail $login_uid" if $confirmed_DN;
		}
	}
	else
	{
		$confirmed_UID = $login_uid;	# There is a user with the uid that was provided. 
	}
	return($confirmed_DN, $confirmed_UID, undef);
}

sub attemptLogin
{
	my $ldap = $_[0];
	my $username = $_[1];
	my $password = $_[2];
	
	my ($confirmed_DN, $confirmed_UID, $err) = verifyLoginUid($ldap, $username);
	if(not $confirmed_DN)
	{
		return (0, $err);
	}

	my $session = new CGI::Session() or die CGI::Session->errstr;
	
	my $ldap2 = Net::LDAP->new($ldap->uri, onerror => sub { &checkLoginError });	# establish a second connection to the same server as the first
	my $pp = Net::LDAP::Control::PasswordPolicy->new;
	my $loginResult = $ldap2->bind($confirmed_DN, password => $password, control => [ $pp ] );		# if the bind fails, this calls
																				# checkLoginError, which will just return the error

	my $ldapErrorNumber = $loginResult->{'resultCode'};
	my ($control) = $loginResult->control(LDAP_CONTROL_PASSWORDPOLICY);
	my $pwd_cntrl_code = $control->pp_error; 
	$pwd_cntrl_code = 0 if not defined $pwd_cntrl_code;
	if($ldapErrorNumber == 49)
	{
		# incorrect user or pass
#		print STDERR "LDAP error 49 using DN $confirmed_DN from username $username with password $password";
		return (0, $pwd_cntrl_code);
	}
	elsif(!$ldapErrorNumber)
	{	
		$ldap2->disconnect;
		# So the bind as the confirmed_DN with the password was successful. But does the password require resetting?
		my $cookie = new CGI::Cookie(-name => $session->name,
				-expires =>  '+1h',
				-secure  =>  0,
				-value => $session->id );
		# Get some stuff out of LDAP about the user that we're likely to need later, such as groups they are a member of, and store it in the
		# session object. That saves us doing unnecessary LDAP searches.
		my $mesg = $ldap->search(base => "ou=Groups,ou=Current,".$ldap_base_dn, filter => "(&(objectClass=groupOfUniqueNames)(uniqueMember=".$confirmed_DN."))", attrs => ['cn']);
		my %groups;
		foreach my $entry ($mesg->entries)
		{
			my $cn= trim($entry->get_value('cn'));
			$groups{$cn} = 1;
		}
		my $member_details = getMemberDetails($ldap, $confirmed_UID);
		$session->param('cn', $member_details->{'cn'});
		$session->param('groups', \%groups);
		$session->param('authenticated_uid', $confirmed_UID);
		$session->param('authenticated_dn', $confirmed_DN);
		return (1, $pwd_cntrl_code, $cookie);
	}
	else
	{
		# other LDAP error
		die "LDAP error $ldapErrorNumber while logging in as $username (DN: $confirmed_DN). Please send this error to $admin_email";
	}
}

sub checkLoginError
{
	return $_[0];
}

# The user has caught up. Mark all events as paid
sub markAllEventsPaid
{
	my $ldap = $_[0];
	my $member = $_[1];

	my $member_details = getMemberDetails($ldap, $member);
	my $event_list = getEventList($ldap, {'from' => $member_details->{'na-joinDate'}, 'to' => UnixDate(ParseDate("today"), "%Y%m%d")});
	foreach my $event(keys %$event_list)
	{
		my $payers = getEventPayers($ldap, $event);
		if(not grep /$member/, @$payers)
		{
			my $mesg = $ldap->modify($event, add => ['spb-uniqueSubPayer' => $member]);
			$mesg->code && die $mesg->error;		# check there wasn't an error
		}
	}
}

# Check if it is time for subs to be charged to the user's balances, and if so, charge it
sub chargeSubs
{
	my $ldap = $_[0];
	my $event = $_[1];

	my $event_details = getEventDetails($ldap, $event);
	# Has the event already been charged? If so, won't do it again
	if($event_details->{'spb-subCharged'} eq "TRUE")
	{
		return "ALREADY";
	}
	else
	{
		# Hasn't been charged yet
		my $time_str = getTimeDelta($event_details->{'spb-date'});
		if($time_str =~ /ago/i || $time_str =~ /today/i)
		{
			# It is today or in the past. Charge it to all users who were members on or before this date
			my $users = getUserList($ldap);			# a hash ref of cns to DNs
			my $balances = getUserSubBalance($ldap);	# a hash ref of DNs to balances
			foreach my $cn (sort keys %$users)		# for each user
			{
				my $dn = $users->{$cn};			# get their DN
				if(wasUserMember($ldap, $dn, $event_details->{'spb-date'}))	# if they were a member at the time
				{								# reduce their balance by the correct amount
					setUserSubBalance($ldap, $dn, $balances->{$dn} - $event_details->{'spb-subPrice'});
				}
			}
			my $mesg = $ldap->modify($event, replace => ['spb-subCharged' => 'TRUE']);	# set the flag to say the members have been charged
			$mesg->code && die $mesg->error;		# check there wasn't an error
			return "CHARGED";
		}
		else
		{
			return "FUTURE";
		}
	}
}

# Was the user a member on the provided date? 0 for no, 1 for yes
sub wasUserMember
{
	my $ldap = $_[0];
	my $user_dn = $_[1];
	my $date = $_[2];

	my $mesg = $ldap->search(base => $user_dn, filter => "objectClass=*", attrs => ['createTimestamp']); # get the hidden details
	$mesg->code && die $mesg->error;												# check there wasn't an error
	my $join_date = substr($mesg->entry(0)->get_value('createTimestamp'), 0, 8);	# don't need the time, just get the YYYYMMDD
	my $delta = DateCalc(ParseDate($join_date),ParseDate($date),1);
	if($delta =~ /^\+/)
	{
		return 1;
	}
	else
	{
		return 0;
	}	
}

sub setUserSubBalance 
{
	my $ldap = $_[0];
	my $user = $_[1];
	my $amount = $_[2];

	# Retrieve the current balance
	#my $mesg = $ldap->search( base => $user, filter => "(&(objectClass=*))", scope => 'base', attrs => ['spb-subBalance']);	
	#$mesg->code && die $mesg->error;		# check there wasn't an error
	#my $subBalance = $mesg->entry(0)->get_value('spb-subBalance');
	#my $alteredSubBalance = $subBalance + $amount;
	my $mesg = $ldap->modify($user, replace => [ 'spb-subBalance' => $amount ]); 
	$mesg->code && die $mesg->error;		# check there wasn't an error
	return 0;					# unix style no error
}

sub getUserSubBalance
{
	my $ldap = $_[0];
	my $user = $_[1];
	my %balances;

	# Retrieve the current balance
	if($user)
	{
		# get the balance for a specific user
		my $mesg = $ldap->search(base => $user, filter => "(&(objectClass=*))", scope => 'base', attrs => ['spb-subBalance']);	
		$mesg->code && die $mesg->error;		# check there wasn't an error
		return $mesg->entry(0)->get_value('spb-subBalance');
	}
	else
	{
		# get the balances for all the users
		my $mesg = $ldap->search(base => "ou=People,ou=Current,".$ldap_base_dn, filter => "objectClass=spbPerson", attrs => ['spb-subBalance']);	
		$mesg->code && die $mesg->error;	# check there wasn't an error
		foreach my $entry ($mesg->entries)
		{
			my $dn = trim($entry->dn);
			my $balance = trim($entry->get_value('spb-subBalance'));
			$balances{$dn} = $balance;
		}
		return \%balances;
	}
}

# sub getViewMemberHTML
# {
# 	my $member = $_[0];
# 	my $member_details = $_[1];
# 	my $cgi = CGI->new();
# 	my $result = "";	
# 	
# 	$result .= "
# 						<a href='member.pl?action=edit&member=".$cgi->escape($member)."'><img src=/images/edit.gif border=0 title='Edit this user'/></a> <a href='member.pl?action=edit&member=".$cgi->escape($member)."'>Edit this user</a><br/><br/>
# 						<table border=0 cellpadding=3>
# 							<th colspan=3>Vital statistics</th>
# 							<tr><td align=right>".getAttributeDisplayName('cn').":</td><td>$member_details->{'personalTitle'} $member_details->{'cn'}</td>
# 								<td rowspan='5'><a href='/images/members/$member_details->{'uid'}.jpg' title='View image of $member_details->{'cn'} full size'><img width='150' src='/images/members/$member_details->{'uid'}.jpg'/></a></td></tr>
# 							<tr><td align=right>".getAttributeDisplayName('givenName').":</td><td>$member_details->{'givenName'}</td></tr>
# 							<tr><td align=right>".getAttributeDisplayName('sn').":</td><td>$member_details->{'sn'}</td></tr>
# 							<tr><td align=right valign='top'>".getAttributeDisplayName('spb-dateOfBirth').":</td><td valign='top'>".getRealDate($member_details->{'spb-dateOfBirth'})."<br/>(Age: ".getAge($member_details->{'spb-dateOfBirth'}).")</td></tr>
# 							<tr><td align=right>".getAttributeDisplayName('spb-gender').":</td><td>".capitaliseFirstLetter(lc($member_details->{'spb-gender'}))."</td></tr>
# 							<th colspan=3>Band statistics</th>
# 							<tr><td align=right>".getAttributeDisplayName('na-joinDate').":</td><td>".getRealDate($member_details->{'na-joinDate'})." (".getTimeDelta($member_details->{'na-joinDate'}).")</td></tr>
# 							<tr><td align=right>".getAttributeDisplayName('spb-subBalance').":</td><td";
# 	if($member_details->{'spb-subBalance'} > 0) { $result .= " class='memberlist3'"; } elsif($member_details->{'spb-subBalance'} < 0) { $result.= " class='memberlist4'"; }
# 	$result .= ">&pound;".$member_details->{'spb-subBalance'}."</td></tr>
# 							<th colspan=3>Contact details</th>
# 							<tr><td align=right valign=top>Address:</td><td colspan='2'>$member_details->{'spb-houseIdentifierLocation'}"; 
# 	if(looks_like_number($member_details->{'spb-houseIdentifierLocation'}))
# 	{
# 		$result .= " ";
# 	}
# 	else
# 	{
# 		$result .= "<br/>\n";
# 	}
# 	$result .= "							$member_details->{'spb-streetLocation'}<br/>
# 							$member_details->{'spb-boroughLocation'}<br/>
# 							$member_details->{'spb-townLocation'}<br/>
# 							$member_details->{'spb-countyLocation'}<br/>
# 							$member_details->{'spb-postcodeLocation'}<br/></td></tr>
# 							<tr><td align=right>".getAttributeDisplayName('homePhone').":</td><td valign='top' colspan='2'>$member_details->{'homePhone'}</td></tr>
# 							<tr><td align=right>".getAttributeDisplayName('mobile').":</td><td valign='top' colspan='2'>$member_details->{'mobile'}</td></tr>
# 							<tr><th colspan='3'>Other life details</th></tr>
# 							<tr><td align='right'>".getAttributeDisplayName('spb-employerName').":</td>
# 							<td>$member_details->{'spb-employerName'}</td>
# 							</tr>
# 							<tr>
# 								<td align='right'>".getAttributeDisplayName('spb-warrantHolder').":</td>
# 								<td>";
# 	if($member_details->{'spb-warrantHolder'})
# 	{
# 		$result .= "Yes";
# 	}
# 	$result .= "</td>
# 							</tr>
# 							<th colspan=3>Email addresses</th>
# 							<tr><td align=right valign=top>".getAttributeDisplayName('mail')."es:</td><td colspan='2'>";
# 	foreach my $mail (@{$member_details->{'mail'}})
# 	{
# 		$result .= "<a href=\"mailto:$mail\">$mail</a><br/>\n";
# 	}
# 	$result .= "						</td></tr>
# 							<th colspan=3>Band roles</th>
# 							<tr><td align=right valign=top>".getAttributeDisplayName('spb-instrument').":</td><td colspan='2'>$member_details->{'spb-instrument'}</td></tr>
# 							<tr><td align=right valign=top>".getAttributeDisplayName('employeeType').":</td><td colspan='2'>";
# 	foreach my $role (@{$member_details->{'employeeType'}})
# 	{
# 		$result .= "$role<br/>\n";
# 	}
# 	$result .= "							</table>";
# 	return $result;
# ;}

sub getOptionalAttributes
{
	return \@optional_atts;
}

# This function generates random strings of a given length
sub generate_random_string
{
	my $length_of_randomstring=shift;# the length of the random string to generate

	my @chars=('a'..'z','A'..'Z','0'..'9','_');
	my $random_string;
	foreach (1..$length_of_randomstring) 
	{
		# rand @chars will generate a random number between 0 and scalar @chars
		$random_string.=$chars[rand @chars];
	}
	return $random_string;
}

sub generate_names
{
	my $ldap = $_[0];
	my $sn = $_[1];
	my $fn = $_[2];
	
	my $uniquer = 1;	# what to add to a username to try and make it unique
	my $isUnique = 0;	# assume the username we create is not unique

	my $username_sn = lc(substr($sn,0,5));	# take the first five of the surname. If the surname is less than five, we need more than one char from the first name
	my $firstname_chars = 6 - length($username_sn);		# this is the number of chars we need from the first name to make up the six
	my $username_fn = lc(substr($fn,0,$firstname_chars));	# take however many we need of the first name
	my $username = $username_sn.$username_fn;		# should have six chars now, but had better check...
	my $extra_chars = 6 - length($username);		# this is how many chars short of six the username is. Should be 0, but Jet Li would struggle...
	while($extra_chars > 0)
	{
		$username .= "x";				# pad the username with an x
		$extra_chars--;					# reduce the number of chars we still need by one
	}

	my $tryUsername = $username;				# The uid as it is in LDAP

	# before we add the user, check that we didn't already do it. Because this script simply mods the username
	# if it already exists in LDAP, if you hit the refresh button on the add user result page, you could end up
	# adding the same user multiple times accidentally. So we log in a cookie which users were created by us to prevent
	# that happening
	if(checkCookieForUser($username))
	{	
		die "You have already added the user $username in this session. Do not use your browser's refresh button on this page\n\n\t";
	}
	
	# OK so we haven't already added it. But that doesn't mean there isn't already someone else in the diectory with this username.
	while(not $isUnique)
	{
		my $mesg = $ldap->search( base => "ou=People,ou=Current,".$ldap_base_dn, filter => "(&(uid=$tryUsername))");		# look for an existing user with this username
		$mesg->code && die $mesg->error;		# check there wasn't an error
		my $num_results =  $mesg->count;		# how many results were returned?
		if($num_results == 0)				
		{
			$isUnique = 1;				# no existing users. Go with this one
		}
		else
		{
			$uniquer++;				# increment the uniquer string
			$tryUsername = $username.$uniquer;	# append it to the username and try again
		}
	}
	return ($username, $tryUsername);
}

sub checkCookieForUser
{
	my $username = $_[0];
	my %cookies = fetch CGI::Cookie;
	my @users_created;
	if($cookies{'entities-created-this-session'})
	{
		@users_created = split(",", $cookies{'entities-created-this-session'}->value);
		foreach my $user (@users_created)
		{
			if($user eq $username)
			{
				return 1;
			}
		}
	}
	return 0;
}

sub setCookieForUser
{
	my $username = $_[0];
	my %cookies = fetch CGI::Cookie;
	my @users_created = ();
	if($cookies{'entities-created-this-session'})
	{
		my $cookie = $cookies{'entities-created-this-session'}->value; $cookie = '' if not $cookie;
		@users_created = split(",", $cookie); 
	}
	@users_created = () if not @users_created;
	push(@users_created, $username);			# add the one we have just created to this list
	#my @returned = $c->value(['one','two','three']); 	# apparently you can pass an array as the cookie value, and indeed this line works <-
	#my @returned = $c->value(@users_created);		# but this one doesn't - you just get the first value of the array. I can't work out why, 
								# so I turn the array into a CSV before setting it
	my $users_created_string = join(",", @users_created); 
	my $c = new CGI::Cookie(-name    =>  'entities-created-this-session',
				-expires =>  '+1h',
				-secure  =>  0,
				-value => $users_created_string );

	return $c;
}	

sub sanitiseString
{
	my $in = $_[0];
	$in =~ s/'//g;						# Remove any quotes
	$in = uc(substr($in,0,1)).substr($in,1,length($in));	# Capitalise first char
	my $hyphen_pos = index($in, "-");			# Check for hyphenated names
	while($hyphen_pos != -1)
	{
		$in =~ s/-//;					# Remove the first hyphen
		$in = substr($in,0,$hyphen_pos).uc(substr($in,$hyphen_pos,1)).substr($in,$hyphen_pos + 1, length($in) - $hyphen_pos);	# Capitalise the letter after the hyphen
		$hyphen_pos = index($in, "-");			# Check for hyphenated names
	}
	return $in
}

sub getMonthNumber
{
	my $month = $_[0];
	my %months = ('January' => '01', 'February' => '02', 'March' => '03', 'April' => '04', 'May' => '05', 'June' => '06', 'July' => '07',
			'August' => '08', 'September' => '09', 'October' => '10', 'November' => '11', 'December' => '12' );
	return $months{$month};
}

sub getAttributeDisplayName
{
	my $att = $_[0];
	my %atts = ('personalTitle' => 'Title', 'givenName' => 'First name', 'sn' => 'Surname', 'spb-gender' => 'Sex', 
				'spb-houseIdentifierLocation' => 'House number or name', 'spb-streetLocation' => 'Street', 
				'spb-boroughLocation' => 'Locality', 'spb-townLocation' => 'Town', 'spb-countyLocation' => 'County',
				'spb-postcodeLocation' => 'Postcode', 'homePhone' => 'Home telephone number', 'mobile' => 'Mobile telephone number', 
				'mail' => 'Email address',	'cn' => 'Name', 'uid' => 'Username', 'spb-dateOfBirth' => 'Date of birth', 
				'employeeType' => 'Roles', 'spb-eventType' => 'Event type', 'description' => 'Description', 'spb-displayName' => 'Name',
				'spb-date' => 'Date', 'spb-time' => 'Time', 'spb-subPrice' => 'Subs', 'na-joinDate' => 'Member since', 
				'spb-subBalance' => 'Sub balance', 'spb-websiteAnchorName' => 'Public URL', 'spb-instrument' => 'Instrument',
				'spb-employerName' => 'Employer\'s Name', 'spb-warrantHolder' => 'Warrant Holder');
	return $atts{$att};
}


sub getValueDisplayName
{
	my $val = $_[0];
	my %vals = ('SOCIAL' => 'Social', 'REHEARSAL' => 'Rehearsal', 'PERFORMANCE' => 'Performance', 
				'PERFORMER' => 'Performer', 'CHAIRMAN' => 'Chairman', 'SECRETARY' => 'Secretary', 'TREASURER' => 'Treasurer', 
				'LIBRARIAN' => 'Librarian', 'BANDMASTER' => 'Musical Director',
				'CLARINET' => 'Clarinet', 'BASSCLARINET' => 'Bass Clarinet', 'OBOE' => 'Oboe', 'BASSOON' => 'Bassoon', 
				'FLUTE' => 'Flute/Piccolo', 'FRENCHHORN' => 'French Horn', 'CORNET' => 'Cornet/Trumpet', 'ALTOSAX' => 'Alto Saxomophone',
				'TENORSAX' => 'Tenor Saxomophone', 'TROMBONE' => 'Trombone', 'BASSTROMBONE' => 'Bass Trombone', 'EUPHONIUM' => 'Euphonium', 'BASS' => 'Bass/Tuba', 'PERCUSSION' => 'Percussion');
	return $vals{$val};
}

sub attributeOptional
{
	my $att = $_[0];
	return grep /^$att$/, @optional_atts;
}
	
sub getRealDate
{
	my $ldap_date = $_[0];
	return substr($ldap_date,6,2)."/".substr($ldap_date,4,2)."/".substr($ldap_date,0,4)
}

sub getLdapDate
{
	my $real_date = $_[0];
	my @date_parts = split /\//, $real_date;	# 0 is day, 1 is month, 2 is year
	return $date_parts[2].$date_parts[1].$date_parts[0];
	
}

sub getRealTime
{
	return substr($_[0],0,2).":".substr($_[0],2,2);
}

sub getLdapTime
{
	shift;
	return s/://;
}	

# determine the time between now and the date provided in terms of an age. Assumes date
# provided is before today
sub getAge
{
	my $dob = $_[0];
	if($dob =~ /\//) { $dob = getLdapDate($dob); }		# if it is a real date, change it to an LDAP date
	my $age = DateCalc(ParseDate($dob),ParseDate("today"),1); 
	my @age_parts = split /:/, $age;			# gives me years, months, weeks and days.
	$age_parts[0] =~ s/^\+//;				# get rid of the + sign in the years
	$age_parts[2] = 7*$age_parts[2] + $age_parts[3];	# convert the weeks into days and overwrite the weeks
	my ($year_label, $month_label, $day_label) = "";
	if($age_parts[0] == 1) { $year_label = "year"; } else { $year_label = "years"; }
	if($age_parts[1] == 1) { $month_label= "month"; } else { $month_label = "months"; }
	if($age_parts[2] == 1) { $day_label = "day"; } else { $day_label = "days"; }
	return "$age_parts[0] $year_label, $age_parts[1] $month_label, $age_parts[2] $day_label";
}

# determine the time between now and the date provided
sub getTimeDelta
{
	my $date = $_[0];
	my $nolabel = $_[1];
	my $future = 0;
	my $result = "";
	if($date =~ /\//) { $date = getLdapDate($date); }		# if it is a real date, change it to an LDAP date
	my $delta = DateCalc(ParseDate("today"),ParseDate($date),1); 
	my @date_parts = split /:/, $delta;				# gives me years, months, weeks and days.
	if($date_parts[0] =~ /^\+/)					# get rid of the + sign in the years, and note that we found it
	{
		$future = 1;
		$date_parts[0] =~ s/^\+//;
	}
	else
	{	$future = 0;
		$date_parts[0] =~ s/^-//;
	}
	$date_parts[2] = 7*$date_parts[2] + $date_parts[3];	# convert the weeks into days and overwrite the weeks
	my ($year_label, $month_label, $day_label) = "";
	if($date_parts[0] == 1) { $year_label = "year"; } else { $year_label = "years"; }
	if($date_parts[1] == 1) { $month_label= "month"; } else { $month_label = "months"; }
	if($date_parts[2] == 1) { $day_label = "day"; } else { $day_label = "days"; }
	if($date_parts[0] + $date_parts[1] + $date_parts[2] == 0) { return "Today"; }
	if($date_parts[0] > 0) { $result .= "$date_parts[0] $year_label, "; }
	if($date_parts[1] > 0) { $result .= "$date_parts[1] $month_label, "; }
	$result .= "$date_parts[2] $day_label";
	if($future) { $result .= " away"; } else { $result .= " ago"; }
	if($nolabel)
	{
		return \@date_parts;
	}
	else
	{
		return $result;
	}
}

# Get a list of user DNs keyed on CN
sub getUserList
{
	my $ldap = $_[0];
	my $ou = $_[1]; $ou = 'current' if not defined $ou;
	
	my %users;
	
	my $mesg = $ldap->search( base => "ou=people,ou=$ou,".$ldap_base_dn, filter => "(&(objectClass=spbPerson))");	# look for all users
	$mesg->code && die $mesg->error;		# check there wasn't an error
	foreach my $entry ($mesg->entries)
	{
		my $dn = trim($entry->dn);
		my $cn = trim($entry->get_value('cn'));
		$users{$cn} = "$dn";
	}
	
	return \%users;
}

# Returns a hash of all user DNs, keyed on uid
sub getUserUidList
{
	my $ldap = $_[0];

	my %users;
	my $mesg = $ldap->search( base => "ou=people,ou=current,".$ldap_base_dn, filter => "(&(objectClass=spbPerson))");	# look for all users
	$mesg->code && die $mesg->error;		# check there wasn't an error
	foreach my $entry ($mesg->entries)
	{
		my $dn = trim($entry->dn);
		my $uid= trim($entry->get_value('uid'));
		$users{$uid} = "$dn";
	}

	return \%users;
}

# Return a HoH of all performing users, keyed on dn
sub getPerformerList
{
	my $ldap = $_[0];
	
	my %performers;
	
	my $mesg = $ldap->search( base => "ou=people,ou=current,".$ldap_base_dn, filter => "(&(objectClass=spbPerson)(employeeType=PERFORMER))");	# look for all perfoming members
	$mesg->code && die $mesg->error;		# check there wasn't an error
	foreach my $entry ($mesg->entries)
	{
		my $dn = trim($entry->dn);
		my $cn= trim($entry->get_value('cn'));
		my $uid= trim($entry->get_value('uid'));
		my $joinDate = substr($mesg->entry(0)->get_value('createTimestamp'), 0, 8);	# don't need the time, just get the YYYYMMDD
		my $instrument = trim($entry->get_value('spb-instrument'));
		$performers{$dn} = {'cn' => $cn, 'uid' => $uid, 'na-joinDate' => $joinDate, 'spb-instrument' => $instrument};
	}
	
	return \%performers;
}

sub getEventList
{
	my $ldap = $_[0];
	my $date_limits = $_[1];
	my $ou = $_[2]; $ou = 'current' if not defined $ou;

	my $from_date = $date_limits->{'from'};	$from_date = '' if not defined $from_date;	# the earliest (ie furthest in the past) date 
																						# that should be returned
	my $to_date = $date_limits->{'to'};	$to_date = '' if not defined $to_date;	# the latest (ie most recent) date that should be returned
	if($from_date && $to_date && $from_date > $to_date) # assume the user got it wrong and swap them over
	{ 
		$from_date = $date_limits->{'to'}; 
		$to_date = $date_limits->{'from'};
		#logMsg("getEventList: Switching from and to");
	}	
	my $add_to_list = 0;
	my $count = 0;
	my %events;
	#logMsg("getEventList: searching for events from $from_date to $to_date inclusive");
	my $mesg = $ldap->search( base => "ou=events,ou=$ou,".$ldap_base_dn, filter => "(&(objectClass=spbEvent))");	# look for all events
	$mesg->code && die $mesg->error;		# check there wasn't an error
	foreach my $entry ($mesg->entries)
	{
		my $dn = trim($entry->dn);
		my $description = trim($entry->get_value('description'));
		my $displayName= trim($entry->get_value('spb-displayName'));
		my $date = trim($entry->get_value('spb-date'));
		my $eventType= trim($entry->get_value('spb-eventType'));
		my $subPrice= trim($entry->get_value('spb-subPrice'));
		my $cn= trim($entry->get_value('cn'));
		my $time = trim($entry->get_value('spb-time'));
		my $hi = trim($entry->get_value('spb-houseIdentifierLocation'));
		my $street = trim($entry->get_value('spb-streetLocation'));
		my $borough = trim($entry->get_value('spb-boroughLocation'));
		my $town = trim($entry->get_value('spb-townLocation'));
		my $county = trim($entry->get_value('spb-countyLocation'));
		my $postcode = trim($entry->get_value('spb-postcodeLocation'));
		my $anchorName = trim($entry->get_value('spb-websiteAnchorName'));
		my $intendanceRequiredDate = trim($entry->get_value('spb-intendanceRequiredDate'));
		if(!$to_date && !$from_date) { $add_to_list = 1; }
		elsif($from_date && !$to_date && $date >= $from_date) { $add_to_list = 1; }
		elsif($to_date && !$from_date && $date <= $to_date) { $add_to_list = 1; }
		elsif($to_date && $from_date && $date <= $to_date && $date >= $from_date) { $add_to_list = 1; }
		else { $add_to_list = 0; }	
		$events{$dn} = {'description' => $description, 'spb-displayName' => $displayName, 'cn' => $cn, 'spb-time' => $time, 
						'spb-subPrice' => $subPrice, 'spb-date' => $date, 'spb-eventType' => $eventType, 'spb-houseIdentifierLocation' => $hi,
						'spb-streetLocation' => $street, 'spb-boroughLocation' => $borough, 'spb-townLocation' => $town,
						'spb-countyLocation' => $county, 'spb-postcodeLocation' => $postcode, 'spb-websiteAnchorName' => $anchorName,
						'spb-intendanceRequiredDate' => $intendanceRequiredDate} if $add_to_list;
		$count = $count + 1 if $add_to_list;
	}
#	logMsg("getEventList: $count events found");
	return \%events;
}

sub attributeExists
{
	my $ldap = $_[0];
	my $entry_dn = $_[1];
	my $att = $_[2];

#	print STDERR "Searching for att $att in entry $entry_dn\n";
	my $mesg = $ldap->search(base => $entry_dn, filter => "objectClass=*", scope => 'base', attrs => [$att]);
	$mesg->code && die $mesg->error;
	my $values = $mesg->entry(0)->get_value($att); $values = '' if not $values;
#	print STDERR "$values values found";
	return 1 if length($values) > 0;
	return 0;
}

sub entryExists
{
	my $ldap = $_[0];
	my $entry_dn = $_[1];
	my $mesg = $ldap->search(base => $entry_dn, filter => "objectClass=*", scope => 'base');
	if($mesg->code == 0)	# search was successful, 0 or more entries were returned. Use this number as the return code
	{
		return $mesg->count;
	}
	elsif($mesg->code == 32 || $mesg->code == 34)	# if we get a 32 (no such object) or 34 (invalid DN), treat that as no result
	{
		return 0;
	}
	else	# some other LDAP error that shouldn't have happened
	{
		die "Ldap error ".$mesg->code.": ".$mesg->error;
	}
	return 0;	# shouldn't get here
}
	
sub getEventDetails
{
	my $ldap = $_[0];
	my $event_dn = $_[1];
	
	my %event_details;
	my $mesg = $ldap->search( base => $event_dn, filter => "objectClass=*");	# look for the event
	$mesg->code && die $mesg->error;					# check there wasn't an error
	$event_details{'cn'} = $mesg->entry(0)->get_value('cn');
	$event_details{'spb-subPrice'} = $mesg->entry(0)->get_value('spb-subPrice');
	$event_details{'spb-date'} = $mesg->entry(0)->get_value('spb-date');
	$event_details{'spb-time'} = $mesg->entry(0)->get_value('spb-time');
	$event_details{'spb-houseIdentifierLocation'} = $mesg->entry(0)->get_value('spb-houseIdentifierLocation');
	$event_details{'spb-streetLocation'} = $mesg->entry(0)->get_value('spb-streetLocation');
	$event_details{'spb-boroughLocation'} = $mesg->entry(0)->get_value('spb-boroughLocation');
	$event_details{'spb-townLocation'} = $mesg->entry(0)->get_value('spb-townLocation');
	$event_details{'spb-countyLocation'} = $mesg->entry(0)->get_value('spb-countyLocation');
	$event_details{'spb-postcodeLocation'} = $mesg->entry(0)->get_value('spb-postcodeLocation');
	$event_details{'description'} = $mesg->entry(0)->get_value('description');
	$event_details{'spb-displayName'} = $mesg->entry(0)->get_value('spb-displayName');
	$event_details{'spb-eventType'} = $mesg->entry(0)->get_value('spb-eventType');
	$event_details{'spb-subCharged'} = $mesg->entry(0)->get_value('spb-subCharged');
	$event_details{'spb-websiteAnchorName'} = $mesg->entry(0)->get_value('spb-websiteAnchorName');
	$event_details{'spb-intendanceRequiredDate'} = $mesg->entry(0)->get_value('spb-intendanceRequiredDate');
	$event_details{'spb-lastIntendanceReminderDate'} = $mesg->entry(0)->get_value('spb-lastIntendanceReminderDate');
	
	return \%event_details;
}	

sub getMemberDN
{
	my $ldap = $_[0];
	my $hint = $_[1]; $hint = "" if not $hint;	# a clue as to the user we're looking for. Probably uid
	# Maybe the hint is a uid. Let's look	
	my $mesg = $ldap->search(base => "ou=People,ou=Current,".$ldap_base_dn, filter => "(&(objectClass=spbPerson)(uid=$hint))");
	if($mesg->count < 1)
	{
		return 0;
	}
	if($mesg->count > 1)
	{
		die "More than one user with uid $hint\n";
	}
	else
	{
		return $mesg->entry(0)->dn;
	}
}

sub getMemberDetails
{
	my $ldap = $_[0];
	my $member_dn = $_[1]; $member_dn = "" if not $member_dn;
	
	my %member_details;
	if($member_dn =~ /$ldap_base_dn/)
	{
		# we were passed the DN of a user. Fine.
	}
	else
	{
		# we were passed a uid. Look up the DN of that user
		my $temp = getMemberDN($ldap, $member_dn);
		if($temp) { $member_dn = $temp; };	# As long as we successfully get a DN, assign
							# that returned value to member_dn
	}
	#print STDERR "  Getting details for $member_dn in getMemberDetails";
	my $mesg = $ldap->search( base => $member_dn, filter => "objectClass=*");	# get the standard details
	if($mesg->code)
	{
		# Return code from search was non-zero - not successful.
		if($mesg->code == 32)
		{
#			die "No such member '$member_dn' in getMemberDetails()\n".$mesg->error;
			return;
		}
		else
		{
			die "LDAP error ".$mesg->code." searching for $member_dn in getMemberDetails()\n".
			"Error: ".$mesg->error."\n".
			"Error name: ".$mesg->error_name."\n".
			"Error text: ".$mesg->error_text."\n".
		#	"Error desc: ".$mesg->error_desc."\n".
			"Controls: ".$mesg->control;
		}
	}
	if($mesg->count < 1)
	{
		die "Member DN $member_dn found but result count ".$mesg->count;
	}
	$member_details{'cn'} = $mesg->entry(0)->get_value('cn');
	$member_details{'personalTitle'} = $mesg->entry(0)->get_value('personalTitle');
	$member_details{'spb-gender'} = $mesg->entry(0)->get_value('spb-Gender');
	$member_details{'givenName'} = $mesg->entry(0)->get_value('givenName');
	$member_details{'sn'} = $mesg->entry(0)->get_value('sn');
	$member_details{'spb-dateOfBirth'} = $mesg->entry(0)->get_value('spb-dateOfBirth');
	$member_details{'spb-houseIdentifierLocation'} = $mesg->entry(0)->get_value('spb-houseIdentifierLocation');
	$member_details{'spb-streetLocation'} = $mesg->entry(0)->get_value('spb-streetLocation');
	$member_details{'spb-boroughLocation'} = $mesg->entry(0)->get_value('spb-boroughLocation');
	$member_details{'spb-townLocation'} = $mesg->entry(0)->get_value('spb-townLocation');
	$member_details{'spb-countyLocation'} = $mesg->entry(0)->get_value('spb-countyLocation');
	$member_details{'spb-postcodeLocation'} = $mesg->entry(0)->get_value('spb-postcodeLocation');
	$member_details{'homePhone'} = $mesg->entry(0)->get_value('homePhone');
	$member_details{'mobile'} = $mesg->entry(0)->get_value('mobile');
	$member_details{'uid'} = $mesg->entry(0)->get_value('uid');
	$member_details{'spb-subBalance'} = $mesg->entry(0)->get_value('spb-subBalance');
	my @instruments = $mesg->entry(0)->get_value('spb-instrument'); $member_details{'spb-instrument'} = \@instruments;
	$member_details{'spb-employerName'} = $mesg->entry(0)->get_value('spb-employerName');
	$member_details{'spb-warrantHolder'} = $mesg->entry(0)->get_value('spb-warrantHolder');
	$member_details{'spb-latLocation'} = $mesg->entry(0)->get_value('spb-latLocation');
	$member_details{'spb-longLocation'} = $mesg->entry(0)->get_value('spb-longLocation');
	my @mails = $mesg->entry(0)->get_value('mail');
	$member_details{'mail'} = \@mails;
	my @roles= $mesg->entry(0)->get_value('employeeType');
#	my @display_roles = getDisplayRoles(\@roles);
	$member_details{'employeeType'} = \@roles;

#	$mesg = $ldap->search(base => $member_dn, filter => "objectClass=*", attrs => ['createTimestamp']); # get the hidden details
#	$mesg->code && die $mesg->error;								# check there wasn't an error
	$member_details{'na-joinDate'} = substr($mesg->entry(0)->get_value('spb-joinDate'), 0, 8);	# don't need the time, just get the YYYYMMDD
	
	return \%member_details;
}	

# sub getDisplayRoles
# {
# 	my $roles = $_[0];
# 	foreach my $role (@{$roles})
# 	{
# 		if(lc($role) eq "secretary") { $role = "Secretary" }
# 		elsif(lc($role) eq "membershipsecretary") { $role = "Membership Secretary" }
# 		elsif(lc($role) eq "treasurer") { $role = "Treasurer" }
# 		elsif(lc($role) eq "chairman") { $role = "Chairman" }
# 		elsif(lc($role) eq "performer") { $role = "Performer" }
# 		elsif(lc($role) eq "librarian") { $role = "Librarian" }
# 		elsif(lc($role) eq "bandmaster") { $role = "Band Master" }
# 	}
# 	return @{$roles};
# }

sub capitaliseFirstLetter
{
	return uc(substr($_[0],0,1)).substr($_[0],1);
}

# Return an array ref of people who did attend an event
sub getEventAttendees
{
	my $ldap = $_[0];
	my $event_dn = $_[1];
	
	my $mesg = $ldap->search( base => $event_dn, filter => "objectClass=*");	# look for the event
	$mesg->code && die $mesg->error;						# check there wasn't an error
	my @event_attendees = $mesg->entry(0)->get_value('spb-uniqueAttendee');
	
	return \@event_attendees;
}	

# Return an array ref of people who intend to attend an event
sub getEventIntendedAttendees
{
	my $ldap = $_[0];
	my $event_dn = $_[1];
	
	my $mesg = $ldap->search( base => $event_dn, filter => "objectClass=*");	# look for the event
	$mesg->code && die $mesg->error;						# check there wasn't an error
	my @event_intended_attendees = $mesg->entry(0)->get_value('spb-uniqueIntendedAttendee');
	
	return \@event_intended_attendees;
}	

# Return an array ref of people who do not intend to attend an event
sub getEventIntendedAbsentees
{
	my $ldap = $_[0];
	my $event_dn = $_[1];
	
	my $mesg = $ldap->search( base => $event_dn, filter => "objectClass=*");	# look for the event
	$mesg->code && die $mesg->error;						# check there wasn't an error
	my @event_intended_absentees = $mesg->entry(0)->get_value('spb-uniqueIntendedAbsentee');
	
	return \@event_intended_absentees;
}

# Return three array refs of people who do, don't, and don't know
sub getEventIntentions
{
	my $ldap = $_[0];
	my $event_dn = $_[1];

	my $mesg = $ldap->search( base => $event_dn, filter => "objectClass=*");	# look for the event
	$mesg->code && die $mesg->error;						# check there wasn't an error
	my @event_intended_absentees = $mesg->entry(0)->get_value('spb-uniqueIntendedAbsentee');
	my @event_intended_attendees = $mesg->entry(0)->get_value('spb-uniqueIntendedAttendee');
	# Then there's everybody else. Get a list of everybody first
	my $performers = getPerformerList($ldap);
	# Remove from the two lists anyone who doesn't exist anymore
	my (@sanitised_attendees, @sanitised_absentees) = ();
	foreach my $attendee (@event_intended_attendees) { push @sanitised_attendees, $attendee if entryExists($ldap, $attendee);	}
	foreach my $attendee (@event_intended_absentees) { push @sanitised_absentees, $attendee if entryExists($ldap, $attendee);	}
	# Now turn each of the two arrays above into hashes for easy checking
	my (%absenteeHash, %attendeeHash) = ();
	for(@sanitised_absentees) { $absenteeHash{$_} = 1; }
	for(@sanitised_attendees) { $attendeeHash{$_} = 1; }
	# Now push the DN into the unknown array if not in either of the others
	my @event_unknown = ();
	foreach my $performer (keys %$performers)
	{
		print STDERR "Checking intentions for $performer";
		if($attendeeHash{$performer})
		{
			print STDERR "$performer is attendee; ignoring";
		}
		elsif($absenteeHash{$performer})
		{
			print STDERR "$performer is absentee; ignoring";
		}
		else
		{
			print STDERR "${performer}'s intentions are unknown; adding to list";
			push @event_unknown, $performer;
		}
	}
	
	return \@sanitised_attendees, \@sanitised_absentees, \@event_unknown;
}

sub getEventPayers
{
	my $ldap = $_[0];
	my $event_dn = $_[1];
	
	my $mesg = $ldap->search( base => $event_dn, filter => "objectClass=*");	# look for the event
	$mesg->code && die $mesg->error;					# check there wasn't an error
	my @event_payers = $mesg->entry(0)->get_value('spb-uniqueSubPayer');
	
	return \@event_payers;
}	

sub printInclude
{
	open(INFILE, $_[0]) or die "Can't open $_[0] for inclusion: $!\n";
	while(<INFILE>) { print $_ };
	close INFILE;
}

sub loadInclude
{
	my $result;
	open(INFILE, $_[0]) or die "Can't open $_[0] for inclusion: $!\n";
	while(<INFILE>) { $result .= $_ };
	close INFILE;
	return $result;
}

# Perl trim function to remove whitespace from the start and end of the string
sub trim($)
{
	my $string = shift; $string = '' if not defined $string;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}
# Left trim function to remove leading whitespace
sub ltrim($)
{
	my $string = shift; $string = '' if not defined $string;
	$string =~ s/^\s+//;
	return $string;
}
# Right trim function to remove trailing whitespace
sub rtrim($)
{
	my $string = shift; $string = '' if not defined $string;
	$string =~ s/\s+$//;
	return $string;
}

sub hoot {
  my $self = shift;
  return "Don't pollute!" if $self->{'verbose'};
  return;
}

1;
__END__

