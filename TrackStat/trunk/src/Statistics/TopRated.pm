#         TrackStat::Statistics::TopRated module
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
                   
package Plugins::TrackStat::Statistics::TopRated;

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
		toprated => {
			'webfunction' => \&getTopRatedTracksWeb,
			'playlistfunction' => \&getTopRatedTracks,
			'id' =>  'toprated',
			'namefunction' => \&getTopRatedTracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isTopRatedTracksValidInContext,
			'playlisttemplates' => ['toprated']
		},
		topratedartists => {
			'webfunction' => \&getTopRatedArtistsWeb,
			'playlistfunction' => \&getTopRatedArtistTracks,
			'id' =>  'topratedartists',
			'namefunction' => \&getTopRatedArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isTopRatedArtistsValidInContext,
			'playlisttemplates' => ['topratedartists']
		},
		topratedalbums => {
			'webfunction' => \&getTopRatedAlbumsWeb,
			'playlistfunction' => \&getTopRatedAlbumTracks,
			'id' =>  'topratedalbums',
			'namefunction' => \&getTopRatedAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isTopRatedAlbumsValidInContext,
			'playlisttemplates' => ['topratedalbums']
		},
		topratedgenres => {
			'webfunction' => \&getTopRatedGenresWeb,
			'playlistfunction' => \&getTopRatedGenreTracks,
			'id' =>  'topratedgenres',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDGENRES'),
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_GENRE_GROUP')]],
			'contextfunction' => \&isTopRatedGenresValidInContext,
			'playlisttemplates' => ['topratedgenres']
		},
		topratedyears => {
			'webfunction' => \&getTopRatedYearsWeb,
			'playlistfunction' => \&getTopRatedYearTracks,
			'id' =>  'topratedyears',
			'namefunction' => \&getTopRatedYearsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_YEAR_GROUP')]],
			'contextfunction' => \&isTopRatedYearsValidInContext,
			'playlisttemplates' => ['topratedyears']
		},
		topratedplaylists => {
			'webfunction' => \&getTopRatedPlaylistsWeb,
			'playlistfunction' => \&getTopRatedPlaylistTracks,
			'id' =>  'topratedplaylists',
			'namefunction' => \&getTopRatedPlaylistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_PLAYLIST_GROUP')]],
			'contextfunction' => \&isTopRatedPlaylistsValidInContext,
			'playlisttemplates' => ['topratedplaylists']
		}

	);
	return \%statistics;
}

sub getTopRatedTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORYEAR')." ".$params->{'year'};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED');
	}
}

sub isTopRatedTracksValidInContext {
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

sub getTopRatedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 group by tracks.url order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'album'})) {
		my $album = $params->{'album'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and tracks.album=$album order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy;";
	    $params->{'statisticparameters'} = "&album=$album";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and tracks.year=$year order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	}
    Plugins::TrackStat::Statistics::Base::getTracksWeb($sql,$params);
    my %currentstatisticlinks = (
    	'album' => 'toprated',
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getTopRatedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist_norepeat")) {
		$sql = "select tracks.id from tracks left join track_statistics on tracks.url = track_statistics.url left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where tracks.audio=1 and dynamicplaylist_history.id is null order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	}else {
		$sql = "select tracks.id from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	}
    return Plugins::TrackStat::Statistics::Base::getTracks($sql,$limit);
}

sub getTopRatedAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS');
	}
}

sub isTopRatedAlbumsValidInContext {
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

sub getTopRatedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	my $minalbumtext = "";
	my $minalbumlimit = Slim::Utils::Prefs::get("plugin_trackstat_min_album_tracks");
	if($minalbumlimit && $minalbumlimit>0) {
		$minalbumtext = "having count(tracks.id)>=".$minalbumlimit." ";
	}
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album $minalbumtext order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where tracks.year=$year group by tracks.album $minalbumtext order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album $minalbumtext order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'toprated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'album' => 'toprated'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getTopRatedAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $minalbumtext = "";
	my $minalbumlimit = Slim::Utils::Prefs::get("plugin_trackstat_min_album_tracks");
	if($minalbumlimit && $minalbumlimit>0) {
		$minalbumtext = "having count(tracks.id)>=".$minalbumlimit." ";
	}
	my $sql;
	if(Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist_norepeat")) {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by tracks.album $minalbumtext order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	}else {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album $minalbumtext order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($sql,$limit);
}

sub getTopRatedArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDARTISTS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDARTISTS');
	}
}

