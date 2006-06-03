#         TrackStat::Statistics::TopRatedRecent module
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
                   
package Plugins::TrackStat::Statistics::TopRatedRecent;

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
		topratednotrecent => {
			'webfunction' => \&getTopRatedNotRecentTracksWeb,
			'playlistfunction' => \&getTopRatedNotRecentTracks,
			'id' =>  'topratednotrecent',
			'namefunction' => \&getTopRatedNotRecentTracksName,
			'contextfunction' => \&isTopRatedNotRecentTracksValidInContext
		},
		topratednotrecentartists => {
			'webfunction' => \&getTopRatedNotRecentArtistsWeb,
			'playlistfunction' => \&getTopRatedNotRecentArtistTracks,
			'id' =>  'topratednotrecentartists',
			'namefunction' => \&getTopRatedNotRecentArtistsName,
			'contextfunction' => \&isTopRatedNotRecentArtistsValidInContext
		},
		topratednotrecentalbums => {
			'webfunction' => \&getTopRatedNotRecentAlbumsWeb,
			'playlistfunction' => \&getTopRatedNotRecentAlbumTracks,
			'id' =>  'topratednotrecentalbums',
			'namefunction' => \&getTopRatedNotRecentAlbumsName,
			'contextfunction' => \&isTopRatedNotRecentAlbumsValidInContext
		}
	);
	if(Slim::Utils::Prefs::get("plugin_trackstat_history_enabled")) {
		$statistics{topratedrecent} = {
			'webfunction' => \&getTopRatedRecentTracksWeb,
			'playlistfunction' => \&getTopRatedRecentTracks,
			'id' =>  'topratedrecent',
			'namefunction' => \&getTopRatedRecentTracksName,
			'contextfunction' => \&isTopRatedRecentTracksValidInContext
		};
		$statistics{topratedrecentartists} = {
			'webfunction' => \&getTopRatedRecentArtistsWeb,
			'playlistfunction' => \&getTopRatedRecentArtistTracks,
			'id' =>  'topratedrecentartists',
			'namefunction' => \&getTopRatedRecentArtistsName,
			'contextfunction' => \&isTopRatedRecentArtistsValidInContext
		};
		$statistics{topratedrecentalbums} = {
			'webfunction' => \&getTopRatedRecentAlbumsWeb,
			'playlistfunction' => \&getTopRatedRecentAlbumTracks,
			'id' =>  'topratedrecentalbums',
			'namefunction' => \&getTopRatedRecentAlbumsName,
			'contextfunction' => \&isTopRatedRecentAlbumsValidInContext
		};
	}
	return \%statistics;
}

sub getTopRatedRecentTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORYEAR')." ".$params->{'year'};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT');
	}
}
sub isTopRatedRecentTracksValidInContext {
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


sub getTopRatedNotRecentTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORYEAR')." ".$params->{'year'};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT');
	}
}

sub isTopRatedNotRecentTracksValidInContext {
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

sub getTopRatedRecentTracksWeb {
	my $params = shift;
	my $listLength = shift;
	getTopRatedHistoryTracksWeb($params,$listLength,">",getRecentTime());
}

sub getTopRatedRecentTracks {
	my $listLength = shift;
	my $limit = shift;
	return getTopRatedHistoryTracks($listLength,$limit,">",getRecentTime());
}

sub getTopRatedRecentAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS_FORYEAR')." ".$params->{'year'};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS');
	}
}
sub isTopRatedRecentAlbumsValidInContext {
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


sub getTopRatedNotRecentAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS_FORYEAR')." ".$params->{'year'};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS');
	}
}
sub isTopRatedNotRecentAlbumsValidInContext {
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

sub getTopRatedRecentAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getTopRatedHistoryAlbumsWeb($params,$listLength,">",getRecentTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'topratedrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
}

sub getTopRatedRecentAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	return getTopRatedHistoryAlbumTracks($listLength,$limit,">",getRecentTime());
}


sub getTopRatedRecentArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTARTISTS_FORYEAR')." ".$params->{'year'};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTARTISTS');
	}
}
sub isTopRatedRecentArtistsValidInContext {
	my $params = shift;
	if(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}
	return 0;
}


