#!/usr/bin/perl -w
## dex-crawl.pl -- script to gather information about TV shows and Movies on an external device (NAS for now)

## schema notes:
# tv: 		uid TEXT PRIMARY KEY, title TEXT, added TEXT, released TEXT, season NUMERIC, series NUMERIC, genre TEXT, notes TEXT
# movies:   uid TEXT PRIMARY KEY, title TEXT, added TEXT, released TEXT, imdb TEXT, cover TEXT, director TEXT, actors TEXT, genre TEXT, notes TEXT

# TODO
## write generic SQL read/write functions
## write function to return as much information (that will be written to sql) based on filename
## write function to query IMDB and return the information needed

use strict;
use warnings;
use 5.010;

use Cwd;
use Data::UUID;
use DBD::SQLite;
use Digest::MD5;
use File::Find;
use File::Spec;
use Getopt::Long;
use LWP::UserAgent;

my (%f, %s); # flags, settings

%s = (
    verbose  => 1, # 0 <= n <= 3
    database => 'dex.sqlite', # this can be overloaded, assume that it exists in $s{working_dir}
	
	dir     => {
		tv 		=> '/media/pdisk1/tv/',
		movies	=> '/media/pdisk2/movies/',
	},

	table   => {
		tv		=> 'tbl_tv',
		movies	=> 'tbl_movies',
		
	},
	
	working_dir => Cwd::getcwd,
	
);

GetOptions(\%f, "help", "dir:s", "verbose:i", "database:s", "working_dir:s");
$s{$_} = $f{$_} foreach (keys %f);
$s{log_error} = "dex-crawl_error." . time . ".log";
$s{image_dir} = File::Spec->catdir($s{working_dir}, "imdb_images");

mkdir($s{image_dir}) or warn "WARN:: unable to create '$s{image_dir}': $!";

print Dumper(\%f) if $s{verbose} ge 2;
print Dumper(\%s) if $s{verbose} ge 1;

## need to have some sort of timer here

exit 0;

## subs below

sub crawl_dir {
	# crawl_dir($dir, $depth) - returns hash of all possible video filenames
	my ($dir, $depth) = @_;
	my %h;
	
	print "> crawling '$dir'..\n" if $s{verbose} ge 1;
	
	my $start = time;
	
	find(
		sub {
			my $ffp = File::Spec->canonpath($File::Find::name);
			return unless -f $ffp; # don't want directories
			#return unless $ffp =~ /\.(avi|mp4|mpeg|mpg|mkv)$/; # short whitelist
			return if $ffp =~ /\.(txt|log|srt|nfo)$/; # short blacklist

			my $file = $File::Find::name;

			$h{$file} = 1;		
		},
		$dir
	);
	
	my $stop = time;
	print "\tdone, took " . ($stop - $start) . "\n" if $s{verbose} ge 1;
	
	return %h;
}

sub get_uid {
    # get_uid($title) - returns a unique identifier (based on UUID for now, but could be MD5)
	my $title = shift;
	my $uid;
	
	if (0) {
		# this is good, but doesn't allow for backwards comparison
		my $worker = new Data::UUID;
	
		$uid = $worker->create_str();
	} else {
		# this makes it easy to determine if we've already added this to the db
		$uid = get_md5($title);
		
	}
	
	return $uid;
}

sub get_info_from_filename {
	# get_info_from_filename($ffp, $type) -- returns a hash of information based on $ffp and $type (tv|movies)
	
	# if we can't parse the filename as expected, need to log it out to the error file and prevent it from being added to the DB until filename has been fixed
	
	my ($ffp, $type) = @_;
	my $file = (File::Spec->splitpath($ffp))[2];
	my %h;
	
	if ($type =~ /movie/i) {
		# Megamind (2010).avi
		
		my $title = $1 if $ffp =~ /(.*)\s\((\d*)\)\./;
		my $year  = $2 // "unknown";
		
		unless ($title and $year) {
			log_error("unrecognized filename format: $ffp");
			return %h;
		}
		
		$h{title} = $title;
		$h{year}  = $year;
		
	} elsif ($type =~ /tv/i) {

		my $count = $file =~ /-/g; # this will not work if there are -'s in the episode name
		
		my @a = split("-", $file);
		
		if ($count == 1) {
			# Angry Beavers - Zooing Time.mp4
			$h{series} = $a[0];
			$h{title}  = $a[1];
			
		} elsif ($count == 3) {
			# Burn Notice - 01 - 10 - False Flag.avi
			$h{series}  = $a[0];
			$h{season}  = $a[1];
			$h{episode} = $a[2];
			$h{title}   = $a[3];
			
		} elsif ($count == 4) {
			# Burn Notice - 01 - 11-12 - Drop Dead and Loose Ends.avi
			$h{series}  = $a[0];
			$h{season}  = $a[1];
			$h{episode} = $a[2] . '-' . $a[3];
			$h{title}   = $a[4];
			
		} else {
			log_error("unrecognized filename format: $ffp");
			return %h;
		}
		
		return %h;
		
	} else {
		warn "WARN:: invalid type '$type', returning empty hash\n";
		return %h;
	}
	
	return %h;
}

