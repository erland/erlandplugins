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
my $driver;
my $distinct;

sub init {
	$driver = Slim::Utils::Prefs::get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
    if($driver eq 'mysql') {
    	$distinct = 'distinct';
    }
}


sub fisher_yates_shuffle {
    my $myarray = shift;  
    my $i = @$myarray;
    while (--$i) {
        my $j = int rand ($i+1);
        @$myarray[$i,$j] = @$myarray[$j,$i];
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
    my $artistListLength = Slim::Utils::Prefs::get("plugin_trackstat_playlist_per_artist_length");
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
	
	if ($::VERSION ge '6.5') {
		$item->displayAsHTML($form);
	}else {
		my $ds = Plugins::TrackStat::Storage::getCurrentDS();
		my $fieldInfo = Slim::DataStores::Base->fieldInfo;
        my $levelInfo = $fieldInfo->{$type};
        &{$levelInfo->{'listItem'}}($ds, $form, $item);
	}
}

sub getLinkAttribute {
	my $attr = shift;
	if ($::VERSION ge '6.5') {
		if($attr eq 'artist') {
			$attr = 'contributor';
		}
		return $attr.'.id';
	}
	return $attr;
}

sub getTracksWeb {
	my $sql = shift;
	my $params = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	debugMsg("Executing: $sql\n");
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
		$sth->execute();

		my( $url, $playCount, $added, $lastPlayed, $rating );
		$sth->bind_columns( undef, \$url, \$playCount, \$added, \$lastPlayed, \$rating );
		my $itemNumber = 0;
		while( $sth->fetch() ) {
			$lastPlayed = 0 if (!(defined($lastPlayed)));
			$added = 0 if (!(defined($added)));
			$playCount = 0 if (!(defined($playCount)));
			$rating = 0 if (!(defined($rating)));
			my $track = Plugins::TrackStat::Storage::objectForUrl($url);
			next unless defined $track;
		  	my %trackInfo = ();
			
			$trackInfo{'noTrackStatButton'} = 1;
			$trackInfo{'levelName'}  = 'track';
			displayAsHTML('track', \%trackInfo, $track);
		  	$trackInfo{'title'} = Slim::Music::Info::standardTitle(undef,$track);
		  	$trackInfo{'lastPlayed'} = $lastPlayed;
		  	$trackInfo{'added'} = $added;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
			$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
			$trackInfo{'skinOverride'}     = $params->{'skinOverride'};
			$trackInfo{'song_count'}       = $playCount;
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
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
	    	warn "Database error: $DBI::errstr\n";
	    }else {
	    	warn "Database error: $@";
	    }
	}
	$sth->finish();
}

sub getTracks {
	my $sql = shift;
	my $limit = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	debugMsg("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	my @result;
	eval {
		$sth->execute();
		my $url;
		$sth->bind_col( 1, \$url );
		while( $sth->fetch() ) {
			my $track = Plugins::TrackStat::Storage::objectForUrl($url);
		  	push @result, $track;
		}
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
	    		warn "Database error: $DBI::errstr\n";
	    	}else {
	    		warn "Database error: $@";
		}
	}
	$sth->finish();
	fisher_yates_shuffle(\@result);
	if(defined($limit) && scalar(@result)>$limit) {
		my $entriesToRemove = scalar(@result) - $limit;
		splice(@result,0,$entriesToRemove);
	}
	return \@result;
}

