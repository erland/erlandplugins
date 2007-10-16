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
		mostplayednotrecent => {
			'webfunction' => \&getMostPlayedNotRecentTracksWeb,
			'playlistfunction' => \&getMostPlayedNotRecentTracks,
			'id' =>  'mostplayednotrecent',
			'namefunction' => \&getMostPlayedNotRecentTracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENT_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isMostPlayedNotRecentTracksValidInContext
		},
		mostplayednotrecentartists => {
			'webfunction' => \&getMostPlayedNotRecentArtistsWeb,
			'playlistfunction' => \&getMostPlayedNotRecentArtistTracks,
			'id' =>  'mostplayednotrecentartists',
			'namefunction' => \&getMostPlayedNotRecentArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENT_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isMostPlayedNotRecentArtistsValidInContext
		},
		mostplayednotrecentalbums => {
			'webfunction' => \&getMostPlayedNotRecentAlbumsWeb,
			'playlistfunction' => \&getMostPlayedNotRecentAlbumTracks,
			'id' =>  'mostplayednotrecentalbums',
			'namefunction' => \&getMostPlayedNotRecentAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENT_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isMostPlayedNotRecentAlbumsValidInContext
		}
	);
	if($prefs->get("history_enabled")) {
		$statistics{mostplayedrecent} = {
			'webfunction' => \&getMostPlayedRecentTracksWeb,
			'playlistfunction' => \&getMostPlayedRecentTracks,
			'id' =>  'mostplayedrecent',
			'namefunction' => \&getMostPlayedRecentTracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENT_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isMostPlayedRecentTracksValidInContext
		};

		$statistics{mostplayedrecentartists} = {
			'webfunction' => \&getMostPlayedRecentArtistsWeb,
			'playlistfunction' => \&getMostPlayedRecentArtistTracks,
			'id' =>  'mostplayedrecentartists',
			'namefunction' => \&getMostPlayedRecentArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENT_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isMostPlayedRecentArtistsValidInContext
		};
				
		$statistics{mostplayedrecentalbums} = {
			'webfunction' => \&getMostPlayedRecentAlbumsWeb,
			'playlistfunction' => \&getMostPlayedRecentAlbumTracks,
			'id' =>  'mostplayedrecentalbums',
			'namefunction' => \&getMostPlayedRecentAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENT_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isMostPlayedRecentAlbumsValidInContext
		};
	}
	return \%statistics;
}

sub getMostPlayedRecentTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT');
	}
}

sub isMostPlayedRecentTracksValidInContext {
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
sub getMostPlayedNotRecentTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT');
	}
}

