#!/usr/bin/perl -w
#  nerdiestdoorbell.pl - project to send XMPP messages to specified users when motion is detected on a local webcam
#            i.e. a nerdy version of the doorbell
# prereqs:
#  take_picture.py - python script to take a picture from webcam
#  python-opencv   - python package to interface with camera .. ubuntu can sudo apt-get install this
#  libgd2-xpm-dev  - image libraries for GD .. ubuntu can sudo apt-get install this too
#  libssl-dev      - SSL binaries .. ubuntu can sudo apt-get install
#  Crypt::SSLeay   - SSL crypto package from CPAN
#  IO::Socket:SSL  - SSL wrapper
#  XML::Stream     - XMPP dependency
#
# 
# run 'perl -c nerdiestdoorbell.pl' for any machine specific dependencies

# TODO
#   need an interface for email and sms (google voice api?)
#   write an interrupt handler to cleanup

use strict;
use warnings;
use 5.010;

use File::Basename;
use File::Spec;  # this can really only run on unix (GD), but still.. FFP FTW
use Getopt::Long; 
use GD;          # it sure seems like magic
use Net::XMPP;   # to connect to gtalk

use ironhide;

$| = 1;
 
my (%f, %s); # flags, settings

%s = (
    verbose => 1,    
    home    => "/home/your/", # can be overloaded
    
    # XMPP settings
    x_user     => "",
    x_password => "",
    x_domain   => "talk.google.com",
    x_name     => "gmail.com",
    x_port     => 5222, # yes, requires TLS
    x_resource => "test",
    x_throttle => 60, # number of seconds between messages.. 
    x_last_msg => time(), # so we don't send a message for at least 60 seconds
    
    x_targets => [ "you@yours.com", ], # who to message
    x_messages => [ "OH TEH NOES!!!! MOTION DETECTED", "Houston, we have a problem.", "I sense a disturbance in the force..", "There's a N+-100% chance that someone is here.", "Whatever you do, don't look behind you."], # list of semi amusing messages to send, one chosen randomly for each send_alert()
    
    # motion settings
    m_device      => "/dev/video0",
    m_cmd         => "python take_picture.py", # how to call python, will append dynamic filename
    m_sleep       => 5,      # how often should we check the camera?
    m_ceiling     => 0,      # if set to 0, will loop forever
    m_diff_found  => 0,      # initializing so we remember this value
    m_image_x     => 640,    # m4400 is 640x480, greed is 640x480
    m_image_y     => 480,
    m_image_itr   => 10_000, # how many pixels to compare.. the bigger the sample the better, 640x480 yields 307,200 possibles
    m_deviation   => 2,      # $s{m_image_itr} / n    ... 5 = 20%, 3 = 33%, etc.. 50% is working well at cclb
    m_p_deviation => 10,     # if not 0, enables and sets RGB deviation detection per pixel
);

GetOptions(\%f, "help", "verbose:i", "j_user:s", "j_domain:s", "j_resource:s", "j_password:s", "m_sleep:s", "m_device:i", "m_ceiling:i", "home:s", "m_image_itr:i", "m_image_x:i", "m_image_y:i", "m_deviation:s", "m_p_deviation:s", "x_throttle:s");
if ($f{help}) { m_help(); exit 0; }
$s{$_} = $f{$_} foreach (keys %f);

# make sure we're on unix
die "DIE:: only working on *nix for now" unless $^O =~ /linux/i;

# make sure a webcam is attached
die "DIE:: unable to locate webcam" unless -e $s{m_device};


my (@t1, @t2); @t1 = localtime;
print "% mcap started at  ", &nicetime(\@t1, "time"), "\n";

hdump(\%f, "flags")    if $s{verbose} ge 2;
hdump(\%s, "settings") if $s{verbose} ge 2;

