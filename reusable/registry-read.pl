#!/usr/bin/perl -w
# registry-read.pl - registry reading on win32

use strict;
use warnings;
use Win32::TieRegistry; # what we actually need

# need to use the full form HKEY_LOCAL_MACHINE instead of HKLM
my $key = "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartMenu\\StartMenu\\Bitmap";

print "Start Menu bitmap: ", cfu_regread($key);

exit 0;

sub cfu_regread {
	# cfu_regread($key) where $key = HKLM\Software\Webroot\SpySweeper\id
	# returns the value of 'id'
	my $key = shift @_; my $output;
	
	$output = $Registry->{$key};
	
	return $output;
}