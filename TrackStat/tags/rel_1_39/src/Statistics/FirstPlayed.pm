#         TrackStat::Statistics::FirstPlayed module
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
                   
package Plugins::TrackStat::Statistics::FirstPlayed;

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
		firstplayed => {
			'webfunction' => \&getFirstPlayedTracksWeb,
			'playlistfunction' => \&getFirstPlayedTracks,
			'id' =>  'firstplayed',
			'namefunction' => \&getFirstPlayedTracksName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP')]],
			'contextfunction' => \&isFirstPlayedTracksValidInContext
		},
		firstplayedalbums => {
			'webfunction' => \&getFirstPlayedAlbumsWeb,
			'playlistfunction' => \&getFirstPlayedAlbumTracks,
			'id' =>  'firstplayedalbums',
			'namefunction' => \&getFirstPlayedAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isFirstPlayedAlbumsValidInContext
		},
		firstplayedartists => {
			'webfunction' => \&getFirstPlayedArtistsWeb,
			'playlistfunction' => \&getFirstPlayedArtistTracks,
			'id' =>  'firstplayedartists',
			'namefunction' => \&getFirstPlayedArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isFirstPlayedArtistsValidInContext
		},
	);
	return \%statistics;
}

sub getFirstPlayedTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'album'})) {
	    my $album = Plugins::TrackStat::Storage::objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->title,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED_FORYEAR')." ".$year;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED');
	}
}
sub isFirstPlayedTracksValidInContext {
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
sub getFirstPlayedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist and contributor_track.role in (1,4,5,6) left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 group by tracks.url order by track_statistics.lastPlayed asc,tracks.lastPlayed asc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'album'})) {
		my $album = $params->{'album'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 and tracks.album=$album order by track_statistics.lastPlayed asc,tracks.lastPlayed asc,$orderBy;";
	    $params->{'statisticparameters'} = "&album=$album";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.lastPlayed asc,tracks.lastPlayed asc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.year=$year and tracks.audio=1 order by track_statistics.lastPlayed asc,tracks.lastPlayed asc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&year=$year";
	}else {
	    $sql = "select tracks.id,track_statistics.playCount,track_statistics.added,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.lastPlayed asc,tracks.lastPlayed asc,$orderBy limit $listLength;";
	}
    Plugins::TrackStat::Statistics::Base::getTracksWeb($sql,$params);
    my %currentstatisticlinks = (
    	'album' => 'firstplayed',
    	'artist' => 'firstplayedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getFirstPlayedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist_norepeat")) {
		$sql = "select tracks.id from tracks left join track_statistics on tracks.url = track_statistics.url left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where tracks.audio=1 and dynamicplaylist_history.id is null order by track_statistics.lastPlayed asc,tracks.lastPlayed asc,$orderBy limit $listLength;";
	}else {
		$sql = "select tracks.id from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.lastPlayed asc,tracks.lastPlayed asc,$orderBy limit $listLength;";
	}
    return Plugins::TrackStat::Statistics::Base::getTracks($sql,$limit);
}