sub getTopRatedNotRecentArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTARTISTS_FORYEAR')." ".$params->{'year'};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTARTISTS');
	}
}
sub isTopRatedNotRecentArtistsValidInContext {
	my $params = shift;
	if(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}
	return 0;
}


sub getTopRatedRecentArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getTopRatedHistoryArtistsWeb($params,$listLength,">",getRecentTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'topratedrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'topratedrecentalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
}

sub getTopRatedRecentArtistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	return getTopRatedHistoryArtistTracks($listLength,$limit,">",getRecentTime());
}

sub getTopRatedNotRecentTracksWeb {
	my $params = shift;
	my $listLength = shift;
	getTopRatedHistoryTracksWeb($params,$listLength,"<",getRecentTime());
}

sub getTopRatedNotRecentTracks {
	my $listLength = shift;
	my $limit = shift;
	return getTopRatedHistoryTracks($listLength,$limit,"<",getRecentTime());
}

sub getTopRatedNotRecentAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getTopRatedHistoryAlbumsWeb($params,$listLength,"<",getRecentTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'topratednotrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
}

sub getTopRatedNotRecentAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	return getTopRatedHistoryAlbumTracks($listLength,$limit,"<",getRecentTime());
}

sub getTopRatedNotRecentArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getTopRatedHistoryArtistsWeb($params,$listLength,"<",getRecentTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'topratednotrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'topratednotrecentalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
}

sub getTopRatedNotRecentArtistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	return getTopRatedHistoryArtistTracks($listLength,$limit,"<",getRecentTime());
}

sub getTopRatedHistoryTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select tracks.url,count(tracks.url) as playCount,0 as added,max(track_history.played) as lastPlayed,avg(track_history.rating) as avgrating from tracks, track_history,contributor_track where tracks.url = track_history.url and tracks.id=contributor_track.track and contributor_track.contributor=$artist and tracks.audio=1 and played$beforeAfter$beforeAfterTime group by tracks.url order by avgrating desc,playCount desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    }
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'album'})) {
		my $album = $params->{'album'};
	    $sql = "select tracks.url,count(tracks.url) as playCount,0 as added,max(track_history.played) as lastPlayed,avg(track_history.rating) as avgrating from tracks, track_history where tracks.url = track_history.url and tracks.album=$album and tracks.audio=1 and played$beforeAfter$beforeAfterTime group by tracks.url order by avgrating desc,playCount desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.album=$album and tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    }
	    $params->{'statisticparameters'} = "&album=$album";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select tracks.url,count(tracks.url) as playCount,0 as added,max(track_history.played) as lastPlayed,avg(track_history.rating) as avgrating from tracks, track_history,genre_track where tracks.url = track_history.url and tracks.id=genre_track.track and genre_track.genre=$genre and tracks.audio=1 and played$beforeAfter$beforeAfterTime group by tracks.url order by avgrating desc,playCount desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    }
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select tracks.url,count(tracks.url) as playCount,0 as added,max(track_history.played) as lastPlayed,avg(track_history.rating) as avgrating from tracks, track_history where tracks.url = track_history.url and tracks.year=$year and tracks.audio=1 and played$beforeAfter$beforeAfterTime group by tracks.url order by avgrating desc,playCount desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.year=$year and tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    }
	    $params->{'statisticparameters'} = "&year=$year";
	}else {
	    $sql = "select tracks.url,count(tracks.url) as playCount,0 as added,max(track_history.played) as lastPlayed,avg(track_history.rating) as avgrating from tracks, track_history where tracks.url = track_history.url and tracks.audio=1 and played$beforeAfter$beforeAfterTime group by tracks.url order by avgrating desc,playCount desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    }
	}
    Plugins::TrackStat::Statistics::Base::getTracksWeb($sql,$params);
}