sub getAlbumsWeb {
	my $sql = shift;
	my $params = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	debugMsg("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->execute();

		my( $id, $rating, $playCount, $lastPlayed, $added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount, \$lastPlayed, \$added );
		my $itemNumber = 0;
		while( $sth->fetch() ) {
			$playCount = 0 if (!(defined($playCount)));
			$lastPlayed = 0 if (!(defined($lastPlayed)));
			$added = 0 if (!(defined($added)));
			$rating = 0 if (!(defined($rating)));
			my $album = Plugins::TrackStat::Storage::objectForId('album',$id);
			next unless defined $album;
		  	my %trackInfo = ();
			
		  	$trackInfo{'album'} = $album->id;
			$trackInfo{'noTrackStatButton'} = 1;
			$trackInfo{'levelName'}  = 'album';
			displayAsHTML('album', \%trackInfo, $album);
		  	$trackInfo{'title'} = undef;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
			$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
		  	$trackInfo{'lastPlayed'} = $lastPlayed;
		  	$trackInfo{'added'} = $added;
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
			$trackInfo{'skinOverride'}     = $params->{'skinOverride'};
			$trackInfo{'song_count'}       = ceil($playCount);
			$trackInfo{'attributes'}       = '&'.getLinkAttribute('album').'='.$album->id;
			$trackInfo{'itemobj'}{'album'} = $album;
			$trackInfo{'listtype'} = 'album';
		  	
			saveMixerLinks(\%trackInfo);

		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
		    	warn "Database error: $DBI::errstr\n";
		}else {
			warn "Database error: $@";
		}
	}
	$sth->finish();
}

sub getAlbumTracks {
	my $sql = shift;
	my $limit = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	debugMsg("Executing: $sql\n");
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
			debugMsg("Getting tracks for album: ".$album->title."\n");
			my $iterator = $album->tracks;
			for my $item ($iterator->slice(0,$iterator->count)) {
				push @result, $item;
			}
		}
		debugMsg("Got ".scalar(@result)." tracks\n");
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
			warn "Database error: $DBI::errstr\n";
		}else {
			warn "Database error: $@";
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
	debugMsg("Returning ".scalar(@result)." tracks\n");
	return \@result;
}

sub getArtistsWeb {
	my $sql = shift;
	my $params = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	debugMsg("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->execute();

		my( $id, $rating, $playCount,$lastPlayed,$added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount,\$lastPlayed,\$added );
		my $itemNumber = 0;
		while( $sth->fetch() ) {
			$playCount = 0 if (!(defined($playCount)));
			$lastPlayed = 0 if (!(defined($lastPlayed)));
			$added = 0 if (!(defined($added)));
			$rating = 0 if (!(defined($rating)));
			my $artist = Plugins::TrackStat::Storage::objectForId('artist',$id);
			next unless defined $artist;
		  	my %trackInfo = ();
			
		  	$trackInfo{'artist'} = $artist->id;
			$trackInfo{'noTrackStatButton'} = 1;
			$trackInfo{'levelName'}  = 'artist';
			displayAsHTML('artist', \%trackInfo, $artist);
		  	$trackInfo{'title'} = undef;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
		  	$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
		  	$trackInfo{'lastPlayed'} = $lastPlayed;
		  	$trackInfo{'added'} = $added;
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
			$trackInfo{'skinOverride'}     = $params->{'skinOverride'};
			$trackInfo{'song_count'}       = ceil($playCount);
			$trackInfo{'attributes'}       = '&'.getLinkAttribute('artist').'='.$artist->id;
			$trackInfo{'itemobj'}{'artist'} = $artist;
			$trackInfo{'listtype'} = 'artist';
            
			saveMixerLinks(\%trackInfo);
            
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
			warn "Database error: $DBI::errstr\n";
		}else {
			warn "Database error: $@";
		}
	}
	$sth->finish();
}

sub getArtistTracks {
	my $sql = shift;
	my $limit = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	debugMsg("Executing: $sql\n");
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

				debugMsg("Getting tracks for artist: ".$artist->name."\n");
				my $artistFind = {'artist' => $artist->id };

				my $items = $ds->find({
					'field'  => 'track',
					'find'   => $artistFind,
					'sortBy' => 'random',
					'limit'  => $limit,
					'cache'  => 0,
				});
				for my $item (@$items) {
					push @result, $item;
				}
				debugMsg("Got ".scalar(@result)." tracks for ".$artist->name."\n");
			}
		}
		debugMsg("Got ".scalar(@result)." tracks\n");
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
			warn "Database error: $DBI::errstr\n";
		}else {
			warn "Database error: $@";
		}
	}
	$sth->finish();
	debugMsg("Returning ".scalar(@result)." tracks\n");
	return \@result;
}

