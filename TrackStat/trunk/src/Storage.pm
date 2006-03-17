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
	lastPlayed => '$',
	rating => '$'
};

sub init {
	#Check if tables exists and create them if not
	debugMsg("Checking if database table exists\n");
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
	eval { $dbh->do("select musicbrainz_id from track_statistics limit 1;") };
	if ($@) {
		debugMsg("Create database table column musicbrainz_id\n");
		Plugins::TrackStat::Storage::executeSQLFile("dbupgrade_musicbrainz.sql");
	}
	refreshTracks();
}

sub findTrack {
	my $track_url = shift;
	my $mbId      = shift;
	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = $ds->objectForUrl($track_url);
	my $searchString = "";
	my $queryAttribute = "";
	
	return 0 unless $track;

	$mbId = $track->{musicbrainz_id} if (!(defined($mbId)));

	debugMsg("findTrack(): URL: ".$track->url."\n");
	debugMsg("findTrack(): mbId: ". $mbId ."\n") if (defined($mbId));

	# create searchString and remove duplicate/trailing whitespace as well.
	if (defined($mbId)) {
		$searchString = $mbId;
		$queryAttribute = "musicbrainz_id";
	} else {
		$searchString = $track->url;
		$queryAttribute = "url";
	}

	return 0 unless length($searchString) >= 1;

	my $sql = "SELECT url, musicbrainz_id, playCount, lastPlayed, rating FROM track_statistics where $queryAttribute = ? or url = ?";
	my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
	my $sth = $dbh->prepare( $sql );
	my $result = undef;
	eval {
		$sth->bind_param(1, $searchString , SQL_VARCHAR);
		$sth->bind_param(2, $track->url , SQL_VARCHAR);
		$sth->execute();

		my( $url, $mbId, $playCount, $lastPlayed, $rating );
		$sth->bind_columns( undef, \$url, \$mbId, \$playCount, \$lastPlayed, \$rating );
		while( $sth->fetch() ) {
		  $result = TrackInfo->new( url => $url, mbId => $mbId, playCount => $playCount, lastPlayed => $lastPlayed, rating => $rating );
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}

	$sth->finish();

	return $result;
}

sub saveRating {
	my ($url,$mbId,$rating) = @_;
	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = $ds->objectForUrl($url);
	my $trackHandle = Plugins::TrackStat::Storage::findTrack( $url);
	my $searchString = "";
	my $queryAttribute = "";
	my $sql;
	
	$mbId = $track->{musicbrainz_id} if (!(defined($mbId)));

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
		if(defined($mbId)) {
			$sql = ("INSERT INTO track_statistics (musicbrainz_id,url,rating) values (?,?,$rating)");
		}else {
			$sql = ("INSERT INTO track_statistics (url,rating) values (?,$rating)");
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
	    $dbh->rollback(); #just die if rollback is failing
	}

	$sth->finish();
}

sub savePlayCountAndLastPlayed
{
	my ($url,$mbId,$playCount,$lastPlayed) = @_;

	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = $ds->objectForUrl($url);
	my $trackHandle = Plugins::TrackStat::Storage::findTrack( $url);
	my $sql;
	$url = $track->url;

	debugMsg("Marking as played in storage\n");

	my $trackmbId = $track->musicbrainz_id;

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
		if (defined($mbId)) {
			$sql = "INSERT INTO track_statistics (url, musicbrainz_id, playCount, lastPlayed) values (?, '$mbId', $playCount, $lastPlayed)";
		} else {
			if(defined($trackmbId)) {
				$sql = "INSERT INTO track_statistics (url, musicbrainz_id, playCount, lastPlayed) values (?, '$trackmbId', $playCount, $lastPlayed)";
			}else {
				$sql = "INSERT INTO track_statistics (url, musicbrainz_id, playCount, lastPlayed) values (?, NULL, $playCount, $lastPlayed)";
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
	    $dbh->rollback(); #just die if rollback is failing
	}
	$sth->finish();
}

sub saveTrack 
{
	my ($url,$mbId,$playCount,$lastPlayed,$rating) = @_;
		
	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = $ds->objectForUrl($url);

	return unless $track;

	my $trackHandle = Plugins::TrackStat::Storage::findTrack($url, $mbId);
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
				$sql = "INSERT INTO track_statistics (url, musicbrainz_id, playCount, lastPlayed) values (?, '$mbId', $playCount, $lastPlayed)";
			}else {
				$sql = "INSERT INTO track_statistics (url, musicbrainz_id, playCount, lastPlayed) values (?, NULL, $playCount, $lastPlayed)";
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
		    $dbh->rollback(); #just die if rollback is failing
		}

		$sth->finish();
	}
	
	#Lookup again since the row can have been created above
	$trackHandle = Plugins::TrackStat::Storage::findTrack( $url);
	if ($rating && $rating ne "") {
		debugMsg("Store rating: $rating\n");
	    #ratings are 0-5 stars, 100 = 5 stars

		if ($trackHandle) {
			$sql = ("UPDATE track_statistics set rating=$rating where url=?");
		} else {
			$sql = ("INSERT INTO track_statistics (url,rating) values (?,$rating)");
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
		    $dbh->rollback(); #just die if rollback is failing
		}
		$sth->finish();
	}
}