sub getFirstPlayedAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDALBUMS_FORYEAR')." ".$year;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDALBUMS');
	}
}
sub isFirstPlayedAlbumsValidInContext {
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

sub getFirstPlayedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	my $minalbumtext = "";
	my $minalbumlimit = Slim::Utils::Prefs::get("plugin_trackstat_min_album_tracks");
	if($minalbumlimit && $minalbumlimit>0) {
		$minalbumtext = "having count(tracks.id)>=".$minalbumlimit." ";
	}
		
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as maxlastplayed, max(track_statistics.added) as maxadded from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist and contributor_track.role in (1,4,5,6) left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by maxlastplayed asc, avgcount desc,avgrating desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as maxlastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album $minalbumtext order by maxlastplayed asc, avgcount desc,avgrating desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as maxlastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where tracks.year=$year group by tracks.album $minalbumtext order by maxlastplayed asc, avgcount desc,avgrating desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
	}else {
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as maxlastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album $minalbumtext order by maxlastplayed asc, avgcount desc,avgrating desc,$orderBy limit $listLength";
    }
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'firstplayed',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'album' => 'firstplayed'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getFirstPlayedAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $minalbumtext = "";
	my $minalbumlimit = Slim::Utils::Prefs::get("plugin_trackstat_min_album_tracks");
	if($minalbumlimit && $minalbumlimit>0) {
		$minalbumtext = "having count(tracks.id)>=".$minalbumlimit." ";
	}
	my $sql;
	if(Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist_norepeat")) {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as maxlastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by tracks.album $minalbumtext order by maxlastplayed asc, avgcount desc,avgrating desc,$orderBy limit $listLength";
	}else {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as maxlastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album $minalbumtext order by maxlastplayed asc, avgcount desc,avgrating desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($sql,$limit);
}

sub getFirstPlayedArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDARTISTS_FORYEAR')." ".$year;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDARTISTS');
	}
}
sub isFirstPlayedArtistsValidInContext {
	my $params = shift;
	if(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}
	return 0;
}

sub getFirstPlayedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	my $minartisttext = "";
	my $minartistlimit = Slim::Utils::Prefs::get("plugin_trackstat_min_artist_tracks");
	if($minartistlimit && $minartistlimit>0) {
		$minartisttext = "having count(tracks.id)>=".$minartistlimit." ";
	}
	if(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as maxlastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id $minartisttext order by maxlastplayed asc, sumcount desc,avgrating desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as maxlastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor where tracks.year=$year group by contributors.id $minartisttext order by maxlastplayed asc, sumcount desc,avgrating desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
	}else {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as maxlastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id $minartisttext order by maxlastplayed asc, sumcount desc,avgrating desc,$orderBy limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {    	
    	'id' => 'firstplayed',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED_FORARTIST_SHORT')
	};
    push @statisticlinks, {    	
    	'id' => 'firstplayedalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDALBUMS_FORARTIST_SHORT')
	};
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'artist' => 'firstplayedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getFirstPlayedArtistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $minartisttext = "";
	my $minartistlimit = Slim::Utils::Prefs::get("plugin_trackstat_min_artist_tracks");
	if($minartistlimit && $minartistlimit>0) {
		$minartisttext = "having count(tracks.id)>=".$minartistlimit." ";
	}
	my $sql;
	if(Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist_norepeat")) {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as maxlastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by contributors.id $minartisttext order by maxlastplayed asc, sumcount desc,avgrating desc,$orderBy limit $listLength";
	}else {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as maxlastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id $minartisttext order by maxlastplayed asc, sumcount desc,avgrating desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getArtistTracks($sql,$limit);
}

sub strings()
{
	return "
PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED
	EN	Songs played long ago

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED_FORALBUM_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED_FORALBUM
	EN	Songs played long ago from: 

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED_FORARTIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED_FORARTIST
	EN	Songs played long ago by: 

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED_FORGENRE_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED_FORGENRE
	EN	Songs played long ago in: 

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED_FORYEAR_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED_FORYEAR
	EN	Songs played long ago from: 

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDALBUMS
	EN	Albums played long ago

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDALBUMS_FORARTIST
	EN	Albums played long ago by: 

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDALBUMS_FORGENRE_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDALBUMS_FORGENRE
	EN	Albums played long ago in: 

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDALBUMS_FORYEAR_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDALBUMS_FORYEAR
	EN	Albums played long ago from: 

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDARTISTS
	EN	Artists played long ago

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDARTISTS_FORGENRE_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDARTISTS_FORGENRE
	EN	Artists played long ago in: 

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDARTISTS_FORYEAR_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYEDARTISTS_FORYEAR
	EN	Artists played long ago from: 

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED_GROUP
	EN	Played long ago
";
}

1;

__END__
