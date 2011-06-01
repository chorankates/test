#!/usr/bin/perl -w
## dex.cgi -- web interface for dex (influenced by dico)

# todo
# need to convert the single mode in get_table_for_printing() to be able to handle inline editing
# admin page
    #x add a way to view errors
    # need to add controls to force a new scan
# need to do some processing on links to prevent accidental (or intentional) sql injection from episodes with quotation marks in them -- also, they need to be carets to match database entries
# add a 'summary' page that pulls unique attributes from both databases (total count, tv episodes, top directors / actors, etc) -- this probably should also be stored in a table and could be updated by db_maintenance()
# need to determine how feasible it is to allow ORDER BY queries to be used in $addl_sql, since we're adding results to a hash.. would have to give each entry an incremental number coming out of the db, then sort based on that when displaying the results
# stuff the search forms on the home page into collapsible divs.. did this for another project, but can't remember which one

use strict;
use warnings;
use 5.010;

use CGI ':standard';
use CGI::Carp 'fatalsToBrowser'; # dbgz
use Data::Dumper;
use DBD::SQLite;
use File::Basename;
require File::Spec;
use Time::HiRes;

use lib '/home/conor/Dropbox/perl/_pm';
use ironhide;

use lib '/home/conor/git/test/dex/lib';
use dex::util;

my $time_start = Time::HiRes::gettimeofday();


## define some defaults
my (%d, %p, %s); # database, incoming parameters, settings

%s = (
    host         => "http://192.168.1.122",
    #host         => get_ip(),
    host_dir     => '/dex/',
    cgi_dir      => '/cgi-bin/',
    
    db_folder    => "/home/conor/dex/", # having www-data permission issues when trying to updated the DB in Dropbox
    db           => "", # dynamically defined below
    
    error_file         => "error_dex-crawl.log", # switching to a single log file
    function     => (param()) ? "executing function" : "waiting for input",

    results_limit => 500, # puts a hard cap on the number of results returned from any db query (applied after any LIMIT calls)
    
    # scope hacking, this needs to be kept up to date with dex-crawl.pl
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
    
);


%dex::util::settings = %s; # excellent..
$s{cgi_address}   = $s{host} . $s{cgi_dir} . basename($0);
$s{image_dir_uri} = $s{host} . $s{host_dir} . "media_images/";
$s{image_dir}     = $s{db_folder} . "media_images/";
$s{db}            = $s{db_folder} . "dex.sqlite";

## global headers
html_start();
print get_stats_div();