sub mergeTrack()
{
	my ($url,$mbId,$playCount,$lastPlayed,$rating) = @_;

	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = $ds->objectForUrl($url);

	return unless $track;

	my $trackHandle = Plugins::TrackStat::Storage::findTrack($url);
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
			if($lastPlayed) {
				$sql = ("INSERT INTO track_statistics (url,playCount,lastPlayed) values (?,$playCount,$lastPlayed)");
			}else {
				$sql = ("INSERT INTO track_statistics (url,playCount) values (?,$playCount)");
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
			    $dbh->rollback(); #just die if rollback is failing
			}

			$sth->finish();
		}
	}
	
	#Lookup again since the row can have been created above
	$trackHandle = Plugins::TrackStat::Storage::findTrack( $url);
	if ($rating && $rating ne "") {
		debugMsg("Store rating: $rating\n");
	    #ratings are 0-5 stars, 100 = 5 stars

		if ($trackHandle) {
			$sql = ("UPDATE track_statistics set rating=$rating where url=?");
		} else {
			$sql = ("INSERT INTO track_statistics (url,rating) values (?,$rating)");
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
		    $dbh->rollback(); #just die if rollback is failing
		}
		$sth->finish();
	}
}


sub refreshTracks 
{
		
	my $ds        = Slim::Music::Info::getCurrentDataStore();
	
	debugMsg("Starting to update urls in statistic data based on musicbrainz ids\n");
	# First lets refresh all urls with musicbrainz id's
	my $sql = "SELECT tracks.url,tracks.musicbrainz_id from tracks,track_statistics where tracks.musicbrainz_id is not null and tracks.musicbrainz_id=track_statistics.musicbrainz_id and track_statistics.url!=tracks.url";
	my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
	my $sth = $dbh->prepare( $sql );
	my $sqlupdate = "UPDATE track_statistics set url=? where musicbrainz_id = ?";
	my $sthupdate = $dbh->prepare( $sqlupdate );
	my $count = 0;
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
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}

	$dbh->commit();
	$sth->finish();
	$sthupdate->finish();
	debugMsg("Finished updating urls in statistic data based on musicbrainz ids, updated $count items\n");
	
	
	debugMsg("Starting to update musicbrainz id's in statistic data based on urls\n");
	# Now lets set all musicbrainz id's not already set
	$sql = "SELECT tracks.url,tracks.musicbrainz_id from tracks,track_statistics where tracks.url=track_statistics.url and tracks.musicbrainz_id is not null and track_statistics.musicbrainz_id is null";
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
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}

	$dbh->commit();
	$sth->finish();
	$sthupdate->finish();
	debugMsg("Finished updating musicbrainz id's in statistic data based on urls, updated $count items\n");
	
	if ($::VERSION ge '6.5') {
		debugMsg("Starting to update ratings in standard slimserver database based on urls\n");
		# Now lets set all ratings not already set in the slimserver standards database
		$sql = "SELECT track_statistics.url,track_statistics.rating from tracks,track_statistics where tracks.url=track_statistics.url and track_statistics.rating is not null and (tracks.rating!=track_statistics.rating or tracks.rating is null)";
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
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		}

		$dbh->commit();
		$sth->finish();
		debugMsg("Finished updating ratings in standard slimserver database based on urls, updated $count items\n");
	}

}