sub get_imdb {
	# get_imdb($movie) - given a $movie title, returns a hash of information about the first match found
	  # TODO: update function so it can handle multiple matches -- though since this is a non-interactive crawler, how would we handle the logic?
	my $movie = shift;
	my %h;

	my $search_url = "http://www.imdb.com/find?s=tt&q=$movie"; # s=tt is for 'search: titles'
	
	my $worker = LWP::UserAgent->new();
	   $worker->agent('dex'); 
	
	my $response  = $worker->get($search_url);
	
	## $response now contains the contents of the search result page, need to find the first link, and follow it before parsing
	# we also need to download the cover image to $s{image_dir}
	
	$h{released} = '';
	$h{imdb}     = ''; # URL from worker
	$h{actors}   = ''; # CSV, since we're going to push into a SQLite DB anyway
	$h{genre}    = ''; # CSV
	
	return %h;
}

sub log_error {
	# log_error($string) -- throws an error to the console and writes out to $s{log_error}
	my $string = shift;
	
	my $fh;
	open($fh, '>>', $s{log_error}) or warn "WARN:: unable to open '$s{log_error}':$!";
	if ($fh) {
		print $fh scalar(localtime(time)) . "::" . $string . "\n";
		close($fh);
	}
	
	warn "WARN:: $string\n"; # key off of verbosity?
	
	return;
}

sub do_sql {
	# do_sql($database, $type, $href)  -- takes a hash of data and adds it to $database according to $type -- returns 0|1|2 for success|already known|failure
	my ($database, $type, $href) = @_;
	my $results = 0;
	my $table;
	my $query;
	
	return 2 unless -f $database;
	
	my $dbh = DBI->connect("dbi:SQLite:$database") or warn "WARN:: unable to connect to '$database': $DBI::errstr" and return 2;
	
	if ($type =~ /tv/) {
		$table = 'tbl_tv';
		
		# need to check to see if this is already in the DB
		
		
		$query = $dbh->prepare("
							   ");
		
	} elsif ($type =~ /movie/) {
		$table = 'tbl_movies';
		
		# need to check to make sure this isn't already in the DB
		
		
		$query = $dbh->prepare("
							   ");
		
		
	} else {
		warn "WARN:: unknown type '$type'";
		return 2;
	}
	
	my $qresults = $query->execute;
	
	$results = 2 if $DBI::errstr;
	
	return $results;
}

sub get_sql {
	# get_sql($database, $sql) -- returns a href of data corresponding to $sql in $database
	my ($database, $sql) = @_; # type = tv/movies
	my %h;
	
	my $dbh = DBI->connect("dbi:SQLite:$database");
	unless ($dbh) {
		warn "WARN:: unable to connect to '$database': $DBI::errstr";
		return undef;
	}
	
	my $query = $dbh->prepare($sql);
	unless ($query) {
		warn "WARN:: unable to prepare '$sql': $DBI::errstr";
		return undef;
	}
	
	my $q = $query->execute;
	
	
	
	return \%h;
}

sub already_added {
	# already_added($database, $md5) -- does a quick check to determine if the $md5 passed is already in the $database -- returns 0|1 for no|yes
	my ($database, $md5) = @_;
	my $results = 0;
	
	my $sql = 'SELECT UID from '
	
	my $q = get_sql($database, $sql);
	
	return $results;
}

sub get_md5 {
	# get_md5($string) -- returns MD5 based on $string
	my $string = shift;
	my $results;
	
	$results = Digest::MD5::md5_hex($string);
	
	return $results;
}