## traffic cop
unless (param()) {
    # no params, build the start page
    print (h2("information"), "<ul>");
    
    my $cron       = "<br>&nbsp;&nbsp;&nbsp;" . join("<br>&nbsp;&nbsp;&nbsp;",cronread("dex"));
    my $db_link    = $s{host} . "/dex/dex.sqlite"; # previous solution was: just ran 'link /home/conor/Dropbox/perl/_7/_dico/results.sqlite /home/conor/drop/dico_results.sqlite'
    my $admin_link = $s{cgi_address} . '?function=admin';
    my @db_file    = stat $s{db};
    my $db_size    = nicesize($db_file[7]);
    my $movies_unknown_link = $s{cgi_address} . '?function=query&media=movies&notes=unknown&use_notes=on';
    
    my @information = (
        "dex is a media indexing/research system combining Perl, SQLite and a little HTML/CSS",
        "currently all queries parameters are boolean ANDs",
        "database <a href=$db_link>here</a> ($db_size)",
        "administration <a href=$admin_link>here</a>",
        "movies that need more info: <a href=$movies_unknown_link>here</a>",
        #"test-* functions may ignore specifications in 'new poke' table, <a href=$s_link>RTFS</a>",
	"/etc/crontab: $cron",
    );
    
    print "<ul>";
    foreach (@information) {
        print "<li>$_</li>";
    } print ("</ul>");
    
    # this is good code, but needs to be massaged before including it
    #print "<h3>recent additions ($s{total_results} total)</h3>";
    #print_table(10); # this is in flux
    #print "&nbsp;" x 10 . "<a href='" . $s{host} . "/cgi-bin/dico-wrapper.pl?function=query&builtin=most-recent&ceiling=100&use_ceiling=on&use_builtin=on'>100 more recent additions</a>..";
    
    print "<br>";
    #my $recent_sql = 'ORDER BY show DESC LIMIT 10';
    my $recent_sql = 'ORDER BY added DESC LIMIT 5';
    print h2("sample sql: " . $recent_sql);
    
    # get the last ten tv entries
    #print get_table_for_printing($s{db}, 'tv', 'multiple', $recent_sql);
    
    # get the last 5 movie entries (since they look prettier -- usually)
    print get_table_for_printing($s{db},  'movies', 'multiple', $recent_sql);
    
    print get_query_control();
    # end up for parameter page
    
    
} else {
    # do work son
   my @p = param();
   
   $p{$_} = param($_) foreach(@p); # this is a quick and dirty way to handle most parameters.. does not work when you've got multiple controls with the same name but different values
   
    dump_hash(\%p, "params"); # not a debug command in this context
    
    if (0) {
        # just some samples
        print h2("arrested development (multiple):");
        print get_table_for_printing($s{db}, 'tv', 'multiple', 'WHERE show LIKE \'%Arrested%\'');
        
        print h2("the i.t. crowd - calamity jane (single):");
        print get_table_for_printing($s{db},'tv', 'single', 'WHERE uid == \'4b8ba2eeccc49252a01776eadbb15422\'');
        
        print h2("indiana jones (multiple):");
        print get_table_for_printing($s{db}, 'movies', 'multiple', 'WHERE title LIKE \'%Indiana Jones%\'');
        
        print h2("the usual suspects (single):");
        print get_table_for_printing($s{db}, 'movies', 'single', 'WHERE uid == \'16153ca725d14826ed3857cf08996121\'');
    }
    
    # sub traffic cop
    if ($p{function} =~ /query/i) {
            # build a SQL query
        my @query;
        foreach my $param (keys %p) {
            next if $param eq 'function';
            next if $param eq 'media';
            next if $param =~ /use_/; # i know, but watch
            push @query, "$param LIKE '%$p{$param}%'" if $p{'use_'. $param};
        }
        
        my $query;
        if ($p{sql} and $p{use_sql}) {
            # override the default query with user input .. unsafe
            $query = $p{sql};
        } else {
            $query = 'WHERE ' . join(" and ", @query); # . ' ORDER BY DESC'; # appending an order is a good idea, but how can we generalize it?
        }
        
        print h2("query: $query");
        
        my $mode = ($p{uid} and $p{use_uid}) ? 'single' : 'multiple'; # if match_count returned from the get_sql() call == 1, we'll adapt << maybe
        my $media = $p{media};
        
        print get_table_for_printing($s{db}, $media, $mode, $query);
        
        # end of query page
        
    } elsif ($p{function} eq 'admin') {
        # administration page displays error log -- and allows for a rescan (not yet)
        my $fh;
        my $lresults;
        open ($fh, '<', $s{db_folder} . '/' . $s{error_file}) or $lresults = $!;
        if ($lresults) {
            dex::util::log_error("error opening error file '$s{error_file}' (yo dawg): $lresults");
        } else {
            my @c = <$fh>;
            print h2("contents of $s{error_file}:");
            print "<table border=0>";
            foreach (@c) {
                my $line = $_;
                   $line =~ /(.*?)\:\:(.*?)\:(.*)/;
                   
                my $timestamp = $1;
                my $error     = $2;
                my $unique    = $3;
                print "<tr><td>$timestamp</td><td>$error</td><td>$unique</td></tr>";
            }
            print "</table>";
        }
        
        print h2("rescanning options will come at some point");
        
        # end of admin page
    }
    
    # end of param/no param
}

my $time_finish = Time::HiRes::gettimeofday();
# end up
print(
    "<br><br>",
    "back to <a href=\"/cgi-bin/dex.cgi\">launcher</a><br>",
    "<br><br>rendered in " . substr(($time_finish - $time_start), 0, 5) . "s\n",
    #"back to <a href=\"/index.html\">index.html</a><br>",
    end_html()
    );


exit 0;

## subs below

sub html_start {
    # html_start() - obfuscation for the initial HTML headers
    
    print(
        header(),
        start_html(
            	-title=> "dex.cgi - $s{function}",
            	-text   => "black",
		-style => { src => $s{host} . '/dex.css' }
        ),
        "<div class=\"header\" align=\"right\"><h3><a href=\"",
        $s{host}, "/cgi-bin/dex.cgi", 
        "\" class=\"header\">dex.cgi</a></h3></div><br>",
    );
}

