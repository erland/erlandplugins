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

use Slim::Utils::Misc;
use Class::Struct;

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

sub getCustomScanFunctions {
	my %functions = (
		'id' => 'musicmagicexport',
		'order' => '75',
		'defaultenabled' => 0,
		'name' => 'MusicIP Statistic Export',
		'description' => "This module exports statistic information in SlimServer to MusicIP Mixer. The information exported are ratings, playcounts, last played time<br><br>The export module is prepared for having separate libraries in MusicIP and SlimServer, for example the MusicIP library can be on a Windows computer in mp3 format and the SlimServer library can be on a Linux computer with flac format. The music path and file extension parameters will in this case be used to convert the exported data so it corresponds to the paths and files used in MusicIP. If you are running MusicIP and SlimServer on the same computer towards the same library the music path and file extension parameters can typically be left empty.",
		'alwaysRescanTrack' => 1,
		'initScanTrack' => \&initScanTrack,
		'exitScanTrack' => \&scanFunction,
		'scanText' => 'Export',
		'properties' => [
			{
				'id' => 'musicmagichost',
				'name' => 'MusicIP hostname',
				'description' => 'Hostname of computer where MusicIP is running',
				'type' => 'text',
				'value' => defined(Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_host"))?Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_host"):Slim::Utils::Prefs::get('MMSHost')
			},
			{
				'id' => 'musicmagicport',
				'name' => 'MusicIP port',
				'description' => 'Port which is used for MusicIP',
				'type' => 'text',
				'value' => defined(Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_port"))?Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_port"):Slim::Utils::Prefs::get('MMSport')
			},
			{
				'id' => 'musicmagicextension',
				'name' => 'File extension in MusicIP',
				'description' => 'File extension in MusicIP (for example .mp3), empty means same file extension as in SlimServer',
				'type' => 'text',
				'value' => Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_replace_extension")
			},
			{
				'id' => 'musicmagicmusicpath',
				'name' => 'Music path in MusicIP',
				'description' => 'Path to main music directory in MusicIP, empty means same music path as in SlimServer',
				'type' => 'text',
				'value' => Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_export_library_music_path")
			},
			{
				'id' => 'musicmagicslimservermusicpath',
				'name' => 'Music path in SlimServer',
				'description' => 'Path to main music directory in SlimServer, empty means same music path as in SlimServer',
				'type' => 'text',
				'validate' => \&Plugins::TrackStat::Plugin::validateIsDirOrEmpty,
				'value' => Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_library_music_path")
			},
			{
				'id' => 'musicmagicdynamicupdate',
				'name' => 'Dynamically update statistics',
				'description' => 'Continously write statistics to MusicIP when ratings are changed and songs are played in SlimServer',
				'type' => 'checkbox',
				'value' => defined(Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_enabled"))?Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_enabled"):0
			}
		]
	);
	return \%functions;
		
}

sub initScanTrack {
	checkDefaults();
	@songs = ();
	$MusicMagicScanStartTime = time();
	
	my $sql = "SELECT track_statistics.url, track_statistics.playCount, track_statistics.lastPlayed, track_statistics.rating FROM track_statistics,tracks where track_statistics.url=tracks.url and (track_statistics.lastPlayed is not null or track_statistics.rating>0)";

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
		msg("TrackStat::MusicMagic::Export: SQL error: $DBI::errstr, $@\n");
		$isScanning = -1;
	}
	$isScanning = 1;
	return undef;
}

