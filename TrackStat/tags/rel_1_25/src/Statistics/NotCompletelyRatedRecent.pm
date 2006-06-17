#         TrackStat::Statistics::NotCompletelyRatedRecent module
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
                   
package Plugins::TrackStat::Statistics::NotCompletelyRatedRecent;

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
		notcompletelyratednotrecentartists => {
			'webfunction' => \&getNotCompletelyRatedNotRecentArtistsWeb,
			'playlistfunction' => \&getNotCompletelyRatedNotRecentArtistTracks,
			'id' =>  'notcompletelyratednotrecentartists',
			'namefunction' => \&getNotCompletelyRatedNotRecentArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENT_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENT_GROUP')]],
			'contextfunction' => \&isNotCompletelyRatedNotRecentArtistsValidInContext
		},
		notcompletelyratednotrecentalbums => {
			'webfunction' => \&getNotCompletelyRatedNotRecentAlbumsWeb,
			'playlistfunction' => \&getNotCompletelyRatedNotRecentAlbumTracks,
			'id' =>  'notcompletelyratednotrecentalbums',
			'namefunction' => \&getNotCompletelyRatedNotRecentAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENT_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENT_GROUP')]],
			'contextfunction' => \&isNotCompletelyRatedNotRecentAlbumsValidInContext
		}
	);
	if(Slim::Utils::Prefs::get("plugin_trackstat_history_enabled")) {
		$statistics{notcompletelyratedrecentartists} = {
			'webfunction' => \&getNotCompletelyRatedRecentArtistsWeb,
			'playlistfunction' => \&getNotCompletelyRatedRecentArtistTracks,
			'id' =>  'notcompletelyratedrecentartists',
			'namefunction' => \&getNotCompletelyRatedRecentArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENT_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENT_GROUP')]],
			'contextfunction' => \&isNotCompletelyRatedRecentArtistsValidInContext
		};
				
		$statistics{notcompletelyratedrecentalbums} = {
			'webfunction' => \&getNotCompletelyRatedRecentAlbumsWeb,
			'playlistfunction' => \&getNotCompletelyRatedRecentAlbumTracks,
			'id' =>  'notcompletelyratedrecentalbums',
			'namefunction' => \&getNotCompletelyRatedRecentAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENT_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENT_GROUP')]],
			'contextfunction' => \&isNotCompletelyRatedRecentAlbumsValidInContext
		};
	}
	return \%statistics;
}


sub getNotCompletelyRatedRecentAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTALBUMS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->name,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTALBUMS');
	}
}
sub isNotCompletelyRatedRecentAlbumsValidInContext {
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

sub getNotCompletelyRatedNotRecentAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTALBUMS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTALBUMS');
	}
}
sub isNotCompletelyRatedNotRecentAlbumsValidInContext {
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

sub getNotCompletelyRatedRecentAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getNotCompletelyRatedHistoryAlbumsWeb($params,$listLength,">",getRecentTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'topratedrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'album' => 'topratedrecent',
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getNotCompletelyRatedRecentAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	return getNotCompletelyRatedHistoryAlbumTracks($listLength,$limit,">",getRecentTime());
}

sub getNotCompletelyRatedRecentArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTARTISTS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTARTISTS');
	}
}
sub isNotCompletelyRatedRecentArtistsValidInContext {
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

sub getNotCompletelyRatedNotRecentArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTARTISTS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTARTISTS');
	}
}
sub isNotCompletelyRatedNotRecentArtistsValidInContext {
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

sub getNotCompletelyRatedRecentArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getNotCompletelyRatedHistoryArtistsWeb($params,$listLength,">",getRecentTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'notratedrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'notcompletelyratedrecentalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'artist' => 'notcompletelyratedrecentalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getNotCompletelyRatedRecentArtistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	return getNotCompletelyRatedHistoryArtistTracks($listLength,$limit,">",getRecentTime());
}

sub getNotCompletelyRatedNotRecentAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getNotCompletelyRatedHistoryAlbumsWeb($params,$listLength,"<",getRecentTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'topratednotrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'album' => 'topratednotrecent'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getNotCompletelyRatedNotRecentAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	return getNotCompletelyRatedHistoryAlbumTracks($listLength,$limit,"<",getRecentTime());
}

sub getNotCompletelyRatedNotRecentArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getNotCompletelyRatedHistoryArtistsWeb($params,$listLength,"<",getRecentTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'notratednotrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'notcompletelyratednotrecentalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'artist' => 'notcompletelyratednotrecentalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getNotCompletelyRatedNotRecentArtistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	return getNotCompletelyRatedHistoryArtistTracks($listLength,$limit,"<",getRecentTime());
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
	    $sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,contributor_track,track_statistics where tracks.url=track_history.url and tracks.url=track_statistics.url and tracks.album=albums.id and tracks.id=contributor_track.track and contributor_track.contributor=$artist and played$beforeAfter$beforeAfterTime group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,genre_track,track_statistics where tracks.url=track_history.url and tracks.url=track_statistics.url and tracks.album=albums.id and tracks.id=genre_track.track and genre_track.genre=$genre and played$beforeAfter$beforeAfterTime group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,track_statistics where tracks.url=track_history.url and tracks.url=track_statistics.url and tracks.album=albums.id and tracks.year=$year and played$beforeAfter$beforeAfterTime group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where tracks.year=$year group by tracks.album having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,playlist_track,track_statistics where tracks.url=track_history.url and tracks.url=track_statistics.url and tracks.album=albums.id and tracks.id=playlist_track.track and playlist_track.playlist=$playlist and played$beforeAfter$beforeAfterTime group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,track_statistics where tracks.url=track_history.url and tracks.url=track_statistics.url and tracks.album=albums.id and played$beforeAfter$beforeAfterTime group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
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
    my $sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,track_statistics where tracks.url=track_history.url and tracks.url=track_statistics.url and tracks.album=albums.id and played$beforeAfter$beforeAfterTime group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select albums.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,minrating desc,$orderBy limit $listLength";
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
	    $sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,genre_track,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and tracks.id=genre_track.track and genre_track.genre=$genre and played$beforeAfter$beforeAfterTime group by contributors.id having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";    
		}
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and tracks.year=$year and played$beforeAfter$beforeAfterTime group by contributors.id having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor where tracks.year=$year group by contributors.id having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";    
		}
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,playlist_track,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and tracks.id=playlist_track.track and playlist_track.playlist=$playlist and played$beforeAfter$beforeAfterTime group by contributors.id having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";    
		}
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and played$beforeAfter$beforeAfterTime group by contributors.id having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";    
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
    my $sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and played$beforeAfter$beforeAfterTime group by contributors.id having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select contributors.id,min(case when track_statistics.rating is null then 0 else track_statistics.rating end) as minrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,minrating desc,$orderBy limit $listLength";    
	}
    return Plugins::TrackStat::Statistics::Base::getArtistTracks($sql,$limit);
}


sub getRecentTime() {
	my $days = Slim::Utils::Prefs::get("plugin_trackstat_recent_number_of_days");
	if(!defined($days)) {
		$days = 30;
	}
	return time() - 24*3600*$days;
}

sub strings()
{
	return "
PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTALBUMS
	EN	Not completely rated albums recently played

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTALBUMS_FORARTIST
	EN	Not completely rated albums recently played by: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTALBUMS_FORGENRE_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTALBUMS_FORGENRE
	EN	Not completely rated albums recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTALBUMS_FORYEAR_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTALBUMS_FORYEAR
	EN	Not completely rated albums recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTALBUMS_FORPLAYLIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTALBUMS_FORPLAYLIST
	EN	Not completely rated albums recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTARTISTS
	EN	Not completely rated artists recently played

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTARTISTS_FORGENRE_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTARTISTS_FORGENRE
	EN	Not completely rated artists recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTARTISTS_FORYEAR_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTARTISTS_FORYEAR
	EN	Not completely rated artists recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTARTISTS_FORPLAYLIST_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENTARTISTS_FORPLAYLIST
	EN	Not completely rated artists recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTALBUMS
	EN	Not completely rated albums not recently played

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTALBUMS_FORARTIST
	EN	Not completely rated albums not recently played by: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTALBUMS_FORGENRE_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTALBUMS_FORGENRE
	EN	Not completely rated albums not recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTALBUMS_FORYEAR_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTALBUMS_FORYEAR
	EN	Not completely rated albums not recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTALBUMS_FORPLAYLIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTALBUMS_FORPLAYLIST
	EN	Not completely rated albums not recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTARTISTS
	EN	Not completely rated artists not recently played

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTARTISTS_FORGENRE_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTARTISTS_FORGENRE
	EN	Not completely rated artists not recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTARTISTS_FORYEAR_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTARTISTS_FORYEAR
	EN	Not completely rated artists not recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTARTISTS_FORPLAYLIST_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENTARTISTS_FORPLAYLIST
	EN	Not completely rated artists not recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDRECENT_GROUP
	EN	Not completely rated

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDNOTRECENT_GROUP
	EN	Not completely rated
";
}

1;

__END__
