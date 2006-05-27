#         TrackStat::Statistics::NotRated module
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
                   
package Plugins::TrackStat::Statistics::NotRated;

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
		notrated => {
			'webfunction' => \&getNotRatedTracksWeb,
			'playlistfunction' => \&getNotRatedTracks,
			'id' =>  'notrated',
			'namefunction' => \&getNotRatedTracksName
		},
		notratedartists => {
			'webfunction' => \&getNotRatedArtistsWeb,
			'playlistfunction' => \&getNotRatedArtistTracks,
			'id' =>  'notratedartists',
			'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDARTISTS')
		},
		notratedalbums => {
			'webfunction' => \&getNotRatedAlbumsWeb,
			'playlistfunction' => \&getNotRatedAlbumTracks,
			'id' =>  'notratedalbums',
			'namefunction' => \&getNotRatedAlbumsName
		}
	);
	return \%statistics;
}

sub getNotRatedTracksName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $artist = $ds->objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATED_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->{name},'utf8');
	}elsif(defined($params->{'album'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $album = $ds->objectForId('album',$params->{'album'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATED_FORALBUM')." ".Slim::Utils::Unicode::utf8decode($album->{title},'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATED');
	}
}

sub getNotRatedTracksWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
	    $sql = "select tracks.url,t1.playCount,t1.added,t1.lastPlayed,t1.rating from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist left join track_statistics t1 on tracks.url=t1.url left join track_statistics t2 on tracks.url=t2.url and t2.rating>0 where tracks.audio=1 and t2.url is null order by t1.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}elsif(defined($params->{'album'})) {
		my $album = $params->{'album'};
	    $sql = "select tracks.url,t1.playCount,t1.added,t1.lastPlayed,t1.rating from tracks left join track_statistics t1 on tracks.url=t1.url left join track_statistics t2 on tracks.url=t2.url and t2.rating>0 where tracks.audio=1 and tracks.album=$album and t2.url is null order by t1.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	    $params->{'statisticparameters'} = "&album=$album";
	}else {
	    $sql = "select tracks.url,t1.playCount,t1.added,t1.lastPlayed,t1.rating from tracks left join track_statistics t1 on tracks.url=t1.url left join track_statistics t2 on tracks.url=t2.url and t2.rating>0 where tracks.audio=1 and t2.url is null order by t1.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
	}
    Plugins::TrackStat::Statistics::Base::getTracksWeb($sql,$params);
}

sub getNotRatedTracks {
	my $listLength = shift;
	my $limit = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select tracks.url from tracks left join track_statistics t1 on tracks.url=t1.url left join track_statistics t2 on tracks.url=t2.url and t2.rating>0 where tracks.audio=1 and t2.url is null order by t1.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    return Plugins::TrackStat::Statistics::Base::getTracks($sql,$limit);
}

sub getNotRatedAlbumsName {
	my $params = shift;
	if(defined($params->{'artist'})) {
	    my $ds = Slim::Music::Info::getCurrentDataStore();
	    my $artist = $ds->objectForId('artist',$params->{'artist'});
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDALBUMS_FORARTIST')." ".Slim::Utils::Unicode::utf8decode($artist->{name},'utf8');
	}else {
		return string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDALBUMS');
	}
}

sub getNotRatedAlbumsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
	my $sql;
	if(defined($params->{'artist'})) {
		my $artist = $params->{'artist'};
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.contributor=$artist left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having avgrating=0 order by avgcount desc,$orderBy limit $listLength";
	    $params->{'statisticparameters'} = "&artist=$artist";
	}else {
    	$sql = "select albums.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having avgrating=0 order by avgcount desc,$orderBy limit $listLength";
    }
    Plugins::TrackStat::Statistics::Base::getAlbumsWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'notrated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATED_FORALBUM_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
}

sub getNotRatedAlbumTracks {
	my $listLength = shift;
	my $limit = undef;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select albums.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,avg(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as avgcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded  from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album having avgrating=0 order by avgcount desc,$orderBy limit $listLength";
    return Plugins::TrackStat::Statistics::Base::getAlbumTracks($sql,$limit);
}

sub getNotRatedArtistsWeb {
	my $params = shift;
	my $listLength = shift;
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having avgrating=0 order by sumcount desc,$orderBy limit $listLength";
    Plugins::TrackStat::Statistics::Base::getArtistsWeb($sql,$params);
    my @statisticlinks = ();
    push @statisticlinks, {
    	'id' => 'notrated',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATED_FORARTIST_SHORT')
    };
    push @statisticlinks, {
    	'id' => 'notratedalbums',
    	'name' => string('PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDALBUMS_FORARTIST_SHORT')
    };
    $params->{'substatisticitems'} = \@statisticlinks;
}

sub getNotRatedArtistTracks {
	my $listLength = shift;
	my $limit = Plugins::TrackStat::Statistics::Base::getNumberOfTypeTracks();
	my $orderBy = Plugins::TrackStat::Statistics::Base::getRandomString();
    my $sql = "select contributors.id,avg(case when track_statistics.rating is null then 0 else track_statistics.rating end) as avgrating,sum(case when track_statistics.playCount is null then tracks.playCount else track_statistics.playCount end) as sumcount,max(track_statistics.lastPlayed) as lastplayed, max(track_statistics.added) as maxadded from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id having avgrating=0 order by sumcount desc,$orderBy limit $listLength";
    return Plugins::TrackStat::Statistics::Base::getArtistTracks($sql,$limit);
}

sub strings()
{
	return "
PLUGIN_TRACKSTAT_SONGLIST_NOTRATED
	EN	Not rated songs

PLUGIN_TRACKSTAT_SONGLIST_NOTRATED_FORARTIST_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_NOTRATED_FORARTIST
	EN	Not rated songs by: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATED_FORALBUM_SHORT
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_NOTRATED_FORALBUM
	EN	Not rated songs from: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDALBUMS
	EN	Not rated albums

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDALBUMS_FORARTIST_SHORT
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDALBUMS_FORARTIST
	EN	Not rated albums by: 

PLUGIN_TRACKSTAT_SONGLIST_NOTRATEDARTISTS
	EN	Not rated artists
";
}

1;

__END__
