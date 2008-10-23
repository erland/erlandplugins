#         TrackStat::Storage module
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
# 
# 	 Code for Musicbrainz support partly provided by hakan.
# 
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


use strict;
use warnings;
                   
package Plugins::TrackStat::Storage;

use Slim::Utils::Prefs;
use Date::Parse qw(str2time);
use Fcntl ':flock'; # import LOCK_* constants
use File::Spec::Functions qw(:ALL);
use File::Basename;
use XML::Parser;
use DBI qw(:sql_types);
use Class::Struct;
use FindBin qw($Bin);
use POSIX qw(strftime ceil);
use Slim::Schema;

if ($] > 5.007) {
	require Encode;
}

use Slim::Utils::Misc;

struct TrackInfo => {
	url => '$',
	mbId => '$',
	playCount => '$',
	added => '$',
	lastPlayed => '$',
	rating => '$'
};

my $prefs = preferences('plugin.trackstat');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.trackstat',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_TRACKSTAT',
});

my $driver;
my $useLongUrls = 1;
my $majorMysqlVersion = undef;
my $minorMysqlVersion = undef;

sub getCurrentDBH {
	return Slim::Schema->storage->dbh();
}

sub getCurrentDS {
	return 'Slim::Schema';
}

sub getMusicBrainzId {
	my $track = shift;
	return $track->musicbrainz_id;
}

sub commit {
	my $dbh = shift;
	if (!$dbh->{'AutoCommit'}) {
		$dbh->commit();
	}
}

sub rollback {
	my $dbh = shift;
	if (!$dbh->{'AutoCommit'}) {
		$dbh->rollback();
	}
}

sub objectForYear {
	my $year = shift;
	return Slim::Schema->resultset('Year')->single({'year' => $year});
}
sub objectForId {
	my $type = shift;
	my $id = shift;
	if($type eq 'artist') {
		$type = 'Contributor';
	}elsif($type eq 'album') {
		$type = 'Album';
	}elsif($type eq 'genre') {
		$type = 'Genre';
	}elsif($type eq 'track') {
		$type = 'Track';
	}elsif($type eq 'playlist') {
		$type = 'Playlist';
	}elsif($type eq 'year') {
		$type = 'Year';
	}
	return Slim::Schema->resultset($type)->find($id);
}

sub objectsForId {
	my $type = shift;
	my $idArray = shift;
	
	my @resultArray = ();
	return \@resultArray unless scalar(@$idArray)>0;

	if($type eq 'artist') {
		$type = 'Contributor';
	}elsif($type eq 'album') {
		$type = 'Album';
	}elsif($type eq 'genre') {
		$type = 'Genre';
	}elsif($type eq 'track') {
		$type = 'Track';
	}elsif($type eq 'playlist') {
		$type = 'Playlist';
	}elsif($type eq 'year') {
		$type = 'Year';
	}
	@resultArray = Slim::Schema->resultset($type)->search({ 'id' => { 'in' => $idArray } });
	return \@resultArray;
}

sub objectForUrl {
	my $url = shift;
	return Slim::Schema->objectForUrl({
		'url' => $url
	});
}

