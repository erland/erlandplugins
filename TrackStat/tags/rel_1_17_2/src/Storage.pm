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

sub getLastPlayedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.lastPlayed desc,tracks.lastPlayed desc,$orderBy limit $listLength;";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks,track_statistics where tracks.url=track_statistics.url and tracks.audio=1 order by track_statistics.lastPlayed desc,tracks.lastPlayed desc,$orderBy limit $listLength;";
    }
    getTracksWeb($sql,$params);
}

sub getLastPlayedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.lastPlayed desc,tracks.lastPlayed desc,$orderBy limit $listLength;";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select tracks.url from tracks,track_statistics where tracks.url=track_statistics.url and tracks.audio=1 order by track_statistics.lastPlayed desc,tracks.lastPlayed desc,$orderBy limit $listLength;";
    }
    return getTracks($sql,$limit);
}

sub getFirstPlayedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.lastPlayed asc,tracks.lastPlayed asc,$orderBy limit $listLength;";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks,track_statistics where tracks.url = track_statistics.url and tracks.audio=1 order by track_statistics.lastPlayed asc,tracks.lastPlayed asc,$orderBy limit $listLength;";
    }
    getTracksWeb($sql,$params);
}

sub getFirstPlayedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.lastPlayed asc,tracks.lastPlayed asc,$orderBy limit $listLength;";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select tracks.url from tracks,track_statistics where tracks.url = track_statistics.url and tracks.audio=1 order by track_statistics.lastPlayed asc,tracks.lastPlayed asc,$orderBy limit $listLength;";
    }
    return getTracks($sql,$limit);
}

sub getMostPlayedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks,track_statistics where tracks.url = track_statistics.url and tracks.audio=1 order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    }
    getTracksWeb($sql,$params);
}

sub getMostPlayedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select tracks.url from tracks,track_statistics where tracks.url = track_statistics.url and tracks.audio=1 order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    }
    return getTracks($sql,$limit);
}

sub getMostPlayedHistoryTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url,count(track_history.url) as playCount,0 as added,max(track_history.played) as lastPlayed,avg(track_history.rating) as avgrating from tracks,track_history where tracks.url = track_history.url and tracks.audio=1 and played$beforeAfter$beforeAfterTime group by track_history.url order by playCount desc,avgrating desc,$orderBy limit $listLength;";
    if($beforeAfter eq "<") {
	    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;"
    }
    getTracksWeb($sql,$params);
}

sub getMostPlayedHistoryTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url,count(track_history.url) as playCount,0 as added,max(track_history.played) as lastPlayed,avg(track_history.rating) as avgrating from tracks,track_history where tracks.url = track_history.url and tracks.audio=1 and played$beforeAfter$beforeAfterTime group by track_history.url order by playCount desc,avgrating desc,$orderBy limit $listLength;";
    if($beforeAfter eq "<") {
	    $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    }
    return getTracks($sql,$limit);
}

sub getLastAddedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.added desc,track_statistics.playCount, tracks.playCount desc,$orderBy limit $listLength;";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks,track_statistics where tracks.url = track_statistics.url and tracks.audio=1 order by track_statistics.added desc,track_statistics.playCount, tracks.playCount desc,$orderBy limit $listLength;";
    }
    getTracksWeb($sql,$params);
}

sub getLastAddedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.added desc,track_statistics.playCount, tracks.playCount desc,$orderBy limit $listLength;";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select tracks.url from tracks,track_statistics where tracks.url = track_statistics.url and tracks.audio=1 order by track_statistics.added desc,track_statistics.playCount, tracks.playCount desc,$orderBy limit $listLength;";
    }
    return getTracks($sql,$limit);
}

sub getLeastPlayedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks, track_statistics where tracks.url = track_statistics.url and tracks.audio=1 order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
    }
    getTracksWeb($sql,$params);
}

sub getLeastPlayedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select tracks.url from tracks, track_statistics where tracks.url = track_statistics.url and tracks.audio=1 order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
    }
    return getTracks($sql,$limit);
}

sub getNotPlayedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (tracks.playCount=0 or tracks.playCount is null) and (track_statistics.playCount=0 or track_statistics.playCount is null) order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks, track_statistics where tracks.url = track_statistics.url and tracks.audio=1 and (tracks.playCount=0 or tracks.playCount is null) and (track_statistics.playCount=0 or track_statistics.playCount is null) order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
    }
    getTracksWeb($sql,$params);
}

