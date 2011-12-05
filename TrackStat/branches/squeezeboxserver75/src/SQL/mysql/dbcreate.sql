CREATE TABLE track_statistics (
  url varchar(255) NOT NULL,
  musicbrainz_id varchar(40),	-- musicbrainz uuid (36 bytes of text)
  playCount int(10) unsigned,
  added int(10) unsigned,
  lastPlayed int(10) unsigned,
  rating int(10) unsigned
) TYPE=InnoDB;

CREATE TABLE track_history (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT UNIQUE,
  url varchar(255) NOT NULL,
  musicbrainz_id varchar(40),	-- musicbrainz uuid (36 bytes of text)
  played int(10) unsigned,
  rating int(10) unsigned
) TYPE=InnoDB;

