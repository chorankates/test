#!/usr/bin/perl -w
#  depends.pl - scans the directory passed for 'use' entries in *.pl. makes it easy to determine what packages each environment will need

use strict;
use warnings;
use 5.010;

use Cwd;
use File::Find; # wish we didn't have to use this, but it's pretty global
use File::Spec; # same

my $dir = (@ARGV) ? shift @ARGV : File::Spec->canonpath(Cwd::getcwd);
my (@files, %d); 

print "% $0 - checking '$dir'..";

# File::Find to look for *.pl/*.cgi recursively
find(
    sub {
        my $ffp = File::Spec->canonpath($File::Find::name);
        return unless -f $ffp and $ffp =~ /\.(pl|cgi)$/i;
        push @files, $ffp;
    },
    $dir # outside the inline sub
);

print "\n\tdone, found ", $#files + 1, " files.\n";

print "> examining file contents..";

# now iterate the files and find 'use' entries
foreach my $ffp (@files) {   
    # slurping for now
    
    open(FILE, '<', $ffp) or next;
    my @slurp = <FILE>;
    close(FILE);
    
    foreach (@slurp) { $d{$1}++ if $_ =~ /^use\s?(.*);$/i; }
}

print "\n\tdone, found ", scalar keys %d, " unique packages.\n";


print "count ::", " " x (10 - length("count")), "package\n";
foreach (reverse sort { $d{$a} <=> $d{$b} } keys %d) {
    my $package = $_;
    my $count   = $d{$_};
    print "$count :: ", " " x (10 - length($count)), $package, "\n";
    
}

print "% $0 - done.\n";

exit 0;
