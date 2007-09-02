#         TrackStat::iTunes module
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
                   
package Plugins::TrackStat::iTunes::Import;

use Date::Parse qw(str2time);
use Fcntl ':flock'; # import LOCK_* constants
use File::Spec::Functions qw(:ALL);
use File::Basename;
use XML::Parser;
use DBI qw(:sql_types);
use Plugins::TrackStat::Storage;
use Plugins::TrackStat::Plugin;

if ($] > 5.007) {
	require Encode;
}

use Slim::Utils::Misc;

my $lastMusicLibraryFinishTime = undef;
my $lastITunesMusicLibraryDate = 0;
my $iTunesScanStartTime = 0;

my $isScanning = 0;
my $opened = 0;
my $locked = 0;
my $iBase = '';

my $inPlaylists;
my $inTracks;
my %tracks;
my $importCount;

my $iTunesLibraryFile;
my $iTunesParser;
my $iTunesParserNB;
my $offset = 0;

my ($inKey, $inDict, $inValue, %item, $currentKey, $nextIsMusicFolder, $nextIsPlaylistName, $inPlaylistArray);

# mac file types
our %filetypes = (
	1095321158 => 'aif', # AIFF
	1295270176 => 'mov', # M4A
	1295270432 => 'mov', # M4B
#	1295274016 => 'mov', # M4P
	1297101600 => 'mp3', # MP3
	1297101601 => 'mp3', # MP3!
	1297106247 => 'mp3', # MPEG
	1297106738 => 'mp3', # MPG2
	1297106739 => 'mp3', # MPG3
	1299148630 => 'mov', # MooV
	1299198752 => 'mp3', # Mp3
	1463899717 => 'wav', # WAVE
	1836069665 => 'mp3', # mp3!
	1836082995 => 'mp3', # mpg3
	1836082996 => 'mov', # mpg4
);
my $replaceExtension = undef;

