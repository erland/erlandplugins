#         TrackStat::Statistics::MostPlayedRecentAdded module
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
                   
package Plugins::TrackStat::Statistics::MostPlayedRecentAdded;

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
    
    if($driver eq 'mysql') {
    	$distinct = 'distinct';
    }
}

sub getStatisticItems {
	my %statistics = (
		mostplayedrecentadded => {
			'webfunction' => \&getMostPlayedRecentAddedTracksWeb,
			'playlistfunction' => \&getMostPlayedRecentAddedTracks,
			'id' =>  'mostplayedrecentadded',
			'namefunction' => \&getMostPlayedRecentAddedTracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isMostPlayedRecentAddedTracksValidInContext
		},
		mostplayedrecentaddedartists => {
			'webfunction' => \&getMostPlayedRecentAddedArtistsWeb,
			'playlistfunction' => \&getMostPlayedRecentAddedArtistTracks,
			'id' =>  'mostplayedrecentaddedartists',
			'namefunction' => \&getMostPlayedRecentAddedArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isMostPlayedRecentAddedArtistsValidInContext
		},
		mostplayedrecentaddedalbums => {
			'webfunction' => \&getMostPlayedRecentAddedAlbumsWeb,
			'playlistfunction' => \&getMostPlayedRecentAddedAlbumTracks,
			'id' =>  'mostplayedrecentaddedalbums',
			'namefunction' => \&getMostPlayedRecentAddedAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isMostPlayedRecentAddedAlbumsValidInContext
		},
		mostplayednotrecentadded => {
			'webfunction' => \&getMostPlayedNotRecentAddedTracksWeb,
			'playlistfunction' => \&getMostPlayedNotRecentAddedTracks,
			'id' =>  'mostplayednotrecentadded',
			'namefunction' => \&getMostPlayedNotRecentAddedTracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isMostPlayedNotRecentAddedTracksValidInContext
		},
		mostplayednotrecentaddedartists => {
			'webfunction' => \&getMostPlayedNotRecentAddedArtistsWeb,
			'playlistfunction' => \&getMostPlayedNotRecentAddedArtistTracks,
			'id' =>  'mostplayednotrecentaddedartists',
			'namefunction' => \&getMostPlayedNotRecentAddedArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isMostPlayedNotRecentAddedArtistsValidInContext
		},
		mostplayednotrecentaddedalbums => {
			'webfunction' => \&getMostPlayedNotRecentAddedAlbumsWeb,
			'playlistfunction' => \&getMostPlayedNotRecentAddedAlbumTracks,
			'id' =>  'mostplayednotrecentaddedalbums',
			'namefunction' => \&getMostPlayedNotRecentAddedAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isMostPlayedNotRecentAddedAlbumsValidInContext
		}
	);
	return \%statistics;
}

sub getMostPlayedRecentAddedTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_FORYEAR')." ".$params->{'year'};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED');
	}
}

sub isMostPlayedRecentAddedTracksValidInContext {
	my $params = shift;
	if(defined($params->{'artist'})) {
		return 1;
	}elsif(defined($params->{'album'})) {
		return 1;
	}elsif(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}elsif(defined($params->{'playlist'})) {
		return 1;
	}
	return 0;
}

sub getMostPlayedRecentAddedTracksWeb {
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
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist and contributor_track.role in (1,4,5,6) left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded group by tracks.url order by track_statistics.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'album'})) {
		my $album = $params->{'album'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and tracks.album=$album and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount desc,$orderBy;";
	    $params->{'statisticparameters'} = "&album=$album";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and tracks.year=$year and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount desc,$orderBy limit $listLength;";
	}
    Plugins::TrackStat::Statistics::Base::getTracksWeb($sql,$params);
    if($recentaddedcmp eq '>') {
	    my %currentstatisticlinks = (
	    	'album' => 'mostplayedrecentadded',
	    	'artist' => 'mostplayedrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}else {
	    my %currentstatisticlinks = (
	    	'album' => 'mostplayednotrecentadded',
	    	'artist' => 'mostplayednotrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}
}

sub getMostPlayedRecentAddedTracks {
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
		$sql = "select tracks.id from tracks left join track_statistics on tracks.url = track_statistics.url left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where tracks.audio=1 and dynamicplaylist_history.id is null and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount desc,$orderBy limit $listLength;";
	}else {
		$sql = "select tracks.id from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.playCount desc,$orderBy limit $listLength;";
	}
    return Plugins::TrackStat::Statistics::Base::getTracks($sql,$limit);
}

sub getMostPlayedRecentAddedAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDEDALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDEDALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDEDALBUMS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDEDALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDEDALBUMS');
	}
}

