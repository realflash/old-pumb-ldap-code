#!/usr/bin/perl -wT

use CGI ':standard';
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use Math::Round;
use BandWebsite;
use CGI::Session;
use HTML::Template;
use File::Basename;
use File::stat;
use DateTime;

use strict;

my $s = &getSettings;
my $debug = "0";
my $templates = $s->{'template_dir'};
my $files_dir = $s->{'files_dir'};
my $cgi = CGI->new;
my $helper = BandWebsite->new({ basedn => $s->{'ldap_base_dn'} });

my $title = "File download";

my $fn = $cgi->unescape($cgi->param('fn')); $fn = "" unless defined $fn;

my $header = HTML::Template->new(filename => "$templates/header.tmpl");
my $content = HTML::Template->new(filename => "$templates/download.tmpl", global_vars => 1);
my $footer = HTML::Template->new(filename => "$templates/footer.tmpl");

# Are we logged in as someone?
my $session = checkUserLoggedIn($cgi);

if($session)
{
	$header->param(CN => $session->{'cn'});
	$header->param(LOGGED_IN => 1);
	my @links = ({HREF=>"download.pl?type=recordings",TEXT=>"Recordings"});
	$header->param(LINKS => \@links);
}
else
{
	print redirect(buildLoginPageURL($cgi));		# bounce the user to the login page, adding the source so that 
								# they can be brought back once they are authenticated
}

$content->param(TITLE => $title);
$header->param(PAGE_TITLE => $s->{'site_name'}." - $title");
$header->param(IS_IE6 => 1) if(&isIE6);

if(!$fn)
{
    my @out_files;	# the ordered list passed to the display template
    my $dir = "$files_dir/recordings"; $dir = "" if not $dir;
    my @fl = <$dir/*>;	# the list from the filesystem
    my @unsorted_files; # the list from the filesystem plus their attributes
    if(scalar(@fl))
    {
	foreach my $file (@fl)
	{
	    my $size_bytes = stat($file)->size;
	    my $size_mb = nearest(0.1, $size_bytes/(1024*1024));
	    my $mtime = stat($file)->mtime;
	    my $mtime_p = DateTime->from_epoch(epoch => $mtime);
	    $mtime_p->set_time_zone("local");
	    my $mtime_d = $mtime_p->strftime("%d/%m/%y");
	    my $shortname = fileparse($file);
	    my $enc_file = $cgi->escape($file);
	    push @unsorted_files, ({enc_file=>$enc_file, shortname=>$shortname, size_mb=>$size_mb, 
			      mtime=>$mtime_d, mtime_epoch=>$mtime});
	}

	my @sorted_files = reverse sort { $a->{'mtime_epoch'} <=> $b->{'mtime_epoch'} } @unsorted_files;

	my $zebra = 1;
	foreach my $file (@sorted_files)
	{
	    push @out_files, ({ENCODED_FN=>$file->{'enc_file'}, DISP_FN=>$file->{'shortname'}, SIZE=>$file->{'size_mb'}, 
			      MTIME=>$file->{'mtime'}, COLOUR_NUMBER=>$zebra});
	    if($zebra eq 1)
	    {
		    $zebra = 2;
	    }
	    else
	    {
		    $zebra = 1;
	    }
	}

	$content->param(FILES => \@out_files);
    }
    else
    {
	$content->param(NO_FILES => 1);
    }
    # Print normal HTML page header as this is a file listing
    print header;
    print $header->output;
    print $content->output;
    print $footer->output;
}
else
{
#    logMsg("Returning file $fn");
    my($filename, $directories, $suffix) = fileparse($fn);
    if($fn =~ /^$files_dir/)
    {
	my $size_bytes = stat($fn)->size;
  
	print "Content-Type:application/x-download\n";
	print "Content-Length: $size_bytes\n";
	print "Content-Disposition:attachment;filename=$filename\n\n";
	open my $fh , '<', $fn; 
	print $_ while ( sysread $fh, $_ , 8192 ); 
	close $fh; 
    }
    else
    {
	$content->param(NO_FILES => 1);
	print header;
	print $header->output;
	print $content->output;
	print $footer->output;
    }
}