sub cronread {
    # cronread($match) - returns @array of all /etc/crontab entries that match $match
    my $match = shift @_;
    
    my ($fh, $cron, @results);
    
    $cron = "/etc/crontab";
    
    open($fh, '<', $cron) or return "ERROR:: unable to open '$cron':$!";
    
    
    while (<$fh>) {
	next if $_ =~ /#.*/; # skipping comment lines
	next unless $_ =~ /$match/; # skipping other cron jobs
        # 0 0 * * 0 conor diff -r -x *.jpg ~/Dropbox/perl ~/git/perl
        my $cmd;
        if ($_ =~ /.\s+.\s+.\s+.\s+.\s+(.*)/) {
            # $cmd = $1; # grabbed from the regex
            $cmd = $_; # let's take the whole line actually
            push @results, $cmd;
        }
    }
    close($fh);
    
    @results = "nothing currently scheduled" unless @results;
    
    return @results;
}

sub dump_hash {
    # dump_hash(\%hash, $type) - dumps the contents of %hash into a table based on $type
    my ($href, $type) = @_;
    my %h = %{$href};
    
    # build the table, make it look nice
    print(
        h2($type),
        "<table border='1'>",
        "<tr>",
        "<td><strong>key</strong></td>",
        "<td><strong>value</strong></td>",
    );

    #print "<tr><td>$_</td><td>$h{$_}</td></tr>" foreach sort keys %h;

    foreach (sort keys %h) {
        next unless $h{$_};
        print "<tr><td>$_</td><td>$h{$_}</td></tr>"    unless $h{$_} =~ /array/i;
        print "<tr><td>$_</td><td>@{$h{$_}}</td></tr>" if     $h{$_} =~ /array/i;
    }


    print "</table><br>";
    
    return;
    
}

sub err {
    # err(error message) - want to use this in a similar way as the CGI ':standard', so just return the formatted text
    my @return;
    
    while ($_ = shift @_) {
        my $new = "err: <font color=\"red\" size=\"+2\">" . $_ . "</font>";
        push @return, $new;
    }
    
    return @return
}

