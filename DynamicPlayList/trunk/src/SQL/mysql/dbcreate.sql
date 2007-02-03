CREATE TABLE dynamicplaylist_history (
  client varchar(100),
  position BIGINT UNSIGNED NOT NULL AUTO_INCREMENT UNIQUE,
  id int(10) unsigned NOT NULL,
  url text NOT NULL,
  added int(10) unsigned NOT NULL,
  skipped int(10) unsigned DEFAULT NULL
) TYPE=InnoDB;

