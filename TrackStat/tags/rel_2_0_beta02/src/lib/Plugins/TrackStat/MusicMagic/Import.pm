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

use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use DBI qw(:sql_types);
use Plugins::CustomScan::Validators;

my $prefs = preferences('plugin.trackstat');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.trackstat',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_TRACKSTAT',
});

my $lastMusicMagicFinishTime = undef;
my $lastMusicMagicDate = 0;
my $MusicMagicScanStartTime = 0;

my $isScanning = 0;
my $importCount;
my @songs = ();

sub getCustomScanFunctions {
	my %functions = (
		'id' => 'musicmagicimport',
		'order' => '70',
		'defaultenabled' => 0,
		'name' => 'MusicIP Statistics Import',
		'description' => "This module imports statistic information in SlimServer from MusicIP Mixer. The information imported are ratings, playcounts, last played time<br>Information is imported from the MusicIP service running at the specified host and port, if there are any existing ratings, play counts or last played information in TrackStat these might be overwritten. There is some logic to avoid overwrite when it isn\'t needed but this shouldn\'t be trusted.<br><br>The import module is prepared for having separate libraries in MusicIP and SlimServer, for example the MusicIP library can be on a Windows computer in mp3 format and the SlimServer library can be on a Linux computer with flac format. The music path and file extension parameters will in this case be used to convert the imported data so it corresponds to the paths and files used in SlimServer. If you are running MusicIP and SlimServer on the same computer towards the same library the music path and file extension parameters can typically be left empty.",
		'alwaysRescanTrack' => 1,
		'clearEnabled' => 0,
		'initScanTrack' => \&initScanTrack,
		'exitScanTrack' => \&scanFunction,
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
				'id' => 'musicmagicslimserverextension',
				'name' => 'File extension in SlimServer',
				'description' => 'File extension in SlimServer (for example .flac), empty means same file extension as in MusicIP',
				'type' => 'text',
				'value' => $prefs->get("musicmagic_slimserver_replace_extension")
			},
			{
				'id' => 'musicmagicmusicpath',
				'name' => 'Music path in MusicIP',
				'description' => 'Path to main music directory in MusicIP, empty means same music path as in SlimServer',
				'type' => 'text',
				'value' => $prefs->get("musicmagic_export_library_music_path")
			},
			{
				'id' => 'musicmagicslimservermusicpath',
				'name' => 'Music path in SlimServer',
				'description' => 'Path to main music directory in SlimServer, empty means same music path as in SlimServer',
				'type' => 'text',
				'validate' => \&Plugins::CustomScan::Validators::isDirOrEmpty,
				'value' => $prefs->get("musicmagic_library_music_path")
			},
			{
				'id' => 'musicmagicslimserverutf8',
				'name' => 'SlimServer uses UTF-8 encoded filesystem',
				'description' => 'SlimServer uses UTF-8 encoded filesystem',
				'type' => 'checkbox',
				'value' => (Slim::Utils::OSDetect::OS() eq 'win')?0:1
			}
		]
	);
	if(Plugins::TrackStat::Plugin::isPluginsInstalled(undef,"MultiLibrary::Plugin")) {
		my $properties = $functions{'properties'};
		my $values = Plugins::TrackStat::Storage::getSQLPropertyValues("select id,name from multilibrary_libraries");
		my %library = (
			'id' => 'musicmagicimportlibraries',
			'name' => 'Libraries to limit the import to',
			'description' => 'Limit the import to songs in the selected libraries (None selected equals no limit)',
			'type' => 'multiplelist',
			'values' => $values,
			'value' => '',
		);
		push @$properties,\%library;
	}
	return \%functions;
		
}

sub isMusicLibraryFileChanged {

	my $hostname = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagichost");
	my $port = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicport");
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
		$lastMusicMagicDate = $prefs->get('lastMusicMagicDate');
		
		# Only say "yes" if it has been more than one minute since we last finished scanning
		# and the file mod time has changed since we last scanned. Note that if we are
		# just starting, lastMusicMagicDate is undef, so both $fileMTime
		# will be greater than 0 and time()-0 will be greater than 180 :-)
		if ($modificationTime > $lastMusicMagicDate) {
			$log->debug("music library has changed: ".scalar localtime($lastMusicMagicDate)."\n");
			
			return 1 if (!$lastMusicMagicFinishTime);

			return 1;
		}
	}else {
		$log->warn("Failed to call MusicMagic at: $musicmagicurl\n");
		return -1;
	}
	return 0;
}