sub get_table_for_printing {
    # get_table_for_printing($database, $type, $mode, $addl_sql) - returns a string of a complete HTML table or throws an error
    my ($database, $type, $mode, $addl_sql) = @_;
    $addl_sql = '' unless defined $addl_sql;
    my $html;
    
    my ($href, $count); # will contain the results of a SQL query
    my %hash; # i don't like refs
    
    if ($type =~ /tv/) {
        ($href, $count) = get_sql($database, 'tv', $addl_sql);
    } elsif ($type =~ /movies/) {
        ($href, $count) = get_sql($database, 'movies', $addl_sql);
    } elsif ($type =~ /stats/) {
        ($href, $count) = get_sql($database, 'stats');
    }
    
    $mode = ($count == 1) ? 'single' : 'multiple'; # this will override the calling context.. hope thats all right
    
    unless (ref $href) { 
        print Dumper(\$href);
        die "DIE:: no results from get_sql() call, check for DB errors";
    }

    %hash = %{$href};
    my $processed_count = 0;
    my @table = ("<table border=0 width='80%'>"); 
    foreach (sort keys %hash) {
        my $uid = $_;
        my $str;
        
        my %lh = %{$hash{$uid}} if $type ne 'stats'; # hacky..

        # if we have an image, use that instead of the show title 
        if (defined $lh{cover} and -f $lh{cover}) {
            my $link = basename($lh{cover});
               $link = dex::util::escape_uri($link); # money
               $link = $s{image_dir_uri} . $link;
            $lh{image_uri} = "<img src='$link'>";
        } else {
            # default image to display
            my $link = $s{image_dir_uri} . "default.jpg";
            $lh{image_uri} = "<img src='$link'>";
        }        
        
        if ($type =~ /tv/) {
            #get_table_for_printing($s{db}, 'tv', 'multiple', 'ORDER BY added ASC LIMIT 10');

            # need to strip leading 0s?
            
            my $show_image_link = make_query_link($lh{show}, 'show', 'tv', $lh{image_uri});
            my $show_text_link  = make_query_link($lh{show}, 'show', 'tv');
            my $season_link     = make_query_link($lh{season}, 'season', 'tv'); # multiple queries would be cool here, could specify show AND season
            my $episode_link    = make_query_link($lh{episode}, 'epsiode', 'tv'); # this is kind of useless either way, but we can't not turn into a link
            my $title_link      = make_query_link($lh{title}, 'title', 'tv', $lh{title}); # this is mostly useless, but could find some cool intersections
            my $released_link   = make_query_link($lh{released}, 'released', 'tv');
            my $self_link       = make_query_link($uid, 'uid', 'tv', 'moar');
            my $wiki_link       = "<a href='$lh{wikipedia}'>$lh{wikipedia}</a>";

            if ($mode eq 'multiple') {
                # returns a vertical table with a limited number of attributes for each match
                # tv: 		uid TEXT PRIMARY KEY, show TEXT, season NUMERIC, episode NUMERIC, title TEXT, genres TEXT, notes TEXT, added TEXT, released TEXT
                
                $str = "<tr><td><strong>show</strong></td><td><strong>season #</strong></td><td><strong>episode #</strong></td><td><strong>title</strong></td><td><strong>released</strong></td><td>more</td></tr>\n" if $processed_count == 0;
                $str .= "<tr><td>$show_image_link<br>$show_text_link</td><td>$season_link</td><td>$episode_link</td><td>$title_link</td><td>$released_link</td><td>$self_link</td></tr>";
                
                print "DBGZ" if 0;
                
            } elsif ($mode eq 'single') {
                # this returns a horizontal based table containing all values in the hash, suitable for individual pages, but still supports being called multiple times
                unless (ref $hash{$uid}) {
                    warn "WARN:: weird datatype";
                    next;
                }
                
                $str = "<tr><td>$lh{image_uri}</td><td>&nbsp;</td></tr>\n
                <tr><td><strong>attribute</strong></td><td><strong>value</strong></td></tr>\n
                <tr><td>uid</td><td>$uid</td></tr>\n
                <tr><td>show</td><td>$lh{show}</td></tr>\n
                <tr><td>season</td><td>$lh{season}</td></tr>\n
                <tr><td>episode</td><td>$lh{episode}</td></tr>\n
                <tr><td>title</td><td>$lh{title}</td></tr>\n
                <tr><td>actors</td><td>$lh{actors}</td></tr>\n
                <tr><td>genres</td><td>$lh{genres}</td></tr>\n
                <tr><td>notes</td><td>$lh{notes}</td></tr>\n
                <tr><td>added</td><td>$lh{added}</td></tr>\n
                <tr><td>wikipedia</td><td>$wiki_link</td></tr>\n
                <tr><td>released</td><td>$lh{released}</td></tr>\n
                <tr><td>ffp</td><td>$lh{ffp}</td></tr>\n
                ";
                
                #$str .= "<tr><td>$_</td><td>$hash{$_}</td></tr>" foreach keys <-- this is the way forward
                
                # should we last here? 
                
                print "DBGZ" if 0;
            }
            
            # end of tv printing
            
        } elsif ($type =~ /movies/) {
            #get_table_for_printing($s{db}, 'movies', 'multiple', 'ORDER BY added ASC LIMIT 10');
            
            # need to strip leading 0s ?
            
            my $movie_image_link = make_query_link($lh{title}, 'title', 'movies', $lh{image_uri});
            my $movie_text_link  = make_query_link($lh{title}, 'title', 'movies');
            my $director_link    = make_query_link($lh{director}, 'director', 'movies');
            
            my @genres = split(",", $lh{genres});
            my $genres_link;
            foreach my $genre (@genres) {
                $genres_link .= make_query_link($genre, 'genres', 'movies') . " ";
            }
            
            my @actors = split(",", $lh{actors});
            my $actors_link;
            foreach my $actor (@actors) {
                $actors_link .= make_query_link($actor, 'actors', 'movies') . " ";
            }
            
            my $released_link   = make_query_link($lh{released}, 'released', 'movies');
            my $imdb_link       = "<a href='$lh{imdb}' target='_new'>$lh{imdb}</a>";
            my $self_link       = make_query_link($uid, 'uid', 'movies', 'moar');                
            
            if ($mode eq 'multiple') {
                # movies: uid TEXT PRIMARY KEY, title TEXT, director TEXT, actors TEXT, genres TEXT, notes TEXT, imdb TEXT, cover TEXT, added TEXT, released TEXT, ffp TEXT
                
                $str = "<tr><td><strong>title</strong></td><td><strong>genres</strong></td><td><strong>imdb</strong></td><td><strong>released</strong></td><td><strong>more</strong></td></tr>" if $processed_count == 0;
                $str .= "<tr><td>$movie_image_link<br>$movie_text_link</td><td>$genres_link</td><td>$imdb_link</td><td>$released_link</td><td>$self_link</td></tr>";
                
                print "DBGZ" if 0;
                
            } elsif ($mode eq 'single') {
                
                # have to do it this way to do it abstractally and not write a ridiculous custom sort 
                $str = "<tr><td>$lh{image_uri}</td><td>&nbsp;</td></tr>\n
                <tr><td><strong>attribute</strong></td><td><strong>value</strong></td></tr>\n
                <tr><td>uid</td><td>$uid</td></tr>\n
                <tr><td>title</td><td>$movie_text_link</td></tr>\n
                <tr><td>director</td><td>$director_link</td></tr>\n
                <tr><td>actors</td><td>$actors_link</td></tr>\n
                <tr><td>genres</td><td>$genres_link</td></tr>\n
                <tr><td>notes</td><td>$lh{notes}</td></tr>\n
                <tr><td>imdb</td><td>$imdb_link</td></tr>\n
                <tr><td>released</td><td>$released_link</td></tr>\n
                <tr><td>ffp</td><td>$lh{ffp}</td></tr>\n 
                ";

                
                # should we last here?
                
                print "DBGZ" if 0;
                
            }
            

            
        } elsif ($type =~ /stats/) {
            my $title = $_;
            my $value = $hash{$title};
            $str = "<tr><td width='60%'>$title</td><td>$value</td></tr>";
        }
        
        push @table, $str;
        $processed_count++;
        
        # more for HTML rendering/processing than db strain
        if ($processed_count > $s{results_limit}) {
            err("returning early with '$s{results_limit}' results (out of $count total)"); # there is a bug here, this is not hitting
            last;
        }
    }
    
    push @table, "</table>";
    push @table, "<h2>found $count results</h2>" unless $type =~ /stats/;
    $html .= join("\n", @table);
    
    return $html;
}

