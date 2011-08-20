#!/usr/bin/perl
## adedToday.pl - looks for torrent files uploaded Today

use strict;
use warnings;

use Cwd;
use LWP::UserAgent;

my %s = (
    home    => Cwd::getcwd,
    verbose => 1, # 0 <= n <= 2

	base_url => [
		'http://thepiratebay.org/top/205', # Top 100 TV shows
		'http://thepiratebay.org/top/201', # Top 100 Movies
	], # will check each of these pages

	known_uploaders => [
    	'eztv',
		'VTV',
	],

    download_torrent => 1, # 1 downloads files from known ul-ers, 2 downloads from anyone
	allow_yesterday  => 0, # matches 'Today' or 'Y-day'

	browser_agent => "Mozilla/5.0 (Windows; U; Windows NT 5.2; en-US; rv:1.9.2) Gecko/20100115 Firefox/3.6",

);

my %torrents;

my $start = localtime;
print "$0 started at " . localtime . "\n" if $s{verbose} ge 1;

## find torrent files on each URL
my $i = 0;
for my $url (@{$s{base_url}}) {
	print "  processing URL [$url]..\n" if $s{verbose} ge 1;

	my ($worker, $response);
	$worker = LWP::UserAgent->new();
    $worker->agent($s{browser_agent}); # liar

	$response = $worker->get($url);
	
	my @content = split("<tr>", $response->content);

	for my $line (@content) { 
    	print "DBGZ" if 0;
		if ($line =~ /href=(.*)\stitle="Download this torrent">/) { 
            $torrents{$i}{url} = $1;
			
			$torrents{$i}{ul_by}   = $1 if $line =~ /ULed\sby\s.*?>(.*?)</;
			$torrents{$i}{ul_time} = $1 if $line =~ /Uploaded\s(.*?), Size\s(.*?),/;
			$torrents{$i}{size}    = $2 if defined $2;

			$i++;
		}
	}

	print "\tdone\n" if $s{verbose} ge 2;

}

print "found " . scalar keys (%torrents) . " torrents\n" if $s{verbose} ge 1;

## download torrent files
for my $t (keys %torrents) {
	my $url      = $torrents{$t}{url};
	my $uploader = $torrents{$t}{ul_by};
	my $time     = $torrents{$t}{ul_time};
	my $size     = $torrents{$t}{size};

	my $fname    = basename($url);

	last if $s{download_torrent} == 0;

	print "  processing torrent link [$url]..\n" if $s{verbose} ge 2;
	print "  ul_by: $uploader\n  ul_time: $time\n  size: $size\n" if $s{verbose} ge 1;

	if ($s{allow_yesterday}) {
		next unless $torrents{$t}{ul_time} =~ /Today|Y-day/i;
		print "   torrent [$fname] is from yesterday\n" if $torrents{$t}{ul_time} =~ /Y-day/i and $s{verbose} ge 2;
	} else {
		next unless $torrents{$t}{ul_time} =~ /Today/i;
		print "    torrent [$fname] is from today\n" if $s{verbose} ge 2;
	}

	unless ($s{download_torrent} == 2) { 
		unless (@{$s{known_uploaders}} ~~ $torrents{$t}{ul_by}) { 
			print "  skipping download of torrent [$fname] because ul_by [$torrents{$t}{ul_by}] is not a known uploader\n" if $s{verbose} ge 2;
			next;
		}
	}

	print "  downloading torrent [$url]..\n" if $s{verbose} ge 1;

	my $dl_results = get_file($url, $fname);

	print "\tdone\n" if $s{verbose} ge 2;
}

my $finish = localtime;

print "$0 finished at " . localtime . ", took " . $finish - $start . "\n";

exit;


sub get_file {
	# get_file($url, $fname) - returns 0|1 for success|failure
	my ($url, $file) = @_;
    my $results = 1;

	my $worker = LWP::UserAgent->new();
	   $worker->agent($s{browser_agent});

	my $response = $worker->get($url, ':content_file' => $file);

    ## could probably key off $worker->is_success instead

	$results = (-f $file) ? 0 : 1;
}

