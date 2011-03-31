/* need to decide on data structure
# one table for movies, another for TV shows

# movies:
    unique key
    movie title
    date/time added to db
    year released
    imdb (full URL or just the id string?)
    cover image path (local or remote, prefer local)
    director
    actors / actresses <-- CSV
    genres / themes <-- CSV
    user notes/comments

*/

CREATE TABLE tbl_movies (
    uid TEXT PRIMARY KEY,
    title TEXT,
    added TEXT,
    released TEXT,
    imdb TEXT,
    cover TEXT,
    director TEXT,
    actors TEXT,
    genre TEXT,
    notes TEXT
);


