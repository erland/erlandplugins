ALTER TABLE track_statistics ADD COLUMN urlmd5 char(32) NOT NULL default '0';
UPDATE track_statistics set urlmd5=md5(url) where urlmd5=0;
ALTER TABLE track_history ADD COLUMN urlmd5 char(32) NOT NULL default '0';
UPDATE track_history set urlmd5=md5(url) where urlmd5=0;