sub getGenresWeb {
	my $sql = shift;
	my $params = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	debugMsg("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->execute();

		my( $id, $rating, $playCount,$lastPlayed,$added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount,\$lastPlayed,\$added );
		my $itemNumber = 0;
		while( $sth->fetch() ) {
			$playCount = 0 if (!(defined($playCount)));
			$lastPlayed = 0 if (!(defined($lastPlayed)));
			$added = 0 if (!(defined($added)));
			$rating = 0 if (!(defined($rating)));
			my $genre = Plugins::TrackStat::Storage::objectForId('genre',$id);
			next unless defined $genre;
		  	my %trackInfo = ();
			
		  	$trackInfo{'genre'} = $id;
			$trackInfo{'noTrackStatButton'} = 1;
			$trackInfo{'levelName'}  = 'genre';
			displayAsHTML('genre', \%trackInfo, $genre);
		  	$trackInfo{'title'} = undef;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
			$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
		  	$trackInfo{'lastPlayed'} = $lastPlayed;
		  	$trackInfo{'added'} = $added;
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
			$trackInfo{'skinOverride'}     = $params->{'skinOverride'};
			$trackInfo{'song_count'}       = ceil($playCount);
			$trackInfo{'attributes'}       = '&'.getLinkAttribute('genre').'='.$genre->id;
			$trackInfo{'itemobj'}{'genre'} = $genre;
			$trackInfo{'listtype'} = 'genre';
            		  	
			saveMixerLinks(\%trackInfo);

		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
			warn "Database error: $DBI::errstr\n";
		}else {
			warn "Database error: $@";
		}
	}
	$sth->finish();
}

sub getGenreTracks {
	my $sql = shift;
	my $limit = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	debugMsg("Executing: $sql\n");
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

				debugMsg("Getting tracks for genre: ".$genre->name."\n");
				my $genreFind = {'genre' => $genre->id };

				my $items = $ds->find({
					'field'  => 'track',
					'find'   => $genreFind,
					'sortBy' => 'random',
					'limit'  => $limit,
					'cache'  => 0,
				});
				for my $item (@$items) {
					push @result, $item;
				}
				debugMsg("Got ".scalar(@result)." tracks for ".$genre->name."\n");
			}
		}
		debugMsg("Got ".scalar(@result)." tracks\n");
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
			warn "Database error: $DBI::errstr\n";
		}else {
			warn "Database error: $@";
		}
	}
	$sth->finish();
	debugMsg("Returning ".scalar(@result)." tracks\n");
	return \@result;
}

sub getYearsWeb {
	my $sql = shift;
	my $params = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	debugMsg("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->execute();

		my( $id, $rating, $playCount,$lastPlayed,$added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount,\$lastPlayed,\$added );
		my $itemNumber = 0;
		while( $sth->fetch() ) {
			$playCount = 0 if (!(defined($playCount)));
			$lastPlayed = 0 if (!(defined($lastPlayed)));
			$added = 0 if (!(defined($added)));
			$rating = 0 if (!(defined($rating)));
			my $year = $id;
		  	my %trackInfo = ();
			$trackInfo{'noTrackStatButton'} = 1;
			$trackInfo{'levelName'}  = 'year';
			if ($::VERSION ge '6.5') {
				my $yearobj = Plugins::TrackStat::Storage::objectForYear($id);
				displayAsHTML('year', \%trackInfo, $yearobj);
			}
		  	$trackInfo{'title'} = undef;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
			$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
		  	$trackInfo{'lastPlayed'} = $lastPlayed;
		  	$trackInfo{'added'} = $added;
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
			$trackInfo{'skinOverride'}     = $params->{'skinOverride'};
			$trackInfo{'song_count'}       = ceil($playCount);
			$trackInfo{'attributes'}       = '&'.getLinkAttribute('year').'='.$year;
			$trackInfo{'itemobj'}{'year'} = $year;
			$trackInfo{'listtype'} = 'year';
            		  	
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
			warn "Database error: $DBI::errstr\n";
		}else {
			warn "Database error: $@";
		}
	}
	$sth->finish();
}

