#         TrackStat::Statistics::LeastPlayedRecentAdded module
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
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
                   
package Plugins::TrackStat::Statistics::LeastPlayedRecentAdded;

use Date::Parse qw(str2time);
use Fcntl ':flock'; # import LOCK_* constants
use File::Spec::Functions qw(:ALL);
use File::Basename;
use XML::Parser;
use DBI qw(:sql_types);
use Class::Struct;
use FindBin qw($Bin);
use POSIX qw(strftime ceil);
use Slim::Utils::Strings qw(string);
use Plugins::TrackStat::Statistics::Base;
use Slim::Utils::Prefs;

my $prefs = preferences("plugin.trackstat");
my $serverPrefs = preferences("server");


if ($] > 5.007) {
	require Encode;
}

my $driver;
my $distinct = '';

sub init {
	$driver = $serverPrefs->get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
	if(UNIVERSAL::can("Slim::Schema","sourceInformation")) {
		my ($source,$username,$password);
		($driver,$source,$username,$password) = Slim::Schema->sourceInformation;
	}

    if($driver eq 'mysql') {
    	$distinct = 'distinct';
    }
}

sub getStatisticItems {
	my %statistics = (
		leastplayedrecentadded => {
			'webfunction' => \&getLeastPlayedRecentAddedTracksWeb,
			'playlistfunction' => \&getLeastPlayedRecentAddedTracks,
			'id' =>  'leastplayedrecentadded',
			'namefunction' => \&getLeastPlayedRecentAddedTracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isLeastPlayedRecentAddedTracksValidInContext
		},
		leastplayedrecentaddedartists => {
			'webfunction' => \&getLeastPlayedRecentAddedArtistsWeb,
			'playlistfunction' => \&getLeastPlayedRecentAddedArtistTracks,
			'id' =>  'leastplayedrecentaddedartists',
			'namefunction' => \&getLeastPlayedRecentAddedArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isLeastPlayedRecentAddedArtistsValidInContext
		},
		leastplayedrecentaddedalbums => {
			'webfunction' => \&getLeastPlayedRecentAddedAlbumsWeb,
			'playlistfunction' => \&getLeastPlayedRecentAddedAlbumTracks,
			'id' =>  'leastplayedrecentaddedalbums',
			'namefunction' => \&getLeastPlayedRecentAddedAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isLeastPlayedRecentAddedAlbumsValidInContext
		},
		leastplayednotrecentadded => {
			'webfunction' => \&getLeastPlayedNotRecentAddedTracksWeb,
			'playlistfunction' => \&getLeastPlayedNotRecentAddedTracks,
			'id' =>  'leastplayednotrecentadded',
			'namefunction' => \&getLeastPlayedNotRecentAddedTracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isLeastPlayedNotRecentAddedTracksValidInContext
		},
		leastplayednotrecentaddedartists => {
			'webfunction' => \&getLeastPlayedNotRecentAddedArtistsWeb,
			'playlistfunction' => \&getLeastPlayedNotRecentAddedArtistTracks,
			'id' =>  'leastplayednotrecentaddedartists',
			'namefunction' => \&getLeastPlayedNotRecentAddedArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isLeastPlayedNotRecentAddedArtistsValidInContext
		},
		leastplayednotrecentaddedalbums => {
			'webfunction' => \&getLeastPlayedNotRecentAddedAlbumsWeb,
			'playlistfunction' => \&getLeastPlayedNotRecentAddedAlbumTracks,
			'id' =>  'leastplayednotrecentaddedalbums',
			'namefunction' => \&getLeastPlayedNotRecentAddedAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isLeastPlayedNotRecentAddedAlbumsValidInContext
		}
	);
	return \%statistics;
}

sub getLeastPlayedRecentAddedTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORYEAR')." ".$year;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED');
	}
}

sub isLeastPlayedRecentAddedTracksValidInContext {
	my $params = shift;
	if(defined($params->{'artist'})) {
		return 1;
	}elsif(defined($params->{'album'})) {
		return 1;
	}elsif(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}
	return 0;
}

sub getLeastPlayedRecentAddedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $recentadded = getRecentAddedTime();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist and contributor_track.role in (1,4,5,6) left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded group by tracks.url order by track_statistics.playCount asc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'album'})) {
		my $album = $params->{'album'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and tracks.album=$album and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount asc,$orderBy;";
	    $params->{'statisticparameters'} = "&album=$album";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount asc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.year=$year and tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount asc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&year=$year";
	}else {
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount asc,$orderBy limit $listLength;";
	}
    Plugins::TrackStat::Statistics::Base::getTracksWeb($sql,$params);
    if($recentaddedcmp eq '>') {
	    my %currentstatisticlinks = (
	    	'album' => 'leastplayedrecentadded',
	    	'artist' => 'leastplayedrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}else {
	    my %currentstatisticlinks = (
	    	'album' => 'leastplayednotrecentadded',
	    	'artist' => 'leastplayednotrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}
}

sub getLeastPlayedRecentAddedTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = shift;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $recentadded = getRecentAddedTime();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		my $clientid = $client->id;
		$sql = "select tracks.id from tracks left join track_statistics on tracks.url = track_statistics.url left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id and dynamicplaylist_history.client='$clientid' where tracks.audio=1 and dynamicplaylist_history.id is null and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount asc,$orderBy limit $listLength;";
	}else {
		$sql = "select tracks.id from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount asc,$orderBy limit $listLength;";
	}
    return Plugins::TrackStat::Statistics::Base::getTracks($sql,$limit);
}

sub getLeastPlayedRecentAddedAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDALBUMS_FORYEAR')." ".$year;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDALBUMS');
	}
}