sub isTopRatedArtistsValidInContext {
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


sub getTopRatedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	my $minartisttext = "";
	my $minartistlimit = Slim::Utils::Prefs::get("plugin_trackstat_min_artist_tracks");
	if($minartistlimit && $minartistlimit>0) {
		$minartisttext = "having count(tracks.id)>=".$minartistlimit." ";
	}
    if(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id $minartisttext order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor where tracks.year=$year group by contributors.id $minartisttext order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
    }elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id $minartisttext order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'toprated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'topratedalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'topratedyears',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDYEARS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getTopRatedArtistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $minartisttext = "";
	my $minartistlimit = Slim::Utils::Prefs::get("plugin_trackstat_min_artist_tracks");
	if($minartistlimit && $minartistlimit>0) {
		$minartisttext = "having count(tracks.id)>=".$minartistlimit." ";
	}
	my $sql;
	if(Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist_norepeat")) {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by contributors.id $minartisttext order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	}else {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id $minartisttext order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getArtistTracks($sql,$limit);
}

sub isTopRatedGenresValidInContext {
	my $params = shift;
	return 0;
}


sub getTopRatedGenresWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select genres.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join genre_track on tracks.id=genre_track.track join genres on genres.id = genre_track.genre group by genres.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    Plugins::TrackStat::Statistics::Base::getGenresWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'toprated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORGENRE_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'topratedalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORGENRE_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'topratedartists',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDARTISTS_FORGENRE_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'genre' => 'topratedartists'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getTopRatedGenreTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist_norepeat")) {
		$sql = "select genres.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join genre_track on tracks.id=genre_track.track join genres on genres.id = genre_track.genre left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by genres.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	}else {
		$sql = "select genres.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join genre_track on tracks.id=genre_track.track join genres on genres.id = genre_track.genre group by genres.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getGenreTracks($sql,$limit);
}

sub getTopRatedYearsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDYEARS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDYEARS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDYEARS');
	}
}

sub isTopRatedYearsValidInContext {
	my $params = shift;
	if(defined($params->{'artist'})) {
		return 1;
	}elsif(defined($params->{'genre'})) {
		return 1;
	}
	return 0;
}


sub getTopRatedYearsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select year,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url group by year having year>0 order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select year,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url group by year having year>0 order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}else {
	    $sql = "select year,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url group by year having year>0 order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getYearsWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'toprated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORYEAR_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'topratedalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORYEAR_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'topratedartists',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDARTISTS_FORYEAR_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'year' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getTopRatedYearTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist_norepeat")) {
		$sql = "select year,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by year having year>0 order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	}else {
		$sql = "select year,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url group by year having year>0 order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getYearTracks($sql,$limit);
}

sub getTopRatedPlaylistsName {
	my $params = shift;
	return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDPLAYLISTS');
}

sub isTopRatedPlaylistsValidInContext {
	my $params = shift;
	return 0;
}

sub getTopRatedPlaylistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select playlist_track.playlist,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join playlist_track on tracks.id=playlist_track.track group by playlist_track.playlist order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    Plugins::TrackStat::Statistics::Base::getPlaylistsWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'toprated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORYEAR_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'topratedalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORYEAR_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'topratedartists',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDARTISTS_FORYEAR_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'playlist' => 'toprated'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getTopRatedPlaylistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist_norepeat")) {
		$sql = "select playlist_track.playlist,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join playlist_track on tracks.id=playlist_track.track left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by playlist_track.playlist order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	}else {
		$sql = "select playlist_track.playlist,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join playlist_track on tracks.id=playlist_track.track group by playlist_track.playlist order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getPlaylistTracks($sql,$limit);
}

sub strings()
{
	return "
PLUGIN_TRACKSTAT_SONGLIST_TOPRATED
	EN	Top rated songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORARTIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORARTIST
	EN	Top rated songs by: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORALBUM_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORALBUM
	EN	Top rated songs from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORGENRE_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORGENRE
	EN	Top rated songs in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORYEAR_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORYEAR
	EN	Top rated songs from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORPLAYLIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORPLAYLIST
	EN	Top rated songs in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS
	EN	Top rated albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORARTIST
	EN	Top rated albums by: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORGENRE_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORGENRE
	EN	Top rated albums in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORYEAR_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORYEAR
	EN	Top rated albums from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORPLAYLIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORPLAYLIST
	EN	Top rated albums in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDARTISTS
	EN	Top rated artists

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDARTISTS_FORGENRE_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDARTISTS_FORGENRE
	EN	Top rated artists in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDARTISTS_FORYEAR_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDARTISTS_FORYEAR
	EN	Top rated artists from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDARTISTS_FORPLAYLIST_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDARTISTS_FORPLAYLIST
	EN	Top rated artists in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDGENRES
	EN	Top rated genres

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDYEARS
	EN	Top rated years

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDYEARS_FORARTIST_SHORT
	EN	Years

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDYEARS_FORARTIST
	EN	Top rated years by: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDYEARS_FORGENRE_SHORT
	EN	Years

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDYEARS_FORGENRE
	EN	Top rated years in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDPLAYLISTS
	EN	Top rated playlists

PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_GROUP
	EN	Top rated
";
}

1;

__END__
