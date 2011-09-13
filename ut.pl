#!/usr/bin/perl
## ut.pl - looks for torrent files uploaded Today

# TODO
## rework the display of contents of %torrents
## add the number of seeders/leechers to the %torrents hash 

use strict;
use warnings;

use Cwd;
use File::Basename;
use Getopt::Long;
use LWP::UserAgent;

my (%f, %s); # flags, settings

%s = (
    home    => Cwd::getcwd,
    verbose => 1, # 0 <= n <= 2

	base_url => [
		'http://thepiratebay.org/top/205', # Top 100 TV shows
		'http://thepiratebay.org/top/201', # Top 100 Movies
	], # will check each of these pages

	known_uploaders => [
    	'eztv',
		'VTV',
		'TVTeam',
	],

	ignored_regex => [
    	'(?i).*WWE.*',
	], # will check the torrent file name against these regexes and skip if matched

	check_archive => 1, # will look in archive directory for $fname, and not download if -f
	archive       => '/home/conor/dl/_torrent/src/',

    download_torrent => 1, # 1 downloads files from known ul-ers, 2 downloads from anyone
	allow_yesterday  => 0, # matches 'Today' or 'Y-day'

	browser_agent => "Mozilla/5.0 (Windows; U; Windows NT 5.2; en-US; rv:1.9.2) Gecko/20100115 Firefox/3.6",

);

GetOptions(\%f, "verbose:i", "download_torrent:i", "allow_yesterday:i", "help");
$s{$_} = $f{$_} foreach (keys %f);

my %torrents;

my $start = time;
print "$0 started at " . localtime() . "\n" if $s{verbose} ge 1;

## find torrent files on each URL
my $i = 0;
for my $url (@{$s{base_url}}) {
	print "  processing URL [$url]..\n" if $s{verbose} ge 1;

	my ($worker, $response);
	$worker = LWP::UserAgent->new();
    $worker->agent($s{browser_agent}); # liar
	$worker->timeout(10); # fail fast

	$response = $worker->get($url);

	unless ($response->is_success) {
		print "  failed to get URL: " . $response->status_line . "\n" if $s{verbose} ge 1;
		next;
	}
	
	my @content = split("<tr>", $response->content);

	for my $line (@content) { 

		if ($line =~ /href=(.*)\stitle="Download this torrent">/) { 
            $torrents{$i}{url} = $1;
			
			$torrents{$i}{ul_by}   = $1 if $line =~ /ULed\sby\s.*?>(.*?)</;
			$torrents{$i}{ul_time} = $1 if $line =~ /Uploaded\s(.*?), Size\s(.*?),/;
			$torrents{$i}{size}    = $2 if defined $2;
			$torrents{$i}{src}     = $url;

			#ocd
			$torrents{$i}{url}     =~ s/"//g;
			$torrents{$i}{ul_time} =~ s/&nbsp;/ /;
			$torrents{$i}{size}    =~ s/&nbsp;/ /;
			
			$i++;
		}
	}

	print "\tdone\n" if $s{verbose} ge 2;

}

print " found " . scalar keys (%torrents) . " torrents\n" if $s{verbose} ge 1;