sub getCustomScanFunctions {
	my %functions = (
		'id' => 'itunesimport',
		'order' => '70',
		'defaultenabled' => 0,
		'name' => 'iTunes Statistics Import',
		'description' => "This module imports statistic information in SlimServer from iTunes. The information imported are ratings, playcounts, last played time<br>Information is imported from the specified iTunes Music Library.xml file, if there are any existing ratings, play counts or last played information in TrackStat these might be overwritten. There is some logic to avoid overwrite when it isn\'t needed but this shouldn\'t be trusted.<br><br>The import module is prepared for having separate libraries in iTunes and SlimServer, for example the iTunes library can be on a Windows computer in mp3 format and the SlimServer library can be on a Linux computer with flac format. The music path and file extension parameters will in this case be used to convert the imported data so it corresponds to the paths and files used in SlimServer. If you are running iTunes and SlimServer on the same computer towards the same library the music path and file extension parameters can typically be left empty.",
		'alwaysRescanTrack' => 1,
		'clearEnabled' => 0,
		'initScanTrack' => \&initScanTrack,
		'exitScanTrack' => \&scanFunction,
		'properties' => [
			{
				'id' => 'ituneslibraryfile',
				'name' => 'iTunes Library XML file',
				'description' => 'Full path to iTunes Music Library.xml file to read',
				'type' => 'text',
				'validate' => \&Slim::Utils::Validate::isFile,
				'value' => Slim::Utils::Prefs::get("plugin_trackstat_itunes_library_file")
			},
			{
				'id' => 'itunesslimserverextension',
				'name' => 'File extension in SlimServer',
				'description' => 'File extension in SlimServer (for example .flac), empty means same file extension as in iTunes',
				'type' => 'text',
				'value' => Slim::Utils::Prefs::get("plugin_trackstat_itunes_replace_extension")
			},
			{
				'id' => 'itunesslimservermusicpath',
				'name' => 'Music path in SlimServer',
				'description' => 'Path to main music directory in SlimServer, empty means same music path as in SlimServer',
				'type' => 'text',
				'validate' => \&Plugins::TrackStat::Plugin::validateIsDirOrEmpty,
				'value' => Slim::Utils::Prefs::get("plugin_trackstat_itunes_library_music_path")
			},
			{
				'id' => 'itunesignoredisabledtracks',
				'name' => 'Ignore disabled songs',
				'description' => 'Indicates that disabled songs in iTunes shouldn\'t be imported',
				'type' => 'checkbox',
				'value' => 1
			}
		]
	);
	if(Plugins::TrackStat::Plugin::isPluginsInstalled(undef,"MultiLibrary::Plugin")) {
		my $properties = $functions{'properties'};
		my $values = Plugins::TrackStat::Storage::getSQLPropertyValues("select id,name from multilibrary_libraries");
		my %library = (
			'id' => 'itunesimportlibraries',
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

sub canUseiTunesLibrary {

	checkDefaults();

	return defined findMusicLibraryFile();
}

sub findMusicLibraryFile {

	return $iTunesLibraryFile;
}

sub isMusicLibraryFileChanged {

	my $file      = findMusicLibraryFile();
	my $fileMTime = (stat $file)[9];

	# Set this so others can use it without going through Prefs in a tight loop.
	$lastITunesMusicLibraryDate = Slim::Utils::Prefs::get('plugin_trackstat_lastITunesMusicLibraryDate');
	
	# Only say "yes" if it has been more than one minute since we last finished scanning
	# and the file mod time has changed since we last scanned. Note that if we are
	# just starting, lastITunesMusicLibraryDate is undef, so both $fileMTime
	# will be greater than 0 and time()-0 will be greater than 180 :-)
	if ($file && $fileMTime > $lastITunesMusicLibraryDate) {
		debugMsg("music library has changed: %s\n", scalar localtime($lastITunesMusicLibraryDate));
		
		return 1 if (!$lastMusicLibraryFinishTime);

		return 1;
	}

	return 0;
}

sub initScanTrack {
	$iTunesLibraryFile = Plugins::CustomScan::Plugin::getCustomScanProperty("ituneslibraryfile");
	$replaceExtension = Plugins::CustomScan::Plugin::getCustomScanProperty("itunesslimserverextension");
	$iTunesScanStartTime = time();

	if (!canUseiTunesLibrary()) {
		$isScanning = 0;
		return undef;
	}
		
	my $file = findMusicLibraryFile();

	debugMsg("startScan on file: $file\n");

	if (!defined($file) || ! -e $file) {
		$isScanning = -1;
		warn "Trying to scan an iTunes file that doesn't exist.";
		return undef;
	}

	$locked = 0;
	$opened = 0;
	$iTunesParser = undef;
	resetScanState();

	$isScanning = 1;
	$importCount = 0;

	$iTunesParser = XML::Parser->new(
		'ErrorContext'     => 2,
		'ProtocolEncoding' => 'UTF-8',
		'NoExpand'         => 1,
		'NoLWP'            => 1,
		'Handlers'         => {

			'Start' => \&handleStartElement,
			'Char'  => \&handleCharElement,
			'End'   => \&handleEndElement,
		},
	);
	return undef;
}

sub doneScanning {
	debugMsg("done Scanning: unlocking and closing\n");

	if (defined $iTunesParserNB) {

		# This spews, but it's harmless.
		eval { $iTunesParserNB->parse_done };
	}

	$iTunesParserNB = undef;
	$iTunesParser   = undef;

	if($opened) {
		# Don't leak filehandles.
		close(ITUNESLIBRARY);
	}

	$locked = 0;
	$opened = 0;

	if($isScanning == 2) {
		$lastMusicLibraryFinishTime = time();
		$isScanning = 0;

		# Set the last change time for the next go-round.
		my $file  = findMusicLibraryFile();
		my $mtime = (stat($file))[9];

		$lastITunesMusicLibraryDate = $mtime;

		msg("TrackStat::iTunes::Import: Import completed in ".(time() - $iTunesScanStartTime)." seconds, imported statistics for $importCount songs\n");

		Slim::Utils::Prefs::set('plugin_trackstat_lastITunesMusicLibraryDate', $lastITunesMusicLibraryDate);
	}elsif($isScanning==-1) {
		msg("TrackStat::iTunes::Import: Import failed after ".(time() - $iTunesScanStartTime)." seconds, imported statistics for $importCount songs\n");
	}else {
		msg("TrackStat::iTunes::Import: Import skipped after ".(time() - $iTunesScanStartTime)." seconds, imported statistics for $importCount songs\n");
	}
}

sub scanFunction {
	if($isScanning==-1  || $isScanning==0) {
		doneScanning();
		return undef;
	}		
	# this assumes that iTunes uses file locking when writing the xml file out.
	if (!$opened) {

		debugMsg("opening iTunes Library XML file.\n");

		open(ITUNESLIBRARY, $iTunesLibraryFile) || do {
			warn "TrackStat::iTunes::Import: Couldn't open iTunes Library: $iTunesLibraryFile";
			$isScanning=-1;
			return undef;
		};

		$opened = 1;

		resetScanState();

		Slim::Utils::Prefs::set('plugin_trackstat_lastITunesMusicLibraryDate', (stat($iTunesLibraryFile))[9]);
	}

	if ($opened && !$locked) {

		debugMsg("Attempting to get lock on iTunes Library XML file.\n");

		$locked = 1;
		$locked = flock(ITUNESLIBRARY, LOCK_SH | LOCK_NB) unless ($^O eq 'MSWin32'); 

		if ($locked) {

			debugMsg("Got file lock on iTunes Library\n");

			$locked = 1;

			if (defined $iTunesParser) {

				debugMsg("Created a new Non-blocking XML parser.\n");

				$iTunesParserNB = $iTunesParser->parse_start();

			} else {

				debugMsg("No iTunesParser was defined!\n");
			}

		} else {

			warn "TrackStat::iTunes::Import: Waiting on lock for iTunes Library";
			return 1;
		}
	}

	# parse a little more from the stream.
	if (defined $iTunesParserNB) {

		debugMsg("Parsing next bit of XML..\n");

		local $/ = '</dict>';
		my $line;

		for (my $i = 0; $i < 25; $i++) {
			$line .= <ITUNESLIBRARY>;
		}

		$line =~ s/&#(\d*);/escape(chr($1))/ge;

		$iTunesParserNB->parse_more($line);

		if($isScanning==2) {
			doneScanning();
			return undef;
		}
		return 1;
	}

	msg("TrackStat:iTunes::Import: No iTunesParserNB defined!\n");
	$isScanning = -1;
	doneScanning();
	return undef;
}

sub getCurrentLocale {
	return Slim::Utils::Unicode::currentLocale();
}
sub handleTrack {
	my $curTrack = shift;

	my %cacheEntry = ();

	my $id       = $curTrack->{'Track ID'};
	my $location = $curTrack->{'Location'};
	my $filetype = $curTrack->{'File Type'};
	my $type     = undef;

	# We got nothin
	if (scalar keys %{$curTrack} == 0) {
		return 1;
	}

	if (defined $location) {
		$location = Slim::Utils::Unicode::utf8off($location);
	}

	if ($location =~ /^((\d+\.\d+\.\d+\.\d+)|([-\w]+(\.[-\w]+)*)):\d+$/) {
		$location = "http://$location"; # fix missing prefix in old invalid entries
	}

	my $url = normalize_location($location);
	my $file;

	if (Slim::Music::Info::isFileURL($url)) {

		$file  = Slim::Utils::Misc::pathFromFileURL($url);

		if ($] > 5.007 && $file && !-e $file && getCurrentLocale() ne 'utf8') {
			eval { Encode::from_to($file, 'utf8', getCurrentLocale()) };

			# If the user is using both iTunes & a music folder,
			# iTunes stores the url as encoded utf8 - but we want
			# it in the locale of the machine, so we won't get
			# duplicates.
			$url = Slim::Utils::Misc::fileURLFromPath($file);
		}
	}

	# Use this for playlist verification.
	$tracks{$id} = $url;

	if (Slim::Music::Info::isFileURL($url)) {

		# dsully - Sun Mar 20 22:50:41 PST 2005
		# iTunes has a last 'Date Modified' field, but
		# it isn't updated even if you edit the track
		# properties directly in iTunes (dumb) - the
		# actual mtime of the file is updated however.

		my $mtime = (stat($file))[9];

		# Reuse the stat from above.
		if (!$file || !-r _) { 
			debugMsg("file not found: $file\n");

			# Tell the database to cleanup.
			#$ds->markEntryAsInvalid($url);

			delete $tracks{$id};

			return 1;
		}
	}

	# skip track if Disabled in iTunes
	if ($curTrack->{'Disabled'} && !Plugins::CustomScan::Plugin::getCustomScanProperty("itunesignoredisabledtracks")) {

		debugMsg("deleting disabled track $url\n");

		#$ds->markEntryAsInvalid($url);

		# Don't show these tracks in the playlists either.
		delete $tracks{$id};

		return 1;
	}

	debugMsg("got a track named " . $curTrack->{'Name'} . " location: $url\n");

	if ($filetype) {

		if (exists $Slim::Music::Info::types{$filetype}) {
			$type = $Slim::Music::Info::types{$filetype};
		} else {
			$type = $filetypes{$filetype};
		}
	}

	if ($url && !defined($type)) {
		$type = Slim::Music::Info::typeFromPath($url);
	}

	if ($url && (Slim::Music::Info::isSong($url, $type) || Slim::Music::Info::isHTTPURL($url))) {

		for my $key (keys %{$curTrack}) {

			next if $key eq 'Location';

			$curTrack->{$key} = unescape($curTrack->{$key});
		}


		$cacheEntry{'RATING'}    = $curTrack->{'Rating'};
		$cacheEntry{'PLAYCOUNT'} = $curTrack->{'Play Count'};
		if($curTrack->{'Play Date UTC'}) {
			$cacheEntry{'LASTPLAYED'} = str2time($curTrack->{'Play Date UTC'});
		}
		

		sendTrackToStorage($url,\%cacheEntry);
	} else {

		debugMsg("unknown file type " . ($curTrack->{'Kind'} || '') . " " . ($url || 'Unknown URL') . "\n");

	}
}


sub handleStartElement {
	my ($p, $element) = @_;

	# Don't care about the outer <dict> right after <plist>
	if ($inTracks && $element eq 'dict') {
		$inDict = 1;
	}

	if ($element eq 'key') {
		$inKey = 1;
	}

	# If we're inside the playlist element, and the array is starting,
	# clear out the previous array (defensive), and mark ourselves as inside.
	if ($inPlaylists && defined $item{'TITLE'} && $element eq 'array') {

		@{$item{'LIST'}} = ();
		$inPlaylistArray = 1;
	}

	# Disabled tracks are marked as such:
	# <key>Disabled</key><true/>
	if ($element eq 'true') {

		$item{$currentKey} = 1;
	}

	# Store this value somewhere.
	if ($element eq 'string' || $element eq 'integer' || $element eq 'date') {
		$inValue = 1;
	}
}

sub handleCharElement {
	my ($p, $value) = @_;

	# Just need the one value here.
	if ($nextIsMusicFolder && $inValue) {

		$nextIsMusicFolder = 0;

		#$iBase = Slim::Utils::Misc::pathFromFileURL($iBase);
		$iBase = strip_automounter($value);
		$iBase =~ s/\(/\\\(/;
		$iBase =~ s/\)/\\\)/;
		debugMsg("found the music folder: $iBase\n");

		return;
	}

	# Playlists have their own array structure.
	if ($nextIsPlaylistName && $inValue) {

		$item{'TITLE'} = $value;
		$nextIsPlaylistName = 0;

		return;
	}

	if ($inKey) {
		$currentKey = $value;
		return;
	}

	if ($inTracks && $inValue) {

		if ($] > 5.007) {
			$item{$currentKey} = $value;
		} else {
			$item{$currentKey} = Slim::Utils::Unicode::utf8toLatin1($value);
		}

		return;
	}
}

sub handleEndElement {
	my ($p, $element) = @_;

	if($isScanning!=1) {
		return;
	}

	# Start our state machine controller - tell the next char handler what to do next.
	if ($element eq 'key') {

		$inKey = 0;

		# This is the only top level value we care about.
		if ($currentKey eq 'Music Folder') {
			$nextIsMusicFolder = 1;
		}

		if ($currentKey eq 'Tracks') {

			debugMsg("starting track parsing\n");

			$inTracks = 1;
		}

		if ($inTracks && $currentKey eq 'Playlists') {

			#Slim::Music::Info::clearPlaylists('itunesplaylist:');

			$inTracks = 0;
			$inPlaylists = 1;
		}

		if ($inPlaylists && $currentKey eq 'Name') {
			$nextIsPlaylistName = 1;
		}

		if($inPlaylists==0) {
			return;
		}
	}

	if ($element eq 'string' || $element eq 'integer' || $element eq 'date') {
		$inValue = 0;
	}

	# Done reading this entry - add it to the database.
	if ($inTracks && $element eq 'dict') {

		$inDict = 0;

		handleTrack(\%item);

		%item = ();
	}

	# Finish up
	if ($element eq 'plist' || $inPlaylists==1) {
		debugMsg("Finished scanning iTunes XML\n");

		$isScanning = 2;

		return 0;
	}
}

sub resetScanState {

	debugMsg("Resetting scan state.\n");

	$inPlaylists = 0;
	$inTracks = 0;

	$inKey = 0;
	$inDict = 0;
	$inValue = 0;
	%item = ();
	$currentKey = undef;
	$nextIsMusicFolder = 0;
	$nextIsPlaylistName = 0;
	$inPlaylistArray = 0;
	
	%tracks = ();
}

sub normalize_location {
	my $location = shift;
	my $url;

	my $stripped = strip_automounter($location);

	# on non-mac or windows, we need to substitute the itunes library path for the one in the iTunes xml file
	my $explicit_path = Plugins::CustomScan::Plugin::getCustomScanProperty("itunesslimservermusicpath");
	if(!defined($explicit_path) || $explicit_path eq '') {
		# Use iTunes import path as backup
		$explicit_path = Slim::Utils::Prefs::get('audiodir');
	}

	if ($explicit_path) {

		# find the new base location.  make sure it ends with a slash.
		my $base = Slim::Utils::Misc::fileURLFromPath($explicit_path);

		$url = $stripped;
		$url =~ s/$iBase/$base/isg;
		if($replaceExtension) {
			my $path = Slim::Utils::Misc::pathFromFileURL($url);
			if(! -e $path) {
				$url =~ s/\.[^.]*$/$replaceExtension/isg;
			}
		}
		$url =~ s/(\w)\/\/(\w)/$1\/$2/isg;

	} else {

		$url = Slim::Utils::Misc::fixPath($stripped);
	}

	$url =~ s/file:\/\/localhost\//file:\/\/\//;
	debugMsg("normalized $location to $url\n");

	return $url;
}

sub strip_automounter {
	my $path = shift;

	if ($path && ($path =~ /automount/)) {

		# Strip out automounter 'private' paths.
		# OSX wants us to use file://Network/ or timeouts occur
		# There may be more combinations
		$path =~ s/private\/var\/automount\///;
		$path =~ s/private\/automount\///;
		$path =~ s/automount\/static\///;
	}

	#remove trailing slash
	$path && $path =~ s/\/$//;

	return $path;
}


sub checkDefaults {
	if (!Slim::Utils::Prefs::isDefined('ignoredisableditunestracks')) {
		Slim::Utils::Prefs::set('plugin_trackstat_ignoredisableditunestracks',0);
	}

	if (!Slim::Utils::Prefs::isDefined('lastITunesMusicLibraryDate')) {
		Slim::Utils::Prefs::set('plugin_trackstat_lastITunesMusicLibraryDate',0);
	}
	
	if (!Slim::Utils::Prefs::isDefined('plugin_trackstat_itunes_library_music_path')) {
		Slim::Utils::Prefs::set('plugin_trackstat_itunes_library_music_path','');
	}
}


sub sendTrackToStorage()
{
	my $url = shift;
	my $attributes = shift;

	my $playCount = $attributes->{'PLAYCOUNT'};
	my $lastPlayed = $attributes->{'LASTPLAYED'};
	my $rating = $attributes->{'RATING'};
	
	my $libraries = Plugins::CustomScan::Plugin::getCustomScanProperty("itunesimportlibraries");

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
				debugMsg("Ignoring track, doesnt exist in selected libraries: $url\n");
				$include = 0;
			}
		};
		if($@) {
			warn "Database error: $DBI::errstr for track: $url\n";
			$include = 0;
		}
		if(!$include) {
			return;
		}
	}
	$importCount++;
	Plugins::TrackStat::Storage::mergeTrack($url,undef,$playCount,$lastPlayed,$rating);
}

# A wrapper to allow us to uniformly turn on & off debug messages
sub debugMsg
{
	my $message = join '','TrackStat::iTunes::Import: ',@_;
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
