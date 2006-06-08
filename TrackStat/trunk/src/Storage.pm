#         TrackStat::iTunes module
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

use Date::Parse qw(str2time);
use Fcntl ':flock'; # import LOCK_* constants
use File::Spec::Functions qw(:ALL);
use File::Basename;
use XML::Parser;
use DBI qw(:sql_types);
use Class::Struct;
use FindBin qw($Bin);
use POSIX qw(strftime ceil);

if ($] > 5.007) {
	require Encode;
}
if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
	eval "use Slim::Schema";
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

my $driver;
my $distinct = '';

sub getCurrentDBH {
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
		return Slim::Schema->storage->dbh();
	}else {
		return Slim::Music::Info::getCurrentDataStore()->dbh();
	}
}

sub getCurrentDS {
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
		return 'Slim::Schema';
	}else {
		return Slim::Music::Info::getCurrentDataStore();
	}
}

sub getMusicBrainzId {
	my $track = shift;
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
		return $track->musicbrainz_id;
	}else {
		return $track->{musicbrainz_id};
	}
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

sub objectForId {
	my $type = shift;
	my $id = shift;
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
		if($type eq 'artist') {
			$type = 'Contributor';
		}elsif($type eq 'album') {
			$type = 'Album';
		}elsif($type eq 'genre') {
			$type = 'Genre';
		}elsif($type eq 'track') {
			$type = 'Track';
		}
		return Slim::Schema->resultset($type)->find($id);
	}else {
		return getCurrentDS()->objectForId($type,$id);
	}
}

sub objectForUrl {
	my $url = shift;
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
		return Slim::Schema->objectForUrl({
			'url' => $url
		});
	}else {
		return getCurrentDS()->objectForUrl($url,undef,undef,1);
	}
}