## download torrent files
for my $t (keys %torrents) {
	my $url      = $torrents{$t}{url};
	my $uploader = $torrents{$t}{ul_by};
	my $time     = $torrents{$t}{ul_time};
	my $size     = $torrents{$t}{size};

	my $fname    = basename($url);

	$torrents{$t}{downloaded} = "pending";

	last if $s{download_torrent} == 0;

	print "  processing torrent link [$fname]..\n" if $s{verbose} ge 2;
	print "    ul_by: $uploader\t ul_time: $time\t size: $size\n" if $s{verbose} ge 2;

	if ($s{allow_yesterday}) {
		unless ($torrents{$t}{ul_time} =~ /Today|Y-day/i) {
	        print "   skipping torrent [$fname], not ul [Today|Y-day]\n" if $s{verbose} ge 2;
			next;
		}
		print "   torrent [$fname] is from yesterday\n" if $torrents{$t}{ul_time} =~ /Y-day/i and $s{verbose} ge 2;
	} else {
		unless ($torrents{$t}{ul_time} =~ /Today/i) {
			print "    skipping torrent [$fname], not ul [Today]\n" if $s{verbose} ge 2;
			next;
		}
		print "    torrent [$fname] is from today\n" if $s{verbose} ge 2;
	}

	unless ($s{download_torrent} == 2) { 
		print "DBGZ" if 0;
		unless (@{$s{known_uploaders}} ~~ /$torrents{$t}{ul_by}/) { 
			print "  skipping download of torrent [$fname] because ul_by [$torrents{$t}{ul_by}] is not a known uploader\n" if $s{verbose} ge 2;
			$torrents{$t}{downloaded} = 'skipped';
			next;
		}		

		if (already_downloaded($fname)) { 
			print "  skipping download of torrent [$fname] because it already exists in [$s{archive}]\n" if $s{verbose} ge 2;
			next;
		}

		if (is_ignored($fname)) { 
            print "  skipping download of torrent [$fname] because it matches an entry in the ignore list\n" if $s{verbose} ge 1;
			next;
		}
		
		print "  downloading torrent [$url]..\n" if $s{verbose} ge 1;
	}


	my $dl_results = get_file($url, $fname);
       $dl_results = ($dl_results) ? 'success' : 'failure';
	
	$torrents{$t}{downloaded} = $dl_results;

	print "\tdone: $dl_results\n" if $s{verbose} ge 2;
}

if ($s{verbose} ge 1) { 
	print "\%torrents:\n";

	for my $key (sort { $torrents{$a}{downloaded} cmp $torrents{$b}{downloaded} } keys %torrents) { 
		next unless $torrents{$key}{downloaded} =~ /success|failure|skipped/i or $s{verbose} ge 3;

		# keys are numeric, so keeping this order will list most popular -> least popular
    	print(
			"\t$key\n",
			"\t\turl:        $torrents{$key}{url}\n",
			"\t\tdownloaded: $torrents{$key}{downloaded}\n",
			"\t\tfname:      " . basename($torrents{$key}{url}) . "\n",
			"\t\tul_by:      $torrents{$key}{ul_by}\n",
			"\t\ttime:       $torrents{$key}{ul_time}\n",
			"\t\tsize:       $torrents{$key}{size}\n",
			#"\t\tsource:     $torrents{$key}{source}\n",
		) if 0;

		print("  $key ($torrents{$key}{downloaded}) ul: $torrents{$key}{ul_by}, time: $torrents{$key}{ul_time}, size: $torrents{$key}{size}, url: $torrents{$key}{url}\n");

	}
}

my $finish = time;

print "$0 finished at " . localtime() . ", took " . ($finish - $start) . "\n";

exit;


sub get_file {
	# get_file($url, $fname) - returns 1|0 for success|failure
	my ($url, $file) = @_;
    my $results = 1;

	my $worker = LWP::UserAgent->new();
	   $worker->agent($s{browser_agent});

	my $response = $worker->get($url, ':content_file' => $file);

	#$results = (-f $file) ? 0 : 1;
	$results = ($response->is_success) ? 1 : 0;
}

sub already_downloaded {
	# already_downloaded($file) - returns 0|1 for no|yes
	my $file = shift;

	my $results = (-f File::Spec->catfile($s{archive}, $file)) ? 1 : 0;

	return $results;
	
}

sub is_ignored {
	# is_ignored($filename) - returns 0|1 for no|yes
	my $file    = shift;
	my $results = 0;

	## this is just the wrong way to do this.. make it better
	for my $regex (@{$s{ignored_regex}}) {
    	if ($file =~ /$regex/) { 
        	$results = 1;
			last;
		}
	}

    return $results;
}
