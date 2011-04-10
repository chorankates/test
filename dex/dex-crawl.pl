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

use lib '/home/conor/Dropbox/perl/_pm/';
use ironhide;

use Cwd;
use Data::Dumper;
#use Data::UUID;
use DBD::SQLite;
use Digest::MD5;
use File::Basename;
use File::Find;
use File::Spec;
use Getopt::Long;
use LWP::UserAgent;
use Storable;

my (%f, %files, %s); # flags, results from dir_crawling, settings

%s = (
    verbose  => 1, # 0 <= n <= 3
    database => 'dex.sqlite', # this can be overloaded, assume that it exists in $s{working_dir}
    debug    => 1, # overload the indexing with a storable 
	dbg_storable => 'latest_index.sbl', 

	dir     => {
		tv 	=> [ '/media/pdisk1/tv/', ],
		movies	=> [ '/media/pdisk2/movies/', ],
	},

	table   => {
		tv	=> 'tbl_tv',
		movies	=> 'tbl_movies',
		
	},
	
	media_types => [
		'tv',
		'movies',
		#'mp3', # how can we incorporate this? generate html with folder.jpg?
	],
	
	function => 'crawl', # will want to change this to dex-cli.pl and add a 'query' function
	
	working_dir => Cwd::getcwd,
	
);

GetOptions(\%f, "help", "dir:s", "verbose:i", "database:s", "working_dir:s", "debug:i");
$s{$_} = $f{$_} foreach (keys %f);
$s{log_error} = "dex-crawl_error." . time . ".log";
$s{image_dir} = File::Spec->catdir($s{working_dir}, "imdb_images");

my @t1 = localtime;
print "% $0 started at ", nicetime(\@t1, "time"), "\n" if $s{verbose} ge 1;

unless (-d $s{image_dir}) {
	mkdir($s{image_dir}) or warn "WARN:: unable to create '$s{image_dir}': $!";
}

unless (-f $s{database}) {
	my $results = create_db($s{database});
	if ($results) {
		warn "WARN:: unable to locate OR create '$s{database}': $results";
		exit 1;
	} else {
		print "  created '$s{database}'\n" if $s{verbose} ge 1;
	}
	
}

print Dumper(\%f) if $s{verbose} ge 2;
print Dumper(\%s) if $s{verbose} ge 1;

## find all the files.. all the files
my @lt1 = localtime;
foreach my $type (@{$s{media_types}}) {
	if ($s{debug} and -f $s{dbg_storable}) {
		print "DBG:: skipping dynamic crawling..\n";
		my $href = retrieve($s{dbg_storable});
		%files = %{$href};
		last;
	}
	
	print "> starting $type index:\n" if $s{verbose} ge 1;
	my @dirs = @{$s{dir}{$type}};
	
	foreach my $dir (@dirs) {
		print "  crawling '$dir'..\n" if $s{verbose} ge 2;
		%files = crawl_dir($dir, 0, $type, \%files);
	}
	print "  done indexing $type\n" if $s{verbose} ge 3;
}

store(\%files, $s{dbg_storable}); # should throw some debug message
my @lt2 = localtime;
print "> done indexing, found ", scalar keys %files, " files, took ", timetaken(\@lt1, \@lt2), "\n" if $s{verbose} ge 1;

## find out which ones are new and add them to the db
my @lt3 = localtime;
my $added = 0;
foreach my $ffp (keys %files) {
	print "> adding new media to the db:\n" if $s{verbose} ge 1;
	my $file = $files{$ffp}{basename};
	my $type = $files{$ffp}{type};
	
	my $md5 = get_md5($file); # md5 of the filename string, not the file itself
	
	next if already_added($s{database}, $md5, $type);
	
	my %file_info = get_info_from_filename($file, $type);
	
	## now add to the db
	
	
	
	$added++;
}
my @lt4 = localtime;
print "> done adding, found/added $added new files, took ", timetaken(\@lt3, \@lt4), "\n" if $s{verbose} ge 1;

