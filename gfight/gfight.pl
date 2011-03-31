#!/usr/bin/perl -w
#  gfight.pl --

use strict;
use warnings;
use 5.010;

use Getopt::Long;
use LWP::UserAgent;

use lib '/home/conor/Dropbox/perl/_pm';
use lib 'c:/_dropbox/My Dropbox/perl/_pm';
use webroot;

#(02:02:27 PM) Conor Horan-Kates: Write a google fight script -- compare the number of results for two different strings
#(02:02:42 PM) Conor Horan-Kates: Save past queries in a YAML file

my (%f, %s); # flags, settings

%s = (
    verbose => 1,
    
    
);

GetOptions(\%f, "help", "verbose:i", "home:s", "f1:s", "f2:s");
$s{$_} = $f{$_} foreach (keys %f);

hdump(\%f, "flags")    if $s{verbose} ge 2;
hdump(\%s, "settings") if $s{verbose} ge 1;



exit 0;

## subs below
# hdump(\%hash, $type) - dumps %hash, helped by $type

sub hdump {
    # hdump(\%hash, $type) - dumps %hash, helped by $type
    my ($href, $type) = @_;
    my %h = %{$href};
    
    print "> hdump($type):\n";
    
    foreach (sort keys %h) {
        print "\t$_", " " x (20 - length($_));
        
        print "$h{$_}\n"    unless $h{$_} =~ /array/i;
        print "@{$h{$_}}\n" if     $h{$_} =~ /array/i;
    }
    
    return;
}