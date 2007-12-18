#         TrackStat::Statistics::NotCompletelyRatedRecentAdded module
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
                   
package Plugins::TrackStat::Statistics::NotCompletelyRatedRecentAdded;

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
		notcompletelyratednotrecentaddedartists => {
			'webfunction' => \&getNotCompletelyRatedNotRecentAddedArtistsWeb,
			'playlistfunction' => \&getNotCompletelyRatedNotRecentAddedArtistTracks,
			'id' =>  'notcompletelyratednotrecentaddedartists',
			'namefunction' => \&getNotCompletelyRatedNotRecentAddedArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isNotCompletelyRatedNotRecentAddedArtistsValidInContext
		},
		notcompletelyratednotrecentaddedalbums => {
			'webfunction' => \&getNotCompletelyRatedNotRecentAddedAlbumsWeb,
			'playlistfunction' => \&getNotCompletelyRatedNotRecentAddedAlbumTracks,
			'id' =>  'notcompletelyratednotrecentaddedalbums',
			'namefunction' => \&getNotCompletelyRatedNotRecentAddedAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isNotCompletelyRatedNotRecentAddedAlbumsValidInContext
		}
	);
	if($prefs->get("history_enabled")) {
		$statistics{notcompletelyratedrecentaddedartists} = {
			'webfunction' => \&getNotCompletelyRatedRecentAddedArtistsWeb,
			'playlistfunction' => \&getNotCompletelyRatedRecentAddedArtistTracks,
			'id' =>  'notcompletelyratedrecentaddedartists',
			'namefunction' => \&getNotCompletelyRatedRecentAddedArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isNotCompletelyRatedRecentAddedArtistsValidInContext
		};
				
		$statistics{notcompletelyratedrecentaddedalbums} = {
			'webfunction' => \&getNotCompletelyRatedRecentAddedAlbumsWeb,
			'playlistfunction' => \&getNotCompletelyRatedRecentAddedAlbumTracks,
			'id' =>  'notcompletelyratedrecentaddedalbums',
			'namefunction' => \&getNotCompletelyRatedRecentAddedAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isNotCompletelyRatedRecentAddedAlbumsValidInContext
		};
	}
	return \%statistics;
}


sub getNotCompletelyRatedRecentAddedAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTADDEDALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTADDEDALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTADDEDALBUMS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTADDEDALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->name,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTADDEDALBUMS');
	}
}
sub isNotCompletelyRatedRecentAddedAlbumsValidInContext {
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

sub getNotCompletelyRatedNotRecentAddedAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTADDEDALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTADDEDALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTADDEDALBUMS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTADDEDALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTADDEDALBUMS');
	}
}
sub isNotCompletelyRatedNotRecentAddedAlbumsValidInContext {
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

sub getNotCompletelyRatedRecentAddedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getNotCompletelyRatedHistoryAlbumsWeb($params,$listLength,">",getRecentAddedTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'topratedrecentadded',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTADDED_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'album' => 'topratedrecentadded',
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getNotCompletelyRatedRecentAddedAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	return getNotCompletelyRatedHistoryAlbumTracks($listLength,$limit,">",getRecentAddedTime());
}

sub getNotCompletelyRatedRecentAddedArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTADDEDARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTADDEDARTISTS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTADDEDARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTADDEDARTISTS');
	}
}
sub isNotCompletelyRatedRecentAddedArtistsValidInContext {
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

sub getNotCompletelyRatedNotRecentAddedArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTADDEDARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTADDEDARTISTS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTADDEDARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTADDEDARTISTS');
	}
}
sub isNotCompletelyRatedNotRecentAddedArtistsValidInContext {
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

sub getNotCompletelyRatedRecentAddedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getNotCompletelyRatedHistoryArtistsWeb($params,$listLength,">",getRecentAddedTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'notratedrecentadded',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'notcompletelyratedrecentaddedalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTADDEDALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'artist' => 'notcompletelyratedrecentaddedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getNotCompletelyRatedRecentAddedArtistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	return getNotCompletelyRatedHistoryArtistTracks($listLength,$limit,">",getRecentAddedTime());
}

sub getNotCompletelyRatedNotRecentAddedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getNotCompletelyRatedHistoryAlbumsWeb($params,$listLength,"<",getRecentAddedTime());
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

sub getNotCompletelyRatedNotRecentAddedAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	return getNotCompletelyRatedHistoryAlbumTracks($listLength,$limit,"<",getRecentAddedTime());
}

sub getNotCompletelyRatedNotRecentAddedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getNotCompletelyRatedHistoryArtistsWeb($params,$listLength,"<",getRecentAddedTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'notratednotrecentadded',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'notcompletelyratednotrecentaddedalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTADDEDALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'artist' => 'notcompletelyratednotrecentaddedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getNotCompletelyRatedNotRecentAddedArtistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	return getNotCompletelyRatedHistoryArtistTracks($listLength,$limit,"<",getRecentAddedTime());
}

sub getNotCompletelyRatedHistoryAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) from tracks,albums,contributor_track,track_statistics where tracks.url=track_statistics.url and tracks.album=albums.id and tracks.id=contributor_track.track and contributor_track.contributor=$artist and contributor_track.role in (1,4,5,6) and track_statistics.added$beforeAfter$beforeAfterTime group by tracks.album order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist and contributor_track.role in (1,4,5,6) left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having (max(track_statistics.added) is null or max(track_statistics.added)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added)  from tracks,albums,genre_track,track_statistics where tracks.url=track_statistics.url and tracks.album=albums.id and tracks.id=genre_track.track and genre_track.genre=$genre and track_statistics.added$beforeAfter$beforeAfterTime group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having (max(track_statistics.added) is null or max(track_statistics.added)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added)  from tracks,albums,track_statistics where tracks.url=track_statistics.url and tracks.album=albums.id and tracks.year=$year and track_statistics.added$beforeAfter$beforeAfterTime group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where tracks.year=$year group by tracks.album having (max(track_statistics.added) is null or max(track_statistics.added)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added)  from tracks,albums,playlist_track,track_statistics where tracks.url=track_statistics.url and tracks.album=albums.id and tracks.id=playlist_track.track and playlist_track.playlist=$playlist and track_statistics.added$beforeAfter$beforeAfterTime group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having (max(track_statistics.added) is null or max(track_statistics.added)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added)  from tracks,albums,track_statistics where tracks.url=track_statistics.url and tracks.album=albums.id and track_statistics.added$beforeAfter$beforeAfterTime group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having (max(track_statistics.added) is null or max(track_statistics.added)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    }
	}
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
}

sub getNotCompletelyRatedHistoryAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		$sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added)  from tracks join albums on tracks.album=albums.id join track_statistics on tracks.url=track_statistics.url left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null and track_statistics.added$beforeAfter$beforeAfterTime group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
		if($beforeAfter eq "<") {
			$sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by tracks.album having (max(track_statistics.added) is null or max(track_statistics.added)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
		}
	}else {
		$sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added)  from tracks,albums,track_statistics where tracks.url=track_statistics.url and tracks.album=albums.id and track_statistics.added$beforeAfter$beforeAfterTime group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
		if($beforeAfter eq "<") {
			$sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having (max(track_statistics.added) is null or max(track_statistics.added)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
		}
	}
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($sql,$limit);
}

sub getNotCompletelyRatedHistoryArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) from tracks,contributor_track,contributors,genre_track,track_statistics where  tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributors.id = contributor_track.contributor and tracks.id=genre_track.track and genre_track.genre=$genre and track_statistics.added$beforeAfter$beforeAfterTime group by contributors.id having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having (max(track_statistics.added) is null or max(track_statistics.added)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";    
		}
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) from tracks,contributor_track,contributors,track_statistics where  tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributors.id = contributor_track.contributor and tracks.year=$year and track_statistics.added$beforeAfter$beforeAfterTime group by contributors.id having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor where tracks.year=$year group by contributors.id having (max(track_statistics.added) is null or max(track_statistics.added)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";    
		}
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) from tracks,contributor_track,contributors,playlist_track,track_statistics where  tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributors.id = contributor_track.contributor and tracks.id=playlist_track.track and playlist_track.playlist=$playlist and track_statistics.added$beforeAfter$beforeAfterTime group by contributors.id having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having (max(track_statistics.added) is null or max(track_statistics.added)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";    
		}
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) from tracks,contributor_track,contributors,track_statistics where  tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributors.id = contributor_track.contributor and track_statistics.added$beforeAfter$beforeAfterTime group by contributors.id having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having (max(track_statistics.added) is null or max(track_statistics.added)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";    
		}
	}
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
}

sub getNotCompletelyRatedHistoryArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		$sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributor_track.contributor=contributors.id join track_statistics on tracks.url=track_statistics.url left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null and track_statistics.added$beforeAfter$beforeAfterTime group by contributors.id having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";
		if($beforeAfter eq "<") {
			$sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by contributors.id having (max(track_statistics.added) is null or max(track_statistics.added)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";    
		}
	}else {
		$sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) from tracks,contributor_track,contributors,track_statistics where  tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributors.id = contributor_track.contributor and track_statistics.added$beforeAfter$beforeAfterTime group by contributors.id having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";
		if($beforeAfter eq "<") {
			$sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having (max(track_statistics.added) is null or max(track_statistics.added)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";    
		}
	}
    return Plugins::TrackStat::Statistics::Base::getArtistTracks($sql,$limit);
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