sub init {
	$driver = $serverPrefs->get('dbsource');
	$driver =~ s/dbi:(.*?):(.*)$/$1/;
    
	#Check if tables exists and create them if not
	$log->debug("Checking if track_statistics database table exists\n");
	my $dbh = getCurrentDBH();
	my $st = $dbh->table_info();
	my $tblexists;
	while (my ( $qual, $owner, $table, $type ) = $st->fetchrow_array()) {
		if($table eq "track_statistics") {
			$tblexists=1;
		}
	}
	unless ($tblexists) {
		$log->debug("Create database table\n");
		Plugins::TrackStat::Storage::executeSQLFile("dbcreate.sql");
	}
	
	$log->debug("Checking if track_history database table exists\n");
	$st = $dbh->table_info();
	$tblexists = undef;
	while (my ( $qual, $owner, $table, $type ) = $st->fetchrow_array()) {
		if($table eq "track_history") {
			$tblexists=1;
		}
	}
	unless ($tblexists) {
		$log->debug("Create database table track_history\n");
		Plugins::TrackStat::Storage::executeSQLFile("dbupgrade_history.sql");
	}
	
	eval { $dbh->do("select musicbrainz_id from track_statistics limit 1;") };
	if ($@) {
		$log->debug("Create database table column musicbrainz_id\n");
		Plugins::TrackStat::Storage::executeSQLFile("dbupgrade_musicbrainz.sql");
	}
	
	eval { $dbh->do("select added from track_statistics limit 1;") };
	if ($@) {
		$log->debug("Create database table column added\n");
		Plugins::TrackStat::Storage::executeSQLFile("dbupgrade_added.sql");
	}
	
	my $sth = $dbh->prepare("select version()");
	$majorMysqlVersion = undef;
	$minorMysqlVersion = undef;
	eval {
		$log->debug("Checking MySQL version\n");
		$sth->execute();
		my $version = undef;
		$sth->bind_col( 1, \$version);
		if( $sth->fetch() ) {
			if(defined($version) && (lc($version) =~ /^(\d+)\.(\d+)\.(\d+)[^\d]*/)) {
				$majorMysqlVersion = $1;
				$minorMysqlVersion = $2;
				$log->debug("Got MySQL $version\n");
			}
		}
		$sth->finish();
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n$@\n");
	}
	if(!defined($majorMysqlVersion)) {
		$majorMysqlVersion = 5;
		$minorMysqlVersion = 0;
		$log->warn("Unable to retrieve MySQL version, using default\n");
	}
	$useLongUrls = 1;
	if($majorMysqlVersion<5 || !$prefs->get("long_urls")) {
		$useLongUrls = 0;
		$prefs->set("long_urls",0);
	}

	$sth = $dbh->prepare("show create table track_statistics");
	eval {
		$log->debug("Checking datatype on track_statistics\n");
		$sth->execute();
		my $line = undef;
		$sth->bind_col( 2, \$line);
		if( $sth->fetch() ) {
			if(defined($line) && (lc($line) =~ /url.*(text|mediumtext)/m)) {
				$log->warn("TrackStat: Upgrading database changing type of url column, please wait...\n");
				if($useLongUrls) {
					executeSQLFile("dbupgrade_url_type.sql");
				}else {
					executeSQLFile("dbupgrade_url_type255.sql");
				}
			}elsif(defined($line) && $useLongUrls && (lc($line) =~ /url.*(varchar\(255\))/m)) {
				$log->warn("TrackStat: Upgrading database changing type of url column to varchar(511), please wait...\n");
				executeSQLFile("dbupgrade_url_type.sql");
			}elsif(defined($line) && !$useLongUrls && (lc($line) =~ /url.*(varchar\(511\))/m)) {
				$log->warn("TrackStat: Upgrading database changing type of url column to varchar(255), please wait...\n");
				executeSQLFile("dbupgrade_url_type255.sql");
			}
		}
	};
	$sth->finish();

	$sth = $dbh->prepare("show create table tracks");
	my $charset;
	eval {
		$log->debug("Checking charsets on tables\n");
		$sth->execute();
		my $line = undef;
		$sth->bind_col( 2, \$line);
		if( $sth->fetch() ) {
			if(defined($line) && ($line =~ /.*CHARSET\s*=\s*([^\s\r\n]+).*/)) {
				$charset = $1;
				my $collate = '';
				if($line =~ /.*COLLATE\s*=\s*([^\s\r\n]+).*/) {
					$collate = $1;
				}elsif($line =~ /.*collate\s+([^\s\r\n]+).*/) {
					$collate = $1;
				}

				$log->debug("Got tracks charset = $charset and collate = $collate\n");
				
				if(defined($charset)) {
					$sth->finish();
					$sth = $dbh->prepare("show create table track_statistics");
					$sth->execute();
					$line = undef;
					$sth->bind_col( 2, \$line);
					if( $sth->fetch() ) {
						if(defined($line) && ($line =~ /.*CHARSET\s*=\s*([^\s\r\n]+).*/)) {
							my $ts_charset = $1;
							my $ts_collate = '';
							if($line =~ /.*COLLATE\s*=\s*([^\s\r\n]+).*/) {
								$ts_collate = $1;
							}
							$log->debug("Got track_statistics charset = $ts_charset and collate = $ts_collate\n");
							if($charset ne $ts_charset || ($collate && (!$ts_collate || $collate ne $ts_collate)) || (!$collate && $ts_collate)) {
								$log->warn("Converting track_statistics to correct charset=$charset collate=$collate\n");
								if(!$collate) {
									eval { $dbh->do("alter table track_statistics convert to character set $charset") };
								}else {
									eval { $dbh->do("alter table track_statistics convert to character set $charset collate $collate") };
								}
								if ($@) {
									$log->warn("Couldn't convert charsets: $@\n");
								}
							}
						}
					}
					
					$sth->finish();
					$sth = $dbh->prepare("show create table track_history");
					$sth->execute();
					$line = undef;
					$sth->bind_col( 2, \$line);
					if( $sth->fetch() ) {
						if(defined($line) && ($line =~ /.*CHARSET\s*=\s*([^\s\r\n]+).*/)) {
							my $ts_charset = $1;
							my $ts_collate = '';
							if($line =~ /.*COLLATE\s*=\s*([^\s\r\n]+).*/) {
								$ts_collate = $1;
							}
							$log->debug("Got track_history charset = $ts_charset and collate = $ts_collate\n");
							if($charset ne $ts_charset || ($collate && (!$ts_collate || $collate ne $ts_collate)) || (!$collate && $ts_collate)) {
								$log->warn("Converting track_history to correct charset=$charset collate=$collate\n");
								if(!$collate) {
									eval { $dbh->do("alter table track_history convert to character set $charset") };
								}else {
									eval { $dbh->do("alter table track_history convert to character set $charset collate $collate") };
								}
								if ($@) {
									$log->warn("Couldn't convert charsets: $@\n");
								}
							}
						}
					}
					
				}
			}
		}
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	}
	$sth->finish();

	$sth = $dbh->prepare("show index from track_statistics;");
	eval {
		$log->debug("Checking if indexes is needed for track_statistics\n");
		$sth->execute();
		my $keyname;
		$sth->bind_col( 3, \$keyname );
		my $foundMB = 0;
		my $foundUrl = 0;
		my $foundUrlMB = 0;
		while( $sth->fetch() ) {
			if($keyname eq "urlIndex") {
				$foundUrl = 1;
			}elsif($keyname eq "musicbrainzIndex") {
				$foundMB = 1;
			}elsif($keyname eq "url_musicbrainz") {
				$foundUrlMB = 1;
			}
		}
		if(!$foundUrl) {
			$log->warn("TrackStat::Storage: No urlIndex index found in track_statistics, creating index...\n");
			eval { $dbh->do("create index urlIndex on track_statistics (url(255));") };
			if ($@) {
				$log->warn("Couldn't add index: $@\n");
			}
		}
		if(!$foundMB) {
			$log->warn("TrackStat::Storage: No musicbrainzIndex index found in track_statistics, creating index...\n");
			eval { $dbh->do("create index musicbrainzIndex on track_statistics (musicbrainz_id);") };
			if ($@) {
				$log->warn("Couldn't add index: $@\n");
			}
		}
		if($foundUrlMB) {
			$log->warn("TrackStat::Storage: Dropping old url_musicbrainz index...\n");
			eval { $dbh->do("drop index url_musicbrainz on track_statistics;") };
			if ($@) {
				$log->warn("Couldn't drop index: $@\n");
			}
		}
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	}
	$sth->finish();

	$sth = $dbh->prepare("show index from track_history;");
	eval {
		$log->debug("Checking if indexes is needed for track_history\n");
		$sth->execute();
		my $keyname;
		$sth->bind_col( 3, \$keyname );
		my $foundUrlMB = 0;
		my $foundMB = 0;
		while( $sth->fetch() ) {
			if($keyname eq "urlIndex") {
				$foundUrlMB = 1;
			}elsif($keyname eq "musicbrainzIndex") {
				$foundMB = 1;
			}
		}
		if(!$foundUrlMB) {
			$log->warn("TrackStat::Storage: No urlIndex index found in track_history, creating index...\n");
			eval { $dbh->do("create index urlIndex on track_history (url(255));") };
			if ($@) {
				$log->warn("Couldn't add index: $@\n");
			}
		}
		if(!$foundMB) {
			$log->warn("TrackStat::Storage: No musicbrainzIndex index found in track_history, creating index...\n");
			eval { $dbh->do("create index musicbrainzIndex on track_history (musicbrainz_id);") };
			if ($@) {
				$log->warn("Couldn't add index: $@\n");
			}
		}
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	}
	$sth->finish();
    
	# Only perform refresh at startup if this has been activated
	return unless $prefs->get("refresh_startup");
	refreshTracks();
}

sub getLastPlayedArtist {
	my $artistId = shift;
	my $ds = getCurrentDS();
	
	my $sql = "SELECT max(ifnull(track_statistics.lastPlayed,0)) FROM tracks,track_statistics,contributor_track where tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributor_track.contributor=?";
	my $dbh = getCurrentDBH();
	my $sth = $dbh->prepare( $sql );
	my $result = undef;
	eval {
		$sth->bind_param(1, $artistId , SQL_INTEGER);
		$sth->execute();

		$sth->bind_columns( undef, \$result);
		$sth->fetch();
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	}

	$sth->finish();
	return $result;
}

