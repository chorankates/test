#!/usr/bin/perl -w
## dex-crawl.pl -- script to gather information about TV shows and Movies on an external device (NAS for now)

# TODO
## write function to query wikipedia and return the information needed

use strict;
use warnings;
use 5.010;

use lib 'lib';
use dex::util;

use lib '/home/conor/Dropbox/perl/_pm';
use ironhide;

use Cwd;
use Data::Dumper;
#use Data::UUID;
use DBD::SQLite;
use File::Basename;
use File::Find;
use File::Spec;
use Getopt::Long;
use LWP::UserAgent;
use Storable;
use Time::HiRes;

my (%f, %files, %s); # flags, results from dir_crawling, settings

%s = (
	database           => 'dex.sqlite', # this can be overloaded, assume that it exists in $s{working_dir}
	debug              => 1, # overload the indexing with a storable 
	dbg_storable       => 'latest_index.sbl', 
	error_file         => "error_dex-crawl.log", # switching to a single log file
	function           => 'crawl', # will want to change this to dex-cli.pl and add a 'query' function
	retrieve_imdb      => 1,
	retrieve_wikipedia => 1,
	working_dir        => Cwd::getcwd,
	verbose            => 1, # 0 <= n <= 3
	
	dir     => {
		tv 	=> [ '/media/pdisk1/tv/', ],
		movies	=> [ '/media/pdisk2/movies/', ],
	},

	table   => {
		tv	=> 'tbl_tv',
		movies	=> 'tbl_movies',
		stats => 'tbl_stats',
	},
	
	media_types => [
		'tv',
		'movies',
		#'mp3', # how can we incorporate this? generate html with folder.jpg?
	],
	
	browser => {
		useragent => 'Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.2.16) Gecko/20110323 Ubuntu/10.10 (maverick) Firefox/3.6.16',
		timeout   => 10, # low timeouts
	},	
	
);

GetOptions(\%f, "help", "dir:s", "verbose:i", "database:s", "working_dir:s", "debug:i", "rescan:i");
$s{$_} = $f{$_} foreach (keys %f);
$s{image_dir} = File::Spec->catdir($s{working_dir}, "media_images");

%dex::util::settings = %s; # excellent..

my @t1 = localtime;
print "% $0 started at ", nicetime(\@t1, "time"), "\n" if $s{verbose} ge 1;

if ($s{rescan}) {
	# delete artifacts and scan from scratch
	print "> removing artifacts..\n" if $s{verbose} ge 1;
	if (-f $s{database})     { unlink ($s{database})     or warn "WARN:: unable to remove $s{database}: $!"; }
	if (-f $s{dbg_storable}) { unlink ($s{dbg_storable}) or warn "WARN:: unable to remove $s{dbg_storable}: $!"; }
}

if (-f $s{error_file})   { unlink ($s{error_file})   or warn "WARN:: unable to remove $s{error_file}: $!"; }

unless (-d $s{image_dir}) {
	mkdir($s{image_dir}) or warn "WARN:: unable to create '$s{image_dir}': $!";
}

unless (-f $s{database}) {
	my $results = dex::util::create_db($s{database});
	if ($results) {
		warn "WARN:: unable to locate OR create '$s{database}': $results";
		exit 1;
	} else {
		print "  created '$s{database}'\n" if $s{verbose} ge 1;
	}
	
}

print Dumper(\%f) if $s{verbose} ge 2;
print Dumper(\%s) if $s{verbose} ge 1;

# find all the files.. all the files
my @lt_find_files_begin = localtime;
print "> indexing media (" . join("," . @{$s{media_types}}) . ")\n" if $s{verbose} ge 1;
foreach my $type (@{$s{media_types}}) {
	if ($s{debug} and -f $s{dbg_storable}) {
		print "DBG:: skipping dynamic crawling..\n";
		my $href = retrieve($s{dbg_storable});
		%files = %{$href};
		last;
	}
	
	my @lt_index_time_begin = localtime;
	print "  indexing $type:\n" if $s{verbose} ge 1;
	my @dirs = @{$s{dir}{$type}};
	
	foreach my $dir (@dirs) {
		print "    crawling '$dir'..\n" if $s{verbose} ge 2;
		%files = crawl_dir($dir, 0, $type, \%files);
	}
	my @lt_index_time_end = localtime;
	print "  done indexing $type, took ", timetaken(\@lt_index_time_begin, \@lt_index_time_end), "\n" if $s{verbose} ge 2;
}

store(\%files, $s{dbg_storable}); # should throw some debug message
my @lt_find_files_end = localtime;
print "  done indexing media, found ", scalar keys %files, " files, took ", timetaken(\@lt_find_files_begin, \@lt_find_files_end), "\n" if $s{verbose} ge 1;

## find out which ones are new and add them to the db
my @lt_find_new_files_begin = localtime;
my ($added, $processed, $size_total, $size_added) = (0, 0);
print "> adding new media to the db:\n" if $s{verbose} ge 1;
foreach my $ffp (sort keys %files) {
	# sorting is expensive, especially on 4k+ keys, but we only have to do it once
	$processed++;
	my $file = $files{$ffp}{basename};
	my $type = $files{$ffp}{type};
	my $size = $files{$ffp}{size};
	
	$size_total += $size;
	
	#this verbosity is wonky.. need to fix it, until then, stick with verbose=2 or 0
	print "  $processed ::  processing '$file'.." if $s{verbose} ge 2;
	
	my $md5 = get_md5($file); # md5 of the filename string, not the file itself
	
	if (already_added($s{database}, $md5, $type)) {
		print " " x (90 - length($file)), "already exists, skipping\n" if $s{verbose} ge 2;
		next;
	} else {
		print " " x (90 - length($file)), "unknown MD5, adding\n" if $s{verbose} ge 2;
	}
	
	$size_added += $size;
	
	
	# should have a $processed/$total print out here.. every 10%?
	
	my %file_info = get_info_from_filename($ffp, $file, $type);
	
	next if ($file_info{error}); # already logged a warning
		
	## now add to the db
	my $results = put_sql($s{database}, $type, \%file_info);
	
	
	$added++;
}
my @lt_find_new_files_end = localtime;
print "  done adding, found/added $added new files, took ", timetaken(\@lt_find_new_files_begin, \@lt_find_new_files_end), "\n" if $s{verbose} ge 1;

