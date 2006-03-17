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
                   
package Plugins::TrackStat::MusicMagic::Import;

use Slim::Utils::Misc;

my $lastMusicMagicFinishTime = undef;
my $lastMusicMagicDate = 0;
my $MusicMagicScanStartTime = 0;

my $isScanning = 0;

my @songs = ();

sub canUseMusicMagic {

	checkDefaults();

	my $enabled = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_enabled");
		
	return $enabled;
}

sub isMusicLibraryFileChanged {

	my $hostname = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_host");
	my $port = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_port");
	my $musicmagicurl = "http://$hostname:$port/api/cacheid";
	my $http = Slim::Player::Protocols::HTTP->new({
        'url'    => "$musicmagicurl",
        'create' => 0,
    });
    if(defined($http)) {
		my $modificationTime = $http->content();
		$http->close();
		chomp $modificationTime;

		# Set this so others can use it without going through Prefs in a tight loop.
		$lastMusicMagicDate = Slim::Utils::Prefs::get('plugin_trackstat_lastMusicMagicDate');
		
		# Only say "yes" if it has been more than one minute since we last finished scanning
		# and the file mod time has changed since we last scanned. Note that if we are
		# just starting, lastMusicMagicDate is undef, so both $fileMTime
		# will be greater than 0 and time()-0 will be greater than 180 :-)
		if ($modificationTime > $lastMusicMagicDate) {
			debugMsg("music library has changed: %s\n", scalar localtime($lastMusicMagicDate));
			
			return 1 if (!$lastMusicMagicFinishTime);

			return 1;
		}
	}
	return 0;
}

sub startImport {
	if (!canUseMusicMagic()) {
		return;
	}
	
	if(!isMusicLibraryFileChanged()) {
		return;
	}
		
	my $hostname = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_host");
	my $port = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_port");
	my $musicmagicurl = "http://$hostname:$port/api/songs?extended";
	debugMsg("Calling: $musicmagicurl\n");
	my $http = Slim::Player::Protocols::HTTP->new({
        'url'    => "$musicmagicurl",
        'create' => 0,
    });

    if(defined($http)) {
		stopScan();
		@songs = split(/\n\n/, $http->content);
		$http->close();

		$isScanning = 1;
		$MusicMagicScanStartTime = time();

		Slim::Utils::Scheduler::add_task(\&scanFunction);
	}
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
	}

	msg("TrackStat:MusicMagic: Import completed in ".(time() - $MusicMagicScanStartTime)." seconds.\n");

	Slim::Utils::Prefs::set('plugin_trackstat_lastMusicMagicDate', $lastMusicMagicDate);

	# Take the scanner off the scheduler.
	Slim::Utils::Scheduler::remove_task(\&scanFunction);
}

sub scanFunction {
	# parse a little more from the stream.
	if (scalar(@songs)>0) {
		for (my $i = 0; $i < 25 && scalar(@songs)>0; $i++) {
			my $song = shift @songs;
			if ($song) {
				handleTrack($song);
			}
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
	my $trackData = shift;
	
	my @rows = split(/\n/, $trackData);
	
	my $url;
	my $rating;
	my $playCount;
	my $lastPlayed;
	
	for my $row (@rows) {
		if(substr($row,0,4) eq "file") {
			$url = substr($row,4);
			$url =~ s/^\s+//;
			$url =~ s/\s+$//;
		}elsif(substr($row,0,6) eq "rating") {
			$rating = substr($row,6);
			$url =~ s/^\s+//;
			$url =~ s/\s+$//;
			$rating = $rating * 20;
		}elsif(substr($row,0,9) eq "playcount") {
			$playCount = substr($row,9);
			$url =~ s/^\s+//;
			$url =~ s/\s+$//;
		}elsif(substr($row,0,10) eq "lastplayed") {
			$lastPlayed = substr($row,10);
			$url =~ s/^\s+//;
			$url =~ s/\s+$//;
		}
	}
	
	if($url && ($playCount || $rating)) {
		my $replacePath = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_library_music_path");
		if(defined(!$replacePath) && $replacePath ne '') {
			$url =~ s/\\/\//isg;
			$replacePath =~ s/\\/\//isg;
			my $nativeRoot = Slim::Utils::Prefs::get('audiodir');
			$url =~ s/$replacePath/$nativeRoot/isg;
			$url = Slim::Utils::Misc::fileURLFromPath($url);
		}else {
			$url = Slim::Utils::Misc::fileURLFromPath($url);
		}
		
		my $replaceExtension = Slim::Utils::Prefs::get('plugin_trackstat_musicmagic_slimserver_replace_extension');;
		if($replaceExtension) {
			$url =~ s/\.[^.]*$/$replaceExtension/isg;
		}
		$url =~ s/\\/\//isg;
		debugMsg("Store Track: $url\n");
		sendTrackToStorage($url,$rating,$lastPlayed,$playCount);
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
