#         TrackStatPlaylist::Export module
#
#    Copyright (c) 2008 Erland Isaksson (erland_i@hotmail.com)
#
#    Portions of code derived from the iTunesUpdate 1.5 plugin
#    Copyright (c) 2004-2006 James Craig (james.craig@london.com)
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
                   
package Plugins::TrackStatPlaylist::Export;

use Slim::Utils::Prefs;
use Date::Parse qw(str2time);
use Fcntl ':flock'; # import LOCK_* constants
use POSIX qw(strftime);
use File::Spec::Functions qw(:ALL);
use DBI qw(:sql_types);
use Slim::Utils::Misc;
use Plugins::CustomScan::Validators;
use Slim::Player::Playlist;
use Time::Stopwatch;

my $prefs = preferences('plugin.trackstatplaylist');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.trackstatplaylist',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_TRACKSTATPLAYLIST',
});

my %playlistTracksCache = ();
my $ratingSth = undef;
my $ratingSthCount = undef;

sub getCustomScanFunctions {
	my %functions = (
		'id' => 'trackstatplaylistexport',
		'order' => '75',
		'defaultenabled' => 0,
		'name' => 'TrackStat Playlist Export',
		'description' => "This module exports statistic information in SqueezeCenter to static playlists. When a user changes a rating on a song the song is moved into one of the rating playlists and when a song is played the song is moved into the played playlist. If you do a export the rating playlists will be filled with all rated tracks in the SqueezeCenter database",
		'developedBy' => 'Erland Isaksson',
		'developedByLink' => 'http://erland.isaksson.info/donate', 
		'alwaysRescanTrack' => 1,
		'clearEnabled' => 0,
		'requiresRefresh' => 0,
		'initScanTrack' => \&initScanTrack,
		'exitScanTrack' => \&exitScanTrack,
		'scanText' => 'Export',
		'properties' => [
			{
				'id' => 'trackstatplaylistdynamicupdate',
				'name' => 'Continously write to playlists',
				'description' => 'Continously write a to playlists when songs are played and ratings are changed in SqueezeCenter',
				'type' => 'checkbox',
				'value' => 1
			},
			{
				'id' => 'trackstatplaylistrating0name',
				'name' => 'Unrated playlist',
				'description' => 'Name of playlist where unrated songs should be added',
				'type' => 'text',
				'value' => ''
			},
			{
				'id' => 'trackstatplaylistrating1name',
				'name' => '1 rating playlist',
				'description' => 'Name of playlist where 1 rating (0-29 / 100) songs should be added',
				'type' => 'text',
				'value' => 'TrackStat 1 Ratings'
			},
			{
				'id' => 'trackstatplaylistrating2name',
				'name' => '2 rating playlist',
				'description' => 'Name of playlist where 2 rating (30-49 / 100) songs should be added',
				'type' => 'text',
				'value' => 'TrackStat 2 Ratings'
			},
			{
				'id' => 'trackstatplaylistrating3name',
				'name' => '3 rating playlist',
				'description' => 'Name of playlist where 3 rating (50-69 / 100) songs should be added',
				'type' => 'text',
				'value' => 'TrackStat 3 Ratings'
			},
			{
				'id' => 'trackstatplaylistrating4name',
				'name' => '4 rating playlist',
				'description' => 'Name of playlist where 4 rating (70-89 / 100) songs should be added',
				'type' => 'text',
				'value' => 'TrackStat 4 Ratings'
			},
			{
				'id' => 'trackstatplaylistrating5name',
				'name' => '5 rating playlist',
				'description' => 'Name of playlist where 5 rating (90-100 / 100) songs should be added',
				'type' => 'text',
				'value' => 'TrackStat 5 Ratings'
			},
			{
				'id' => 'trackstatplaylistplayedname',
				'name' => 'Playlist name played songs',
				'description' => 'Name of playlist where played songs should be added',
				'type' => 'text',
				'value' => 'TrackStat Played'
			},
			{
				'id' => 'trackstatplaylistplayedlength',
				'name' => 'Length of played playlist',
				'description' => 'Maximum length of played playlist',
				'type' => 'text',
				'validate' => \&Plugins::CustomScan::Validators::isInt,
				'value' => '100'
			},
			{
				'id' => 'trackstatplaylistincludeautoratings',
				'name' => 'Include automatic ratings',
				'description' => 'Ratings automatically set by TrackStat updates the rating playlists',
				'type' => 'checkbox',
				'value' => 0
			},
		]
	);
	my $properties = $functions{'properties'};
	if(Plugins::TrackStatPlaylist::Plugin::isPluginsInstalled(undef,"MultiLibrary::Plugin")) {
		my $values = getSQLPropertyValues("select id,name from multilibrary_libraries");
		my %library = (
			'id' => 'trackstatplaylistexportlibraries',
			'name' => 'Libraries to limit the export to',
			'description' => 'Limit the export to songs in the selected libraries (None selected equals no limit)',
			'type' => 'multiplelist',
			'values' => $values,
			'value' => '',
		);
		push @$properties,\%library;
		my %dynamiclibrary = (
			'id' => 'trackstatplaylistexportlibrariesdynamicupdate',
			'name' => 'Limit history to libraries',
			'description' => 'Limit the continously added songs to selected libraries',
			'type' => 'checkbox',
			'value' => 1
		);
		push @$properties,\%dynamiclibrary,
	}
	return \%functions;
		
}
sub initScanTrack {
	$ratingSth = undef;
	$log->info("Start exporting ratings to playlist at ".(strftime ("%Y-%m-%d %H:%M:%S",localtime())));
	return undef;
}

