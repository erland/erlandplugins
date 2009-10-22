ALTER TABLE customscan_track_attributes ADD COLUMN extravalue varchar(255) AFTER valuesort;
ALTER TABLE customscan_album_attributes ADD COLUMN extravalue varchar(255) AFTER valuesort;
ALTER TABLE customscan_contributor_attributes ADD COLUMN extravalue varchar(255) AFTER valuesort;
