#!/usr/bin/perl -w
## id3sync.pl - iterates mp3s and synchronizes id3v1 and id3v2 tags

use strict;
use warnings;
use 5.010;

use Data::Dumper;
use File::Find;
use File::Spec;
use Cwd;
use Getopt::Long;
use MP3::Tag;

use lib '/home/choran-kates/Dropbox/perl/_pm';
use lib '/home/conor/Dropbox/perl/_pm';
use lib 'C:\Dropbox\perl\_pm';
use lib 'C:\_dropbox\My Dropbox\perl\_pm';
use ironhide;

## initialize variables
%C::settings = (
    verbose => 1, # 0 <= 2
    
    folder  => Cwd::getcwd(), # folder to examine, can be overloaded by CLI
    
    fields  => [
        'artist',
        'title',
        'album',
        'track', # track#
        'comment',
        #'year',
        #'genre'
    ], # fields to compare (must be supported in id3)
    
    win         => '1', # which version of id3 should win if both versions contain data, but they are different
    interactive => 1,   # if true, prompts the user on what change to make for each file found
    
    skips => [
        
    ], # if a file matches any of these regexes, it will be skipped
);

my @t1 = localtime;

GetOptions(\%C::flags, "help", "verbose:i", "folder:s", "win:i");
$C::settings{$_} = $C::flags{$_} foreach (keys %C::flags);

print "% $0 started at ", nicetime(\@t1, "time"), "\n" if $C::settings{verbose} ge 1;

print Dumper(\%C::flags)    if $C::settings{verbose} ge 2;
print Dumper(\%C::settings) if $C::settings{verbose} ge 1; 

## determine which files to look at
%D::mp3 = (); # hash key = ffp, value = filename (need it this way in case we have multiple files with the same name in different directories)

print "> indexing '$C::settings{folder}'..\n" if $C::settings{verbose} ge 1;

find(
    sub {
        return unless $_ =~ /\.mp3$/;
        
        my $file = $_;
        my $ffp  = File::Spec->canonpath($File::Find::name);
        
        return if is_skip($ffp); # check the @C::settings{skip} list
        return unless -f $ffp;   # just to make sure we don't add any directories (that happen to end in .mp3)
        
        #print "\tadding '$ffp'\n" if $C::settings{verbose} ge 2;
        print "\tadding '$file'\n" if $C::settings{verbose} ge 2;
        
        $D::mp3{$ffp} = $file;
    },
    $C::settings{folder},
);

my @lt1 = localtime;
print "  found ", scalar keys %D::mp3, " mp3s in ", timetaken(\@t1, \@lt1), "\n" if $C::settings{verbose} ge 1;

