#!/usr/bin/perl -w
# proxy-validate.pl - validates proxies

use strict;
use warnings;
use LWP::UserAgent;

my $i = 0;
my ($address, $verify, $port);

do {
	my %proxy = choose_proxy();
	   $address = $proxy{address};
	   $port    = $proxy{port};
	
	$verify = verify_proxy(\%proxy);
	
	print ">\$verify of $address / $port : $verify\n";
	$i++;
} until $verify eq "true" or $i > 10;

if ($i > 10) { print "> bailed out after '$i' attempts\n"; }
else {
	print(
		"> found: $address / $port\n",
	);
}

exit 0;

sub choose_proxy {
    # takes no parameters, returns a FQD proxy and port in an array
    my (%hash, %return_hash);
    my $i = 0;

    my @array = (
	#"148.233.229.235:80",
	#"213.203.241.210:80",
	#"208.100.40.34:80",
	#"148.233.229.235:80",
	#"201.92.253.33:3128",
	#"200.65.129.1:80",
	#"200.65.129.1:3128",
	#"200.65.127.161:80",
	"67.208.234.6:8080",
	"61.93.137.209:8088",
	"61.28.162.234:3128",
	"61.244.157.239:808",
	"61.177.201.236:8080",
	"61.158.163.112:8081",
	"59.90.16.106:6588",
	"59.36.98.154:80",
	"59.108.224.191:808",
	"58.61.38.19:808",
	"58.246.76.76:8080",
	"41.223.157.14:8080",
	"24.155.134.222:8085",
	"222.43.54.98:808",
	"222.178.58.112:808",
	);

    foreach (@array) { $hash{$i} = $_; $i++; }

    my $rand = int(rand(keys(%hash))); # roof is total number of known proxies

    my @proxy = split(":",$hash{$rand});
    %return_hash = ( 'address', $proxy[0], 'port', $proxy[1]);

    return %return_hash;
}

sub verify_proxy {
    # takes a hash ref pointing to a address/port combo
    my $href = shift @_; my %hash = %{$href};
    my $result; my $target = "http://www.webroot.com/"; # need some KG target here
    my $timeout = 10; # time to wait for response from proxy

    my $address = $hash{address}; my $port = $hash{port};
    my $full_address = "http://" . $address . ":" . $port;

    my $worker   = LWP::UserAgent->new;
       $worker->agent("Mozilla/5.0 (Windows; U; Windows NT 5.2; en-US rv:1.9.1.1) Gecko/20090715 Firefox/3.5.1"); # pretend to be firefox
       $worker->proxy(http => $full_address);  # setting the proxy
       $worker->timeout($timeout);
    my $request  = HTTP::Request->new(GET => $target);
    my $response = $worker->request($request);

    #if ($settings{debug} == 1) { print "checking: $full_address\n"; }

    if ($response->is_success) { 
	my %content = %{$response};
	my %hrequest = %{${content}{_request}}; # content of headers
	#my %hrequest = %{${content}{_content}}; # content of download

	#while (my ($k, $v) = each %hrequest) {
	#    next unless $v;
	#    print "\n$k .. $v";
	#}

	# confirming by way of a follow 
	if ($hrequest{_uri} eq "http://www.webroot.com/En_US/index.html") { 
	    $result = "true";
	} else { $result = "false"; } # failing because we didn't get the correct forward

	

    } else { $result = "false"; } # failing because $response->isnotsuccess

    return  $result;
}
