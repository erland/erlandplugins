DELETE FROM customscan_track_attributes where length(url)>511;

ALTER TABLE customscan_track_attributes modify url varchar(511) not null;