## look at these files
print "> examining mp3s found..\n" if $C::settings{verbose} ge  1;
foreach (sort keys %D::mp3) {
    # sorting is a performance hit.. maybe we should only sort in interactive mode?
    
    my $ffp  = $_;
    my $file = $D::mp3{$ffp};
    
    print "\tprocessing '$ffp'\n" if $C::settings{verbose} ge 2;
    
    my (%v1, %v2, %vN); # id3v1 tags, id3v2 tags, new tags
    
    %v1 = get_id3($ffp, 'id3v1');
    %v2 = get_id3($ffp, 'id3v2');
    
    ## do some comparison -- need to do it based on the keys known to be in id3
    foreach (keys %v1) {
        my @fields = @{$C::settings{fields}};
        my $field  = $_;

        unless (@fields ~~ /$field/) {
            # smartmatching ftw.. love me some 5.10
            print "\t  skipping '$field'\n" if $C::settings{verbose} ge 3;
            next;
        }
        
        my $v1 = $v1{$field} // 'unset';
           $v1 = ($v1 eq '') ?  'unset' : $v1;
           
        my $v2 = $v2{$field} // 'unset';
           $v2 = ($v2 eq '') ?  'unset' : $v2;
        
        
        
        if ($v1 eq $v2 and $v1 ne 'unset') {
            # fields are already in sync, nothing to do
            print "\t  '$field' already in sync: $v1\n" if $C::settings{verbose} ge 3;
            $vN{$field} = $v1;
            
            $D::stats{already_in_sync}++;
            
        } elsif ($v1 eq 'unset' and $v1 ne 'unset') {
            # id3v1 is unset, but we have value in id3v2
            print "\t  '$field' in v2 is set to '$v2', synching\n" if $C::settings{verbose} ge 3;
            $vN{$field} = $v2;
            
            $D::stats{v2_synched_to_v1}++;
            
        } elsif ($v2 eq 'unset' and $v1 ne 'unset') {
            # id3v2 is unset, but we have value in id3v2
            print "\t  '$field' in v1 is set to '$v1', synching\n" if $C::settings{verbose} ge 3;
            $vN{$field} = $v1;
            
            $D::stats{v1_synched_to_v2}++;
            
        } elsif ($v1 eq 'unset' and $v2 eq 'unset') {
            # both fields are 'unset', flag this somehow
            print "\t  '$field' is unset in both v1 and v2, skipping\n" if $C::settings{verbose} ge 3; # this will be summarized at the end, no need to notify in-line
            
            $D::stats{both_unset}++;
            push @{$D::both_unset}, $ffp;
            
        } else {
            # both have data, but not the same.. need to key off of $C::settings{win}
            $D::stats{out_of_sync}++;
            
            
            
        }
        
        
    }
    
    print Dumper(\%v1); # current contents of id3v1
    print Dumper(\%v2); # current contents of id3v2
    print Dumper(\%vN); # contents to be written to both id3v1 and id3v2
    
    if (keys %vN) {
        # need to prompt the user before doing this if $C::settings{interactive}
        put_id3($ffp, 'id3v1', \%vN);
        put_id3($ffp, 'id3v2', \%vN); # this seems bulky
    } else {
        warn "WARN:: all id3 tags missing from: $ffp\n";
    }
    

}

my @lt2 = localtime;
print "  processed ", keys %D::mp3, " mp3s in ", timetaken(\@lt1, \@lt2);


## report on what we did 
display_summary(\%D::stats);

my @t2 = localtime;
print "% $0 finished at ", nicetime(\@t2, "time"), " took ", timetaken(\@t1, \@t2), "\n" if $C::settings{verbose} ge 1;

exit 0;

## subs below 

sub get_id3 {
    # get_id3($ffp, $version) - returns a hash based on the $version tags in $ffp
    my $ffp     = shift;
    my $version = shift;
    my %h;
    
    $version = uc($version);
    $version =~ s/V/v/g;
    
    my $worker; # scope hack
    
    eval {
        $worker = MP3::Tag->new($ffp);
        $worker->get_tags(); # need this or everything is undef
    };
    
    if ($@) {
        warn "WARN:: caught death while trying to read '$version' from '$ffp', returning";
        return;
    }
    
    my @fields = @{$C::settings{fields}};
    foreach my $field (@fields) {
        $h{$field} = $worker->{$version}->{$field};
    }
    
    return %h;
}

sub put_id3 {
    # put_id3($ffp, \%hash, $version) - sets the $version tags in $ffp based on %hash -- returns 0|1 for success|failure
    my ($ffp, $href, $version) = @_;
    my $results = 0;
    
    return $results;
}

sub is_skip {
    # is_skip($ffp) - returns 0|1 based on whether the user wants to skip this file
    my $ffp     = shift;
    my @skips   = @{$C::settings{skips}};
    my $results = 0;
    
    foreach (@skips) {
        my $skip = $_;
        
        next unless $ffp =~ /$_/;
        
        return 1;
    }
    
    return $results;
}

sub display_summary {
    # display_summary(\%hash) - summarizes the work done by id3sync.pl
    my $href = shift;
    my %h    = %{$href};
    
    #$D::stats{already_in_sync}++;
    #$D::stats{v2_synched_to_v1}++;
    #$D::stats{v1_synched_to_v2}++;
    #$D::stats{both_unset}++;
    #$D::stats{out_of_sync}++;
    
    my $total_synched = $h{v2_synched_to_v1} + $h{v1_synched_to_v2} + $h{out_of_sync};
    my $unmodified    = $h{already_in_sync} + $h{both_unset};
    
    print(
       "synched:\t$total_synched\n",
       "untouched:\t$unmodified\n",
    );
    
    return;
}