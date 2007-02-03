CREATE TABLE dynamicplaylist_history (
  client varchar,
  position integer NOT NULL primary key,
  id integer NOT NULL,
  url varchar NOT NULL,
  added integer NOT NULL,
  skipped integer DEFAULT NULL
);
