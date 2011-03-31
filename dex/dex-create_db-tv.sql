/*
# tv shows
    unique key
    show title
    date/time added to db
    year released (possible?)
    season number (can get this from filename)
    series number (can get this from filename)
    actors / actresses <-- CSV
    genres / themes <-- CSV
    user notes/comments
*/

CREATE TABLE tbl_tv (
    uid TEXT PRIMARY KEY,
    title TEXT,
    added TEXT,
    released TEXT,
    season NUMERIC,
    series NUMERIC,
    genre TEXT,
    notes TEXT
);
