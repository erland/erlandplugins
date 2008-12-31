#         TrackStat::MusicMagic module
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
# 
#    Portions of code derived from the iTunes plugin included with slimserver
#    SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
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
                   
package Plugins::TrackStat::MusicMagic::Export;

use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Class::Struct;
use POSIX qw(floor);
use DBI qw(:sql_types);
use Plugins::CustomScan::Validators;
use LWP::UserAgent;

my $lastMusicMagicFinishTime = undef;
my $lastMusicMagicDate = 0;
my $MusicMagicScanStartTime = 0;

my $isScanning = 0;

my @songs = ();

struct TrackExportInfo => {

	url => '$',
	rating => '$',
	playCount => '$',
	lastPlayed => '$',
};

my $prefs = preferences('plugin.trackstat');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.trackstat',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_TRACKSTAT',
});

sub getCustomScanFunctions {
	my %functions = (
		'id' => 'musicmagicexport',
		'order' => '75',
		'defaultenabled' => 0,
		'name' => 'MusicIP Statistics Export',
		'description' => "This module exports statistic information in SqueezeCenter to MusicIP Mixer. The information exported are ratings, playcounts, last played time<br><br>The export module is prepared for having separate libraries in MusicIP and SqueezeCenter, for example the MusicIP library can be on a Windows computer in mp3 format and the SqueezeCenter library can be on a Linux computer with flac format. The music path and file extension parameters will in this case be used to convert the exported data so it corresponds to the paths and files used in MusicIP. If you are running MusicIP and SqueezeCenter on the same computer towards the same library the music path and file extension parameters can typically be left empty.",
		'alwaysRescanTrack' => 1,
		'clearEnabled' => 0,
		'initScanTrack' => \&initScanTrack,
		'exitScanTrack' => \&scanFunction,
		'scanText' => 'Export',
		'properties' => [
			{
				'id' => 'musicmagichost',
				'name' => 'MusicIP hostname',
				'description' => 'Hostname of computer where MusicIP is running',
				'type' => 'text',
				'value' => defined($prefs->get("musicmagic_host"))?$prefs->get("musicmagic_host"):$serverPrefs->get('MMSHost')
			},
			{
				'id' => 'musicmagicport',
				'name' => 'MusicIP port',
				'description' => 'Port which is used for MusicIP',
				'type' => 'text',
				'value' => defined($prefs->get("musicmagic_port"))?$prefs->get("musicmagic_port"):$serverPrefs->get('MMSport')
			},
			{
				'id' => 'musicmagicextension',
				'name' => 'File extension in MusicIP',
				'description' => 'File extension in MusicIP (for example .mp3), empty means same file extension as in SqueezeCenter',
				'type' => 'text',
				'value' => $prefs->get("musicmagic_replace_extension")
			},
			{
				'id' => 'musicmagicmusicpath',
				'name' => 'Music path in MusicIP',
				'description' => 'Path to main music directory in MusicIP, empty means same music path as in SqueezeCenter',
				'type' => 'text',
				'value' => $prefs->get("musicmagic_export_library_music_path")
			},
			{
				'id' => 'musicmagicslimservermusicpath',
				'name' => 'Music path in SqueezeCenter',
				'description' => 'Path to main music directory in SqueezeCenter, empty means same music path as in SqueezeCenter',
				'type' => 'text',
				'validate' => \&Plugins::CustomScan::Validators::isDirOrEmpty,
				'value' => $prefs->get("musicmagic_library_music_path")
			},
			{
				'id' => 'musicmagicdynamicupdate',
				'name' => 'Dynamically update statistics',
				'description' => 'Continously write statistics to MusicIP when ratings are changed and songs are played in SqueezeCenter',
				'type' => 'checkbox',
				'value' => defined($prefs->get("musicmagic_enabled"))?$prefs->get("musicmagic_enabled"):0
			},
			{
				'id' => 'musicmagictimeout',
				'name' => 'Timeout',
				'description' => 'Timeout in requests towards MusicIP',
				'type' => 'text',
				'value' => $serverPrefs->get("remotestreamtimeout")||15
			},
		]
	);
	if(Plugins::TrackStat::Plugin::isPluginsInstalled(undef,"MultiLibrary::Plugin")) {
		my $properties = $functions{'properties'};
		my $values = Plugins::TrackStat::Storage::getSQLPropertyValues("select id,name from multilibrary_libraries");
		my %library = (
			'id' => 'musicmagicexportlibraries',
			'name' => 'Libraries to limit the export to',
			'description' => 'Limit the export to songs in the selected libraries (None selected equals no limit)',
			'type' => 'multiplelist',
			'values' => $values,
			'value' => '',
		);
		push @$properties,\%library;
		my %dynamiclibrary = (
			'id' => 'musicmagicexportlibrariesdynamicupdate',
			'name' => 'Limit dynamic update to libraries',
			'description' => 'Limit the continously written dynamic updates to selected libraries',
			'type' => 'checkbox',
			'value' => 1
		);
		push @$properties,\%dynamiclibrary,
	}
	return \%functions;
		
}

