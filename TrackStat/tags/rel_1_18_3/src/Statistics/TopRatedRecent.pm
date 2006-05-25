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
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT')
		},
		topratednotrecentartists => {
			'webfunction' => \&getTopRatedNotRecentArtistsWeb,
			'playlistfunction' => \&getTopRatedNotRecentArtistTracks,
			'id' =>  'topratednotrecentartists',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTARTISTS')
		},
		topratednotrecentalbums => {
			'webfunction' => \&getTopRatedNotRecentAlbumsWeb,
			'playlistfunction' => \&getTopRatedNotRecentAlbumTracks,
			'id' =>  'topratednotrecentalbums',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS')
		}
	);
	if(Slim::Utils::Prefs::get("plugin_trackstat_history_enabled")) {
		$statistics{topratedrecent} = {
			'webfunction' => \&getTopRatedRecentTracksWeb,
			'playlistfunction' => \&getTopRatedRecentTracks,
			'id' =>  'topratedrecent',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENT')
		};
		$statistics{topratedrecentartists} = {
			'webfunction' => \&getTopRatedRecentArtistsWeb,
			'playlistfunction' => \&getTopRatedRecentArtistTracks,
			'id' =>  'topratedrecentartists',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTARTISTS')
		};
		$statistics{topratedrecentalbums} = {
			'webfunction' => \&getTopRatedRecentAlbumsWeb,
			'playlistfunction' => \&getTopRatedRecentAlbumTracks,
			'id' =>  'topratedrecentalbums',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS')
		};
	}
	return \%statistics;
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

sub getTopRatedRecentAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getTopRatedHistoryAlbumsWeb($params,$listLength,">",getRecentTime());
}

sub getTopRatedRecentAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	return getTopRatedHistoryAlbumTracks($listLength,$limit,">",getRecentTime());
}

sub getTopRatedRecentArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getTopRatedHistoryArtistsWeb($params,$listLength,">",getRecentTime());
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
    my $sql = "select tracks.url,count(tracks.url) as playCount,0 as added,max(track_history.played) as lastPlayed,avg(track_history.rating) as avgrating from tracks, track_history where tracks.url = track_history.url and tracks.audio=1 and played$beforeAfter$beforeAfterTime group by tracks.url order by avgrating desc,playCount desc,$orderBy limit $listLength;";
    if($beforeAfter eq "<") {
	    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.lastPlayed<$beforeAfterTime order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
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
	    $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.lastPlayed<$beforeAfterTime order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    }
    return Plugins::TrackStat::Statistics::Base::getTracks($sql,$limit);
}

sub getTopRatedHistoryAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select albums.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as minadded  from tracks,track_history, albums where tracks.url=track_history.url and tracks.album=albums.id and played$beforeAfter$beforeAfterTime group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    }
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
}

sub getTopRatedHistoryAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select albums.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as minadded  from tracks,track_history, albums where tracks.url=track_history.url and tracks.album=albums.id and played$beforeAfter$beforeAfterTime group by tracks.album order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    }
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($sql,$limit);
}

sub getTopRatedHistoryArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select contributors.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as minadded from tracks,track_history,contributor_track,contributors where tracks.url = track_history.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and played$beforeAfter$beforeAfterTime group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,sumcount desc,$orderBy limit $listLength";    
	}
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
}

sub getTopRatedHistoryArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select contributors.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as minadded from tracks,track_history,contributor_track,contributors where tracks.url = track_history.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and played$beforeAfter$beforeAfterTime group by contributors.id order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgrating desc,sumcount desc,$orderBy limit $listLength";    
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

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTALBUMS
	EN	Top rated albums recently played

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDRECENTARTISTS
	EN	Top rated artists recently played

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENT
	EN	Top rated songs not recently played

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTALBUMS
	EN	Top rated albums not recently played

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDNOTRECENTARTISTS
	EN	Top rated artists not recently played
";
}

1;

__END__
