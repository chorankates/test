#!/usr/bin/perl -w
#  gfight.pl -- takes 2 terms and searches multiple search engines, comparing the results

# also want to write something that reads twitter's trending topics and archives them on a regular basis
# then pipe them into this script and see how closely twitter and google mirror each other

use strict;
use warnings;
use 5.010;

use File::Spec;
use File::Basename;
use Cwd;
use Getopt::Long;
use LWP::UserAgent;
use URI::Escape;
use YAML;

use lib '/home/conor/Dropbox/perl/_pm';
use lib 'c:/_dropbox/My Dropbox/perl/_pm';
use ironhide;
use webroot;

my (%e, %f, %s, %r); # engines, flags, settings, results

%s = (
    verbose => 2,
    
    home => Cwd::getcwd,
    
    function => "fight", # will also accept list

    # engines => [ "google", "yahoo", "bing" ], # this will be defined below
);

# define the base urls for all search engines 
$e{google}{base} = "http://www.google.com/#hl=en&q=";
# not working: $e{yahoo}{base} = "http://search.yahoo.com/search;_ylt=A9G_eoyfJjpMdqEAZCubvZx4?&toggle=1&cop=mss&ei=UTF-8&fr=yfp-t-701p=" 
# not working: $e{bing}{base} = "http://www.bing.com/search?&go=&form=QBLH&qs=n&sk=q=";

GetOptions(\%f, "help", "verbose:i", "function:s", "first:s", "second:s", "engines:s");
push @{$s{engines}}, $_ foreach (split(",", $f{engines})); # boom
foreach (keys %f) {
    $s{$_} = $f{$_} unless $_ =~ /^e/i;
}




my (@lt1, @lt2); @lt1 = localtime;
print "% gfight started at  ", &nicetime(\@lt1, "time"), "\n" if $s{verbose} ge 1;

hdump(\%f, "flags") if $s{verbose} ge 2;
hdump(\%s, "settings") if $s{verbose} ge 1;

# traffic cop
if ($s{function} =~ /fight/i) {
    # get some results
    my $t1 = $s{first}      // "your mother was a hampster";
    my $t2 = $s{second} // "and your father smelled of elderberries";

    $t1 = uri_escape($t1);
    $t2 = uri_escape($t2);

    my @engines = @{$s{engines}};
    
    foreach (@engines) { 

        print "> fight($_, $t1, $t2)..\n";

        my $base = $e{$_}{base};

        unless ($base) {
            print "WARN:: engine '$_' has no defined base url, skipping\n";
            next;
        }

        my $t1_count = count($_, $base, $t1) // 0;
        my $t2_count = count($_, $base, $t2) // 0;
    
        print(
            "\t$t1_count", " " x (10 - length($t1_count)), "$t1\n",
            "\t$t2_count", " " x (10 - length($t2_count)), "$t2\n",
        );
        
    }
        
    # archive them
    
} elsif ($s{function} =~ /list/i) {
    # not written yet
}

@lt2 = localtime;
print "% gfight finished at ", &nicetime(\@lt2, "time"), " (", &timetaken(\@lt1, \@lt2), ") \n" if $s{verbose} ge 1;


exit 0;

## subs below

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


sub count {
    # count($engine_name, $base_url, $search_term) - uses $base_url and
    # $search_term to generate some HTML, then use $engine_name to parse for the number of results
    # return number of results
    my ($engine, $base, $term) = @_;
    my $count = 0;
    
    my $worker = LWP::UserAgent->new;
         $worker->agent("gfight");

    my $query = $base . $term;
    
    my $request  = HTTP::Request->new(GET => $query);
    my $response = $worker->request($request);
    
    unless ($response->is_success) {
        warn "WARN:: '$query' returned " . $response->status_line . "\n";
        return -1;
    }
    
    my %content = %{$response};
    my @content = split(/<br>/, ${content}{_content}); # splitting content into an array
    
    if ($engine =~ /google/i) {       
        
        $count = "foo";
        
    } elsif ($engine =~ /bing/i) {
        warn "WARN:: engine '$engine' not complete\n";
        return -1;
        
    } elsif ($engine =~ /yahoo/i) {
        warn "WARN:: engine '$engine' not complete\n";
        return -1;
        
    } else {
        warn "WARN:: unknown engine '$engine'\n";
        return -1;
    }
    
    return $count;
}