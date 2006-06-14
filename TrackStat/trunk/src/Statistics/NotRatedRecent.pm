#         TrackStat::Statistics::NotRatedRecent module
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
                   
package Plugins::TrackStat::Statistics::NotRatedRecent;

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
		notratednotrecent => {
			'webfunction' => \&getNotRatedNotRecentTracksWeb,
			'playlistfunction' => \&getNotRatedNotRecentTracks,
			'id' =>  'notratednotrecent',
			'namefunction' => \&getNotRatedNotRecentTracksName,
			'contextfunction' => \&isNotRatedNotRecentTracksValidInContext
		},
		notratednotrecentartists => {
			'webfunction' => \&getNotRatedNotRecentArtistsWeb,
			'playlistfunction' => \&getNotRatedNotRecentArtistTracks,
			'id' =>  'notratednotrecentartists',
			'namefunction' => \&getNotRatedNotRecentArtistsName,
			'contextfunction' => \&isNotRatedNotRecentArtistsValidInContext
		},
		notratednotrecentalbums => {
			'webfunction' => \&getNotRatedNotRecentAlbumsWeb,
			'playlistfunction' => \&getNotRatedNotRecentAlbumTracks,
			'id' =>  'notratednotrecentalbums',
			'namefunction' => \&getNotRatedNotRecentAlbumsName,
			'contextfunction' => \&isNotRatedNotRecentAlbumsValidInContext
		}
	);
	if(Slim::Utils::Prefs::get("plugin_trackstat_history_enabled")) {
		$statistics{notratedrecent} = {
			'webfunction' => \&getNotRatedRecentTracksWeb,
			'playlistfunction' => \&getNotRatedRecentTracks,
			'id' =>  'notratedrecent',
			'namefunction' => \&getNotRatedRecentTracksName,
			'contextfunction' => \&isNotRatedRecentTracksValidInContext
		};

		$statistics{notratedrecentartists} = {
			'webfunction' => \&getNotRatedRecentArtistsWeb,
			'playlistfunction' => \&getNotRatedRecentArtistTracks,
			'id' =>  'notratedrecentartists',
			'namefunction' => \&getNotRatedRecentArtistsName,
			'contextfunction' => \&isNotRatedRecentArtistsValidInContext
		};
				
		$statistics{notratedrecentalbums} = {
			'webfunction' => \&getNotRatedRecentAlbumsWeb,
			'playlistfunction' => \&getNotRatedRecentAlbumTracks,
			'id' =>  'notratedrecentalbums',
			'namefunction' => \&getNotRatedRecentAlbumsName,
			'contextfunction' => \&isNotRatedRecentAlbumsValidInContext
		};
	}
	return \%statistics;
}

sub getNotRatedRecentTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT');
	}
}

sub isNotRatedRecentTracksValidInContext {
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
sub getNotRatedNotRecentTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT');
	}
}