sub isLeastPlayedRecentAddedAlbumsValidInContext {
	my $params = shift;
	if(defined($params->{'artist'})) {
		return 1;
	}elsif(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}
	return 0;
}

sub getLeastPlayedRecentAddedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $recentadded = getRecentAddedTime();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist and contributor_track.role in (1,4,5,6) left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount asc,avgrating asc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount asc,avgrating asc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where tracks.year=$year group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount asc,avgrating asc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
	}else {
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount asc,avgrating asc,$orderBy limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
    if($recentaddedcmp eq '>') {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'leastplayedrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORALBUM_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'album' => 'leastplayedrecentadded',
	    	'artist' => 'leastplayedrecentaddedalbums',
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}else {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'leastplayednotrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORALBUM_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'album' => 'leastplayednotrecentadded',
	    	'artist' => 'leastplayednotrecentaddedalbums',
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}
}

sub getLeastPlayedRecentAddedAlbumTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = shift;
	$limit = undef;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $recentadded = getRecentAddedTime();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		my $clientid = $client->id;
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id and dynamicplaylist_history.client='$clientid' where dynamicplaylist_history.id is null group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount asc,avgrating asc,$orderBy limit $listLength";
	}else {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount asc,avgrating asc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($client,$sql,$limit);
}

sub getLeastPlayedRecentAddedArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDARTISTS_FORYEAR')." ".$year;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDARTISTS');
	}
}

sub isLeastPlayedRecentAddedArtistsValidInContext {
	my $params = shift;
	if(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}
	return 0;
}

sub getLeastPlayedRecentAddedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $recentadded = getRecentAddedTime();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount asc,avgrating asc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor where tracks.year=$year group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount asc,avgrating asc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
	}else {
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount asc,avgrating asc,$orderBy limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
    if($recentaddedcmp eq '>') {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'leastplayedrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDED_FORARTIST_SHORT')
	    };
	    push @statisticlinks, {
	    	'id' => 'leastplayedrecentaddedalbums',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDRECENTADDEDALBUMS_FORARTIST_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'artist' => 'leastplayedrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}else {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'leastplayednotrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORARTIST_SHORT')
	    };
	    push @statisticlinks, {
	    	'id' => 'leastplayednotrecentaddedalbums',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDALBUMS_FORARTIST_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'artist' => 'leastplayednotrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}
}

sub getLeastPlayedRecentAddedArtistTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = shift;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $recentadded = getRecentAddedTime();
	$limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		my $clientid = $client->id;
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id and dynamicplaylist_history.client='$clientid' where dynamicplaylist_history.id is null group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount asc,avgrating asc,$orderBy limit $listLength";
	}else {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount asc,avgrating asc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getArtistTracks($client,$sql,$limit);
}

sub getLeastPlayedNotRecentAddedTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED_FORYEAR')." ".$year;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDED');
	}
}

sub isLeastPlayedNotRecentAddedTracksValidInContext {
	my $params = shift;
	if(defined($params->{'artist'})) {
		return 1;
	}elsif(defined($params->{'album'})) {
		return 1;
	}elsif(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}
	return 0;
}

sub getLeastPlayedNotRecentAddedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	getLeastPlayedRecentAddedTracksWeb($params,$listLength,'<');
}

sub getLeastPlayedNotRecentAddedTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = shift;
	return getLeastPlayedRecentAddedTracks($client,$listLength,$limit,'<');
}

sub getLeastPlayedNotRecentAddedAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDALBUMS_FORYEAR')." ".$year;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDALBUMS');
	}
}

sub isLeastPlayedNotRecentAddedAlbumsValidInContext {
	my $params = shift;
	if(defined($params->{'artist'})) {
		return 1;
	}elsif(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}
	return 0;
}

sub getLeastPlayedNotRecentAddedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getLeastPlayedRecentAddedAlbumsWeb($params,$listLength,'<');
}

sub getLeastPlayedNotRecentAddedAlbumTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = shift;
	return getLeastPlayedRecentAddedAlbumTracks($client,$listLength,$limit,'<');
}

sub getLeastPlayedNotRecentAddedArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDARTISTS_FORYEAR')." ".$year;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDNOTRECENTADDEDARTISTS');
	}
}

sub isLeastPlayedNotRecentAddedArtistsValidInContext {
	my $params = shift;
	if(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}
	return 0;
}

sub getLeastPlayedNotRecentAddedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getLeastPlayedRecentAddedArtistsWeb($params,$listLength,'<');
}

sub getLeastPlayedNotRecentAddedArtistTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = shift;
	return getLeastPlayedRecentAddedArtistTracks($client,$listLength,$limit,'<');
}

sub getRecentAddedTime() {
	my $days = $prefs->get("recentadded_number_of_days");
	if(!defined($days)) {
		$days = 30;
	}
	return time() - 24*3600*$days;
}


1;

__END__
