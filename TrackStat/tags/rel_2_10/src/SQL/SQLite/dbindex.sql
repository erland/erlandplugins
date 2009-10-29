DROP INDEX IF EXISTS persistentdb.urlIndex;
DROP INDEX IF EXISTS persistentdb.musicbrainzIndex;
CREATE INDEX IF NOT EXISTS persistentdb.tsurlIndex on track_statistics (url);
CREATE INDEX IF NOT EXISTS persistentdb.tsmusicbrainzIndex on track_statistics (musicbrainz_id);
CREATE INDEX IF NOT EXISTS persistentdb.tshurlIndex on track_history (url);
CREATE INDEX IF NOT EXISTS persistentdb.tshmusicbrainzIndex on track_history (musicbrainz_id);
CREATE INDEX IF NOT EXISTS trackStatMBIndex on tracks (musicbrainz_id)