sub exitScanTrack
{
	my $libraries = Plugins::CustomScan::Plugin::getCustomScanProperty("trackstatplaylistexportlibraries");
	$log->debug("Exporting ratings to playlist");

	my $timeMeasure = Time::Stopwatch->new();
	$timeMeasure->clear();
	$timeMeasure->start();

	my @ratingDigits = qw(0 1 2 3 4 5);

	if(!defined($ratingSth)) {
		for my $ratingDigit (@ratingDigits) {
			deletePlaylist(Plugins::CustomScan::Plugin::getCustomScanProperty("trackstatplaylistrating".$ratingDigit."name"));

			$log->info("Finished deleting old rating ".$ratingDigit." playlist : It took ".$timeMeasure->getElapsedTime()." seconds");
			$timeMeasure->stop();
			$timeMeasure->clear();
			$timeMeasure->start();

			# Lets make sure streaming gets it time
			main::idleStreams();
		}


		my $sql = undef;
		if($libraries && Plugins::TrackStatPlaylist::Plugin::isPluginsInstalled(undef,"MultiLibrary::Plugin")) {
			if(Plugins::TrackStatPlaylist::Plugin::isPluginsInstalled(undef,"TrackStat::Plugin")) {
				$sql = "SELECT track_statistics.url, track_statistics.rating FROM track_statistics,tracks,multilibrary_track where track_statistics.url=tracks.url and track_statistics.rating>0 and tracks.id=multilibrary_track.track and multilibrary_track.library in ($libraries)";
			}else {
				$sql = "SELECT tracks.url, tracks_persistent.rating FROM tracks_persistent,tracks,multilibrary_track where tracks_persistent.track=tracks.id and tracks_persistent.rating>0 and tracks.id=multilibrary_track.track and multilibrary_track.library in ($libraries)";
			}
		}else {
			if(Plugins::TrackStatPlaylist::Plugin::isPluginsInstalled(undef,"TrackStat::Plugin")) {
				$sql = "SELECT track_statistics.url, track_statistics.rating FROM track_statistics,tracks where track_statistics.url=tracks.url and track_statistics.rating>0";
			}else {
				$sql = "SELECT tracks.url, tracks_persistent.rating FROM tracks_persistent,tracks where tracks_persistent.track=tracks.id and tracks_persistent.rating>0";
			}
		}

		my $dbh = Slim::Schema->storage->dbh();
		$log->debug("Retreiving tracks with: $sql");
		$ratingSth = $dbh->prepare( $sql );

		%playlistTracksCache = ();
		$ratingSthCount = 0;

		eval {
			$ratingSth->execute();
		};
		if( $@ ) {
		    $log->warn("Database error: $DBI::errstr,$@");
		}
		$log->info("Finished getting ratings from database : It took ".$timeMeasure->getElapsedTime()." seconds");
		$log->info("Fetching songs, this might take a while...");
		$timeMeasure->stop();
		$timeMeasure->clear();
		return 1;
	}else {
		my $lastEntry = 1;
		my( $url, $rating );
		eval {
			$ratingSth->bind_columns( undef, \$url, \$rating );

			my $result;
			if( $ratingSth->fetch() ) {
				$lastEntry = 0;
				if($url) {
					my $track = Slim::Schema->objectForUrl({
						'url' => $url
					});
					addBulkRatingToPlaylist(undef,$track,$rating);
					$ratingSthCount++;
				}
			}
		};
		if( $@ ) {
		    $log->warn("Database error: $DBI::errstr,$@");
		}
		if($lastEntry) {
			$ratingSth->finish();
			$ratingSth = undef;

			my $playlistDir = $serverPrefs->get('playlistdir');
			for my $playlist (keys %playlistTracksCache) {
				my $tracks = $playlistTracksCache{$playlist};
				my $playlistObj = getPlaylist($playlistDir, $playlist);
				$playlistObj->setTracks($tracks);
				$playlistObj->update;

				$log->info("Finished updating playlist: ".$playlist." : It took ".$timeMeasure->getElapsedTime()." seconds");
				$timeMeasure->stop();
				$timeMeasure->clear();

				# Lets make sure streaming gets it time
				main::idleStreams();

				$timeMeasure->start();
			}
			Slim::Schema->forceCommit;

			for my $ratingDigit (@ratingDigits) {
				my $playlistObj = getPlaylist($playlistDir, Plugins::CustomScan::Plugin::getCustomScanProperty("trackstatplaylistrating".$ratingDigit."name"));
				if($playlistObj && scalar($playlistObj->tracks())>0) {
					Slim::Player::Playlist::scheduleWriteOfPlaylist(undef,$playlistObj);
					$log->info("Finished writing rating playlist ".$ratingDigit." : It took ".$timeMeasure->getElapsedTime()." seconds");
					$timeMeasure->stop();
					$timeMeasure->clear();

					# Lets make sure streaming gets it time
					main::idleStreams();

					$timeMeasure->start();
				}else {
					deletePlaylist(Plugins::CustomScan::Plugin::getCustomScanProperty("trackstatplaylistrating".$ratingDigit."name"));
					$log->info("Finished deleting playlist ".$ratingDigit." : It took ".$timeMeasure->getElapsedTime()." seconds");
					$timeMeasure->stop();
					$timeMeasure->clear();

					# Lets make sure streaming gets it time
					main::idleStreams();

					$timeMeasure->start();
				}
			}

			$timeMeasure->stop();
			$timeMeasure->clear();

			%playlistTracksCache = ();

			$log->info("Exporting ratings to playlist completed at ".(strftime ("%Y-%m-%d %H:%M:%S",localtime())).", exported $ratingSthCount songs");
			return undef;
		}

		$timeMeasure->stop();
		$timeMeasure->clear();
		return 1;
	}
}

