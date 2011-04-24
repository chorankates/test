package dex::util;
use strict;
use warnings;

use DBD::SQLite;
use Digest::MD5;
use File::Basename;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(log_error create_db nicetime);
our @EXPORT = qw(get_info_from_filename  get_md5);

# this will be used as an output for error_log()
%CFG::log = (
    error_file => "dex-crawl_error." . time . ".log",
);

# this should be kept in sync with dex-crawl.pl's $s{dir}, but in reality, should remain fairly static
%CFG::sources = (
		tv 	=> [ '/media/pdisk1/tv/', ],
		movies	=> [ '/media/pdisk2/movies/', ],
);

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
	
	# this is kind of cheating..
	my $tmp_ffp = $ffp;
	my $rel_str = join("|", @{$CFG::sources{$type}});
	$tmp_ffp =~ s/\Q$rel_str//;
	$h{relpath} = $tmp_ffp;

	
	if ($type =~ /movie/i) {
		# movies: uid TEXT PRIMARY KEY, title TEXT, director TEXT, actors TEXT, genre TEXT, notes TEXT, imdb TEXT, cover TEXT, added TEXT, released TEXT, relpath TEXT
		# Megamind (2010).avi
		
		my $title = $1 if $ffp =~ /.*\/(.*)\..*?$/;
		my $year  = $2 if $ffp =~ /.*\/(.*?)\s?\((.*?)\)\..*?$/;
		
		$title =~ s/\s*\($year\)// if defined $year; # strip out ' ($year)'
		$year = 'unknown' unless defined $year;
		
		unless ($title and $year) {
			$h{error} = "unrecognized filename format: $ffp";
			log_error($h{error});
			
			return %h;
		}
		
		$h{title} = $title;
		$h{released}  = $year;
		
		$h{cover} = 'unknown';
		$h{imdb}  = ''; # generate this here
		$h{genre} = 'unknown'; # for now, we'll parse this via the imdb address later
		$h{actors} = 'unknown'; # again, for now
		$h{director} = 'unknown';
	
		# tv returns on its own, but we rely on a fall through return.. why?
		
	} elsif ($type =~ /tv/i) {
		# tv: 		uid TEXT PRIMARY KEY, show TEXT, season NUMERIC, episode NUMERIC, title TEXT, genre TEXT, notes TEXT, added TEXT, released TEXT
		#my $count = $file =~ /-/g; # this will not work if there are -'s in the episode name
		my @t = $file =~ /-/g;
		my $count = (@t) ? $#t + 1 : 0; # lol @ typecasting
		
		unless ($#t) {
			$h{error} = "unknown file format: $ffp";
			log_error($h{error});
			return %h;
		}
		
		$h{released} = 'unknown'; # don't currently have a good way of pulling this
		$h{genre}    = 'unknown';
		
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
		
		$h{title} =~ s/(\..*?$)//; # chopping the file extension
		
		return %h;
		
	} else {
		warn "WARN:: invalid type '$type', returning empty hash\n";
		return %h;
	}
	
	return %h;
}

sub log_error {
	# log_error($filename, $string) -- throws an error to the console and writes out to $s{log_error}
	my $filename = $CFG::log{error_file};
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
		
		# tv: 		uid TEXT PRIMARY KEY, show TEXT, season NUMERIC, episode NUMERIC, title TEXT, genre TEXT, notes TEXT, added TEXT, released TEXT
		$schema = 'uid TEXT PRIMARY KEY, title TEXT, director TEXT, actors TEXT, genre TEXT, notes TEXT, imdb TEXT, cover TEXT, added TEXT, released TEXT, relpath TEXT' if $tbl_name eq 'tbl_movies';
		$schema = 'uid TEXT PRIMARY KEY, show TEXT, season NUMERIC, episode NUMERIC, title TEXT, genre TEXT, notes TEXT, added TEXT, released TEXT, relpath TEXT'        if $tbl_name eq 'tbl_tv';
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


1;