sub getNotPlayedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (tracks.playCount=0 or tracks.playCount is null) and (track_statistics.playCount=0 or track_statistics.playCount is null) order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select tracks.url from tracks, track_statistics where tracks.url = track_statistics.url and tracks.audio=1 and (tracks.playCount=0 or tracks.playCount is null) and (track_statistics.playCount=0 or track_statistics.playCount is null) order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
    }
    return getTracks($sql,$limit);
}

sub getTopRatedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks, track_statistics where tracks.url = track_statistics.url and tracks.audio=1 order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    }
    getTracksWeb($sql,$params);
}

sub getTopRatedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select tracks.url from tracks, track_statistics where tracks.url = track_statistics.url and tracks.audio=1 order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    }
    return getTracks($sql,$limit);
}

sub getTopRatedHistoryTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url,count(tracks.url) as playCount,0 as added,max(track_history.played) as lastPlayed,avg(track_history.rating) as avgrating from tracks, track_history where tracks.url = track_history.url and tracks.audio=1 and played$beforeAfter$beforeAfterTime group by tracks.url order by avgrating desc,playCount desc,$orderBy limit $listLength;";
    if($beforeAfter eq "<") {
	    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.lastPlayed<$beforeAfterTime order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    }
    getTracksWeb($sql,$params);
}

sub getTopRatedHistoryTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url,count(tracks.url) as playCount,0 as added,max(track_history.played) as lastPlayed,avg(track_history.rating) as avgrating from tracks, track_history where tracks.url = track_history.url and tracks.audio=1 and played$beforeAfter$beforeAfterTime group by tracks.url order by avgrating desc,playCount desc,$orderBy limit $listLength;";
    if($beforeAfter eq "<") {
	    $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.lastPlayed<$beforeAfterTime order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    }
    return getTracks($sql,$limit);
}

sub getTopRatedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded  from tracks, track_statistics,albums where tracks.url = track_statistics.url and tracks.album=albums.id group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    }
    getAlbumsWeb($sql,$params);
}

sub getTopRatedAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded  from tracks, track_statistics,albums where tracks.url = track_statistics.url and tracks.album=albums.id group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    }
    return getAlbumTracks($sql,$limit);
}

sub getTopRatedHistoryAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as minadded  from tracks,track_history, albums where tracks.url=track_history.url and tracks.album=albums.id and played$beforeAfter$beforeAfterTime group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    }
    getAlbumsWeb($sql,$params);
}

sub getTopRatedHistoryAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as minadded  from tracks,track_history, albums where tracks.url=track_history.url and tracks.album=albums.id and played$beforeAfter$beforeAfterTime group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    }
    return getAlbumTracks($sql,$limit);
}

sub getNotRatedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url,t1.playCount,t1.added,t1.lastPlayed,t1.rating from tracks left join track_statistics t1 on tracks.url=t1.url left join track_statistics t2 on tracks.url=t2.url and t2.rating>0 where tracks.audio=1 and t2.url is null order by t1.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    getTracksWeb($sql,$params);
}

sub getNotRatedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url from tracks left join track_statistics t1 on tracks.url=t1.url left join track_statistics t2 on tracks.url=t2.url and t2.rating>0 where tracks.audio=1 and t2.url is null order by t1.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    return getTracks($sql,$limit);
}

sub getNotRatedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having avgrating=0 order by avgcount desc,$orderBy limit $listLength";
    getAlbumsWeb($sql,$params);
}

sub getNotRatedAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having avgrating=0 order by avgcount desc,$orderBy limit $listLength";
    return getAlbumTracks($sql,$limit);
}

sub getMostPlayedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by avgcount desc,avgrating desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks,track_statistics,albums where tracks.url = track_statistics.url and tracks.album=albums.id group by tracks.album order by avgcount desc,avgrating desc,$orderBy limit $listLength";
    }
    getAlbumsWeb($sql,$params);
}

sub getMostPlayedAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by avgcount desc,avgrating desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks,track_statistics,albums where tracks.url = track_statistics.url and tracks.album=albums.id group by tracks.album order by avgcount desc,avgrating desc,$orderBy limit $listLength";
    }
    return getAlbumTracks($sql,$limit);
}

