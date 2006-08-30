CREATE TEMPORARY TABLE track_statistics_tmp(url,musicbrainz_id,playCount,lastPlayed,rating);
INSERT INTO track_statistics_tmp SELECT url,musicbrainz_id,playCount,lastPlayed,rating FROM track_statistics;
DROP TABLE track_statistics;
CREATE TABLE track_statistics (
  url varchar UNIQUE NOT NULL,
  musicbrainz_id varchar,
  playCount integer,
  added integer,
  lastPlayed integer,
  rating integer
);
INSERT INTO track_statistics SELECT url,musicbrainz_id,playCount,null,lastPlayed,rating FROM track_statistics_tmp;
DROP TABLE track_statistics_tmp;
