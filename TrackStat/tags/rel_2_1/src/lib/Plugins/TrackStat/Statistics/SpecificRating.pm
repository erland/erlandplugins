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
		rated1 => {
			'webfunction' => \&getRated1TracksWeb,
			'playlistfunction' => \&getRated1Tracks,
			'id' =>  'rated1',
			'namefunction' => \&getRated1TracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isRatedTracksValidInContext
		},
		rated2 => {
			'webfunction' => \&getRated2TracksWeb,
			'playlistfunction' => \&getRated2Tracks,
			'id' =>  'rated2',
			'namefunction' => \&getRated2TracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isRatedTracksValidInContext
		},
		rated3 => {
			'webfunction' => \&getRated3TracksWeb,
			'playlistfunction' => \&getRated3Tracks,
			'id' =>  'rated3',
			'namefunction' => \&getRated3TracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isRatedTracksValidInContext
		},
		rated4 => {
			'webfunction' => \&getRated4TracksWeb,
			'playlistfunction' => \&getRated4Tracks,
			'id' =>  'rated4',
			'namefunction' => \&getRated4TracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isRatedTracksValidInContext
		},
		rated5 => {
			'webfunction' => \&getRated5TracksWeb,
			'playlistfunction' => \&getRated5Tracks,
			'id' =>  'rated5',
			'namefunction' => \&getRated5TracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isRatedTracksValidInContext
		},
		rated1artists => {
			'webfunction' => \&getRated1ArtistsWeb,
			'playlistfunction' => \&getRated1ArtistTracks,
			'id' =>  'rated1artists',
			'namefunction' => \&getRated1ArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isRatedArtistsValidInContext
		},
		rated2artists => {
			'webfunction' => \&getRated2ArtistsWeb,
			'playlistfunction' => \&getRated2ArtistTracks,
			'id' =>  'rated2artists',
			'namefunction' => \&getRated2ArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isRatedArtistsValidInContext
		},
		rated3artists => {
			'webfunction' => \&getRated3ArtistsWeb,
			'playlistfunction' => \&getRated3ArtistTracks,
			'id' =>  'rated3artists',
			'namefunction' => \&getRated3ArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isRatedArtistsValidInContext
		},
		rated4artists => {
			'webfunction' => \&getRated4ArtistsWeb,
			'playlistfunction' => \&getRated4ArtistTracks,
			'id' =>  'rated4artists',
			'namefunction' => \&getRated4ArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isRatedArtistsValidInContext
		},
		rated5artists => {
			'webfunction' => \&getRated5ArtistsWeb,
			'playlistfunction' => \&getRated5ArtistTracks,
			'id' =>  'rated5artists',
			'namefunction' => \&getRated5ArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isRatedArtistsValidInContext
		},
		rated1albums => {
			'webfunction' => \&getRated1AlbumsWeb,
			'playlistfunction' => \&getRated1AlbumTracks,
			'id' =>  'rated1albums',
			'namefunction' => \&getRated1AlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isRatedAlbumsValidInContext
		},
		rated2albums => {
			'webfunction' => \&getRated2AlbumsWeb,
			'playlistfunction' => \&getRated2AlbumTracks,
			'id' =>  'rated2albums',
			'namefunction' => \&getRated2AlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isRatedAlbumsValidInContext
		},
		rated3albums => {
			'webfunction' => \&getRated3AlbumsWeb,
			'playlistfunction' => \&getRated3AlbumTracks,
			'id' =>  'rated3albums',
			'namefunction' => \&getRated3AlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isRatedAlbumsValidInContext
		},
		rated4albums => {
			'webfunction' => \&getRated4AlbumsWeb,
			'playlistfunction' => \&getRated4AlbumTracks,
			'id' =>  'rated4albums',
			'namefunction' => \&getRated4AlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isRatedAlbumsValidInContext
		},
		rated5albums => {
			'webfunction' => \&getRated5AlbumsWeb,
			'playlistfunction' => \&getRated5AlbumTracks,
			'id' =>  'rated5albums',
			'namefunction' => \&getRated5AlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isRatedAlbumsValidInContext
		}
	);
	if($prefs->get("rating_10scale")) {
		$statistics{rated6} = {
			'webfunction' => \&getRated6TracksWeb,
			'playlistfunction' => \&getRated6Tracks,
			'id' =>  'rated6',
			'namefunction' => \&getRated6TracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isRatedTracksValidInContext
		};
		$statistics{rated7} = {
			'webfunction' => \&getRated7TracksWeb,
			'playlistfunction' => \&getRated7Tracks,
			'id' =>  'rated7',
			'namefunction' => \&getRated7TracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isRatedTracksValidInContext
		};
		$statistics{rated8} = {
			'webfunction' => \&getRated8TracksWeb,
			'playlistfunction' => \&getRated8Tracks,
			'id' =>  'rated8',
			'namefunction' => \&getRated8TracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isRatedTracksValidInContext
		};
		$statistics{rated9} = {
			'webfunction' => \&getRated9TracksWeb,
			'playlistfunction' => \&getRated9Tracks,
			'id' =>  'rated9',
			'namefunction' => \&getRated9TracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isRatedTracksValidInContext
		};
		$statistics{rated10} = {
			'webfunction' => \&getRated10TracksWeb,
			'playlistfunction' => \&getRated10Tracks,
			'id' =>  'rated10',
			'namefunction' => \&getRated10TracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isRatedTracksValidInContext
		};
		$statistics{rated6artists} = {
			'webfunction' => \&getRated6ArtistsWeb,
			'playlistfunction' => \&getRated6ArtistTracks,
			'id' =>  'rated6artists',
			'namefunction' => \&getRated6ArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isRatedArtistsValidInContext
		};
		$statistics{rated7artists} = {
			'webfunction' => \&getRated7ArtistsWeb,
			'playlistfunction' => \&getRated7ArtistTracks,
			'id' =>  'rated7artists',
			'namefunction' => \&getRated7ArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isRatedArtistsValidInContext
		};
		$statistics{rated8artists} = {
			'webfunction' => \&getRated8ArtistsWeb,
			'playlistfunction' => \&getRated8ArtistTracks,
			'id' =>  'rated8artists',
			'namefunction' => \&getRated8ArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isRatedArtistsValidInContext
		};
		$statistics{rated9artists} = {
			'webfunction' => \&getRated9ArtistsWeb,
			'playlistfunction' => \&getRated9ArtistTracks,
			'id' =>  'rated9artists',
			'namefunction' => \&getRated9ArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isRatedArtistsValidInContext
		};
		$statistics{rated10artists} = {
			'webfunction' => \&getRated10ArtistsWeb,
			'playlistfunction' => \&getRated10ArtistTracks,
			'id' =>  'rated10artists',
			'namefunction' => \&getRated10ArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isRatedArtistsValidInContext
		};
		$statistics{rated6albums} = {
			'webfunction' => \&getRated6AlbumsWeb,
			'playlistfunction' => \&getRated6AlbumTracks,
			'id' =>  'rated6albums',
			'namefunction' => \&getRated6AlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isRatedAlbumsValidInContext
		};
		$statistics{rated7albums} = {
			'webfunction' => \&getRated7AlbumsWeb,
			'playlistfunction' => \&getRated7AlbumTracks,
			'id' =>  'rated7albums',
			'namefunction' => \&getRated7AlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isRatedAlbumsValidInContext
		};
		$statistics{rated8albums} = {
			'webfunction' => \&getRated8AlbumsWeb,
			'playlistfunction' => \&getRated8AlbumTracks,
			'id' =>  'rated8albums',
			'namefunction' => \&getRated8AlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isRatedAlbumsValidInContext
		};
		$statistics{rated9albums} = {
			'webfunction' => \&getRated9AlbumsWeb,
			'playlistfunction' => \&getRated9AlbumTracks,
			'id' =>  'rated9albums',
			'namefunction' => \&getRated9AlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isRatedAlbumsValidInContext
		};
		$statistics{rated10albums} = {
			'webfunction' => \&getRated10AlbumsWeb,
			'playlistfunction' => \&getRated10AlbumTracks,
			'id' =>  'rated10albums',
			'namefunction' => \&getRated10AlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_SPECIFICRATING_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isRatedAlbumsValidInContext
		};
	}
	return \%statistics;
}