sub isMostPlayedNotRecentTracksValidInContext {
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
sub getMostPlayedRecentTracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedHistoryTracksWeb($params,$listLength,">",getRecentTime());
    my %currentstatisticlinks = (
    	'album' => 'mostplayedrecent',
    	'artist' => 'mostplayedrecentalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getMostPlayedRecentTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedHistoryTracks($listLength,$limit,">",getRecentTime());
}

sub getMostPlayedRecentAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTALBUMS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->name,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTALBUMS');
	}
}
sub isMostPlayedRecentAlbumsValidInContext {
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

sub getMostPlayedNotRecentAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTALBUMS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTALBUMS');
	}
}
sub isMostPlayedNotRecentAlbumsValidInContext {
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

sub getMostPlayedRecentAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedHistoryAlbumsWeb($params,$listLength,">",getRecentTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'mostplayedrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'album' => 'mostplayedrecent',
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getMostPlayedRecentAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	return getMostPlayedHistoryAlbumTracks($listLength,$limit,">",getRecentTime());
}

sub getMostPlayedRecentArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTARTISTS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTARTISTS');
	}
}
sub isMostPlayedRecentArtistsValidInContext {
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

sub getMostPlayedNotRecentArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTARTISTS_FORYEAR')." ".$params->{'year'};
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTARTISTS');
	}
}
sub isMostPlayedNotRecentArtistsValidInContext {
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

sub getMostPlayedRecentArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedHistoryArtistsWeb($params,$listLength,">",getRecentTime());
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'mostplayedrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENT_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'mostplayedrecentalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDRECENTALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'artist' => 'mostplayedrecentalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
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
    my %currentstatisticlinks = (
    	'album' => 'mostplayednotrecent',
    	'artist' => 'mostplayednotrecentalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
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
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'mostplayednotrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'album' => 'mostplayednotrecent'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
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
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'mostplayednotrecent',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENT_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'mostplayednotrecentalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDNOTRECENTALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'artist' => 'mostplayednotrecentalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
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
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select tracks.id,count(track_history.url) as recentPlayCount,0 as added,max(track_history.played) as lastPlayed,avg(track_statistics.rating) as avgrating from tracks,track_history,contributor_track,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributor_track.contributor=$artist and contributor_track.role in (1,4,5,6) and tracks.audio=1 and played$beforeAfter$beforeAfterTime group by track_history.url order by recentPlayCount desc,avgrating desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist and contributor_track.role in (1,4,5,6) left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) group by tracks.url order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;"
	    }
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'album'})) {
		my $album = $params->{'album'};
	    $sql = "select tracks.id,count(track_history.url) as recentPlayCount,0 as added,max(track_history.played) as lastPlayed,avg(track_statistics.rating) as avgrating from tracks,track_history,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.audio=1 and tracks.album=$album and played$beforeAfter$beforeAfterTime group by track_history.url order by recentPlayCount desc,avgrating desc,$orderBy;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and tracks.album=$album and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) order by track_statistics.playCount desc,tracks.playCount desc,$orderBy;"
	    }
	    $params->{'statisticparameters'} = "&album=$album";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select tracks.id,count(track_history.url) as recentPlayCount,0 as added,max(track_history.played) as lastPlayed,avg(track_statistics.rating) as avgrating from tracks,track_history,genre_track,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=genre_track.track and genre_track.genre=$genre and tracks.audio=1 and played$beforeAfter$beforeAfterTime group by track_history.url order by recentPlayCount desc,avgrating desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;"
	    }
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select tracks.id,count(track_history.url) as recentPlayCount,0 as added,max(track_history.played) as lastPlayed,avg(track_statistics.rating) as avgrating from tracks,track_history,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.audio=1 and tracks.year=$year and played$beforeAfter$beforeAfterTime group by track_history.url order by recentPlayCount desc,avgrating desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and tracks.year=$year and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;"
	    }
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select tracks.id,count(track_history.url) as recentPlayCount,0 as added,max(track_history.played) as lastPlayed,avg(track_statistics.rating) as avgrating from tracks,track_history,playlist_track,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=playlist_track.track and playlist_track.playlist=$playlist and tracks.audio=1 and played$beforeAfter$beforeAfterTime group by track_history.url order by recentPlayCount desc,avgrating desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;"
	    }
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select tracks.id,count(track_history.url) as recentPlayCount,0 as added,max(track_history.played) as lastPlayed,avg(track_statistics.rating) as avgrating from tracks,track_history,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.audio=1 and played$beforeAfter$beforeAfterTime group by track_history.url order by recentPlayCount desc,avgrating desc,$orderBy limit $listLength;";
	    if($beforeAfter eq "<") {
		    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;"
	    }
	}
    Plugins::TrackStat::Statistics::Base::getTracksWeb($sql,$params);
}

sub getMostPlayedHistoryTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
    		$sql = "select tracks.id,count(track_history.url) as recentPlayCount,0 as added,max(track_history.played) as lastPlayed,avg(track_statistics.rating) as avgrating from tracks join track_history on tracks.url=track_history.url join track_statistics on tracks.url=track_statistics.url left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where tracks.audio=1 and dynamicplaylist_history.id is null and played$beforeAfter$beforeAfterTime group by track_history.url order by recentPlayCount desc,avgrating desc,$orderBy limit $listLength;";
		if($beforeAfter eq "<") {
			$sql = "select tracks.id from tracks left join track_statistics on tracks.url = track_statistics.url left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where tracks.audio=1 and dynamicplaylist_history.id is null and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
		}
	}else {
    		$sql = "select tracks.id,count(track_history.url) as recentPlayCount,0 as added,max(track_history.played) as lastPlayed,avg(track_statistics.rating) as avgrating from tracks,track_history,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.audio=1 and played$beforeAfter$beforeAfterTime group by track_history.url order by recentPlayCount desc,avgrating desc,$orderBy limit $listLength;";
		if($beforeAfter eq "<") {
			$sql = "select tracks.id from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and (track_statistics.lastPlayed is null or track_statistics.lastPlayed<$beforeAfterTime) order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
		}
	}
    return Plugins::TrackStat::Statistics::Base::getTracks($sql,$limit);
}