sub getMostPlayedHistoryAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as minadded  from tracks,track_history, albums where tracks.url=track_history.url and tracks.album=albums.id and played$beforeAfter$beforeAfterTime group by tracks.album order by avgcount desc,avgrating desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgcount desc,avgrating desc,$orderBy limit $listLength";
    }
    getAlbumsWeb($sql,$params);
}

sub getMostPlayedHistoryAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as minadded  from tracks,track_history, albums where tracks.url=track_history.url and tracks.album=albums.id and played$beforeAfter$beforeAfterTime group by tracks.album order by avgcount desc,avgrating desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgcount desc,avgrating desc,$orderBy limit $listLength";
    }
    return getAlbumTracks($sql,$limit);
}

sub getLastAddedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by minadded desc, avgcount desc,avgrating desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks,track_statistics,albums where tracks.url = track_statistics.url and tracks.album=albums.id group by tracks.album order by minadded desc, avgcount desc,avgrating desc,$orderBy limit $listLength";
    }
    getAlbumsWeb($sql,$params);
}

sub getLastAddedAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by minadded desc, avgcount desc,avgrating desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks,track_statistics,albums where tracks.url = track_statistics.url and tracks.album=albums.id group by tracks.album order by minadded desc, avgcount desc,avgrating desc,$orderBy limit $listLength";
    }
    return getAlbumTracks($sql,$limit);
}

sub getLeastPlayedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by avgcount asc,avgrating asc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks, track_statistics,albums where tracks.url = track_statistics.url and tracks.album=albums.id group by tracks.album order by avgcount asc,avgrating asc,$orderBy limit $listLength";
    }
    getAlbumsWeb($sql,$params);
}

sub getLeastPlayedAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by avgcount asc,avgrating asc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks, track_statistics,albums where tracks.url = track_statistics.url and tracks.album=albums.id group by tracks.album order by avgcount asc,avgrating asc,$orderBy limit $listLength";
    }
    return getAlbumTracks($sql,$limit);
}

sub getNotPlayedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then case when tracks.playCount is null then 0 else tracks.playCount end else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having avgcount=0 order by avgcount asc,avgrating asc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then case when tracks.playCount is null then 0 else tracks.playCount end else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks, track_statistics,albums where tracks.url = track_statistics.url and tracks.album=albums.id group by tracks.album having avgcount=0 order by avgcount asc,avgrating asc,$orderBy limit $listLength";
    }
    getAlbumsWeb($sql,$params);
}

sub getNotPlayedAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then case when tracks.playCount is null then 0 else tracks.playCount end else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having avgcount=0 order by avgcount asc,avgrating asc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then case when tracks.playCount is null then 0 else tracks.playCount end else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks, track_statistics,albums where tracks.url = track_statistics.url and tracks.album=albums.id group by tracks.album having avgcount=0 order by avgcount asc,avgrating asc,$orderBy limit $listLength";
    }
    return getAlbumTracks($sql,$limit);
}

sub getTopRatedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks , track_statistics, contributors, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    }
    getArtistsWeb($sql,$params);
}

sub getTopRatedArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks , track_statistics, contributors, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    }
    return getArtistTracks($sql,$limit);
}

sub getTopRatedHistoryArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as minadded from tracks,track_history,contributor_track,contributors where tracks.url = track_history.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and played$beforeAfter$beforeAfterTime group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,sumcount desc,$orderBy limit $listLength";    
	}
    getArtistsWeb($sql,$params);
}

sub getTopRatedHistoryArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as minadded from tracks,track_history,contributor_track,contributors where tracks.url = track_history.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and played$beforeAfter$beforeAfterTime group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,sumcount desc,$orderBy limit $listLength";    
	}
    return getArtistTracks($sql,$limit);
}

sub getTopRatedGenresWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select genres.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join genre_track on tracks.id=genre_track.track join genres on genres.id = genre_track.genre group by genres.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select genres.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks, track_statistics, genre_track,genres where tracks.url = track_statistics.url and tracks.id=genre_track.track and genres.id = genre_track.genre group by genres.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    }
    getGenresWeb($sql,$params);
}

sub getTopRatedGenreTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select genres.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join genre_track on tracks.id=genre_track.track join genres on genres.id = genre_track.genre group by genres.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select genres.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks, track_statistics, genre_track,genres where tracks.url = track_statistics.url and tracks.id=genre_track.track and genres.id = genre_track.genre group by genres.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    }
    return getGenreTracks($sql,$limit);
}