sub getLastPlayedAlbum {
	my $albumId = shift;
	my $ds = getCurrentDS();
	
	my $sql = "SELECT max(ifnull(track_statistics.lastPlayed,0)) FROM tracks,track_statistics where tracks.url=track_statistics.url and tracks.album=?";
	my $dbh = getCurrentDBH();
	my $sth = $dbh->prepare( $sql );
	my $result = undef;
	eval {
		$sth->bind_param(1, $albumId , SQL_INTEGER);
		$sth->execute();

		$sth->bind_columns( undef, \$result);
		$sth->fetch();
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	}

	$sth->finish();
	return $result;
}

sub findTrack {
	my $track_url = shift;
	my $mbId      = shift;
	my $ds        = getCurrentDS();
	my $track = shift;
	my $ignoreTrackInSlimserver = shift;
	
	if(!defined($track) && !$ignoreTrackInSlimserver) {
		# The encapsulation with eval is just to make it crash safe
		eval {
			$log->debug("Reading slimserver track: $track_url\n");
			$track = objectForUrl($track_url);
		};
		if ($@) {
			$log->warn("Error retrieving track: $track_url\n");
		}
	}
	my $searchString = "";
	my $queryAttribute = "";
	
	if(!$ignoreTrackInSlimserver) {
		return 0 unless $track;

		$mbId = getMusicBrainzId($track) if (!(defined($mbId)));
	}

	#Fix to make sure only real musicbrainz id's is used, slimserver can put text in this field instead in some situations
	if(defined $mbId && $mbId !~ /.*-.*/) {
		$mbId = undef;
	}

	if(defined($track)) {
		$track_url = $track->url;
	}
	$log->debug("findTrack(): URL: ".$track_url."\n");
	$log->debug("findTrack(): mbId: ". $mbId ."\n") if (defined($mbId));

	# create searchString and remove duplicate/trailing whitespace as well.
	if (defined($mbId)) {
		$searchString = $mbId;
		$queryAttribute = "musicbrainz_id";
	} else {
		$searchString = $track_url;
		$queryAttribute = "url";
	}

	return 0 unless length($searchString) >= 1;

	my $sql = "SELECT url, musicbrainz_id, playCount, added,lastPlayed, rating FROM track_statistics where $queryAttribute = ? or url = ?";
	my $dbh = getCurrentDBH();
	my $sth = $dbh->prepare( $sql );
	my $result = undef;
	eval {
		$sth->bind_param(1, $searchString , SQL_VARCHAR);
		$sth->bind_param(2, $track_url , SQL_VARCHAR);
		$sth->execute();

		my( $url, $mbId, $playCount, $added, $lastPlayed, $rating );
		$sth->bind_columns( undef, \$url, \$mbId, \$playCount, \$added, \$lastPlayed, \$rating );
		while( $sth->fetch() ) {
		  $result = TrackInfo->new( url => $url, mbId => $mbId, playCount => $playCount, added => $added, lastPlayed => $lastPlayed, rating => $rating );
		}
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	}

	$sth->finish();

	return $result;
}

sub getGroupStatistic {
	my $type = shift;
	my $id = shift;
	return undef unless $id;
	
	my $sql;
	if($type eq 'album') {
		$sql = "select avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.album=$id group by tracks.album;";
	}elsif($type eq 'artist') {
		$sql = "select avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$id left join track_statistics on tracks.url = track_statistics.url group by contributor_track.contributor;";
	}elsif($type eq 'playlist') {
		$sql = "select avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$id left join track_statistics on tracks.url = track_statistics.url group by playlist_track.playlist;";
	}elsif($type eq 'year') {
		$sql = "select avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.year=$id group by tracks.year;";
	}elsif($type eq 'genre') {
		$sql = "select avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$id left join track_statistics on tracks.url = track_statistics.url group by genre_track.genre;";
	}else {
		return undef;
	}
	$log->debug("Executing: $sql\n");
	my $dbh = getCurrentDBH();
	my $sth = $dbh->prepare( $sql );
	my %statistic = ();
	eval {
		$sth->execute();
		my $rating;
		my $lowestrating;
		$sth->bind_columns( undef, \$rating, \$lowestrating );
		if($sth->fetch()) {
	   		$statistic{'rating'} = $rating;
	   		$statistic{'lowestrating'} = $lowestrating;
		}else {
	   		$statistic{'rating'} = 0;
		}
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
   	}
   	return \%statistic;
}

sub getUnratedTracksOnAlbum {
	my $albumid = shift;
	return 0 unless $albumid;
	
	my $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.album=$albumid and (track_statistics.rating is null or track_statistics.rating=0)";
	my $dbh = getCurrentDBH();
	my $sth = $dbh->prepare( $sql );
	my @unratedTracks = ();
	eval {
		$sth->execute();
		my $url;
		$sth->bind_columns( undef, \$url );
		while( $sth->fetch() ) {
			push @unratedTracks, $url;
		}
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
   	}
   	return \@unratedTracks;
}

sub getTracksOnAlbum {
	my $albumid = shift;
	return 0 unless $albumid;
	
	my $sql = "select tracks.url from tracks where tracks.album=$albumid";
	my $dbh = getCurrentDBH();
	my $sth = $dbh->prepare( $sql );
	my @tracks = ();
	eval {
		$sth->execute();
		my $url;
		$sth->bind_columns( undef, \$url );
		while( $sth->fetch() ) {
			push @tracks, $url;
		}
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
   	}
   	return \@tracks;
}

sub saveRating {
	my ($url,$mbId,$track,$rating) = @_;
	
	my $maxCharacters = ($useLongUrls?511:255);
	if(length($url)>$maxCharacters) {
		$log->warn("Ignore, url is ".length($url)." characters long which longer than the $maxCharacters characters which is supported\n");
		return;
	}
	
	my $ds        = getCurrentDS();
	if(!defined($track)) {
		$track     = objectForUrl($url);
	}
	my $trackHandle = Plugins::TrackStat::Storage::findTrack( $url,undef,$track);
	my $searchString = "";
	my $queryAttribute = "";
	my $sql;
	
	$mbId = getMusicBrainzId($track) if (!(defined($mbId)));
	#Fix to make sure only real musicbrainz id's is used, slimserver can put text in this field instead in some situations
	if(defined $mbId && $mbId !~ /.*-.*/) {
		$mbId = undef;
	}

	# create searchString and remove duplicate/trailing whitespace as well.
	if (defined($mbId)) {
		$searchString = $mbId;
		$queryAttribute = "musicbrainz_id";
	} else {
		$searchString = $track->url;
		$queryAttribute = "url";
	}

	$log->debug("Store rating\n");

	if ($trackHandle) {
		if(!$rating) {
			$rating='null';
		}
		$sql = ("UPDATE track_statistics set rating=$rating where $queryAttribute = ? or url = ?");
	} else {
		my $added = getAddedTime($track);
		if(defined($mbId)) {
			$sql = ("INSERT INTO track_statistics (musicbrainz_id,url,added,rating) values (?,?,$added,$rating)");
		}else {
			$sql = ("INSERT INTO track_statistics (url,added,rating) values (?,$added,$rating)");
		}
	}
	my $dbh = getCurrentDBH();
	$log->debug("Execute $sql\n");
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->bind_param(1, $searchString , SQL_VARCHAR);
		if ($trackHandle || defined($mbId)) {
			$sth->bind_param(2, $url , SQL_VARCHAR);
		}
		$sth->execute();
		commit($dbh);
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
   	}

	$sth->finish();
}

