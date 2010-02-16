#!/usr/bin/perl -w
# hosts_minder.pl - cron job that cleans up /etc/hosts when it's been munged

# this is a change

use strict;
use warnings;
use 5.010;

# flow:
# diff /etc/hosts and /etc/hosts.kg, if same, bail out
# determine if a perl process is running (and thus we expect hosts to be munged), if so, bail out
# no perl process is running and /etc/hosts and /etc/hosts.kg are different, overwrite /etc/hosts with /etc/hosts.kg

my %s = (
  hosts    => "/etc/hosts",
  hosts_kg => "/etc/hosts.kg",
  
  rpre => "perl", # to be used in: ps aux | grep $rpre, to search for running perl processes
  
  caller => "console",
);

$s{caller} = $1 if @ARGV ~~ /caller=(.*)/i; #


my $diff = `diff $s{hosts} $s{hosts_kg}`;
print "\$diff: '$diff'\n" if $s{verbose};

# bail out if no diff
unless ($diff) { 
    warn "> bailing out (no $s{hosts} differences)" if $s{caller} eq "console";
    exit 0;
}

my @rp = `ps aux | grep $s{rpre}`;
if ($s{verbose}) { print "[@] $_" foreach (@rp); }


# bail out if running perl process
if ($#rp > 2) {
    # 1 for self, 1 for system call, 1 for actual grep, any more than that and someone else is running
    warn "> bailing out (currently running perl)" if $s{caller} eq "console";;
    exit 0;
}

# if we're still running, reset the hosts file
# also print something so we get an email
if ($diff and $#rp <= 2) {
    my $results = `cp $s{hosts_kg} $s{hosts}` // "success";
    print "> hosts_minder had to reset $s{hosts}: '$results'\n";
    exit 0;
}

print "> no changes made by hosts_minder.pl, OK\n" if $s{caller} eq "console";

exit 1;