sub purgeTracks {
	my $ds        = Slim::Music::Info::getCurrentDataStore();

	# First perform a refresh so we know we have correct data
	refreshTracks();
	
	debugMsg("Starting to remove statistic data which no longer exists\n");
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
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}

	$dbh->commit();
	$sth->finish();
	$sthupdate->finish();
	debugMsg("Finished removing statistic data which no longer exists, removed $count items\n");
}

sub deleteAllTracks()
{
	my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
	my $sth = $dbh->prepare( "delete from track_statistics" );
	
	$sth->execute();
	$dbh->commit();

	$sth->finish();
	msg("TrackStat: Clear all data finished at: ".time()."\n");
}

sub executeSQLFile {
        my $file  = shift;

		my $driver = Slim::Utils::Prefs::get('dbsource');
        $driver =~ s/dbi:(.*?):(.*)$/$1/;
        
        my $sqlFile = catdir($Bin, "Plugins", "TrackStat", "SQL", $driver, $file);

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
	my $driver = Slim::Utils::Prefs::get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
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
    my $sql = "select tracks.url,track_statistics.playCount,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.lastPlayed desc,tracks.lastPlayed desc,$orderBy limit $listLength;";
    getTracksWeb($sql,$params);
}

sub getLastPlayedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.lastPlayed desc,tracks.lastPlayed desc,$orderBy limit $listLength;";
    return getTracks($sql,$limit);
}

sub getFirstPlayedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url,track_statistics.playCount,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.lastPlayed asc,tracks.lastPlayed asc,$orderBy limit $listLength;";
    getTracksWeb($sql,$params);
}

sub getFirstPlayedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.lastPlayed asc,tracks.lastPlayed asc,$orderBy limit $listLength;";
    return getTracks($sql,$limit);
}

sub getMostPlayedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url,track_statistics.playCount,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    getTracksWeb($sql,$params);
}

sub getMostPlayedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    return getTracks($sql,$limit);
}

sub getLeastPlayedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url,track_statistics.playCount,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
    getTracksWeb($sql,$params);
}

sub getLeastPlayedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
    return getTracks($sql,$limit);
}

sub getTopRatedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url,track_statistics.playCount,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    getTracksWeb($sql,$params);
}

sub getTopRatedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    return getTracks($sql,$limit);
}

sub getTopRatedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(track_statistics.rating) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    getAlbumsWeb($sql,$params);
}

sub getTopRatedAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(track_statistics.rating) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    return getAlbumTracks($sql,$limit);
}

sub getMostPlayedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(track_statistics.rating) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by avgcount desc,avgrating desc,$orderBy limit $listLength";
    getAlbumsWeb($sql,$params);
}

sub getMostPlayedAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(track_statistics.rating) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by avgcount desc,avgrating desc,$orderBy limit $listLength";
    return getAlbumTracks($sql,$limit);
}

sub getLeastPlayedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(track_statistics.rating) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by avgcount asc,avgrating asc,$orderBy limit $listLength";
    getAlbumsWeb($sql,$params);
}