sub getTopRatedYearsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select year,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url group by year having year>0 order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select year,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks, track_statistics where tracks.url = track_statistics.url group by year having year>0 order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    }
    getYearsWeb($sql,$params);
}

sub getTopRatedYearTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select year,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url group by year having year>0 order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select year,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks, track_statistics where tracks.url = track_statistics.url group by year having year>0 order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    }
    return getYearTracks($sql,$limit);
}

sub getNotRatedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having avgrating=0 order by sumcount desc,$orderBy limit $listLength";
    getArtistsWeb($sql,$params);
}

sub getNotRatedArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having avgrating=0 order by sumcount desc,$orderBy limit $listLength";
    return getArtistTracks($sql,$limit);
}

sub getMostPlayedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks , track_statistics , contributors, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor group by contributors.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
    }
    getArtistsWeb($sql,$params);
}

sub getMostPlayedArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks , track_statistics , contributors, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor group by contributors.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
    }
    return getArtistTracks($sql,$limit);
}

sub getMostPlayedHistoryArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as minadded from tracks,track_history,contributor_track,contributors where tracks.url = track_history.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and played$beforeAfter$beforeAfterTime group by contributors.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by sumcount desc,avgrating desc,$orderBy limit $listLength";    
	}
    getArtistsWeb($sql,$params);
}

sub getMostPlayedHistoryArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as minadded from tracks,track_history,contributor_track,contributors where tracks.url = track_history.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and played$beforeAfter$beforeAfterTime group by contributors.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by sumcount desc,avgrating desc,$orderBy limit $listLength";    
	}
    return getArtistTracks($sql,$limit);
}

sub getMostPlayedGenresWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select genres.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join genre_track on tracks.id=genre_track.track join genres on genres.id = genre_track.genre group by genres.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select genres.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks , track_statistics , genres, genre_track where tracks.url = track_statistics.url and tracks.id=genre_track.track and genres.id = genre_track.genre group by genres.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
    }
    getGenresWeb($sql,$params);
}

sub getMostPlayedGenreTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select genres.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join genre_track on tracks.id=genre_track.track join genres on genres.id = genre_track.genre group by genres.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select genres.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks , track_statistics , genres, genre_track where tracks.url = track_statistics.url and tracks.id=genre_track.track and genres.id = genre_track.genre group by genres.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
    }
    return getGenreTracks($sql,$limit);
}

sub getMostPlayedYearsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select year,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url group by year having year>0 order by sumcount desc,avgrating desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select year,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks , track_statistics where tracks.url = track_statistics.url group by year having year>0 order by sumcount desc,avgrating desc,$orderBy limit $listLength";
    }
    getYearsWeb($sql,$params);
}

sub getMostPlayedYearTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select year,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url group by year having year>0 order by sumcount desc,avgrating desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select year,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks , track_statistics where tracks.url = track_statistics.url group by year having year>0 order by sumcount desc,avgrating desc,$orderBy limit $listLength";
    }
    return getYearTracks($sql,$limit);
}

sub getLastAddedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id order by minadded desc, sumcount desc,avgrating desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks , track_statistics , contributors, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor group by contributors.id order by minadded desc, sumcount desc,avgrating desc,$orderBy limit $listLength";
    }
    getArtistsWeb($sql,$params);
}

sub getLastAddedArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id order by minadded desc,sumcount desc,avgrating desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks , track_statistics , contributors, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor group by contributors.id order by minadded desc,sumcount desc,avgrating desc,$orderBy limit $listLength";
    }
    return getArtistTracks($sql,$limit);
}

sub getLeastPlayedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id order by sumcount asc,avgrating asc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks , track_statistics , contributors, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor group by contributors.id order by sumcount asc,avgrating asc,$orderBy limit $listLength";
    }
    getArtistsWeb($sql,$params);
}

sub getLeastPlayedArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id order by sumcount asc,avgrating asc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks , track_statistics , contributors, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor group by contributors.id order by sumcount asc,avgrating asc,$orderBy limit $listLength";
    }
    return getArtistTracks($sql,$limit);
}

sub getNotPlayedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then case when tracks.playCount is null then 0 else tracks.playCount end else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having sumcount=0 order by sumcount asc,avgrating asc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then case when tracks.playCount is null then 0 else tracks.playCount end else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks , track_statistics , contributors, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor group by contributors.id having sumcount=0 order by sumcount asc,avgrating asc,$orderBy limit $listLength";
    }
    getArtistsWeb($sql,$params);
}

