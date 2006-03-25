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
	
sub canUseMusicMagic {

	checkDefaults();

	my $enabled = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_enabled");
		
	return $enabled;
}

sub startExport {
	if (!canUseMusicMagic()) {
		return;
	}
	
	my $sql = "SELECT url, playCount, lastPlayed, rating FROM track_statistics";

	my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
	my $sth = $dbh->prepare( $sql );
	$sth->execute();
	@songs = ();
	my( $url, $playCount, $lastPlayed, $rating );
	eval {
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
	};
	stopScan();

	$isScanning = 1;
	$MusicMagicScanStartTime = time();

	Slim::Utils::Scheduler::add_task(\&scanFunction);
}

sub stopScan {

	if (stillScanning()) {

		debugMsg("Was stillScanning - stopping old scan.\n");

		Slim::Utils::Scheduler::remove_task(\&scanFunction);
		$isScanning = 0;
		
		resetScanState();
	}
}

sub stillScanning {
	return $isScanning;
}

sub doneScanning {
	debugMsg("done Scanning: unlocking and closing\n");

	$lastMusicMagicFinishTime = time();
	$isScanning = 0;

	my $hostname = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_host");
	my $port = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_port");
	my $musicmagicurl = "http://$hostname:$port/api/cacheid";
	debugMsg("Calling: $musicmagicurl\n");
	my $http = Slim::Player::Protocols::HTTP->new({
        'url'    => "$musicmagicurl",
        'create' => 0,
    });
    if(defined($http)) {
		my $modificationTime = $http->content();
		$http->close();
		chomp $modificationTime;

		$lastMusicMagicDate = $modificationTime;
	}else {
		msg("Failed to call MusicMagic at: $musicmagicurl\n");
	}

	msg("TrackStat:MusicMagic: Export completed in ".(time() - $MusicMagicScanStartTime)." seconds.\n");

	Slim::Utils::Prefs::set('plugin_trackstat_lastMusicMagicDate', $lastMusicMagicDate);

	# Take the scanner off the scheduler.
	Slim::Utils::Scheduler::remove_task(\&scanFunction);
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
		return 0;
	}
}

sub handleTrack {
	my $track = shift;

	my $url = $track->url();
	my $rating = $track->rating();
	my $playCount = $track->playCount();
	my $lastPlayed = $track->lastPlayed();

	$url =~ s/\\/\//isg;

	$track = escape($track);
	
	my $hostname = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_host");
	my $port = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_port");
	my $replacePath = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_library_music_path");
	if(defined(!$replacePath) && $replacePath ne '') {
		$replacePath =~ s/\\/\//isg;
		$replacePath = escape($replacePath);
		my $nativeRoot = Slim::Utils::Prefs::get('audiodir');
		my $nativeUrl = Slim::Utils::Misc::fileURLFromPath($nativeRoot);
		$nativeUrl =~ s/\\/\//isg;
		$url =~ s/$nativeUrl/$replacePath/isg;
	}else {
		my $nativeRoot = Slim::Utils::Prefs::get('audiodir');
		my $nativeUrl = Slim::Utils::Misc::fileURLFromPath($nativeRoot);
		$url =~ s/$nativeUrl/$nativeRoot/isg;
	}
	
	my $replaceExtension = Slim::Utils::Prefs::get('plugin_trackstat_musicmagic_replace_extension');;
	if($replaceExtension) {
		$url =~ s/\.[^.]*$/$replaceExtension/isg;
	}
	$url =~ s/\\/\//isg;
	
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
			msg("Failed to call MusicMagic at: $musicmagicurl\n");
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
			msg("Failed to call MusicMagic at: $musicmagicurl\n");
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
			msg("Failed to call MusicMagic at: $musicmagicurl\n");
		}
	}
}


sub resetScanState {

	debugMsg("Resetting scan state.\n");

	@songs = ();
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

# A wrapper to allow us to uniformly turn on & off debug messages
sub debugMsg
{
	my $message = join '','TrackStat::MusicMagic: ',@_;
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
