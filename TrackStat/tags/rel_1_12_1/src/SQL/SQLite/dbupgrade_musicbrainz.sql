CREATE TEMPORARY TABLE track_statistics_tmp(url,playCount,lastPlayed,rating);
INSERT INTO track_statistics_tmp SELECT url,playCount,lastPlayed,rating FROM track_statistics;
DROP TABLE track_statistics;
CREATE TABLE track_statistics (
  url varchar UNIQUE NOT NULL,
  musicbrainz_id varchar,  -- musicbrainz uuid (36 bytes of text)
  playCount integer,
  lastPlayed integer,
  rating integer
);
INSERT INTO track_statistics SELECT url,null,playCount,lastPlayed,rating FROM track_statistics_tmp;
DROP TABLE track_statistics_tmp;
