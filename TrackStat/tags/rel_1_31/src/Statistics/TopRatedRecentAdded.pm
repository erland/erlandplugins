#         TrackStat::Statistics::TopRatedRecentAdded module
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
                   
package Plugins::TrackStat::Statistics::TopRatedRecentAdded;

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

if ($] > 5.007) {
	require Encode;
}

my $driver;
my $distinct = '';

sub init {
	$driver = Slim::Utils::Prefs::get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
    if($driver eq 'mysql') {
    	$distinct = 'distinct';
    }
}

sub getStatisticItems {
	my %statistics = (
		topratedrecentadded => {
			'webfunction' => \&getTopRatedRecentAddedTracksWeb,
			'playlistfunction' => \&getTopRatedRecentAddedTracks,
			'id' =>  'topratedrecentadded',
			'namefunction' => \&getTopRatedRecentAddedTracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isTopRatedRecentAddedTracksValidInContext
		},
		topratedrecentaddedartists => {
			'webfunction' => \&getTopRatedRecentAddedArtistsWeb,
			'playlistfunction' => \&getTopRatedRecentAddedArtistTracks,
			'id' =>  'topratedrecentaddedartists',
			'namefunction' => \&getTopRatedRecentAddedArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isTopRatedRecentAddedArtistsValidInContext
		},
		topratedrecentaddedalbums => {
			'webfunction' => \&getTopRatedRecentAddedAlbumsWeb,
			'playlistfunction' => \&getTopRatedRecentAddedAlbumTracks,
			'id' =>  'topratedrecentaddedalbums',
			'namefunction' => \&getTopRatedRecentAddedAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isTopRatedRecentAddedAlbumsValidInContext
		},
		topratednotrecentadded => {
			'webfunction' => \&getTopRatedNotRecentAddedTracksWeb,
			'playlistfunction' => \&getTopRatedNotRecentAddedTracks,
			'id' =>  'topratednotrecentadded',
			'namefunction' => \&getTopRatedNotRecentAddedTracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isTopRatedNotRecentAddedTracksValidInContext
		},
		topratednotrecentaddedartists => {
			'webfunction' => \&getTopRatedNotRecentAddedArtistsWeb,
			'playlistfunction' => \&getTopRatedNotRecentAddedArtistTracks,
			'id' =>  'topratednotrecentaddedartists',
			'namefunction' => \&getTopRatedNotRecentAddedArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isTopRatedNotRecentAddedArtistsValidInContext
		},
		topratednotrecentaddedalbums => {
			'webfunction' => \&getTopRatedNotRecentAddedAlbumsWeb,
			'playlistfunction' => \&getTopRatedNotRecentAddedAlbumTracks,
			'id' =>  'topratednotrecentaddedalbums',
			'namefunction' => \&getTopRatedNotRecentAddedAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isTopRatedNotRecentAddedAlbumsValidInContext
		}
	);
	return \%statistics;
}

sub getTopRatedRecentAddedTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_FORYEAR')." ".$params->{'year'};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED');
	}
}

sub isTopRatedRecentAddedTracksValidInContext {
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

sub getTopRatedRecentAddedTracksWeb {
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
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded group by tracks.url order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'album'})) {
		my $album = $params->{'album'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and tracks.album=$album and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy;";
	    $params->{'statisticparameters'} = "&album=$album";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and tracks.year=$year and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	}
    Plugins::TrackStat::Statistics::Base::getTracksWeb($sql,$params);
    if($recentaddedcmp eq '>') {
	    my %currentstatisticlinks = (
	    	'album' => 'topratedrecentadded',
	    	'artist' => 'topratedrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}else {
	    my %currentstatisticlinks = (
	    	'album' => 'topratednotrecentadded',
	    	'artist' => 'topratednotrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}
}

sub getTopRatedRecentAddedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $recentadded = getRecentAddedTime();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist_norepeat")) {
		$sql = "select tracks.id from tracks left join track_statistics on tracks.url = track_statistics.url left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where tracks.audio=1 and dynamicplaylist_history.id is null and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	}else {
		$sql = "select tracks.id from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.added$recentaddedcmp$recentadded order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	}
    return Plugins::TrackStat::Statistics::Base::getTracks($sql,$limit);
}

sub getTopRatedRecentAddedAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDALBUMS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDALBUMS');
	}
}

sub isTopRatedRecentAddedAlbumsValidInContext {
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

sub getTopRatedRecentAddedAlbumsWeb {
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
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where tracks.year=$year group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
    if($recentaddedcmp eq '>') {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'topratedrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_FORALBUM_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'album' => 'topratedrecentadded'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}else {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'topratednotrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_FORALBUM_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'album' => 'topratednotrecentadded'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}
}

sub getTopRatedRecentAddedAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	$limit=undef;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $recentadded = getRecentAddedTime();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist_norepeat")) {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	}else {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.added)$recentaddedcmp$recentadded order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($sql,$limit);
}

sub getTopRatedRecentAddedArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDARTISTS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDARTISTS');
	}
}

