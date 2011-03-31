#!/usr/bin/perl -w
#  registry-write.pl - testbed for registry writing

use strict;
use warnings;
use 5.010;
use Win32::TieRegistry(Delimiter => "/");

my $ffp = shift @ARGV;
die "syntax: $0 <file>" unless -e $ffp;

my $key  = "HKEY_LOCAL_MACHINE/SOFTWARE/Microsoft/Windows/CurrentVersion/RunOnce";
my $name = "breakaway.pl_add";
my $parameters = "/foo";
my $data = $ffp . " " . $parameters;

my $type = 'startup entry';

my $results = b_put_registry($key, $name, $type, $data);

print "\$results: $results\n";

exit 0;

sub b_put_registry {
    # b_put_registry($key, $name, $data); - where key is the parent key, $name/$type - returns 0|1 success|failure
    # ex: b_put_registry("HKEY_LOCAL_MACHINE/SOFTWARE/Microsoft/Windows/CurrentVersion/RunOnce", "startup entry", "format.exe c: /y")
    my ($key, $name, $type, $data) = @_;
    my $results;
    
    print(
        "\t\$key  = $key\n",
        "\t\$name = $name\n",
	"\t\$type = $type\n",
        "\t\$data = $data\n",
    ) if 1;
    
    my $r = $Registry->{$key . "/" . $name} = $data;
	#$r{'/' . $name} = $data;
    
    
    $results = 0; # fuzzed
    
    return $results;
}

