#         TrackStat::iTunes module
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
                   
package Plugins::TrackStat::Statistics::Base;

use Slim::Utils::Misc;

use Slim::Utils::Prefs;
use Date::Parse qw(str2time);
use Fcntl ':flock'; # import LOCK_* constants
use File::Spec::Functions qw(:ALL);
use File::Basename;
use XML::Parser;
use DBI qw(:sql_types);
use Class::Struct;
use FindBin qw($Bin);
use POSIX qw(strftime ceil);

if ($] > 5.007) {
	require Encode;
}

my $prefs = preferences('plugin.trackstat');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.trackstat',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_TRACKSTAT',
});

my $driver;
my $distinct;

sub init {
	$driver = $serverPrefs->get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
    if($driver eq 'mysql') {
    	$distinct = 'distinct';
    }
}


sub fisher_yates_shuffle {
    my $myarray = shift;  
    my $i = @$myarray;
    if(scalar(@$myarray)>1) {
	    while (--$i) {
	        my $j = int rand ($i+1);
	        @$myarray[$i,$j] = @$myarray[$j,$i];
	    }
    }
}

sub getRandomString {
    my $orderBy;
    if($driver eq 'mysql') {
    	$orderBy = "rand()";
    }else {
    	$orderBy = "random()";
    }
    return $orderBy;
}

sub getNumberOfTypeTracks() {
    my $artistListLength = $prefs->get("playlist_per_artist_length");
    if(!defined $artistListLength || $artistListLength==0) {
    	$artistListLength = 10;
    }
    return $artistListLength;
}	

sub saveMixerLinks {
	my $item = shift;
    if(defined($item->{'mixerlinks'})) {
        my $mixerlinks = $item->{'mixerlinks'};
        $item->{'mixerlinks'} = ();
        for my $it (keys %$mixerlinks) {
        	$item->{'mixerlinks'}{$it}=$mixerlinks->{$it};
        }
    }
}

sub displayAsHTML {
	my $type = shift;
	my $form = shift;
	my $item = shift;
	
	$item->displayAsHTML($form);
}

sub getLinkAttribute {
	my $attr = shift;
	if($attr eq 'artist') {
		$attr = 'contributor';
	}
	return $attr.'.id';
}

sub getTracksWeb {
	my $sql = shift;
	my $params = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	$log->debug("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	my $currenttrackstatitem = $params->{'currenttrackstatitem'};
	if(defined($currenttrackstatitem)) {
		my $parameters = $params->{'statisticparameters'};
		if(defined($parameters)) {
			$parameters .= "&currenttrackstatitem=$currenttrackstatitem";
			$params->{'statisticparameters'} = $parameters;
		}
	}
	eval {
		my $count = $sth->execute();
		$log->debug("Got $count items\n");

		my( $id, $playCount, $added, $lastPlayed, $rating );
		$sth->bind_columns( undef, \$id, \$playCount, \$added, \$lastPlayed, \$rating );
		my $itemNumber = 0;
		my %objects = ();
		my @objectIds = ();
		while( $sth->fetch() ) {
			$playCount = 0 if (!(defined($playCount)));
			$lastPlayed = 0 if (!(defined($lastPlayed)));
			$added = 0 if (!(defined($added)));
			$rating = 0 if (!(defined($rating)));
			my %objectStatisticInfo = (
				'lastPlayed' => $lastPlayed,
				'added' => $added,
				'playCount' => $playCount,
				'rating' => $rating
			);
			push @objectIds,$id;
			$objects{$id} = \%objectStatisticInfo;
		}
		my $objectItems = Plugins::TrackStat::Storage::objectsForId('track',\@objectIds);
		for my $object (@$objectItems) {
			$objects{$object->id}->{'itemobj'} = $object;
		}
		for my $objectId (@objectIds) {
			my $objectData = $objects{$objectId};
			my $track = $objectData->{'itemobj'};
			next unless defined $track;
		  	my %trackInfo = ();
			
			$trackInfo{'noTrackStatButton'} = 1;
			$trackInfo{'levelName'}  = 'track';
			displayAsHTML('track', \%trackInfo, $track);
		  	$trackInfo{'title'} = Slim::Music::Info::standardTitle(undef,$track);
		  	$trackInfo{'lastPlayed'} = $objectData->{'lastPlayed'};
		  	$trackInfo{'added'} = $objectData->{'added'};
			my $rating = $objectData->{'rating'};
			if($prefs->get("rating_10scale")) {
			  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+5)/10:0);
				$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/10);
			}else {
			  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
				$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
			}
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
			$trackInfo{'skinOverride'}     = $params->{'skinOverride'};
			$trackInfo{'song_count'}       = $objectData->{'playCount'};
			$trackInfo{'attributes'}       = '&'.getLinkAttribute('track').'='.$track->id;
			$trackInfo{'itemobj'}          = $track;
			$trackInfo{'listtype'} = 'track';
			if(defined($currenttrackstatitem) && $track->id == $currenttrackstatitem) {
				$trackInfo{'currentsong'} = 1;
			}
            		  	
			saveMixerLinks(\%trackInfo);

			push @{$params->{'browse_items'}},\%trackInfo;
			$itemNumber++;
		  
		}
		$log->debug("Returning $itemNumber items\n");
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
	    	$log->warn("Database error: $DBI::errstr\n");
	    }else {
	    	$log->warn("Database error: $@\n");
	    }
	}
	$sth->finish();
}

