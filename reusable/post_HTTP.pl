#!/usr/bin/perl -w
# post_HTTP.pl - housing for the corollary to get_HTTP.pl, will be ported to ironhide when done

use strict;
use warnings;
use 5.010;

use LWP;
use HTTP::Request::Common;

my (%p, %s); # POST parameters, settings

%s = (
    verbose => 1,
    
    target  => "http://www.peets.com/site/search.asp", 
    
);

# key=value will be passed to $target
%p = (
    SEARCH1    => "peetnik", # search term
    image7     => "submit",
    'image7.x' => "0", # where on the 'submit' button i clicked? 0,0 if you press 'enter'
    'image7.y' => "0",
);

hdump(\%s, "settings")   if $s{verbose} ge 1;
hdump(\%p, "parameters") if $s{verbose} ge 1;

my $results = post_HTTP($s{target}, \%p);

print "\$results: $results\n";

exit 0;

sub hdump {
    # hdump(\%hash, $type) - dumps %hash, helped by $type
    my ($href, $type) = @_;
    my %h = %{$href};
    
    my $x = 20;
    
    print "> hdump($type):\n";
    
    foreach (sort keys %h) {
        print "\t$_", " " x ($x - length($_));
        
        print "$h{$_}\n"    unless $h{$_} =~ /array/i;
        print "@{$h{$_}}\n" if     $h{$_} =~ /array/i;
    }
    
    return;
}

sub post_HTTP {
    # post_HTTP($url, \%parameters) - passed a URL and hash ref of parameters, returns decoded HTML
    my ($url, $href) = @_;
    my %h = %{$href};
    my $results;
    
    my $worker = LWP::UserAgent->new();
    
    push @{ $worker->requests_redirectable }, 'POST'; # this may or may not be necessary depending on site
    
    my $request = HTTP::Request::Common::POST(
        $url,
        
        Content_Type => 'application/x-www-form-urlencoded', #  or text/plain 
        Content => [ \%h ] ,
    
    );

    my $response = $worker->request($request);
    
    if ($response->is_success) {
        $results = $response->content;
        #$results = $response->status_line;
    } else {
        $results = $response->status_line;
    }
    
    return $results;
}