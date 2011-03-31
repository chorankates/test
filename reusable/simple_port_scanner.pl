#!/usr/bin/perl -w
#  simple_port_scanner.pl - using IO::Socket, try to connect to each port specified. display number of successful vs. failure as results

use strict;
use warnings;
use 5.010;

use Getopt::Long;
use IO::Socket;

use lib 'c:/_dropbox/My Dropbox/perl/_pm';
use lib '/home/conor/Dropbox/perl/_pm';
use ironhide;

# this is a perfect time to use SIGINT redirection, if ctrl+c is seen, print out current results hash

# allow specification of either TCP or UDP scanning
my (%f, %r, %s); # flags, results, settings

$| = 1;

%s = (
    verbose => 1,
    
    host_addr  => "127.0.0.1", # scan yourself for now
    
    port_start => 1,
    port_range => 65535,
    
    connect_type    => "TCP", # can overload with UDP .. but not yet
    connect_timeout => 1,     # time to wait for a response once a request is sent
    sleep           => 1,     # time to wait in between sending requests
    
);

GetOptions(\%f, "help", "verbose:i", "port_start:i", "port_range:i", "connect_type:s", "connect_timeout:i", "sleep:i");
$s{$_} = $f{$_} foreach (keys %f);

my @t1 = localtime;
print "% $0 started at ", nicetime(\@t1, "time"), "\n";

hdump(\%f, "flags")    if $s{verbose} gt 1;
hdump(\%s, "settings") if $s{verbose} gt 0;

print "> scanning $s{host_addr}:$s{port_start}-$s{port_range}\n";

for (my $i = $s{port_start}; $i <= $s{port_range}; $i++) {
    
    # verbose = 0, don't display anything until the scan has completed
    # verbose = 1, only show successful connections during the scan, then show all results
    # verbose = 2, show all attempts success/failure during the scan
    
    print "\ttrying port '$i'.." if $s{verbose} gt 1;
    
    my $results = sps_connect($s{host_addr}, $i, $s{connect_type}, $s{connect_timeout});

    print "\n" if $s{verbose} gt 1; # provides a better experience 
    
    if ($results) {
        # successful connection to $i
        print "\tSUCCESS, connected to $s{host_addr}:$i\n" if $s{verbose} gt 0;
    } else {
        # unsuccessful in connecting to $i
        print "\tFAILURE, unable to connect to $s{host_addr}:$i\n" if $s{verbose} gt 1;
    }
    
    # record the results in %r
    $r{$i} = $results;
    
    if ($s{sleep}) {
        print "(sleeping $s{sleep})" if $s{verbose} gt 1;
        sleep $s{sleep};
        print "\n" if $s{verbose} gt 1;
    }
    
}

hdump(\%r, "results") if $s{verbose} lt 3;

my @t2 = localtime;
print "% $0 finished at ", nicetime(\@t1, "time"), ". took ", timetaken(\@t1, \@t2), "\n";

exit 0;

###### subs
sub sps_connect {
    # sps_connect($host, $port, $proto, $timeout) - connects to $host:$port over $proto, with $timeout timeout. returns 0|1 for failed|success
    my ($host, $port, $proto, $timeout) = @_;
    my $results = 0;
    
    # create the worker in a generic way
    my $scanner;
    if ($proto =~ /TCP/i) { 

        $scanner = IO::Socket::INET->new(
            PeerAdr  => $host,
            PeerPort => $port,
            Proto    => $proto,
            Timeout  => $timeout,
            Type     => SOCK_STREAM
        );
                
        
    } elsif ($proto =~ /UDP/i) {
        # not supported yet        
    } else {
        warn "WARN:: unknown protocol '$proto', bailing out\n";
        return 0;
    }
    
    
    # since this is just a connect scan, use $scanner as results and close socket
    $results = 1 if $scanner;
    
    close($scanner);
    
    
    return $results;
}

sub hdump {
    # hdump(\%hash, $type) - drumps %hash, helped by $type
    my ($href, $type) = @_;
    my %h = %{$href};
    
    print "> hdump($type):\n";
    
    if ($type =~ /settings|flags/) {
        
        foreach (sort keys %h) {
            my $key   = $_;
            my $value = $h{$_};
            
            if ($value =~ /ARRAY/) { $value = join(", ", @{$value}); }
            print "\t$key", " " x (20 - length($key)), "$value\n";
        }
        
        
    } elsif ($type =~ /results/) {
        # $key = port, $value = failure|success
        
        print "\tPORT      RESULT\n";
        print "\t$_", " " x (10 - length($_)), ($h{$_}) ? "success" : "failure", "\n" foreach (sort { $a <=> $b } keys %h);
        
        # now a quick summary thanks to grep { }
        my @success = grep { $h{$_} } keys %h;
        my @failure = grep { not $h{$_} } keys %h;
        
        print(
            "> summary:\n",
            "\t ", $#failure + 1, " failed connections\n",
            "\t ", $#success + 1, " successful connections\n",
            "\t@success\n",
        );
        
    } else {
        # nothing
    }
    
    return;
}