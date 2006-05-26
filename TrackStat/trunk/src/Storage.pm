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

sub init {
	$driver = Slim::Utils::Prefs::get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
    if($driver eq 'mysql') {
    	$distinct = 'distinct';
    }
    
	#Check if tables exists and create them if not
	debugMsg("Checking if track_statistics database table exists\n");
	my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
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
		my $sth = $dbh->prepare("show index from track_statistics;");
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
	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track = shift;
	my $ignoreTrackInSlimserver = shift;
	
	if(!defined($track) && !$ignoreTrackInSlimserver) {
		# The encapsulation with eval is just to make it crash safe
		eval {
			debugMsg("Reading slimserver track: $track_url\n");
			$track = $ds->objectForUrl($track_url);
		};
		if ($@) {
			debugMsg("Error retrieving track: $track_url\n");
		}
	}
	my $searchString = "";
	my $queryAttribute = "";
	
	if(!$ignoreTrackInSlimserver) {
		return 0 unless $track;

		$mbId = $track->{musicbrainz_id} if (!(defined($mbId)));
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
	my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
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
	
	my $ds        = Slim::Music::Info::getCurrentDataStore();
	if(!defined($track)) {
		$track     = $ds->objectForUrl($url);
	}
	my $trackHandle = Plugins::TrackStat::Storage::findTrack( $url,undef,$track);
	my $searchString = "";
	my $queryAttribute = "";
	my $sql;
	
	$mbId = $track->{musicbrainz_id} if (!(defined($mbId)));
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
	my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->bind_param(1, $searchString , SQL_VARCHAR);
		if ($trackHandle || defined($mbId)) {
			$sth->bind_param(2, $url , SQL_VARCHAR);
		}
		$sth->execute();
		$dbh->commit();
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	$dbh->rollback(); #just die if rollback is failing
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

	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = $ds->objectForUrl($url);
	my $trackHandle = Plugins::TrackStat::Storage::findTrack( $url,undef,$track);
	my $sql;
	$url = $track->url;

	debugMsg("Marking as played in storage\n");

	my $trackmbId = $track->{musicbrainz_id};
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
		$mbId = $track->{musicbrainz_id};
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

	my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->bind_param(1, $key , SQL_VARCHAR);
		$sth->execute();
		$dbh->commit();
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	$dbh->rollback(); #just die if rollback is failing
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

	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = undef;
	if(!$ignoreTrackInSlimserver) {
		$track = $ds->objectForUrl($url);
		return unless $track;
	}

	my $sql;
	my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
	if(defined $track) {
		$url = $track->url;
		$mbId = $track->{musicbrainz_id};
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
			$dbh->commit();
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	$dbh->rollback(); #just die if rollback is failing
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

	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = undef;
	if(!$ignoreTrackInSlimserver) {
		$track = $ds->objectForUrl($url);
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
		my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
		my $sth = $dbh->prepare( $sql );
		eval {
			$sth->bind_param(1, $key , SQL_VARCHAR);
			$sth->execute();
			$dbh->commit();
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	$dbh->rollback(); #just die if rollback is failing
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
		my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
		my $sth = $dbh->prepare( $sql );
		eval {
			$sth->bind_param(1, $url , SQL_VARCHAR);
			$sth->execute();
			$dbh->commit();
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	$dbh->rollback(); #just die if rollback is failing
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

	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = $ds->objectForUrl($url);

	return unless $track;

	my $trackHandle = Plugins::TrackStat::Storage::findTrack($url,undef,$track);
	my $sql;
	
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
				$sql = ("INSERT INTO track_statistics (url,playCount,added,lastPlayed) values (?,$playCount,$added,$lastPlayed)");
			}else {
				$sql = ("INSERT INTO track_statistics (url,playCount,added) values (?,$playCount,$added)");
			}
		}
		if($sql) {
			my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
			my $sth = $dbh->prepare( $sql );
			eval {
				$sth->bind_param(1, $url , SQL_VARCHAR);
				$sth->execute();
				$dbh->commit();
			};
			if( $@ ) {
			    warn "Database error: $DBI::errstr\n";
			    eval {
			    	$dbh->rollback(); #just die if rollback is failing
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
			$sql = ("INSERT INTO track_statistics (url,added,rating) values (?,$added,$rating)");
		}
		my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
		my $sth = $dbh->prepare( $sql );
		eval {
			$sth->bind_param(1, $url , SQL_VARCHAR);
			$sth->execute();
			$dbh->commit();
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	$dbh->rollback(); #just die if rollback is failing
		    };
		}
		$sth->finish();
	}
}


sub refreshTracks 
{
		
	my $ds        = Slim::Music::Info::getCurrentDataStore();
    
	my $timeMeasure = Time::Stopwatch->new();
    if($driver eq 'mysql') {
    	my $dbh = $ds->dbh();
		$timeMeasure->clear();
		$timeMeasure->start();
		my $sth = $dbh->prepare("show index from tracks;");
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
			$dbh->commit();
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	$dbh->rollback(); #just die if rollback is failing
		    };
		}
		debugMsg("Finished analyzing indexes : It took ".$timeMeasure->getElapsedTime()." seconds\n");
		$timeMeasure->stop();
    }

	$timeMeasure->clear();
	$timeMeasure->start();
	debugMsg("Starting to update urls in statistic data based on musicbrainz ids\n");
	# First lets refresh all urls with musicbrainz id's
	my $sql = "SELECT tracks.url,tracks.musicbrainz_id from tracks,track_statistics where tracks.musicbrainz_id is not null and tracks.musicbrainz_id=track_statistics.musicbrainz_id and track_statistics.url!=tracks.url";
    if($driver eq 'mysql') {
    	$sql = "SELECT tracks.url,tracks.musicbrainz_id from tracks,track_statistics where tracks.musicbrainz_id is not null and tracks.musicbrainz_id=track_statistics.musicbrainz_id and track_statistics.url!=tracks.url and length(tracks.url)<256";
	}
	my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
	my $sth = $dbh->prepare( $sql );
	my $sqlupdate = "UPDATE track_statistics set url=? where musicbrainz_id = ?";
	my $sthupdate = $dbh->prepare( $sqlupdate );
	my $count = 0;
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
		$dbh->commit();
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	$dbh->rollback(); #just die if rollback is failing
	    };
	}

	$sth->finish();
	$sthupdate->finish();
	debugMsg("Finished updating urls in statistic data based on musicbrainz ids, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();

	$timeMeasure->clear();
	$timeMeasure->start();
	debugMsg("Starting to update musicbrainz id's in statistic data based on urls\n");
	# Now lets set all musicbrainz id's not already set
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
		$dbh->commit();
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	$dbh->rollback(); #just die if rollback is failing
	    };
	}

	$sth->finish();
	$sthupdate->finish();
	debugMsg("Finished updating musicbrainz id's in statistic data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();
	
	if ($::VERSION ge '6.5') {
		$timeMeasure->clear();
		$timeMeasure->start();
		debugMsg("Starting to update ratings in standard slimserver database based on urls\n");
		# Now lets set all ratings not already set in the slimserver standards database
		$sql = "SELECT track_statistics.url,track_statistics.rating from tracks,track_statistics where tracks.url=track_statistics.url and track_statistics.rating>0 and (tracks.rating!=track_statistics.rating or tracks.rating is null)";
		$sth = $dbh->prepare( $sql );
		$count = 0;
		eval {
			$sth->execute();

			my( $url,$rating );
			$sth->bind_columns( undef, \$url, \$rating );
			while( $sth->fetch() ) {
				my $track = $ds->objectForUrl($url);
				# Run this within eval for now so it hides all errors until this is standard
				eval {
					$track->set('rating' => $rating);
					$track->update();
				};
				$count++;
			}
			$dbh->commit();
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		}

		$sth->finish();
		debugMsg("Finished updating ratings in standard slimserver database based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
		$timeMeasure->stop();
	}

	$timeMeasure->clear();
	$timeMeasure->start();
	debugMsg("Starting to update added times in statistic data based on urls\n");
	# Now lets set all added times not already set
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
		$dbh->commit();
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	$dbh->rollback(); #just die if rollback is failing
	    };
	}

	$sth->finish();
	$sthupdate->finish();
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
		$dbh->commit();
		if($count eq '0E0') {
			$count = 0;
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	$dbh->rollback(); #just die if rollback is failing
	    };
	}

	$sth->finish();
	debugMsg("Finished adding tracks without added times in statistic data based on urls, added $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();

	$timeMeasure->clear();
	$timeMeasure->start();
	debugMsg("Starting to update ratings in statistic data based on urls\n");
	# Now lets set all added times not already set
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
		$dbh->commit();
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	$dbh->rollback(); #just die if rollback is failing
	    };
	}

	$sth->finish();
	$sthupdate->finish();
	debugMsg("Finished updating ratings in statistic data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();

	if(Slim::Utils::Prefs::get("plugin_trackstat_history_enabled")) {
		$timeMeasure->clear();
		$timeMeasure->start();
		debugMsg("Starting to update urls in track_history based on musicbrainz ids\n");
		# First lets refresh all urls with musicbrainz id's
		$sql = "SELECT tracks.url,tracks.musicbrainz_id from tracks,track_history where tracks.musicbrainz_id is not null and tracks.musicbrainz_id=track_history.musicbrainz_id and track_history.url!=tracks.url";
	    if($driver eq 'mysql') {
	    	$sql = "SELECT tracks.url,tracks.musicbrainz_id from tracks,track_history where tracks.musicbrainz_id is not null and tracks.musicbrainz_id=track_history.musicbrainz_id and track_history.url!=tracks.url and length(tracks.url)<256";
	    }
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
			$dbh->commit();
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	$dbh->rollback(); #just die if rollback is failing
		    };
		}

		$sth->finish();
		$sthupdate->finish();
		debugMsg("Finished updating urls in track_history based on musicbrainz ids, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
		$timeMeasure->stop();
		
		$timeMeasure->clear();
		$timeMeasure->start();
		debugMsg("Starting to update musicbrainz id's in track_history based on urls\n");
		# Now lets set all musicbrainz id's not already set
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
			$dbh->commit();
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	$dbh->rollback(); #just die if rollback is failing
		    };
		}

		$sth->finish();
		$sthupdate->finish();
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
			$dbh->commit();
			if($count eq '0E0') {
				$count = 0;
			}
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	$dbh->rollback(); #just die if rollback is failing
		    };
		}

		$sth->finish();
		debugMsg("Finished adding missing entries to history table, adding $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	}
	$timeMeasure->stop();
	$timeMeasure->clear();

}

