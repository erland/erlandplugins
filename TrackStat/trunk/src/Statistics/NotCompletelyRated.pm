#         TrackStat::Statistics::NotCompletelyRated module
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
                   
package Plugins::TrackStat::Statistics::NotCompletelyRated;

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
		notcompletelyratedartists => {
			'webfunction' => \&getNotCompletelyRatedArtistsWeb,
			'playlistfunction' => \&getNotCompletelyRatedArtistTracks,
			'id' =>  'notcompletelyratedartists',
			'namefunction' => \&getNotCompletelyRatedArtistsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP')]],
			'contextfunction' => \&isNotCompletelyRatedArtistsValidInContext
		},
		notcompletelyratedalbums => {
			'webfunction' => \&getNotCompletelyRatedAlbumsWeb,
			'playlistfunction' => \&getNotCompletelyRatedAlbumTracks,
			'id' =>  'notcompletelyratedalbums',
			'namefunction' => \&getNotCompletelyRatedAlbumsName,
			'groups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP'),string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATED_GROUP')]],
			'statisticgroups' => [[string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATED_GROUP')],[string('PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP')]],
			'contextfunction' => \&isNotCompletelyRatedAlbumsValidInContext
		}
	);
	return \%statistics;
}

sub getNotCompletelyRatedAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $artist = Plugins::TrackStat::Storage::objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->name,'utf8');
	}elsif(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDALBUMS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDALBUMS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDALBUMS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDALBUMS');
	}
}
sub isNotCompletelyRatedAlbumsValidInContext {
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

sub getNotCompletelyRatedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id where tracks.year=$year group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,$orderBy limit $listLength";
    }
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'toprated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'album' => 'toprated',
    	'artist' => 'notcompletelyratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getNotCompletelyRatedAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist_norepeat")) {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,$orderBy limit $listLength";
	}else {
		$sql = "select albums.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by avgcount desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($sql,$limit);
}

sub getNotCompletelyRatedArtistsName {
	my $params = shift;
	if(defined($params->{'genre'})) {
	    my $genre = Plugins::TrackStat::Storage::objectForId('genre',$params->{'genre'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDARTISTS_FORGENRE')." ".Slim::Utils::Unicode::utf8decode($genre->name,'utf8');
	}elsif(defined($params->{'year'})) {
	    my $year = $params->{'year'};
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDARTISTS_FORYEAR')." ".$year;
	}elsif(defined($params->{'playlist'})) {
	    my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$params->{'playlist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDARTISTS_FORPLAYLIST')." ".Slim::Utils::Unicode::utf8decode($playlist->title,'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDARTISTS');
	}
}

sub isNotCompletelyRatedArtistsValidInContext {
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

sub getNotCompletelyRatedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'genre'})) {
		my $genre = $params->{'genre'};
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join genre_track on tracks.id=genre_track.track and genre_track.genre=$genre left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&genre=$genre";
	}elsif(defined($params->{'year'})) {
		my $year = $params->{'year'};
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor where tracks.year=$year group by contributors.id having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&year=$year";
	}elsif(defined($params->{'playlist'})) {
		my $playlist = $params->{'playlist'};
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks join playlist_track on tracks.id=playlist_track.track and playlist_track.playlist=$playlist left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&playlist=$playlist";
	}else {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,$orderBy limit $listLength";
	}
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'notrated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATED_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'notcompletelyratedalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
    my %currentstatisticlinks = (
    	'artist' => 'notcompletelyratedalbums'
    );
    $params->{'currentstatisticitems'} = \%currentstatisticlinks;
}

sub getNotCompletelyRatedArtistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist_norepeat")) {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null group by contributors.id having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,$orderBy limit $listLength";
	}else {
		$sql = "select contributors.id,avg(case when track_statistics.rating is null then 60 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having min(case when track_statistics.rating is null then 0 else track_statistics.rating end)=0 order by sumcount desc,$orderBy limit $listLength";
	}
    return Plugins::TrackStat::Statistics::Base::getArtistTracks($sql,$limit);
}

sub strings()
{
	return "
PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDALBUMS
	EN	Not completely rated albums

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDALBUMS_FORARTIST
	EN	Not completely rated albums by: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDALBUMS_FORGENRE_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDALBUMS_FORGENRE
	EN	Not completely rated albums in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDALBUMS_FORYEAR_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDALBUMS_FORYEAR
	EN	Not completely rated albums from: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDALBUMS_FORPLAYLIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDALBUMS_FORPLAYLIST
	EN	Not completely rated albums in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDARTISTS
	EN	Not completely rated artists

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDARTISTS_FORGENRE_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDARTISTS_FORGENRE
	EN	Not completely rated artists in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDARTISTS_FORYEAR_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDARTISTS_FORYEAR
	EN	Not completely rated artists from: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDARTISTS_FORPLAYLIST_SHORT
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATEDARTISTS_FORPLAYLIST
	EN	Not completely rated artists in: 

PLUGIN_TRACKSTAT_SONGLIST_NOTCOMPLETELYRATED_GROUP
	EN	Not completely rated
";
}

1;

__END__
