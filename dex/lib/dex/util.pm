package dex::util;
use strict;
use warnings;

use DBD::SQLite;
use Digest::MD5;
use File::Basename;
use LWP::UserAgent;
use URI::Escape;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(log_error create_db nicetime cleanup_sql cleanup_uri cleanup_filename escape_uri);
our @EXPORT = qw(get_info_from_filename get_md5 get_sql put_sql database_maintenance download_file get_imdb get_wikipedia);

# todo
# now that we're collecting wikipedia urls for tv shows, it makes sense to abstract the urls based on show title to another table..
# need to update get_imdb/wikipedia to store movie/episode summary in 'notes'

sub get_info_from_filename {
	# get_info_from_filename($ffp, $file, $type) -- returns a hash of information based on $ffp and $type (tv|movies)
	
	# if we can't parse the filename as expected, need to log it out to the error file and prevent it from being added to the DB until filename has been fixed
	
	my ($ffp, $file, $type) = @_;
	#my $file = (File::Spec->splitpath($ffp))[2];
	my %h;

	my $ctime;
	if (-f $ffp) {
		$ctime = scalar localtime((stat($ffp))[9]); # 10 = ctime, 9 = mtime.. getting better results with 9
	} else {
		$ctime = scalar localtime(time); # usually this will be a test from file_info.t
	}
	my @lt = localtime;
	my $atime = nicetime(\@lt, "both"); # will be adding this to the db as well for future additions
	$h{ctime} = $ctime; # not currently in the schema
	$h{added} = $atime; # added time
	$h{uid}      = get_md5($file); # this is an MD5 of the filename, not the file
	$h{notes} = '';
	
	# this is kind of cheating.. and we're not using this in the schema (for now)
	my $tmp_ffp = $ffp;
	
	$h{ffp} = $ffp;

	
	if ($type =~ /movie/i) {
		# movies: uid TEXT PRIMARY KEY, title TEXT, director TEXT, actors TEXT, genres TEXT, notes TEXT, imdb TEXT, cover TEXT, added TEXT, released TEXT, ffp TEXT
		# Megamind (2010).avi
		
		my $title = $1 if $ffp =~ /.*\/(.*)\..*?$/;
		my $year  = $2 if $ffp =~ /.*\/(.*?)\s?\((.*?)\)\..*?$/;
		
		$title =~ s/\s*\($year\)// if defined $year; # strip out ' ($year)'
		$year = 'not_set' unless defined $year;
		
		my @dots = $title =~ /\./g;
		if (($title =~ /\[|\]/) or ($#dots gt 1)) {
			$h{error} = "bad characters found: $ffp";
			log_error($h{error});
			
			return %h;
		}
		
		unless ($title and $year) {
			$h{error} = "unrecognized filename format: $ffp";
			log_error($h{error});
			
			return %h;
		}
		
		$h{title} = $title;
		$h{released}  = $year;
		
		$h{cover}    = 'not_set';
		$h{imdb}     = get_external_link(\%h, 'imdb'); # this is just a link, another function will recurse through and populate genres/actors/director
		$h{genres}   = 'not_set'; # for now, we'll parse this via the imdb address later
		$h{actors}   = 'not_set'; # again, for now
		$h{director} = 'not_set';
	
		# tv returns on its own, but we rely on a fall through return.. why?
		
	} elsif ($type =~ /tv/i) {
		# tv: 		uid TEXT PRIMARY KEY, show TEXT, season NUMERIC, episode NUMERIC, title TEXT, actors TEXT, genres TEXT, notes TEXT, added TEXT, released TEXT
		#my $count = $file =~ /-/g; # this will not work if there are -'s in the episode name
		my @t = $file =~ /-/g;
		my $count = (@t) ? $#t + 1 : 0; # lol @ typecasting
		
		unless ($#t) {
			$h{error} = "unknown filename format: $ffp";
			log_error($h{error});
			return %h;
		}
		
		$h{released}  = ($ffp =~ /\((\d*)\)$/) ? $1 : 'not_set'; # tries to match <series name> - <'season' \d> (<year>)
		$h{genres}    = 'not_set';
		$h{cover}     = 'not_set'; 
		$h{actors}    = 'not_set';
		
		# why are we always getting 'n' when '0n' is passed in?
		
		my @a = split(/\s?-\s?/, $file);
		
		if ($count == 1) {
			# Angry Beavers - Zooing Time.mp4
			$h{show} = $a[0];
			$h{title}  = $a[1];
			
			$h{season}  = 'unknown';
			$h{episode} = 'unknown';
			
		} elsif ($count == 3) {
			# Burn Notice - 01 - 10 - False Flag.avi
			$h{show}  = $a[0];
			$h{season}  = $a[1];
			$h{episode} = $a[2];
			$h{title}   = $a[3];
			
		} elsif ($count >= 4) {
			
			if ($a[4] =~ /^\d*$/) {
				# Burn Notice - 01 - 11-12 - Drop Dead and Loose Ends.avi
				$h{show}  = $a[0];
				$h{season}  = $a[1];
				$h{episode} = $a[2] . '-' . $a[3];
				$h{title}   = join(" ", @a[4..$#a]);
			} else {
				# But could also be Burn Notice - 01 - 11 - Drop-Dead And Lose Ends
				$h{show}  = $a[0];
				$h{season}  = $a[1];
				$h{episode} = $a[2];
				$h{title}   = join("-", @a[3..$#a]);
			}
			
			
			
		} else {
			$h{error} = "unrecognized filename format: $ffp";
			log_error($h{error});
			return %h;
		}
		
		if ($h{title} =~ /~/) {
			$h{error} = "bad characters found in: $ffp";
			log_error($h{error});
			
			return %h;
		}
		
		$h{title} =~ s/(\..*?$)//; # chopping the file extension
		$h{wikipedia} = get_external_link(\%h, 'wikipedia'); # generate this here
		
		return %h;
		
	} else {
		warn "WARN:: invalid type '$type', returning empty hash\n";
		return %h;
	}
	
	return %h;
}

sub log_error {
	# log_error($filename, $string) -- throws an error to the console and writes out to $s{log_error}
	my $filename = $dex::util::settings{error_file};
    my $string = shift;
	
	my $fh;
	open($fh, '>>', $filename) or warn "WARN:: unable to open '$filename':$!";
	if ($fh) {
		print $fh scalar(localtime(time)) . "::" . $string . "\n";
		close($fh);
	}
	
	warn "WARN:: $string\n"; # key off of verbosity?
	
	return;
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

sub get_md5 {
	# get_md5($string) -- returns MD5 based on $string
	my $string = shift;
	my $results;
	
	$results = Digest::MD5::md5_hex($string);
	
	return $results;
}

sub get_sql {
    # get_sql($database, $type, $addl_sql) - returns (\%hash, $match_count) containing database matches
    my $database = shift;
    my $type = shift;
    
    # addl_sql will be appended to the SELECT * enforced -- ex: WHERE id == "foo"
    my $addl_sql = shift;
    
    my %h;

    my ($dbh, $sql, $query, $q, $table);
    
    $dbh = DBI->connect("dbi:SQLite:$database");
    unless ($dbh) {
        warn "WARN:: unable to connect to '$database': $DBI::errstr";
        return 1;
    }
    
	
	$table = $dex::util::settings{table}{$type};
    $sql   = "SELECT * FROM $table";    
	$sql  .= " $addl_sql" if defined $addl_sql; # herp

	eval {
		$query = $dbh->prepare($sql);
		$q     = $query->execute;
	};
	
	if ($@) {
		warn "WARN:: sql '$sql' failed: $@";
		return (\%h, -1);
	}
	
    
    ## handle the different data structures
    my $match_count = 0;
    while (my @r = $query->fetchrow_array()) {
        $match_count++;
        if ($type eq 'stats') {
			# $schema = 'uid TEXT PRIMARY KEY, name TEXT, value TEXT' if $tbl_name eq 'tbl_stats';
            my $uid   = $r[0];
            my $name  = $r[1];
            my $value = $r[2];
            
            $h{$name} = $value; # this hash is special
            
        } elsif ($type eq 'tv') {
            # $schema = 'uid TEXT PRIMARY KEY, show TEXT, season NUMERIC, episode NUMERIC, title TEXT, actors TEXT, genres TEXT, notes TEXT, wikipedia TEXT, cover TEXT added TEXT, released TEXT, ffp TEXT' if $tbl_name eq 'tbl_tv';
			my $u = $r[0];
			$h{$u}{show}      = $r[1];
			$h{$u}{season}    = $r[2];
			$h{$u}{episode}   = $r[3];
			$h{$u}{title}     = $r[4];
			$h{$u}{actors}    = $r[5];
			$h{$u}{genres}    = $r[6];
			$h{$u}{notes}     = $r[7];
			$h{$u}{wikipedia} = $r[8];
			$h{$u}{cover}     = $r[9];
			$h{$u}{added}     = $r[10];
			$h{$u}{released}  = $r[11];
			$h{$u}{ffp}       = $r[12];

		} elsif ($type eq 'movies') {
            # $schema = 'uid TEXT PRIMARY KEY, title TEXT, director TEXT, actors TEXT, genres TEXT, notes TEXT, imdb TEXT, cover TEXT, added TEXT, released TEXT, ffp TEXT' if $tbl_name eq 'tbl_movies';
            my $u = $r[0];
			$h{$u}{title}    = $r[1];
			$h{$u}{director} = $r[2];
			$h{$u}{actors}   = $r[3];
			$h{$u}{genres}   = $r[4];
			$h{$u}{notes}    = $r[5];			
			$h{$u}{imdb}     = $r[6];
			$h{$u}{cover}    = $r[7];
			$h{$u}{added}    = $r[8];
			$h{$u}{released} = $r[9];
			$h{$u}{ffp}      = $r[10];

            
        } else {
            err("trying to get_sql on an unknown type: $type");
        }
    }
    
    $dbh->disconnect;
    
	unless ($match_count == 0) {
		# %h = cleanup_sql(\%h, 'out') unless $match_count == 0; # yeah, should probably fix this on the other side too
		if($type eq 'stats') {
			# stats is always a simple hash
			%h = cleanup_sql(\%h, 'out'); 
		} else {
			# tv and movie are defined as HoH (even if only one match)
		    foreach my $entry (keys %h) { 
				# this is so hacktastic.. is there a wantarray equivalent for hashes?
				my %lh = cleanup_sql($h{$entry}, "out");
				$h{$entry} = \%lh;
		    }

		}
	}
	
	
    return (\%h, $match_count);
}

sub put_sql {
	# put_sql($database, $type, $href, [update])  -- takes a hash of data and adds it to $database according to $type -- returns 0|1|2 for success|already known|failure
	my $database = shift;
	my $type = shift;
	my $href = shift;
	my $update = shift; # if this is set, update not insert
	my %h = %{$href};
	my $results = 0;
	my $table;
	my $query;

	#$update = 1 if already_added($dex::util::settings{database}, $h{uid}, $type); # this is going to slow commits down, changing to argument spec

	#$h{$_} = cleanup_sql($_)  foreach (keys %h);
	%h = cleanup_sql(\%h, 'in'); # here we know we only have one hash key
	
	return 2 unless -f $database;
	
	my $dbh = DBI->connect("dbi:SQLite:$database") or warn "WARN:: unable to connect to '$database': $DBI::errstr" and return 2;
	
	if ($type =~ /tv/) {
		$table = 'tbl_tv';
		
		if ($update) {
			# do an update based on uid, this only works if we already have this uid.. should probably have some logic here
			$query = $dbh->prepare("UPDATE
					$table
					SET uid='$h{uid}', show='$h{show}', episode='$h{episode}', title='$h{title}', actors='$h{actors}', genres='$h{genres}', notes='$h{notes}', wikipedia='$h{wikipedia}', cover='$h{cover}', added='$h{added}', released='$h{released}', ffp='$h{ffp}'
					WHERE uid='$h{uid}'
					");
			
		} else {
			# tv: uid TEXT PRIMARY KEY, show TEXT, season NUMERIC, episode NUMERIC, title TEXT, actors TEXT, genres TEXT, notes TEXT, wikipedia TEXT, cover TEXT, added TEXT, released TEXT, ffp TEXT
			$query = $dbh->prepare("INSERT
					INTO $table
					(uid, show, season, episode, title, actors, genres, notes, wikipedia, cover, added, released, ffp)
					VALUES ('$h{uid}', '$h{show}', '$h{season}', '$h{episode}', '$h{title}', '$h{actors}', '$h{genres}', '$h{notes}', '$h{wikipedia}', '$h{cover}', '$h{added}', '$h{released}', '$h{ffp}')
					");
		}
		
	} elsif ($type =~ /movie/) {
		$table = 'tbl_movies';
		
		if ($update) { 
			# movies: uid TEXT PRIMARY KEY, title TEXT, director TEXT, actors TEXT, genres TEXT, notes TEXT, imdb TEXT, cover TEXT, added TEXT, released TEXT, ffp TEXT
			$query = $dbh->prepare("UPDATE
						$table
				        SET uid='$h{uid}', title='$h{title}', director='$h{director}', actors='$h{actors}', genres='$h{genres}', notes='$h{notes}', imdb='$h{imdb}', cover='$h{cover}', added='$h{added}', released='$h{released}', ffp='$h{ffp}'
						WHERE uid='$h{uid}'
						");
		} else {
			# movies: uid TEXT PRIMARY KEY, title TEXT, director TEXT, actors TEXT, genres TEXT, notes TEXT, imdb TEXT, cover TEXT, added TEXT, released TEXT, ffp TEXT
			$query = $dbh->prepare("INSERT
				       INTO $table
				       (uid, title, director, actors, genres, notes, imdb, cover, added, released, ffp)
				       VALUES ('$h{uid}', '$h{title}', '$h{director}', '$h{actors}', '$h{genres}', '$h{notes}', '$h{imdb}', '$h{cover}', '$h{added}', '$h{released}', '$h{ffp}')
							   ");
		}
		
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

sub cleanup_sql {
	# cleanup_sql(\%hash_of_text_to_be_used_in_sql, $direction) -- returns a 'sanitized' version of $sql_text -- direction is 'in'/'out' oriented on the database
	# sanitized not intended to mean secure, just 'prettier' characters
	my $href = shift;
	my $direction = shift;
	my %h = %{$href};
	
	return %h unless keys %h; # yep
	
	if ($direction =~ /in/i) {
		# these are going into the database, convert ' to ^
		foreach my $key (keys %h) {
			$h{$key} =~ s/'/^/g; 
		}
	} else {
		# these are coming out of the database, convert ^ to ' ()
		foreach my $key (keys %h) {
			$h{$key} =~ s/\^/'/g;
			$h{$key} =~ s/^(\d)$/0$1/g; # prepending 0 because the database is dropping unnecessary digits 
		}
	}

	return %h;
}

sub cleanup_uri {
	# uri_cleanup($string, $type) -- returns a URI escaped version of $string based on $type
	my $string = shift;
	my $type   = shift;
	my $results;
	
	#$results = URI::Escape::uri_escape($string); # this will give us %20, not +
	if ($type eq 'imdb') {
		$string =~ s/\s/\+/g; # turn ' 'into +
	} elsif ($type eq 'wikipedia') {
		$string =~ s/\s/_/g; # turn ' ' into _
	}

	$results = $string;

	# we're already warning above, no need to duplicate it here

	return $results;
}

sub create_db {
    # create_db($name) - creates a blank database ($name), returns 0 or an error message
    my $name = shift @_;
    my $results = 0;
    
	print "DBGZ" if 0;
	
    # need to open a db and create the default schema
    # default schema is:
    # CREATE TABLE tbl_main (url TEXT PRIMARY KEY, status_code TEXT, size NUMERIC, links TEXT)
    my @tables = values %{$dex::util::settings{table}};
    
    my $dbh = DBI->connect("dbi:SQLite:$name") or $results = $DBI::errstr;
    
    if ($results) { 
    	warn "WARN:: unable to open db '$name', bailing out of this function";
    	
    	# this falls through to the default 'return' statement
    	
    } else {
    	# so far so good
    	
		foreach my $tbl_name (@tables) {
			my $schema;
			
			# tv: 		uid TEXT PRIMARY KEY, show TEXT, season NUMERIC, episode NUMERIC, title TEXT, genres TEXT, notes TEXT, added TEXT, released TEXT
			$schema = 'uid TEXT PRIMARY KEY, title TEXT, director TEXT, actors TEXT, genres TEXT, notes TEXT, imdb TEXT, cover TEXT, added TEXT, released TEXT, ffp TEXT'                                   if $tbl_name eq 'tbl_movies';
			$schema = 'uid TEXT PRIMARY KEY, show TEXT, season NUMERIC, episode NUMERIC, title TEXT, actors TEXT, genres TEXT, notes TEXT, wikipedia TEXT, cover TEXT, added TEXT, released TEXT, ffp TEXT' if $tbl_name eq 'tbl_tv';
			$schema = 'uid TEXT PRIMARY KEY, name TEXT, value TEXT' if $tbl_name eq 'tbl_stats';
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
			
			my %h;
			if ($tbl_name =~ /tbl_stats/) {
				# in order to use 'UPDATE' in update_stats(), need to set default values for tbl_stats
				my @names = ('files_found', 'files_added_in_last_run', 'files_tv_count', 'files_movie_count', 'files_size_total', 'files_size_added');
				
				foreach my $name (@names) {
					$h{uid}   = get_md5($name);
					$h{name}  = $name;
					$h{value} = 0;
				
					my $sql = "INSERT INTO $tbl_name (uid, name, value) VALUES ('$h{uid}', '$h{name}', '$h{value}')";
					my $query = $dbh->prepare($sql);
					
					eval {
						$query->execute;
					};
					
					if ($@) {
						warn "WARN:: error while setting default stats: $@";
						return $results;
					}
				
				}
				# end of tbl_stats updates
			}
		
		# end of tbl_* creation
		}
		
		# end of if-else -- over commented, but there are an awful lot of closing braces round these parts
    }
    
    return $results;
}

sub get_wikipedia {
	# get_wikipedia(\%file_info) - given %file_info, returns a hash of information about the first match found (or an empty hash for error)
	my $href = shift;
	my %file_info = %{$href};
	my %h;
	
	my $search_url = $file_info{wikipedia}; # this is usually a direct link, not a search url
	
	return %h unless defined $search_url;
	
	my $worker = LWP::UserAgent->new();
	   $worker->agent($dex::util::settings{browser}{useragent});
	   $worker->timeout($dex::util::settings{browser}{timeout});
	   
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
	
	return %h unless defined $search_url;
	
	my $worker = LWP::UserAgent->new();
	   $worker->agent($dex::util::settings{browser}{useragent});
	   $worker->timeout($dex::util::settings{browser}{timeout});
	
	# get the search result page
	my $search_time_begin = Time::HiRes::gettimeofday();
	my $response  = $worker->get($search_url);
	my $search_time_end = Time::HiRes::gettimeofday();
	print "      search took ", substr(($search_time_end - $search_time_begin), 0, 5), "s\n" if $dex::util::settings{verbose} ge 3;
	
	# we also need to download the cover image to $s{image_dir}
	my @search_contents = $response->content;
	
	my $rel_link     = 'http://www.imdb.com';
	my $title_path   = $1 if @search_contents ~~ /href="(\/title\/tt\d*\/)"/ig;
	
	unless ($title_path) {
		$h{error} = "error finding wikipedia page for $file_info{title} from $search_url";
		log_error($h{error});
		return %h;
	}
	
	my $content_link = $rel_link . $title_path; 
	
	# get the content result page
	my $content_time_begin = Time::HiRes::gettimeofday();
	$response = $worker->get($content_link);
	my @results_contents = $response->content;
	my $content_time_end = Time::HiRes::gettimeofday();
	print "      results fetch took ", substr(($content_time_end - $content_time_begin), 0, 5), "s\n" if $dex::util::settings{verbose} ge 3;
	
	# extract basic information from @results_contents
	$h{new_imdb}  = $content_link; # contains the actual address to the imdb page, not the search results
	$h{released}  = $1 if @results_contents ~~ /\<span\>\(\<a\shref=".*?\/year\/.*\>(\d*?)\<\/a\>\)<\/span\>/ims;
	$h{director}  = $1 if @results_contents ~~ /Director\:.*?"\>(.*?)\<\/a\>\<\/div\>/ims;
	$h{www_cover} = $1 if @results_contents ~~ /\<a\s*onclick="\(new\sImage.*?\>\<img\ssrc="(.*?)".*?Poster"\s*\/\>\<\/a\>/ims; # need to download this file to $s{image_dir}, then set $h{cover} to the filename in $s{image_dir}
	
	$h{notes}     = $1 if @results_contents ~~ /\<p\>..\<p\>([^\>|\<]*?)\<\/p\>..\<\/p\>/ims;         # this is a little brittle, but it's the short version of the summary on the next line
	$h{summary}   = $1 if @results_contents ~~ /\<h2\>Storyline\<\/h2\>....\<p\>([^\<\>]*?)...\</ims; # this one is stronger, but also longer.. <3 daft punk
	$h{notes} = $h{summary} unless defined $h{notes};
	
	unless ($h{new_imdb} and $h{released} and $h{director} and $h{www_cover}) {
		my $imdb = (defined $h{new_imdb}) ? "new: $h{new_imdb}" : "old: $h{imdb}";
		$h{error} = "error gathering wikipedia information for $file_info{title} from $imdb";
		log_error($h{error});
		return %h;
	}
	
	# extract extended information
	my $download_filename = File::Spec->catfile($dex::util::settings{image_dir}, basename($file_info{ffp}));
	   $download_filename =~ s/\..*?$/\.jpg/i;
	if (! -f $download_filename) {
		my $download_results  = download_file($h{www_cover}, $download_filename);
		$h{cover} = ($download_results eq 0) ? $download_filename : "unable to download: $h{www_cover}";
	} else {
		$h{cover} = $download_filename;
	}
	
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

sub database_maintenance {
	# database_maintenance () -- iterates all entries in $database and drops the UID unless -f $ffp, then tries to find wiki/imdb information about the remaining files, returns ($tv_removed, $tv_wiki_added, $movies_removed, $movie_imdb_added)
	# might be faster to do this after indexing (but would require us to load the entire DB into memory to compare)
	my $database = $dex::util::settings{database};
	my @media_types = @{$dex::util::settings{media_types}};
	my %media_tables = %{$dex::util::settings{table}};
	
	my ($dbh, $query, $q); # scope hacking
	
	my ($tv_removed, $tv_added, $movies_removed, $movies_added) = (0, 0, 0, 0);
	
	foreach my $type (@media_types) {
		my $table = $media_tables{$type};
		#my $sql   = "SELECT uid,ffp FROM $table";
		my $sql   = "SELECT * FROM $table";
		
		my %removes;
		my %external_media;
		
		$dbh = DBI->connect("dbi:SQLite:$database");
		return (-1, "unable to connect to '$database': $DBI::errstr") unless $dbh;
		
		$query = $dbh->prepare($sql);
		return (-1, "unable to prepare '$sql': $DBI::errstr") unless $query;
		
		$q = $query->execute;
		return $DBI::errstr if defined $DBI::errstr;

		# iterating all database entries
		while (my @r = $query->fetchrow_array()) {
#			$schema = 'uid TEXT PRIMARY KEY, title TEXT, director TEXT, actors TEXT, genres TEXT, notes TEXT, imdb TEXT, cover TEXT, added TEXT, released TEXT, ffp TEXT'                                   if $tbl_name eq 'tbl_movies';
#			$schema = 'uid TEXT PRIMARY KEY, show TEXT, season NUMERIC, episode NUMERIC, title TEXT, actors TEXT, genres TEXT, notes TEXT, wikipedia TEXT, cover TEXT, added TEXT, released TEXT, ffp TEXT' if $tbl_name eq 'tbl_tv';
			# common
			my %qh;
			
			# don't like having to keep this in 2 places, but get_sql() is best suited for queries, and we're iterating here
			if ($type eq 'movies') {
				$qh{uid} = $r[0];
				$qh{title}    = $r[1];
				$qh{director} = $r[2];
				$qh{actors}   = $r[3];
				$qh{genres}   = $r[4];
				$qh{notes}    = $r[5];			
				$qh{imdb}     = $r[6];
				$qh{cover}    = $r[7];
				$qh{added}    = $r[8];
				$qh{released} = $r[9];
				$qh{ffp}      = $r[10];
			} elsif ($type eq 'tv') {
				$qh{uid} = $r[0];				
				$qh{show}      = $r[1];
				$qh{season}    = $r[2];
				$qh{episode}   = $r[3];
				$qh{title}     = $r[4];
				$qh{actors}    = $r[5];
				$qh{genres}    = $r[6];
				$qh{notes}     = $r[7];
				$qh{wikipedia} = $r[8];
				$qh{cover}     = $r[9];
				$qh{added}     = $r[10];
				$qh{released}  = $r[11];
				$qh{ffp}       = $r[12];

			} else {
				return (-1, "unknown table '$type'");
			}

			# $qh{type} = $type; # doing this for reference in %external_media -- just use $type
			%qh = cleanup_sql(\%qh, 'out');
			#$ffp =~ s/\^/'/g;
		
			# see if the file still exists
			unless (-f $qh{ffp}) {
				# DELETE FROM tbl_tv WHERE uid == "ab3bc886eebe63ee5487fef62e3523e2"
				# can't run deletes in the middle of a fetchrow, add UIDs to a hash 
				$removes{$qh{uid}} = $qh{ffp};
				
				$tv_removed++     if $type =~ /tv/i;
				$movies_removed++ if $type =~ /movies/i;
			}
			
			if (-f $qh{ffp}) {
				# need to check to see if it has wiki entries or not -- and if these values = unknown, it means we've tried to get them before and failed
				if ($type eq 'tv') {
					if (! -f $qh{cover} or $qh{actors} eq 'unknown' or $qh{genres} eq 'unknown') {
						# log_error("incomplete information on $type: $qh{show} - $qh{title}"); # haven't written this functionality yet
					} else {
						$external_media{$qh{uid}} = \%qh;
					}
					
				} elsif ($type eq 'movies') {
					if (! -f $qh{cover} or $qh{actors} eq 'unknown' or $qh{director} eq 'unknown' or $qh{genres} eq 'unknown') {
						log_error("incomplete information on $type: $qh{title}");
					} elsif ($qh{actors} eq 'not_set' or $qh{director} eq 'not_set' or $qh{genres} eq 'not_set') {
						$external_media{$qh{uid}} = \%qh;
					} else {
						# we already have information on this file, skip
					}
				}
				
				# done with checking for wikipedia/imdb entries
			}
			
			# done iterating this tables results
		}
		
		# remove the entries where file DNE
		foreach my $uid (keys %removes) {
			my $ffp = $removes{$uid}; # need to undo any changes made to insert into SQL
			
			print "  removing '$ffp' ($uid)\n" if $dex::util::settings{verbose} ge 1;
			$sql = "DELETE FROM $table WHERE uid == \"$uid\"";
			$query = $dbh->prepare($sql);
			$q     = $query->execute;
			
			return (-1, $DBI::errstr) if defined $DBI::errstr;
		}
		
		print "  done locating non-existent '$type'\n" if $dex::util::settings{verbose} ge 2;
		
		# get wikipedia/imdb information where we don't have it
		foreach my $uid (keys %external_media) {
			my $href = $external_media{$uid};
			my %lh   = %{$href};
			my $query_success = 0;
			
			## traffic cop for movies/tv here
			if ($type eq 'movies' and $dex::util::settings{retrieve_imdb}) {
				# need to try and get the wikipedia information
				print "    get_imdb($lh{title})\n" if $dex::util::settings{verbose} ge 1;
				my %movie_info = get_imdb(\%lh);
				
				my $error = (defined $movie_info{error}) ? $movie_info{error} : 0;
				
				if (keys %movie_info and not $error) {
					# successful call, add information to %file_info (need to update the $files{$ffp}{imdb} entry to be the actual page, not search page)
					$lh{released} = $movie_info{released} // 'unknown';
					$lh{director} = $movie_info{director} // 'unknown';
					$lh{imdb}     = $movie_info{new_imdb} // $lh{imdb};
					$lh{cover}    = $movie_info{cover}    // 'unknown';
					$lh{actors}   = $movie_info{actors}   // 'unknown';
					$lh{genres}   = $movie_info{genres}   // 'unknown';
					$lh{notes}    = $movie_info{notes}    // 'unknown';
					
					$query_success = 1;
					$movies_added++;
				} else {
					# unsuccessful call, throw a warning
					#log_error("unable to get imdb information for '$lh{ffp}' from '$lh{imdb}'");
					$query_success = 1; # not actually a success,but we want to save 'unknown' data so we don't query this again
					$lh{director} = 'unknown';
					$lh{actors}    = 'unknown';
					$lh{genres}    = 'unknown';
					$lh{cover}     = 'unknown';
				}
				
			} elsif ($type eq 'tv' and $dex::util::settings{retrieve_wikipedia}) {
	
				# haven't written the get_wikipedia() function yet
				#print "    get_wikipedia($lh{title})\n" if $dex::util::settings{verbose} ge 1;
				#my %tv_info = get_wikipedia(\%lh);
				$query_success = 0;  # forcing failure for now
				
				# don't forget to inc $tv_added
				
			}
			
			if ($query_success) {
				# we got good info from imdb/wikipedia, add this to the db
				my $results = put_sql($dex::util::settings{database}, $type, \%lh, 1); # final 1 is to specify this to be an update put not insert
			}
			
			return (-1, $DBI::errstr) if defined $DBI::errstr;
		}
		
		print "  done getting wikipedia/imdb information for '$type'\n" if $dex::util::settings{verbose} ge 2;
		($query, $q) = (undef, undef); # don't want to key off of the last loop
	}
	
	$dbh->disconnect;	
	
	#return ($tv_removed, $movies_removed);
	return ($tv_removed, $tv_added, $movies_removed, $movies_added);
}

# $h{wikipedia} = get_external_link(\%h, 'wikipedia'); # generate this here
sub get_external_link {
	# get_external_link(\%file_info, $site) -- returns 0 or a link on $site for the file in \%file_info
	my ($href, $site) = @_;
	my $url;
	
	my %h = %{$href};
	
	if ($site eq 'imdb') {
		# movies
		# sample url = http://www.imdb.com/find?s=tt&q=indiana+jones
		# s=tt means search for movie titles
		# q=<query>
		# need to do some cleanup
		%h = cleanup_sql(\%h, 'out');
		
		my $base_url = 'http://www.imdb.com/find?s=tt&q=';
	    my $query    = cleanup_uri($h{title}, $site); #
		
		$url = $base_url . $query;
		
	} elsif ($site eq 'wikipedia') {
		# probably tv, but maybe movies in the future
		# sample url = http://en.wikipedia.org/wiki/Nikita_(tv_series)
		# always want to append '(tv series)' for best results
		my $base_url = 'http://en.wikipedia.org/wiki/';
		my $query = cleanup_uri($h{show}, $site); 
		my $append = '_(tv_series)';
		
		$url = $base_url . $query  . $append;
		
	} else {
		warn "WARN:: unknown site '$site' specified in get_external_link()";
		return 0;
	}
	
	return $url;
}

sub download_file {
	# download_file($url, $ffp) - downloads $url to $ffp, returns 0|1 for success|failure
	my ($url, $ffp) = @_;
	
	my $worker = LWP::UserAgent->new();
	   $worker->agent($dex::util::settings{browser}{useragent});
	   $worker->timeout($dex::util::settings{browser}{timeout});
	
	my $request = HTTP::Request->new(GET => $url);
	my $response = $worker->get($url, ':content_file' => $ffp);
	
	if ($response->is_success) {
		return 0;
	} else {
		return 1;
	}
}

sub nicetime {
    # nicetime(\@time, type) - returns time/date according to the type 
    # types are: time, date, both
    my $aref = shift @_; my @time = @{$aref};
    my $type = shift @_ || "both"; # default variables ftw.
    warn "warn> nicetime: type '$type' unknown" unless ($type =~ /time|date|both/);
    warn "warn> nicetime: \@time may not be properly populated (", scalar @time, " elements)" unless scalar @time == 9;


    my $hour = $time[2]; my $minute = $time[1]; my $second = $time[0];
    $hour    = 0 . $hour   if $hour   < 10;
    $minute  = 0 . $minute if $minute < 10;
    $second  = 0 . $second if $second < 10;

    my $day = $time[3]; my $month = $time[4] + 1; my $year = $time[5] + 1900;
    $day   = 0 . $day   if $day   < 10;
    $month = 0 . $month if $month < 10;

    my $time = $hour .  "." . $minute . "." . $second;
    #my $date = $month . "." . $day    . "." . $year; 
    my $date = $year . "." . $month . "." . $day; # new style, makes for better sorting

    my $full = $date . "-" . $time;

    if ($type eq "time") { return $time; }
    if ($type eq "date") { return $date; }
    if ($type eq "both") { return $full; }
}


sub escape_uri {
	# uri_escape($string, [reverse]) - returns a URI escaped version of $string, if [reverse] is specified, we unescape it
	my $string    = shift;
	my $direction = shift // 0;
	
	my $results;
	
	if ($direction) {
		$results = URI::Escape::uri_unescape($string);
	} else {
		$results = URI::Escape::uri_escape($string);
	}
 	
	return $results;
}

1;

