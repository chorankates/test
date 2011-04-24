#!/usr/bin/perl -w
## dex-crawl.pl -- script to gather information about TV shows and Movies on an external device (NAS for now)

## schema notes:
# tv: 		uid TEXT PRIMARY KEY, show TEXT, season NUMERIC, episode NUMERIC, title TEXT, genre TEXT, notes TEXT, added TEXT, released TEXT, ffp TEXT
#                42242243,              Psych,      04,                14          Think Tank,   unknown,   none,       2011/04/01, 2010/01/02,  /media/pdisk1/tv/Psych/Psych - Season 04/Psych - 04 - 14 - Think Tank.avi
# movies: uid TEXT PRIMARY KEY, title TEXT, director TEXT, actors TEXT, genre TEXT, notes TEXT, imdb TEXT, cover TEXT, added TEXT, released TEXT, ffp TEXT

# TODO
## write generic SQL read/write functions
## write function to return as much information (that will be written to sql) based on filename
## write function to query IMDB and return the information needed

use strict;
use warnings;
use 5.010;

use lib 'lib/';
use dex::util;

use lib '/home/conor/Dropbox/perl/_pm/';
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
$s{image_dir} = File::Spec->catdir($s{working_dir}, "imdb_images");

my @t1 = localtime;
print "% $0 started at ", nicetime(\@t1, "time"), "\n" if $s{verbose} ge 1;

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

## remove files that no longer exist
my @lt_remove_begin = localtime;
my $remove_results = remove_non_existent_entries($s{database});
my @lt_remove_end = localtime;
print "> done removing non-existent entries, took ", timetaken(\@lt_remove_begin, \@lt_remove_end), "\n" if $s{verbose} ge 1;

## find all the files.. all the files
my @lt_find_files_begin = localtime;
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
my @lt_find_files_end = localtime;
print "> done indexing, found ", scalar keys %files, " files, took ", timetaken(\@lt_find_files_begin, \@lt_find_files_end), "\n" if $s{verbose} ge 1;

## find out which ones are new and add them to the db
my @lt_find_new_files_begin = localtime;
my ($added, $processed) = (0, 0);
print "> adding new media to the db:\n" if $s{verbose} ge 1;
foreach my $ffp (keys %files) {
	$processed++;
	my $file = $files{$ffp}{basename};
	my $type = $files{$ffp}{type};
	
	print "$processed ::  processing '$file'.." if $s{verbose} ge 2;
	
	my $md5 = get_md5($file); # md5 of the filename string, not the file itself
	
	if (already_added($s{database}, $md5, $type)) {
		print " " x (70 - length($file)), "already exists, skipping\n" if $s{verbose} ge 2;
		next;
	} else {
		print " " x (70 - length($file)), "unknown MD5, adding\n" if $s{verbose} ge 2;
	}
	
	# should have a $processed/$total print out here.. every 10%?
	
	my %file_info = get_info_from_filename($ffp, $file, $type);
	
	next if ($file_info{error}); # already logged a warning
	
	## now add to the db
	my $results = put_sql($s{database}, $type, \%file_info);
	
	
	$added++;
}
my @lt_find_new_files_end = localtime;
print "> done adding, found/added $added new files, took ", timetaken(\@lt_find_new_files_begin, \@lt_find_new_files_end), "\n" if $s{verbose} ge 1;

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
			return if $ffp =~ /\.(txt|log|srt|nfo|jpg|png|htm|ico|idx|sub|mp3|sfv|pdf|ini)$/i; # short blacklist

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

