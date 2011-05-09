#!/usr/bin/perl -w
# database.t -- tests for the dex database functions

# need to add some tests for sql_cleanup()

use strict;
use warnings;
use 5.010;

use Test::More qw(no_plan);

use lib '../lib';
use dex::util;

# scope hacking
my $db = 'test-db.sqlite';
my $results;
my $match_count;

my %tv = (
    uid => 'slknslkgnslk',
    show => 'test show',
    season => '01',
    episode => '01',
    title => 'test tv title',
    actors => 'test actor1, test actor 2',
    genres => 'test genre1, test genre 2',
    notes => 'test notes',
    wikipedia => 'http://en.wikipedia.org/wiki/test',
    cover => 'test cover.jpg',
    added => 'test added',
    ffp => '/path/to/test',
);

my %movie = (
    uid   => 'sdlkfnsdlkngs',
    title => 'test movie title',
    director => 'test director',
    actors => 'test actors',
    genres => 'test genres',
    notes => 'test notes',
    imdb => 'http://www.imdb.com',
    cover => 'test cover.jpg',
    added => 'test added',
    released => 'test released',
    ffp => '/path/to/test',
);

## database creation
$results = dex::util::create_db($db);
is ($results, 0, 'create_db(): $results');

## add sql to database
$results = dex::util::put_sql($db, 'tv', \%tv);
is ($results, 0, "add a tv entry to the database");

$results = dex::util::put_sql($db, 'movies', \%movie);
is ($results, 0, "add a movie entry to the database");

## update sql in database

## get sql out of database
($results, $match_count) = dex::util::get_sql($db, 'tv', "WHERE title == 'test tv title'");
is ($match_count, 1, "got a tv entry out of the db 1of2");
is ($results->{ffp}, '/path/to/test', "got a tv entry out of the db 2of2");

($results, $match_count) = dex::util::get_sql($db, 'tv', "WHERE title == 'test movie title'");
is ($match_count, 1, "got a tv entry out of the db 1of2");
is ($results->{ffp}, '/path/to/test', "got a tv entry out of the db 2of2");


## cleanup
#is(unlink($db), 1, "remove database '$db'");


exit;