sub initScanTrack {
	checkDefaults();
	@songs = ();
	$MusicMagicScanStartTime = time();
	my $libraries = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicexportlibraries");
	
	my $sql = undef;
	if($libraries && Plugins::TrackStat::Plugin::isPluginsInstalled(undef,"MultiLibrary::Plugin")) {
		$sql = "SELECT track_statistics.url, track_statistics.playCount, track_statistics.lastPlayed, track_statistics.rating FROM track_statistics,tracks,multilibrary_track where track_statistics.url=tracks.url and (track_statistics.lastPlayed is not null or track_statistics.rating>0) and tracks.id=multilibrary_track.track and multilibrary_track.library in ($libraries)";
	}else {
		$sql = "SELECT track_statistics.url, track_statistics.playCount, track_statistics.lastPlayed, track_statistics.rating FROM track_statistics,tracks where track_statistics.url=tracks.url and (track_statistics.lastPlayed is not null or track_statistics.rating>0)";
	}

	my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
	my $sth = $dbh->prepare( $sql );
	my( $url, $playCount, $lastPlayed, $rating );
	eval {
		$sth->execute();
		$sth->bind_columns( undef, \$url, \$playCount, \$lastPlayed, \$rating );
		while( $sth->fetch() ) {
			my $track = TrackExportInfo->new();
			$track->url($url);
			if($rating) {
				$track->rating($rating/20);
			}else {
				$track->rating(0);
			}
			$track->playCount($playCount);
			$track->lastPlayed($lastPlayed);
			push @songs, $track;
		}
		$sth->finish();
	};
	if ($@) {
		$log->warn("SQL error: $DBI::errstr, $@\n");
		$isScanning = -1;
	}else {
		$log->debug("Got ".scalar(@songs)." number of tracks with statistics");
	}
	$isScanning = 1;
	return undef;
}

