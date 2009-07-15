CREATE TABLE IF NOT EXISTS persistentdb.customscan_contributor_attributes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  contributor int(10),
  name blob not null,
  musicbrainz_id varchar(40),
  module varchar(40) NOT NULL,
  attr varchar (255) NOT NULL,
  value varchar(255),
  valuesort varchar(255),
  extravalue varchar(255),
  valuetype varchar(255)
);

CREATE TABLE IF NOT EXISTS persistentdb.customscan_album_attributes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  album int(10),
  title blob not null,
  musicbrainz_id varchar(40),
  module varchar(40) NOT NULL,
  attr varchar (255) NOT NULL,
  value varchar(255),
  valuesort varchar(255),
  extravalue varchar(255),
  valuetype varchar(255)
);

CREATE TABLE IF NOT EXISTS persistentdb.customscan_track_attributes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  track int(10),
  url text NOT NULL,
  musicbrainz_id varchar(40),
  module varchar(40) NOT NULL,
  attr varchar (255) NOT NULL,
  value varchar(255),
  valuesort varchar(255),
  extravalue varchar(255),
  valuetype varchar(255)
);

