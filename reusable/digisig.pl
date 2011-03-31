#!/usr/bin/perl -w
#  digisig.pl - compare number of signed vs. unsigned exes

use strict;
use warnings;
use 5.010;

use File::Basename;
use File::Find;
use File::Spec;

use lib 'c:\\_dropbox\\My Dropbox\perl\_pm';
use lib 'c:\\test\\perl\\_pm';
use ironhide;

$| = 1; # flush

my $folder   = "C:\\Windows\\System32\\";
my $glob     = ".*\.exe\$";

my @skip     = ("C:\\System Volume Information\\", "C:\\Documents and Settings\\conor\\Local Settings\\Temp\\VMwareDnD"); # skip these folders

my $sigcheck = "C:\\util\\sysinternals\\sigcheck.exe -q -i ";

my @tp = (
    "Microsoft Corporation",
    "Microsoft Windows Component Publisher",
    "PWI, Inc.",
    "Webroot Software, Inc.",
    "Webroot Software",
    "CA",
    "McAfee, Inc.",
    "Adobe Systems, Incorporated",
    "NVIDIA Corporation",
    "Mozilla Corporation",
    "Apple Inc.",
    "Logitech",
    "WebEx Communications Inc.",
    "Cisco Systems, Inc.",
    "RealNetworks, Inc.",
    "Intuit Inc.",
    "VANTAGE TECHNOLOGIES SYSTEMS INTEGRATION LLC",
    "Intuit, Inc.",
    "Electronic Arts",
    "Blizzard Entertainment",
    "Sonic Solutions",
    "MainConcept AG",
    "InterActual Technologies INC",
    "DivX, Inc.",
    "Google Inc",
    "Google Inc.",
    "Intel Corporation",
    "Hewlett-Packard",
    "Hewlett-Packard Company",
    "SoftThinks",
    "Xceed Software Inc.",
    "Agere Systems",
    "SRS Labs, Inc",
    "Sun Microsystems, Inc.",
    "Adobe Systems Incorporated",
    "CyberLink",
    "SoftwareShield Technologies Inc.",
    "Conexant Systems, Inc.",
    "InstallShield Software Corporation",
    "GEAR Software Inc.",
    "Symantec Corporation",
    "WildTangent Inc.",
    "muvee Technologies Pte Ltd",
    "Macrovision Corporation",
    "Alps Electric Co., LTD.",
    "Broadcom Corporation",
    "CANON INC.",
    "AnchorFree Inc",
);

my (@csigned, @esigned, @signed, @unsigned, @tpsigned); # catalog, error, self-signed, unsigned, self-signed and recognized by TP

my @t1 = localtime;
print "% $0 started at ", nicetime(\@t1), "\n";

my %files; # hash of hashes, primary key is ffp (subkeys are filename, signed/unsigned, signature type, is_tp)

find(
    sub {
        my $name   = basename($_);
        my $folder = dirname($_);
        my $ffp    = File::Spec->canonpath($File::Find::name);
        
        return if -d $name or -d $ffp;
        return unless $name =~ /$glob/i;
        
        return if @skip ~~ $folder; # skipping some unnecessary folders
    
        my $cmd = "$sigcheck \"$ffp\"";
        #print "\$cmd: $cmd\n";
        
        my @results = `$cmd`;
        my $lresults = join "", @results;
    
        # according to PadWalker:
        # \cI <-- beginning of line (\cI\cI for indented entries)
        # \cJ <-- end of line
	
        
        while ($lresults =~ /\cI(\w*):.*?(\w.*)\cJ/ig) { 
            # matches: Verified:       Signed
            # this is right.  run this and set all values based on it.
            my $key   = $1;
            my $value = $2;
            
			#print "\$key: $key\n";
			#print "\$value: $value\n";
            
            $files{$ffp}{$key} = $value;
		}
		
		if ($lresults =~ /\cI(\w*):\cJ\cI\cI(.*)\cJ/ig) { 
			# matches: Signer:\n		Microsoft Windows Component Publisher
			$files{$ffp}{$1} = (defined $2) ? $2 : "??";
		}
    
        # basic determination if we are signed
        my $signed    = (defined $files{$ffp}{Verified})  ? $files{$ffp}{Verified}  : "??";
        my $publisher = (defined $files{$ffp}{Publisher}) ? $files{$ffp}{Publisher} : "??";
        my $catalog   = (defined $files{$ffp}{Catalog})   ? $files{$ffp}{Catalog}   : "??";
        my $sign_type = ($catalog =~ /.*cat$/i)         ? "catalog"               : "self"; # make this a little easier on my self
        my $signer    = $files{$ffp}{Signers}; # will contain the first entry in the list following the key "Signers:"        
        
		print(
			"keying off of:\n",
			"\t\$signed:    '$signed'\n",
			"\t\$publisher: '$publisher'\n",
			"\t\$sign_type: '$sign_type'\n",
			"\t\$catalog:   '$catalog'\n",
			"\t\$signer:    '$signer'\n",
		) if 0;
		
        # changed all $publisher refrences to $signer..
        if ($signed =~ /Signed/) {
            if ($sign_type eq "catalog") {
                # this file is signed, but will not be recognized by TP
                push @csigned, $ffp;
                print "\tCATALOG-SIGNED::$signer: $ffp\n";
                
            } elsif ($sign_type eq "self") {
                # this file is signed by itself, TP will recognize this
				
               if ($signer ~~ @tp) {
                    print "\tSELF-SIGNED/TP::$signer: $ffp\n";
                    push @tpsigned, $ffp;
                } else {
                    print "\tSELF-SIGNED::$signer: $ffp\n";
                    push @signed, $ffp;
                }
                
            }
            # end of signed handling
        } elsif ($signed =~ /Unsigned/) {
            print "\tUNSIGNED: $ffp\n";
            push @unsigned, $ffp;
        } elsif ($signed =~ /(Unverified|Invalid Chain|Untrusted Root)/) {
            print "\tSIGNED, but something wrong::$signed: $ffp\n";
            push @esigned, $ffp;
        } else {
            print "ERROR:: unrecognized response for '$ffp', skipping\n";
            push @unsigned, $ffp;
        }
        
    },
    $folder,
);