sub get_stats_div {
    # get_stats_div() - returns an HTML string for the <div> containing statistics
    my $html;

    
    $html = "<div class='floater_stats'>";
    
    $html .= get_table_for_printing($s{db}, 'stats');
    
    $html .= get_query_div(); # actually returns a table...
    
    $html .= "</div>";
    
    return $html;
}

sub get_query_div {
    # get_query_div() - returns an HTML string for the <div> containing popular queries
    my $html;
    
    my %q = (
        a => {
            string => 'John Cusack',
            type   => 'actors',
            media  => 'movies',
        },
        b => {
            string => 'Harry Potter',
            type   => 'title',
            media  => 'movies',
        },
        c => {
            string => 'comedy',
            type   => 'genres',
            media  => 'movies',
        },
        d => {
            string => 'Sean Connery',
            type   => 'actors',
            media  => 'movies',
        },
        e => {
            string => 'James Bond',
            type   => 'title',
            media  => 'movies',
        }
    );
    
    
    # searches for popular genres (action, comedy), searches for popular actors/actresses (sean connery, harrison ford)
    
    
    $html = "<br><table align='right' border=0><tr><td>frequently used:</td></tr>";
    
    foreach my $query (%q) {
        $html .= "<tr><td>" . make_query_link($q{$query}{string}, $q{$query}{type}, $q{$query}{media}) . "</tr></td>";
    }
    
    # had to go the 'hardcoded' route because the link namescoming back from make_query_link() uses the first parameters as the name.. printing URI escaped HTML is ugly
    #my $rand_tv = make_query_link('ORDER+BY+RANDOM%28%29%0D%0ALIMIT+10', 'sql', 'tv');
    #my $rand_movies = make_query_link('ORDER+BY+RANDOM%28%29%0D%0ALIMIT+10', 'sql', 'movies');
    my $rand_tv = "<a href=" .$s{cgi_address} . '?function=query&media=tv&sql=ORDER+BY+RANDOM%28%29%0D%0ALIMIT+10&use_sql=1' . ">10 rand tv</a>";
    my $rand_movies = "<a href=" . $s{cgi_address} . '?function=query&media=movies&sql=ORDER+BY+RANDOM%28%29%0D%0ALIMIT+10&use_sql=1' . ">10 rand movies</a>";
    
    $html .= "<tr><td>$rand_tv</td></tr><tr><td>$rand_movies</td></tr>";
    
    $html .= "</table>";
    
    return $html;
}


