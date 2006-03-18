CREATE TABLE track_statistics (
  url varchar UNIQUE NOT NULL,
  musicbrainz_id varchar,  -- musicbrainz uuid (36 bytes of text)
  playCount integer,
  lastPlayed integer,
  rating integer
);