sub getNotPlayedArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then case when tracks.playCount is null then 0 else tracks.playCount end else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having sumcount=0 order by sumcount asc,avgrating asc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then case when tracks.playCount is null then 0 else tracks.playCount end else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks , track_statistics , contributors, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor group by contributors.id having sumcount=0 order by sumcount asc,avgrating asc,$orderBy limit $listLength";
    }
    return getArtistTracks($sql,$limit);
}

sub getTracksWeb {
	my $sql = shift;
	my $params = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
	debugMsg("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->execute();

		my( $url, $playCount, $added, $lastPlayed, $rating );
		$sth->bind_columns( undef, \$url, \$playCount, \$added, \$lastPlayed, \$rating );
		my $itemNumber = 0;
		while( $sth->fetch() ) {
			$lastPlayed = 0 if (!(defined($lastPlayed)));
			$added = 0 if (!(defined($added)));
			$playCount = 0 if (!(defined($playCount)));
			$rating = 0 if (!(defined($rating)));
			my $track = $ds->objectForUrl($url);
			next unless defined $track;
		  	my %trackInfo = ();
			my $fieldInfo = Slim::DataStores::Base->fieldInfo;
            my $levelInfo = $fieldInfo->{'track'};
			
            &{$levelInfo->{'listItem'}}($ds, \%trackInfo, $track);
		  	$trackInfo{'title'} = Slim::Music::Info::standardTitle(undef,$track);
		  	$trackInfo{'lastPlayed'} = $lastPlayed;
		  	$trackInfo{'added'} = $added;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
			$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
            $trackInfo{'skinOverride'}     = $params->{'skinOverride'};
            $trackInfo{'song_count'}       = $playCount;
            $trackInfo{'attributes'}       = '&track='.$track->id;
            $trackInfo{'itemobj'}          = $track;
            $trackInfo{'listtype'} = 'track';
            		  	
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
}

sub fisher_yates_shuffle {
    my $myarray = shift;  
    my $i = @$myarray;
    while (--$i) {
        my $j = int rand ($i+1);
        @$myarray[$i,$j] = @$myarray[$j,$i];
    }
}
sub getTracks {
	my $sql = shift;
	my $limit = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
	debugMsg("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	my @result;
	eval {
		$sth->execute();
		my $url;
		$sth->bind_columns( undef, \$url );
		while( $sth->fetch() ) {
			my $track = $ds->objectForUrl($url);
		  	push @result, $track;
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
	fisher_yates_shuffle(\@result);
	if(defined($limit) && scalar(@result)>$limit) {
		my $entriesToRemove = scalar(@result) - $limit;
		splice(@result,0,$entriesToRemove);
	}
	return \@result;
}

sub getAlbumsWeb {
	my $sql = shift;
	my $params = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
	debugMsg("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->execute();

		my( $id, $rating, $playCount, $lastPlayed, $added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount, \$lastPlayed, \$added );
		my $itemNumber = 0;
		while( $sth->fetch() ) {
			$playCount = 0 if (!(defined($playCount)));
			$lastPlayed = 0 if (!(defined($lastPlayed)));
			$added = 0 if (!(defined($added)));
			$rating = 0 if (!(defined($rating)));
			my $album = $ds->objectForId('album',$id);
			next unless defined $album;
		  	my %trackInfo = ();
			my $fieldInfo = Slim::DataStores::Base->fieldInfo;
            my $levelInfo = $fieldInfo->{'album'};
			
            &{$levelInfo->{'listItem'}}($ds, \%trackInfo, $album);
		  	$trackInfo{'title'} = undef;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
			$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
		  	$trackInfo{'lastPlayed'} = $lastPlayed;
		  	$trackInfo{'added'} = $added;
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
            $trackInfo{'skinOverride'}     = $params->{'skinOverride'};
            $trackInfo{'song_count'}       = ceil($playCount);
            $trackInfo{'attributes'}       = '&album='.$album->id;
            $trackInfo{'itemobj'}{'album'} = $album;
            $trackInfo{'listtype'} = 'album';
		  	
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
}

sub getAlbumTracks {
	my $sql = shift;
	my $limit = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
	debugMsg("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	my @result;
	eval {
		$sth->execute();
		my( $id, $rating, $playCount, $lastPlayed, $added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount, \$lastPlayed, \$added );
		my @albums;
		while( $sth->fetch() ) {
			push @albums, $id;
		}
		if(scalar(@albums)>0) {
			fisher_yates_shuffle(\@albums);
			$id = shift @albums;
			my $album = $ds->objectForId('album',$id);
			debugMsg("Getting tracks for album: ".$album->title."\n");
			my $iterator = $album->tracks;
			for my $item ($iterator->slice(0,$iterator->count)) {
				push @result, $item;
			}
		}
		debugMsg("Got ".scalar(@result)." tracks\n");
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
	if(defined($limit)) {
		fisher_yates_shuffle(\@result);
		if(scalar(@result)>$limit) {
			my $entriesToRemove = scalar(@result) - $limit;
			splice(@result,0,$entriesToRemove);
		}
	}
	debugMsg("Returning ".scalar(@result)." tracks\n");
	return \@result;
}

sub getArtistsWeb {
	my $sql = shift;
	my $params = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
	debugMsg("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->execute();

		my( $id, $rating, $playCount,$lastPlayed,$added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount,\$lastPlayed,\$added );
		my $itemNumber = 0;
		while( $sth->fetch() ) {
			$playCount = 0 if (!(defined($playCount)));
			$lastPlayed = 0 if (!(defined($lastPlayed)));
			$added = 0 if (!(defined($added)));
			$rating = 0 if (!(defined($rating)));
			my $artist = $ds->objectForId('artist',$id);
			next unless defined $artist;
		  	my %trackInfo = ();
			my $fieldInfo = Slim::DataStores::Base->fieldInfo;
            my $levelInfo = $fieldInfo->{'artist'};
			
            &{$levelInfo->{'listItem'}}($ds, \%trackInfo, $artist);
		  	$trackInfo{'title'} = undef;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
		  	$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
		  	$trackInfo{'lastPlayed'} = $lastPlayed;
		  	$trackInfo{'added'} = $added;
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
            $trackInfo{'skinOverride'}     = $params->{'skinOverride'};
            $trackInfo{'song_count'}       = ceil($playCount);
            $trackInfo{'attributes'}       = '&artist='.$artist->id;
            $trackInfo{'itemobj'}{'artist'} = $artist;
            $trackInfo{'listtype'} = 'artist';
            		  	
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
}

sub getArtistTracks {
	my $sql = shift;
	my $limit = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
	debugMsg("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	my @result;
	eval {
		$sth->execute();
		my( $id, $rating, $playCount,$lastPlayed,$added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount,\$lastPlayed,\$added);
		my @artists;
		while( $sth->fetch() ) {
			push @artists, $id;
		}
		if(scalar(@artists)>0) {
			fisher_yates_shuffle(\@artists);
			for (my $i = 0; $i < 2 && scalar(@result)<2; $i++) {
				$id = shift @artists;
				my $artist = $ds->objectForId('artist',$id);

				debugMsg("Getting tracks for artist: ".$artist->name."\n");
				my $artistFind = {'artist' => $artist->id };

				my $items = $ds->find({
					'field'  => 'track',
					'find'   => $artistFind,
					'sortBy' => 'random',
					'limit'  => $limit,
					'cache'  => 0,
				});
				for my $item (@$items) {
					push @result, $item;
				}
				debugMsg("Got ".scalar(@result)." tracks for ".$artist->name."\n");
			}
		}
		debugMsg("Got ".scalar(@result)." tracks\n");
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
	debugMsg("Returning ".scalar(@result)." tracks\n");
	return \@result;
}

sub getGenresWeb {
	my $sql = shift;
	my $params = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
	debugMsg("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->execute();

		my( $id, $rating, $playCount,$lastPlayed,$added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount,\$lastPlayed,\$added );
		my $itemNumber = 0;
		while( $sth->fetch() ) {
			$playCount = 0 if (!(defined($playCount)));
			$lastPlayed = 0 if (!(defined($lastPlayed)));
			$added = 0 if (!(defined($added)));
			$rating = 0 if (!(defined($rating)));
			my $genre = $ds->objectForId('genre',$id);
			next unless defined $genre;
		  	my %trackInfo = ();
			my $fieldInfo = Slim::DataStores::Base->fieldInfo;
            my $levelInfo = $fieldInfo->{'genre'};
			
            &{$levelInfo->{'listItem'}}($ds, \%trackInfo, $genre);
		  	$trackInfo{'title'} = undef;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
			$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
		  	$trackInfo{'lastPlayed'} = $lastPlayed;
		  	$trackInfo{'added'} = $added;
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
            $trackInfo{'skinOverride'}     = $params->{'skinOverride'};
            $trackInfo{'song_count'}       = ceil($playCount);
            $trackInfo{'attributes'}       = '&genre='.$genre->id;
            $trackInfo{'itemobj'}{'genre'} = $genre;
            $trackInfo{'listtype'} = 'genre';
            		  	
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
}

sub getGenreTracks {
	my $sql = shift;
	my $limit = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
	debugMsg("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	my @result;
	eval {
		$sth->execute();
		my( $id, $rating, $playCount,$lastPlayed,$added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount,\$lastPlayed,\$added);
		my @genres;
		while( $sth->fetch() ) {
			push @genres, $id;
		}
		if(scalar(@genres)>0) {
			fisher_yates_shuffle(\@genres);
			for (my $i = 0; $i < 2 && scalar(@result)<2; $i++) {
				$id = shift @genres;
				my $genre = $ds->objectForId('genre',$id);

				debugMsg("Getting tracks for genre: ".$genre->name."\n");
				my $genreFind = {'genre' => $genre->id };

				my $items = $ds->find({
					'field'  => 'track',
					'find'   => $genreFind,
					'sortBy' => 'random',
					'limit'  => $limit,
					'cache'  => 0,
				});
				for my $item (@$items) {
					push @result, $item;
				}
				debugMsg("Got ".scalar(@result)." tracks for ".$genre->name."\n");
			}
		}
		debugMsg("Got ".scalar(@result)." tracks\n");
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
	debugMsg("Returning ".scalar(@result)." tracks\n");
	return \@result;
}

sub getYearsWeb {
	my $sql = shift;
	my $params = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
	debugMsg("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->execute();

		my( $id, $rating, $playCount,$lastPlayed,$added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount,\$lastPlayed,\$added );
		my $itemNumber = 0;
		while( $sth->fetch() ) {
			$playCount = 0 if (!(defined($playCount)));
			$lastPlayed = 0 if (!(defined($lastPlayed)));
			$added = 0 if (!(defined($added)));
			$rating = 0 if (!(defined($rating)));
			my $year = $id;
		  	my %trackInfo = ();
			#my $fieldInfo = Slim::DataStores::Base->fieldInfo;
            #my $levelInfo = $fieldInfo->{'genre'};
			
            #&{$levelInfo->{'listItem'}}($ds, \%trackInfo, $genre);
		  	$trackInfo{'title'} = undef;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
			$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
		  	$trackInfo{'lastPlayed'} = $lastPlayed;
		  	$trackInfo{'added'} = $added;
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
            $trackInfo{'skinOverride'}     = $params->{'skinOverride'};
            $trackInfo{'song_count'}       = ceil($playCount);
            $trackInfo{'attributes'}       = '&year='.$year;
            $trackInfo{'itemobj'}{'year'} = $year;
            $trackInfo{'listtype'} = 'year';
            		  	
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
}

sub getYearTracks {
	my $sql = shift;
	my $limit = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
	debugMsg("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	my @result;
	eval {
		$sth->execute();
		my( $id, $rating, $playCount,$lastPlayed,$added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount,\$lastPlayed,\$added);
		my @years;
		while( $sth->fetch() ) {
			push @years, $id;
		}
		if(scalar(@years)>0) {
			fisher_yates_shuffle(\@years);
			for (my $i = 0; $i < 2 && scalar(@result)<2; $i++) {
				$id = shift @years;
				my $year = $id;

				debugMsg("Getting tracks for year: ".$year."\n");
				my $yearFind = {'year' => $year };

				my $items = $ds->find({
					'field'  => 'track',
					'find'   => $yearFind,
					'sortBy' => 'random',
					'limit'  => $limit,
					'cache'  => 0,
				});
				for my $item (@$items) {
					push @result, $item;
				}
				debugMsg("Got ".scalar(@result)." tracks for ".$year."\n");
			}
		}
		debugMsg("Got ".scalar(@result)." tracks\n");
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
	debugMsg("Returning ".scalar(@result)." tracks\n");
	return \@result;
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