sub isNotRatedNotRecentTracksValidInContext {
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
sub getNotRatedRecentTracksWeb {
	my $params = shift;
	my $listLength = shift;
	getNotRatedHistoryTracksWeb($params,$listLength,">",getRecentTime());
    my %currentstatisticlinks = (
    	'album' => 'notratedrecent',
    	'artist' => 'notratedrecentalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getNotRatedRecentTracks {
	my $listLength = shift;
	my $limit = shift;
	return getNotRatedHistoryTracks($listLength,$limit,">",getRecentTime());
}

sub getNotRatedRecentAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTALBUMS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->name,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTALBUMS');
	}
}
sub isNotRatedRecentAlbumsValidInContext {
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

sub getNotRatedNotRecentAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTALBUMS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTALBUMS');
	}
}
sub isNotRatedNotRecentAlbumsValidInContext {
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

sub getNotRatedRecentAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getNotRatedHistoryAlbumsWeb($params,$listLength,">",getRecentTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'notratedrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'album' => 'notratedrecent',
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getNotRatedRecentAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	return getNotRatedHistoryAlbumTracks($listLength,$limit,">",getRecentTime());
}

sub getNotRatedRecentArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTARTISTS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTARTISTS');
	}
}
sub isNotRatedRecentArtistsValidInContext {
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

sub getNotRatedNotRecentArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTARTISTS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTARTISTS');
	}
}
sub isNotRatedNotRecentArtistsValidInContext {
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

sub getNotRatedRecentArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getNotRatedHistoryArtistsWeb($params,$listLength,">",getRecentTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'notratedrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'notratedrecentalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'artist' => 'notratedrecentalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getNotRatedRecentArtistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	return getNotRatedHistoryArtistTracks($listLength,$limit,">",getRecentTime());
}

sub getNotRatedNotRecentTracksWeb {
	my $params = shift;
	my $listLength = shift;
	getNotRatedHistoryTracksWeb($params,$listLength,"<",getRecentTime());
    my %currentstatisticlinks = (
    	'album' => 'notratednotrecent',
    	'artist' => 'notratednotrecentalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getNotRatedNotRecentTracks {
	my $listLength = shift;
	my $limit = shift;
	return getNotRatedHistoryTracks($listLength,$limit,"<",getRecentTime());
}

sub getNotRatedNotRecentAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getNotRatedHistoryAlbumsWeb($params,$listLength,"<",getRecentTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'notratednotrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'album' => 'notratednotrecent'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getNotRatedNotRecentAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	return getNotRatedHistoryAlbumTracks($listLength,$limit,"<",getRecentTime());
}

sub getNotRatedNotRecentArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getNotRatedHistoryArtistsWeb($params,$listLength,"<",getRecentTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'notratednotrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'notratednotrecentalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'artist' => 'notratednotrecentalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getNotRatedNotRecentArtistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	return getNotRatedHistoryArtistTracks($listLength,$limit,"<",getRecentTime());
}

sub getNotRatedHistoryTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select tracks.url,count(track_history.url) as playCount,0 as added,max(track_history.played) as lastPlayed,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating from tracks,track_history,contributor_track,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributor_track.contributor=$artist and tracks.audio=1 and played$beforeAfter$beforeAfterTime and (track_statistics.rating is null or track_statistics.rating=0) group by track_history.url order by count(track_history.url) desc,maxrating desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) and (track_statistics.rating is null or track_statistics.rating=0) group by tracks.url order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;"
	    }
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'album'})) {
		my $album = $params->{'album'};
	    $sql = "select tracks.url,count(track_history.url) as playCount,0 as added,max(track_history.played) as lastPlayed,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating from tracks,track_history,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.audio=1 and tracks.album=$album and played$beforeAfter$beforeAfterTime and (track_statistics.rating is null or track_statistics.rating=0) group by track_history.url order by count(track_history.url) desc,maxrating desc,$orderBy;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and tracks.album=$album and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) and (track_statistics.rating is null or track_statistics.rating=0) order by track_statistics.playCount desc,tracks.playCount desc,$orderBy;"
	    }
	    $params->{'statisticparameters'} = "&album=$album";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select tracks.url,count(track_history.url) as playCount,0 as added,max(track_history.played) as lastPlayed,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating from tracks,track_history,genre_track,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=genre_track.track and genre_track.genre=$genre and tracks.audio=1 and played$beforeAfter$beforeAfterTime and (track_statistics.rating is null or track_statistics.rating=0) group by track_history.url order by count(track_history.url) desc,maxrating desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) and (track_statistics.rating is null or track_statistics.rating=0) order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;"
	    }
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select tracks.url,count(track_history.url) as playCount,0 as added,max(track_history.played) as lastPlayed,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating from tracks,track_history,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.audio=1 and tracks.year=$year and played$beforeAfter$beforeAfterTime and (track_statistics.rating is null or track_statistics.rating=0) group by track_history.url order by count(track_history.url) desc,maxrating desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and tracks.year=$year and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) and (track_statistics.rating is null or track_statistics.rating=0) order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;"
	    }
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select tracks.url,count(track_history.url) as playCount,0 as added,max(track_history.played) as lastPlayed,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating from tracks,track_history,playlist_track,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=playlist_track.track and playlist_track.playlist=$playlist and tracks.audio=1 and played$beforeAfter$beforeAfterTime and (track_statistics.rating is null or track_statistics.rating=0) group by track_history.url order by count(track_history.url) desc,maxrating desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) and (track_statistics.rating is null or track_statistics.rating=0) order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;"
	    }
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select tracks.url,count(track_history.url) as playCount,0 as added,max(track_history.played) as lastPlayed,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating from tracks,track_history,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.audio=1 and played$beforeAfter$beforeAfterTime and (track_statistics.rating is null or track_statistics.rating=0) group by track_history.url order by count(track_history.url) desc,maxrating desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) and (track_statistics.rating is null or track_statistics.rating=0) order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;"
	    }
	}
    Plugins::TrackStat::Statistics::Base::getTracksWeb($sql,$params);
}

