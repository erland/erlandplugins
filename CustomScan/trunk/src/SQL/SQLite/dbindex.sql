create index if not exists persistentdb.contributor_attr_idx on customscan_contributor_attributes (contributor,module,attr,id);
create index if not exists persistentdb.musicbrainzIndex on customscan_contributor_attributes (musicbrainz_id);
create index if not exists persistentdb.module_attr_value_idx on customscan_contributor_attributes (module,attr,value);

create index if not exists persistentdb.album_attr_idx on customscan_album_attributes (album,module,attr,id);
create index if not exists persistentdb.musicbrainzIndex on customscan_album_attributes (musicbrainz_id);
create index if not exists persistentdb.module_attr_value_idx on customscan_album_attributes (module,attr,value);

create index if not exists persistentdb.track_attr_idx on customscan_track_attributes (track,module,attr,id);
create index if not exists persistentdb.musicbrainzIndex on customscan_track_attributes (musicbrainz_id);
create index if not exists persistentdb.urlIndex on customscan_track_attributes (url);
create index if not exists persistentdb.module_attr_value_idx on customscan_track_attributes (module,attr,value);
create index if not exists persistentdb.attr_module_idx on customscan_track_attributes (attr,module);
create index if not exists persistentdb.extravalue_attr_module_track_idx on customscan_track_attributes (extravalue,attr,module,track);
create index if not exists persistentdb.track_module_attr_extravalue_idx on customscan_track_attributes (track,module,attr,extravalue);
create index if not exists persistentdb.module_attr_extravalue_idx on customscan_track_attributes (module,attr,extravalue);
create index if not exists persistentdb.module_attr_valuesort_idx on customscan_track_attributes (module,attr,valuesort);