sub isTopRatedRecentAddedArtistsValidInContext {
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


sub getTopRatedRecentAddedArtistsWeb {
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
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor where tracks.year=$year group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
    }elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
    if($recentaddedcmp eq '>') {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'topratedrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_FORARTIST_SHORT')
	    };
	    push @statisticlinks, {
	    	'id' => 'topratedrecentaddedalbums',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDALBUMS_FORARTIST_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'artist' => 'topratedrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}else {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'topratednotrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_FORARTIST_SHORT')
	    };
	    push @statisticlinks, {
	    	'id' => 'topratednotrecentaddedalbums',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDALBUMS_FORARTIST_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'artist' => 'topratednotrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}
}

sub getTopRatedRecentAddedArtistTracks {
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
	if(Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist_norepeat")) {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	}else {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.added)$recentaddedcmp$recentadded order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getArtistTracks($sql,$limit);
}


sub getTopRatedNotRecentAddedTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_FORYEAR')." ".$params->{'year'};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED');
	}
}

sub isTopRatedNotRecentAddedTracksValidInContext {
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

sub getTopRatedNotRecentAddedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	getTopRatedRecentAddedTracksWeb($params,$listLength,'<');
}

sub getTopRatedNotRecentAddedTracks {
	my $listLength = shift;
	my $limit = shift;
	return getTopRatedRecentAddedTracks($listLength,$limit,'<');
}

sub getTopRatedNotRecentAddedAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDALBUMS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDALBUMS');
	}
}

sub isTopRatedNotRecentAddedAlbumsValidInContext {
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

sub getTopRatedNotRecentAddedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getTopRatedRecentAddedAlbumsWeb($params,$listLength,'<');
}

sub getTopRatedNotRecentAddedAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	return getTopRatedRecentAddedAlbumTracks($listLength,$limit,'<');
}

sub getTopRatedNotRecentAddedArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDARTISTS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDARTISTS');
	}
}

sub isTopRatedNotRecentAddedArtistsValidInContext {
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


sub getTopRatedNotRecentAddedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getTopRatedRecentAddedArtistsWeb($params,$listLength,'<');
}

sub getTopRatedNotRecentAddedArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	return getTopRatedRecentAddedArtistTracks($listLength,$limit,'<');
}

sub getRecentAddedTime() {
	my $days = Slim::Utils::Prefs::get("plugin_trackstat_recentadded_number_of_days");
	if(!defined($days)) {
		$days = 30;
	}
	return time() - 24*3600*$days;
}


sub strings()
{
	return "
PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED
	EN	Top rated songs recently added

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_FORARTIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_FORARTIST
	EN	Top rated songs recently added by: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_FORALBUM_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_FORALBUM
	EN	Top rated songs recently added from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_FORGENRE_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_FORGENRE
	EN	Top rated songs recently added in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_FORYEAR_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_FORYEAR
	EN	Top rated songs recently added from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_FORPLAYLIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_FORPLAYLIST
	EN	Top rated songs recently added in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDALBUMS
	EN	Top rated albums recently added

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDALBUMS_FORARTIST
	EN	Top rated albums recently added by: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDALBUMS_FORGENRE_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDALBUMS_FORGENRE
	EN	Top rated albums recently added in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDALBUMS_FORYEAR_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDALBUMS_FORYEAR
	EN	Top rated albums recently added from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDALBUMS_FORPLAYLIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDALBUMS_FORPLAYLIST
	EN	Top rated albums recently added in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDARTISTS
	EN	Top rated artists recently added

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDARTISTS_FORGENRE_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDARTISTS_FORGENRE
	EN	Top rated artists recently added in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDARTISTS_FORYEAR_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDARTISTS_FORYEAR
	EN	Top rated artists recently added from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDARTISTS_FORPLAYLIST_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDEDARTISTS_FORPLAYLIST
	EN	Top rated artists recently added in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED
	EN	Top rated songs not recently added

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_FORARTIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_FORARTIST
	EN	Top rated songs not recently added by: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_FORALBUM_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_FORALBUM
	EN	Top rated songs not recently added from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_FORGENRE_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_FORGENRE
	EN	Top rated songs not recently added in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_FORYEAR_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_FORYEAR
	EN	Top rated songs not recently added from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_FORPLAYLIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_FORPLAYLIST
	EN	Top rated songs not recently added in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDALBUMS
	EN	Top rated albums not recently added

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDALBUMS_FORARTIST
	EN	Top rated albums not recently added by: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDALBUMS_FORGENRE_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDALBUMS_FORGENRE
	EN	Top rated albums not recently added in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDALBUMS_FORYEAR_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDALBUMS_FORYEAR
	EN	Top rated albums not recently added from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDALBUMS_FORPLAYLIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDALBUMS_FORPLAYLIST
	EN	Top rated albums not recently added in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDARTISTS
	EN	Top rated artists not recently added

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDARTISTS_FORGENRE_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDARTISTS_FORGENRE
	EN	Top rated artists not recently added in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDARTISTS_FORYEAR_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDARTISTS_FORYEAR
	EN	Top rated artists not recently added from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDARTISTS_FORPLAYLIST_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDEDARTISTS_FORPLAYLIST
	EN	Top rated artists not recently added in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_GROUP
	EN	Top rated

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTADDED_GROUP
	EN	Top rated
";
}

1;

__END__