sub getNotRatedHistoryTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select tracks.url,count(track_history.url) as playCount,0 as added,max(track_history.played) as lastPlayed,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating as maxrating from tracks,track_history,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.audio=1 and played$beforeAfter$beforeAfterTime and (track_statistics.rating is null or track_statistics.rating=0) group by track_history.url order by count(track_history.url) desc,maxrating desc,$orderBy limit $listLength;";
    if($beforeAfter eq "<") {
	    $sql = "select tracks.url,(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) and (track_statistics.rating is null or track_statistics.rating=0) order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    }
    return Plugins::TrackStat::Statistics::Base::getTracks($sql,$limit);
}

sub getNotRatedHistoryAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select albums.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,contributor_track,track_statistics where tracks.url=track_history.url and tracks.url=track_statistics.url and tracks.album=albums.id and tracks.id=contributor_track.track and contributor_track.contributor=$artist and played$beforeAfter$beforeAfterTime group by tracks.album having max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,maxrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,maxrating desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select albums.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,genre_track,track_statistics where tracks.url=track_history.url and tracks.url=track_statistics.url and tracks.album=albums.id and tracks.id=genre_track.track and genre_track.genre=$genre and played$beforeAfter$beforeAfterTime group by tracks.album having max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,maxrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,maxrating desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select albums.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,track_statistics where tracks.url=track_history.url and tracks.url=track_statistics.url and tracks.album=albums.id and tracks.year=$year and played$beforeAfter$beforeAfterTime group by tracks.album having max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,maxrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where tracks.year=$year group by tracks.album having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,maxrating desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select albums.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,playlist_track,track_statistics where tracks.url=track_history.url and tracks.url=track_statistics.url and tracks.album=albums.id and tracks.id=playlist_track.track and playlist_track.playlist=$playlist and played$beforeAfter$beforeAfterTime group by tracks.album having max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,maxrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,maxrating desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select albums.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,track_statistics where tracks.url=track_history.url and tracks.url=track_statistics.url and tracks.album=albums.id and played$beforeAfter$beforeAfterTime group by tracks.album having max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,maxrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,maxrating desc,$orderBy limit $listLength";
	    }
	}
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
}

sub getNotRatedHistoryAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select albums.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,track_statistics where tracks.url=track_history.url and tracks.url=track_statistics.url and tracks.album=albums.id and played$beforeAfter$beforeAfterTime group by tracks.album having max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,maxrating desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select albums.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,maxrating desc,$orderBy limit $listLength";
    }
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($sql,$limit);
}