my @tv_files    = grep { $files{$_}{type} eq 'tv' }     keys %files;
my @movie_files = grep { $files{$_}{type} eq 'movies' } keys %files;

# this helps
if (-f $s{error_file}) { 
	my $sort_file = $s{error_file} . ".tmp";
	my $sort_cmd = "sort $s{error_file} >> $sort_file";
	my $sort_results = `$sort_cmd`;
	$sort_cmd = "mv $sort_file $s{error_file}";
	$sort_results = `$sort_cmd`;
}

## do some database maintenance
my $stats_results = put_stats($s{database}, $processed, $added, $#tv_files, $#movie_files, $size_total, $size_added);

## remove files that DNE, get imdb/wikipedia information
my @lt_db_maint_begin = localtime;
print "> database_maintenance($s{database}):\n" if $s{verbose} ge 1;
my ($tv_removed_count, $tv_wiki_count, $movie_removed_count, $movie_imdb_count) = database_maintenance($s{database});
my @lt_db_maint_end = localtime;
print(
	  "  done: non-existent entries removed ($tv_removed_count tv files, $movie_removed_count movie files), ",
	  "wiki/imdb information added ($tv_wiki_count tv files, $movie_imdb_count movie files), ",
	  " took ",
	  timetaken(\@lt_db_maint_begin, \@lt_db_maint_end),
	  "\n",
) if $s{verbose} ge 1;



my @t2 = localtime;
print "% $0 finished at ", nicetime(\@t2, "time"), " took ", timetaken(\@t1, \@t2), "\n" if $s{verbose} ge 1;
exit 0;

## subs below

sub crawl_dir {
	# crawl_dir($dir, $depth, $type, $href) - adds all possible video filenames to $href
	my ($dir, $depth, $type, $href) = @_;
	my %h = %{$href};
	
	my @lt1 = localtime;
	my $added = 0;
	
	find(
		sub {
			my $ffp = File::Spec->canonpath($File::Find::name);
			return unless -f $ffp; # don't want directories
			#return unless $ffp =~ /\.(avi|mp4|mpeg|mpg|mkv)$/; # short whitelist
			return if $ffp =~ /\.(txt|log|srt|nfo|jpg|png|htm|ico|idx|sub|mp3|sfv|pdf|ini|zip)$/i; # short blacklist

			my $file = $File::Find::name;
			my $basename = basename($file);
			print "\tfound ", $basename, "\n" if $s{verbose} ge 3;

			$h{$file}{type}     = $type;
			$h{$file}{basename} = $basename;
			$h{$file}{size}     = (stat($ffp))[7];
			$added++;
		},
		$dir
	);
	
	my @lt2 = localtime;
	print "\tdone, added $added, (total: ", scalar keys %h, "), took " . timetaken(\@lt1, \@lt2), "\n" if $s{verbose} ge 2;
	
	return %h;
}

sub already_added {
	# already_added($database, $md5, $type) -- does a quick check to determine if the $md5 passed is already in the $database -- returns 0|1 for no|yes
	my ($database, $md5, $type) = @_;
	my $results = 0;
	
	# we should check to see if the folder path has changed, and if so, delete the current entry
	
	my $table = $s{table}{$type};
	#my $sql   = "SELECT * from $table WHERE UID == \"$md5\""; # don't really need the whole match, but get_sql() freaks out if not
	my $addl_sql = "WHERE UID == \"$md5\"";
	
	#my $q = get_sql($database, $sql, $type);
	my ($q, $count) = get_sql($database, $type, $addl_sql);
	
	#$results = (keys %{$q}) ? 1 : 0;
	$results = $count;
	
	return $results;
}

sub put_stats {
	# put_stats() - returns 0|1 based on SQL update results
	#my $stats_results = put_stats($processed, $added, $#tv_files, $#movie_files, $size_total, $size_added);
	my ($database, $files_found, $files_added_in_last_run, $files_tv_count, $files_movie_count, $files_size_total, $files_size_added) = @_;
	my $results = 0;
	
	my $table = 'tbl_stats';
	
	my $dbh = DBI->connect("dbi:SQLite:$database");
	unless ($dbh) {
		warn "WARN:: unable to connect to '$database': $DBI::errstr";
		return 1;
	}
	
	# $schema = 'uid TEXT PRIMARY KEY, name TEXT, value TEXT' if $tbl_name eq 'tbl_stats';
	my %stats = (
		files_found             => $files_found,
		files_added_in_last_run => $files_added_in_last_run,
		files_tv_count          => $files_tv_count,
		files_movie_count       => $files_movie_count,
		files_size_total        => nicesize($files_size_total),
		files_size_added        => nicesize($files_size_added),
	);
	

	foreach my $name (keys %stats) {
		my $value = $stats{$name};
		
		my $sql = "UPDATE $table SET value='$value' WHERE name='$name'";
		
		my $query = $dbh->prepare($sql);
		unless ($query) {
			warn "WARN:: unable to prepare '$sql': $DBI::errstr";
			return 1;
		}
		
		my $q = $query->execute;	
		
	}
	
	$dbh->disconnect;
	
	return $results;
}