# synergyc 192.168.1.122

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
			return if $ffp =~ /\.(txt|log|srt|nfo|jpg|png|htm)$/; # short blacklist

			my $file = $File::Find::name;
			my $basename = basename($file);
			print "\tfound ", $basename, "\n" if $s{verbose} ge 3;

			$h{$file}{type}     = $type;
			$h{$file}{basename} = $basename;
			$added++;
		},
		$dir
	);
	
	my @lt2 = localtime;
	print "\tdone, added $added, (total: ", scalar keys %h, "), took " . timetaken(\@lt1, \@lt2), "\n" if $s{verbose} ge 2;
	
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
		
		my $title = $1 if $ffp =~ /(.*)\s\((\d*)\)?\./;
		my $year  = $2 // "unknown";
		
		unless ($title and $year) {
			log_error("unrecognized filename format: $ffp");
			return %h;
		}
		
		$h{title} = $title;
		$h{year}  = $year;
		
	} elsif ($type =~ /tv/i) {

		#my $count = $file =~ /-/g; # this will not work if there are -'s in the episode name
		my @t = $file =~ /-/g;
		my $count = (@t) ? $#t + 1 : 0; # lol @ typecasting
		
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

sub put_sql {
	# put_sql($database, $type, $href)  -- takes a hash of data and adds it to $database according to $type -- returns 0|1|2 for success|already known|failure
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
	# get_sql($database, $sql, $type) -- returns a href of data corresponding to $sql in $database
	my ($database, $sql, $type) = @_; # type = tv/movies
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
	
	# tv: 		uid TEXT PRIMARY KEY, title TEXT, added TEXT, released TEXT, season NUMERIC, series NUMERIC, genre TEXT, notes TEXT
	# movies:   uid TEXT PRIMARY KEY, title TEXT, added TEXT, released TEXT, imdb TEXT, cover TEXT, director TEXT, actors TEXT, genre TEXT, notes TEXT
	
	while (my @r = $query->fetchrow_array()) {
		if ($type =~ /tv/) {
			my $u = $r[0];
			$h{$u}{title}    = $r[1];
			$h{$u}{added}    = $r[2];
			$h{$u}{released} = $r[3];
			$h{$u}{season}   = $r[4];
			$h{$u}{series}   = $r[5];
			$h{$u}{genre}    = $r[6];
			$h{$u}{notes}    = $r[7];
			
		} else {
			# movies
			my $u = $r[0];
			$h{$u}{title}    = $r[1];
			$h{$u}{added}    = $r[2];
			$h{$u}{released} = $r[3];
			$h{$u}{imdb}     = $r[4];
			$h{$u}{cover}    = $r[5];
			$h{$u}{director} = $r[6];
			$h{$u}{actors}   = $r[7];
			$h{$u}{genre}    = $r[8];
			$h{$u}{notes}    = $r[9];			
		}
	}
	
	return \%h;
}
sub already_added {
	# already_added($database, $md5, $type) -- does a quick check to determine if the $md5 passed is already in the $database -- returns 0|1 for no|yes
	my ($database, $md5, $type) = @_;
	my $results = 0;
	
	my $table = $s{table}{$type};
	my $sql   = "SELECT * from $table WHERE UID == \"$md5\""; # don't really need the whole match, but get_sql() freaks out if not
	
	my $q = get_sql($database, $sql, $type);
	
	$results = (keys %{$q}) ? 1 : 0;
	
	return $results;
}

sub get_md5 {
	# get_md5($string) -- returns MD5 based on $string
	my $string = shift;
	my $results;
	
	$results = Digest::MD5::md5_hex($string);
	
	return $results;
}

sub create_db {
    # create_db($name) - creates a blank database ($name), returns 0 or an error message
    my $name = shift @_;
    my $results = 0;
    
    # need to open a db and create the default schema
    # default schema is:
    # CREATE TABLE tbl_main (url TEXT PRIMARY KEY, status_code TEXT, size NUMERIC, links TEXT)
    my @tables = ('tbl_movies', 'tbl_tv');
    
    my $dbh = DBI->connect("dbi:SQLite:$name") or $results = $DBI::errstr;
    
    if ($results) { 
    	warn "WARN:: unable to open db '$name', bailing out of this function";
    	
    	# this falls through to the default 'return' statement
    	
    } else {
    	# so far so good
    	
	foreach my $tbl_name (@tables) {
		my $schema;
		
		$schema = 'uid TEXT PRIMARY KEY, title TEXT, added TEXT, released TEXT, imdb TEXT, cover TEXT, director TEXT, actors TEXT, genre TEXT, notes TEXT' if $tbl_name eq 'tbl_movies';
		$schema = 'uid TEXT PRIMARY KEY, title TEXT, added TEXT, released TEXT, season NUMERIC, series NUMERIC, genre TEXT, notes TEXT'                    if $tbl_name eq 'tbl_tv';
		next unless $schema; # failsafe
	
		my $query = $dbh->prepare(
		    "CREATE TABLE $tbl_name ($schema)"
		);
	    
		# ok, now to actually run the SQL
		eval {
		    $query->execute;
		    
		    # since this is a 'CREATE' statement, it doesn't have a necessary return value. add one for error checking in the future
		};
		
		if ($@) { 
		    warn "WARN:: error while creating default schema: $@";
		    return $results;
		}
		
		
	}    	
    }
    
    return $results;
}