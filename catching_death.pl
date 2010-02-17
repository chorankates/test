#!/usr/bin/perl -w
#  catching_death.pl - testing and example of using eval to catch a die

use strict;
use warnings;
use 5.010;

my $ceil = 10;

for (my $i = 0; $i <= $ceil; $i++) {
    print "> $i ";
        
    my $rand = int(rand(2));
    
    if ($rand) {
        # catching some errors
        eval {
            die "inside an eval block";
        };
        print "\t caught it ($@), continuing\n";
    } else {
        # happy path
        print "\t avoided it..\n";
    }
    
}


exit 0;