sub isMostPlayedRecentAddedAlbumsValidInContext {
	my $params = shift;
	if(defined($params->{'artist'})) {
		return 1;
	}elsif(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}elsif(defined($params->{'playlist'})) {
		return 1;
	}
	return 0;
}

sub getMostPlayedRecentAddedAlbumsWeb {
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
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist and contributor_track.role in (1,4,5,6) left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount desc,avgrating desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount desc,avgrating desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where tracks.year=$year group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount desc,avgrating desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount desc,avgrating desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount desc,avgrating desc,$orderBy limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
    if($recentaddedcmp eq '>') {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'mostplayedrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_FORALBUM_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'album' => 'mostplayedrecentadded',
	    	'artist' => 'mostplayedrecentaddedalbums',
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}else {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'mostplayednotrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_FORALBUM_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'album' => 'mostplayednotrecentadded',
	    	'artist' => 'mostplayednotrecentaddedalbums',
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}
}

sub getMostPlayedRecentAddedAlbumTracks {
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
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount desc,avgrating desc,$orderBy limit $listLength";
	}else {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgcount desc,avgrating desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($sql,$limit);
}

sub getMostPlayedRecentAddedArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDEDARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDEDARTISTS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDEDARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDEDARTISTS');
	}
}

sub isMostPlayedRecentAddedArtistsValidInContext {
	my $params = shift;
	if(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}elsif(defined($params->{'playlist'})) {
		return 1;
	}
	return 0;
}


sub getMostPlayedRecentAddedArtistsWeb {
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
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount desc,avgrating desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor where tracks.year=$year group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount desc,avgrating desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
    }elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount desc,avgrating desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount desc,avgrating desc,$orderBy limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
    if($recentaddedcmp eq '>') {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'mostplayedrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDED_FORARTIST_SHORT')
	    };
	    push @statisticlinks, {
	    	'id' => 'mostplayedrecentaddedalbums',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTADDEDALBUMS_FORARTIST_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'artist' => 'mostplayedrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}else {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'mostplayednotrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_FORARTIST_SHORT')
	    };
	    push @statisticlinks, {
	    	'id' => 'mostplayednotrecentaddedalbums',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDEDALBUMS_FORARTIST_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'artist' => 'mostplayednotrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}
}

sub getMostPlayedRecentAddedArtistTracks {
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
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount desc,avgrating desc,$orderBy limit $listLength";
	}else {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by sumcount desc,avgrating desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getArtistTracks($sql,$limit);
}


sub getMostPlayedNotRecentAddedTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED_FORYEAR')." ".$params->{'year'};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDED');
	}
}

sub isMostPlayedNotRecentAddedTracksValidInContext {
	my $params = shift;
	if(defined($params->{'artist'})) {
		return 1;
	}elsif(defined($params->{'album'})) {
		return 1;
	}elsif(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}elsif(defined($params->{'playlist'})) {
		return 1;
	}
	return 0;
}

sub getMostPlayedNotRecentAddedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedRecentAddedTracksWeb($params,$listLength,'<');
}

sub getMostPlayedNotRecentAddedTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedRecentAddedTracks($listLength,$limit,'<');
}

sub getMostPlayedNotRecentAddedAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDEDALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDEDALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDEDALBUMS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDEDALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDEDALBUMS');
	}
}

sub isMostPlayedNotRecentAddedAlbumsValidInContext {
	my $params = shift;
	if(defined($params->{'artist'})) {
		return 1;
	}elsif(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}elsif(defined($params->{'playlist'})) {
		return 1;
	}
	return 0;
}

sub getMostPlayedNotRecentAddedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedRecentAddedAlbumsWeb($params,$listLength,'<');
}

sub getMostPlayedNotRecentAddedAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedRecentAddedAlbumTracks($listLength,$limit,'<');
}

sub getMostPlayedNotRecentAddedArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDEDARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDEDARTISTS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDEDARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTADDEDARTISTS');
	}
}

sub isMostPlayedNotRecentAddedArtistsValidInContext {
	my $params = shift;
	if(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}elsif(defined($params->{'playlist'})) {
		return 1;
	}
	return 0;
}


sub getMostPlayedNotRecentAddedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedRecentAddedArtistsWeb($params,$listLength,'<');
}

sub getMostPlayedNotRecentAddedArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedRecentAddedArtistTracks($listLength,$limit,'<');
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