sub getTracks {
	my $sql = shift;
	my $limit = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	$log->debug("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	my @objectIds = ();
	eval {
		$sth->execute();
		my $id;
		$sth->bind_col( 1, \$id );
		while( $sth->fetch() ) {
			push @objectIds,$id;
		}
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
	    		$log->warn("Database error: $DBI::errstr\n");
	    	}else {
	    		$log->warn("Database error: $@\n");
		}
	}
	$sth->finish();
	fisher_yates_shuffle(\@objectIds);
	if(defined($limit) && scalar(@objectIds)>$limit) {
		my $entriesToRemove = scalar(@objectIds) - $limit;
		splice(@objectIds,0,$entriesToRemove);
	}
	my $objectItems = Plugins::TrackStat::Storage::objectsForId('track',\@objectIds);
	my %objects = ();
	for my $object (@$objectItems) {
		$objects{$object->id} = $object;
	}
	my @result = ();
	for my $objectId (@objectIds) {
	  	push @result, $objects{$objectId};
		$log->debug("Adding track: ".$objects{$objectId}->title."\n");
	}
	return \@result;
}

sub getAlbumsWeb {
	my $sql = shift;
	my $params = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	$log->debug("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	eval {
		my $count = $sth->execute();
		$log->debug("Got $count items\n");

		my( $id, $rating, $playCount, $lastPlayed, $added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount, \$lastPlayed, \$added );
		my $itemNumber = 0;
		my %objects = ();
		my @objectIds = ();
		while( $sth->fetch() ) {
			$playCount = 0 if (!(defined($playCount)));
			$lastPlayed = 0 if (!(defined($lastPlayed)));
			$added = 0 if (!(defined($added)));
			$rating = 0 if (!(defined($rating)));
			my %objectStatisticInfo = (
				'lastPlayed' => $lastPlayed,
				'added' => $added,
				'playCount' => $playCount,
				'rating' => $rating
			);
			push @objectIds,$id;
			$objects{$id} = \%objectStatisticInfo;
		}
		my $objectItems = Plugins::TrackStat::Storage::objectsForId('album',\@objectIds);
		for my $object (@$objectItems) {
			$objects{$object->id}->{'itemobj'} = $object;
		}
		for my $objectId (@objectIds) {
			my $objectData = $objects{$objectId};
			my $album = $objectData->{'itemobj'};
			next unless defined $album;
		  	my %trackInfo = ();
			
		  	$trackInfo{'album'} = $album->id;
			$trackInfo{'noTrackStatButton'} = 1;
			$trackInfo{'levelName'}  = 'album';
			displayAsHTML('album', \%trackInfo, $album);
		  	$trackInfo{'title'} = undef;
			my $rating = $objectData->{'rating'};
			if($prefs->get("rating_10scale")) {
			  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+5)/10:0);
				$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/10);
			}else {
			  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
				$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
			}
		  	$trackInfo{'lastPlayed'} = $objectData->{'lastPlayed'};
		  	$trackInfo{'added'} = $objectData->{'added'};
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
			$trackInfo{'skinOverride'}     = $params->{'skinOverride'};
			$trackInfo{'song_count'}       = ceil($objectData->{'playCount'});
			$trackInfo{'attributes'}       = '&'.getLinkAttribute('album').'='.$album->id;
			$trackInfo{'itemobj'}{'album'} = $album;
			$trackInfo{'listtype'} = 'album';
		  	
			saveMixerLinks(\%trackInfo);

		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
		$log->debug("Returning $itemNumber items\n");
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
		    	$log->warn("Database error: $DBI::errstr\n");
		}else {
			$log->warn("Database error: $@\n");
		}
	}
	$sth->finish();
}

