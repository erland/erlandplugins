CREATE TABLE portable_track (
  library int(10) not null,
  track int(10) not null,
  slimserverurl text not null,
  musicbrainz_id varchar(40),
  portablepath varchar(511),
  portablefilesize int(10),
  primary key (library,track)
);

CREATE TABLE portable_libraries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  libraryid varchar(255) not null,
  name varchar(255) not null
);
