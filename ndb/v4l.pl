#!/usr/bin/perl -w
#  v4l.pl - sandbox for Video::Capture::V4l testing

use strict;
use warnings;
use 5.010;

use Video::Capture::V4l;
#use Video::Capture::V4l::Imager

my $grab = Video::Capture::V4l->new() or die "DIE:: unable to open /dev/video0: $!";

my $frame = $grab->capture(0, 640, 480);

$grab->sync(0);

print "foo\n";

exit 0;