sub getAlbumTracks {
	my $sql = shift;
	my $limit = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	$log->debug("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	my @result;
	eval {
		$sth->execute();
		my( $id, $rating, $playCount, $lastPlayed, $added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount, \$lastPlayed, \$added );
		my @albums;
		while( $sth->fetch() ) {
			push @albums, $id;
		}
		if(scalar(@albums)>0) {
			fisher_yates_shuffle(\@albums);
			$id = shift @albums;
			my $album = Plugins::TrackStat::Storage::objectForId('album',$id);
			$log->debug("Getting tracks for album: ".$album->title."\n");
			my $iterator = $album->tracks;
			for my $item ($iterator->slice(0,$iterator->count)) {
				push @result, $item;
			}
		}
		$log->debug("Got ".scalar(@result)." tracks\n");
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
			$log->warn("Database error: $DBI::errstr\n");
		}else {
			$log->warn("Database error: $@\n");
		}
	}
	$sth->finish();
	if(defined($limit)) {
		fisher_yates_shuffle(\@result);
		if(scalar(@result)>$limit) {
			my $entriesToRemove = scalar(@result) - $limit;
			splice(@result,0,$entriesToRemove);
		}
	}
	$log->debug("Returning ".scalar(@result)." tracks\n");
	return \@result;
}

sub getArtistsWeb {
	my $sql = shift;
	my $params = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	$log->debug("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	eval {
		my $count = $sth->execute();
		$log->debug("Got $count items\n");

		my( $id, $rating, $playCount,$lastPlayed,$added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount,\$lastPlayed,\$added );
		my $itemNumber = 0;
		my %objects = ();
		my @objectIds = ();
		while( $sth->fetch() ) {
			$playCount = 0 if (!(defined($playCount)));
			$lastPlayed = 0 if (!(defined($lastPlayed)));
			$added = 0 if (!(defined($added)));
			$rating = 0 if (!(defined($rating)));
			my %objectStatisticInfo = (
				'lastPlayed' => $lastPlayed,
				'added' => $added,
				'playCount' => $playCount,
				'rating' => $rating
			);
			push @objectIds,$id;
			$objects{$id} = \%objectStatisticInfo;
		}
		my $objectItems = Plugins::TrackStat::Storage::objectsForId('artist',\@objectIds);
		for my $object (@$objectItems) {
			$objects{$object->id}->{'itemobj'} = $object;
		}
		for my $objectId (@objectIds) {
			my $objectData = $objects{$objectId};
			my $artist = $objectData->{'itemobj'};
			next unless defined $artist;
		  	my %trackInfo = ();
			
		  	$trackInfo{'artist'} = $artist->id;
			$trackInfo{'noTrackStatButton'} = 1;
			$trackInfo{'levelName'}  = 'artist';
			displayAsHTML('artist', \%trackInfo, $artist);
		  	$trackInfo{'title'} = undef;
			my $rating = $objectData->{'rating'};
			if($prefs->get("rating_10scale")) {
			  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+5)/10:0);
			  	$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/10);
			}else {
			  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
			  	$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
			}
		  	$trackInfo{'lastPlayed'} = $objectData->{'lastPlayed'};
		  	$trackInfo{'added'} = $objectData->{'added'};
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
			$trackInfo{'skinOverride'}     = $params->{'skinOverride'};
			$trackInfo{'song_count'}       = ceil($objectData->{'playCount'});
			$trackInfo{'attributes'}       = '&'.getLinkAttribute('artist').'='.$artist->id;
			$trackInfo{'itemobj'}{'artist'} = $artist;
			$trackInfo{'listtype'} = 'artist';
            
			saveMixerLinks(\%trackInfo);
            
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
		$log->debug("Returning $itemNumber items\n");
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
			$log->warn("Database error: $DBI::errstr\n");
		}else {
			$log->warn("Database error: $@\n");
		}
	}
	$sth->finish();
}

