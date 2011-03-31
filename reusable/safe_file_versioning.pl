#!/usr/bin/perl -w
#   safe_file_versioning.pl 

use strict;
use warnings;
use 5.010;
use Win32::Exe;

# trap errors coming from Win32::Exe in an eval block

my $param = shift @ARGV || ".";

if (-d $param) {
    my $folder = $param;
    opendir(DIR, $folder) or die "unable to open '$folder':$!";
    while ($_ = readdir(DIR)) {
        my $ffp = $folder . $_;
        next if $_ eq "." or $_ eq "..";
        next if -d $ffp;
        
        my $return = s_fileversion($ffp);
        print "$return \t $_\n";
    }
    closedir(DIR);
}
elsif (-f $param) {
    my $file = $param;
    my $return = s_fileversion($file);
    print "$return \t $file\n";
}

exit 0;

sub s_fileversion {
    # s_fileversion($filename) - return file version OR '?'
    my $file = shift @_;
    my $version;
    
    return "?" unless $file =~ /.*\.(exe|dll|ocx|)$/i; # we know these files won't have versions
    
    # ok, eval block
    eval {
        my $worker = Win32::Exe->new($file); # catch all
        
        my $file_version    = $worker->version_info->get('FileVersion');
        my $product_version = $worker->version_info->get('ProductVersion'); 
    
        $version = $file_version || $product_version;
    
        $version =~ tr/,/\./; # replace commas with periods
        
    };
    if ($@) { return "?"; }
    else { return $version; }
    
}