sub getTopRatedHistoryTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select tracks.url,count(tracks.url) as playCount,0 as added,max(track_history.played) as lastPlayed,avg(track_history.rating) as avgrating from tracks, track_history where tracks.url = track_history.url and tracks.audio=1 and played$beforeAfter$beforeAfterTime group by tracks.url order by avgrating desc,playCount desc,$orderBy limit $listLength;";
    if($beforeAfter eq "<") {
	    $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    }
    return Plugins::TrackStat::Statistics::Base::getTracks($sql,$limit);
}

sub getTopRatedHistoryAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select albums.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,contributor_track where tracks.url=track_history.url and tracks.album=albums.id and tracks.id=contributor_track.track and contributor_track.contributor=$artist and played$beforeAfter$beforeAfterTime group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select albums.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,genre_track where tracks.url=track_history.url and tracks.album=albums.id and tracks.id=genre_track.track and genre_track.genre=$genre and played$beforeAfter$beforeAfterTime group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select albums.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums where tracks.url=track_history.url and tracks.album=albums.id and tracks.year=$year and played$beforeAfter$beforeAfterTime group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where tracks.year=$year group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&year=$year";
	}else {
	    $sql = "select albums.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums where tracks.url=track_history.url and tracks.album=albums.id and played$beforeAfter$beforeAfterTime group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    }
	}
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
}

sub getTopRatedHistoryAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select albums.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums where tracks.url=track_history.url and tracks.album=albums.id and played$beforeAfter$beforeAfterTime group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    }
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($sql,$limit);
}

sub getTopRatedHistoryArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select contributors.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,genre_track where tracks.url = track_history.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and tracks.id=genre_track.track and genre_track.genre=$genre and played$beforeAfter$beforeAfterTime group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,sumcount desc,$orderBy limit $listLength";    
		}
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select contributors.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors where tracks.url = track_history.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and tracks.year=$year and played$beforeAfter$beforeAfterTime group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor where tracks.year=$year group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,sumcount desc,$orderBy limit $listLength";    
		}
	    $params->{'statisticparameters'} = "&year=$year";
	}else {
	    $sql = "select contributors.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors where tracks.url = track_history.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and played$beforeAfter$beforeAfterTime group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,sumcount desc,$orderBy limit $listLength";    
		}
	}
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
}

sub getTopRatedHistoryArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select contributors.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors where tracks.url = track_history.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and played$beforeAfter$beforeAfterTime group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,sumcount desc,$orderBy limit $listLength";    
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
PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT
	EN	Top rated songs recently played

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORALBUM_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORALBUM
	EN	Top rated songs recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORARTIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORARTIST
	EN	Top rated songs recently played by: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORGENRE_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORGENRE
	EN	Top rated songs recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORYEAR_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT_FORYEAR
	EN	Top rated songs recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS
	EN	Top rated albums recently played

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS_FORARTIST
	EN	Top rated albums recently played by: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS_FORGENRE_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS_FORGENRE
	EN	Top rated albums recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS_FORYEAR_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS_FORYEAR
	EN	Top rated albums recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTARTISTS
	EN	Top rated artists recently played

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTARTISTS_FORGENRE_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTARTISTS_FORGENRE
	EN	Top rated artists recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTARTISTS_FORYEAR_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTARTISTS_FORYEAR
	EN	Top rated artists recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT
	EN	Top rated songs not recently played

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORALBUM_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORALBUM
	EN	Top rated songs not recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORARTIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORARTIST
	EN	Top rated songs not recently played by: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORGENRE_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORGENRE
	EN	Top rated songs not recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORYEAR_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT_FORYEAR
	EN	Top rated songs not recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS
	EN	Top rated albums not recently played

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS_FORARTIST
	EN	Top rated albums not recently played by: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS_FORGENRE_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS_FORGENRE
	EN	Top rated albums not recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS_FORYEAR_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS_FORYEAR
	EN	Top rated albums not recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTARTISTS
	EN	Top rated artists not recently played

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTARTISTS_FORGENRE_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTARTISTS_FORGENRE
	EN	Top rated artists not recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTARTISTS_FORYEAR_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTARTISTS_FORYEAR
	EN	Top rated artists not recently played from: 
";
}

1;

__END__
