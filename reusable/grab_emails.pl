#!/usr/bin/perl -w
#  grab_emails.pl - looks through plaintext files for email addresses, logs them out to a file (not CSV any more, was crashing np++)

use strict;
use warnings;
use 5.010;

use Cwd;
use File::Basename;
use File::Find;

my (%e, %s); # emails, settings

%s = (
    verbose  => 1,
    
    #file_re  => '.*\.txt$',
    file_re   => '.*[\.txt|phones]$', # need to match files without extensions
);

my $dir      = shift @ARGV // Cwd::getcwd;
$s{file_out} = basename($dir) . "-emails.txt";

my $results  = 0;

print(
      "\tverbose\t$s{verbose}\n",
      "\tdir    \t$dir\n",
      "\tfile_re\t$s{file_re}\n",
      );

# build a list of filenames
my @files;
find(
    sub {
        my $k = $File::Find::name;
        if (-f $k) {
            if ($k =~ /$s{file_re}/ and $k !~ /\.zip|\.bmp|\.xls|\.exe/) {
                push @files, $k;
            }
        }
    },
    $dir # FTW
);

print "> found '", $#files + 1, "' files..\n";

foreach (@files) {
    print "> searching '$_'..\n";
    
    my $lresults = grab_emails($_);
    
    $results += $lresults;
}

log_out(\%e, $s{file_out});

print "> found '$results' total email addresses. wrote to '$s{file_out}'\n";

exit 0;
################

sub grab_emails {
    # grab_emails($ffp) - greps for email addresses inside $ffp. adds found addresses to %e to prevent duplicates and returns total number of additions
    my $ffp = shift @_;
    my $results = 0;
    my $fh;
    
    open($fh, '<', $ffp) or return -1;
    while (<$fh>) {
        chomp (my $k = $_);
        next unless $k;
        
        #my $match  = $1 if $k =~ /.*[\d\w]*\@[\d\w]*\.\w{3}.*/;
        my $match = $1 if $k =~ /([A-Z0-9._%-]+@[A-Z0-9.-]+\.[A-Z]{2,4})/gi;
        if ($match) {
            $e{$match} = 1;
            $results++;
        }
    }
    close($fh);
    
    return $results;
}

sub log_out {
    # log_out(\%emails, $file_out) - writes the contents of %emails to $file_out
    my ($href, $file_out) = @_;
    my %h = %{$href};
    my $fh;
    
    open ($fh, '>', $file_out) or die "DIE:: unable to write to '$file_out':$!";
    
    foreach (sort keys %h) {
        print $fh $_ . "\n";
    }
    
    close ($fh);
    
    
    return;
}