sub init {
	$driver = Slim::Utils::Prefs::get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
    if($driver eq 'mysql') {
    	$distinct = 'distinct';
    }
    
	#Check if tables exists and create them if not
	debugMsg("Checking if track_statistics database table exists\n");
	my $dbh = getCurrentDBH();
	my $st = $dbh->table_info();
	my $tblexists;
	while (my ( $qual, $owner, $table, $type ) = $st->fetchrow_array()) {
		if($table eq "track_statistics") {
			$tblexists=1;
		}
	}
	unless ($tblexists) {
		debugMsg("Create database table\n");
		Plugins::TrackStat::Storage::executeSQLFile("dbcreate.sql");
	}
	
	debugMsg("Checking if track_history database table exists\n");
	$st = $dbh->table_info();
	$tblexists = undef;
	while (my ( $qual, $owner, $table, $type ) = $st->fetchrow_array()) {
		if($table eq "track_history") {
			$tblexists=1;
		}
	}
	unless ($tblexists) {
		debugMsg("Create database table track_history\n");
		Plugins::TrackStat::Storage::executeSQLFile("dbupgrade_history.sql");
	}
	
	eval { $dbh->do("select musicbrainz_id from track_statistics limit 1;") };
	if ($@) {
		debugMsg("Create database table column musicbrainz_id\n");
		Plugins::TrackStat::Storage::executeSQLFile("dbupgrade_musicbrainz.sql");
	}
	
	eval { $dbh->do("select added from track_statistics limit 1;") };
	if ($@) {
		debugMsg("Create database table column added\n");
		Plugins::TrackStat::Storage::executeSQLFile("dbupgrade_added.sql");
	}
	
    if($driver eq 'mysql') {
		my $sth = $dbh->prepare("show create table tracks");
		my $charset;
		eval {
			debugMsg("Checking charsets on tables\n");
			$sth->execute();
			my $line = undef;
			$sth->bind_col( 2, \$line);
			if( $sth->fetch() ) {
				if(defined($line) && ($line =~ /.*CHARSET\s*=\s*([^\s\r\n]+).*/)) {
					$charset = $1;
					debugMsg("Got tracks charset = $charset\n");
					
					if(defined($charset)) {
						$sth->finish();
						$sth = $dbh->prepare("show create table track_statistics");
						$sth->execute();
						$line = undef;
						$sth->bind_col( 2, \$line);
						if( $sth->fetch() ) {
							if(defined($line) && ($line =~ /.*CHARSET\s*=\s*([^\s\r\n]+).*/)) {
								my $ts_charset = $1;
								debugMsg("Got track_statistics charset = $ts_charset\n");
								if($charset ne $ts_charset) {
									debugMsg("Converting track_statistics to correct charset=$charset\n");
									eval { $dbh->do("alter table track_statistics convert to character set $charset") };
									if ($@) {
										debugMsg("Couldn't convert charsets: $@\n");
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
								debugMsg("Got track_history charset = $ts_charset\n");
								if($charset ne $ts_charset) {
									debugMsg("Converting track_history to correct charset=$charset\n");
									eval { $dbh->do("alter table track_history convert to character set $charset") };
									if ($@) {
										debugMsg("Couldn't convert charsets: $@\n");
									}
								}
							}
						}
						
					}
				}
			}
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		}
		$sth->finish();

		$sth = $dbh->prepare("show index from track_statistics;");
		eval {
			debugMsg("Checking if indexes is needed for track_statistics\n");
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
				msg("TrackStat::Storage: No urlIndex index found in track_statistics, creating index...\n");
				eval { $dbh->do("create index urlIndex on track_statistics (url(255));") };
				if ($@) {
					debugMsg("Couldn't add index: $@\n");
				}
			}
			if(!$foundMB) {
				msg("TrackStat::Storage: No musicbrainzIndex index found in track_statistics, creating index...\n");
				eval { $dbh->do("create index musicbrainzIndex on track_statistics (musicbrainz_id);") };
				if ($@) {
					debugMsg("Couldn't add index: $@\n");
				}
			}
			if($foundUrlMB) {
				msg("TrackStat::Storage: Dropping old url_musicbrainz index...\n");
				eval { $dbh->do("drop index url_musicbrainz on track_statistics;") };
				if ($@) {
					debugMsg("Couldn't drop index: $@\n");
				}
			}
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		}
		$sth->finish();

		$sth = $dbh->prepare("show index from track_history;");
		eval {
			debugMsg("Checking if indexes is needed for track_history\n");
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
				msg("TrackStat::Storage: No urlIndex index found in track_history, creating index...\n");
				eval { $dbh->do("create index urlIndex on track_history (url(255));") };
				if ($@) {
					debugMsg("Couldn't add index: $@\n");
				}
			}
			if(!$foundMB) {
				msg("TrackStat::Storage: No musicbrainzIndex index found in track_history, creating index...\n");
				eval { $dbh->do("create index musicbrainzIndex on track_history (musicbrainz_id);") };
				if ($@) {
					debugMsg("Couldn't add index: $@\n");
				}
			}
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		}
		$sth->finish();
		
    }
    
    if($driver eq 'SQLite') {
		my $sth = $dbh->prepare("select sql from sqlite_master where name='track_history'");
		eval {
			debugMsg("Checking if track_history contains autoincrement column\n");
			$sth->execute();
			my $sql = undef;
			$sth->bind_col( 1, \$sql);
			if( $sth->fetch() ) {
				if(defined($sql) && ($sql =~ /.*autoincrement.*/)) {
					debugMsg("Altering track_history table to remove autoincrement\n");
					Plugins::TrackStat::Storage::executeSQLFile("dbupgrade_history_noautoincrement.sql");
				}
			}
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		}
		$sth->finish();
    }

    # Only perform refresh at startup if this has been activated
    return unless Slim::Utils::Prefs::get("plugin_trackstat_refresh_startup");
	refreshTracks();
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
			debugMsg("Reading slimserver track: $track_url\n");
			$track = objectForUrl($track_url);
		};
		if ($@) {
			debugMsg("Error retrieving track: $track_url\n");
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
	debugMsg("findTrack(): URL: ".$track_url."\n");
	debugMsg("findTrack(): mbId: ". $mbId ."\n") if (defined($mbId));

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
	    warn "Database error: $DBI::errstr\n";
	}

	$sth->finish();

	return $result;
}