sub isRatedTracksValidInContext {
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

sub getRated1TracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1');
	}
}

sub getRated2TracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2');
	}
}

sub getRated3TracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3');
	}
}

sub getRated4TracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4');
	}
}

sub getRated5TracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5');
	}
}

sub getRated6TracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED6_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED6_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED6_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED6_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED6_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED6');
	}
}

sub getRated7TracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED7_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED7_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED7_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED7_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED7_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED7');
	}
}

sub getRated8TracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED8_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED8_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED8_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED8_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED8_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED8');
	}
}

sub getRated9TracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED9_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED9_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED9_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED9_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED9_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED9');
	}
}

sub getRated10TracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED10_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED10_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED10_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED10_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED10_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED10');
	}
}

sub getMinRating {
	my $rating = shift;
	if($prefs->get("rating_10scale")) {
		if($rating>1) {
			return ($rating-1)*10+4;
		}
	}else {
		if($rating>1) {
			return ($rating-1)*20+9;
		}
	}
	return 0;	
}

sub getMaxRating {
	my $rating = shift;
	if($prefs->get("rating_10scale")) {
		if($rating<10) {
			return $rating*10+4;
		}
	}else {
		if($rating<10) {
			return $rating*20+9;
		}
	}
	return 100;
}
sub getRated1TracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedTracksWeb($params,$listLength,getMinRating(1),getMaxRating(1));
    my %currentstatisticlinks = (
    	'album' => 'toprated',
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated1Tracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedTracks($listLength,$limit,getMinRating(1),getMaxRating(1));
}

