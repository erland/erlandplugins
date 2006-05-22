#         TrackStat::Statistics::MostPlayedRecent module
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
                   
package Plugins::TrackStat::Statistics::MostPlayedRecent;

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
		mostplayednotrecent => {
			'webfunction' => \&getMostPlayedNotRecentTracksWeb,
			'playlistfunction' => \&getMostPlayedNotRecentTracks,
			'id' =>  'mostplayednotrecent',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT')
		},
		mostplayednotrecentartists => {
			'webfunction' => \&getMostPlayedNotRecentArtistsWeb,
			'playlistfunction' => \&getMostPlayedNotRecentArtistTracks,
			'id' =>  'mostplayednotrecentartists',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTARTISTS')
		},
		mostplayednotrecentalbums => {
			'webfunction' => \&getMostPlayedNotRecentAlbumsWeb,
			'playlistfunction' => \&getMostPlayedNotRecentAlbumTracks,
			'id' =>  'mostplayednotrecentalbums',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTALBUMS')
		}
	);
	if(Slim::Utils::Prefs::get("plugin_trackstat_history_enabled")) {
		$statistics{mostplayedrecent} = {
			'webfunction' => \&getMostPlayedRecentTracksWeb,
			'playlistfunction' => \&getMostPlayedRecentTracks,
			'id' =>  'mostplayedrecent',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT')
		};

		$statistics{mostplayedrecentartists} = {
			'webfunction' => \&getMostPlayedRecentArtistsWeb,
			'playlistfunction' => \&getMostPlayedRecentArtistTracks,
			'id' =>  'mostplayedrecentartists',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTARTISTS')
		};
				
		$statistics{mostplayedrecentalbums} = {
			'webfunction' => \&getMostPlayedRecentAlbumsWeb,
			'playlistfunction' => \&getMostPlayedRecentAlbumTracks,
			'id' =>  'mostplayedrecentalbums',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTALBUMS')
		};
	}
	return \%statistics;
}

sub getMostPlayedRecentTracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedHistoryTracksWeb($params,$listLength,">",getRecentTime());
}

sub getMostPlayedRecentTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedHistoryTracks($listLength,$limit,">",getRecentTime());
}

sub getMostPlayedRecentAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedHistoryAlbumsWeb($params,$listLength,">",getRecentTime());
}

sub getMostPlayedRecentAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	return getMostPlayedHistoryAlbumTracks($listLength,$limit,">",getRecentTime());
}

sub getMostPlayedRecentArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedHistoryArtistsWeb($params,$listLength,">",getRecentTime());
}

sub getMostPlayedRecentArtistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	return getMostPlayedHistoryArtistTracks($listLength,$limit,">",getRecentTime());
}

sub getMostPlayedNotRecentTracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedHistoryTracksWeb($params,$listLength,"<",getRecentTime());
}

sub getMostPlayedNotRecentTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedHistoryTracks($listLength,$limit,"<",getRecentTime());
}

sub getMostPlayedNotRecentAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedHistoryAlbumsWeb($params,$listLength,"<",getRecentTime());
}

sub getMostPlayedNotRecentAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	return getMostPlayedHistoryAlbumTracks($listLength,$limit,"<",getRecentTime());
}

sub getMostPlayedNotRecentArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedHistoryArtistsWeb($params,$listLength,"<",getRecentTime());
}

sub getMostPlayedNotRecentArtistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	return getMostPlayedHistoryArtistTracks($listLength,$limit,"<",getRecentTime());
}

sub getMostPlayedHistoryTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select tracks.url,count(track_history.url) as playCount,0 as added,max(track_history.played) as lastPlayed,avg(track_history.rating) as avgrating from tracks,track_history where tracks.url = track_history.url and tracks.audio=1 and played$beforeAfter$beforeAfterTime group by track_history.url order by playCount desc,avgrating desc,$orderBy limit $listLength;";
    if($beforeAfter eq "<") {
	    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;"
    }
    Plugins::TrackStat::Statistics::Base::getTracksWeb($sql,$params);
}

sub getMostPlayedHistoryTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select tracks.url,count(track_history.url) as playCount,0 as added,max(track_history.played) as lastPlayed,avg(track_history.rating) as avgrating from tracks,track_history where tracks.url = track_history.url and tracks.audio=1 and played$beforeAfter$beforeAfterTime group by track_history.url order by playCount desc,avgrating desc,$orderBy limit $listLength;";
    if($beforeAfter eq "<") {
	    $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    }
    return Plugins::TrackStat::Statistics::Base::getTracks($sql,$limit);
}

sub getMostPlayedHistoryAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select albums.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as minadded  from tracks,track_history, albums where tracks.url=track_history.url and tracks.album=albums.id and played$beforeAfter$beforeAfterTime group by tracks.album order by avgcount desc,avgrating desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgcount desc,avgrating desc,$orderBy limit $listLength";
    }
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
}

sub getMostPlayedHistoryAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select albums.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as minadded  from tracks,track_history, albums where tracks.url=track_history.url and tracks.album=albums.id and played$beforeAfter$beforeAfterTime group by tracks.album order by avgcount desc,avgrating desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgcount desc,avgrating desc,$orderBy limit $listLength";
    }
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($sql,$limit);
}

sub getMostPlayedHistoryArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select contributors.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as minadded from tracks,track_history,contributor_track,contributors where tracks.url = track_history.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and played$beforeAfter$beforeAfterTime group by contributors.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by sumcount desc,avgrating desc,$orderBy limit $listLength";    
	}
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
}

sub getMostPlayedHistoryArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select contributors.id,avg(case when track_history.rating is null then 60 else track_history.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as minadded from tracks,track_history,contributor_track,contributors where tracks.url = track_history.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and played$beforeAfter$beforeAfterTime group by contributors.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, min(track_statistics.added) as minadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by sumcount desc,avgrating desc,$orderBy limit $listLength";    
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
PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT
	EN	Most played songs recently played

PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTALBUMS
	EN	Most played albums recently played

PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTARTISTS
	EN	Most played artists recently played

PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT
	EN	Most played songs not recently played

PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTALBUMS
	EN	Most played albums not recently played

PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTARTISTS
	EN	Most played artists not recently played
";
}

1;

__END__
