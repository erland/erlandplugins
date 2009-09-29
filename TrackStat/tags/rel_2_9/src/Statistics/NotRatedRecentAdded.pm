#         TrackStat::Statistics::NotRatedRecentAdded module
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
                   
package Plugins::TrackStat::Statistics::NotRatedRecentAdded;

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
    
	if(UNIVERSAL::can("Slim::Schema","sourceInformation")) {
		my ($source,$username,$password);
		($driver,$source,$username,$password) = Slim::Schema->sourceInformation;
	}

    if($driver eq 'mysql') {
    	$distinct = 'distinct';
    }
}

sub getStatisticItems {
	my %statistics = (
		notratedrecentadded => {
			'webfunction' => \&getNotRatedRecentAddedTracksWeb,
			'playlistfunction' => \&getNotRatedRecentAddedTracks,
			'id' =>  'notratedrecentadded',
			'namefunction' => \&getNotRatedRecentAddedTracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isNotRatedRecentAddedTracksValidInContext
		},
		notratedrecentaddedartists => {
			'webfunction' => \&getNotRatedRecentAddedArtistsWeb,
			'playlistfunction' => \&getNotRatedRecentAddedArtistTracks,
			'id' =>  'notratedrecentaddedartists',
			'namefunction' => \&getNotRatedRecentAddedArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isNotRatedRecentAddedArtistsValidInContext
		},
		notratedrecentaddedalbums => {
			'webfunction' => \&getNotRatedRecentAddedAlbumsWeb,
			'playlistfunction' => \&getNotRatedRecentAddedAlbumTracks,
			'id' =>  'notratedrecentaddedalbums',
			'namefunction' => \&getNotRatedRecentAddedAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isNotRatedRecentAddedAlbumsValidInContext
		},
		notratednotrecentadded => {
			'webfunction' => \&getNotRatedNotRecentAddedTracksWeb,
			'playlistfunction' => \&getNotRatedNotRecentAddedTracks,
			'id' =>  'notratednotrecentadded',
			'namefunction' => \&getNotRatedNotRecentAddedTracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isNotRatedNotRecentAddedTracksValidInContext
		},
		notratednotrecentaddedartists => {
			'webfunction' => \&getNotRatedNotRecentAddedArtistsWeb,
			'playlistfunction' => \&getNotRatedNotRecentAddedArtistTracks,
			'id' =>  'notratednotrecentaddedartists',
			'namefunction' => \&getNotRatedNotRecentAddedArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isNotRatedNotRecentAddedArtistsValidInContext
		},
		notratednotrecentaddedalbums => {
			'webfunction' => \&getNotRatedNotRecentAddedAlbumsWeb,
			'playlistfunction' => \&getNotRatedNotRecentAddedAlbumTracks,
			'id' =>  'notratednotrecentaddedalbums',
			'namefunction' => \&getNotRatedNotRecentAddedAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isNotRatedNotRecentAddedAlbumsValidInContext
		}

	);
	return \%statistics;
}

sub getNotRatedRecentAddedTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED');
	}
}

