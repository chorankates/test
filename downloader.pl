#!/usr/bin/perl -w
#  downloader.pl - given an array of addresses, download each of these files

use strict;
use warnings;
use 5.010;
use LWP::UserAgent;
use HTTP::Request::Common;
use Getopt::Long;
use File::Spec;

# define some hashes
my (%f, %s, %d); # %f=CLI flags, %s=settings, %d=downloaded files HoH
my @list;

# do some timing
my (@lt1, @lt2);
@lt1 = localtime;
print "% $0 started at ", &d_nicetime(\@lt1, "time"), "\n";

%s = (
    verbose => 1,
    os      => "Windows",
    
    dest_dir => "d:\\scratch\\",
    random   => 0, # if 1, we will prefix a random number to the local filename for dynamicisim
);

GetOptions(\%f, "help", "verbose:i", "dest:s", "list:s", "csv:s", "random:i");

&d_help() if $f{help}; # we exit from this function

$s{debug}    = $f{debug};# // 0;
$s{dest_dir} = $f{dest} if $f{dest} and -d $f{dest}; 
$s{list}     = $f{list} if $f{list} and -f $f{list};
$s{csv}      = $f{csv}  if $f{csv};
$s{random}   = $f{random} if $f{random};

$s{os} = "Windows" if $^O =~ /MSWin32/i;
$s{os} = "Linux"   if $^O =~ /(linux|unix)/i;

# populate @list
my $tsource;
if ($s{list}) {
    # user specified an external list of URLs in $s{list}
    @list = d_populate($s{list});
    my $count = $#list + 1;
    $tsource = "file";
    print "> imported $count URLs from '$s{list}'\n";
} elsif ($s{csv}) {
    # ok, user specified a CSV list of URLs on the CLI
    @list = split /,/, $s{csv};
    $tsource = "command line";
    my $count = $#list + 1;
    print "> found $count URLs from '\$f{csv}'\n";
    
} else {
    print "% downloader.pl - need a list of files to download\n";
    &d_help();
}

print(
    "> settings:\n",
    "\tOS          = $s{os}\n",
    "\tdestination = $s{dest_dir}\n",
    "\tsource      = $tsource\n",
    "\trandomize   = $s{random}\n",
    
) if $s{verbose};


# ok, do some work
for (my $i = 0; $i <= $#list; $i++) {
    my $url     = $list[$i];
    my @tmp     = split /\//, $url;
    my $local   = $tmp[-1];
    $local = int(rand(1000)) . "." . $local if $s{random}; # this isn't perfect as we could get the same random number twice, but it's good enough for now
    my $ffp     = File::Spec->catfile($s{dest_dir}, $local); # woot
    print "downloading '$url' to '$local'...";
    my $results = &d_downloader($url, $ffp);
    if ($results) {
        print "\tdownload successful\n";
    } else { print "\tdownload FAILED\n"; }
    
}

@lt2 = localtime;
print "% $0 finished at ", &d_nicetime(\@lt2, "time"), " (", &d_timetaken(\@lt1, \@lt2), ")\n";

exit 0;

####### subs below
# d_downloader -- d_downloader($url, $local_ffp) - returns 0|1
# d_populate   -- d_populate($text_file) - returns an array containing contents of $text_file
# d_nicetime   -- d_nicetime(\@time, type) - returns time/date according to the type 
# d_timetaken  -- d_timetaken(\@time1, \@time2) - returns the difference between times
# d_help       -- print some help and exit 0;

sub d_downloader {
    # d_downloader($url, $local_ffp) - returns 0|1
    my ($url, $ffp) = @_;
    my $results;
    
    my ($worker, $request, $response);
    
    $worker = LWP::UserAgent->new;
    $worker->agent("downloader.pl");
    $request = HTTP::Request->new(GET => $url);

    $response = $worker->get($url, ':content_file' => $ffp);
    
    unless ($response->is_success) {
        return 0;
    } else {
        return 1;
    }
    
}

