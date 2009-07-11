CREATE TABLE IF NOT EXISTS dynamicplaylist_history (
  client varchar(20) NOT NULL,
  position INTEGER PRIMARY KEY AUTOINCREMENT,
  id int(10) NOT NULL,
  url text NOT NULL,
  added int(10) NOT NULL,
  skipped int(10) DEFAULT NULL
);