sub isNotRatedRecentAddedTracksValidInContext {
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
sub getNotRatedRecentAddedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	my $recentadded = getRecentAddedTime();
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select tracks.id,t1.playCount,t1.added,t1.lastPlayed,t1.rating from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributor_track.contributor=$artist left join track_statistics t1 on tracks.url=t1.url left join track_statistics t2 on tracks.url=t2.url and t2.rating>0 where tracks.audio=1 and t2.url is null and t1.added$recentaddedcmp$recentadded group by tracks.url order by t1.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'album'})) {
		my $album = $params->{'album'};
	    $sql = "select tracks.id,t1.playCount,t1.added,t1.lastPlayed,t1.rating from tracks left join track_statistics t1 on tracks.url=t1.url left join track_statistics t2 on tracks.url=t2.url and t2.rating>0 where tracks.audio=1 and tracks.album=$album and t2.url is null and t1.added$recentaddedcmp$recentadded order by t1.playCount desc,$orderBy;";
	    $params->{'statisticparameters'} = "&album=$album";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select tracks.id,t1.playCount,t1.added,t1.lastPlayed,t1.rating from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics t1 on tracks.url=t1.url left join track_statistics t2 on tracks.url=t2.url and t2.rating>0 where tracks.audio=1 and t2.url is null and t1.added$recentaddedcmp$recentadded order by t1.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select tracks.id,t1.playCount,t1.added,t1.lastPlayed,t1.rating from tracks left join track_statistics t1 on tracks.url=t1.url left join track_statistics t2 on tracks.url=t2.url and t2.rating>0 where tracks.audio=1 and t2.url is null and tracks.year=$year and t1.added$recentaddedcmp$recentadded order by t1.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
	    $sql = "select tracks.id,t1.playCount,t1.added,t1.lastPlayed,t1.rating from tracks join playlist_track on tracks.url=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics t1 on tracks.url=t1.url left join track_statistics t2 on tracks.url=t2.url and t2.rating>0 where tracks.audio=1 and t2.url is null and t1.added$recentaddedcmp$recentadded order by t1.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
	    $sql = "select tracks.id,t1.playCount,t1.added,t1.lastPlayed,t1.rating from tracks left join track_statistics t1 on tracks.url=t1.url left join track_statistics t2 on tracks.url=t2.url and t2.rating>0 where tracks.audio=1 and t2.url is null and t1.added$recentaddedcmp$recentadded order by t1.playCount desc,$orderBy limit $listLength;";
	}
    Plugins::TrackStat::Statistics::Base::getTracksWeb($sql,$params);
    if($recentaddedcmp eq '>') {
	    my %currentstatisticlinks = (
	    	'album' => 'notratedrecentadded',
	    	'artist' => 'notratedrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}else {
	    my %currentstatisticlinks = (
	    	'album' => 'notratednotrecentadded',
	    	'artist' => 'notratednotrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}
}

sub getNotRatedRecentAddedTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = shift;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $recentadded = getRecentAddedTime();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		my $clientid = $client->id;
		$sql = "select tracks.id from tracks left join track_statistics t1 on tracks.url=t1.url left join track_statistics t2 on tracks.url=t2.url and t2.rating>0 left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id and dynamicplaylist_history.client='$clientid' where tracks.audio=1 and dynamicplaylist_history.id is null and t2.url is null and t1.added$recentaddedcmp$recentadded order by t1.playCount desc,$orderBy limit $listLength;";
	}else {
		$sql = "select tracks.id from tracks left join track_statistics t1 on tracks.url=t1.url left join track_statistics t2 on tracks.url=t2.url and t2.rating>0 where tracks.audio=1 and t2.url is null and t1.added$recentaddedcmp$recentadded order by t1.playCount desc,$orderBy limit $listLength;";
	}
    return Plugins::TrackStat::Statistics::Base::getTracks($sql,$limit);
}


sub getNotRatedNotRecentAddedTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED');
	}
}

sub isNotRatedNotRecentAddedTracksValidInContext {
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

sub getNotRatedNotRecentAddedTracksWeb {
	my $params = shift;
	my $listLength = shift;

	getNotRatedRecentAddedTracksWeb($params,$listLength,'<');
}

sub getNotRatedNotRecentAddedTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = shift;
	
	return getNotRatedRecentAddedTracks($client,$listLength,$limit,'<');
}


sub getNotRatedRecentAddedAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDEDALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDEDALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDEDALBUMS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDEDALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDEDALBUMS');
	}
}

sub isNotRatedRecentAddedAlbumsValidInContext {
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


sub getNotRatedRecentAddedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	my $recentadded = getRecentAddedTime();
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where track_statistics.added$recentaddedcmp$recentadded group by tracks.album having avgrating=0 order by avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where track_statistics.added$recentaddedcmp$recentadded group by tracks.album having avgrating=0 order by avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where tracks.year=$year where track_statistics.added$recentaddedcmp$recentadded group by tracks.album having avgrating=0 order by avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join playlist_track on tracks.url=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where track_statistics.added$recentaddedcmp$recentadded group by tracks.album having avgrating=0 order by avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where track_statistics.added$recentaddedcmp$recentadded group by tracks.album having avgrating=0 order by avgcount desc,$orderBy limit $listLength";
    }
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
    if($recentaddedcmp eq '>') {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'notratedrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_FORALBUM_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'album' => 'notratedrecentadded',
	    	'artist' => 'notratedrecentaddedalbums',
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}else {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'notratednotrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_FORALBUM_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'album' => 'notratednotrecentadded',
	    	'artist' => 'notratednotrecentaddedalbums',
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}
}

sub getNotRatedRecentAddedAlbumTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = shift;
	$limit = undef;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $recentadded = getRecentAddedTime();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		my $clientid = $client->id;
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id and dynamicplaylist_history.client='$clientid' where dynamicplaylist_history.id is null and track_statistics.added$recentaddedcmp$recentadded group by tracks.album having avgrating=0 order by avgcount desc,$orderBy limit $listLength";
	}else {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where track_statistics.added$recentaddedcmp$recentadded group by tracks.album having avgrating=0 order by avgcount desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($client,$sql,$limit);
}

sub getNotRatedNotRecentAddedAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDEDALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDEDALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDEDALBUMS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDEDALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDEDALBUMS');
	}
}

sub isNotRatedNotRecentAddedAlbumsValidInContext {
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

sub getNotRatedNotRecentAddedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;

	getNotRatedRecentAddedAlbumsWeb($params,$listLength,'<');
}

sub getNotRatedNotRecentAddedAlbumTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = shift;
	
	return getNotRatedRecentAddedAlbumTracks($client,$listLength,$limit,'<');
}


sub getNotRatedRecentAddedArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDEDARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDEDARTISTS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDEDARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDEDARTISTS');
	}
}

sub isNotRatedRecentAddedArtistsValidInContext {
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

sub getNotRatedRecentAddedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	my $recentadded = getRecentAddedTime();
	if(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor where track_statistics.added$recentaddedcmp$recentadded group by contributors.id having avgrating=0 order by sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor where tracks.year=$year and track_statistics.added$recentaddedcmp$recentadded group by contributors.id having avgrating=0 order by sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join playlist_track on tracks.url=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor where track_statistics.added$recentaddedcmp$recentadded group by contributors.id having avgrating=0 order by sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor where track_statistics.added$recentaddedcmp$recentadded group by contributors.id having avgrating=0 order by sumcount desc,$orderBy limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
    if($recentaddedcmp eq '>') {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'notratedrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDED_FORARTIST_SHORT')
	    };
	    push @statisticlinks, {
	    	'id' => 'notratedrecentaddedalbums',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDRECENTADDEDALBUMS_FORARTIST_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'artist' => 'notratedrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}else {
	    my @statisticlinks = ();
	    push @statisticlinks, {
	    	'id' => 'notratednotrecentadded',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDED_FORARTIST_SHORT')
	    };
	    push @statisticlinks, {
	    	'id' => 'notratednotrecentaddedalbums',
	    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDEDALBUMS_FORARTIST_SHORT')
	    };
	    $params->{'substatisticitems'} = \@statisticlinks;
	    my %currentstatisticlinks = (
	    	'artist' => 'notratednotrecentaddedalbums'
	    );
	    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
	}
}

sub getNotRatedRecentAddedArtistTracks {
	my $client = shift;
	my $listLength = shift;
	my $limit = shift;
	my $recentaddedcmp = shift;
	if(!defined($recentaddedcmp)) {
		$recentaddedcmp = '>';
	}
	my $recentadded = getRecentAddedTime();
	$limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		my $clientid = $client->id;
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id and dynamicplaylist_history.client='$clientid' where dynamicplaylist_history.id is null and track_statistics.added$recentaddedcmp$recentadded group by contributors.id having avgrating=0 order by sumcount desc,$orderBy limit $listLength";
	}else {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor where track_statistics.added$recentaddedcmp$recentadded group by contributors.id having avgrating=0 order by sumcount desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getArtistTracks($client,$sql,$limit);
}


sub getNotRatedNotRecentAddedArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDEDARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDEDARTISTS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDEDARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDNOTRECENTADDEDARTISTS');
	}
}

sub isNotRatedNotRecentAddedArtistsValidInContext {
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

sub getNotRatedNotRecentAddedArtistsWeb {
	my $params = shift;
	my $listLength = shift;

	getNotRatedRecentAddedArtistsWeb($params,$listLength,'<');
}


sub getNotRatedNotRecentAddedArtistTracks {
	my $client = shift;
	my $listLength = shift;

	return getNotRatedRecentAddedArtistTracks($client,$listLength,undef,'<');
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
