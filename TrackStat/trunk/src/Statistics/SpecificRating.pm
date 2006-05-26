#         TrackStat::Statistics::MostPlayed module
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
                   
package Plugins::TrackStat::Statistics::SpecificRating;

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
		rated1 => {
			'webfunction' => \&getRated1TracksWeb,
			'playlistfunction' => \&getRated1Tracks,
			'id' =>  'rated1',
			'namefunction' => \&getRated1TracksName
		},
		rated2 => {
			'webfunction' => \&getRated2TracksWeb,
			'playlistfunction' => \&getRated2Tracks,
			'id' =>  'rated2',
			'namefunction' => \&getRated2TracksName
		},
		rated3 => {
			'webfunction' => \&getRated3TracksWeb,
			'playlistfunction' => \&getRated3Tracks,
			'id' =>  'rated3',
			'namefunction' => \&getRated3TracksName
		},
		rated4 => {
			'webfunction' => \&getRated4TracksWeb,
			'playlistfunction' => \&getRated4Tracks,
			'id' =>  'rated4',
			'namefunction' => \&getRated4TracksName
		},
		rated5 => {
			'webfunction' => \&getRated5TracksWeb,
			'playlistfunction' => \&getRated5Tracks,
			'id' =>  'rated5',
			'namefunction' => \&getRated5TracksName
		},
		rated1artists => {
			'webfunction' => \&getRated1ArtistsWeb,
			'playlistfunction' => \&getRated1ArtistTracks,
			'id' =>  'rated1artists',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_RATED1ARTISTS')
		},
		rated2artists => {
			'webfunction' => \&getRated2ArtistsWeb,
			'playlistfunction' => \&getRated2ArtistTracks,
			'id' =>  'rated2artists',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_RATED2ARTISTS')
		},
		rated3artists => {
			'webfunction' => \&getRated3ArtistsWeb,
			'playlistfunction' => \&getRated3ArtistTracks,
			'id' =>  'rated3artists',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_RATED3ARTISTS')
		},
		rated4artists => {
			'webfunction' => \&getRated4ArtistsWeb,
			'playlistfunction' => \&getRated4ArtistTracks,
			'id' =>  'rated4artists',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_RATED4ARTISTS')
		},
		rated5artists => {
			'webfunction' => \&getRated5ArtistsWeb,
			'playlistfunction' => \&getRated5ArtistTracks,
			'id' =>  'rated5artists',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_RATED5ARTISTS')
		},
		rated1albums => {
			'webfunction' => \&getRated1AlbumsWeb,
			'playlistfunction' => \&getRated1AlbumTracks,
			'id' =>  'rated1albums',
			'namefunction' => \&getRated1AlbumsName
		},
		rated2albums => {
			'webfunction' => \&getRated2AlbumsWeb,
			'playlistfunction' => \&getRated2AlbumTracks,
			'id' =>  'rated2albums',
			'namefunction' => \&getRated2AlbumsName
		},
		rated3albums => {
			'webfunction' => \&getRated3AlbumsWeb,
			'playlistfunction' => \&getRated3AlbumTracks,
			'id' =>  'rated3albums',
			'namefunction' => \&getRated3AlbumsName
		},
		rated4albums => {
			'webfunction' => \&getRated4AlbumsWeb,
			'playlistfunction' => \&getRated4AlbumTracks,
			'id' =>  'rated4albums',
			'namefunction' => \&getRated4AlbumsName
		},
		rated5albums => {
			'webfunction' => \&getRated5AlbumsWeb,
			'playlistfunction' => \&getRated5AlbumTracks,
			'id' =>  'rated5albums',
			'namefunction' => \&getRated5AlbumsName
		}
	);
	return \%statistics;
}

sub getRated1TracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $artist = $ds->objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1_FORARTIST')." ".$artist->{name};
	}elsif(defined($params->{'album'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $album = $ds->objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1_FORALBUM')." ".$album->{title};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1');
	}
}