sub addBulkRatingToPlaylist {
	my $client = shift;
	my $track = shift;
	my $rating = shift;

	my $playlistDir = $serverPrefs->get('playlistdir');

	my $ratingDigit;
	if($rating<10) {
		$ratingDigit = 0;
	}elsif($rating<30) {
		$ratingDigit = 1;
	}elsif($rating<50) {
		$ratingDigit = 2;
	}elsif($rating<70) {
		$ratingDigit = 3;
	}elsif($rating<90) {
		$ratingDigit = 4;
	}else {
		$ratingDigit = 5;
	}				
	my $title = Plugins::CustomScan::Plugin::getCustomScanProperty("trackstatplaylistrating".$ratingDigit."name");

	if($title && $playlistDir) {
		my $tracks = $playlistTracksCache{$title};
		if(!defined($tracks)) {
			my @empty = ();
			$playlistTracksCache{$title} = \@empty;
			$tracks = $playlistTracksCache{$title};
		}
		push @$tracks,$track;
	}
}

sub addRatingToPlaylist {
	my $client = shift;
	my $track = shift;
	my $rating = shift;

	my $playlistDir = $serverPrefs->get('playlistdir');

	my @removeFrom = qw(0 1 2 3 4 5);
	for my $i (@removeFrom) {
		my $title = Plugins::CustomScan::Plugin::getCustomScanProperty("trackstatplaylistrating".$i."name");
		if($title) {
			deleteRatingFromPlaylist($client,$track,$title);
		}
	}

	my $ratingDigit;
	if($rating<10) {
		$ratingDigit = 0;
	}elsif($rating<30) {
		$ratingDigit = 1;
	}elsif($rating<50) {
		$ratingDigit = 2;
	}elsif($rating<70) {
		$ratingDigit = 3;
	}elsif($rating<90) {
		$ratingDigit = 4;
	}else {
		$ratingDigit = 5;
	}				
	my $title = Plugins::CustomScan::Plugin::getCustomScanProperty("trackstatplaylistrating".$ratingDigit."name");

	if($title && $playlistDir) {
		my $playlistObj = getPlaylist($playlistDir, $title);
		my @tracks = ($track);
		$playlistObj->appendTracks(\@tracks);
		$playlistObj->update;
		Slim::Schema->forceCommit;
		Slim::Player::Playlist::scheduleWriteOfPlaylist($client, $playlistObj);
	}else {
		Slim::Schema->forceCommit;
	}
}