sub getRated2TracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedTracksWeb($params,$listLength,getMinRating(2),getMaxRating(2));
    my %currentstatisticlinks = (
    	'album' => 'toprated',
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated2Tracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedTracks($listLength,$limit,getMinRating(2),getMaxRating(2));
}

sub getRated3TracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedTracksWeb($params,$listLength,getMinRating(3),getMaxRating(3));
    my %currentstatisticlinks = (
    	'album' => 'toprated',
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated3Tracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedTracks($listLength,$limit,getMinRating(3),getMaxRating(3));
}

sub getRated4TracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedTracksWeb($params,$listLength,getMinRating(4),getMaxRating(4));
    my %currentstatisticlinks = (
    	'album' => 'toprated',
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated4Tracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedTracks($listLength,$limit,getMinRating(4),getMaxRating(4));
}

sub getRated5TracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedTracksWeb($params,$listLength,getMinRating(5),getMaxRating(5));
    my %currentstatisticlinks = (
    	'album' => 'toprated',
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated5Tracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedTracks($listLength,$limit,getMinRating(5),getMaxRating(5));
}

sub getRated6TracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedTracksWeb($params,$listLength,getMinRating(6),getMaxRating(6));
    my %currentstatisticlinks = (
    	'album' => 'toprated',
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated6Tracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedTracks($listLength,$limit,getMinRating(6),getMaxRating(6));
}
sub getRated7TracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedTracksWeb($params,$listLength,getMinRating(7),getMaxRating(7));
    my %currentstatisticlinks = (
    	'album' => 'toprated',
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated7Tracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedTracks($listLength,$limit,getMinRating(7),getMaxRating(7));
}
sub getRated8TracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedTracksWeb($params,$listLength,getMinRating(8),getMaxRating(8));
    my %currentstatisticlinks = (
    	'album' => 'toprated',
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated8Tracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedTracks($listLength,$limit,getMinRating(8),getMaxRating(8));
}
sub getRated9TracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedTracksWeb($params,$listLength,getMinRating(9),getMaxRating(9));
    my %currentstatisticlinks = (
    	'album' => 'toprated',
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated9Tracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedTracks($listLength,$limit,getMinRating(9),getMaxRating(9));
}
sub getRated10TracksWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedTracksWeb($params,$listLength,getMinRating(10),getMaxRating(10));
    my %currentstatisticlinks = (
    	'album' => 'toprated',
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated10Tracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedTracks($listLength,$limit,getMinRating(10),getMaxRating(10));
}

sub isRatedAlbumsValidInContext {
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


sub getRated1AlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1ALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1ALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1ALBUMS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1ALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1ALBUMS');
	}
}

sub getRated2AlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2ALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2ALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2ALBUMS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2ALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2ALBUMS');
	}
}
sub getRated3AlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3ALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3ALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3ALBUMS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3ALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3ALBUMS');
	}
}
sub getRated4AlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4ALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4ALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4ALBUMS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4ALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4ALBUMS');
	}
}
sub getRated5AlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5ALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5ALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5ALBUMS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5ALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5ALBUMS');
	}
}
sub getRated6AlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED6ALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED6ALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED6ALBUMS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED6ALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED6ALBUMS');
	}
}
sub getRated7AlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED7ALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED7ALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED7ALBUMS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED7ALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED7ALBUMS');
	}
}
sub getRated8AlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED8ALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED8ALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED8ALBUMS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED8ALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED8ALBUMS');
	}
}
sub getRated9AlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED9ALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED9ALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED9ALBUMS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED9ALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED9ALBUMS');
	}
}
sub getRated10AlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED10ALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED10ALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED10ALBUMS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED10ALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED10ALBUMS');
	}
}

