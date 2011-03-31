#!/usr/bin/perl -w

use strict;
use warnings;
use 5.010;

use GD;

my $f1 = shift @ARGV // "sample1-r.jpg";
my $f2 = shift @ARGV // "sample5-e.jpg";

my %s = (
    m_image_x => 640,
    m_image_y => 480,
    
    m_image_itr => 250,
    m_deviation => 5,
);

my $results = compare_pictures($f1, $f2);

$results = ($results) ? "DIFFERENT" : "the same";

print "\$results: $results\n";

exit 0;

sub compare_pictures {
    # compare_pictures($f1, $f2) - compares image files $f1 and $f2, if they are different enough, we assume motion.. this is not perfect .. return 0|1 for same|diff
    my ($f1, $f2) = @_;
    my $results = 0;
    
    # HT to http://www.perlmonks.org/?node_id=576382
    my $ih1 = GD::Image->new($f1);
    my $ih2 = GD::Image->new($f2);
    
    my $iterations        = $s{m_image_itr};
    my $allowed_deviation = $iterations / $s{m_deviation};
    my $deviation         = 0;
    
    # size of input image
    my $x = $s{m_image_x}; 
    my $y = $s{m_image_y};
    
    for (my $i = 0; $i <= $iterations; $i++) {
        # generate some coords
        my $gx = int(rand($x));
        my $gy = int(rand($y));
        
        # pull actual values
        my $index1 = $ih1->getPixel($gx, $gy);
        my $index2 = $ih2->getPixel($gx, $gy);
        
        # compare values need to be broken down?
        my @r1 = $ih1->rgb($index1);
        my @r2 = $ih2->rgb($index2);
        
        #print "comparing: @r1 // @r2\n";
        
        $deviation++ unless @r1 ~~ @r2;
        
    }
    
    $results = ($deviation > $allowed_deviation) ? 1 : 0; # 1 is different, 0 is same

    print "deviation: $deviation\n";

    return $results;
}

