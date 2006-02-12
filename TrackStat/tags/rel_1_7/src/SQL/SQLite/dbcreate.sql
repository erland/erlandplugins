CREATE TABLE track_statistics (
  url varchar UNIQUE NOT NULL,
  playCount integer,
  lastPlayed integer,
  rating integer
);