sub d_populate {
    # d_populate($text_file) - returns an array containing contents of $text_file
    # assumes that text file is CRLF line delimited
    my $file = shift @_;
    my @results;
    
    open (FILE, '<', $file) or die "die> unable to open '$file':$!";
    while (<FILE>) {
        chomp($_);
        next if $_ =~ /^#/; # skipping comments
        push @results, $_;
    }
    close (FILE);
    
    return @results;
}


sub d_nicetime {
    # n_nicetime(\@time, type) - returns time/date according to the type 
    # types are: time, date, both
    my $aref = shift @_; my @time = @{$aref};
    my $type = shift @_ || "both"; # default variables ftw.
    warn "warn>  e_nicetime: type '$type' unknown" unless ($type =~ /time|date|both/);

    my $hour = $time[2]; my $minute = $time[1]; my $second = $time[0];
    $hour    = 0 . $hour   if $hour   < 10;
    $minute  = 0 . $minute if $minute < 10;
    $second  = 0 . $second if $second < 10;

    my $day = $time[3]; my $month = $time[4] + 1; my $year = $time[5] + 1900;
    $day   = 0 . $day   if $day   < 10;
    $month = 0 . $month if $month < 10;

    my $time = $hour .  "." . $minute . "." . $second;
    my $date = $month . "." . $day    . "." . $year;

    my $full = $date . "-" . $time;

    if ($type eq "time") { return $time; }
    if ($type eq "date") { return $date; }
    if ($type eq "both") { return $full; }
}

sub d_timetaken {
    # n_timetaken(\@time1, \@time2) - returns the difference between times
    # right now only supporting diffs measured in hours, and will break on wraparound hours
    my ($aref1, $aref2, @time1, @time2);
    $aref1 = shift @_;  $aref2 = shift @_;
    @time1 = @{$aref1}; @time2 = @{$aref2};
	
	my ($diff_second, $diff_minute, $diff_hour);
    # main handling
    if ($time1[0] <= $time2[0]) {
		$diff_second = $time2[0] - $time1[0];
		$diff_minute = $time2[1] - $time1[1];
	} else {
		$diff_second = ($time2[0] + 60) - $time1[0];
		$diff_minute = ($time2[1] - 1) - $time1[1];
	}
    # still need to resolve the hour wraparound, but low priority
    $diff_hour   = $time2[2] - $time1[2];

    # stickler for leading 0 if 1 < N > 10, flexing some regex muscle
    foreach ($diff_second, $diff_minute, $diff_hour) { $_ =~ /^(\d{1})$/; if (($1) and length($1) eq 1) { $_ = 0 . $_; } }


    my $return = $diff_hour . "h" . $diff_minute . "m" . $diff_second . "s";
    return $return;

}

sub d_help {
    
    #GetOptions(\%f, "help", "verbose:i", "dest:s", "list:s", "csv:s");
    
    print(
	"[$0] - syntax: --help, --verbose=N, --dest=path, --list=file, --csv=CSV\n",
        "\n",
        "> details: \n",
	"\t--help", " " x (15 - length("--help")), "this screen\n",
	"\t--verbose=N", " " x (15 - length("--verbose=N")), "sets verbose level to N, 0|1 accepted\n",
        "\t--dest=path", " " x (15 - length("--dest=path")), "sets the destination directory, Windows/Unix safe\n",
        "\t--list=file", " " x (15 - length("--list=file")), "path to CRLF line terminated file containing URLs to download\n",
        "\t--csv=CSV", " " x (15 - length("--csv=CSV")), "CSV list of URLs to download\n",
        "\t--random=N", " " x (15 - length("--random=N")), "prefixes the destination filename with a random number (useful if you are downloading files with the same basename)\n",
	"\n\n",
        "> examples: \n",
        "\t $0 --dest=d:\\scratch\\ --csv=http://www.webroot.com/index.html --random=1\n",
        "\t     [downloads 'index.html' to d:\\scratch\\ and randomizes it's filename]\n",
        "\t $0 --list=foo.txt --verbose=N\n",
        "\t     [downloads all URLs in 'foo.txt' in verbose mode]\n",
    );
    
    exit 1;
}