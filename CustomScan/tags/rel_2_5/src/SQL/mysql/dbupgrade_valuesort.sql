ALTER TABLE customscan_track_attributes ADD COLUMN valuesort varchar(255) AFTER value;
ALTER TABLE customscan_album_attributes ADD COLUMN valuesort varchar(255) AFTER value;
ALTER TABLE customscan_contributor_attributes ADD COLUMN valuesort varchar(255) AFTER value;
