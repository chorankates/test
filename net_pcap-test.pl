#!/usr/bin/perl -w
# net_pcap-test.pl - quick and dirty test of Net::Pcap

use strict;
use warnings;
use Net::Pcap::Easy;

# everything is optional

my $npe = Net::Pcap::Easy->new(
    dev     => "lo", # not number based like tshark
    filter  => "host 127.0.0.1 and icmp", # this looks to support both capture AND display filters
   
    packets_per_loop  => 1, # this is going to be key.. but is it packets captured or packets inspected?
    bytes_to_capture  => 1024, # can probably be set to 0 if we only want headers
    timeout_in_ms     => 0, # 0 means forever (what does that  mean?)
    promiscuous       => 1, # duh

    icmp_callback => sub {
	my ($npe, $ether, $ip, $icmp) = @_;
	
	print "ICMP: $ether->{src_mac}:$ip->{src_ip} -> $ether->{dest_msc}:$ip->{dest_ip}\n";
    }
    
    );

1 while $npe->loop;
