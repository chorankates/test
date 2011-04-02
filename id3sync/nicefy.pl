#!/usr/bin/perl -w
# nicefy.pl - a tool for managing media file and folder names

use strict;

# using a while <> loop for now because we're just passing
# the filenames in a txt file (sample/mp3_filenames.txt)

while (<>) {

    chomp($_);
    my $tmp = $_;

# capitalize first letter of every word
    s/\b(\w)(\w*)/\U$1\L$2/g; 

# fix the mp3 -> .Mp3 issue in a hacky way. tmtowtdi
    s/\.Mp3/\.mp3/g;

# replacement section 
    s/_/\ /g; # replace _ with space
    s/\[/\(/g; s/\]/\)/g; # replace[]  with ()
    s/Feat/ft/ig; # Feat with ft (done after capitalization)
    s/Ft./ft./g;  # but we also need to fix true 'ft.'
  
# find if ft. is at the end of a string and not encapsulated
    s/[^(]ft(\b\w)[^)]/\(ft\. $1\)/g;


# flag weird characters ; # + ~ @
    if (/[\s\S]*([@+;#~]+)[\s\S]*/) { print "FLAG:'$1'\tin: $_\n"; }

    if ($tmp ne $_) { # the string has changed, lets print 
	print "b4:\t$tmp\n";
	print " a:\t$_\n";
    } else {
	print "uc:\t$_";
    }

# flag files that don't match certain patterns - FUTURE



#    print "$_\n";

}
