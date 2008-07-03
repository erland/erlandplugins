#         TrackStat::Statistics::All module
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
                   
package Plugins::TrackStat::Statistics::All;

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
		all => {
			'webfunction' => \&getAllTracksWeb,
			'playlistfunction' => \&getAllTracks,
			'id' =>  'all',
			'namefunction' => \&getAllTracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isAllTracksValidInContext
		},
		allartists => {
			'webfunction' => \&getAllArtistsWeb,
			'playlistfunction' => \&getAllArtistTracks,
			'id' =>  'allartists',
			'namefunction' => \&getAllArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isAllArtistsValidInContext
		},
		allalbums => {
			'webfunction' => \&getAllAlbumsWeb,
			'playlistfunction' => \&getAllAlbumTracks,
			'id' =>  'allalbums',
			'namefunction' => \&getAllAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isAllAlbumsValidInContext
		},
		allgenres => {
			'webfunction' => \&getAllGenresWeb,
			'playlistfunction' => \&getAllGenreTracks,
			'id' =>  'allgenres',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_ALLGENRES'),
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_GENRE_GROUP')]],
			'contextfunction' => \&isAllGenresValidInContext
		},
		allyears => {
			'webfunction' => \&getAllYearsWeb,
			'playlistfunction' => \&getAllYearTracks,
			'id' =>  'allyears',
			'namefunction' => \&getAllYearsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_YEAR_GROUP')]],
			'contextfunction' => \&isAllYearsValidInContext
		},
		allplaylists => {
			'webfunction' => \&getAllPlaylistsWeb,
			'playlistfunction' => \&getAllPlaylistTracks,
			'id' =>  'allplaylists',
			'namefunction' => \&getAllPlaylistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_PLAYLIST_GROUP')]],
			'contextfunction' => \&isAllPlaylistsValidInContext
		}
	);
	return \%statistics;
}

sub getAllTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_ALL_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_ALL_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_ALL_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_ALL_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_ALL_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_ALL');
	}
}

sub isAllTracksValidInContext {
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
sub getAllTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist and contributor_track.role in (1,4,5,6) left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 group by tracks.url order by tracks.album asc,tracks.disc asc,tracks.tracknum asc limit $listLength;";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'album'})) {
		my $album = $params->{'album'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and tracks.album=$album order by tracks.disc asc,tracks.tracknum";
	    $params->{'statisticparameters'} = "&album=$album";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by tracks.album asc,tracks.disc asc,tracks.tracknum asc limit $listLength;";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and tracks.year=$year order by tracks.album asc,tracks.disc asc,tracks.tracknum asc limit $listLength;";
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by playlist_track.position asc limit $listLength;";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by tracks.album asc,tracks.disc asc,tracks.tracknum asc limit $listLength;";
	}
    Plugins::TrackStat::Statistics::Base::getTracksWeb($sql,$params);
    my %currentstatisticlinks = (
    	'album' => 'all',
    	'artist' => 'allalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getAllTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		$sql = "select tracks.id from tracks left join track_statistics on tracks.url = track_statistics.url left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where tracks.audio=1 and dynamicplaylist_history.id is null order by tracks.album asc,tracks.disc asc,tracks.tracknum asc limit $listLength;";
	}else {
		$sql = "select tracks.id from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by tracks.album asc,tracks.disc asc, tracks.tracknum asc limit $listLength;";
	}
    return Plugins::TrackStat::Statistics::Base::getTracks($sql,$limit);
}

sub getAllAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_ALLALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_ALLALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_ALLALBUMS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_ALLALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_ALLALBUMS');
	}
}
sub isAllAlbumsValidInContext {
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

sub getAllAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	my $minalbumtext = "";
	my $minalbumlimit = $prefs->get("min_album_tracks");
	if($minalbumlimit && $minalbumlimit>0) {
		$minalbumtext = "having count(tracks.id)>=".$minalbumlimit." ";
	}
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist  and contributor_track.role in (1,4,5,6) left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by albums.year desc,albums.titlesort asc limit $listLength";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album $minalbumtext order by albums.titlesort asc limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where tracks.year=$year group by tracks.album $minalbumtext order by albums.titlesort asc limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by albums.titlesort asc limit $listLength";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album $minalbumtext order by albums.titlesort asc limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'all',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_ALL_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'album' => 'all'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getAllAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $minalbumtext = "";
	my $minalbumlimit = $prefs->get("min_album_tracks");
	if($minalbumlimit && $minalbumlimit>0) {
		$minalbumtext = "having count(tracks.id)>=".$minalbumlimit." ";
	}
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by tracks.album $minalbumtext order by albums.titlesort asc limit $listLength";
	}else {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album $minalbumtext order by albums.titlesort asc limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($sql,$limit);
}

