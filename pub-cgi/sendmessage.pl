#!/usr/bin/perl -wT

use CGI ':standard';
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use BandWebsite;
use CGI::Session;
use HTML::Template;
use Mail::Sender;

use strict;

my $s = &getSettings;
my $debug = "0";
my $templates = $s->{'template_dir'};
my $cgi = CGI->new;
my $helper = BandWebsite->new({ basedn => $s->{'ldap_base_dn'} });

my %recipients = ( 'BECOMING PERFORMER' => 'secretary@pumb.org.uk, bandmaster@pumb.org.uk',

			'DONATIONS' => 'treasurer@pumb.org.uk',
			'MEDIA ENQUIRY' => 'secretary@pumb.org.uk',
			'WEBSITE' => $s->{'admin_email'},
			'OTHER' => $s->{'admin_email'} );
my $mail_server = $s->{'smtp_host'};
my $default_from = "'".$s->{'short_name'}." Website' <".$s->{'admin_email'}.">";
my $enquiry_type = $cgi->param('type'); $enquiry_type = '' unless defined $enquiry_type;
my $subject = $cgi->param('subject');
my $name = $cgi->param('name');
my $email = $cgi->param('email');
my $phone = $cgi->param('phone');
my $message = $cgi->param('message');
my $uid = $cgi->param('uid');
my $captcha_code = lc($cgi->param('captcha_code')); $captcha_code = '' unless defined $captcha_code;
my $captcha_sum = $cgi->param('captcha_sum'); $captcha_sum = '' unless defined $captcha_sum;

# Are we logged in as someone? If not, show the login page
my $session = checkUserLoggedIn($cgi);

my $header = HTML::Template->new(filename => "$templates/header.tmpl");
$header->param(PAGE_TITLE => $s->{'site_name'}." - About");
$header->param(LINKS => [ {HREF=>"sendmessage.pl",TEXT=>"Email us"},
							{HREF=>"postaladdress.pl",TEXT=>"Postal address"},
							{HREF=>"book.pl",TEXT=>"Book the band"},
							 ]);
my $content = HTML::Template->new(filename => "$templates/sendmessage.tmpl");
my $footer = HTML::Template->new(filename => "$templates/footer.tmpl");

if($session)
{
	$header->param(CN => $session->{'cn'});
	$header->param(LOGGED_IN => 1);
	$content->param(UID => $session->{'authenticated_uid'});
}
else
{
	$header->param(LOGGED_IN => 0);
}

if($enquiry_type)
{
	# Check that the captcha is valid
	my $valid = checkCaptcha($captcha_code, $captcha_sum);
	if($valid < 1)
	{	# they were wrong. Give them another one to try again
		my ($md5sum, $image) = &getCaptcha;		# call our helper function in BandWebsite. Returns the path to the 
									# image and the sum
		$content->param(CAPTCHA_IMG => $image, CAPTCHA_SUM => $md5sum);
		$content->param(CAPTCHA_WRONG => 1);
		logMsg("Failed with error $valid verifying code $captcha_code against image $captcha_sum.png");
	}
	else
	{
		my $body = "Message from: \"$name\"";
		if($email)
		{
			$body .= "\nEmail: $email";
			my $from = "\'$name\' <$email>";
		}
		else
		{
			$body .= "\nEmail: not provided";
		}
		if($phone)
		{
			$body .= "\nPhone: $phone";
		}
		else
		{
			$body .= "\nPhone: not provided";
		}
		$body .= "\n\n$message";
		
		my $mail_subject = "Message from ".$s->{'short_name'}." website";
		$mail_subject .= ": $subject" if $subject;
		
		eval
		{
			my $sender = new Mail::Sender {smtp => $mail_server, on_errors => 'die', from => $default_from };
			if($email)
			{
				$sender->Open({to => $recipients{$enquiry_type}, subject => $mail_subject, replyto => "\'$name\' <$email>" });
			}
			else
			{
				$sender->Open({to => $recipients{$enquiry_type}, subject => $mail_subject, });
			}
			$sender->SendLineEnc($body);
			$sender->Close();
		};
		if ($@)
		{
			die "Failed to send the message: $@\n";
		}
		else
		{
			$content->param(SENT => 1);
		}
	}
}
else
{	# This is a standard GET
	my ($md5sum, $image) = &getCaptcha;		# call our helper function in BandWebsite. Returns the path to the 
								# image and the sum
	$content->param(CAPTCHA_IMG => $image, CAPTCHA_SUM => $md5sum);
}

$header->param(IS_IE6 => 1) if(&isIE6);

print header;
print $header->output;
print $content->output;
print $footer->output;
