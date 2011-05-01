#!/usr/bin/perl -w
## dex-crawl.pl -- script to gather information about TV shows and Movies on an external device (NAS for now)

# TODO
## write function to query IMDB and return the information needed

use strict;
use warnings;
use 5.010;

use lib 'lib/';
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

## remove files that no longer exist -- only in non-debug runs
unless ($s{debug}) { 
	my @lt_remove_begin = localtime;
	# remove_non_existent_entries($database, \@media_types, \%media_tables, $verbosity)
	print "> remove_non_existent_entries($s{database}):\n" if $s{verbose} ge 1;
	my ($tv_count, $movies_count) = remove_non_existent_entries();
	warn "WARN:: error during removal: $movies_count" if $tv_count == -1;
	my @lt_remove_end = localtime;
	print "  done removing non-existent entries ($tv_count tv files, ", ($movies_count =~ /\d+/ ? $movies_count : -1), " movie files), took ", timetaken(\@lt_remove_begin, \@lt_remove_end), "\n" if $s{verbose} ge 1; # this line helps me understand why some people hate perl
}

## find all the files.. all the files
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
	
	# don't know that we always want to do this here, but
	if ($type eq 'tv' and $s{retrieve_wikipedia}) {
		# noop, don't have get_wikipedia() up and running
		
		#my %tv_info = get_wikipedia(\%file_info);
		
		print "DBGZ" if 0;
	} elsif ($type eq 'movies' and $s{retrieve_imdb}) {
		# get information from imdb.com
		print "    get_imdb($file_info{title})\n" if $s{verbose} ge 1;
		my %movie_info = get_imdb(\%file_info);
		
		if (keys %movie_info) {
			# successful call, add information to %file_info (need to update the $files{$ffp}{imdb} entry to be the actual page, not search page)
			$file_info{released} = $movie_info{released} // 'unknown';
			$file_info{director} = $movie_info{director} // 'unknown';
			$file_info{imdb}     = $movie_info{new_imdb} // $file_info{imdb};
			$file_info{cover}    = $movie_info{cover}    // 'unknown';
			$file_info{actors}   = $movie_info{actors}   // 'unknown';
			$file_info{genres}   = $movie_info{genres}   // 'unknown';
			
		} else {
			# unsuccessful call, throw a warning
			log_error("unable to get imdb information for '$file' from '$files{$ffp}{imdb}");
		}
		
	}
	
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

my $stats_results = put_stats($s{database}, $processed, $added, $#tv_files, $#movie_files, $size_total, $size_added);

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
			return if $ffp =~ /\.(txt|log|srt|nfo|jpg|png|htm|ico|idx|sub|mp3|sfv|pdf|ini)$/i; # short blacklist

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


sub get_wikipedia {
	# get_wikipedia(\%file_info) - given %file_info, returns a hash of information about the first match found (or an empty hash for error)
	my $href = shift;
	my %file_info = %{$href};
	my %h;
	
	my $search_url = $file_info{wikipedia}; # this is usually a direct link, not a search url
	
	return {} unless defined $search_url;
	
	my $worker = LWP::UserAgent->new();
	   $worker->agent($s{browser}{useragent});
	   $worker->timeout($s{browser}{timeout});
	   
	my $response = $worker->get($search_url);
	
	# stuff to parse out:
	# genres, cover, wikipedia, released, actors
	
	return %h;
}

sub get_imdb {
	# get_imdb(\%file_info) - given %file_info, returns a hash of information about the first match found (or an empty hash for error)
	# TODO: update function so it can handle multiple matches -- though since this is a non-interactive crawler, how would we handle the logic?
	my $href = shift;
	my %file_info = %{$href};
	my %h; # will contain information coming back from imdb

	my $search_url = $file_info{imdb};
	
	return {} unless defined $search_url;
	
	my $worker = LWP::UserAgent->new();
	   $worker->agent($s{browser}{useragent});
	   $worker->timeout($s{browser}{timeout});
	
	# get the search result page
	my $search_time_begin = Time::HiRes::gettimeofday();
	my $response  = $worker->get($search_url);
	my $search_time_end = Time::HiRes::gettimeofday();
	print "      search took ", substr(($search_time_end - $search_time_begin), 0, 5), "s\n" if $s{verbose} ge 3;
	
	# we also need to download the cover image to $s{image_dir}
	my @search_contents = $response->content;
	
	my $rel_link     = 'http://www.imdb.com';
	my $title_path   = $1 if @search_contents ~~ /href="(\/title.*?)"/ig;
	my $content_link = $rel_link . $title_path;
	
	# get the content result page
	my $content_time_begin = Time::HiRes::gettimeofday();
	$response = $worker->get($content_link);
	my @results_contents = $response->content;
	my $content_time_end = Time::HiRes::gettimeofday();
	print "      results fetch took ", substr(($content_time_end - $content_time_begin), 0, 5), "s\n" if $s{verbose} ge 3;
	
	# extract basic information from @results_contents
	$h{new_imdb}  = $content_link; # contains the actual address to the imdb page, not the search results
	$h{released}  = $1 if @results_contents ~~ /\<span\>\(\<a\shref=".*?\/year\/.*\>(.*?)\<\/a\>\)<\/span\>/ims;
	$h{director}  = $1 if @results_contents ~~ /Director\:.*?"\>(.*?)\<\/a\>\<\/div\>/ims;
	$h{www_cover} = $1 if @results_contents ~~ /\<a\s*onclick="\(new\sImage.*?\>\<img\ssrc="(.*?)".*?Poster"\s*\/\>\<\/a\>/ims; # need to download this file to $s{image_dir}, then set $h{cover} to the filename in $s{image_dir}
	
	# extract extended information
	my $download_filename = File::Spec->catfile($s{image_dir}, basename($file_info{ffp}));
	   $download_filename =~ s/\..*?$/\.jpg/i;
	my $download_results  = download_file($h{www_cover}, $download_filename);
	$h{cover} = ($download_results eq 0) ? $download_filename : "unable to download: $h{www_cover}";
	
	my @actors;
	my $actors_str = $1 if @results_contents ~~ /\<h4 class="inline"\>Stars\:\<\/h4\>(.*?)\<\/div\>/ims; # this technically pulls 'stars', but that's what we're looking for anyway
	my @actors_list = split(">", $actors_str);
	
	foreach (@actors_list) {
	    push @actors, $1 if $_ =~ /(.*?)\<\/a$/;
	}
	
	
	$h{actors}    = join(', ', @actors); # CSV, since we're going to push into a SQLite DB anyway
	
	my @genres;
	my $genres_str = $1 if @results_contents ~~ /\<h4 class="inline"\>Genres\:\<\/h4\>(.*?)\<\/div\>/ims;
	my @genres_list = split(">", $genres_str); # don't know if this is right..
	
	## real men do it with a grep -- but i can't get this one to work right.. 
	#@genres = grep { if ($_ =~ /(.*?)\<\/a$/) { return $1; } } @genres_list;
	
	foreach (@genres_list) {
	    push @genres, $1 if $_ =~ /(.*?)\<\/a$/;
	}
	
	$h{genres} = join(', ', @genres); # CSV
	
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