DELETE FROM track_statistics where length(url)>255;

ALTER TABLE track_statistics modify url varchar(255) not null;

CREATE TABLE track_history (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT UNIQUE,
  url varchar(255) NOT NULL,
  musicbrainz_id varchar(40),	-- musicbrainz uuid (36 bytes of text)
  played int(10) unsigned,
  rating int(10) unsigned
) TYPE=InnoDB;