sub getArtistTracks {
	my $sql = shift;
	my $limit = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	$log->debug("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	my @result;
	eval {
		$sth->execute();
		my( $id, $rating, $playCount,$lastPlayed,$added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount,\$lastPlayed,\$added);
		my @artists;
		while( $sth->fetch() ) {
			push @artists, $id;
		}
		if(scalar(@artists)>0) {
			fisher_yates_shuffle(\@artists);
			for (my $i = 0; $i < 2 && scalar(@result)<2; $i++) {
				$id = shift @artists;
				my $artist = Plugins::TrackStat::Storage::objectForId('artist',$id);

				$log->debug("Getting tracks for artist: ".$artist->name."\n");

				my $items;
				my $sthtracks;
				if($prefs->get("dynamicplaylist_norepeat")) {
					$sthtracks = $dbh->prepare("select tracks.id from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null and contributor_track.contributor=$id group by tracks.id order by rand() limit $limit");
				}else {
					$sthtracks = $dbh->prepare("select tracks.id from tracks join contributor_track on tracks.id=contributor_track.track and contributor_track.role in (1,4,5,6) where contributor_track.contributor=$id group by tracks.id order by rand() limit $limit");
				}
				$sthtracks->execute();
				my $trackId;
				$sthtracks->bind_columns(undef,\$trackId);
				my @trackIds = ();
				while( $sthtracks->fetch()) {
					push @trackIds,$trackId;
				}
				if(scalar(@trackIds)>0) {
					my @result = Slim::Schema->rs('Track')->search({ 'id' => { 'in' => \@trackIds } });
					$items = \@result;
				}
				for my $item (@$items) {
					push @result, $item;
				}
				$log->debug("Got ".scalar(@result)." tracks for ".$artist->name."\n");
			}
		}
		$log->debug("Got ".scalar(@result)." tracks\n");
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
			$log->warn("Database error: $DBI::errstr\n");
		}else {
			$log->warn("Database error: $@\n");
		}
	}
	$sth->finish();
	$log->debug("Returning ".scalar(@result)." tracks\n");
	return \@result;
}

sub getGenresWeb {
	my $sql = shift;
	my $params = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	$log->debug("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	eval {
		my $count = $sth->execute();
		$log->debug("Got $count items\n");

		my( $id, $rating, $playCount,$lastPlayed,$added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount,\$lastPlayed,\$added );
		my $itemNumber = 0;
		my %objects = ();
		my @objectIds = ();
		while( $sth->fetch() ) {
			$playCount = 0 if (!(defined($playCount)));
			$lastPlayed = 0 if (!(defined($lastPlayed)));
			$added = 0 if (!(defined($added)));
			$rating = 0 if (!(defined($rating)));
			my %objectStatisticInfo = (
				'lastPlayed' => $lastPlayed,
				'added' => $added,
				'playCount' => $playCount,
				'rating' => $rating
			);
			push @objectIds,$id;
			$objects{$id} = \%objectStatisticInfo;
		}
		my $objectItems = Plugins::TrackStat::Storage::objectsForId('genre',\@objectIds);
		for my $object (@$objectItems) {
			$objects{$object->id}->{'itemobj'} = $object;
		}
		for my $objectId (@objectIds) {
			my $objectData = $objects{$objectId};
			my $genre = $objectData->{'itemobj'};
			next unless defined $genre;
		  	my %trackInfo = ();
			
		  	$trackInfo{'genre'} = $id;
			$trackInfo{'noTrackStatButton'} = 1;
			$trackInfo{'levelName'}  = 'genre';
			displayAsHTML('genre', \%trackInfo, $genre);
		  	$trackInfo{'title'} = undef;
			my $rating = $objectData->{'rating'};
			if($prefs->get("rating_10scale")) {
			  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+5)/10:0);
				$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/10);
			}else {
			  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
				$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
			}
		  	$trackInfo{'lastPlayed'} = $objectData->{'lastPlayed'};
		  	$trackInfo{'added'} = $objectData->{'added'};
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
			$trackInfo{'skinOverride'}     = $params->{'skinOverride'};
			$trackInfo{'song_count'}       = ceil($objectData->{'playCount'});
			$trackInfo{'attributes'}       = '&'.getLinkAttribute('genre').'='.$genre->id;
			$trackInfo{'itemobj'}{'genre'} = $genre;
			$trackInfo{'listtype'} = 'genre';
            		  	
			saveMixerLinks(\%trackInfo);

		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
		$log->debug("Returning $itemNumber items\n");
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
			$log->warn("Database error: $DBI::errstr\n");
		}else {
			$log->warn("Database error: $@\n");
		}
	}
	$sth->finish();
}