sub getRated2TracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $artist = $ds->objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2_FORARTIST')." ".$artist->{name};
	}elsif(defined($params->{'album'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $album = $ds->objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2_FORALBUM')." ".$album->{title};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2');
	}
}

sub getRated3TracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $artist = $ds->objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3_FORARTIST')." ".$artist->{name};
	}elsif(defined($params->{'album'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $album = $ds->objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3_FORALBUM')." ".$album->{title};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3');
	}
}

sub getRated4TracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $artist = $ds->objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4_FORARTIST')." ".$artist->{name};
	}elsif(defined($params->{'album'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $album = $ds->objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4_FORALBUM')." ".$album->{title};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4');
	}
}

sub getRated5TracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $artist = $ds->objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5_FORARTIST')." ".$artist->{name};
	}elsif(defined($params->{'album'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $album = $ds->objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5_FORALBUM')." ".$album->{title};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5');
	}
}

sub getRated1TracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedTracksWeb($params,$listLength,0,29);
}

sub getRated1Tracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedTracks($listLength,$limit,0,29);
}

sub getRated2TracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedTracksWeb($params,$listLength,29,49);
}

sub getRated2Tracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedTracks($listLength,$limit,29,49);
}

sub getRated3TracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedTracksWeb($params,$listLength,49,69);
}

sub getRated3Tracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedTracks($listLength,$limit,49,69);
}

sub getRated4TracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedTracksWeb($params,$listLength,69,89);
}

sub getRated4Tracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedTracks($listLength,$limit,69,89);
}

sub getRated5TracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedTracksWeb($params,$listLength,89,100);
}

sub getRated5Tracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedTracks($listLength,$limit,89,100);
}


sub getRated1AlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $artist = $ds->objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1ALBUMS_FORARTIST')." ".$artist->{name};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1ALBUMS');
	}
}

sub getRated2AlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $artist = $ds->objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2ALBUMS_FORARTIST')." ".$artist->{name};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2ALBUMS');
	}
}
sub getRated3AlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $artist = $ds->objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3ALBUMS_FORARTIST')." ".$artist->{name};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3ALBUMS');
	}
}
sub getRated4AlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $artist = $ds->objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4ALBUMS_FORARTIST')." ".$artist->{name};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4ALBUMS');
	}
}
sub getRated5AlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $artist = $ds->objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5ALBUMS_FORARTIST')." ".$artist->{name};
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5ALBUMS');
	}
}
sub getRated1AlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedAlbumsWeb($params,$listLength,0,29);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'toprated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
}

sub getRated1AlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedAlbumTracks($listLength,$limit,0,29);
}

sub getRated2AlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedAlbumsWeb($params,$listLength,29,49);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'toprated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
}

sub getRated2AlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedAlbumTracks($listLength,$limit,29,49);
}

sub getRated3AlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedAlbumsWeb($params,$listLength,49,69);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'toprated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
}

sub getRated3AlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedAlbumTracks($listLength,$limit,49,69);
}

sub getRated4AlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedAlbumsWeb($params,$listLength,69,89);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'toprated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
}

sub getRated4AlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedAlbumTracks($listLength,$limit,69,89);
}

sub getRated5AlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedAlbumsWeb($params,$listLength,89,100);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'toprated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
}

sub getRated5AlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedAlbumTracks($listLength,$limit,89,100);
}


sub getRated1ArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedArtistsWeb($params,$listLength,0,29);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'toprated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'topratedalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
}

sub getRated1ArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedArtistTracks($listLength,$limit,0,29);
}

sub getRated2ArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedArtistsWeb($params,$listLength,29,49);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'toprated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => '´topratedalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
}

sub getRated2ArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedArtistTracks($listLength,$limit,29,49);
}

sub getRated3ArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedArtistsWeb($params,$listLength,49,69);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'toprated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'topratedalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
}