sub getAllArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_ALLARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_ALLARTISTS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_ALLARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_ALLARTISTS');
	}
}

sub isAllArtistsValidInContext {
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
sub getAllArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	my $minartisttext = "";
	my $minartistlimit = $prefs->get("min_artist_tracks");
	if($minartistlimit && $minartistlimit>0) {
		$minartisttext = "having count(tracks.id)>=".$minartistlimit." ";
	}
	if(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track  and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id $minartisttext order by contributors.namesort asc limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor and tracks.year=$year group by contributors.id $minartisttext order by contributors.namesort asc limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id order by contributors.namesort asc limit $listLength";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id $minartisttext order by contributors.namesort asc limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'all',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_ALL_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'allalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_ALLALBUMS_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'allyears',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_ALLYEARS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'artist' => 'allalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getAllArtistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $minartisttext = "";
	my $minartistlimit = $prefs->get("min_artist_tracks");
	if($minartistlimit && $minartistlimit>0) {
		$minartisttext = "having count(tracks.id)>=".$minartistlimit." ";
	}
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by contributors.id $minartisttext order by contributors.namesort asc limit $listLength";
	}else {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id $minartisttext order by contributors.namesort asc limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getArtistTracks($sql,$limit);
}

sub isAllGenresValidInContext {
	my $params = shift;
	return 0;
}

sub getAllGenresWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select genres.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join genre_track on tracks.id=genre_track.track join genres on genres.id = genre_track.genre group by genres.id order by genres.namesort asc limit $listLength";
    Plugins::TrackStat::Statistics::Base::getGenresWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'all',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_ALL_FORGENRE_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'allalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_ALLALBUMS_FORGENRE_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'allartists',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_ALLARTISTS_FORGENRE_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'genre' => 'allartists',
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getAllGenreTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select genres.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join genre_track on tracks.id=genre_track.track join genres on genres.id = genre_track.genre group by genres.id order by genres namesort asc limit $listLength";
    return Plugins::TrackStat::Statistics::Base::getGenreTracks($sql,$limit);
}

sub isAllYearsValidInContext {
	my $params = shift;
	if(defined($params->{'artist'})) {
		return 1;
	}elsif(defined($params->{'genre'})) {
		return 1;
	}
	return 0;
}

sub getAllYearsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_ALLYEARS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_ALLYEARS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_ALLYEARS');
	}
}
sub getAllYearsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select year,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist and contributor_track.role in (1,4,5,6) left join track_statistics on tracks.url = track_statistics.url group by year having year>0 order by year desc limit $listLength";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select year,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url group by year having year>0 order by year desc limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}else {
	    $sql = "select year,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url group by year having year>0 order by year desc limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getYearsWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'all',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_ALL_FORYEAR_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'allalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_ALLALBUMS_FORYEAR_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'allartists',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_ALLARTISTS_FORYEAR_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'year' => 'allalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getAllYearTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		$sql = "select year,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by year having year>0 order by year desc limit $listLength";
	}else {
		$sql = "select year,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url group by year having year>0 order by year desc limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getYearTracks($sql,$limit);
}


sub isAllPlaylistsValidInContext {
	my $params = shift;
	return 0;
}

sub getAllPlaylistsName {
	my $params = shift;
	return string('PLUGIN_TRACKSTAT_SONGLIST_ALLPLAYLISTS');
}
sub getAllPlaylistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select playlist_track.playlist,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join playlist_track on tracks.id=playlist_track.track group by playlist_track.playlist order by playlist_track.playlist asc limit $listLength";
    Plugins::TrackStat::Statistics::Base::getPlaylistsWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'all',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_ALL_FORPLAYLIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'allalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_ALLALBUMS_FORPLAYLIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'allartists',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_ALLARTISTS_FORPLAYLIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'playlist' => 'all'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getAllPlaylistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		$sql = "select playlist_track.playlist,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join playlist_track on tracks.id=playlist_track.track left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by playlist_track.playlist order by playlist_track.playlist asc limit $listLength";
	}else {
		$sql = "select playlist_track.playlist,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join playlist_track on tracks.id=playlist_track.track group by playlist_track.playlist order by playlist_track.playlist asc limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getPlaylistTracks($sql,$limit);
}

1;

__END__
