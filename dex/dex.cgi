#!/usr/bin/perl -w
## dex.cgi -- web interface for dex (influenced by dico)

use strict;
use warnings;
use 5.010;

use CGI ':standard';
use CGI::Carp 'fatalsToBrowser'; # dbgz
use DBD::SQLite;
use Time::HiRes;

use lib '/home/conor/Dropbox/perl/_pm';
use ironhide;

my $time_start = Time::HiRes::gettimeofday();

## define some defaults
my (%d, %p, %s); # database, incoming parameters, settings

%s = (
    host         => "http://192.168.1.122",
    
    db_folder    => "/home/conor/dex/", # having www-data permission issues when trying to updated the DB in Dropbox
    db           => "", # dynamically defined below
    
    function     => (param()) ? "executing function" : "waiting for input",

    
);

$s{db} = $s{db_folder} . "dex.sqlite";

## global headers
html_start();
print get_stats_div();

## traffic cop
unless (param()) {
    # no params, build the start page
    print (h2("information"), "<ul>");
    
    my $cron    = "<br>&nbsp;&nbsp;&nbsp;" . join("<br>&nbsp;&nbsp;&nbsp;",cronread("dex"));
    my $db_link = $s{host} . "/dex/dex.sqlite"; # previous solution was: just ran 'link /home/conor/Dropbox/perl/_7/_dico/results.sqlite /home/conor/drop/dico_results.sqlite'
    my @db_file = stat $s{db};
    my $db_size = nicesize($db_file[7]);
    
    my @information = (
        "dex is a media indexing/research system combining Perl, SQLite and a little HTML/CSS",
        "currently all queries parameters are boolean ANDs",
        "database <a href=$db_link>here</a> ($db_size)",
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
    
    print get_query_control();
    # end up for parameter page
    
    
} else {
    # do work son
   my @p = param();
   
   $p{$_} = param($_) foreach(@p); # this is a quick and dirty way to handle most parameters.. does not work when you've got multiple controls with the same name but different values
   
    dump_hash(\%p, "params"); # not a debug command in this context
    
    
    # sub traffic cop
    if ($p{function} =~ /query/i) {
        
    }
    
}

my $time_finish = Time::HiRes::gettimeofday();
# end up
print(
    "<br><br><br>rendered in " . substr(($time_finish - $time_start), 0, 5) . "s\n",
    "<br><br>",
    "back to <a href=\"/cgi-bin/dex.cgi\">launcher</a><br>",
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
		-style => { src => $s{host} . '/default.css' }
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
	    $cmd = $1; # grabbed from the regex
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

sub get_stats_div {
    # get_stats_div() - returns an HTML string for the <div> containing statistics
    my $html;
    
    my %hash = get_sql($s{db}, 'stats');
    my @stats_table = ("<table border=0>");
    
    $html = "<div class='floater'>";
    
    
    foreach (sort keys %hash) {
        my $title = $_;
        my $value = $hash{$title};
        
        
        my $str = "<tr><td width='60%' align='left'>$title</td><td>$value</td></tr>";
        push @stats_table, $str;
    }
    
    push @stats_table, "</table>";
    $html .= join("\n", @stats_table);
    
    $html .= "</div>";
    
    
    
    return $html;
}

sub get_query_control {
    # get_query_control() - obfuscation to build the SQL query control so it can be called from anywhere. return an @ or $ of html
    my @results;
    
    # # tv: 		uid TEXT PRIMARY KEY, show TEXT, season NUMERIC, episode NUMERIC, title TEXT, genre TEXT, notes TEXT, added TEXT, released TEXT, ffp TEXT
    # movies: uid TEXT PRIMARY KEY, title TEXT, director TEXT, actors TEXT, genre TEXT, notes TEXT, imdb TEXT, cover TEXT, added TEXT, released TEXT, ffp TEXT
    @results = (
        "<h3>new query</h3>",
        "<form action=/cgi-bin/dex.cgi>",
        "<input type='hidden' name='function' value='query'>",
        
        "<strong>tv</strong>",
        "<table border='1' width='50%'>\n",
        "<tr><td><strong>setting</strong></td><td><strong>value</strong></td><td><strong>use</strong></td></tr>\n",
        "<input type='hidden' name='type' value='tv'>\n",
        "<tr><td>show title</td><td><input name='show'></td><td><input type='checkbox' name='use_show'></td></tr>\n",
        "<tr><td>season #</td><td>", get_select('season'), "</td><td><input type='checkbox' name='use_season'></td></tr>\n",
        "<tr><td>episode #</td><td>", get_select('episode'), "</td><td><input type='checkbox' name='use_episode'></td></tr>\n",
        "<tr><td>episode title</td><td><input name='title'></td><td><input type='checkbox' name='use_title'></td></tr>\n",
        "<tr><td>genre</td><td>", get_select('genre'), "</td><td><input type='checkbox' name='use_genre'></td></tr>\n",
        "<tr><td>notes</td><td><input name='notes'></td><td><input type='checkbox' name='use_notes'></td></tr>\n",
        "<tr><td>released year</td><td>", get_select('released'), "</td><td><input type='checkbox' name='use_released'></td></tr>\n",
        "<tr><td>ffp</td><td><input name='ffp'></td><td><input type='checkbox' name='use_ffp'></td></tr>\n",
        "<tr><td>&nbsp;</td><td>&nbsp;</td><td><input type='submit'></td></tr>",
        "</table>",
        
        "<strong>movies</strong>\n",
        "<table border='1' width='50%'>\n",
        "<tr><td><strong>setting</strong></td><td><strong>value</strong></td><td><strong>use</strong></td></tr>\n",
        "<input type='hidden' name='type' value='movies'>\n",
        "<tr><td>movie title</td><td><input name='title'></td><td><input type='checkbox' name='use_title'></td></tr>\n",
        "<tr><td>director</td><td><input name='director'></td><td><input type='checkbox' name='use_director'></td></tr>\n",
        "<tr><td>actors</td><td><input name='actors'></td><td><input type='checkbox' name='use_actors'></td></tr>\n",
        "<tr><td>genre</td><td>", get_select('genre'), "</td><td><input type='checkbox' name='use_genre'></td></tr>\n",
        "<tr><td>actors</td><td><input name='notes'></td><td><input type='checkbox' name='use_notes'></td></tr>\n",
        "<tr><td>actors</td><td><input name='actors'></td><td><input type='checkbox' name='use_actors'></td></tr>\n",
        "<tr><td>released year</td><td>", get_select('released'), "</td><td><input type='checkbox' name='use_released'></td></tr>\n",
        "<tr><td>ffp</td><td><input name='ffp'></td><td><input type='checkbox' name='use_ffp'></td></tr>\n",
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
        my @ints = (1..30); 
        
        foreach (@ints) {
            $_ = 0 . $_ if ($_ < 10);
        }
        
        @ints = @ints[0..20] if $name =~ /season/; # well thats an annoying perlism.. generate 1..30, have to reference 0..n
        
        $html = "<select name='$name'>";
        
        $html .= "<option value='$_'>$_</option>" foreach (@ints);
        
        $html .= "</select>";
    } elsif ($name =~ /genre/) {
        my @genres = (
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
        my @years = (1980..$cur_year);
        
        $html = "<select name='$name'>";
        $html .= "<option value='$_'>$_</option>" foreach (@years);
        $html .= "</select>";
        
    } else {
        err("unknown name '$name' sent to get_select()");
    }
    
    return $html;
}

sub get_sql {
    # get_sql($database, $type, $)
    my $database = shift;
    my $type = shift;
    
    my %h;
    
    if ($type =~ /stats/) {
        
        %h = (
            files_count_total  => '100,000',
            files_count_tv     => '99,000',
            files_count_movies => '1,000',
            files_size_total   => '3 tb',
            files_size_new     => '100 mb',
        );
        
    } else {
        warn "this is fuzzed for now";
    }
    
    return %h;
}