#!/usr/bin/perl -w
## hound.pl - monitors websites for links based on keyword, includes download capability

# TODO
## store %C::downloads with storable?

use strict;
use warnings;
use 5.010;

use Cwd;
use Data::Dumper;
use File::Basename;
use File::Find;
use File::Spec;
use Getopt::Long;
use LWP::UserAgent;
use XML::Simple;

## initialize variables
%C::settings = (
    verbose => 1,
    
    home => Cwd::getcwd,
    
    config => 'tv.xml',
    
    ip     => get_ip(),
    vpn => '93\.182\.\d{1-3}\.\d{1-3}', # if set, requires that @{ip} ~~ $vpn
);

GetOptions(\%C::flags, "help", "verbose:i", "config:s", "download:i", "vpn:s");
$C::settings{$_} = $C::flags{$_} foreach (keys %C::flags);

my @t1 = localtime;
print "% $0 started at ", scalar(localtime), "\n" if $C::settings{verbose} ge 1;

%C::config = get_xml($C::settings{config});

%Q::sites        = %{$C::config{settings}};
%Q::tv_shows     = %{$C::config{tv_show}};
%Q::handlers     = %{$C::config{handlers}};
%Q::destinations = %{$C::config{destinations}};

%C::downloads = get_files(\%Q::destinations);

print Dumper(\%C::flags)    if $C::settings{verbose} ge 2;
print Dumper(\%C::settings) if $C::settings{verbose} ge 1;
print 

print "DBGZ" if 0;

## do work
# look for links -- push into %Q::links
foreach (keys %Q::tv_shows) {
    my $show = $_;
    my $type = $Q::tv_shows{$show}{type};
    my @regex = (ref $Q::tv_shows{$show}{regex}) ? @{$Q::tv_shows{$show}{regex}} : ($Q::tv_shows{$show}{regex});
    
    my %site = %{$Q::sites{$type}};
    
    
    
}

# download files
foreach (keys %Q::links) {
    my $link = $_;
    my $show = $Q::links{$link}{show};
    my $type = $Q::links{$link}{type};
    
    my $action = $Q::handlers{$type};
    my $auto_download = $Q::tv_shows{$show}{auto_download};
    
    my $downloaded_file = download_file($link);
    $Q::links{$link}{downloaded} = $downloaded_file; # 0 or a filename
    
}

# process files



# record what you did

## cleanup

my @t2 = localtime;
print "% $0 finished at ", scalar(@t2), "\n" if $C::settings{verbose} ge 1;
exit 0;

## subs below

sub download_file {
    # download_file($url, [$filename]) -- downloads $url to $filename (optional) and return 0 or filename
    my $url      = shift;
    my $filename = shift;
    my $results  = 0;
    
    
    
    return $results;
}

sub get_ip {
    # get_ip() -- returns an array of IP addresses for this host
    my @results;
    
    my $cmd = 'ifconfig';
    my @a   = `$cmd`;
    
    foreach my $line (@a) {
        next unless $line =~ /inet\saddr:(.*?)\s/i;
        push @results, $1;
    }
    
    return \@results;
}

sub already_downloaded {
    # already_downloaded($filename) - returns 0 or the download time of a file (if it has already been downloaded)
    my $filename = shift;
    my $results  = 0;
    
    foreach (keys %C::downloads) {
        next unless $C::downloads{$_}{fname} eq $filename;
        
        $results = $C::downloads{$_}{ctime};
        last;
    }
    
    return $results;
}

sub get_files {
    # get_files(\%hash) - pulls directorys out of the destinations hash and returns a hash of files (key = filename, value = ctime)
    my $href = shift;
    my %h = %{$href};
    
    my @dirs;
    foreach my $ref (keys %h) {
        push @dirs, $_ foreach (values %{$h{$ref}});
    }
    
    my %files;
    
    foreach my $dir (@dirs) {
        find(
            sub {
                my $ffp = $File::Find::name;
                
                return unless -f $ffp;
                
                $files{$ffp}{ctime} = scalar localtime((stat($ffp))[10]);
                $files{$ffp}{fname} = basename($ffp);
                
            },
            $dir
        );
    }
    
    
    return %files;
}

sub get_xml {
    # get_xml($file) - returns %hash based on contents of $file
    my $file = shift;
    my %h;
    
    my $worker = XML::Simple->new();
    my $document = $worker->XMLin($file);# ForceArray => 1);
    
    %h = %{$document};
    
    return %h;
}

sub put_xml {
    # put_xml($file, \%hash) - writes %hash to $file, returns 0|1 for success|failure
    my ($file, $href) = @_;
    my $results = 0;
    
    my $worker = XML::Simple->new();
    
    my $fh;
    open($fh, '>', $file) or die "DIE:: unable to open '$file': $!";
    print $fh $worker->XMLout($href, noattr => 1); 
    close ($fh);
    
    return $results;
}

sub help {
    # help([$message]) - prints some command line syntax and exits with 0 unless called with $message (then 1)
    my $message = shift;
    
    if ($message) {
        print "$message\n";
    }
    
    # GetOptions(\%C::flags, "help", "verbose:i", "config:s", "download:i", "vpn:s");
    print(
        "",
    );
    
    exit 1 if $message;
    exit 0;
}