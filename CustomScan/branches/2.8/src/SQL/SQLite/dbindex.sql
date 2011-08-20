create index if not exists persistentdb.contributor_attr_cscontributoridx on customscan_contributor_attributes (contributor,module,attr,id);
create index if not exists persistentdb.musicbrainz_cscontributoridx on customscan_contributor_attributes (musicbrainz_id);
create index if not exists persistentdb.module_attr_value_cscontributoridx on customscan_contributor_attributes (module,attr,value);

create index if not exists persistentdb.album_attr_csalbumidx on customscan_album_attributes (album,module,attr,id);
create index if not exists persistentdb.musicbrainz_csalbumidx on customscan_album_attributes (musicbrainz_id);
create index if not exists persistentdb.module_attr_value_csalbumidx on customscan_album_attributes (module,attr,value);

create index if not exists persistentdb.track_attr_cstrackidx on customscan_track_attributes (track,module,attr,id);
create index if not exists persistentdb.musicbrainz_cstrackidx on customscan_track_attributes (musicbrainz_id);
create index if not exists persistentdb.url_cstrackidx on customscan_track_attributes (url);
create index if not exists persistentdb.module_attr_value_cstrackidx on customscan_track_attributes (module,attr,value);
create index if not exists persistentdb.attr_module_cstrackidx on customscan_track_attributes (attr,module);
create index if not exists persistentdb.extravalue_attr_module_track_cstrackidx on customscan_track_attributes (extravalue,attr,module,track);
create index if not exists persistentdb.track_module_attr_extravalue_cstrackidx on customscan_track_attributes (track,module,attr,extravalue);
create index if not exists persistentdb.module_attr_extravalue_cstrackidx on customscan_track_attributes (module,attr,extravalue);
create index if not exists persistentdb.module_attr_valuesort_cstrackidx on customscan_track_attributes (module,attr,valuesort);

create index if not exists musicbrainzUrlIdCSIndex on tracks (musicbrainz_id,url,id);