sub get_query_control {
    # get_query_control() - obfuscation to build the SQL query control so it can be called from anywhere. return an @ or $ of html
    my @results;
    
    # # tv: 		uid TEXT PRIMARY KEY, show TEXT, season NUMERIC, episode NUMERIC, title TEXT, actors TEXT, genres TEXT, notes TEXT, added TEXT, released TEXT, ffp TEXT
    # movies: uid TEXT PRIMARY KEY, title TEXT, director TEXT, actors TEXT, genres TEXT, notes TEXT, imdb TEXT, cover TEXT, added TEXT, released TEXT, ffp TEXT
    @results = (
        "<h3>new query</h3>",
        "<form action=/cgi-bin/dex.cgi>",
        "<input type='hidden' name='function' value='query'>",
        
        "<strong>tv</strong>",
        "<table border='1' width='50%'>\n",
        "<tr><td><strong>attribute</strong></td><td><strong>value</strong></td><td><strong>use</strong></td></tr>\n",
        "<input type='hidden' name='media' value='tv'>\n",
        "<tr><td>show title</td><td><input name='show' onchange='use_show.checked=true'></td><td><input type='checkbox' name='use_show'></td></tr>\n",
        "<tr><td>season #</td><td>", get_select('season'), "</td><td><input type='checkbox' name='use_season'></td></tr>\n",
        "<tr><td>episode #</td><td>", get_select('episode'), "</td><td><input type='checkbox' name='use_episode'></td></tr>\n",
        "<tr><td>episode title</td><td><input name='title' onchange='use_title.checked=true'></td><td><input type='checkbox' name='use_title'></td></tr>\n",
        "<tr><td>actors</td><td><input name='actors' onchange='use_actors.checked=true'></td><td><input type='checkbox' name='use_actors'></td></tr>\n",
        "<tr><td>genres</td><td>", get_select('genres'), "</td><td><input type='checkbox' name='use_genres'></td></tr>\n",
        "<tr><td>notes</td><td><input name='notes' onchange='use_notes.checked=true'></td><td><input type='checkbox' name='use_notes'></td></tr>\n",
        "<tr><td>released year</td><td>", get_select('released'), "</td><td><input type='checkbox' name='use_released'></td></tr>\n",
        "<tr><td>ffp</td><td><input name='ffp' onchange='use_ffp.checked=true'></td><td><input type='checkbox' name='use_ffp'></td></tr>\n",
        "<tr><td>sql</td><td><textarea name='sql' onchange='use_sql.checked=true'></textarea></td><td><input type='checkbox' name='use_sql'></td></tr>\n",
        "<tr><td>&nbsp;</td><td>&nbsp;</td><td><input type='submit'></td></tr>",
        "</table>\n",
        "</form>\n",
        
        "<strong>movies</strong>\n",
        "<table border='1' width='50%'>\n",
        "<tr><td><strong>attribute</strong></td><td><strong>value</strong></td><td><strong>use</strong></td></tr>\n",
        "<form action=/cgi-bin/dex.cgi>",
        "<input type='hidden' name='function' value ='query'>\n",
        "<input type='hidden' name='media' value='movies'>\n",
        "<tr><td>movie title</td><td><input name='title' onchange='use_title.checked=true'></td><td><input type='checkbox' name='use_title'></td></tr>\n",
        "<tr><td>director</td><td><input name='director' onchange='use_director.checked=true'></td><td><input type='checkbox' name='use_director'></td></tr>\n",
        "<tr><td>actors</td><td><input name='actors' onchange='use_actors.checked=true'></td><td><input type='checkbox' name='use_actors'></td></tr>\n",
        "<tr><td>genres</td><td>", get_select('genres'), "</td><td><input type='checkbox' name='use_genres'></td></tr>\n",
        "<tr><td>notes</td><td><input name='notes' onchange='use_notes.checked=true'></td><td><input type='checkbox' name='use_notes'></td></tr>\n",
        "<tr><td>released year</td><td>", get_select('released'), "</td><td><input type='checkbox' name='use_released'></td></tr>\n",
        "<tr><td>ffp</td><td><input name='ffp' onchange='use_ffp.checked=true'></td><td><input type='checkbox' name='use_ffp'></td></tr>\n",
        "<tr><td>sql</td><td><textarea name='sql' onchange='use_.sqlchecked=true'></textarea></td><td><input type='checkbox' name='use_sql'></td></tr>\n",
        "<tr><td>&nbsp;</td><td>&nbsp;</td><td><input type='submit'></td></tr>",
        "</table>\n",
        "</form>\n",
        
        #"<tr><td>date</td><td><input name='date' onchange='document.forms[0].use_date.checked = true'></td><td><input type='checkbox' name='use_date'></td></tr>",
        #"<tr><td>author</td><td>", d_select("author"), "</td><td><input type='checkbox' name='use_author'></td></tr>", # commented out to force users to type deverloper name
        #"<tr><td>author</td><td><input name='author' onclick='document.forms[0].use_author.checked = true'></td><td><input type='checkbox' name='use_author'></td></tr>",

    );
    
    return @results;
}