sub getLeastPlayedAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select albums.id,avg(track_statistics.rating) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by avgcount asc,avgrating asc,$orderBy limit $listLength";
    return getAlbumTracks($sql,$limit);
}


sub getTopRatedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(track_statistics.rating) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    getArtistsWeb($sql,$params);
}

sub getTopRatedArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(track_statistics.rating) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    return getArtistTracks($sql,$limit);
}

sub getMostPlayedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(track_statistics.rating) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
    getArtistsWeb($sql,$params);
}

sub getMostPlayedArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(track_statistics.rating) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
    return getArtistTracks($sql,$limit);
}

sub getLeastPlayedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(track_statistics.rating) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id order by sumcount asc,avgrating asc,$orderBy limit $listLength";
    getArtistsWeb($sql,$params);
}

sub getLeastPlayedArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = getRandomString();
    my $sql = "select contributors.id,avg(track_statistics.rating) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id order by sumcount asc,avgrating asc,$orderBy limit $listLength";
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

		my( $url, $playCount, $lastPlayed, $rating );
		$sth->bind_columns( undef, \$url, \$playCount, \$lastPlayed, \$rating );
		my $itemNumber = 0;
		while( $sth->fetch() ) {
			$lastPlayed = 0 if (!(defined($lastPlayed)));
			$playCount = 0 if (!(defined($playCount)));
			$rating = 0 if (!(defined($rating)));
			my $track = $ds->objectForUrl($url);
		  	my %trackInfo = ();
			my $fieldInfo = Slim::DataStores::Base->fieldInfo;
            my $levelInfo = $fieldInfo->{'track'};
			
            &{$levelInfo->{'listItem'}}($ds, \%trackInfo, $track);
		  	$trackInfo{'title'} = Slim::Music::Info::standardTitle(undef,$track);
		  	$trackInfo{'lastPlayed'} = $lastPlayed;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
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

		my( $id, $rating, $playCount );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount );
		my $itemNumber = 0;
		while( $sth->fetch() ) {
			$playCount = 0 if (!(defined($playCount)));
			$rating = 0 if (!(defined($rating)));
			my $album = $ds->objectForId('album',$id);
		  	my %trackInfo = ();
			my $fieldInfo = Slim::DataStores::Base->fieldInfo;
            my $levelInfo = $fieldInfo->{'album'};
			
            &{$levelInfo->{'listItem'}}($ds, \%trackInfo, $album);
		  	$trackInfo{'title'} = undef;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
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
		my( $id, $rating, $playCount );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount );
		my @albums;
		while( scalar(@result)<=1 && $sth->fetch() ) {
			push @albums, $id;
		}
		fisher_yates_shuffle(\@albums);
		$id = shift @albums;
		my $album = $ds->objectForId('album',$id);
		debugMsg("Getting tracks for album: ".$album->title."\n");
		my $iterator = $album->tracks;
		for my $item ($iterator->slice(0,$iterator->count)) {
			push @result, $item;
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

		my( $id, $rating, $playCount );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount );
		my $itemNumber = 0;
		while( $sth->fetch() ) {
			$playCount = 0 if (!(defined($playCount)));
			$rating = 0 if (!(defined($rating)));
			my $artist = $ds->objectForId('artist',$id);
		  	my %trackInfo = ();
			my $fieldInfo = Slim::DataStores::Base->fieldInfo;
            my $levelInfo = $fieldInfo->{'artist'};
			
            &{$levelInfo->{'listItem'}}($ds, \%trackInfo, $artist);
		  	$trackInfo{'title'} = undef;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
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
		my( $id, $rating, $playCount );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount );
		my @artists;
		while( scalar(@result)<=1 && $sth->fetch() ) {
			push @artists, $id;
		}
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
			debugMsg("Got ".scalar(@result)." tracks\n");
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
	debugMsg("Returning ".scalar(@result)." tracks\n");
	return \@result;
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