sub savePlayCountAndLastPlayed
{
	my ($url,$mbId,$playCount,$lastPlayed,$track) = @_;

	my $maxCharacters = ($useLongUrls?511:255);
	if(length($url)>$maxCharacters) {
		$log->warn("Ignore, url is ".length($url)." characters long which longer than the $maxCharacters characters which is supported\n");
		return;
	}

	my $ds        = getCurrentDS();
	if(!defined($track)) {
		$track     = objectForUrl($url);
	}
	my $trackHandle = Plugins::TrackStat::Storage::findTrack( $url,undef,$track);
	my $sql;
	$url = $track->url;

	$log->debug("Marking as played in storage\n");

	my $trackmbId = getMusicBrainzId($track);
	#Fix to make sure only real musicbrainz id's is used, slimserver can put text in this field instead in some situations
	if(defined $trackmbId && $trackmbId !~ /.*-.*/) {
		$trackmbId = undef;
	}

	my $key = $url;
	$key = $mbId if (defined($mbId));

	if ($trackHandle) {
		if (defined($mbId)) {
			$sql = "UPDATE track_statistics set playCount=$playCount, lastPlayed=$lastPlayed where musicbrainz_id = ?";
		} else {
			if(defined($trackmbId)) {
				$sql = "UPDATE track_statistics set playCount=$playCount, lastPlayed=$lastPlayed, musicbrainz_id = '$trackmbId' where url = ?";
			}else {
				$sql = "UPDATE track_statistics set playCount=$playCount, lastPlayed=$lastPlayed where url = ?";
			}
		}
	}else {
		$mbId = getMusicBrainzId($track);
		#Fix to make sure only real musicbrainz id's is used, slimserver can put text in this field instead in some situations
		if(defined $mbId && $mbId !~ /.*-.*/) {
			$mbId = undef;
		}
		my $added = getAddedTime($track);
		if (defined($mbId)) {
			$sql = "INSERT INTO track_statistics (url, musicbrainz_id, playCount, added, lastPlayed) values (?, '$mbId', $playCount, $added, $lastPlayed)";
		} else {
			if(defined($trackmbId)) {
				$sql = "INSERT INTO track_statistics (url, musicbrainz_id, playCount, added, lastPlayed) values (?, '$trackmbId', $playCount, $added, $lastPlayed)";
			}else {
				$sql = "INSERT INTO track_statistics (url, musicbrainz_id, playCount, added, lastPlayed) values (?, NULL, $playCount, $added, $lastPlayed)";
			}
		}
	}

	my $dbh = getCurrentDBH();
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->bind_param(1, $key , SQL_VARCHAR);
		$sth->execute();
		commit($dbh);
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n while executing:\n$sql\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}
	$sth->finish();
}

