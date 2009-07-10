CREATE INDEX IF NOT EXISTS persistentdb.urlIndex on track_statistics (url);
CREATE INDEX IF NOT EXISTS persistentdb.musicbrainzIndex on track_statistics (musicbrainz_id);
CREATE INDEX IF NOT EXISTS persistentdb.urlIndex on track_history (url);
CREATE INDEX IF NOT EXISTS persistentdb.musicbrainzIndex on track_history (musicbrainz_id);
CREATE INDEX IF NOT EXISTS trackStatMBIndex on tracks (musicbrainz_id)

