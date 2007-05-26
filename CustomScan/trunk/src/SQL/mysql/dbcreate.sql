CREATE TABLE customscan_contributor_attributes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT UNIQUE,
  contributor int(10),
  name blob not null,
  musicbrainz_id varchar(40),
  module varchar(40) NOT NULL,
  attr varchar (255) NOT NULL,
  value varchar(255),
  valuesort varchar(255),
  extravalue varchar(255),
  valuetype varchar(255),
  index contributor_attr_idx (contributor,module,attr,id),
  primary key (id)
) TYPE=InnoDB;

CREATE TABLE customscan_album_attributes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT UNIQUE,
  album int(10),
  title blob not null,
  musicbrainz_id varchar(40),
  module varchar(40) NOT NULL,
  attr varchar (255) NOT NULL,
  value varchar(255),
  valuesort varchar(255),
  extravalue varchar(255),
  valuetype varchar(255),
  index album_attr_idx (album,module,attr,id),
  primary key (id)
) TYPE=InnoDB;

CREATE TABLE customscan_track_attributes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT UNIQUE,
  track int(10),
  url varchar (255) NOT NULL,
  musicbrainz_id varchar(40),
  module varchar(40) NOT NULL,
  attr varchar (255) NOT NULL,
  value varchar(255),
  valuesort varchar(255),
  extravalue varchar(255),
  valuetype varchar(255),
  index track_attr_idx (track,module,attr,id),
  primary key (id)
) TYPE=InnoDB;