sub saveRating {
	my ($url,$mbId,$track,$rating) = @_;
	
	if(length($url)>255 && ($driver eq 'mysql')) {
		debugMsg("Ignore, url is ".length($url)." characters long which longer than the 255 characters which is supported\n");
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

	debugMsg("Store rating\n");

	if ($trackHandle) {
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
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
   	}

	$sth->finish();
}

sub savePlayCountAndLastPlayed
{
	my ($url,$mbId,$playCount,$lastPlayed) = @_;

	if(length($url)>255 && ($driver eq 'mysql')) {
		debugMsg("Ignore, url is ".length($url)." characters long which longer than the 255 characters which is supported\n");
		return;
	}

	my $ds        = getCurrentDS();
	my $track     = objectForUrl($url);
	my $trackHandle = Plugins::TrackStat::Storage::findTrack( $url,undef,$track);
	my $sql;
	$url = $track->url;

	debugMsg("Marking as played in storage\n");

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
	    warn "Database error: $DBI::errstr\n while executing:\n$sql\n";
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}
	$sth->finish();
}

sub addToHistory
{
	debugMsg("Entering addToHistory\n");
	my ($url,$mbId,$playedTime,$rating,$ignoreTrackInSlimserver) = @_;

	return unless Slim::Utils::Prefs::get("plugin_trackstat_history_enabled");
	
	if(length($url)>255 && ($driver eq 'mysql')) {
		debugMsg("Ignore, url is ".length($url)." characters long which longer than the 255 characters which is supported\n");
		return;
	}

	my $ds        = getCurrentDS();
	my $track     = undef;
	if(!$ignoreTrackInSlimserver) {
		$track = objectForUrl($url);
		return unless $track;
	}

	my $sql;
	my $dbh = getCurrentDBH();
	if(defined $track) {
		$url = $track->url;
		$mbId = getMusicBrainzId($track);
	}

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
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();

	my $key = $url;
	$sql = undef;
	if (defined($mbId)) {
		if (defined($rating)) {
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
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
		$sth->finish();
	}
	debugMsg("Exiting addToHistory\n");
}

sub saveTrack 
{
	my ($url,$mbId,$playCount,$added,$lastPlayed,$rating,$ignoreTrackInSlimserver) = @_;
		
	if(length($url)>255 && ($driver eq 'mysql')) {
		debugMsg("Ignore, url is ".length($url)." characters long which longer than the 255 characters which is supported\n");
		return;
	}

	my $ds        = getCurrentDS();
	my $track     = undef;
	if(!$ignoreTrackInSlimserver) {
		$track = objectForUrl($url);
		return unless $track;
	}

	my $trackHandle = Plugins::TrackStat::Storage::findTrack($url, $mbId,$track,$ignoreTrackInSlimserver);
	my $sql;
	
	if ($playCount) {
		debugMsg("Marking as played in storage: $playCount\n");

		my $key = $url;

		$lastPlayed = '0' if (!(defined($lastPlayed)));

		if($trackHandle) {
			my $queryParameter = "url";
			if (defined($mbId)) {
			    $queryParameter = "musicbrainz_id";
			    $key = $mbId;
			}

			$sql = "UPDATE track_statistics set playCount=$playCount, lastPlayed=$lastPlayed where $queryParameter = ?";
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
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}

		$sth->finish();
	}
	
	#Lookup again since the row can have been created above
	$trackHandle = Plugins::TrackStat::Storage::findTrack( $url,$mbId,$track,$ignoreTrackInSlimserver);
	if ($rating && $rating ne "") {
		debugMsg("Store rating: $rating\n");
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
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
		$sth->finish();
	}
}

sub mergeTrack()
{
	my ($url,$mbId,$playCount,$lastPlayed,$rating) = @_;

	if(length($url)>255 && ($driver eq 'mysql')) {
		debugMsg("Ignore, url is ".length($url)." characters long which longer than the 255 characters which is supported\n");
		return;
	}

	my $ds        = getCurrentDS();
	my $track     = objectForUrl($url);

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
		debugMsg("Marking as played in storage: $playCount\n");
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
			    warn "Database error: $DBI::errstr\n";
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
		debugMsg("Store rating: $rating\n");
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
		    warn "Database error: $DBI::errstr\n";
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
    if($driver eq 'mysql') {
		$timeMeasure->clear();
		$timeMeasure->start();
		$sth = $dbh->prepare("show index from tracks;");
		eval {
			debugMsg("Checking if additional indexes are needed for tracks\n");
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
				msg("TrackStat::Storage: No trackStatMBIndex index found in tracks, creating index...\n");
				eval { $dbh->do("create index trackStatMBIndex on tracks (musicbrainz_id);") };
				if ($@) {
					debugMsg("Couldn't add index: $@\n");
				}
			}
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		}
		$sth->finish();
		$timeMeasure->stop();
		$timeMeasure->start();
		debugMsg("Starting to analyze indexes\n");
		eval {
	    	$dbh->do("analyze table tracks;");
	    	$dbh->do("analyze table track_statistics;");
	    	$dbh->do("analyze table track_history;");
			commit($dbh);
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
		debugMsg("Finished analyzing indexes : It took ".$timeMeasure->getElapsedTime()." seconds\n");
		$timeMeasure->stop();
    }

	$timeMeasure->clear();
	$timeMeasure->start();
	debugMsg("Starting to update urls in statistic data based on musicbrainz ids\n");
	# First lets refresh all urls with musicbrainz id's
    if($driver eq 'mysql') {
    	$sql = "UPDATE tracks,track_statistics SET track_statistics.url=tracks.url where tracks.musicbrainz_id is not null and tracks.musicbrainz_id=track_statistics.musicbrainz_id and track_statistics.url!=tracks.url and length(tracks.url)<256";
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
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
    }else {
		my $sql = "SELECT tracks.url,tracks.musicbrainz_id from tracks,track_statistics where tracks.musicbrainz_id is not null and tracks.musicbrainz_id=track_statistics.musicbrainz_id and track_statistics.url!=tracks.url";
	    if($driver eq 'mysql') {
	    	$sql = "SELECT tracks.url,tracks.musicbrainz_id from tracks,track_statistics where tracks.musicbrainz_id is not null and tracks.musicbrainz_id=track_statistics.musicbrainz_id and track_statistics.url!=tracks.url and length(tracks.url)<256";
		}
		$sth = $dbh->prepare( $sql );
		$sqlupdate = "UPDATE track_statistics set url=? where musicbrainz_id = ?";
		$sthupdate = $dbh->prepare( $sqlupdate );
		$count = 0;
		eval {
			$sth->execute();
			debugMsg("Got selection after ".$timeMeasure->getElapsedTime()." seconds\n");
			my( $url,$mbId );
			$sth->bind_columns( undef, \$url, \$mbId );
			while( $sth->fetch() ) {
				$sthupdate->bind_param(1, $url, SQL_VARCHAR);
				$sthupdate->bind_param(2, $mbId, SQL_VARCHAR);
				$sthupdate->execute();
				$count++;
			}
			commit($dbh);
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
		$sthupdate->finish();
	}
	$sth->finish();
	debugMsg("Finished updating urls in statistic data based on musicbrainz ids, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();

	$timeMeasure->clear();
	$timeMeasure->start();
	debugMsg("Starting to update musicbrainz id's in statistic data based on urls\n");
	# Now lets set all musicbrainz id's not already set
	if($driver eq 'mysql') {
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
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
	}else {
		$sql = "SELECT tracks.url,tracks.musicbrainz_id from tracks,track_statistics where tracks.url=track_statistics.url and tracks.musicbrainz_id like '%-%' and track_statistics.musicbrainz_id is null";
		$sth = $dbh->prepare( $sql );
		$sqlupdate = "UPDATE track_statistics set musicbrainz_id=? where url=?";
		$sthupdate = $dbh->prepare( $sqlupdate );
		$count = 0;
		eval {
			$sth->execute();

			my( $url,$mbId );
			$sth->bind_columns( undef, \$url, \$mbId );
			while( $sth->fetch() ) {
				$sthupdate->bind_param(1, $mbId, SQL_VARCHAR);
				$sthupdate->bind_param(2, $url, SQL_VARCHAR);
				$sthupdate->execute();
				$count++;
			}
			commit($dbh);
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
		$sthupdate->finish();
	}

	$sth->finish();
	debugMsg("Finished updating musicbrainz id's in statistic data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();
	
	if ($::VERSION ge '6.5') {
		$timeMeasure->clear();
		$timeMeasure->start();
		debugMsg("Starting to update ratings in standard slimserver database based on urls\n");
		# Now lets set all ratings not already set in the slimserver standards database
		if($driver eq 'mysql') {
			$sql = "UPDATE tracks,track_statistics set tracks.rating=track_statistics.rating where tracks.url=track_statistics.url and track_statistics.rating>0 and (tracks.rating!=track_statistics.rating or tracks.rating is null)";
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
			    warn "Database error: $DBI::errstr\n";
			}
		}else {
			$sql = "SELECT track_statistics.url,track_statistics.rating from tracks,track_statistics where tracks.url=track_statistics.url and track_statistics.rating>0 and (tracks.rating!=track_statistics.rating or tracks.rating is null)";
			$sth = $dbh->prepare( $sql );
			$count = 0;
			eval {
				$sth->execute();

				my( $url,$rating );
				$sth->bind_columns( undef, \$url, \$rating );
				while( $sth->fetch() ) {
					my $track = objectForUrl($url);
					# Run this within eval for now so it hides all errors until this is standard
					eval {
						$track->set('rating' => $rating);
						$track->update();
					};
					$count++;
				}
				commit($dbh);
			};
			if( $@ ) {
			    warn "Database error: $DBI::errstr\n";
			}
		}

		$sth->finish();
		debugMsg("Finished updating ratings in standard slimserver database based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
		$timeMeasure->stop();
	}

	$timeMeasure->clear();
	$timeMeasure->start();
	debugMsg("Starting to update added times in statistic data based on urls\n");
	# Now lets set all added times not already set
	if($driver eq 'mysql') {
		if ($::VERSION ge '6.5') {
			$sql = "UPDATE tracks,track_statistics SET track_statistics.added=tracks.timestamp where tracks.url=track_statistics.url and track_statistics.added is null and tracks.timestamp is not null";
		}else {
			$sql = "UPDATE tracks,track_statistics SET track_statistics.added=tracks.age where tracks.url=track_statistics.url and track_statistics.added is null and tracks.age is not null";
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
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
	}else {
		if ($::VERSION ge '6.5') {
			$sql = "SELECT tracks.url,tracks.timestamp from tracks,track_statistics where tracks.url=track_statistics.url and track_statistics.added is null and tracks.timestamp is not null";
		}else {
			$sql = "SELECT tracks.url,tracks.age from tracks,track_statistics where tracks.url=track_statistics.url and track_statistics.added is null and tracks.age is not null";
		}
		$sth = $dbh->prepare( $sql );
		$sqlupdate = "UPDATE track_statistics set added=? where url=?";
		$sthupdate = $dbh->prepare( $sqlupdate );
		$count = 0;
		eval {
			$sth->execute();

			my( $url,$age );
			$sth->bind_columns( undef, \$url, \$age );
			while( $sth->fetch() ) {
				$sthupdate->bind_param(1, $age, SQL_VARCHAR);
				$sthupdate->bind_param(2, $url, SQL_VARCHAR);
				$sthupdate->execute();
				$count++;
			}
			commit($dbh);
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
		$sthupdate->finish();
	}

	$sth->finish();
	debugMsg("Finished updating added times in statistic data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();

	$timeMeasure->clear();
	$timeMeasure->start();
	debugMsg("Starting to add tracks without added times in statistic data based on urls\n");
	# Now lets set all new tracks with added times not already set
	if ($::VERSION ge '6.5') {
		$sql = "INSERT INTO track_statistics (url,musicbrainz_id,playcount,added,lastPlayed,rating) select tracks.url,case when tracks.musicbrainz_id like '%-%' then tracks.musicbrainz_id else null end as musicbrainz_id,tracks.playcount,tracks.timestamp,tracks.lastplayed,tracks.rating from tracks left join track_statistics on tracks.url = track_statistics.url where audio=1 and track_statistics.url is null";
	    if($driver eq 'mysql') {
	    	$sql = "INSERT INTO track_statistics (url,musicbrainz_id,playcount,added,lastPlayed,rating) select tracks.url,case when tracks.musicbrainz_id like '%-%' then tracks.musicbrainz_id else null end as musicbrainz_id,tracks.playcount,tracks.timestamp,tracks.lastplayed,tracks.rating from tracks left join track_statistics on tracks.url = track_statistics.url where audio=1 and track_statistics.url is null and length(tracks.url)<256";
	    }
	}else {
		$sql = "INSERT INTO track_statistics (url,musicbrainz_id,playCount,added,lastPlayed,rating) select tracks.url,case when tracks.musicbrainz_id like '%-%' then tracks.musicbrainz_id else null end as musicbrainz_id,tracks.playCount,tracks.age,tracks.lastPlayed,tracks.rating from tracks left join track_statistics on tracks.url = track_statistics.url where audio=1 and track_statistics.url is null";
	    if($driver eq 'mysql') {
	    	$sql = "INSERT INTO track_statistics (url,musicbrainz_id,playCount,added,lastPlayed,rating) select tracks.url,case when tracks.musicbrainz_id like '%-%' then tracks.musicbrainz_id else null end as musicbrainz_id,tracks.playCount,tracks.age,tracks.lastPlayed,tracks.rating from tracks left join track_statistics on tracks.url = track_statistics.url where audio=1 and track_statistics.url is null and length(tracks.url)<256";
		}
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
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}

	$sth->finish();
	debugMsg("Finished adding tracks without added times in statistic data based on urls, added $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();

	$timeMeasure->clear();
	$timeMeasure->start();
	debugMsg("Starting to update ratings in statistic data based on urls\n");
	# Now lets set all added times not already set
	if($driver eq 'mysql') {
		$sql = "UPDATE tracks,track_statistics SET track_statistics.rating=tracks.rating where tracks.url=track_statistics.url and (track_statistics.rating is null or track_statistics.rating=0) and tracks.rating>0";
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
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
	}else {
		$sql = "SELECT tracks.url,tracks.rating from tracks,track_statistics where tracks.url=track_statistics.url and (track_statistics.rating is null or track_statistics.rating=0) and tracks.rating>0";
		$sth = $dbh->prepare( $sql );
		$sqlupdate = "UPDATE track_statistics set rating=? where url=?";
		$sthupdate = $dbh->prepare( $sqlupdate );
		$count = 0;
		eval {
			$sth->execute();

			my( $url,$rating );
			$sth->bind_columns( undef, \$url, \$rating );
			while( $sth->fetch() ) {
				$sthupdate->bind_param(1, $rating, SQL_VARCHAR);
				$sthupdate->bind_param(2, $url, SQL_VARCHAR);
				$sthupdate->execute();
				$count++;
			}
			commit($dbh);
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
		$sthupdate->finish();
	}

	$sth->finish();
	debugMsg("Finished updating ratings in statistic data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();

	if(Slim::Utils::Prefs::get("plugin_trackstat_history_enabled")) {
		$timeMeasure->clear();
		$timeMeasure->start();
		debugMsg("Starting to update urls in track_history based on musicbrainz ids\n");
		# First lets refresh all urls with musicbrainz id's
		if($driver eq 'mysql') {
	    	$sql = "UPDATE tracks,track_history SET track_history.url=tracks.url where tracks.musicbrainz_id is not null and tracks.musicbrainz_id=track_history.musicbrainz_id and track_history.url!=tracks.url and length(tracks.url)<256";
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
			    warn "Database error: $DBI::errstr\n";
			    eval {
			    	rollback($dbh); #just die if rollback is failing
			    };
			}
		}else {
			$sql = "SELECT tracks.url,tracks.musicbrainz_id from tracks,track_history where tracks.musicbrainz_id is not null and tracks.musicbrainz_id=track_history.musicbrainz_id and track_history.url!=tracks.url";
			$sth = $dbh->prepare( $sql );
			$sqlupdate = "UPDATE track_history set url=? where musicbrainz_id = ?";
			$sthupdate = $dbh->prepare( $sqlupdate );
			$count = 0;
			eval {
				$sth->execute();

				my( $url,$mbId );
				$sth->bind_columns( undef, \$url, \$mbId );
				while( $sth->fetch() ) {
					$sthupdate->bind_param(1, $url, SQL_VARCHAR);
					$sthupdate->bind_param(2, $mbId, SQL_VARCHAR);
					$sthupdate->execute();
					$count++;
				}
				commit($dbh);
			};
			if( $@ ) {
			    warn "Database error: $DBI::errstr\n";
			    eval {
			    	rollback($dbh); #just die if rollback is failing
			    };
			}
			$sthupdate->finish();
		}

		$sth->finish();
		debugMsg("Finished updating urls in track_history based on musicbrainz ids, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
		$timeMeasure->stop();
		
		$timeMeasure->clear();
		$timeMeasure->start();
		debugMsg("Starting to update musicbrainz id's in track_history based on urls\n");
		# Now lets set all musicbrainz id's not already set
		if($driver eq 'mysql') {
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
			    warn "Database error: $DBI::errstr\n";
			    eval {
			    	rollback($dbh); #just die if rollback is failing
			    };
			}
		}else {
			$sql = "SELECT tracks.url,tracks.musicbrainz_id from tracks,track_history where tracks.url=track_history.url and tracks.musicbrainz_id like '%-%' and track_history.musicbrainz_id is null";
			$sth = $dbh->prepare( $sql );
			$sqlupdate = "UPDATE track_history set musicbrainz_id=? where url=?";
			$sthupdate = $dbh->prepare( $sqlupdate );
			$count = 0;
			eval {
				$sth->execute();

				my( $url,$mbId );
				$sth->bind_columns( undef, \$url, \$mbId );
				while( $sth->fetch() ) {
					$sthupdate->bind_param(1, $mbId, SQL_VARCHAR);
					$sthupdate->bind_param(2, $url, SQL_VARCHAR);
					$sthupdate->execute();
					$count++;
				}
				commit($dbh);
			};
			if( $@ ) {
			    warn "Database error: $DBI::errstr\n";
			    eval {
			    	rollback($dbh); #just die if rollback is failing
			    };
			}
			$sthupdate->finish();
		}

		$sth->finish();
		debugMsg("Finished updating musicbrainz id's in statistic data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
		$timeMeasure->stop();

		$timeMeasure->clear();
		$timeMeasure->start();
		debugMsg("Starting to add missing entries to history table\n");
		# Now lets add all tracks to history table which have been played and don't exist in history table
		$sql = "INSERT INTO track_history (url,musicbrainz_id,played,rating) select tracks.url,case when tracks.musicbrainz_id like '%-%' then tracks.musicbrainz_id else null end as musicbrainz_id,track_statistics.lastPlayed,track_statistics.rating from tracks join track_statistics on tracks.url=track_statistics.url and track_statistics.lastPlayed is not null left join track_history on tracks.url=track_history.url and track_statistics.lastPlayed=track_history.played where track_history.url is null;";
	    if($driver eq 'mysql') {
	    	$sql = "INSERT INTO track_history (url,musicbrainz_id,played,rating) select tracks.url,case when tracks.musicbrainz_id like '%-%' then tracks.musicbrainz_id else null end as musicbrainz_id,track_statistics.lastPlayed,track_statistics.rating from tracks join track_statistics on tracks.url=track_statistics.url and track_statistics.lastPlayed is not null left join track_history on tracks.url=track_history.url and track_statistics.lastPlayed=track_history.played where track_history.url is null and length(tracks.url)<256";
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
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}

		$sth->finish();
		debugMsg("Finished adding missing entries to history table, adding $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
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
	debugMsg("Starting to remove statistic data from track_statistics which no longer exists\n");
	# Remove all tracks from track_statistics if they don't exist in tracks table
	if($driver eq 'mysql') {
		$sql = "DELETE from track_statistics left join tracks on track_statistics.url=tracks.url where tracks.url is null";
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
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
	}else {
		$sql = "select track_statistics.url from track_statistics left join tracks on track_statistics.url=tracks.url where tracks.url is null";
		$sth = $dbh->prepare( $sql );
		$sqlupdate = "DELETE FROM track_statistics where url=?";
		$sthupdate = $dbh->prepare( $sqlupdate );
		$count = 0;
		eval {
			$sth->execute();

			my( $url);
			$sth->bind_columns( undef, \$url);
			while( $sth->fetch() ) {
				$sthupdate->bind_param(1, $url, SQL_VARCHAR);
				$sthupdate->execute();
				$count++;
			}
			commit($dbh);
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
		$sthupdate->finish();
	}

	$sth->finish();
	debugMsg("Finished removing statistic data from track_statistics which no longer exists, removed $count items\n");

	debugMsg("Starting to remove statistic data from track_history which no longer exists\n");
	# Remove all tracks from track_history if they don't exist in tracks table
	if($driver eq 'mysql') {
		$sql = "DELETE FROM track_history left join tracks on track_history.url=tracks.url where tracks.url is null";
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
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
	}else {
		$sql = "select track_history.url from track_history left join tracks on track_history.url=tracks.url where tracks.url is null";
		$sth = $dbh->prepare( $sql );
		$sqlupdate = "DELETE FROM track_history where url=?";
		$sthupdate = $dbh->prepare( $sqlupdate );
		$count = 0;
		eval {
			$sth->execute();

			my( $url);
			$sth->bind_columns( undef, \$url);
			while( $sth->fetch() ) {
				$sthupdate->bind_param(1, $url, SQL_VARCHAR);
				$sthupdate->execute();
				$count++;
			}
			commit($dbh);
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
		$sthupdate->finish();
	}

	$sth->finish();
	debugMsg("Finished removing statistic data from track_history which no longer exists, removed $count items\n");
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
	msg("TrackStat: Clear all data finished at: ".time()."\n");
}

sub executeSQLFile {
        my $file  = shift;

        my $sqlFile;
		if ($::VERSION ge '6.5') {
			for my $plugindir (Slim::Utils::OSDetect::dirsFor('Plugins')) {
				opendir(DIR, catdir($plugindir,"TrackStat")) || next;
        		$sqlFile = catdir($plugindir,"TrackStat", "SQL", $driver, $file);
        		closedir(DIR);
        	}
        }else {
         	$sqlFile = catdir($Bin, "Plugins", "TrackStat", "SQL", $driver, $file);
        }

        debugMsg("Executing SQL file $sqlFile\n");

        open(my $fh, $sqlFile) or do {

                msg("Couldn't open: $sqlFile : $!\n");
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


                        debugMsg("Executing SQL statement: [$statement]\n");

                        eval { $dbh->do($statement) };

                        if ($@) {
                                msg("Couldn't execute SQL statement: [$statement] : [$@]\n");
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
	if ($::VERSION ge '6.5') {
		if($::REVISION ge '7505') {
			return $track->timestamp;
		}else {
			return $track->{timestamp};
		}
	}else {
		return $track->{age};
	}
}

# A wrapper to allow us to uniformly turn on & off debug messages
sub debugMsg
{
	my $message = join '','TrackStat::Storage: ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_trackstat_showmessages"));
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