sub getRated1AlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedAlbumsWeb($params,$listLength,getMinRating(1),getMaxRating(1));
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

sub getRated1AlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedAlbumTracks($listLength,$limit,getMinRating(1),getMaxRating(1));
}

sub getRated2AlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedAlbumsWeb($params,$listLength,getMinRating(2),getMaxRating(2));
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

sub getRated2AlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedAlbumTracks($listLength,$limit,getMinRating(2),getMaxRating(2));
}

sub getRated3AlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedAlbumsWeb($params,$listLength,getMinRating(3),getMaxRating(3));
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

sub getRated3AlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedAlbumTracks($listLength,$limit,getMinRating(3),getMaxRating(3));
}

sub getRated4AlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedAlbumsWeb($params,$listLength,getMinRating(4),getMaxRating(4));
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

sub getRated4AlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedAlbumTracks($listLength,$limit,getMinRating(4),getMaxRating(4));
}

sub getRated5AlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedAlbumsWeb($params,$listLength,getMinRating(5),getMaxRating(5));
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

sub getRated5AlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedAlbumTracks($listLength,$limit,getMinRating(5),getMaxRating(5));
}

sub getRated6AlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedAlbumsWeb($params,$listLength,getMinRating(6),getMaxRating(6));
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

sub getRated6AlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedAlbumTracks($listLength,$limit,getMinRating(6),getMaxRating(6));
}
sub getRated7AlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedAlbumsWeb($params,$listLength,getMinRating(7),getMaxRating(7));
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

sub getRated7AlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedAlbumTracks($listLength,$limit,getMinRating(7),getMaxRating(7));
}
sub getRated8AlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedAlbumsWeb($params,$listLength,getMinRating(8),getMaxRating(8));
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

sub getRated8AlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedAlbumTracks($listLength,$limit,getMinRating(8),getMaxRating(8));
}
sub getRated9AlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedAlbumsWeb($params,$listLength,getMinRating(9),getMaxRating(9));
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

sub getRated9AlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedAlbumTracks($listLength,$limit,getMinRating(9),getMaxRating(9));
}
sub getRated10AlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedAlbumsWeb($params,$listLength,getMinRating(10),getMaxRating(10));
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

sub getRated10AlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedAlbumTracks($listLength,$limit,getMinRating(10),getMaxRating(10));
}
sub isRatedArtistsValidInContext {
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

sub getRated1ArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1ARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1ARTISTS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1ARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED1ARTISTS');
	}
}

sub getRated2ArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2ARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2ARTISTS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2ARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED2ARTISTS');
	}
}
sub getRated3ArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3ARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3ARTISTS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3ARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED3ARTISTS');
	}
}
sub getRated4ArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4ARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4ARTISTS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4ARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED4ARTISTS');
	}
}
sub getRated5ArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5ARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5ARTISTS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5ARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED5ARTISTS');
	}
}

sub getRated6ArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED6ARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED6ARTISTS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED6ARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED6ARTISTS');
	}
}

sub getRated7ArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED7ARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED7ARTISTS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED7ARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED7ARTISTS');
	}
}

sub getRated8ArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED8ARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED8ARTISTS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED8ARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED8ARTISTS');
	}
}

sub getRated9ArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED9ARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED9ARTISTS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED9ARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED9ARTISTS');
	}
}

sub getRated10ArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED10ARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED10ARTISTS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED10ARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_RATED10ARTISTS');
	}
}

sub getRated1ArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedArtistsWeb($params,$listLength,getMinRating(1),getMaxRating(1));
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
    my %currentstatisticlinks = (
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated1ArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedArtistTracks($listLength,$limit,getMinRating(1),getMaxRating(1));
}

sub getRated2ArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedArtistsWeb($params,$listLength,getMinRating(2),getMaxRating(2));
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
    my %currentstatisticlinks = (
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated2ArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedArtistTracks($listLength,$limit,getMinRating(2),getMaxRating(2));
}

