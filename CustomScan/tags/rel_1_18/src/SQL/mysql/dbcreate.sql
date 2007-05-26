CREATE TABLE multilibrary_genre (
  library int(10) not null,
  genre int(10) not null,
  primary key (library,genre)
) TYPE=InnoDB;

CREATE TABLE multilibrary_year (
  library int(10) not null,
  year int(10) not null,
  primary key (library,year)
) TYPE=InnoDB;

CREATE TABLE multilibrary_contributor (
  library int(10) not null,
  contributor int(10) not null,
  primary key (library,contributor)
) TYPE=InnoDB;

CREATE TABLE multilibrary_album (
  library int(10) not null,
  album int(10) not null,
  primary key (library,album)
) TYPE=InnoDB;

CREATE TABLE multilibrary_track (
  library int(10) not null,
  track int(10) not null,
  primary key (library,track)
) TYPE=InnoDB;

CREATE TABLE multilibrary_libraries (
  id int(10) not null AUTO_INCREMENT UNIQUE,
  libraryid varchar(255) not null,
  name varchar(255) not null,
  primary key (id)
) TYPE=InnoDB;