sub getMostPlayedHistoryAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,contributor_track,track_statistics where tracks.url=track_history.url and tracks.url=track_statistics.url and tracks.album=albums.id and tracks.id=contributor_track.track and contributor_track.contributor=$artist and contributor_track.role in (1,4,5,6) and played$beforeAfter$beforeAfterTime group by tracks.album order by avgcount desc,avgrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist and contributor_track.role in (1,4,5,6) left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgcount desc,avgrating desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,genre_track,track_statistics where tracks.url=track_history.url and tracks.url=track_statistics.url and tracks.album=albums.id and tracks.id=genre_track.track and genre_track.genre=$genre and played$beforeAfter$beforeAfterTime group by tracks.album order by avgcount desc,avgrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgcount desc,avgrating desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,track_statistics where tracks.url=track_history.url and tracks.url=track_statistics.url and tracks.album=albums.id and tracks.year=$year and played$beforeAfter$beforeAfterTime group by tracks.album order by avgcount desc,avgrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where tracks.year=$year group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgcount desc,avgrating desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,playlist_track,track_statistics where tracks.url=track_history.url and tracks.url=track_statistics.url and tracks.album=albums.id and tracks.id=playlist_track.track and playlist_track.playlist=$playlist and played$beforeAfter$beforeAfterTime group by tracks.album order by avgcount desc,avgrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgcount desc,avgrating desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,track_statistics where tracks.url=track_history.url and tracks.url=track_statistics.url and tracks.album=albums.id and played$beforeAfter$beforeAfterTime group by tracks.album order by avgcount desc,avgrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgcount desc,avgrating desc,$orderBy limit $listLength";
	    }
	}
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
}

sub getMostPlayedHistoryAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks join track_history on tracks.url=track_history.url join albums on tracks.album=albums.id join track_statistics on tracks.url=track_statistics.url left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null and played$beforeAfter$beforeAfterTime group by tracks.album order by avgcount desc,avgrating desc,$orderBy limit $listLength";
		if($beforeAfter eq "<") {
			$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgcount desc,avgrating desc,$orderBy limit $listLength";
		}
	}else {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url)/count($distinct track_history.url) as avgcount,max(track_history.played) as lastplayed, 0 as maxadded  from tracks,track_history, albums,track_statistics where tracks.url=track_history.url and tracks.url=track_statistics.url and tracks.album=albums.id and played$beforeAfter$beforeAfterTime group by tracks.album order by avgcount desc,avgrating desc,$orderBy limit $listLength";
		if($beforeAfter eq "<") {
			$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by avgcount desc,avgrating desc,$orderBy limit $listLength";
		}
	}
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($sql,$limit);
}

sub getMostPlayedHistoryArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,genre_track,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and contributor_track.role in (1,4,5,6) and tracks.id=genre_track.track and genre_track.genre=$genre and played$beforeAfter$beforeAfterTime group by contributors.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by sumcount desc,avgrating desc,$orderBy limit $listLength";    
		}
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and contributor_track.role in (1,4,5,6) and tracks.year=$year and played$beforeAfter$beforeAfterTime group by contributors.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor where tracks.year=$year group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by sumcount desc,avgrating desc,$orderBy limit $listLength";    
		}
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,playlist_track,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and contributor_track.role in (1,4,5,6) and tracks.id=playlist_track.track and playlist_track.playlist=$playlist and played$beforeAfter$beforeAfterTime group by contributors.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by sumcount desc,avgrating desc,$orderBy limit $listLength";    
		}
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and contributor_track.role in (1,4,5,6) and played$beforeAfter$beforeAfterTime group by contributors.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
	    if($beforeAfter eq "<") {
			$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by sumcount desc,avgrating desc,$orderBy limit $listLength";    
		}
	}
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
}

sub getMostPlayedHistoryArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	my $beforeAfter = shift;
	my $beforeAfterTime = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks join track_history on tracks.url=track_history.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributor_track.contributor=contributors.id join track_statistics on tracks.url=track_statistics.url left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null and played$beforeAfter$beforeAfterTime group by contributors.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
		if($beforeAfter eq "<") {
			$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by sumcount desc,avgrating desc,$orderBy limit $listLength";    
		}
	}else {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,count(track_history.url) as sumcount,max(track_history.played) as lastplayed, 0 as maxadded from tracks,track_history,contributor_track,contributors,track_statistics where tracks.url = track_history.url and tracks.url=track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor and contributor_track.role in (1,4,5,6) and played$beforeAfter$beforeAfterTime group by contributors.id order by sumcount desc,avgrating desc,$orderBy limit $listLength";
		if($beforeAfter eq "<") {
			$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having max(track_statistics.lastPlayed) is null or max(track_statistics.lastPlayed)<$beforeAfterTime order by sumcount desc,avgrating desc,$orderBy limit $listLength";    
		}
	}
    return Plugins::TrackStat::Statistics::Base::getArtistTracks($sql,$limit);
}


sub getRecentTime() {
	my $days = $prefs->get("recent_number_of_days");
	if(!defined($days)) {
		$days = 30;
	}
	return time() - 24*3600*$days;
}


1;

__END__