my $loop = 0;
# super loop
while (1) {
    print $loop . "  take_a_picture()...\n" if $s{verbose} ge 1;

    # takes about 2 seconds per picture
    my $f1 = take_a_picture();
    my $f2 = $s{m_last_picture} // &get_last_picture(); # if we're in a long loop (which we usually will be), this value is in hash. 
    
    print "\tcomparing '", basename($f1), "', '", basename($f2), "'\n" if $s{verbose} ge 2;
    my ($different, $pcent) = compare_pictures($f1, $f2); # 1 is true
    
    if ($different) {
        print "\t" . "DIFF!\n";
        
        $pcent = 0 unless $pcent;
        
        my $send_results = send_alert($f1, $pcent); 
        warn "WARN:: messages may not have been sent..\n" if $send_results; # 0 is success
        $s{m_diff_found}++;
    }
    
    # remove the old last photo
    if (-e $s{m_last_picture}) {
        print "\tremoving '$s{m_last_picture}\n" if $s{verbose} ge 3;
        unlink($s{m_last_picture}) or warn "WARN:: unable to remove '$s{m_last_picture}'\n";
    }
    
    $s{m_last_picture} = $f1;
    $loop++;
    
    if ($s{m_ceiling}) { last if $loop >= $s{m_ceiling}; }
    
    print "\tsleeping $s{m_sleep}." if $s{verbose} ge 2;
    sleep $s{m_sleep};
    print "..\n" if $s{verbose} ge 2;
}

print "> finished after loops > '$s{m_ceiling}'\n";

@t2 = localtime;
print "% mcap finished at ", &nicetime(\@t2), "time", " took ", &timetaken(\@t1, \@t2,), "\n";

exit 0;

######## subs below

sub hdump {
    # hdump(\%hash, $type) - dumps %hash, helped by $type
    my ($href, $type) = @_;
    my %h = %{$href};
    
    print "> hdump($type):\n";
    
    foreach (sort keys %h) {
        print "\t$_", " " x (20 - length($_));
        
        print "$h{$_}\n"    unless $h{$_} =~ /array/i;
        print "@{$h{$_}}\n" if     $h{$_} =~ /array/i;
    }
    
    return;
}