sub doneScanning {
	$log->debug("done Scanning: unlocking and closing\n");

	$lastMusicMagicFinishTime = time();

	my $hostname = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagichost");;
	my $port = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicport");;
	my $musicmagicurl = "http://$hostname:$port/api/cacheid";
	$log->debug("Calling: $musicmagicurl\n");
	my $http = LWP::UserAgent->new;
	$http->timeout(Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagictimeout"));
	my $response = $http->get("http://$hostname:$port/api/flush");
    	if(!$response->is_success) {
    		$log->warn("Failed to flush MusicMagic cache");
	}
	$http = LWP::UserAgent->new;
	$http->timeout(Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagictimeout"));
	$response = $http->get($musicmagicurl);
	if($response->is_success) {
		my $modificationTime = $response->content;
		chomp $modificationTime;

		$lastMusicMagicDate = $modificationTime;
	}else {
		$isScanning = -1;
		$log->warn("Failed to call MusicMagic at: $musicmagicurl\n");
	}

	if($isScanning==1) {
		$isScanning = 0;
		$log->info("TrackStat::MusicMagic::Export: Export completed in ".(time() - $MusicMagicScanStartTime)." seconds.\n");
		$prefs->set('lastMusicMagicDate', $lastMusicMagicDate);
	}elsif($isScanning==-1) {
		$log->info("TrackStat::MusicMagic::Export: Export failed after ".(time() - $MusicMagicScanStartTime)." seconds.\n");
	}else {
		$log->info("TrackStat::MusicMagic::Export: Export skipped after ".(time() - $MusicMagicScanStartTime)." seconds.\n");
	}
}

sub scanFunction {
	# parse a little more from the stream.
	if (scalar(@songs)>0) {
		my $song = shift @songs;
		if ($song) {
			handleTrack($song);
		}
	}

	if (scalar(@songs)>0) {
		return 1;
	}else {
		doneScanning();
		return undef;
	}
}

sub handleTrack {
	my $track = shift;

	my $url = $track->url();
	my $rating = $track->rating();
	my $playCount = $track->playCount();
	my $lastPlayed = $track->lastPlayed();

	my $hostname = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagichost");;
	my $port = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicport");
	$url = getMusicMagicURL($url);
	if($rating && $rating>0) {
		my $musicmagicurl = "http://$hostname:$port/api/setRating?song=$url&rating=$rating";
		my $http = LWP::UserAgent->new;
		$http->timeout(Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagictimeout"));
		my $response = $http->get($musicmagicurl);
		if($response->is_success) {
			my $result = $response->content;
			chomp $result;
	    	
			if($result && $result>0) {
				$log->debug("Set Rating=$rating for $url\n");
			}else {
				$log->warn("Failure setting Rating=$rating for $url\n");
			}
		}else {
			$log->warn("Failed to call MusicMagic at: $musicmagicurl\n");
		}
	}
	if($playCount) {
		my $musicmagicurl = "http://$hostname:$port/api/setPlayCount?song=$url&count=$playCount";
		my $http = LWP::UserAgent->new;
		$http->timeout(Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagictimeout"));
		my $response = $http->get($musicmagicurl);
		if($response->is_success) {
			my $result = $response->content;
			chomp $result;
	    	
			if($result && $result>0) {
				$log->debug("Set PlayCount=$playCount for $url\n");
			}else {
				$log->warn("Failure setting PlayCount=$playCount for $url\n");
			}
		}else {
			$log->warn("Failed to call MusicMagic at: $musicmagicurl\n");
		}
	}
	if($lastPlayed) {
		my $musicmagicurl = "http://$hostname:$port/api/setLastPlayed?song=$url&time=$lastPlayed";
		my $http = LWP::UserAgent->new;
		$http->timeout(Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagictimeout"));
		my $response = $http->get($musicmagicurl);
		if($response->is_success) {
			my $result = $response->content;
			chomp $result;
			
			if($result && $result>0) {
				$log->debug("Set LastPlayed=$lastPlayed for $url\n");
			}else {
				$log->warn("Failure setting LastPlayed=$lastPlayed for $url\n");
			}
		}else {
			$log->warn("Failed to call MusicMagic at: $musicmagicurl\n");
		}
	}
}


sub checkDefaults {
	if (!defined($prefs->get('lastMusicMagicDate'))) {
		$prefs->set('lastMusicMagicDate',0);
	}
	
	if (!defined($prefs->get('musicmagic_library_music_path'))) {
		$prefs->set('musicmagic_library_music_path','');
	}
}


sub sendTrackToStorage()
{
	my $url = shift;
	my $rating = shift;
	my $lastPlayed = shift;
	my $playCount = shift;

	Plugins::TrackStat::Storage::mergeTrack($url,undef,$playCount,$lastPlayed,$rating);
}

sub getMusicMagicURL {
	my $url = shift;
	my $replacePath = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicmusicpath");
	if(defined($replacePath) && $replacePath ne '') {
		$replacePath =~ s/\\/\//isg;
		$replacePath = escape($replacePath);
		my $nativeRoot = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicslimservermusicpath");;
		if(!defined($nativeRoot) || $nativeRoot eq '') {
			my $nativeRoot = $serverPrefs->get('audiodir');
		}
		my $nativeUrl = Slim::Utils::Misc::fileURLFromPath($nativeRoot);
		if($url =~ /$nativeUrl/) {
			$url =~ s/\\/\//isg;
			$nativeUrl =~ s/\\/\//isg;
			$url =~ s/$nativeUrl/$replacePath/isg;
		}else {
			$url = Slim::Utils::Misc::pathFromFileURL($url);
		}
	}else {
		$url = Slim::Utils::Misc::pathFromFileURL($url);
	}
	
	my $replaceExtension = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicextension");
	if($replaceExtension) {
		$url =~ s/\.[^.]*$/$replaceExtension/isg;
	}
	$url =~ s/\\/\//isg;
	$url = unescape($url);
	$url = URI::Escape::uri_escape($url);
	return $url;
}	

sub exportRating {
	my $url = shift;
	my $rating = shift;
	my $track = shift;
	my $lowrating = floor(($rating+10) / 20);

	if(Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicdynamicupdate")) {
		if(isAllowedToExport($url)) {
			my $mmurl = getMusicMagicURL($url);
		
			my $hostname = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagichost");
			my $port = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicport");
			my $musicmagicurl = "http://$hostname:$port/api/setRating?song=$mmurl&rating=$lowrating";
			$log->debug("Calling: $musicmagicurl\n");
			my $http = LWP::UserAgent->new;
			$http->timeout(Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagictimeout"));
			my $response = $http->get($musicmagicurl);
			if($response->is_success) {
				my $result = $response->content;
				chomp $result;
				if($result eq "1") {
					$log->debug("Success setting Music Magic rating\n");
				}else {
					$log->warn("Error setting Music Magic rating, error code = $result\n");
				}
				$http = LWP::UserAgent->new;
				$http->timeout(Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagictimeout"));
				$response = $http->get("http://$hostname:$port/api/flush");
				if(!$response->is_success) {
					$log->warn("Failed to flush MusicMagic cache"); 
				}
			}else {
				$log->warn("Failure setting Music Magic rating\n");
			}
		}else {
			$log->debug("Not setting rating, dynamic export isn't enabled for this track");
		}
	}else {
		$log->debug("Not setting rating, dynamic export isn't enabled");
	}
}
sub exportStatistic {
	my $url = shift;
	my $rating = shift;
	my $playCount = shift;
	my $lastPlayed = shift;

	if(Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicdynamicupdate")) {
		if(isAllowedToExport($url)) {
			my $mmurl = getMusicMagicURL($url);
		
			my $hostname = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagichost");
			my $port = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicport");
			my $musicmagicurl = "http://$hostname:$port/api/setPlayCount?song=$mmurl&count=$playCount";
			$log->debug("Calling: $musicmagicurl\n");
			my $http = Slim::Networking::SimpleAsyncHTTP->new(\&gotViaHTTP, \&gotErrorViaHTTP, {'command' => 'playCount' });
			$http->get($musicmagicurl);
			$musicmagicurl = "http://$hostname:$port/api/setLastPlayed?song=$mmurl&time=$lastPlayed";
			$log->debug("Calling: $musicmagicurl\n");
			$http = Slim::Networking::SimpleAsyncHTTP->new(\&gotViaHTTP, \&gotErrorViaHTTP, {'command' => 'lastPlayed' });
			$http->get($musicmagicurl);
			$http = Slim::Networking::SimpleAsyncHTTP->new(\&gotViaHTTP, \&gotErrorViaHTTP, {'command' => 'flush' });
			$http->get("http://$hostname:$port/api/flush");
		}else {
			$log->debug("Not setting statistic, dynamic export isn't enabled for this track");
		}
	}else {
		$log->debug("Not setting statistic, dynamic export isn't enabled");
	}
}

sub isAllowedToExport {
	my $url = shift;

	my $include = 1;
	my $libraries = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicexportlibraries");
	if(Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicexportlibrariesdynamicupdate") && $libraries && Plugins::TrackStat::Plugin::isPluginsInstalled(undef,"MultiLibrary::Plugin")) {
		my $sql = "SELECT tracks.id FROM tracks,multilibrary_track where tracks.id=multilibrary_track.track and tracks.url=? and multilibrary_track.library in ($libraries)";
		my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
		$log->debug("Executing: $sql\n");
		eval {
			my $sth = $dbh->prepare( $sql );
			$sth->bind_param(1,$url,SQL_VARCHAR);
			$sth->execute();
			$sth->bind_columns( undef, \$include);
			if( !$sth->fetch() ) {
				$log->debug("Ignoring track, not part of selected libraries: ".$url."\n");
				$include = 0;
			}
			$sth->finish();
		};
		if($@) {
			warn "Database error: $DBI::errstr, $@\n";
		}
	}
	return $include;
}

sub gotViaHTTP {
	my $http  = shift;
	my $params = $http->params;
	my $result = $http->content;
	chomp $result;
	if($result eq "1") {
		$log->debug("Success setting Music Magic ".$params->{'command'}."\n");
	}else {
		$log->warn("Error setting Music Magic ".$params->{'command'}.", error code = $result\n");
	}
	$http->close();
}

sub gotErrorViaHTTP {
	my $http  = shift;
	my $params = $http->params;
	$log->warn("Failure setting Music Magic ".$params->{'command'}."\n");
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
