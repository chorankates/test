#!/usr/bin/perl -w
# file_info.t -- tests for get_info_from_filename() in dex::util

# this is a bad set of tests.. they will only catch the most flagrant bugs

use strict;
use warnings;

use Test::More qw(no_plan);

use lib '../lib';
use dex::util;

# hash because we don't know how big the source file will be
my %external_names = get_names('file_info-names.txt');

# array because this is just to ensure that certain tests are exercised
my %static_names = (
    'Burn Notice - 01 - 14 - This is Fairly Simple.mp3'  => '/media/pdisk1/tv/Burn Notice/Burn Notice - Season 01/',
    'Burn Notice - 2 - 11 - Missing a prepended zero in series' => '/media/pdisk1/tv/Burn Notice/Burn Notice - Season 02/',
    'Burn Notice - 02 - 09 - Missing prepended zero in episode' => '/media/pdisk1/tv/Burn Notice/Burn Notice - Season 02/',
    'Burn Notice - 02 - 14 - This Episode Name has a - in it' => '/media/pdisk1/tv/Burn Notice/Burn Notice - Season 01/',
    #'Foo - Bar', => '/media/pdisk1/tv/Foo/',
    #'Archer - 04 - Not enough information' => '/media/pdisk1/tv/Archer/Archer - Season 02/',
    '24 - 07 - 24 - 7 a.m. - 8 a.m..avi' => '/media/pdisk1/tv/24/24 - Season 07/24 - 07 - 24 - 7 a.m. - 8 a.m..avi', # we can fix this by using @a[3...] as $episode_title
    'The X-Files - 04 - 05 - This is a test.avi' => '/media/pdisk1/tv/The X-Files/The X-Files - Season 04/', # we can fix this one by saying that $show is based on the foldername off of the root and stripping that out of the match text
);

my %names;
foreach my $name (keys %external_names) {
    my $dir = $external_names{$name};
    $names{$name} = $dir;
}
foreach my $name (keys %static_names) {
    my $dir = $static_names{$name};
    $names{$name} = $dir;
}

# tv tests only for now
foreach my $name (keys %names) {
    my $type     = 'tv';
    my $base_dir = $names{$name};
    my %results = get_info_from_filename($base_dir, $name, $type);
    
    ##need to do subtests here
    subtest $name => sub {
        is(defined $results{show},    1, 'show title defined');
        is(defined $results{title},   1, 'episode title defined');
        is(defined $results{season},  1, 'season # defined');
        is(defined $results{episode}, 1, 'episode # defined');
        is(defined $results{ctime},   1, 'added ctime defined');
        is(defined $results{uid},     1, 'UID defined');
        fail ("error detected: $results{error}") if defined $results{error};
    };
    
}

exit;

## subs below
sub get_names {
    # get_names($filename) - returns a %hash based on mock filenames in $filename
    my $file = shift;
    my %h;
    
    return %h unless -f $file;
    
    my $fh;
    open($fh, '<', $file) or return {};
    
    my ($ffp, $name, $dir);
    while (<$fh>) {
        # need to account for multiple listings (really just CRLF separated and ls/dir output)
        chomp(my $line = $_);
        if ($line) {
            $ffp = $line;
            $name = basename($ffp);
            $dir  = basedir($ffp);
            
            $h{$name} = $dir;
            
        } else {
            next; 
        }
        
    }
    
    close($fh);
    
    return %h;
}