sub deleteRatingFromPlaylist {
	my $client = shift;
	my $track = shift;
	my $title = shift;

	my $playlistDir = $serverPrefs->get('playlistdir');

	if($title && $playlistDir) {
		my $playlistObj = getPlaylist($playlistDir, $title);
		my @existingTracks = $playlistObj->tracks();
		my $i=0;
		for my $trk (@existingTracks) {
			if($trk->url eq $track->url) {
				splice(@existingTracks,$i,1);
			}
			$i++;
		}
		$playlistObj->setTracks(\@existingTracks);
		if(scalar(@existingTracks)>0) {
			$playlistObj->update;
			Slim::Player::Playlist::scheduleWriteOfPlaylist($client, $playlistObj);
		}else {
			Slim::Player::Playlist::removePlaylistFromDisk($playlistObj);
			$playlistObj->delete;
		}
		$playlistObj = undef;
		Slim::Schema->forceCommit;
	}
}

sub addPlayedToPlaylist {
	my $client = shift;
	my $track = shift;
	my $lastPlayed = shift;

	my $playlistDir = $serverPrefs->get('playlistdir');
	my $title = Plugins::CustomScan::Plugin::getCustomScanProperty("trackstatplaylistplayedname");
	if($title && $playlistDir) {
		my $playlistObj = getPlaylist($playlistDir, $title);
		my $maxLength = Plugins::CustomScan::Plugin::getCustomScanProperty("trackstatplaylistplayedlength");
		if($maxLength>0) {
			my @existingTracks = $playlistObj->tracks();
			my $extraTracks = scalar(@existingTracks)-$maxLength+1;
			$log->debug("Playlist length is ".scalar(@existingTracks)." and is allowed to be $maxLength");
			if($extraTracks>0) {
				$log->debug("Shortening playlist with $extraTracks songs");
				splice(@existingTracks,0,$extraTracks);
				$playlistObj->setTracks(\@existingTracks);
			}
		}
		my @tracks = ($track);
		$playlistObj->appendTracks(\@tracks);
		Slim::Schema->forceCommit;
		Slim::Player::Playlist::scheduleWriteOfPlaylist($client, $playlistObj);
	}
}

sub getPlaylist {
	my $playlistDir = shift;
	my $title = shift;

	my $titlesort = Slim::Utils::Text::ignoreCaseArticles($title);
	my $playlistObj = Slim::Schema->rs('Playlist')->updateOrCreate({
		'url' => Slim::Utils::Misc::fileURLFromPath(catfile($playlistDir, Slim::Utils::Unicode::utf8encode_locale($title).".m3u")),
		'attributes' => {
			'TITLE' => $title,
			'CT'	=> 'ssp',
		},
	});
	$playlistObj->set_column('titlesort',$titlesort);
	$playlistObj->set_column('titlesearch',$titlesort);
	$playlistObj->update;
	return $playlistObj;
}


sub deletePlaylist {
	my $title = shift;

	my $playlistDir = $serverPrefs->get('playlistdir');

	if($title && $playlistDir) {
		my $playlistObj = getPlaylist($playlistDir, $title);

		Slim::Player::Playlist::removePlaylistFromDisk($playlistObj);
		my @tracks = ();
		$playlistObj->setTracks(\@tracks);
		$playlistObj->delete;
		$playlistObj = undef;
		Slim::Schema->forceCommit;
	}
}

