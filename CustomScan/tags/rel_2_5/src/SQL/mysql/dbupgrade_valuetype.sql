ALTER TABLE customscan_track_attributes ADD COLUMN valuetype varchar(255) AFTER extravalue;
ALTER TABLE customscan_album_attributes ADD COLUMN valuetype varchar(255) AFTER extravalue;
ALTER TABLE customscan_contributor_attributes ADD COLUMN valuetype varchar(255) AFTER extravalue;