sub put_sql {
	# put_sql($database, $type, $href)  -- takes a hash of data and adds it to $database according to $type -- returns 0|1|2 for success|already known|failure
	my ($database, $type, $href) = @_;
	my %h = %{$href};
	my $results = 0;
	my $table;
	my $query;
	
	## cleanup for SQL
	foreach my $key (keys %h) {
		$h{$key} =~ s/'/^/g; # changed from " to ^ so that we can easily convert backwards
	}
	
	return 2 unless -f $database;
	
	my $dbh = DBI->connect("dbi:SQLite:$database") or warn "WARN:: unable to connect to '$database': $DBI::errstr" and return 2;
	
	if ($type =~ /tv/) {
		$table = 'tbl_tv';
		
		# tv: 		uid TEXT PRIMARY KEY, show TEXT, season NUMERIC, episode NUMERIC, title TEXT, genre TEXT, notes TEXT, added TEXT, released TEXT, ffp TEXT
		$query = $dbh->prepare("
					INSERT
					INTO $table
					(uid, show, season, episode, title, genre, notes, added, released, ffp)
					VALUES ('$h{uid}', '$h{show}', '$h{season}', '$h{episode}', '$h{title}', '$h{genre}', '$h{notes}', '$h{added}', '$h{released}', '$h{ffp}')
					");

		
	} elsif ($type =~ /movie/) {
		$table = 'tbl_movies';
		
		# movies: uid TEXT PRIMARY KEY, title TEXT, director TEXT, actors TEXT, genre TEXT, notes TEXT, imdb TEXT, cover TEXT, added TEXT, released TEXT, ffp TEXT
		$query = $dbh->prepare("INSERT
				       INTO $table
				       (uid, title, director, actors, genre, notes, imdb, cover, added, released, ffp)
				       VALUES ('$h{uid}', '$h{title}', '$h{director}', '$h{actors}', '$h{genre}', '$h{notes}', '$h{imdb}', '$h{cover}', '$h{added}', '$h{released}', '$h{ffp}')
							   ");
		
	} else {
		warn "WARN:: unknown type '$type'";
		return 2;
	}
	
	my $qresults;

	eval {
		$qresults = $query->execute;
	};
	
	if ($@) {
		$results = 2;
		warn "WARN:: unable to add entry: $DBI::errstr";
	}
	
	$dbh->disconnect;
	
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
	
	# tv: 	  uid TEXT PRIMARY KEY, show TEXT, season NUMERIC, episode NUMERIC, title TEXT, genre TEXT, notes TEXT, added TEXT, released TEXT, ffp TEXT
	# movies: uid TEXT PRIMARY KEY, title TEXT, director TEXT, actors TEXT, genre TEXT, notes TEXT, imdb TEXT, cover TEXT, added TEXT, released TEXT, ffp TEXT
	
	while (my @r = $query->fetchrow_array()) {
		if ($type =~ /tv/) {
			my $u = $r[0];
			$h{$u}{show}     = $r[1];
			$h{$u}{season}   = $r[2];
			$h{$u}{episode}  = $r[3];
			$h{$u}{title}    = $r[4];
			$h{$u}{genre}    = $r[5];
			$h{$u}{notes}    = $r[6];
			$h{$u}{added}    = $r[7];
			$h{$u}{released} = $r[8];
			$h{$u}{ffp}      = $r[9];

			
		} else {
			my $u = $r[0];
			$h{$u}{title}    = $r[1];
			$h{$u}{director} = $r[2];
			$h{$u}{actors}   = $r[3];
			$h{$u}{genre}    = $r[4];
			$h{$u}{notes}    = $r[5];			
			$h{$u}{imdb}     = $r[6];
			$h{$u}{cover}    = $r[7];
			$h{$u}{added}    = $r[8];
			$h{$u}{released} = $r[9];
			$h{$u}{ffp}      = $r[10];
		}
	}
	
	$dbh->disconnect;
	
	return \%h;
}

sub already_added {
	# already_added($database, $md5, $type) -- does a quick check to determine if the $md5 passed is already in the $database -- returns 0|1 for no|yes
	my ($database, $md5, $type) = @_;
	my $results = 0;
	
	# we should check to see if the folder path has changed, and if so, delete the current entry
	
	my $table = $s{table}{$type};
	my $sql   = "SELECT * from $table WHERE UID == \"$md5\""; # don't really need the whole match, but get_sql() freaks out if not
	
	my $q = get_sql($database, $sql, $type);
	
	$results = (keys %{$q}) ? 1 : 0;
	
	return $results;
}

sub remove_non_existent_entries {
	# remove_non_existent_entries($database) -- iterates all entries in $database and drops the UID unless -f $ffp, returns 0|1/error_message based on success|failure
	# might be faster to do this after indexing (but would require us to load the entire DB into memory to compare)
	my $database = shift;
	
	print "> remove_non_existent_entries($database):\n" if $s{verbose} ge 1;
	
	my ($dbh, $query, $q); # scope hacking
	
	foreach my $type (@{$s{media_types}}) {
		my $table = $s{table}{$type};
		my $sql   = "SELECT uid,ffp FROM $table";
		
		my %removes;
		
		$dbh = DBI->connect("dbi:SQLite:$database");
		unless ($dbh) {
			warn "WARN:: unable to connect to '$database': $DBI::errstr";
			return 1;
		}
		
		$query = $dbh->prepare($sql);
		unless ($query) {
			warn "WARN:: unable to prepare '$sql': $DBI::errstr";
			return 1;
		}
		
		$q = $query->execute;
		return $DBI::errstr if defined $DBI::errstr;

		while (my @r = $query->fetchrow_array()) {
			my $uid = $r[0];
			my $ffp = $r[1];
		
			# see if the file still exists
			unless (-f $ffp) {
				# DELETE FROM tbl_tv WHERE uid == "ab3bc886eebe63ee5487fef62e3523e2"
				# can't run deletes in the middle of a fetchrow, add UIDs to a hash 
				$removes{$uid} = $ffp;
			}
			
			# done iterating this tables results
		}
		
		# now actually removing the entries
		foreach my $uid (keys %removes) {
			my $ffp = $removes{$uid}; # need to undo any changes made to insert into SQL
			
			$ffp =~ s/^/'/g;
			
			print "  removing '$ffp' ($uid)\n" if $s{verbose} ge 1;
			$sql = "DELETE FROM $table WHERE uid == \"$uid\"";
			$query = $dbh->prepare($sql);
			$q     = $query->execute;
			
			return $DBI::errstr if defined $DBI::errstr;
		}
		
		print "  done locating non-existent '$type'\n" if $s{verbose} ge 2;
		($query, $q) = (undef, undef); # don't want to key off of the last loop
	}
	
	$dbh->disconnect;	
	
	return 0;
}