#         TrackStat::Statistics::PartlyPlayed module
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
                   
package Plugins::TrackStat::Statistics::PartlyPlayed;

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
		partlyplayedartists => {
			'webfunction' => \&getPartlyPlayedArtistsWeb,
			'playlistfunction' => \&getPartlyPlayedArtistTracks,
			'id' =>  'partlyplayedartists',
			'namefunction' => \&getPartlyPlayedArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_PARTLYPLAYED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_PARTLYPLAYED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_PARTLYPLAYED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isPartlyPlayedArtistsValidInContext
		},
		partlyplayedalbums => {
			'webfunction' => \&getPartlyPlayedAlbumsWeb,
			'playlistfunction' => \&getPartlyPlayedAlbumTracks,
			'id' =>  'partlyplayedalbums',
			'namefunction' => \&getPartlyPlayedAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_PARTLYPLAYED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_PARTLYPLAYED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_PARTLYPLAYED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isPartlyPlayedAlbumsValidInContext
		}
	);
	return \%statistics;
}

sub getPartlyPlayedAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_PARTLYPLAYEDALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_PARTLYPLAYEDALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_PARTLYPLAYEDALBUMS_FORYEAR')." ".$year;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_PARTLYPLAYEDALBUMS');
	}
}

sub isPartlyPlayedAlbumsValidInContext {
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

sub getPartlyPlayedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	my $minalbumtext = "";
	my $minalbumlimit = $prefs->get("min_album_tracks");
	if($minalbumlimit && $minalbumlimit>0) {
		$minalbumtext = "and count(tracks.id)>=".$minalbumlimit." ";
	}
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having min(ifnull(track_statistics.playCount,0))=0 order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having min(ifnull(track_statistics.playCount,0))=0 $minalbumtext order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id tracks.year=$year group by tracks.album having min(ifnull(track_statistics.playCount,0))=0 $minalbumtext order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
	}else {
	    $sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having min(ifnull(track_statistics.playCount,0))=0 $minalbumtext order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'notplayed',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTPLAYED_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'album' => 'notplayed',
    	'artist' => 'partlyplayedalbums',
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getPartlyPlayedAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $minalbumtext = "";
	my $minalbumlimit = $prefs->get("min_album_tracks");
	if($minalbumlimit && $minalbumlimit>0) {
		$minalbumtext = "and count(tracks.id)>=".$minalbumlimit." ";
	}
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by tracks.album having min(ifnull(track_statistics.playCount,0))=0 $minalbumtext order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	}else {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating, avg(ifnull(track_statistics.playCount,0)) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having min(ifnull(track_statistics.playCount,0))=0 $minalbumtext order by avgrating desc,avgcount desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($sql,$limit);
}

sub getPartlyPlayedArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_PARTLYPLAYEDARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_PARTLYPLAYEDARTISTS_FORYEAR')." ".$year;
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_PARTLYPLAYEDARTISTS');
	}
}

sub isPartlyPlayedArtistsValidInContext {
	my $params = shift;
	if(defined($params->{'genre'})) {
		return 1;
	}elsif(defined($params->{'year'})) {
		return 1;
	}
	return 0;
}

sub getPartlyPlayedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	my $minartisttext = "";
	my $minartistlimit = $prefs->get("min_artist_tracks");
	if($minartistlimit && $minartistlimit>0) {
		$minartisttext = "and count(tracks.id)>=".$minartistlimit." ";
	}
	if(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having min(ifnull(track_statistics.playCount,0))=0 $minartisttext order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor where tracks.year=$year group by contributors.id having min(ifnull(track_statistics.playCount,0))=0 $minartisttext order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
	}else {
	    $sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having min(ifnull(track_statistics.playCount,0))=0 $minartisttext order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'notplayed',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTPLAYED_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'partlyplayedalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_PARTLYPLAYEDALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'artist' => 'partlyplayedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getPartlyPlayedArtistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $minartisttext = "";
	my $minartistlimit = $prefs->get("min_artist_tracks");
	if($minartistlimit && $minartistlimit>0) {
		$minartisttext = "and count(tracks.id)>=".$minartistlimit." ";
	}
	my $sql;
	if($prefs->get("dynamicplaylist_norepeat")) {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by contributors.id having min(ifnull(track_statistics.playCount,0))=0 $minartisttext order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	}else {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(ifnull(track_statistics.playCount,0)) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributors.id = contributor_track.contributor group by contributors.id having min(ifnull(track_statistics.playCount,0))=0 $minartisttext order by avgrating desc,sumcount desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getArtistTracks($sql,$limit);
}


1;

__END__
