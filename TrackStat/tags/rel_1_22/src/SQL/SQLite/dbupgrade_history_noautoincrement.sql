CREATE TEMPORARY TABLE track_history_tmp(id,url,musicbrainz_id,played,rating);
INSERT INTO track_history_tmp SELECT id,url,musicbrainz_id,played,rating FROM track_history;
DROP TABLE track_history;
CREATE TABLE track_history (
  id integer primary key,
  url varchar NOT NULL,
  musicbrainz_id varchar,  -- musicbrainz uuid (36 bytes of text)
  played integer,
  rating integer
);
INSERT INTO track_history SELECT id,url,musicbrainz_id,played,rating FROM track_history_tmp;
DROP TABLE track_history_tmp;
