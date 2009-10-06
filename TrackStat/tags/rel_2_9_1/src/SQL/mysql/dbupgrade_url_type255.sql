DELETE FROM track_statistics where length(url)>255;

ALTER TABLE track_statistics modify url varchar(255) not null;

DELETE FROM track_history where length(url)>255;

ALTER TABLE track_history modify url varchar(255) not null;
