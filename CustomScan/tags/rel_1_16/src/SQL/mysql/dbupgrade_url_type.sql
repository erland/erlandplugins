DELETE FROM customscan_track_attributes where length(url)>255;

ALTER TABLE customscan_track_attributes modify url varchar(255) not null;