sub getGenreTracks {
	my $sql = shift;
	my $limit = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	$log->debug("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	my @result;
	eval {
		$sth->execute();
		my( $id, $rating, $playCount,$lastPlayed,$added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount,\$lastPlayed,\$added);
		my @genres;
		while( $sth->fetch() ) {
			push @genres, $id;
		}
		if(scalar(@genres)>0) {
			fisher_yates_shuffle(\@genres);
			for (my $i = 0; $i < 2 && scalar(@result)<2; $i++) {
				$id = shift @genres;
				my $genre = Plugins::TrackStat::Storage::objectForId('genre',$id);

				$log->debug("Getting tracks for genre: ".$genre->name."\n");
				my $items;
				my $sthtracks;
				if($prefs->get("dynamicplaylist_norepeat")) {
					$sthtracks = $dbh->prepare("select tracks.id from tracks join genre_track on tracks.id=genre_track.track left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null and genre_track.genre=$id group by tracks.id order by rand() limit $limit");
				}else {
					$sthtracks = $dbh->prepare("select tracks.id from tracks join genre_track on tracks.id=genre_track.track where genre_track.genre=$id group by tracks.id order by rand() limit $limit");
				}
				$sthtracks->execute();
				my $trackId;
				$sthtracks->bind_columns(undef,\$trackId);
				my @trackIds = ();
				while( $sthtracks->fetch()) {
					push @trackIds,$trackId;
				}
				if(scalar(@trackIds)>0) {
					my @result = Slim::Schema->rs('Track')->search({ 'id' => { 'in' => \@trackIds } });
					$items = \@result;
				}
				for my $item (@$items) {
					push @result, $item;
				}
				$log->debug("Got ".scalar(@result)." tracks for ".$genre->name."\n");
			}
		}
		$log->debug("Got ".scalar(@result)." tracks\n");
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
			$log->warn("Database error: $DBI::errstr\n");
		}else {
			$log->warn("Database error: $@\n");
		}
	}
	$sth->finish();
	$log->debug("Returning ".scalar(@result)." tracks\n");
	return \@result;
}