sub exportRating {
	my $client = shift;
	my $url = shift;
	my $rating = shift;
	my $track = shift;
	my $type = shift;

	if(defined($type) && $type eq 'auto' && !Plugins::CustomScan::Plugin::getCustomScanProperty("trackstatplaylistincludeautoratings")) {
		$log->debug("Automatic rating, ignoring");
		return;
	}elsif(defined($type) && ($type ne 'user' && $type ne 'auto')) {
		$log->debug("Non user rating, ignoring");
		return;
	}

	if(Plugins::CustomScan::Plugin::getCustomScanProperty("trackstatplaylistdynamicupdate")) {
		if(!defined($rating) || !$rating) {
			return;
		}

		if(!defined($track)) {
			$track = Slim::Schema->objectForUrl({
				'url' => $url
			});
		}
		
		if(isAllowedToExport($track)) {
			addRatingToPlaylist($client,$track,$rating);
		}
	}
}

sub isAllowedToExport {
	my $track = shift;

	my $include = 1;
	my $libraries = Plugins::CustomScan::Plugin::getCustomScanProperty("trackstatplaylistexportlibraries");
	if(Plugins::CustomScan::Plugin::getCustomScanProperty("trackstatplaylistexportlibrariesdynamicupdate") && $libraries  && Plugins::TrackStatPlaylist::Plugin::isPluginsInstalled(undef,"MultiLibrary::Plugin")) {
		my $sql = "SELECT tracks.id FROM tracks,multilibrary_track where tracks.id=multilibrary_track.track and tracks.id=".$track->id." and multilibrary_track.library in ($libraries)";
		my $dbh = Slim::Schema->storage->dbh();
		$log->debug("Executing: $sql");
		eval {
			my $sth = $dbh->prepare( $sql );
			$sth->execute();
			$sth->bind_columns( undef, \$include);
			if( !$sth->fetch() ) {
				$log->debug("Ignoring track, not part of selected libraries: ".$track->url);
				$include = 0;
			}
			$sth->finish();
		};
		if($@) {
			$log->debug("Database error: $DBI::errstr, $@");
		}
	}
	return $include;
}
sub exportStatistic {
	my $client = shift;
	my $url = shift;
	my $rating = shift;
	my $playCount = shift;
	my $lastPlayed = shift;

	if(Plugins::CustomScan::Plugin::getCustomScanProperty("trackstatplaylistdynamicupdate")) {
		my $track = Slim::Schema->objectForUrl({
				'url' => $url
			});
		if(isAllowedToExport($track)) {
			if(defined($lastPlayed)) {
				addPlayedToPlaylist($client,$track,$lastPlayed);
			}
		}
	}
}

sub getSQLPropertyValues {
	my $sqlstatements = shift;
	my @result =();
	my $dbh = Slim::Schema->storage->dbh();
	my $trackno = 0;
    	for my $sql (split(/[;]/,$sqlstatements)) {
	    	eval {
			$sql =~ s/^\s+//g;
			$sql =~ s/\s+$//g;
			my $sth = $dbh->prepare( $sql );
			$log->debug("Executing: $sql");
			$sth->execute() or do {
				$log->warn("Error executing: $sql");
				$sql = undef;
			};
	
			if ($sql =~ /^SELECT+/oi) {
				$log->debug("Executing and collecting: $sql");
				my $id;
				my $name;
				$sth->bind_col( 1, \$id);
				$sth->bind_col( 2, \$name);
				while( $sth->fetch() ) {
					my %item = (
						'id' => Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($id,'utf8')),
						'name' => Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($name,'utf8'))
					);
					push @result, \%item;
				}
			}
			$sth->finish();
		};
		if( $@ ) {
			$log->warn("Database error: ".$DBI::errstr);
		}		
	}
	return \@result;
}

# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

# don't use the external one because it doesn't know about the difference
# between a param and not...
#*unescape = \&URI::Escape::unescape;
sub unescape {
        my $in      = shift;
        my $isParam = shift;

        $in =~ s/\+/ /g if $isParam;
        $in =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

        return $in;
}

1;

__END__