sub doneScanning {
	debugMsg("done Scanning: unlocking and closing\n");

	$lastMusicMagicFinishTime = time();

	my $hostname = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagichost");;
	my $port = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicport");;
	my $musicmagicurl = "http://$hostname:$port/api/cacheid";
	debugMsg("Calling: $musicmagicurl\n");
	my $http = Slim::Player::Protocols::HTTP->new({
        	'url'    => "http://$hostname:$port/api/flush",
        	'create' => 0,
    	});
    	if(defined($http)) {
    		my $result = $http->content;
	    	$http->close();
	}
	$http = Slim::Player::Protocols::HTTP->new({
		'url'    => "$musicmagicurl",
		'create' => 0,
	});
	if(defined($http)) {
		my $modificationTime = $http->content();
		$http->close();
		chomp $modificationTime;

		$lastMusicMagicDate = $modificationTime;
	}else {
		$isScanning = -1;
		msg("TrackStat::MusicMagic::Export: Failed to call MusicMagic at: $musicmagicurl\n");
	}

	if($isScanning==1) {
		$isScanning = 0;
		msg("TrackStat::MusicMagic::Export: Export completed in ".(time() - $MusicMagicScanStartTime)." seconds.\n");
		Slim::Utils::Prefs::set('plugin_trackstat_lastMusicMagicDate', $lastMusicMagicDate);
	}elsif($isScanning==-1) {
		msg("TrackStat::MusicMagic::Export: Export failed after ".(time() - $MusicMagicScanStartTime)." seconds.\n");
	}else {
		msg("TrackStat::MusicMagic::Export: Export skipped after ".(time() - $MusicMagicScanStartTime)." seconds.\n");
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

	$track = escape($track);
	
	my $hostname = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagichost");;
	my $port = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicport");
	$url = getMusicMagicURL($url);
	if($rating && $rating>0) {
		my $musicmagicurl = "http://$hostname:$port/api/setRating?song=$url&rating=$rating";
		my $http = Slim::Player::Protocols::HTTP->new({
	        'url'    => "$musicmagicurl",
	        'create' => 0,
	    });
	    if(defined($http)) {
	    	my $result = $http->content;
	    	$http->close();
	    	chomp $result;
	    	
	    	if($result && $result>0) {
	    		debugMsg("Set Rating=$rating for $url\n");
	    	}else {
	    		debugMsg("Failure setting Rating=$rating for $url\n");
	    	}
		}else {
			msg("TrackStat::MusicMagic::Export: Failed to call MusicMagic at: $musicmagicurl\n");
		}
	}
	if($playCount) {
		my $musicmagicurl = "http://$hostname:$port/api/setPlayCount?song=$url&count=$playCount";
		my $http = Slim::Player::Protocols::HTTP->new({
	        'url'    => "$musicmagicurl",
	        'create' => 0,
	    });
	    if(defined($http)) {
	    	my $result = $http->content;
	    	$http->close();
	    	chomp $result;
	    	
	    	if($result && $result>0) {
	    		debugMsg("Set PlayCount=$playCount for $url\n");
	    	}else {
	    		debugMsg("Failure setting PlayCount=$playCount for $url\n");
	    	}
		}else {
			msg("TrackStat::MusicMagic::Export: Failed to call MusicMagic at: $musicmagicurl\n");
		}
	}
	if($lastPlayed) {
		my $musicmagicurl = "http://$hostname:$port/api/setLastPlayed?song=$url&time=$lastPlayed";
		my $http = Slim::Player::Protocols::HTTP->new({
	        'url'    => "$musicmagicurl",
	        'create' => 0,
	    });
	    if(defined($http)) {
	    	my $result = $http->content;
	    	$http->close();
	    	chomp $result;
	    	
	    	if($result && $result>0) {
	    		debugMsg("Set LastPlayed=$lastPlayed for $url\n");
	    	}else {
	    		debugMsg("Failure setting LastPlayed=$lastPlayed for $url\n");
	    	}
		}else {
			msg("TrackStat::MusicMagic::Export: Failed to call MusicMagic at: $musicmagicurl\n");
		}
	}
}


sub checkDefaults {
	if (!Slim::Utils::Prefs::isDefined('lastMusicMagicDate')) {
		Slim::Utils::Prefs::set('plugin_trackstat_lastMusicMagicDate',0);
	}
	
	if (!Slim::Utils::Prefs::isDefined('plugin_trackstat_musicmagic_library_music_path')) {
		Slim::Utils::Prefs::set('plugin_trackstat_musicmagic_library_music_path','');
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
	if(defined(!$replacePath) && $replacePath ne '') {
		$replacePath =~ s/\\/\//isg;
		$replacePath = escape($replacePath);
		my $nativeRoot = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicslimservermusicpath");;
		if(!defined($nativeRoot) || $nativeRoot eq '') {
			my $nativeRoot = Slim::Utils::Prefs::get('audiodir');
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
		my $mmurl = getMusicMagicURL($url);
		
		my $hostname = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagichost");
		my $port = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicport");
		my $musicmagicurl = "http://$hostname:$port/api/setRating?song=$mmurl&rating=$lowrating";
		debugMsg("Calling: $musicmagicurl\n");
		my $http = Slim::Player::Protocols::HTTP->new({
			'url'    => "$musicmagicurl",
			'create' => 0,
		});
		if(defined($http)) {
			my $result = $http->content;
			chomp $result;
			if($result eq "1") {
				debugMsg("Success setting Music Magic rating\n");
			}else {
				debugMsg("Error setting Music Magic rating, error code = $result\n");
			}
			$http->close();
			$http = Slim::Player::Protocols::HTTP->new({
				'url'    => "http://$hostname:$port/api/flush",
				'create' => 0,
			});
			if(defined($http)) {
				$result = $http->content;
				$http->close();
			}
		}else {
			debugMsg("Failure setting Music Magic rating\n");
		}
	}
}
sub exportStatistic {
	my $url = shift;
	my $rating = shift;
	my $playCount = shift;
	my $lastPlayed = shift;

	if(Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicdynamicupdate")) {
		my $mmurl = getMusicMagicURL($url);
		
		my $hostname = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagichost");
		my $port = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicport");
		my $musicmagicurl = "http://$hostname:$port/api/setPlayCount?song=$mmurl&count=$playCount";
		debugMsg("Calling: $musicmagicurl\n");
		my $http = Slim::Networking::SimpleAsyncHTTP->new(\&gotViaHTTP, \&gotErrorViaHTTP, {'command' => 'playCount' });
		$http->get($musicmagicurl);
		$musicmagicurl = "http://$hostname:$port/api/setLastPlayed?song=$mmurl&time=$lastPlayed";
		debugMsg("Calling: $musicmagicurl\n");
		$http = Slim::Networking::SimpleAsyncHTTP->new(\&gotViaHTTP, \&gotErrorViaHTTP, {'command' => 'lastPlayed' });
		$http->get($musicmagicurl);
		$http = Slim::Networking::SimpleAsyncHTTP->new(\&gotViaHTTP, \&gotErrorViaHTTP, {'command' => 'flush' });
		$http->get("http://$hostname:$port/api/flush");
	}
}

sub gotViaHTTP {
	my $http  = shift;
	my $params = $http->params;
	my $result = $http->content;
	chomp $result;
	if($result eq "1") {
		debugMsg("Success setting Music Magic ".$params->{'command'}."\n");
	}else {
		debugMsg("Error setting Music Magic ".$params->{'command'}.", error code = $result\n");
	}
	$http->close();
}

sub gotErrorViaHTTP {
	my $http  = shift;
	my $params = $http->params;
	debugMsg("Failure setting Music Magic ".$params->{'command'}."\n");
}

# A wrapper to allow us to uniformly turn on & off debug messages
sub debugMsg
{
	my $message = join '','TrackStat::MusicMagic::Export: ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_trackstat_showmessages"));
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