sub getYearsWeb {
	my $sql = shift;
	my $params = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	$log->debug("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	eval {
		my $count = $sth->execute();
		$log->debug("Got $count items\n");

		my( $id, $rating, $playCount,$lastPlayed,$added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount,\$lastPlayed,\$added );
		my $itemNumber = 0;
		my %objects = ();
		my @objectIds = ();
		while( $sth->fetch() ) {
			$playCount = 0 if (!(defined($playCount)));
			$lastPlayed = 0 if (!(defined($lastPlayed)));
			$added = 0 if (!(defined($added)));
			$rating = 0 if (!(defined($rating)));
			my %objectStatisticInfo = (
				'lastPlayed' => $lastPlayed,
				'added' => $added,
				'playCount' => $playCount,
				'rating' => $rating
			);
			push @objectIds,$id;
			$objects{$id} = \%objectStatisticInfo;
		}
		my $objectItems = Plugins::TrackStat::Storage::objectsForId('year',\@objectIds);
		for my $object (@$objectItems) {
			$objects{$object->id}->{'itemobj'} = $object;
		}
		for my $objectId (@objectIds) {
			my $objectData = $objects{$objectId};
			my $year = $objectId;
		  	my %trackInfo = ();
			$trackInfo{'noTrackStatButton'} = 1;
			$trackInfo{'levelName'}  = 'year';
			my $yearobj = $objectData->{'itemobj'};
			displayAsHTML('year', \%trackInfo, $yearobj);
		  	$trackInfo{'title'} = undef;
			my $rating = $objectData->{'rating'};
			if($prefs->get("rating_10scale")) {
			  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+5)/10:0);
				$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/10);
			}else {
			  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
				$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
			}
		  	$trackInfo{'lastPlayed'} = $objectData->{'lastPlayed'};
		  	$trackInfo{'added'} = $objectData->{'added'};
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
			$trackInfo{'skinOverride'}     = $params->{'skinOverride'};
			$trackInfo{'song_count'}       = ceil($objectData->{'playCount'});
			$trackInfo{'attributes'}       = '&'.getLinkAttribute('year').'='.$year;
			$trackInfo{'itemobj'}{'year'} = $year;
			$trackInfo{'listtype'} = 'year';
            		  	
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
		$log->debug("Returning $itemNumber items\n");
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
			$log->warn("Database error: $DBI::errstr\n");
		}else {
			$log->warn("Database error: $@\n");
		}
	}
	$sth->finish();
}

sub getYearTracks {
	my $sql = shift;
	my $limit = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	$log->debug("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	my @result;
	eval {
		$sth->execute();
		my( $id, $rating, $playCount,$lastPlayed,$added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount,\$lastPlayed,\$added);
		my @years;
		while( $sth->fetch() ) {
			push @years, $id;
		}
		if(scalar(@years)>0) {
			fisher_yates_shuffle(\@years);
			for (my $i = 0; $i < 2 && scalar(@result)<2; $i++) {
				$id = shift @years;
				my $year = $id;

				$log->debug("Getting tracks for year: ".$year."\n");
				my $items;
				my $sthtracks;
				if($prefs->get("dynamicplaylist_norepeat")) {
					$sthtracks = $dbh->prepare("select tracks.id from tracks left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null and tracks.year=$id group by tracks.id order by rand() limit $limit");
				}else {
					$sthtracks = $dbh->prepare("select tracks.id from tracks where tracks.year=$id order by rand() limit $limit");
				}
				$sthtracks->execute();
				my $trackId;
				$sthtracks->bind_columns(undef,\$trackId);
				my @trackIds = ();
				while( $sthtracks->fetch()) {
					push @trackIds,$trackId;
				}
				if(scalar(@trackIds)>0) {
					my @result = Slim::Schema->rs('Track')->search({ 'id' => { 'in' => \@trackIds } });
					$items = \@result;
				}
				for my $item (@$items) {
					push @result, $item;
				}
				$log->debug("Got ".scalar(@result)." tracks for ".$year."\n");
			}
		}
		$log->debug("Got ".scalar(@result)." tracks\n");
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
			$log->warn("Database error: $DBI::errstr\n");
		}else {
			$log->warn("Database error: $@\n");
		}
	}
	$sth->finish();
	$log->debug("Returning ".scalar(@result)." tracks\n");
	return \@result;
}