sub getRated3ArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedArtistsWeb($params,$listLength,getMinRating(3),getMaxRating(3));
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
    my %currentstatisticlinks = (
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated3ArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedArtistTracks($listLength,$limit,getMinRating(3),getMaxRating(3));
}

sub getRated4ArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedArtistsWeb($params,$listLength,getMinRating(4),getMaxRating(4));
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
    my %currentstatisticlinks = (
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated4ArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedArtistTracks($listLength,$limit,getMinRating(4),getMaxRating(4));
}

sub getRated5ArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedArtistsWeb($params,$listLength,getMinRating(5),getMaxRating(5));
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
    my %currentstatisticlinks = (
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated5ArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedArtistTracks($listLength,$limit,getMinRating(5),getMaxRating(5));
}


sub getRated6ArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedArtistsWeb($params,$listLength,getMinRating(6),getMaxRating(6));
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
    my %currentstatisticlinks = (
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated6ArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedArtistTracks($listLength,$limit,getMinRating(6),getMaxRating(6));
}

sub getRated7ArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedArtistsWeb($params,$listLength,getMinRating(7),getMaxRating(7));
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
    my %currentstatisticlinks = (
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated7ArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedArtistTracks($listLength,$limit,getMinRating(7),getMaxRating(7));
}

sub getRated8ArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedArtistsWeb($params,$listLength,getMinRating(8),getMaxRating(8));
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
    my %currentstatisticlinks = (
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated8ArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedArtistTracks($listLength,$limit,getMinRating(8),getMaxRating(8));
}

sub getRated9ArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedArtistsWeb($params,$listLength,getMinRating(9),getMaxRating(9));
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
    my %currentstatisticlinks = (
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated9ArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedArtistTracks($listLength,$limit,getMinRating(9),getMaxRating(9));
}

sub getRated10ArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	getMostPlayedArtistsWeb($params,$listLength,getMinRating(10),getMaxRating(10));
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
    my %currentstatisticlinks = (
    	'artist' => 'topratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getRated10ArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	return getMostPlayedArtistTracks($listLength,$limit,getMinRating(10),getMaxRating(10));
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
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.rating>$minrating and track_statistics.rating<=$maxrating group by tracks.url order by track_statistics.rating desc, track_statistics.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'album'})) {
		my $album = $params->{'album'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and tracks.album=$album and track_statistics.rating>$minrating and track_statistics.rating<=$maxrating order by track_statistics.rating desc, track_statistics.playCount desc,$orderBy;";
	    $params->{'statisticparameters'} = "&album=$album";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.rating>$minrating and track_statistics.rating<=$maxrating order by track_statistics.rating desc, track_statistics.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.year=$year and tracks.audio=1 and track_statistics.rating>$minrating and track_statistics.rating<=$maxrating order by track_statistics.rating desc, track_statistics.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.rating>$minrating and track_statistics.rating<=$maxrating order by track_statistics.rating desc, track_statistics.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.rating>$minrating and track_statistics.rating<=$maxrating order by track_statistics.rating desc, track_statistics.playCount desc,$orderBy limit $listLength;";
	}
    Plugins::TrackStat::Statistics::Base::getTracksWeb($sql,$params);
}

sub getMostPlayedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $minrating = shift;
	my $maxrating = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		$sql = "select tracks.id from tracks left join track_statistics on tracks.url = track_statistics.url left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where tracks.audio=1 and dynamicplaylist_history.id is null and track_statistics.rating>$minrating and track_statistics.rating<=$maxrating order by track_statistics.rating desc, track_statistics.playCount desc,$orderBy limit $listLength;";
	}else {
		$sql = "select tracks.id from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and track_statistics.rating>$minrating and track_statistics.rating<=$maxrating order by track_statistics.rating desc, track_statistics.playCount desc,$orderBy limit $listLength;";
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
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where tracks.year=$year group by tracks.album having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
}

sub getMostPlayedAlbumTracks {
	my $listLength = shift;
	my $limit = shift;
	$limit = undef;
	my $minrating = shift;
	my $maxrating = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by tracks.album having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	}else {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($sql,$limit);
}

sub getMostPlayedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $minrating = shift;
	my $maxrating = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor where tracks.year=$year group by contributors.id having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
}

sub getMostPlayedArtistTracks {
	my $listLength = shift;
	my $limit = shift;
	$limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $minrating = shift;
	my $maxrating = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by contributors.id having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	}else {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having avgrating>$minrating and avgrating<=$maxrating order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getArtistTracks($sql,$limit);
}


1;

__END__
