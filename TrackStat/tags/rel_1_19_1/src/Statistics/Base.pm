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
sub getTracksWeb {
	my $sql = shift;
	my $params = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
	debugMsg("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
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
			my $track = $ds->objectForUrl($url);
			next unless defined $track;
		  	my %trackInfo = ();
			my $fieldInfo = Slim::DataStores::Base->fieldInfo;
            my $levelInfo = $fieldInfo->{'track'};
			
            &{$levelInfo->{'listItem'}}($ds, \%trackInfo, $track);
		  	$trackInfo{'title'} = Slim::Music::Info::standardTitle(undef,$track);
		  	$trackInfo{'lastPlayed'} = $lastPlayed;
		  	$trackInfo{'added'} = $added;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
			$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
            $trackInfo{'skinOverride'}     = $params->{'skinOverride'};
            $trackInfo{'song_count'}       = $playCount;
            $trackInfo{'attributes'}       = '&track='.$track->id;
            $trackInfo{'itemobj'}          = $track;
            $trackInfo{'listtype'} = 'track';
            		  	
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
}

sub getTracks {
	my $sql = shift;
	my $limit = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
	debugMsg("Executing: $sql\n");
	my $sth = $dbh->prepare( $sql );
	my @result;
	eval {
		$sth->execute();
		my $url;
		$sth->bind_columns( undef, \$url );
		while( $sth->fetch() ) {
			my $track = $ds->objectForUrl($url);
		  	push @result, $track;
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
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
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
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
			my $album = $ds->objectForId('album',$id);
			next unless defined $album;
		  	my %trackInfo = ();
			my $fieldInfo = Slim::DataStores::Base->fieldInfo;
            my $levelInfo = $fieldInfo->{'album'};
			
            &{$levelInfo->{'listItem'}}($ds, \%trackInfo, $album);
		  	$trackInfo{'title'} = undef;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
			$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
		  	$trackInfo{'lastPlayed'} = $lastPlayed;
		  	$trackInfo{'added'} = $added;
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
            $trackInfo{'skinOverride'}     = $params->{'skinOverride'};
            $trackInfo{'song_count'}       = ceil($playCount);
            $trackInfo{'attributes'}       = '&album='.$album->id;
            $trackInfo{'itemobj'}{'album'} = $album;
            $trackInfo{'listtype'} = 'album';
		  	
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
}

sub getAlbumTracks {
	my $sql = shift;
	my $limit = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
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
			my $album = $ds->objectForId('album',$id);
			debugMsg("Getting tracks for album: ".$album->title."\n");
			my $iterator = $album->tracks;
			for my $item ($iterator->slice(0,$iterator->count)) {
				push @result, $item;
			}
		}
		debugMsg("Got ".scalar(@result)." tracks\n");
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
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
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
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
			my $artist = $ds->objectForId('artist',$id);
			next unless defined $artist;
		  	my %trackInfo = ();
			my $fieldInfo = Slim::DataStores::Base->fieldInfo;
            my $levelInfo = $fieldInfo->{'artist'};
			
            &{$levelInfo->{'listItem'}}($ds, \%trackInfo, $artist);
		  	$trackInfo{'title'} = undef;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
		  	$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
		  	$trackInfo{'lastPlayed'} = $lastPlayed;
		  	$trackInfo{'added'} = $added;
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
            $trackInfo{'skinOverride'}     = $params->{'skinOverride'};
            $trackInfo{'song_count'}       = ceil($playCount);
            $trackInfo{'attributes'}       = '&artist='.$artist->id;
            $trackInfo{'itemobj'}{'artist'} = $artist;
            $trackInfo{'listtype'} = 'artist';
            		  	
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
}

sub getArtistTracks {
	my $sql = shift;
	my $limit = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
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
				my $artist = $ds->objectForId('artist',$id);

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
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
	debugMsg("Returning ".scalar(@result)." tracks\n");
	return \@result;
}

sub getGenresWeb {
	my $sql = shift;
	my $params = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
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
			my $genre = $ds->objectForId('genre',$id);
			next unless defined $genre;
		  	my %trackInfo = ();
			my $fieldInfo = Slim::DataStores::Base->fieldInfo;
            my $levelInfo = $fieldInfo->{'genre'};
			
            &{$levelInfo->{'listItem'}}($ds, \%trackInfo, $genre);
		  	$trackInfo{'title'} = undef;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
			$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
		  	$trackInfo{'lastPlayed'} = $lastPlayed;
		  	$trackInfo{'added'} = $added;
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
            $trackInfo{'skinOverride'}     = $params->{'skinOverride'};
            $trackInfo{'song_count'}       = ceil($playCount);
            $trackInfo{'attributes'}       = '&genre='.$genre->id;
            $trackInfo{'itemobj'}{'genre'} = $genre;
            $trackInfo{'listtype'} = 'genre';
            		  	
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
}

sub getGenreTracks {
	my $sql = shift;
	my $limit = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
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
				my $genre = $ds->objectForId('genre',$id);

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
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
	debugMsg("Returning ".scalar(@result)." tracks\n");
	return \@result;
}

sub getYearsWeb {
	my $sql = shift;
	my $params = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
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
			#my $fieldInfo = Slim::DataStores::Base->fieldInfo;
            #my $levelInfo = $fieldInfo->{'genre'};
			
            #&{$levelInfo->{'listItem'}}($ds, \%trackInfo, $genre);
		  	$trackInfo{'title'} = undef;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
			$trackInfo{'ratingnumber'} = sprintf("%.2f", $rating/20);
		  	$trackInfo{'lastPlayed'} = $lastPlayed;
		  	$trackInfo{'added'} = $added;
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
            $trackInfo{'skinOverride'}     = $params->{'skinOverride'};
            $trackInfo{'song_count'}       = ceil($playCount);
            $trackInfo{'attributes'}       = '&year='.$year;
            $trackInfo{'itemobj'}{'year'} = $year;
            $trackInfo{'listtype'} = 'year';
            		  	
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
}

sub getYearTracks {
	my $sql = shift;
	my $limit = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
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
	    warn "Database error: $DBI::errstr\n";
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