sub getPlaylistsWeb {
	my $sql = shift;
	my $params = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	$log->debug("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	eval {
		my $count = $sth->execute();
		$log->debug("Got $count items\n");

		my( $id, $rating, $playCount,$lastPlayed,$added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount,\$lastPlayed,\$added );
		my $itemNumber = 0;
		my %objects = ();
		my @objectIds = ();
		while( $sth->fetch() ) {
			$playCount = 0 if (!(defined($playCount)));
			$lastPlayed = 0 if (!(defined($lastPlayed)));
			$added = 0 if (!(defined($added)));
			$rating = 0 if (!(defined($rating)));
			my %objectStatisticInfo = (
				'lastPlayed' => $lastPlayed,
				'added' => $added,
				'playCount' => $playCount,
				'rating' => $rating
			);
			push @objectIds,$id;
			$objects{$id} = \%objectStatisticInfo;
		}
		my $objectItems = Plugins::TrackStat::Storage::objectsForId('track',\@objectIds);
		for my $object (@$objectItems) {
			$objects{$object->id}->{'itemobj'} = $object;
		}
		for my $objectId (@objectIds) {
			my $objectData = $objects{$objectId};
			my $playlist = $objectData->{'itemobj'};
			next unless defined $playlist;
		  	my %trackInfo = ();
			
		  	$trackInfo{'playlist'} = $playlist->id;
			$trackInfo{'noTrackStatButton'} = 1;
			$trackInfo{'levelName'}  = 'playlist';
			displayAsHTML('playlist', \%trackInfo, $playlist);
		  	$trackInfo{'title'} = undef;
			my $rating = $objectData->{'rating'};
			if($prefs->get("rating_10scale")) {
			  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+5)/10:0);
			  	$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/10);
			}else {
			  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
			  	$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
			}
		  	$trackInfo{'lastPlayed'} = $objectData->{'lastPlayed'};
		  	$trackInfo{'added'} = $objectData->{'added'};
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
			$trackInfo{'skinOverride'}     = $params->{'skinOverride'};
			$trackInfo{'song_count'}       = ceil($objectData->{'playCount'});
			$trackInfo{'attributes'}       = '&'.getLinkAttribute('playlist').'='.$playlist->id;
			$trackInfo{'itemobj'}{'playlist'} = $playlist;
			$trackInfo{'listtype'} = 'playlist';
            
			saveMixerLinks(\%trackInfo);
            
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
		$log->debug("Returning $itemNumber items\n");
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
			$log->warn("Database error: $DBI::errstr\n");
		}else {
			$log->warn("Database error: $@\n");
		}
	}
	$sth->finish();
}

sub getPlaylistTracks {
	my $sql = shift;
	my $limit = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	$log->debug("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	my @result;
	eval {
		$sth->execute();
		my( $id, $rating, $playCount,$lastPlayed,$added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount,\$lastPlayed,\$added);
		my @artists;
		while( $sth->fetch() ) {
			push @artists, $id;
		}
		if(scalar(@artists)>0) {
			fisher_yates_shuffle(\@artists);
			for (my $i = 0; $i < 2 && scalar(@result)<2; $i++) {
				$id = shift @artists;
				my $playlist = Plugins::TrackStat::Storage::objectForId('track',$id);

				$log->debug("Getting tracks for playlist: ".$playlist->title."\n");

				my $items;
				my $sthtracks;
				if($prefs->get("dynamicplaylist_norepeat")) {
					$sthtracks = $dbh->prepare("select tracks.id from tracks join playlist_track on tracks.id=playlist_track.track left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id where dynamicplaylist_history.id is null and playlist_track.playlist=$id group by tracks.id order by rand() limit $limit");
				}else {
					$sthtracks = $dbh->prepare("select tracks.id from tracks join playlist_track on tracks.id=playlist_track.track where playlist_track.playlist=$id group by tracks.id order by rand() limit $limit");
				}
				$sthtracks->execute();
				my $trackId;
				$sthtracks->bind_columns(undef,\$trackId);
				my @trackIds = ();
				while( $sthtracks->fetch()) {
					push @trackIds,$trackId;
				}
				if(scalar(@trackIds)>0) {
					my @result = Slim::Schema->rs('Track')->search({ 'id' => { 'in' => \@trackIds } });
					$items = \@result;
				}
				for my $item (@$items) {
					push @result, $item;
				}
				$log->debug("Got ".scalar(@result)." tracks for ".$playlist->title."\n");
			}
		}
		$log->debug("Got ".scalar(@result)." tracks\n");
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
	    	$log->warn("Database error: $DBI::errstr\n");
	    }else {
	    	$log->warn("Database error: $@\n");
	    }
	}
	$sth->finish();
	$log->debug("Returning ".scalar(@result)." tracks\n");
	return \@result;
}


1;

__END__
