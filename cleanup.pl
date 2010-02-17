#!/usr/bin/perl -w
# this is a port of cleanup.sh, used to remove
# files matching the globs: *~, *.tmp

use strict;
use File::Find;

disp_time("> cleanup.pl - begin");

my $directory = "/home/conor";
my $glob = ".*~"; # this is not being used, see the match on :25

my $count = 0; my $total = 0;
my $whatif = shift @ARGV; $whatif = "1" unless defined $whatif; # we will run in whatif mode 
                                                                # unless we are passed '0'
if ($whatif eq 1) { print "WHATIF: not deleting files.\n"; 
} else { print "deleting files:\n"; }

find (\&cleanup, $directory);

print "matched: $count of $total files.\n";

sub cleanup {
    # regex matches *~ and #*#
    if ($_ =~ /^(.*~|\#.*\#)$/) { 
	my $d = $File::Find::dir;
	my $f = $_; # we could get $d,$f by referencing $File::Find::name
	my $ffp = $File::Find::name;	

	if ($whatif == 0) { 
	    # we are not whatif-ing, let's trash some files
	    print "\t", $ffp, "\n";
	    unlink($ffp) or warn "unable to remove: $ffp";
	} else {
	    print "\t", $d, "/", $f, "\n";
	}
	
	$count++;
    }
    $total++;
}

disp_time("> cleanup.pl - done");

# TODO : testing

sub disp_time {
    my @time = split(/ /, scalar(localtime));
    print "@_\t($time[4])\n";
}