sub getNotRatedHistoryArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select contributors.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,genre_track,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and tracks.id=genre_track.track and genre_track.genre=$genre and played$beforeAfter$beforeAfterTime group by contributors.id having max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,maxrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,maxrating desc,$orderBy limit $listLength";    
		}
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select contributors.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and tracks.year=$year and played$beforeAfter$beforeAfterTime group by contributors.id having max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,maxrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor where tracks.year=$year group by contributors.id having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,maxrating desc,$orderBy limit $listLength";    
		}
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select contributors.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,playlist_track,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and tracks.id=playlist_track.track and playlist_track.playlist=$playlist and played$beforeAfter$beforeAfterTime group by contributors.id having max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,maxrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,maxrating desc,$orderBy limit $listLength";    
		}
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select contributors.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and played$beforeAfter$beforeAfterTime group by contributors.id having max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,maxrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,maxrating desc,$orderBy limit $listLength";    
		}
	}
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
}

sub getNotRatedHistoryArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select contributors.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and played$beforeAfter$beforeAfterTime group by contributors.id having max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,maxrating desc,$orderBy limit $listLength";
    if($beforeAfter eq "<") {
		$sql = "select contributors.id,max(case when track_statistics.rating is null then 0 else track_statistics.rating end) as maxrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having (max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime) and max(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,maxrating desc,$orderBy limit $listLength";    
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
PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT
	EN	Not rated songs recently played

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT_FORALBUM_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT_FORALBUM
	EN	Not rated songs recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT_FORARTIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT_FORARTIST
	EN	Not rated songs recently played by: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT_FORGENRE_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT_FORGENRE
	EN	Not rated songs recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT_FORYEAR_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT_FORYEAR
	EN	Not rated songs recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT_FORPLAYLIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENT_FORPLAYLIST
	EN	Not rated songs recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTALBUMS
	EN	Not rated albums recently played

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTALBUMS_FORARTIST
	EN	Not rated albums recently played by: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTALBUMS_FORGENRE_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTALBUMS_FORGENRE
	EN	Not rated albums recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTALBUMS_FORYEAR_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTALBUMS_FORYEAR
	EN	Not rated albums recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTALBUMS_FORPLAYLIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTALBUMS_FORPLAYLIST
	EN	Not rated albums recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTARTISTS
	EN	Not rated artists recently played

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTARTISTS_FORGENRE_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTARTISTS_FORGENRE
	EN	Not rated artists recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTARTISTS_FORYEAR_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTARTISTS_FORYEAR
	EN	Not rated artists recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTARTISTS_FORPLAYLIST_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTARTISTS_FORPLAYLIST
	EN	Not rated artists recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT
	EN	Not rated songs not recently played

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT_FORALBUM_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT_FORALBUM
	EN	Not rated songs not recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT_FORARTIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT_FORARTIST
	EN	Not rated songs not recently played by: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT_FORGENRE_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT_FORGENRE
	EN	Not rated songs not recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT_FORYEAR_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT_FORYEAR
	EN	Not rated songs not recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT_FORPLAYLIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENT_FORPLAYLIST
	EN	Not rated songs not recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTALBUMS
	EN	Not rated albums not recently played

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTALBUMS_FORARTIST
	EN	Not rated albums not recently played by: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTALBUMS_FORGENRE_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTALBUMS_FORGENRE
	EN	Not rated albums not recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTALBUMS_FORYEAR_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTALBUMS_FORYEAR
	EN	Not rated albums not recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTALBUMS_FORPLAYLIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTALBUMS_FORPLAYLIST
	EN	Not rated albums not recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTARTISTS
	EN	Not rated artists not recently played

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTARTISTS_FORGENRE_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTARTISTS_FORGENRE
	EN	Not rated artists not recently played in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTARTISTS_FORYEAR_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTARTISTS_FORYEAR
	EN	Not rated artists not recently played from: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTARTISTS_FORPLAYLIST_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTARTISTS_FORPLAYLIST
	EN	Not rated artists not recently played in: 
";
}

1;

__END__
