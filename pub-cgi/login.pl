#!/usr/bin/perl -wT

use CGI ':standard';
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use Net::LDAP;
use BandWebsite;
use CGI::Session;
use HTML::Template;
use Net::LDAP::Constant qw(LDAP_PP_CHANGE_AFTER_RESET);

use strict;

my $s = &getSettings;
my $debug = "0";
my $templates = $s->{'template_dir'};
my $cgi = CGI->new;
my $helper = BandWebsite->new({ basedn => $s->{'ldap_base_dn'} });
my $message = $cgi->param('msg'); $message = '' unless defined $message;
my $laction = $cgi->param('laction'); $laction = '' unless defined $laction;
my $message_text = undef;
my $home = $s->{'home'};
my $maxuidlength = $s->{'max_uid_length'};
my $maxpasslength = $s->{'max_pass_length'};
my $minuidlength = $s->{'min_uid_length'};
my $minpasslength = $s->{'min_pass_length'};

my $header = HTML::Template->new(filename => "$templates/header.tmpl");
$header->param(PAGE_TITLE => $s->{'site_name'}." - Login");
$header->param(LINKS => [ {HREF=>"forgotten.pl",TEXT=>"Reset my password"},
							 ]);
my $content = HTML::Template->new(filename => "$templates/login.tmpl");
my $footer = HTML::Template->new(filename => "$templates/footer.tmpl");

# Are we logged in as someone?
my $session = checkUserLoggedIn($cgi);

if($session)
{
	$header->param(CN => $session->{'cn'});
	$header->param(LOGGED_IN => 1);
	$content->param(CN => $session->{'cn'});
	$content->param(UID => $session->{'athenticated_uid'});
	$content->param(LOGGED_IN => 1);
}
else
{
	$header->param(LOGGED_IN => 0);
	$content->param(LOGGED_IN => 0);
	if($laction eq "login")
	{
		my $uid = $cgi->param('uid');
		my $pass = $cgi->param('pass');
		if(length($uid) > $maxuidlength) { $message = 'uidtoolong'; }
		elsif(length($uid) < $minuidlength) { $message = 'uidtooshort'; }
		elsif(length($pass) > $maxpasslength) { $message = 'passtoolong'; }
		elsif(length($pass) < $minpasslength) { $message = 'passtooshort'; }
		#if($uid =~ /[^a-zA-Z0-9-_@.]/)
	#	if($uid =~ /[:^print:]|[^\^]/)
		#{ 
		#		if(length($&) > 0)	# for some reason, % signs don't get picked out by the back reference. 
		#		{
		#			redirectToLoginPage({msg => 'invaliduidchar', invalidchar => entitify($&)});
		#		}
		#		else
		#		{
		#			redirectToLoginPage({msg => 'invaliduidchar'});
		#		}
		#		exit;
		#}
		else
		{
			my $ldap = Net::LDAP->new($s->{'ldap_server'}.":".$s->{'ldap_port'}) or die "Couldn't connect to LDAP: $!";
			my $mesg = $ldap->bind( $s->{'ldap_bind_dn'}, password => $s->{'ldap_bind_pw'}) or die "Couldn't bind to LDAP: $!";
			my ($result, $control, $cookie) = attemptLogin($ldap, $uid, $pass);
			if($result)
			{
				logMsg("Control: $control");
				if($control == 2)
				{
					print redirect(-uri => "${home}/cgi-bin/updatepwd.pl", -cookie => $cookie);
				}
				else # successful login and no reset required
				{
					my $source = $cgi->param('source'); $source = '' unless defined $source;
					my $new_url = $home;
					if($source)				# if we were redirected here from a log-in required page, go back there		
					{
						$new_url .= $cgi->unescape($source)."?";
						my %params = $cgi->Vars;		# Include all the params in the page so we don't lose them
						my @sanitised_params;			# The list of params that aren't to do with this form
						foreach my $param (keys %params)
						{
							my $skip = 0;
							foreach my $excluded (("source", "laction", "uid", "pass"))
							{
								$skip = 1 if($param eq $excluded);
							}
#							logMsg("Adding param $param with value ".$params{$param}) if not $skip;
							$new_url .= "&$param=".$params{$param} if not $skip;
						}
					}
					print redirect(-uri => $new_url, -cookie => $cookie);
				}
			}
			else
			{
		#		print STDERR "Login unsuccessful for $uid; error $extra returned";
				$message = "wronguserpass";
			}
			$mesg = $ldap->disconnect;
		}
	}
	if($message eq "loginreq") { $message_text = "You must log in before you can access this page"; }
	if($message eq "uidtoolong") { $message_text = "The username or email address you provided was too long. Your username or email address is less than $maxuidlength characters long."; }
	if($message eq "uidtooshort") { $message_text = "The username or email address you provided was too short. Your username or email address is at least $minuidlength characters long."; }
	if($message eq "passtoolong") { $message_text = "The password you provided was too long. Your password is less than $maxpasslength characters long."; }
	if($message eq "passtooshort") { $message_text = "The password you provided was too short. Your password is at least $minpasslength characters long."; }
	if($message eq "invaliduidchar")
	{ 
		if($cgi->param('invalidchar'))
		{
			$message_text = "The username or email address you provided contained the invalid character <font color='black'>".$cgi->param('invalidchar')."</font>";
		}
		else
		{
			$message_text = "The username or email address you provided contained one of the invalid characters <font color='black'>&, *</font>";
		}
	}
	if($message eq "wronguserpass") { $message_text = "The credentials you provided were incorrect."; }
	$content->param(MSG => $message_text);

	my %params = $cgi->Vars;		# Include all the params in the page so we don't lose them
	my @sanitised_params;			# The list of params that aren't to do with this form
	foreach my $param (keys %params)
	{
		my $skip = 0;
		foreach my $excluded (("msg", "laction", "uid", "pass"))
		{
			$skip = 1 if($param eq $excluded);
		}
		push(@sanitised_params, { NAME => $param, VALUE => $params{$param} }) if not $skip;
	}
	$content->param(EXTRA_PARAMS => \@sanitised_params);

	$content->param(MAX_UID_LENGTH => $maxuidlength);
	$content->param(MAX_PASS_LENGTH => $maxpasslength);
}

$header->param(IS_IE6 => 1) if(&isIE6);

print header;
print $header->output;
print $content->output;
print $footer->output;

sub entitify
{
	my $char = $_[0];

#	print STDERR "'$char'";
	if(length($char) != 1) { die "Entitfy must be passed one character only"; }
	if($char eq "&") { return "&amp;"; }
	else { return $char; }
}