sub getRated3ArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedArtistTracks($listLength,$limit,49,69);
}

sub getRated4ArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedArtistsWeb($params,$listLength,69,89);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'toprated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'topratedalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
}

sub getRated4ArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedArtistTracks($listLength,$limit,69,89);
}

sub getRated5ArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedArtistsWeb($params,$listLength,89,100);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'toprated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'topratedalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
}

sub getRated5ArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedArtistTracks($listLength,$limit,89,100);
}


sub getMostPlayedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $minrating = shift;
	my $maxrating = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.rating>$minrating and track_statistics.rating<=$maxrating order by track_statistics.rating desc, track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks,track_statistics,contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributor_track.contributor=$artist and tracks.audio=1 and track_statistics.rating>$minrating and track_statistics.rating<=$maxrating order by track_statistics.rating desc, track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    }
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'album'})) {
		my $album = $params->{'album'};
	    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and tracks.album=$album and track_statistics.rating>$minrating and track_statistics.rating<=$maxrating order by track_statistics.rating desc, track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks,track_statistics where tracks.url = track_statistics.url and tracks.audio=1 and tracks.album=$album and track_statistics.rating>$minrating and track_statistics.rating<=$maxrating order by track_statistics.rating desc, track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    }
	    $params->{'statisticparameters'} = "&album=$album";
	}else {
	    $sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.rating>$minrating and track_statistics.rating<=$maxrating order by track_statistics.rating desc, track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select tracks.url,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks,track_statistics where tracks.url = track_statistics.url and tracks.audio=1 and track_statistics.rating>$minrating and track_statistics.rating<=$maxrating order by track_statistics.rating desc, track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    }
	}
    Plugins::TrackStat::Statistics::Base::getTracksWeb($sql,$params);
}

sub getMostPlayedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $minrating = shift;
	my $maxrating = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.rating>$minrating and track_statistics.rating<=$maxrating order by track_statistics.rating desc, track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select tracks.url from tracks,track_statistics where tracks.url = track_statistics.url and tracks.audio=1 and track_statistics.rating>$minrating and track_statistics.rating<=$maxrating order by track_statistics.rating desc, track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    }
    return Plugins::TrackStat::Statistics::Base::getTracks($sql,$limit);
}

sub getMostPlayedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $minrating = shift;
	my $maxrating = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks,track_statistics,albums,contributor_track where tracks.url = track_statistics.url and tracks.album=albums.id and tracks.id=contributor_track.track and contributor_track.contributor=$artist group by tracks.album having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    }
	    $params->{'statisticparameters'} = "&artist=$artist";
	}else {
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
	    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks,track_statistics,albums where tracks.url = track_statistics.url and tracks.album=albums.id group by tracks.album having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    }
	}
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
}

sub getMostPlayedAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	my $minrating = shift;
	my $maxrating = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks,track_statistics,albums where tracks.url = track_statistics.url and tracks.album=albums.id group by tracks.album having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,avgcount desc,$orderBy limit $listLength";
    }
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($sql,$limit);
}

sub getMostPlayedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $minrating = shift;
	my $maxrating = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks , track_statistics , contributors, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor group by contributors.id having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    }
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
}

sub getMostPlayedArtistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $minrating = shift;
	my $maxrating = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    if(Slim::Utils::Prefs::get("plugin_trackstat_fast_queries")) {
    	$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks , track_statistics , contributors, contributor_track where tracks.url = track_statistics.url and tracks.id=contributor_track.track and contributors.id = contributor_track.contributor group by contributors.id having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,sumcount desc,$orderBy limit $listLength";
    }
    return Plugins::TrackStat::Statistics::Base::getArtistTracks($sql,$limit);
}

