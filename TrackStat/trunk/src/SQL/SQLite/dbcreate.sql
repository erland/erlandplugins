CREATE TABLE IF NOT EXISTS persistentdb.track_statistics (
  url text NOT NULL,
  musicbrainz_id varchar(40),	-- musicbrainz uuid (36 bytes of text)
  playCount int(10),
  added int(10),
  lastPlayed int(10),
  rating int(10)
);

CREATE TABLE IF NOT EXISTS persistentdb.track_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  url text NOT NULL,
  musicbrainz_id varchar(40),	-- musicbrainz uuid (36 bytes of text)
  played int(10),
  rating int(10)
);

