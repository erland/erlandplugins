CREATE TABLE track_statistics (
  url text NOT NULL,
  musicbrainz_id varchar(40),	-- musicbrainz uuid (36 bytes of text)
  playCount int(10) unsigned,
  lastPlayed int(10) unsigned,
  rating int(10) unsigned
) TYPE=InnoDB;