sub getYearTracks {
	my $sql = shift;
	my $limit = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	debugMsg("Executing: $sql\n");
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

				debugMsg("Getting tracks for year: ".$year."\n");
				my $yearFind = {'year' => $year };

				my $items = $ds->find({
					'field'  => 'track',
					'find'   => $yearFind,
					'sortBy' => 'random',
					'limit'  => $limit,
					'cache'  => 0,
				});
				for my $item (@$items) {
					push @result, $item;
				}
				debugMsg("Got ".scalar(@result)." tracks for ".$year."\n");
			}
		}
		debugMsg("Got ".scalar(@result)." tracks\n");
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
			warn "Database error: $DBI::errstr\n";
		}else {
			warn "Database error: $@";
		}
	}
	$sth->finish();
	debugMsg("Returning ".scalar(@result)." tracks\n");
	return \@result;
}

sub getPlaylistsWeb {
	my $sql = shift;
	my $params = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	debugMsg("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->execute();

		my( $id, $rating, $playCount,$lastPlayed,$added );
		$sth->bind_columns( undef, \$id, \$rating, \$playCount,\$lastPlayed,\$added );
		my $itemNumber = 0;
		while( $sth->fetch() ) {
			$playCount = 0 if (!(defined($playCount)));
			$lastPlayed = 0 if (!(defined($lastPlayed)));
			$added = 0 if (!(defined($added)));
			$rating = 0 if (!(defined($rating)));
			my $playlist = Plugins::TrackStat::Storage::objectForId('playlist',$id);
			next unless defined $playlist;
		  	my %trackInfo = ();
			
		  	$trackInfo{'playlist'} = $playlist->id;
			$trackInfo{'noTrackStatButton'} = 1;
			$trackInfo{'levelName'}  = 'playlist';
			displayAsHTML('playlist', \%trackInfo, $playlist);
		  	$trackInfo{'title'} = undef;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
		  	$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
		  	$trackInfo{'lastPlayed'} = $lastPlayed;
		  	$trackInfo{'added'} = $added;
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
			$trackInfo{'skinOverride'}     = $params->{'skinOverride'};
			$trackInfo{'song_count'}       = ceil($playCount);
			$trackInfo{'attributes'}       = '&'.getLinkAttribute('playlist').'='.$playlist->id;
			$trackInfo{'itemobj'}{'playlist'} = $playlist;
			$trackInfo{'listtype'} = 'playlist';
            
			saveMixerLinks(\%trackInfo);
            
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
			warn "Database error: $DBI::errstr\n";
		}else {
			warn "Database error: $@";
		}
	}
	$sth->finish();
}

sub getPlaylistTracks {
	my $sql = shift;
	my $limit = shift;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	debugMsg("Executing: $sql\n");
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

				debugMsg("Getting tracks for artist: ".$artist->name."\n");
				my $artistFind = {'artist' => $artist->id };

				my $items = $ds->find({
					'field'  => 'track',
					'find'   => $artistFind,
					'sortBy' => 'random',
					'limit'  => $limit,
					'cache'  => 0,
				});
				for my $item (@$items) {
					push @result, $item;
				}
				debugMsg("Got ".scalar(@result)." tracks for ".$artist->name."\n");
			}
		}
		debugMsg("Got ".scalar(@result)." tracks\n");
	};
	if( $@ ) {
		if(defined($DBI::errstr)) {
	    	warn "Database error: $DBI::errstr\n";
	    }else {
	    	warn "Database error: $@";
	    }
	}
	$sth->finish();
	debugMsg("Returning ".scalar(@result)." tracks\n");
	return \@result;
}

# A wrapper to allow us to uniformly turn on & off debug messages
sub debugMsg
{
	my $message = join '','TrackStat::Statistics: ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_trackstat_showmessages"));
}


1;

__END__
