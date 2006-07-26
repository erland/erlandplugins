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
our %tracks;

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

sub startImport {
	$iTunesLibraryFile = Slim::Utils::Prefs::get('plugin_trackstat_itunes_library_file');;
	$replaceExtension = Slim::Utils::Prefs::get('plugin_trackstat_itunes_replace_extension');;

	if (!canUseiTunesLibrary()) {
		return;
	}
		
	my $file = findMusicLibraryFile();

	debugMsg("startScan on file: $file\n");

	if (!defined($file)) {
		warn "Trying to scan an iTunes file that doesn't exist.";
		return;
	}

	stopScan();

	$isScanning = 1;
	$iTunesScanStartTime = time();

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

	if ($::VERSION ge '6.5' && $::REVISION ge '7505' && $::REVISION lt '8053') {
		while($isScanning) {
			scanFunction();
		}
	}else {
		Slim::Utils::Scheduler::add_task(\&scanFunction);
	}
}

sub stopScan {

	if (stillScanning()) {

		debugMsg("Was stillScanning - stopping old scan.\n");

		if ($::VERSION lt '6.5' || $::REVISION lt '7505' ||  $::REVISION ge '8053') {
			Slim::Utils::Scheduler::remove_task(\&scanFunction);
		}
		$isScanning = 0;
		$locked = 0;
		$opened = 0;
		
		close(ITUNESLIBRARY);
		$iTunesParser = undef;
		resetScanState();
	}
}

sub stillScanning {
	return $isScanning;
}

sub doneScanning {
	debugMsg("done Scanning: unlocking and closing\n");

	if (defined $iTunesParserNB) {

		# This spews, but it's harmless.
		eval { $iTunesParserNB->parse_done };
	}

	$iTunesParserNB = undef;
	$iTunesParser   = undef;

	$locked = 0;
	$opened = 0;

	$lastMusicLibraryFinishTime = time();
	$isScanning = 0;

	# Don't leak filehandles.
	close(ITUNESLIBRARY);

	# Set the last change time for the next go-round.
	my $file  = findMusicLibraryFile();
	my $mtime = (stat($file))[9];

	$lastITunesMusicLibraryDate = $mtime;

	msg("TrackStat:iTunes: Import completed in ".(time() - $iTunesScanStartTime)." seconds.\n");

	Slim::Utils::Prefs::set('plugin_trackstat_lastITunesMusicLibraryDate', $lastITunesMusicLibraryDate);

	if ($::VERSION lt '6.5' || $::REVISION lt '7505' ||  $::REVISION ge '8053') {
		# Take the scanner off the scheduler.
		Slim::Utils::Scheduler::remove_task(\&scanFunction);
	}
}

sub scanFunction {
	# this assumes that iTunes uses file locking when writing the xml file out.
	if (!$opened) {

		debugMsg("opening iTunes Library XML file.\n");

		open(ITUNESLIBRARY, $iTunesLibraryFile) || do {
			warn "TrackStat::iTunes: Couldn't open iTunes Library: $iTunesLibraryFile";
			return 0;
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

			warn "TrackStat::iTunes: Waiting on lock for iTunes Library";
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

		return $isScanning;
	}

	debugMsg("No iTunesParserNB defined!\n");

	return 0;
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

		if ($] > 5.007 && $file && $Slim::Utils::Unicode::locale ne 'utf8') {

			eval { Encode::from_to($file, 'utf8', $Slim::Utils::Unicode::locale) };

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
		my $ctime = str2time($curTrack->{'Date Added'});

		# If the file hasn't changed since the last
		# time we checked, then don't bother going to
		# the database. A file could be new to iTunes
		# though, but it's mtime can be anything.
		#
		# A value of -1 for lastITunesMusicLibraryDate
		# means the user has pressed 'wipe db'.
#		if ($lastITunesMusicLibraryDate &&
#		    $lastITunesMusicLibraryDate != -1 &&
#		    ($ctime && $ctime < $lastITunesMusicLibraryDate) &&
#		    ($mtime && $mtime < $lastITunesMusicLibraryDate)) {
#
#			debugMsg("iTunes: not updated, skipping: $file\n");
#
#			return 1;
#		}

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
	if ($curTrack->{'Disabled'} && !Slim::Utils::Prefs::get('plugin_trackstat_ignoredisableditunestracks')) {

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

		$cacheEntry{'CT'}       = $type;
		$cacheEntry{'TITLE'}    = $curTrack->{'Name'};
		$cacheEntry{'ARTIST'}   = $curTrack->{'Artist'};
		$cacheEntry{'COMPOSER'} = $curTrack->{'Composer'};
		$cacheEntry{'TRACKNUM'} = $curTrack->{'Track Number'};

		my $discNum   = $curTrack->{'Disc Number'};
		my $discCount = $curTrack->{'Disc Count'};

		$cacheEntry{'DISC'}  = $discNum   if defined $discNum;
		$cacheEntry{'DISCC'} = $discCount if defined $discCount;
		$cacheEntry{'ALBUM'} = $curTrack->{'Album'};

		$cacheEntry{'GENRE'} = $curTrack->{'Genre'};
		$cacheEntry{'FS'}    = $curTrack->{'Size'};

		if ($curTrack->{'Total Time'}) {
			$cacheEntry{'SECS'} = $curTrack->{'Total Time'} / 1000;
		}

		$cacheEntry{'BITRATE'} = $curTrack->{'Bit Rate'} * 1000 if $curTrack->{'Bit Rate'};
		$cacheEntry{'YEAR'}    = $curTrack->{'Year'};
		$cacheEntry{'COMMENT'} = $curTrack->{'Comments'};
		$cacheEntry{'RATE'}    = $curTrack->{'Sample Rate'};
		$cacheEntry{'RATING'}    = $curTrack->{'Rating'};
		$cacheEntry{'PLAYCOUNT'} = $curTrack->{'Play Count'};
		if($curTrack->{'Play Date UTC'}) {
			$cacheEntry{'LASTPLAYED'} = str2time($curTrack->{'Play Date UTC'});
		}
		
		my $gain = $curTrack->{'Volume Adjustment'};
		
		# looking for a defined or non-zero volume adjustment
		if ($gain) {
			# itunes uses a range of -255 to 255 to be -100% (silent) to 100% (+6dB)
			if ($gain == -255) {
				$gain = -96.0;
			} else {
				$gain = 20.0 * log(($gain+255)/255)/log(10);
			}
			$cacheEntry{'REPLAYGAIN_TRACK_GAIN'} = $gain;
		}

		$cacheEntry{'VALID'} = 1;

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

	if(!$isScanning) {
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

		doneScanning();

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
	my $explicit_path = Slim::Utils::Prefs::get('plugin_trackstat_itunes_library_music_path');
	
	if ($explicit_path) {

		# find the new base location.  make sure it ends with a slash.
		my $base = Slim::Utils::Misc::fileURLFromPath($explicit_path);

		$url = $stripped;
		$url =~ s/$iBase/$base/isg;
		if($replaceExtension) {
			$url =~ s/\.[^.]*$/$replaceExtension/isg;
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
	
	Plugins::TrackStat::Storage::mergeTrack($url,undef,$playCount,$lastPlayed,$rating);
}

# A wrapper to allow us to uniformly turn on & off debug messages
sub debugMsg
{
	my $message = join '','TrackStat::iTunes: ',@_;
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