sub strings()
{
	return "
PLUGIN_TRACKSTAT_SONGLIST_RATED1
	EN	Songs rated *

PLUGIN_TRACKSTAT_SONGLIST_RATED1_FORALBUM_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_RATED1_FORALBUM
	EN	Songs rated * from: 

PLUGIN_TRACKSTAT_SONGLIST_RATED1_FORARTIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_RATED1_FORARTIST
	EN	Songs rated * by: 

PLUGIN_TRACKSTAT_SONGLIST_RATED2
	EN	Songs rated **

PLUGIN_TRACKSTAT_SONGLIST_RATED2_FORALBUM_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_RATED2_FORALBUM
	EN	Songs rated ** from: 

PLUGIN_TRACKSTAT_SONGLIST_RATED2_FORARTIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_RATED2_FORARTIST
	EN	Songs rated ** by: 

PLUGIN_TRACKSTAT_SONGLIST_RATED3
	EN	Songs rated ***

PLUGIN_TRACKSTAT_SONGLIST_RATED3_FORALBUM_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_RATED3_FORALBUM
	EN	Songs rated *** from: 

PLUGIN_TRACKSTAT_SONGLIST_RATED3_FORARTIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_RATED3_FORARTIST
	EN	Songs rated *** by: 

PLUGIN_TRACKSTAT_SONGLIST_RATED4
	EN	Songs rated ****

PLUGIN_TRACKSTAT_SONGLIST_RATED4_FORALBUM_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_RATED4_FORALBUM
	EN	Songs rated **** from: 

PLUGIN_TRACKSTAT_SONGLIST_RATED4_FORARTIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_RATED4_FORARTIST
	EN	Songs rated **** by: 

PLUGIN_TRACKSTAT_SONGLIST_RATED5
	EN	Songs rated *****

PLUGIN_TRACKSTAT_SONGLIST_RATED5_FORALBUM_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_RATED5_FORALBUM
	EN	Songs rated ***** from: 

PLUGIN_TRACKSTAT_SONGLIST_RATED5_FORARTIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_RATED5_FORARTIST
	EN	Songs rated ***** by: 

PLUGIN_TRACKSTAT_SONGLIST_RATED1ALBUMS
	EN	Albums rated *

PLUGIN_TRACKSTAT_SONGLIST_RATED1ALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_RATED1ALBUMS_FORARTIST
	EN	Albums rated * by: 

PLUGIN_TRACKSTAT_SONGLIST_RATED2ALBUMS
	EN	Albums rated **

PLUGIN_TRACKSTAT_SONGLIST_RATED2ALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_RATED2ALBUMS_FORARTIST
	EN	Albums rated ** by: 

PLUGIN_TRACKSTAT_SONGLIST_RATED3ALBUMS
	EN	Albums rated ***

PLUGIN_TRACKSTAT_SONGLIST_RATED3ALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_RATED3ALBUMS_FORARTIST
	EN	Albums rated *** by: 

PLUGIN_TRACKSTAT_SONGLIST_RATED4ALBUMS
	EN	Albums rated ****

PLUGIN_TRACKSTAT_SONGLIST_RATED4ALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_RATED4ALBUMS_FORARTIST
	EN	Albums rated **** by: 

PLUGIN_TRACKSTAT_SONGLIST_RATED5ALBUMS
	EN	Albums rated *****

PLUGIN_TRACKSTAT_SONGLIST_RATED5ALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_RATED5ALBUMS_FORARTIST
	EN	Albums rated ***** by: 

PLUGIN_TRACKSTAT_SONGLIST_RATED1ARTISTS
	EN	Artists rated *

PLUGIN_TRACKSTAT_SONGLIST_RATED2ARTISTS
	EN	Artists rated **

PLUGIN_TRACKSTAT_SONGLIST_RATED3ARTISTS
	EN	Artists rated ***

PLUGIN_TRACKSTAT_SONGLIST_RATED4ARTISTS
	EN	Artists rated ****

PLUGIN_TRACKSTAT_SONGLIST_RATED5ARTISTS
	EN	Artists rated *****
";
}

1;

__END__