my $s_count = $#signed + 1;
my $c_count = $#csigned + 1;
my $t_count = $#tpsigned + 1;
my $u_count = $#unsigned + 1;

my $total = $s_count + $c_count + $t_count + $u_count;

print(
    "> results:\n",
    "\tcatalog signed (NOT recognized by TP): $c_count (", int(($c_count / $total) * 100) ,"%)\n",
    "\tself signed (NOT recognized by TP):    $s_count (", int(($s_count / $total) * 100) ,"%)\n",
    "\tself signed (recognized by TP):        $t_count (", int(($t_count / $total) * 100) ,"%)\n",
    "\tunsigned (or sig not valid):           $u_count (", int(($u_count / $total) * 100), "%)\n",
    "\n\ttotal                                $total\n",
    );
	
# lets do a quick search on %files, looking for the key 'signer', display the top 10
if (1) { 
    my %publishers;
    my %signers;
    
    foreach (keys %files) {
        #my $ffp       = $_;
        #$ffp =~ s/\\/\\\\/g;
        
        
        my $ffp = $_;
        
        #print "\$publisher: ", exists $files{$ffp}{Publisher}, ": $files{$ffp}{Publisher}\n";
        #print "\$signers:   ", exists $files{$ffp}{Signers},   ": $files{$ffp}{Signers}\n";
        
        my $publisher = $files{$ffp}{Publisher};
        my $signer    = $files{$ffp}{Signers};
        
        # here's the magic..
        $publishers{$publisher}++ if $publisher;
        $signers{$signer}++       if $signer;
    }
    
    #$publishers{$files{$_}{Publisher}}++ foreach (keys %files); # this is the way we want to do it, but it's not working

    my $i       = 0;
    my $ceiling = 10;

    print "> top $ceiling publishers\n";
    foreach (sort keys %publishers) {
        $i++;
        print "\t$_:", " " x (15 - length($_)), "$publishers{$_}\n" ;
        last if $i <= $ceiling;
    }

    $i = 0;
    
    #$signers{$files{$_}{Signers}}++ foreach (keys %files); 

    print "> top $ceiling signers\n";
    foreach (sort keys %signers) {
        $i++;
        print "\t$_:", " " x (15 - length($_)), "$signers{$_}\n" ;
        last if $i <= $ceiling;
    }


    # also top signers not recognized by tp
    $i = 0;
    my %signers_no_tp;
    $signers_no_tp{$files{$_}{Signers}}++ foreach (@csigned);

    print "> top $ceiling signers NOT recognized by TP\n";
    foreach (sort keys %signers_no_tp) {
        $i++;
        print "\t$_:", " " x (15 - length($_)), "$signers_no_tp{$_}\n" ;
        last if $i <= $ceiling;
    }

}

my @t2 = localtime;
print "% $0 done at ", nicetime(\@t2), " taken ", timetaken(\@t1, \@t2), "\n";

exit 0;