sub initScanTrack {
	my $context = shift;

	checkDefaults();
	@songs = ();
	$importCount = 0;
	$MusicMagicScanStartTime = time();

	my $musicMagicStatus = isMusicLibraryFileChanged();
	if($musicMagicStatus==-1) {
		$isScanning = -1;
		return undef;
	}elsif(!$musicMagicStatus) {
		$isScanning = 0;
		return undef;
	}
	$isScanning = 1;
		
	my $hostname = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagichost");
	my $port = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicport");
	my $musicmagicurl = "http://$hostname:$port/api/songs?extended";
	$log->debug("Calling: $musicmagicurl\n");
	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "$musicmagicurl",
		'create' => 0,   
        });
	if(defined($http)) {
		$log->debug("Got answer from Music Magic after ".(time() - $MusicMagicScanStartTime)." seconds\n");
		
		@songs = split(/\n\n/, $http->content);
		$log->debug("Got ".scalar(@songs)." number of songs\n");
		$http->close();

	}else {
		$log->debug("Failure answer from Music Magic\n");
		$isScanning = -1;
	}
	return undef;
}

sub doneScanning {
	$log->debug("done Scanning: unlocking and closing\n");

	$lastMusicMagicFinishTime = time();

	my $hostname = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagichost");
	my $port = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicport");
	my $musicmagicurl = "http://$hostname:$port/api/cacheid";
	$log->debug("Calling: $musicmagicurl\n");
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
		$log->debug("Failed to call MusicMagic at: $musicmagicurl\n");
	}

	if($isScanning==1) {
		$isScanning = 0;
		$prefs->set('lastMusicMagicDate', $lastMusicMagicDate);
		$log->info("TrackStat::MusicMagic::Import: Import completed in ".(time() - $MusicMagicScanStartTime)." seconds, imported statistics for $importCount songs.\n");
	}elsif($isScanning==-1) {
		$log->info("TrackStat::MusicMagic::Import: Import failed after ".(time() - $MusicMagicScanStartTime)." seconds, imported statistics for $importCount songs.\n");
	}else {
		$log->info("TrackStat::MusicMagic::Import: Import skipped after ".(time() - $MusicMagicScanStartTime)." seconds, imported statistics for $importCount songs.\n");
	}
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
		return undef;
	}
}

sub handleTrack {
	my $trackData = shift;
	#$log->debug("Start handling next track\n");
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
			$url = Slim::Utils::Unicode::utf8decode($url,'utf8');
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
	
	#$log->debug("Handling track: $url\n");
	my $debugString = undef;
	if($rating) {
		$debugString.="Got: ";
		$debugString.="Rating: $rating";
	}
	if($playCount) {
		if(!$debugString) {
			$debugString.="Got: ";
		}
		$debugString.=", PlayCount: $playCount";
	}
	if($lastPlayed) {
		if(!$debugString) {
			$debugString.="Got: ";
		}
		$debugString.=", LastPlayed: $lastPlayed";
	}
	if($debugString) {
		$log->debug($debugString."\n");
	}

	if($url && ($playCount || $rating)) {
		my $replacePath = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicmusicpath");
		if(defined(!$replacePath) && $replacePath ne '') {
			$url =~ s/\\/\//isg;
			$replacePath =~ s/\\/\//isg;
			my $nativeRoot = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicslimservermusicpath");;
			if(!defined($nativeRoot) || $nativeRoot eq '') {
				my $nativeRoot = $serverPrefs->get('audiodir');
			}
			$url =~ s/$replacePath/$nativeRoot/isg;
			$url = Slim::Utils::Misc::fileURLFromPath($url);
		}else {
			$url = Slim::Utils::Misc::fileURLFromPath($url);
		}

		if(Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicslimserverutf8")) {
			my $path = Slim::Utils::Misc::pathFromFileURL($url);
			$path = Slim::Utils::Unicode::utf8off($path);
			$url = Slim::Utils::Misc::fileURLFromPath($path);
		}
		
		my $replaceExtension = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicslimserverextension");
		if($replaceExtension) {
			my $path = Slim::Utils::Misc::pathFromFileURL($url);
			if(! -e $path) {
				$url =~ s/\.[^.]*$/$replaceExtension/isg;
			}
		}
		$url =~ s/\\/\//isg;
		$log->debug("Store Track: $url\n");
		$importCount++;
		sendTrackToStorage($url,$rating,$lastPlayed,$playCount);
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

	my $libraries = Plugins::CustomScan::Plugin::getCustomScanProperty("musicmagicimportlibraries");

	if($libraries && Plugins::TrackStat::Plugin::isPluginsInstalled(undef,"MultiLibrary::Plugin")) {
		my $ds = Plugins::TrackStat::Storage::getCurrentDS();
		my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
		
		my $sth = $dbh->prepare( "SELECT id from tracks,multilibrary_track where tracks.id=multilibrary_track.track and multilibrary_track.library in ($libraries) and tracks.url=?" );
		my $include = 1;
		eval {
			$sth->bind_param(1, $url , SQL_VARCHAR);
			$sth->execute();
			my $id;
			$sth->bind_columns( undef, \$id);
			if( !$sth->fetch() ) {
				$log->debug("Ignoring track, doesnt exist in selected libraries: $url\n");
				$include = 0;
			}
		};
		if($@) {
			$log->warn("Database error: $DBI::errstr for track: $url\n");
			$include = 0;
		}
		if(!$include) {
			return;
		}
	}

	Plugins::TrackStat::Storage::mergeTrack($url,undef,$playCount,$lastPlayed,$rating);
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
