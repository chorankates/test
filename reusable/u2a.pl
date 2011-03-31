#!/usr/bin/perl -w
# u2a.pl - converts unicode text files into ascii (a number of methods depending on user needs)

use strict;
use warnings;
use 5.010;

use File::Spec;
use Getopt::Long;
use Unicode::String;

my (%f, %s);

%s = (
    verbose => 1, # 0 <= n <=3  
);

GetOptions(\%f, "help", "in:s", "out:s", "type:s", "string:s");

$s{type}   = (defined $f{type}) ? $f{type} : "string";
$s{string} = (defined $f{string}) ? $f{string} : "+lsctzùïåé}"; 

$s{in}  = File::Spec->rel2abs($f{in})  if defined $f{in};
$s{out} = File::Spec->rel2abs($f{out}) if defined $f{out};

print "% $0\n";

print "> settings:\n";
print "\t$_", " " x (15 - length($_)), "$s{$_}\n" foreach (sort keys %s);

my $results;

if ($s{type} =~ /file/i) { 
    print "> calling \&u2a(file, ($s{in}, $s{out})):\n";

    my @a = ($s{in}, $s{out});

    $results = &u2a("file", \@a);
} else {
    # assuming type=string
    
    print "> calling \&u2a(string, $s{string}):\n";
    
    my @a = ($s{string}); # this seems a little weird..
    
    $results = &u2a("string", \@a); 
}



print "> results: $results\n";

exit 0;

########## subs below

sub u2a {
    # u2a($type, \@options) - performs generic Unicode->ANSI conversion. if $type is 'file', \@options is (in_file, out_file), if $type is 'string', \@options is (string). return is out_filename, decoded string, or undef for error
    my ($type, $aref) = @_;
    my @options = @{$aref};

    my ($err, $results) = (0, 1);
    
    if ($type =~ /file/i) { 
        my ($infile, $outfile) = @options;
        
        my ($reader, $writer); # using $scalars for file handles
        my (@in, @out); # we don't really need an in.. yet
    
    
        # get the contents into an array, do this line by line
        if ($infile) {
            open ($reader, '<', $infile) or $err = $!;
        
            if ($err) {
                warn "ERROR:: unable to open '$infile':$err\n";
                return undef;
            }
        
            while (<$reader>) {
                chomp(my $line = $_);
        
                #print "i: $line\n";
                $line =~ s/(.)/Unicode::String::utf8($1)->latin1()/eg; # credit: http://www.nntp.perl.org/group/perl.beginners.cgi/2006/01/msg12527.html
                $line =~ s/\0//g; # credit: http://en.wikipedia.org/wiki/Null_character
                #print "o: $line\n";
            
                push @out, $line;
            }
        # end of $infile loop
        }
    
        if ($outfile) {
            open ($writer, '>', $outfile) or $err = $!;
            
            if ($err) {
                warn "ERROR:: unable to open '$outfile':$err\n";
                return 1;
            }
        
            print $writer $_ foreach (@out);
            
        }
        
        $results = (-e $outfile) ? $outfile : undef; # god i love ternarys
        
    } elsif ($type =~ /string/i) {
        my $string = $options[0]; # really only need an aref for file conversions
        
        $string =~ s/(.)/Unicode::String::utf8($1)->latin1()/eg; # credit: http://www.nntp.perl.org/group/perl.beginners.cgi/2006/01/msg12527.html
        $string =~ s/\0//g; # credit: http://en.wikipedia.org/wiki/Null_character

        $results = (defined $string) ? $string : undef;
        
    } else {
        warn "ERROR:: type '$type' is not known\n";
        return undef;
    }
    
    
    return $results;
}