sub purgeTracks {
	my $ds        = Slim::Music::Info::getCurrentDataStore();

	# First perform a refresh so we know we have correct data
	refreshTracks();
	
	debugMsg("Starting to remove statistic data from track_statistics which no longer exists\n");
	# Remove all tracks from track_statistics if they don't exist in tracks table
	my $sql = "select track_statistics.url from track_statistics left join tracks on track_statistics.url=tracks.url where tracks.url is null";
	my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
	my $sth = $dbh->prepare( $sql );
	my $sqlupdate = "DELETE FROM track_statistics where url=?";
	my $sthupdate = $dbh->prepare( $sqlupdate );
	my $count = 0;
	eval {
		$sth->execute();

		my( $url);
		$sth->bind_columns( undef, \$url);
		while( $sth->fetch() ) {
			$sthupdate->bind_param(1, $url, SQL_VARCHAR);
			$sthupdate->execute();
			$count++;
		}
		$dbh->commit();
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	$dbh->rollback(); #just die if rollback is failing
	    };
	}

	$sth->finish();
	$sthupdate->finish();
	debugMsg("Finished removing statistic data from track_statistics which no longer exists, removed $count items\n");

	debugMsg("Starting to remove statistic data from track_history which no longer exists\n");
	# Remove all tracks from track_history if they don't exist in tracks table
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
		$dbh->commit();
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	$dbh->rollback(); #just die if rollback is failing
	    };
	}

	$sth->finish();
	$sthupdate->finish();
	debugMsg("Finished removing statistic data from track_history which no longer exists, removed $count items\n");
}

sub deleteAllTracks()
{
	my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
	my $sth = $dbh->prepare( "delete from track_statistics" );
	
	eval {
		$sth->execute();
		$dbh->commit();
	};
	$sth->finish();

	$sth = $dbh->prepare( "delete from track_history" );
	eval {
		$sth->execute();
		$dbh->commit();
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

		my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();

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

        $dbh->commit;

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
		return $track->{timestamp};
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
