CREATE TABLE ipod_track (
  library int(10) not null,
  track int(10) not null,
  slimserverurl text not null,
  musicbrainz_id varchar(40),
  ipodpath varchar(511),
  ipodfilesize int(10),
  primary key (library,track)
);

CREATE TABLE ipod_libraries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  libraryid varchar(255) not null,
  name varchar(255) not null
);