sub send_alert {
    # send_alert($filename, $deviation_pcent) - pulls rest of the needful out of %s hash. return 0|1 for success|failure
    my ($filename, $deviation_pcent) = @_;
    my $results;

    # we're pulling from %s, but still, a little abstraction
    # server settings
    my $hostname      = $s{x_domain};
    my $port          = $s{x_port};
    my $componentname = $s{x_name};
    my $tls           = 1; # this should almost always be 1
    # auth settings
    my $user     = $s{x_user};
    my $password = $s{x_password};
    my $resource = $s{x_resource};
    # message settings
    my @targets  = @{$s{x_targets}};
    my @msgs     = @{$s{x_messages}};
    my $msg_txt  = $msgs[int(rand($#msgs))] . ", deviation: $deviation_pcent%, filename: $filename"; 

    # check throttle
    my $lt1 = time();
    my $lt2 = $s{x_last_msg}; # this also prevents a msg from being sent for the first minute.. disabling throttle is a good idea on a long sleep timer

    my $throttle = $s{x_throttle};
    my $sec_diff = $lt1 - $lt2;
    
    
    
    if ($sec_diff <= $throttle and $throttle != 0) {
        print "\tthrottling XMPP messages, t$throttle / s$sec_diff\n" if $s{verbose} ge 1;
        return 0; # returning success
    }

    # connect to the server
    my $xmpp = Net::XMPP::Client->new();
    my $status = $xmpp->Connect(
        hostname       => $hostname,
        port           => $port,
        componentname  => $componentname,
        connectiontype => "tcpip", # when would it be anything else?
        tls            => $tls,
    ) or die "DIE:: cannot connect: $!\n";
    
    # change hostname .. kind of
    my $sid = $xmpp->{SESSION}->{id};
    $xmpp->{STREAM}->{SIDS}->{$sid}->{hostname} = $s{x_name};
    
    # authenticate 
    my @auth = $xmpp->AuthSend(
        username => $user,
        password => $password,
        resource => $resource, # this identifies the sender
    );
    
    die "DIE:: authorization failed: $auth[0] - $auth[1]" if $auth[0] ne "ok";
    
    # send a message   
    foreach (@targets) {
        my $lresults = 0; 
        print "\tsending alert to '$_'..";
        
        $xmpp->MessageSend(
            to       => $_,
            body     => $msg_txt,
            resource => $resource, # could be used for sending to only a certain location, but if it doesn't match anything the user has, it delivers to all
        ) or $results = $!;
        
        $lresults = ($lresults) ? " FAILED: $lresults" : " OK!";
        print " $results\n",
        
    }
    
    # endup
    $xmpp->Disconnect();
    
    # throttle
    # my @lt1 = localtime;
    $s{x_last_msg} = time();
    
    
    return;
}

sub take_a_picture {
    # take_a_picture() - no params, we'll pull them out of %s
    # i feel dirty, but pythons modules are superior.. OUTSOURCED
    my ($filename, $cmd);
    
    my @lt1 = localtime; # need to define this locally so it gets updated on every run
    
    my $ts = nicetime(\@lt1, "both");
    
    $filename = "mcap-" . $ts . "_diff.jpg";
    
    $cmd = $s{m_cmd} . " $filename";
    
    my $results = `$cmd 2>&1`; # capture and suppress STDOUT and STDERR
    
    $filename = File::Spec->catfile($s{home}, $filename);
    
    warn "WARN:: no picture taken\n" unless -e $filename;
    
    return $filename;
}

sub get_last_picture {
    # get_last_picture() - no parameters, returns the ffp of the last filename found
    my $filename;
   
    my $glob = $s{home} . "*.jpg";
    
    my @files = glob($glob);
    
    $filename = $files[-1]; # this is problematic if there ever isn't a jpg in this folder.. die for now
    die "DIE:: no last picture found. put any .jpg of dimension '$s{m_image_x}x$s{m_image_y}' in $s{home} to resolve" unless -f $filename;
    
    $s{m_last_picture} = $filename;
    #$filename = File::Spec->catfile($s{home}, $filename); # if the glob includes dir, so do results
    
    return $filename;
}

sub help {
    # need to write a helpfile.. 
    #GetOptions(\%f, "help", "verbose:i", "j_user:s", "j_domain:s", "j_resource:s", "j_password:s", "m_sleep:s", "m_device:i", "m_ceiling:i", "home:s", "m_image_itr:i", "m_image_x:i", "m_image_y:i", "m_deviation:i");
}

sub compare_pictures {
    # compare_pictures($f1, $f2) - compares image files $f1 and $f2, if they are different enough, we assume motion.. this is not perfect .. return (0|1 for same|diff, $deviation_pcent)
    my ($f1, $f2) = @_;
    my $results = 0;
    
    warn "WARN:: unable to find '$f1'\n" and return 1 unless -e $f1;
    warn "WARN:: unable to find '$f2'\n" and return 1 unless -e $f2;
    
    
    # HT to http://www.perlmonks.org/?node_id=576382
    my $ih1 = GD::Image->new($f1);
    my $ih2 = GD::Image->new($f2);
  
    my $iterations        = $s{m_image_itr};
    my $allowed_deviation = int($iterations / $s{m_deviation}); # 1.000001  seems to be a good number so far.. looks like need to increase the sample size again or start RGB deviation
    my $deviation         = 0;
    
    # size of input image
    my $x = $s{m_image_x}; 
    my $y = $s{m_image_y};
    
    for (my $i = 0; $i < $iterations; $i++) {
        # generate some coords
        my $gx = int(rand($x));
        my $gy = int(rand($y));
        
        my ($index1, $index2, @r1, @r2); # eval scope hack
        
        eval {
            # pull actual values
            $index1 = $ih1->getPixel($gx, $gy);
            $index2 = $ih2->getPixel($gx, $gy);
            print "\tcomparing '$index1' and '$index2'\n" if $s{verbose} ge 3;
            
            # compare values need to be broken down to RGB
            @r1 = $ih1->rgb($index1);
            @r2 = $ih2->rgb($index2);
            
            print "\tcomparing '@r1' and '@r2'\n" if $s{verbose} ge 4;
        };
        
        if ($@) { warn "WARN:: unable to grab pixels: $@"; return 1; } 
        
        # pixel RGB deviation detection.. it works
        if ($s{m_p_deviation}) {
            # this could be rewritten as a map
            my $p_deviation = $s{m_p_deviation}; # allowed pixel deviation
            my $l_deviation = 0;                 # set this if $diff  >= $p_deviation (where $diff is the difference between each RGB value of each pixel)
                    
            for (my $i = 0; $i < $#r1; $i++) {
                my $one = $r1[$i];
                my $two = $r2[$i];
                
                my $diff = $one - $two;
                   $diff = ($diff < 0) ? $diff * -1 : $diff;
                
                $l_deviation = 1 if $diff >= $p_deviation;
            }
            
            $deviation++ if $l_deviation; 
            
        } else {
            # we could also compare $index1 and $index2 .. and apply some deviation there?
            $deviation++ unless @r1 ~~ @r2;
        }
        
    }
    
    $results = ($deviation > $allowed_deviation) ? 1 : 0; # 1 is different, 0 is same

    my $deviation_pcent = int(($deviation / $iterations) * 100); # we should really be keying off of this

    print "\tdeviation: d$deviation / a$allowed_deviation / i$iterations = $deviation_pcent%\n" if $s{verbose} ge 1;

    return $results, $deviation_pcent;
}

