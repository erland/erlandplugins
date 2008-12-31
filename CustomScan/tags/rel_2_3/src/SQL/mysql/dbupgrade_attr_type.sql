DELETE FROM customscan_track_attributes where length(attr)>40;

ALTER TABLE customscan_track_attributes modify attr varchar(40) not null;

DELETE FROM customscan_album_attributes where length(attr)>40;

ALTER TABLE customscan_album_attributes modify attr varchar(40) not null;

DELETE FROM customscan_contributor_attributes where length(attr)>40;

ALTER TABLE customscan_contributor_attributes modify attr varchar(40) not null;