sub get_select {
    # get_select($name) - returns a string of HTML to be inserted as a select dropdown
    my $name = shift;
    my $html;
    
    if ($name  =~ /episode|season/) {
        my @ints = (' ', 1..30); 
        
        # can't do this as sql doesn't store leading 0 and i don't want to mess up my oneliner on 631
        #foreach (@ints) {
        #    $_ = 0 . $_ if ($_ =~ /\d/ and $_ < 10);
        #}
        
        @ints = @ints[0..20] if $name =~ /season/; # well thats an annoying perlism.. generate 1..30, have to reference 0..n
        
        $html = "<select name='$name' onchange='use_$name.checked=true'>";
        
        $html .= "<option value='$_'>$_</option>" foreach (@ints);
        
        $html .= "</select>";
    } elsif ($name =~ /genres/) {
        my @genres = (
            ' ',
            'action',
            'animated',
            'comedy',
            'drama',
            'foreign',
            'geek',
            'indie',
            'old',
            'spy_action_whosit',
        );
        
        $html = "<select name='$name'>";
        $html .= "<option value='$_'>$_</option>" foreach (@genres);
        $html .= "</select>";
        
    } elsif ($name =~ /released/) {
        my $cur_year = 1900 + (localtime)[5];
        my @years = (' ', 1980..$cur_year);
        
        $html = "<select name='$name'>";
        $html .= "<option value='$_'>$_</option>" foreach (@years);
        $html .= "</select>";
        
    } else {
        err("unknown name '$name' sent to get_select()");
    }
    
    return $html;
}
    
sub make_query_link {
    # make_query_link($string, $type, $text) - returns a link query for a single string/type pair -- also supports calling with $string = hash, see examples:
    # my $foo = make_query_link({show => 'White Collar', Season => '2'}, 'inconsequential', 'tv', 'link text');
    # my $bar = make_query_link('White Collar', 'show', 'tv', 'other link text');

    my $string = shift;
    my $type   = shift;
    my $media  = shift;
    my $text  =  shift;

    my ($multiple, @multiple);
    if (ref $string) {
        my %lh = %{$string};
        foreach my $key (keys %lh) {
            push @multiple, "$key=$lh{$key}";
            push @multiple, "use_" . $key . "=1";
        }
        $multiple = join("&", @multiple);
        $multiple = '&' . $multiple;
    }
    $text = $string unless defined $text; # makes $text an optional parameter
    my $uri = $s{cgi_address} . "?function=query&media=$media";
    
    if ($multiple) {
        $uri .= $multiple;
    } else {
        $uri .= "&$type=$string";
        $uri .= "&use_" . $type . "=1";
    }

    my $pre = "<a href='";
    my $post = "'>$text</a>";
    
    return $pre . $uri . $post;
}
