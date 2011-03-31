#!/usr/bin/perl -w
#  downloader.pl - given an array of addresses, download each of these files

use strict;
use warnings;
use 5.010;
use LWP::UserAgent;
use HTTP::Request::Common;
use Getopt::Long;
use File::Spec;

use lib '/home/conor/Dropbox/perl/_pm/';
use lib 'c:/_dropbox/My Dropbox/perl/_pm/';
use webroot;
use ironhide;

$| = 1; # makes it better when piping output

# define some hashes
my (%f, %s, %d); # %f=CLI flags, %s=settings, %d=downloaded files HoH
my @list;
my %list;

# do some timing
my (@lt1, @lt2);
@lt1 = localtime;
print "% $0 started at ", nicetime(\@lt1, "time"), "\n";

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
$s{verbose}  = $f{verbose} if $f{verbose};

$s{os} = "Windows" if $^O =~ /MSWin32/i;
$s{os} = "Linux"   if $^O =~ /(linux|unix)/i;

# populate @list
my $tsource;
if ($s{list}) {
    # user specified an external list of URLs in $s{list}
    #@list = d_populate($s{list});
    %list = d_populate($s{list});
    #my $count = $#list + 1;
    my $count = (keys %list) + 1;
    $tsource = "file";
    print "> imported $count URLs from '$s{list}'\n";
} elsif ($s{csv}) {
    # ok, user specified a CSV list of URLs on the CLI
    @list = split /,/, $s{csv};
    $tsource = "command line";
    my $count = $#list + 1;
    print "> found $count URLs from '\$f{csv}'\n";
    
    # put the CSV into a hash
    foreach (@list) {
        $list{$_} = "?";
    }
    
    
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

my ($success, $failure) = (0, 0);
my @fails; # list of URLs that 404d

# ok, do some work
#for (my $i = 0; $i <= $#list; $i++) {
my $i = 0;
foreach (sort keys %list) {
    #my $url     = $list[$i];
    my $url     = $_;
       $url     = substr($url, 0, length($url) - 1) if $url =~ /\W$/; # this is not workingg for some reason
    my $md5     = $list{$_};
    my @tmp     = split /\//, $url;
    my $local   = $tmp[-1];
       $local   = int(rand(1000)) . "." . $local if $s{random}; # this isn't perfect as we could get the same random number twice, but it's good enough for now
    my $ffp     = File::Spec->catfile($s{dest_dir}, $local); # woot
    
    my $nurl    = substr($url, -30, 30);
    
    print "> downloading '$url' to '$local'...\n";
    my $results = &d_downloader($url, $ffp);
    if ($results) {
        print "\tdownload successful..";
    
        unless ($md5 eq "?") {
            # ok, download successful and we have an md5
            my $file_md5 = md5($ffp);
            
            if ($file_md5 eq $md5) {
                print "\tMD5 match '$file_md5'\n";
            } else {
                print "\tMD5 match FAILED, downloaded: '$file_md5', expected '$md5'\n";
		push @fails, $url;
		$failure++;
		$i++;
		next; # hacky..
            }
        }
        
        $success++;
    } else {
        print "\tdownload FAILED\n";
        $failure++;
        push @fails, $url;
    }
    $i++;
}

print(
    "> results:\n",
    "\tsuccess: $success\n",
    "\tfailure: $failure\n",
    "\tfail urls:\n",
    );
if (@fails) { print "\t\t$_\n" foreach (@fails); }

@lt2 = localtime;
print "% $0 finished at ", nicetime(\@lt2, "time"), " (", timetaken(\@lt1, \@lt2), ")\n";

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
    # d_populate($text_file) - returns a hash containing contents of $text_file (primary key is path, md5 is value if we have it)
    # assumes that text file is CRLF line delimited
    my $file = shift @_;
    #my @results;
    my %h;
    
    open (FILE, '<', $file) or die "die> unable to open '$file':$!";
    while (<FILE>) {
        chomp($_);
        
        my $md5 = "?";
        my $url = "?";
        
        if ($_ =~ /(.*)\*\*(.*)/) {
            $md5 = $1; # md5s have static lengths, why it is first
            $url = $2;

        } else {
            $url = $_;
        }
        
        next if     $_   =~ /^#/;     # skipping comments
        next unless $url =~ /^http/i; # make sure its an address
        #push @results, $_;
        $h{$url} = $md5;
    }
    close (FILE);
    
    #return @results;
    return %h;
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