sub addToHistory
{
	$log->debug("Entering addToHistory\n");
	my ($url,$mbId,$playedTime,$rating,$ignoreTrackInSlimserver) = @_;

	return unless $prefs->get("history_enabled");
	
	my $maxCharacters = ($useLongUrls?511:255);
	if(length($url)>$maxCharacters) {
		$log->warn("Ignore, url is ".length($url)." characters long which longer than the $maxCharacters characters which is supported\n");
		return;
	}

	my $ds = getCurrentDS();
	my $track = objectForUrl($url);
	if (!defined $track && !defined $mbId) {
		$log->debug("File $url doesn't exist - will try to find on alternative path.");
		$track = findObjectForMovedUrl($url);
		if (defined $track) {
			$url = $track->url;
			$log->debug("Found history song on alternative path $url");
		}
		else {
			$log->warn("No matching alternative path found for $url.");
		}
	}
	if(!$ignoreTrackInSlimserver) {
		return unless $track;
	}

	my $sql;
	my $dbh = getCurrentDBH();

	$url = $track->url if defined($track);
	$mbId = getMusicBrainzId($track) if !defined($mbId);

	#Fix to make sure only real musicbrainz id's is used, slimserver can put text in this field instead in some situations
	if(defined $mbId && $mbId !~ /.*-.*/) {
		$mbId = undef;
	}
	
	if(defined($mbId)) {
		$sql = "SELECT url from track_history where (url=? or musicbrainz_id='$mbId') and played=$playedTime";
	}else {
		$sql = "SELECT url from track_history where url=? and played=$playedTime";
	}
	my $sth = $dbh->prepare( $sql );
	my $found = 0;
	eval {
		$sth->bind_param(1, $url , SQL_VARCHAR);
		$sth->execute();
		my( $url );
		$sth->bind_columns( undef, \$url );
		if( $sth->fetch() ) {
			$found = 1;
		}
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	}
	$sth->finish();

	my $key = $url;
	$sql = undef;
	if (defined($mbId)) {
		if (defined($rating)) {
			if(!$rating) {
				$rating='null';
			}
			if($found) {
				$sql = "UPDATE track_history set rating=$rating where (url=? or musicbrainz_id='$mbId') and played=$playedTime";
			}else {
				$sql = "INSERT INTO track_history (url, musicbrainz_id, played, rating) values (?, '$mbId', $playedTime, $rating)";
			}
		}else {
			if($found) {
				$sql = undef;
			}else {
				$sql = "INSERT INTO track_history (url, musicbrainz_id, played) values (?, '$mbId', $playedTime)";
			}
		}
	} else {
		if (defined($rating)) {
			if(!$rating) {
				$rating='null';
			}
			if($found) {
				$sql = "UPDATE track_history set rating=$rating where url=? and played=$playedTime";
			}else {
				$sql = "INSERT INTO track_history (url, musicbrainz_id, played, rating) values (?, NULL, $playedTime, $rating)";
			}
		}else {
			if($found) {
				$sql = undef;
			}else {
				$sql = "INSERT INTO track_history (url, musicbrainz_id, played) values (?, NULL, $playedTime)";
			}
		}
	}
	
	if(defined($sql)) {

		$sth = $dbh->prepare( $sql );
		eval {
			$sth->bind_param(1, $key , SQL_VARCHAR);
			$sth->execute();
			commit($dbh);
		};
		if( $@ ) {
		    $log->warn("Database error: $DBI::errstr\n");
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
		$sth->finish();
	}
	$log->debug("Exiting addToHistory\n");
}

# Try to find the file if it has moved to an alternative folder.
sub findObjectForMovedUrl
{
	# A lot of user's music libraries are structured:
	# <SC music library base path>\<sub-paths>\<artist>\<album>\<track>.<file-ext>
	# Try to find a match based on the last two folder names and then just the last folder name
	# (ignore the base part of the path and the file extension).

	# This could be made more generic by the following logic:
	# remove the SC music folder path from the URL
	# {
	#     take the leading folder off the front of the sub-path.
	#     search SC library for tracks containing the url sub-string
	# } until (match found or only one folder left in url sub-string)

	my $url = shift;

	if ($url =~ /.*([\\\/].*[\\\/].*[\\\/].*\.).*$/) {
		my $findUrl = $1;

		$log->debug("Find track urls ending with $findUrl");

		my @matchingTracks = Slim::Schema->rs('Track')->search({'url' => { like => "%" . $findUrl . '%'}});

		my $count = @matchingTracks;
		$log->debug("Found $count matching tracks");

		if ($count > 1) {
			$log->warn("Found $count tracks matching $url, picking the first one: ".$matchingTracks[0]->url);
		}
		if ($count > 0) {
			my $track = $matchingTracks[0];
			return $track;
		}
	}

	if ($url =~ /.*([\\\/].*[\\\/].*\.).*$/) {
		my $findUrl = $1;

		# Ignore if this is a disk directory (too risky that this connects to wrong track)
		if(lc($findUrl) =~ /^disk[0-9]/) {
			return undef;
		}

		$log->debug("Find track urls ending with $findUrl");

		my @matchingTracks = Slim::Schema->rs('Track')->search({'url' => { like => "%" . $findUrl . '%'}});

		my $count = @matchingTracks;
		$log->debug("Found $count matching tracks");

		if ($count > 2) {
			$log->warn("Found $count tracks matching $url, ignoring track, too risky to just choose first one");
		}else {
			if ($count > 1) {
				$log->warn("Found $count tracks matching $url, picking the first one: ".$matchingTracks[0]->url);
			}
			if ($count > 0) {
				my $track = $matchingTracks[0];
				return $track;
			}
		}
	}

	return undef;
}

sub saveTrack 
{
	my ($url,$mbId,$playCount,$added,$lastPlayed,$rating) = @_;
		
	my $maxCharacters = ($useLongUrls?511:255);
	if(length($url)>$maxCharacters) {
		$log->warn("Ignore, url is ".length($url)." characters long which longer than the $maxCharacters characters which is supported\n");
		return;
	}

	my $ds        = getCurrentDS();
	my $track = objectForUrl($url);
	if (!defined $track && !defined $mbId) {
		$log->debug("File $url doesn't exist - will try to find on alternative path.");
		$track = findObjectForMovedUrl($url);
		if (defined $track) {
			$url = $track->url;
			$log->debug("Found song on alternative path $url");
		}
		else {
			$log->warn("No matching alternative path found for $url.");
		}
	}

	my $trackHandle = Plugins::TrackStat::Storage::findTrack($url, $mbId,$track,1);
	my $sql;
	
	if (defined($playCount) || defined($lastPlayed) ||defined($added) ) {
		if(!defined($playCount)) {
			$playCount = 'NULL';
		}
		if(!defined($added)) {
			$added = 'NULL';
		}
		if(!defined($lastPlayed)) {
			$lastPlayed = 'NULL';
		}
		$log->debug("Saving play count, last played and added time in storage: $playCount, $lastPlayed, $added\n");

		my $key = $url;

		$lastPlayed = '0' if (!(defined($lastPlayed)));

		if($trackHandle) {
			my $queryParameter = "url";
			if (defined($mbId)) {
			    $queryParameter = "musicbrainz_id";
			    $key = $mbId;
			}

			$sql = "UPDATE track_statistics set playCount=$playCount, lastPlayed=$lastPlayed, added=$added where $queryParameter = ?";
		}else {
			if (defined($mbId)) {
				$sql = "INSERT INTO track_statistics (url, musicbrainz_id, playCount, added, lastPlayed) values (?, '$mbId', $playCount, $added, $lastPlayed)";
			}else {
				$sql = "INSERT INTO track_statistics (url, musicbrainz_id, playCount, added, lastPlayed) values (?, NULL, $playCount, $added, $lastPlayed)";
			}
		}
		my $dbh = getCurrentDBH();
		my $sth = $dbh->prepare( $sql );
		eval {
			$sth->bind_param(1, $key , SQL_VARCHAR);
			$sth->execute();
			commit($dbh);
		};
		if( $@ ) {
		    $log->warn("Database error: $DBI::errstr\n");
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}

		$sth->finish();
	}
	
	#Lookup again since the row can have been created above
	$trackHandle = Plugins::TrackStat::Storage::findTrack( $url,$mbId,$track,1);
	if ($rating && $rating ne "") {
		$log->debug("Store rating: $rating\n");
		#ratings are 0-5 stars, 100 = 5 stars

		if ($trackHandle) {
			$sql = ("UPDATE track_statistics set rating=$rating where url=?");
		} else {
			$sql = ("INSERT INTO track_statistics (url,added,rating) values (?,$added,$rating)");
		}
		my $dbh = getCurrentDBH();
		my $sth = $dbh->prepare( $sql );
		eval {
			$sth->bind_param(1, $url , SQL_VARCHAR);
			$sth->execute();
			commit($dbh);
		};
		if( $@ ) {
		    $log->warn("Database error: $DBI::errstr\n");
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
		$sth->finish();
	}
}

sub mergeTrack
{
	my ($url,$mbId,$playCount,$lastPlayed,$rating) = @_;

	my $maxCharacters = ($useLongUrls?511:255);
	if(length($url)>$maxCharacters) {
		$log->warn("Ignore, url is ".length($url)." characters long which longer than the $maxCharacters characters which is supported\n");
		return;
	}

	my $ds        = getCurrentDS();
	my $track     = objectForUrl($url);
	if (!defined $track && !defined $mbId) {
		$log->debug("File $url doesn't exist - will try to find on alternative path.");
		$track = findObjectForMovedUrl($url);
		if (defined $track) {
			$url = $track->url;
			$log->debug("Found song on alternative path $url");
		}
		else {
			$log->warn("No matching alternative path found for $url.");
		}
	}

	return unless $track;

	my $trackHandle = Plugins::TrackStat::Storage::findTrack($url,undef,$track);
	my $sql;
	
	if(!defined($mbId)) {
		$mbId = getMusicBrainzId($track);
	}
	#Fix to make sure only real musicbrainz id's is used, slimserver can put text in this field instead in some situations
	if(defined $mbId && $mbId !~ /.*-.*/) {
		$mbId = undef;
	}
	
	if ($playCount) {
		$log->debug("Marking as played in storage: $playCount\n");
		if($trackHandle && (!$trackHandle->playCount || ($trackHandle->playCount && $trackHandle->playCount<$playCount))) {
			if($trackHandle->lastPlayed && $trackHandle->lastPlayed>$lastPlayed) {
				$lastPlayed = $trackHandle->lastPlayed;
			}
			if($lastPlayed) {
				$sql = ("UPDATE track_statistics set playCount=$playCount, lastPlayed=$lastPlayed where url=?");
			}else {
				$sql = ("UPDATE track_statistics set playCount=$playCount where url=?");
			}
		}elsif($trackHandle) {
			$sql = undef;
		}else {
			my $added = getAddedTime($track);
			if($lastPlayed) {
				if (defined($mbId)) {
					$sql = ("INSERT INTO track_statistics (url,musicbrainz_id,playCount,added,lastPlayed) values (?,'$mbId',$playCount,$added,$lastPlayed)");
				}else {
					$sql = ("INSERT INTO track_statistics (url,playCount,added,lastPlayed) values (?,$playCount,$added,$lastPlayed)");
				}
			}else {
				if (defined($mbId)) {
					$sql = ("INSERT INTO track_statistics (url,musicbrainz_id,playCount,added) values (?,'$mbId',$playCount,$added)");
				}else {
					$sql = ("INSERT INTO track_statistics (url,playCount,added) values (?,$playCount,$added)");
				}
			}
		}
		if($sql) {
			my $dbh = getCurrentDBH();
			my $sth = $dbh->prepare( $sql );
			eval {
				$sth->bind_param(1, $url , SQL_VARCHAR);
				$sth->execute();
				commit($dbh);
			};
			if( $@ ) {
			    $log->warn("Database error: $DBI::errstr\n");
			    eval {
			    	rollback($dbh); #just die if rollback is failing
			    };
			}

			$sth->finish();
		}
	}
	
	#Lookup again since the row can have been created above
	$trackHandle = Plugins::TrackStat::Storage::findTrack( $url,undef,$track);
	if ($rating && $rating ne "") {
		$log->debug("Store rating: $rating\n");
	    #ratings are 0-5 stars, 100 = 5 stars

		if ($trackHandle) {
			$sql = ("UPDATE track_statistics set rating=$rating where url=?");
		} else {
			my $added = getAddedTime($track);
			if (defined($mbId)) {
				$sql = ("INSERT INTO track_statistics (url,musicbrainz_id,added,rating) values (?,'$mbId',$added,$rating)");
			}else {
				$sql = ("INSERT INTO track_statistics (url,added,rating) values (?,$added,$rating)");
			}
		}
		my $dbh = getCurrentDBH();
		my $sth = $dbh->prepare( $sql );
		eval {
			$sth->bind_param(1, $url , SQL_VARCHAR);
			$sth->execute();
			commit($dbh);
		};
		if( $@ ) {
		    $log->warn("Database error: $DBI::errstr\n");
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
		$sth->finish();
	}
}


sub refreshTracks 
{
		
	my $ds        = getCurrentDS();
	my $dbh = getCurrentDBH();
	my $sth;
	my $sthupdate;
	my $sql;
	my $sqlupdate;
	my $count;
	my $timeMeasure = Time::Stopwatch->new();
	$timeMeasure->clear();
	$timeMeasure->start();
	$sth = $dbh->prepare("show index from tracks;");
	eval {
		$log->debug("Checking if additional indexes are needed for tracks\n");
		$sth->execute();
		my $keyname;
		$sth->bind_col( 3, \$keyname );
		my $found = 0;
		while( $sth->fetch() ) {
			if($keyname eq "trackStatMBIndex") {
				$found = 1;
			}
		}
		if(!$found) {
			$log->warn("TrackStat::Storage: No trackStatMBIndex index found in tracks, creating index...\n");
			eval { $dbh->do("create index trackStatMBIndex on tracks (musicbrainz_id);") };
			if ($@) {
				$log->warn("Couldn't add index: $@\n");
			}
		}
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	}
	$sth->finish();
	$timeMeasure->stop();
	$timeMeasure->start();
	$log->debug("Starting to analyze indexes\n");
	eval {
    	$dbh->do("analyze table tracks;");
    	$dbh->do("analyze table track_statistics;");
    	$dbh->do("analyze table track_history;");
		commit($dbh);
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}
	$log->debug("Finished analyzing indexes : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();

	$timeMeasure->clear();
	$timeMeasure->start();
	$log->debug("Starting to update urls in statistic data based on musicbrainz ids\n");
	# First lets refresh all urls with musicbrainz id's
	$sql = "UPDATE tracks,track_statistics SET track_statistics.url=tracks.url where tracks.musicbrainz_id is not null and tracks.musicbrainz_id=track_statistics.musicbrainz_id and track_statistics.url!=tracks.url and length(tracks.url)<".($useLongUrls?512:256);
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}
	$sth->finish();
	$log->debug("Finished updating urls in statistic data based on musicbrainz ids, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();

	$timeMeasure->clear();
	$timeMeasure->start();
	$log->debug("Starting to update musicbrainz id's in statistic data based on urls\n");
	# Now lets set all musicbrainz id's not already set
	$sql = "UPDATE tracks,track_statistics SET track_statistics.musicbrainz_id=tracks.musicbrainz_id where tracks.url=track_statistics.url and tracks.musicbrainz_id like '%-%' and track_statistics.musicbrainz_id is null";
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}

	$sth->finish();
	$log->debug("Finished updating musicbrainz id's in statistic data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();
	
	$timeMeasure->clear();
	$timeMeasure->start();
	$log->debug("Starting to update ratings in standard slimserver database based on urls\n");
	# Now lets set all ratings not already set in the slimserver standards database
	if(UNIVERSAL::can("Slim::Schema::Track","persistent")) {
		$sql = "UPDATE tracks_persistent,track_statistics set tracks_persistent.rating=track_statistics.rating where tracks_persistent.url=track_statistics.url and track_statistics.rating>0 and (tracks_persistent.rating!=track_statistics.rating or tracks_persistent.rating is null)";
	}else {
		$sql = "UPDATE tracks,track_statistics set tracks.rating=track_statistics.rating where tracks.url=track_statistics.url and track_statistics.rating>0 and (tracks.rating!=track_statistics.rating or tracks.rating is null)";
	}
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	}
	$sth->finish();
	$log->debug("Finished updating ratings in standard slimserver database based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();

	$timeMeasure->clear();
	$timeMeasure->start();
	$log->debug("Starting to update added times in statistic data based on urls\n");
	# Now lets set all added times not already set
	$sql = "UPDATE tracks,track_statistics SET track_statistics.added=tracks.timestamp where tracks.url=track_statistics.url and track_statistics.added is null and tracks.timestamp is not null";
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}

	$sth->finish();
	$log->debug("Finished updating added times in statistic data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();

	$timeMeasure->clear();
	$timeMeasure->start();
	$log->debug("Starting to update play counts in statistic data based on urls\n");
	# Now lets set all added times not already set
	if(UNIVERSAL::can("Slim::Schema::Track","persistent")) {
		$sql = "UPDATE tracks,tracks_persistent,track_statistics SET track_statistics.playCount=tracks_persistent.playCount where tracks.url=track_statistics.url and tracks.id=tracks_persistent.track and track_statistics.playCount is null and tracks_persistent.playCount is not null";
	}else {
		$sql = "UPDATE tracks,track_statistics SET track_statistics.playCount=tracks.playCount where tracks.url=track_statistics.url and track_statistics.playCount is null and tracks.playCount is not null";
	}
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}

	$sth->finish();
	$log->debug("Finished updating play counts in statistic data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();

	$timeMeasure->clear();
	$timeMeasure->start();
	$log->debug("Starting to update last played times in statistic data based on urls\n");
	# Now lets set all added times not already set
	if(UNIVERSAL::can("Slim::Schema::Track","persistent")) {
		$sql = "UPDATE tracks,tracks_persistent,track_statistics SET track_statistics.lastPlayed=tracks_persistent.lastPlayed where tracks.url=track_statistics.url and tracks.id=tracks_persistent.track and track_statistics.lastPlayed is null and tracks_persistent.lastPlayed is not null";
	}else {
		$sql = "UPDATE tracks,track_statistics SET track_statistics.lastPlayed=tracks.lastPlayed where tracks.url=track_statistics.url and track_statistics.lastPlayed is null and tracks.lastPlayed is not null";
	}
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}

	$sth->finish();
	$log->debug("Finished updating last played times in statistic data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();

	$timeMeasure->clear();
	$timeMeasure->start();
	$log->debug("Starting to add tracks without added times in statistic data based on urls\n");
	# Now lets set all new tracks with added times not already set
	if(UNIVERSAL::can("Slim::Schema::Track","persistent")) {
		$sql = "INSERT INTO track_statistics (url,musicbrainz_id,playcount,added,lastPlayed,rating) select tracks.url,case when tracks.musicbrainz_id like '%-%' then tracks.musicbrainz_id else null end as musicbrainz_id,tracks_persistent.playcount,tracks_persistent.added,tracks_persistent.lastplayed,tracks_persistent.rating from tracks left join tracks_persistent on tracks.id=tracks_persistent.track left join track_statistics on tracks.url = track_statistics.url where audio=1 and track_statistics.url is null and length(tracks.url)<".($useLongUrls?512:256);
	}else {
		$sql = "INSERT INTO track_statistics (url,musicbrainz_id,playcount,added,lastPlayed,rating) select tracks.url,case when tracks.musicbrainz_id like '%-%' then tracks.musicbrainz_id else null end as musicbrainz_id,tracks.playcount,tracks.timestamp,tracks.lastplayed,tracks.rating from tracks left join track_statistics on tracks.url = track_statistics.url where audio=1 and track_statistics.url is null and length(tracks.url)<".($useLongUrls?512:256);
	}
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		commit($dbh);
		if($count eq '0E0') {
			$count = 0;
		}
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}

	$sth->finish();
	$log->debug("Finished adding tracks without added times in statistic data based on urls, added $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();

	$timeMeasure->clear();
	$timeMeasure->start();
	$log->debug("Starting to update ratings in statistic data based on urls\n");
	# Now lets set all added times not already set
	if(UNIVERSAL::can("Slim::Schema::Track","persistent")) {
		$sql = "UPDATE tracks_persistent,track_statistics SET track_statistics.rating=tracks_persistent.rating where tracks_persistent.url=track_statistics.url and (track_statistics.rating is null or track_statistics.rating=0) and tracks_persistent.rating>0";
	}else {
		$sql = "UPDATE tracks,track_statistics SET track_statistics.rating=tracks.rating where tracks.url=track_statistics.url and (track_statistics.rating is null or track_statistics.rating=0) and tracks.rating>0";
	}
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}

	$sth->finish();
	$log->debug("Finished updating ratings in statistic data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();

	$timeMeasure->clear();
	$timeMeasure->start();
	$log->debug("Starting to update unrated ratings in statistic data based on null\n");
	# Now lets set all added times not already set
	$sql = "UPDATE track_statistics SET track_statistics.rating=null where track_statistics.rating=0";
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}

	$sth->finish();
	$log->debug("Finished updating unrated ratings in statistic data based on null, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();

	if($prefs->get("history_enabled")) {
		$timeMeasure->clear();
		$timeMeasure->start();
		$log->debug("Starting to update urls in track_history based on musicbrainz ids\n");
		# First lets refresh all urls with musicbrainz id's
	    	$sql = "UPDATE tracks,track_history SET track_history.url=tracks.url where tracks.musicbrainz_id is not null and tracks.musicbrainz_id=track_history.musicbrainz_id and track_history.url!=tracks.url and length(tracks.url)<".($useLongUrls?512:256);
		$sth = $dbh->prepare( $sql );
		$count = 0;
		eval {
			$count = $sth->execute();
			if($count eq '0E0') {
				$count = 0;
			}
			commit($dbh);
		};
		if( $@ ) {
		    $log->warn("Database error: $DBI::errstr\n");
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}

		$sth->finish();
		$log->debug("Finished updating urls in track_history based on musicbrainz ids, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
		$timeMeasure->stop();
		
		$timeMeasure->clear();
		$timeMeasure->start();
		$log->debug("Starting to update musicbrainz id's in track_history based on urls\n");
		# Now lets set all musicbrainz id's not already set
		$sql = "UPDATE tracks,track_history SET track_history.musicbrainz_id=tracks.musicbrainz_id where tracks.url=track_history.url and tracks.musicbrainz_id like '%-%' and track_history.musicbrainz_id is null";
		$sth = $dbh->prepare( $sql );
		$count = 0;
		eval {
			$count = $sth->execute();
			if($count eq '0E0') {
				$count = 0;
			}
			commit($dbh);
		};
		if( $@ ) {
		    $log->warn("Database error: $DBI::errstr\n");
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}

		$sth->finish();
		$log->debug("Finished updating musicbrainz id's in statistic data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
		$timeMeasure->stop();

		$timeMeasure->clear();
		$timeMeasure->start();
		$log->debug("Starting to add missing entries to history table\n");
		# Now lets add all tracks to history table which have been played and don't exist in history table
		$sql = "INSERT INTO track_history (url,musicbrainz_id,played,rating) select tracks.url,case when tracks.musicbrainz_id like '%-%' then tracks.musicbrainz_id else null end as musicbrainz_id,track_statistics.lastPlayed,track_statistics.rating from tracks join track_statistics on tracks.url=track_statistics.url and track_statistics.lastPlayed is not null left join track_history on tracks.url=track_history.url and track_statistics.lastPlayed=track_history.played where track_history.url is null and length(tracks.url)<".($useLongUrls?512:256);
		$sth = $dbh->prepare( $sql );
		$count = 0;
		eval {
			$count = $sth->execute();
			commit($dbh);
			if($count eq '0E0') {
				$count = 0;
			}
		};
		if( $@ ) {
		    $log->warn("Database error: $DBI::errstr\n");
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}

		$sth->finish();
		$log->debug("Finished adding missing entries to history table, adding $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
		$timeMeasure->stop();

		$timeMeasure->clear();
		$timeMeasure->start();
		$log->debug("Starting to update unrated ratings in history table based on null\n");
		# Now lets set all added times not already set
		$sql = "UPDATE track_history SET track_history.rating=null where track_history.rating=0";
		$sth = $dbh->prepare( $sql );
		$count = 0;
		eval {
			$count = $sth->execute();
			if($count eq '0E0') {
				$count = 0;
			}
			commit($dbh);
		};
		if( $@ ) {
		    $log->warn("Database error: $DBI::errstr\n");
		    eval {
		    	rollback($dbh); #just die if rollback is failing
	    	};
		}

		$sth->finish();
		$log->debug("Finished updating unrated ratings in history table based on null, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	}
	$timeMeasure->stop();
	$timeMeasure->clear();

}

sub purgeTracks {
	my $ds        = getCurrentDS();

	# First perform a refresh so we know we have correct data
	refreshTracks();
	
	my $dbh = getCurrentDBH();
	my $sth;
	my $sql;
	my $sqlupdate;
	my $sthupdate;
	my $count;
	$log->debug("Starting to remove statistic data from track_statistics which no longer exists\n");
	# Remove all tracks from track_statistics if they don't exist in tracks table
	$sql = "DELETE from track_statistics USING track_statistics left join tracks on track_statistics.url=tracks.url where tracks.url is null";
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}

	$sth->finish();
	$log->debug("Finished removing statistic data from track_statistics which no longer exists, removed $count items\n");

	$log->debug("Starting to remove statistic data from track_history which no longer exists\n");
	# Remove all tracks from track_history if they don't exist in tracks table
	$sql = "DELETE FROM track_history USING track_history left join tracks on track_history.url=tracks.url where tracks.url is null";
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}

	$sth->finish();
	$log->debug("Finished removing statistic data from track_history which no longer exists, removed $count items\n");
}

sub deleteAllTracks()
{
	my $dbh = getCurrentDBH();
	my $sth = $dbh->prepare( "delete from track_statistics" );
	
	eval {
		$sth->execute();
		commit($dbh);
	};
	$sth->finish();

	$sth = $dbh->prepare( "delete from track_history" );
	eval {
		$sth->execute();
		commit($dbh);
	};

	$sth->finish();
	$log->debug("TrackStat: Clear all data finished at: ".time()."\n");
}

sub executeSQLFile {
        my $file  = shift;

        my $sqlFile;
	for my $plugindir (Slim::Utils::OSDetect::dirsFor('Plugins')) {
		opendir(DIR, catdir($plugindir,"TrackStat")) || next;
       		$sqlFile = catdir($plugindir,"TrackStat", "SQL", $driver, $file);
       		closedir(DIR);
       	}

        $log->debug("Executing SQL file $sqlFile\n");

        open(my $fh, $sqlFile) or do {

                $log->warn("Couldn't open: $sqlFile : $!\n");
                return;
        };

		my $dbh = getCurrentDBH();

        my $statement   = '';
        my $inStatement = 0;

        for my $line (<$fh>) {
                chomp $line;

                # skip and strip comments & empty lines
                $line =~ s/\s*--.*?$//o;
                $line =~ s/^\s*//o;

                next if $line =~ /^--/;
                next if $line =~ /^\s*$/;

                if ($line =~ /^\s*(?:CREATE|SET|INSERT|UPDATE|DELETE|DROP|SELECT|ALTER|DROP)\s+/oi) {
                        $inStatement = 1;
                }

                if ($line =~ /;/ && $inStatement) {

                        $statement .= $line;


                        $log->debug("Executing SQL statement: [$statement]\n");

                        eval { $dbh->do($statement) };

                        if ($@) {
                                $log->warn("Couldn't execute SQL statement: [$statement] : [$@]\n");
                        }

                        $statement   = '';
                        $inStatement = 0;
                        next;
                }

                $statement .= $line if $inStatement;
        }

        commit($dbh);

        close $fh;
}

sub getRandomString {
    my $orderBy;
    if($driver eq 'mysql') {
    	$orderBy = "rand()";
    }else {
    	$orderBy = "random()";
    }
    return $orderBy;
}

sub getAddedTime {
	my $track = shift;
	return $track->timestamp;
}

sub getSQLPropertyValues {
	my $sqlstatements = shift;
	my @result =();
	my $dbh = Slim::Schema->storage->dbh();
	my $trackno = 0;
    	for my $sql (split(/[;]/,$sqlstatements)) {
	    	eval {
			$sql =~ s/^\s+//g;
			$sql =~ s/\s+$//g;
			my $sth = $dbh->prepare( $sql );
			$log->debug("Executing: $sql\n");
			$sth->execute() or do {
				$log->warn("Error executing: $sql\n");
				$sql = undef;
			};
	
			if ($sql =~ /^SELECT+/oi) {
				$log->debug("Executing and collecting: $sql\n");
				my $id;
				my $name;
				$sth->bind_col( 1, \$id);
				$sth->bind_col( 2, \$name);
				while( $sth->fetch() ) {
					my %item = (
						'id' => Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($id,'utf8')),
						'name' => Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($name,'utf8'))
					);
					push @result, \%item;
				}
			}
			$sth->finish();
		};
		if( $@ ) {
			$log->warn("Database error: $DBI::errstr\n");
		}		
	}
	return \@result;
}


# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

# don't use the external one because it doesn't know about the difference
# between a param and not...
#*unescape = \&URI::Escape::unescape;
sub unescape {
        my $in      = shift;
        my $isParam = shift;

        $in =~ s/\+/ /g if $isParam;
        $in =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

        return $in;
}

1;

__END__
