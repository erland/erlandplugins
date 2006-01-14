# 				TrackStat plugin 
#
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
#
#    Portions of code derived from the iTunesUpdate 1.5 plugin
#    Copyright (c) 2004-2006 James Craig (james.craig@london.com)
#
#    Portions of code derived from the SlimScrobbler plugin
#    Copyright (c) 2004 Stewart Loving-Gibbard (sloving-gibbard@uswest.net)
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
                   
package Plugins::TrackStat::Plugin;

use Slim::Player::Playlist;
use Slim::Player::Source;
use Slim::Player::Client;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);

use Time::HiRes;
use Class::Struct;
use POSIX qw(strftime);
use File::Spec::Functions qw(:ALL);

use FindBin qw($Bin);
use Plugins::TrackStat::Time::Stopwatch;

use vars qw($VERSION);
$VERSION = substr(q$Revision$,10);

#################################################
### Global constants - do not change casually ###
#################################################

# There are multiple different conditions which
# influence whether a track is considered played:
#
#  - A minimum number of seconds a track must be 
#    played to be considered a play. Note that
#    if set too high it can prevent a track from
#    ever being noted as played - it is effectively
#    a minimum track length. Overrides other conditions!
#
#  - A percentage play threshold. For example, if 50% 
#    of a track is played, it will be considered played.
#
#  - A time played threshold. After this number of
#    seconds playing, the track will be considered played.
my $TRACKSTAT_MINIMUM_PLAY_TIME = 5;
my $TRACKSTAT_PERCENT_PLAY_THRESHOLD = .50;
my $TRACKSTAT_TIME_PLAY_THRESHOLD = 1800;

# Indicator if hooked or not
# 0= No
# 1= Yes
my $TRACKSTAT_HOOK = 0;

# Each client's playStatus structure. 
my %playerStatusHash = ();

##################################################
### SLIMP3 Plugin API                          ###
##################################################

my %mapping = (
	'0.hold' => 'saveRating_0',
	'1.hold' => 'saveRating_1',
	'2.hold' => 'saveRating_2',
	'3.hold' => 'saveRating_3',
	'4.hold' => 'saveRating_4',
	'5.hold' => 'saveRating_5'
);

sub defaultMap { 
	return \%mapping; 
}

sub getDisplayName()
{
	return $::VERSION =~ m/6\./ ? 'PLUGIN_TRACKSTAT' : string('PLUGIN_TRACKSTAT'); 
}

sub strings() 
{ 
	return '
PLUGIN_TRACKSTAT
	EN	TrackStat

PLUGIN_TRACKSTAT_ACTIVATED
	EN	TrackStat Activated...

PLUGIN_TRACKSTAT_NOTACTIVATED
	EN	TrackStat Not Activated...

PLUGIN_TRACKSTAT_RATING
	EN	Rating:
	
PLUGIN_TRACKSTAT_LAST_PLAYED
	EN	Played:
	
PLUGIN_TRACKSTAT_PLAY_COUNT
	EN	Play Count:
	
PLUGIN_TRACKSTAT_SETUP_GROUP
	EN	TrackStat

PLUGIN_TRACKSTAT_SETUP_GROUP_DESC
	EN	Choose whether the TrackStat plugin will log debug messages.

PLUGIN_TRACKSTAT_SHOW_MESSAGES
	EN	Write messages to log

'};

our %menuSelection;

sub setMode() 
{
	my $client = shift;

    unless (defined($menuSelection{$client})) {
            $menuSelection{$client} = 0;
    }

	$client->lines(\&lines);
}

sub enabled() 
{
	my $client = shift;
	return 1;
}

my %functions = (
	'down' => sub {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, +1, 3, $menuSelection{$client});

        if ($newposition != $menuSelection{$client}) {
                $menuSelection{$client} =$newposition;
				$playerStatusHash{$client}->listitem($playerStatusHash{$client}->listitem+1);
                $client->pushDown();
        }
	},
	'up' => sub {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, -1, 3, $menuSelection{$client});

        if ($newposition != $menuSelection{$client}) {
                $menuSelection{$client} =$newposition;
				$playerStatusHash{$client}->listitem($playerStatusHash{$client}->listitem-1);
                $client->pushUp();
        }
	},
	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub  {
		my $client = shift;
		Slim::Display::Animation::bumpRight($client);
	},
	'saveRating' => sub {
		my $client = shift;
		my $button = shift;
		my $digit = shift;
		debugMsg("saveRating: $client, $button, $digit\n");
		Slim::Display::Animation::showBriefly( $client,
			$client->string( 'PLUGIN_TRACKSTAT'),
			$client->string( 'PLUGIN_TRACKSTAT_RATING').(' *' x $digit),
			3);
		rateSong($client,$digit);
	},
);
	
sub lines() 
{
	my $client = shift;
	my ($line1, $line2);
	$line1 = $client->string('PLUGIN_TRACKSTAT');

	if (my $playStatus = getTrackInfo($client)) {
		my @items = (
		$client->string('PLUGIN_TRACKSTAT_RATING')
			.($playStatus->currentSongRating()?' *' x $playStatus->currentSongRating():''),
		,$client->string('PLUGIN_TRACKSTAT_LAST_PLAYED')
			.' '.($playStatus->lastPlayed()?$playStatus->lastPlayed():''),
		,$client->string('PLUGIN_TRACKSTAT_PLAY_COUNT')
			.' '.($playStatus->playCount()?$playStatus->playCount():''),
		);
		$playStatus->listitem($playStatus->listitem % scalar(@items));
		$line2 = $items[$playStatus->listitem];
	}
	return ($line1, $line2);
}

sub getTrackInfo {
		my $client = shift;
		my $playStatus = $playerStatusHash{$client};
		if ($playStatus->isTiming() eq 'true') {
			if ($playStatus->trackAlreadyLoaded() eq 'false') {
				my($playedCount, $playedDate, $rating) = getTrackFromStorage($playStatus);
				$playStatus->trackAlreadyLoaded('true');
				$playStatus->lastPlayed($playedDate);
				$playStatus->playCount($playedCount);
				#don't overwrite the user's rating
				if ($playStatus->currentSongRating() eq '') {
					$playStatus->currentSongRating($rating);
				}
			}
		} else { 
			return undef;
		}
		return $playStatus;
}

sub getFunctions() 
{
	return \%functions;
}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_trackstat_showmessages'],
	 GroupHead => string('PLUGIN_TRACKSTAT_SETUP_GROUP'),
	 GroupDesc => string('PLUGIN_TRACKSTAT_SETUP_GROUP_DESC'),
	 GroupLine => 1,
	 GroupSub  => 1,
	 Suppress_PrefSub  => 1,
	 Suppress_PrefLine => 1,
	 Suppress_PrefHead => 1
	);

	my %setupPrefs =
	(
	plugin_trackstat_showmessages => {
			'validate'     => \&Slim::Web::Setup::validateTrueFalse
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_SHOW_MESSAGES')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_SHOW_MESSAGES')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_showmessages");}
			},		
	);
	return (\%setupGroup,\%setupPrefs);
}

sub webPages {
	my %pages = ( "index\.htm" => \&handleWebIndex);

	return (\%pages,"index.html");
}

sub handleWebIndex {
	my ($client, $params) = @_;


	# without a player, don't do anything

	if ($client = Slim::Player::Client::getClient($params->{player})) {

		if (my $playStatus = getTrackInfo($client)) {
			if ($params->{p0} and $params->{p0} eq 'rating') {
				if ($params->{p1} eq 'up' and $playStatus->currentSongRating() < 5) {
					$playStatus->currentSongRating($playStatus->currentSongRating() + 1);
				} elsif ($params->{p1} eq 'down' and $playStatus->currentSongRating() > 0) {
					$playStatus->currentSongRating($playStatus->currentSongRating() - 1);
				}
			}
			$params->{playing} = 1;
			$params->{refresh} = $playStatus->currentTrackLength() * 1000;
			$params->{track} = $playStatus->currentSongTrack();
			$params->{rating} = $playStatus->currentSongRating();
			$params->{lastPlayed} = $playStatus->lastPlayed();
			$params->{playCount} = $playStatus->playCount();
		}
	}
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);

}

sub initPlugin
{
    debugMsg("initialising\n");
	#if we haven't already started, do so
	if ( !$TRACKSTAT_HOOK ) {

		# Alter mapping for functions & buttons in Now Playing mode.
		Slim::Hardware::IR::addModeDefaultMapping('playlist',\%mapping);
		my $functref = Slim::Buttons::Playlist::getFunctions();
		$functref->{'saveRating'} = $functions{'saveRating'};

		# this will set messages off by default
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_showmessages"))) { 
			debugMsg("First run - setting showmessages OFF\n");
			Slim::Utils::Prefs::set("plugin_trackstat_showmessages", 0 ); 
		}
		
		installHook();

		#Check if tables exists and create them if not
		debugMsg("Checking if database table exists\n");
		my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
		my $st = $dbh->table_info();
		my $tblexists;
		while (my ( $qual, $owner, $table, $type ) = $st->fetchrow_array()) {
			if($table eq "track_statistics") {
				$tblexists=1;
			}
		}
		unless ($tblexists) {
			debugMsg("Create database table\n");
			executeSQLFile("dbcreate.sql");
		}
	}
}

sub shutdownPlugin {
        debugMsg("disabling\n");
        if ($TRACKSTAT_HOOK) {
                uninstallHook();
        }
}


##################################################
### per-client Data                            ###
##################################################

struct TrackStatus => {

	# Artist's name for current song
	currentSongArtist => '$',

	# Track title for current song
	currentSongTrack => '$',

	# Album title for current song.
	# (If not known, blank.)
	currentSongAlbum => '$',

	# Stopwatch to time the playing of the current track
	currentSongStopwatch => 'Time::Stopwatch',

	# Filename of the current track being played
	currentTrackOriginalFilename => '$',

	# Total length of the track being played
	currentTrackLength => '$',

	# Are we currently paused during a song's playback?
	isPaused => '$',

	# Are we currently timing a song's playback?
	isTiming => '$',

	# have we looked up the track in the storage yet
	trackAlreadyLoaded => '$',

	# Rating for current song
	currentSongRating => '$',

	# last played time
	lastPlayed => '$',

	# play count
	playCount => '$',

	# menu list item
	listitem => '$',

};

struct TrackInfo => {
		url => '$',
		playCount => '$',
		lastPlayed => '$',
		rating => '$'
};

# Set the appropriate default values for this playerStatus struct
sub setPlayerStatusDefaults($$)
{
	# Parameter - client
	my $client = shift;

	# Parameter - Player status structure.
	# Uses pass-by-reference
	my $playerStatusToSetRef = shift;

	# Artist's name for current song
	$playerStatusToSetRef->currentSongArtist("");

	# Track title for current song
	$playerStatusToSetRef->currentSongTrack("");

	# Album title for current song.
	# (If not known, blank.)
	$playerStatusToSetRef->currentSongAlbum("");

	# Rating for current song
	$playerStatusToSetRef->currentSongRating("");

	# Filename of the current track being played
	$playerStatusToSetRef->currentTrackOriginalFilename("");

	# Total length of the track being played
	$playerStatusToSetRef->currentTrackLength(0);

	# Are we currently paused during a song's playback?
	$playerStatusToSetRef->isPaused('false');

	# Are we currently timing a song's playback?
	$playerStatusToSetRef->isTiming('false');

	# Stopwatch to time the playing of the current track
	$playerStatusToSetRef->currentSongStopwatch(Time::Stopwatch->new());

	$playerStatusToSetRef->trackAlreadyLoaded('false');
	$playerStatusToSetRef->listitem(0);

}

# Get the player state for the given client.
# Will create one for new clients.
sub getPlayerStatusForClient($)
{
	# Parameter - Client structure
	my $client = shift;

	# Get the friendly name for this client
	my $clientName = Slim::Player::Client::name($client);
	# Get the ID (IP) for this client
	my $clientID = Slim::Player::Client::id($client);

	#debugMsg("Asking about client $clientName ($clientID)\n");

	# If we haven't seen this client before, create a new per-client 
	# playState structure.
	if (!defined($playerStatusHash{$client}))
	{
		debugMsg("Creating new PlayerStatus for $clientName ($clientID)\n");

		# Create new playState structure
		$playerStatusHash{$client} = TrackStatus->new();

		# Set appropriate defaults
		setPlayerStatusDefaults($client, $playerStatusHash{$client});
	}

	# If it didn't exist, it does now - 
	# return the playerStatus structure for the client.
	return $playerStatusHash{$client};
}

################################################
### main routines                            ###
################################################

# A wrapper to allow us to uniformly turn on & off debug messages
sub debugMsg
{
	my $message = join '','TrackStat: ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_trackstat_showmessages"));
}


# Hook the plugin to the play events.
# Do this as soon as possible during startup.
sub installHook()
{  
	debugMsg("Hook activated.\n");
	Slim::Control::Command::setExecuteCallback(\&commandCallback);
	$TRACKSTAT_HOOK=1;
}

# Unhook the plugin's play event callback function. 
# Do this as the plugin shuts down, if possible.
sub uninstallHook()
{
	debugMsg("Hook deactivated.\n");
	Slim::Control::Command::clearExecuteCallback(\&commandCallback);
	$TRACKSTAT_HOOK=0;
}

# These xxxCommand() routines handle commands coming to us
# through the command callback we have hooked into.
sub openCommand($$)
{
	######################################
	### Open command
	######################################

	# This is the chief way we detect a new song being played, NOT the play command.
	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	# Stop old song, if needed
	# do this before updating the filename as we need to use it in the stop function
	if ($playStatus->isTiming() eq "true")
	{
		stopTimingSong($playStatus);
	}
	# Parameter - filename of track being played
	$playStatus->currentTrackOriginalFilename(shift);

	# Start timing new song
	startTimingNewSong($playStatus);#, $artistName,$trackTitle,$albumName);
}

sub playCommand($)
{
	######################################
	### Play command
	######################################

	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	if ( ($playStatus->isTiming() eq "true") &&($playStatus->isPaused() eq "true") )
	{
		debugMsg("Resuming with play from pause\n");
		resumeTimingSong($playStatus);
	} elsif ( ($playStatus->isTiming() eq "true") &&($playStatus->isPaused() eq "false") )
	{
		debugMsg("Ignoring play command, assumed redundant...\n");		      
	} else {
		# this seems to happen when you switch on and press play    
		# Start timing new song
		startTimingNewSong($playStatus);
	}
}

sub pauseCommand($$)
{
	######################################
	### Pause command
	######################################

	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	# Parameter - Optional second parameter in command
	# (This is for the case <pause 0 | 1> ). 
	# If user said "pause 0" or "pause 1", this will be 0 or 1. Otherwise, undef.
	my $secondParm = shift;

	# Just a plain "pause"
	if (!defined($secondParm))
	{
		# What we do depends on if we are already paused or not
		if ($playStatus->isPaused() eq "false") {
			debugMsg("Pausing (vanilla pause)\n");
			pauseTimingSong($playStatus);   
		} elsif ($playStatus->isPaused() eq "true") {
			debugMsg("Unpausing (vanilla unpause)\n");
			resumeTimingSong($playStatus);      
		}
	}

	# "pause 1" means "pause true", so pause and stop timing, if not already paused.
	elsif ( ($secondParm eq 1) && ($playStatus->isPaused() eq "false") ) {
		debugMsg("Pausing (1 case)\n");
		pauseTimingSong($playStatus);      
	}

	# "pause 0" means "pause false", so unpause and resume timing, if not already timing.
	elsif ( ($secondParm eq 0) && ($playStatus->isPaused() eq "true") ) {
		debugMsg("Pausing (0 case)\n");
		resumeTimingSong($playStatus);      
	} else {      
		debugMsg("Pause command ignored, assumed redundant.\n");
	}
}

sub stopCommand($)
{
	######################################
	### Stop command
	######################################

	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	if ($playStatus->isTiming() eq "true")
	{
		stopTimingSong($playStatus);      
	}
}


# This gets called during playback events.
# We look for events we are interested in, and start and stop our various
# timers accordingly.
sub commandCallback($) 
{
	# These are the two passed parameters
	my $client = shift;
	my $paramsRef = shift;

	return unless $client;

	# Get the PlayerStatus
	my $playStatus = getPlayerStatusForClient($client);

	### START DEBUG
	#debugMsg("====New commands:\n");
	#foreach my $param (@$paramsRef)
	#{
	#   debugMsg("  command: $param\n");
	#}
	#showCurrentVariables($playStatus);
	### END DEBUG

	my $slimCommand = @$paramsRef[0];
	my $paramOne = @$paramsRef[1];

	return unless $slimCommand;
	######################################
	### Open command
	######################################

	# This is the chief way we detect a new song being played, NOT play.

	if ($slimCommand eq "open") 
	{
		my $trackOriginalFilename = $paramOne;
		openCommand($playStatus, $trackOriginalFilename);
	}

	######################################
	### Play command
	######################################

	if( ($slimCommand eq "play") || (($slimCommand eq "mode") && ($paramOne eq "play")) )
	{
		playCommand($playStatus);
	}

	######################################
	### Pause command
	######################################

	if ($slimCommand eq "pause")
	{
		# This second parameter may not exist,
		# and so this may be undef. Routine expects this possibility,
		# so all should be well.
		pauseCommand($playStatus, $paramOne);
	}

	if (($slimCommand eq "mode") && ($paramOne eq "pause"))
	{  
		# "mode pause" will always put us into pause mode, so fake a "pause 1".
		pauseCommand($playStatus, 1);
	}

	######################################
	### Sleep command
	######################################

	if ($slimCommand eq "sleep")
	{
		# Sleep has no effect on streamed players; is this correct for slimp3s?
		# I can't test it.
		#debugMsg("===> Sleep activated! Be sure this works!\n");
		#pauseCommand($playStatus, undef());
	}

	######################################
	### Stop command
	######################################

	if ( ($slimCommand eq "stop") ||	(($slimCommand eq "mode") && ($paramOne eq "stop")) )
	{
		stopCommand($playStatus);
	}

	######################################
	### Stop command
	######################################

	if ( ($slimCommand eq "playlist") && ($paramOne eq "sync") )
	{
		# If this player syncs with another, we treat it as a stop,
		# since whatever it is presently playing (if anything) will end.
		stopCommand($playStatus);
	}

	######################################
	## Power command
	######################################
	# softsqueeze doesn't seem to send a 2nd param on power on/off
	# might as well stop timing regardless of type
	if ( ($slimCommand eq "power") || (($slimCommand eq "mode") && ($paramOne eq "off")) )
	{
		stopCommand($playStatus);
	}
}

# A new song has begun playing. Reset the current song
# timer and set new Artist and Track.
sub startTimingNewSong($$$$)
{
	# Parameter - TrackStatus for current client
	my $playStatus = shift;
	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = $ds->objectForUrl($playStatus->currentTrackOriginalFilename);

	debugMsg("Starting a new song\n");
	if (Slim::Music::Info::isFile($playStatus->currentTrackOriginalFilename)) {
		# Get new song data
		$playStatus->currentTrackLength($track->durationSeconds);

		my $artistName = $track->artist();
		#put this in because I'm getting crashes on missing artists
		$artistName = $artistName->name() if (defined $artistName);
		$artistName = "" if (!defined $artistName or $artistName eq string('NO_ARTIST'));

		my $albumName  = $track->album->title();
		$albumName = "" if (!defined $albumName or $albumName eq string('NO_ALBUM'));

		my $trackTitle = $track->title;
		$trackTitle = "" if $trackTitle eq string('NO_TITLE');

		# Set the Name & artist & album
		$playStatus->currentSongArtist($artistName);
		$playStatus->currentSongTrack($trackTitle);
		$playStatus->currentSongAlbum($albumName);

		if ($playStatus->isTiming() eq "true")
		{
			debugMsg("Programmer error in startTimingNewSong() - already timing!\n");	 
		}

		# Clear the stopwatch and start it again
		($playStatus->currentSongStopwatch())->clear();
		($playStatus->currentSongStopwatch())->start();

		# Not paused - we are playing a song
		$playStatus->isPaused("false");

		# We are now timing a song
		$playStatus->isTiming("true");

		$playStatus->trackAlreadyLoaded("false");

		debugMsg("Starting to time ",$playStatus->currentTrackOriginalFilename,"\n");
	} else {
		debugMsg("Not timing ",$playStatus->currentTrackOriginalFilename," - not a file\n");
	}
	#showCurrentVariables($playStatus);
}

# Pause the current song timer
sub pauseTimingSong($)
{
	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	if ($playStatus->isPaused() eq "true")
	{
		debugMsg("Programmer error or other problem in pauseTimingSong! Confused about pause status.\n");      
	}

	# Stop the stopwatch 
	$playStatus->currentSongStopwatch()->stop();

	# Go into pause mode
	$playStatus->isPaused("true");

	debugMsg("Pausing ",$playStatus->currentTrackOriginalFilename,"\n");
	debugMsg("Elapsed seconds: ",$playStatus->currentSongStopwatch()->getElapsedTime(),"\n");
	#showCurrentVariables($playStatus);
}

# Resume the current song timer - playing again
sub resumeTimingSong($)
{
	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	if ($playStatus->isPaused() eq "false")
	{
		debugMsg("Programmer error or other problem in resumeTimingSong! Confused about pause status.\n");      
	}

	# Re-start the stopwatch 
	$playStatus->currentSongStopwatch()->start();

	# Exit pause mode
	$playStatus->isPaused("false");

	debugMsg("Resuming ",$playStatus->currentTrackOriginalFilename,"\n");
	#showCurrentVariables($playStatus);
}

# Stop timing the current song
# (Either stop was hit or we are about to play another one)
sub stopTimingSong($)
{
	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	if ($playStatus->isTiming() eq "false")
	{
		debugMsg("Programmer error - not already timing!\n");   
	}

	if (Slim::Music::Info::isFile($playStatus->currentTrackOriginalFilename)) {

		my $totalElapsedTimeDuringPlay = $playStatus->currentSongStopwatch()->getElapsedTime();
		debugMsg("Stopping timing ",$playStatus->currentTrackOriginalFilename,"\n");
		debugMsg("Total elapsed time in seconds: $totalElapsedTimeDuringPlay \n");

		# If the track was played long enough to count as a listen..
		if (trackWasPlayedEnoughToCountAsAListen($playStatus, $totalElapsedTimeDuringPlay) )
		{
			#debugMsg("Track was played long enough to count as listen\n");
			sendTrackToStorage($playStatus,'played');
			# We could also log to history at this point as well...
		} else {
			#debugMsg("Track was NOT played long enough to count as listen\n");

			if ($playStatus->currentSongRating && $playStatus->currentSongRating ne "") {
				debugMsg("Track WAS rated\n");
				sendTrackToStorage($playStatus,'rated');
			} 
		}
	} else {
		debugMsg("That wasn't a file - ignoring\n");
	}
	$playStatus->currentSongArtist("");
	$playStatus->currentSongTrack("");
	$playStatus->currentSongRating("");

	# Clear the stopwatch
	$playStatus->currentSongStopwatch()->clear();

	$playStatus->isPaused("false");
	$playStatus->isTiming("false");
}

# Debugging routine - shows current variable values for the given playStatus
sub showCurrentVariables($)
{
	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	debugMsg("======= showCurrentVariables() ========\n");
	debugMsg("Artist:",playStatus->currentSongArtist(),"\n");
	debugMsg("Track: ",$playStatus->currentSongTrack(),"\n");
	debugMsg("Album: ",$playStatus->currentSongAlbum(),"\n");
	debugMsg("Original Filename: ",$playStatus->currentTrackOriginalFilename(),"\n");
	debugMsg("Duration in seconds: ",$playStatus->currentTrackLength(),"\n"); 
	debugMsg("Time showing on stopwatch: ",$playStatus->currentSongStopwatch()->getElapsedTime(),"\n");
	debugMsg("Is song playback paused? : ",$playStatus->isPaused(),"\n");
	debugMsg("Are we currently timing? : ",$playStatus->isTiming(),"\n");
	debugMsg("=======================================\n");
}

sub trackWasPlayedEnoughToCountAsAListen($$)
{
	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	# Total time elapsed during play
	my $totalTimeElapsedDuringPlay = shift;

	my $wasLongEnough = 0;
	my $currentTrackLength = $playStatus->currentTrackLength();
	my $tmpCurrentSongTrack = $playStatus->currentSongTrack();

	# The minimum play time the % minimum requires
	my $minimumPlayLengthFromPercentPlayThreshold = $TRACKSTAT_PERCENT_PLAY_THRESHOLD * $currentTrackLength;

	my $printableDisplayThreshold = $TRACKSTAT_PERCENT_PLAY_THRESHOLD * 100;
	debugMsg("Time actually played in track: $totalTimeElapsedDuringPlay\n");
	#debugMsg("Current play threshold is $printableDisplayThreshold%.\n");
	#debugMsg("Minimum play time is $TRACKSTAT_MINIMUM_PLAY_TIME seconds.\n");
	#debugMsg("Time play threshold is $TRACKSTAT_TIME_PLAY_THRESHOLD seconds.\n");
	#debugMsg("Percentage play threshold calculation:\n");
	#debugMsg("$TRACKSTAT_PERCENT_PLAY_THRESHOLD * $currentTrackLength =$minimumPlayLengthFromPercentPlayThreshold\n");	

	# Did it play at least the absolute minimum amount?
	if ($totalTimeElapsedDuringPlay < $TRACKSTAT_MINIMUM_PLAY_TIME ) 
	{
		# No. This condition overrides the others.
		debugMsg("\"$tmpCurrentSongTrack\" NOT played long enough: Played $totalTimeElapsedDuringPlay; needed to play $TRACKSTAT_MINIMUM_PLAY_TIME seconds.\n");
		$wasLongEnough = 0;   
	}
	# Did it play past the percent-of-track played threshold?
	elsif ($totalTimeElapsedDuringPlay >= $minimumPlayLengthFromPercentPlayThreshold)
	{
		# Yes. We have a play.
		debugMsg("\"$tmpCurrentSongTrack\" was played long enough to count as played.\n");
		debugMsg("Played past percentage threshold of $minimumPlayLengthFromPercentPlayThreshold seconds.\n");
		$wasLongEnough = 1;
	}
	# Did it play past the number-of-seconds played threshold?
	elsif ($totalTimeElapsedDuringPlay >= $TRACKSTAT_TIME_PLAY_THRESHOLD)
	{
		# Yes. We have a play.
		debugMsg("\"$tmpCurrentSongTrack\" was played long enough to count as played.\n");
		debugMsg("Played past time threshold of $TRACKSTAT_TIME_PLAY_THRESHOLD seconds.\n");
		$wasLongEnough = 1;
	} else {
		# We *could* do this calculation above, but I wanted to make it clearer
		# exactly why a play was too short, if it was too short, with explicit
		# debug messages.
		my $minimumPlayTimeNeeded;
		if ($minimumPlayLengthFromPercentPlayThreshold < $TRACKSTAT_TIME_PLAY_THRESHOLD) {
			$minimumPlayTimeNeeded = $minimumPlayLengthFromPercentPlayThreshold;
		} else {
			$minimumPlayTimeNeeded = $TRACKSTAT_TIME_PLAY_THRESHOLD;
		}
		# Otherwise, it played above the minimum 
		#, but below the thresholds, so, no play.
		debugMsg("\"$tmpCurrentSongTrack\" NOT played long enough: Played $totalTimeElapsedDuringPlay; needed to play $minimumPlayTimeNeeded seconds.\n");
		$wasLongEnough = 0;   
	}
	return $wasLongEnough;
}

sub sendTrackToStorage($$)
{
	my ($playStatus,$action) = @_;

	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = $ds->objectForUrl($playStatus->currentTrackOriginalFilename());
	my $trackHandle = searchTrackInStorage( $playStatus->currentTrackOriginalFilename());
	my $sql;
	my $url = $track->url;

	if ($action eq 'played') {
		debugMsg("Marking as played in storage\n");
		my $playCount;
		if($trackHandle && $trackHandle->playCount) {
			$playCount = $trackHandle->playCount + 1;
		}elsif($track->playCount){
			$playCount = $track->playCount;
		}else {
			$playCount = 1;
		}
		my $lastPlayed = $track->lastPlayed;

		if ($trackHandle) {
			$sql = ("UPDATE track_statistics set playCount=$playCount, lastPlayed=$lastPlayed where url='$url'");
		}else {
			$sql = ("INSERT INTO track_statistics (url,playCount,lastPlayed) values ('$url',$playCount,$lastPlayed)");
		}
		my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
		my $sth = $dbh->prepare( $sql );
		
		$sth->execute();
		$dbh->commit();

		$sth->finish();
	}
	
	#Lookup again since the row can have been created above
	$trackHandle = searchTrackInStorage( $playStatus->currentTrackOriginalFilename());
	my $rating = $playStatus->currentSongRating();
	if ($rating && $rating ne "") {
		debugMsg("Store rating\n");
	    #ratings are 0-5 stars, 100 = 5 stars
		$rating = $rating * 20;

		if ($trackHandle) {
			$sql = ("UPDATE track_statistics set rating=$rating where url='$url'");
		} else {
			$sql = ("INSERT INTO track_statistics (url,rating) values ('$url',$rating)");
		}
		my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
		my $sth = $dbh->prepare( $sql );
		
		$sth->execute();
		$dbh->commit();

		$sth->finish();
	}
}

sub getTrackFromStorage
{
	my ($playStatus) = shift;
	my ($playedCount, $playedDate,$rating);

	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = $ds->objectForUrl($playStatus->currentTrackOriginalFilename());
	my $trackHandle = searchTrackInStorage( $playStatus->currentTrackOriginalFilename());

	if ($trackHandle) {
			if($trackHandle->playCount) {
				$playedCount = $trackHandle->playCount;
			}elsif($track->playCount){
				$playedCount = $track->playCount;
			}
			if($trackHandle->lastPlayed) {
				$playedDate = strftime ("%Y-%m-%d %H:%M:%S",localtime $trackHandle->lastPlayed);
			}elsif($track->lastPlayed) {
				$playedDate = strftime ("%Y-%m-%d %H:%M:%S",localtime $track->lastPlayed);
			}
			if($trackHandle->rating) {
				$rating = $trackHandle->rating;
				if($rating) {
					$rating = $rating / 20;
				}
			}
	}else {
		if($track) {
			$playedCount = $track->playCount;
			if($track->lastPlayed) {
				$playedDate = strftime ("%Y-%m-%d %H:%M:%S",localtime $track->lastPlayed);
			}
		}
		debugMsg("Track: ", $playStatus->currentTrackOriginalFilename()," not found\n");
	}
	return $playedCount, $playedDate,$rating;
}


sub rateSong($$) {
	my ($client,$digit)=@_;
	my $playStatus = getPlayerStatusForClient($client);

	debugMsg("Changing song rating to: $digit\n");

	$playStatus->currentSongRating($digit);
}

sub searchTrackInStorage {
	my $track_url = shift;
	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = $ds->objectForUrl($track_url);
	debugMsg("URL: ".$track->url."\n");

	# create searchString and remove duplicate/trailing whitespace as well.
    my $searchString = "";
	$searchString .= $track->url;

	return 0 unless length($searchString) >= 1;

	my $sql = ("SELECT url, playCount, lastPlayed, rating FROM track_statistics where url='$searchString'");

	my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
	my $sth = $dbh->prepare( $sql );
	$sth->execute();

	my( $url, $playCount, $lastPlayed, $rating );
	$sth->bind_columns( undef, \$url, \$playCount, \$lastPlayed, \$rating );
	my $result;
	while( $sth->fetch() ) {
	  $result = TrackInfo->new( url => $url, playCount => $playCount, lastPlayed => $lastPlayed, rating => $rating );
	}

	$sth->finish();

	return $result;
}

sub executeSQLFile {
        my $file  = shift;

		my $driver = Slim::Utils::Prefs::get('dbsource');
        $driver =~ s/dbi:(.*?):(.*)$/$1/;
        
        my $sqlFile = catdir($Bin, "Plugins", "TrackStat", "SQL", $driver, $file);

        debugMsg("Executing SQL file $sqlFile\n");

        open(my $fh, $sqlFile) or do {

                msg("Couldn't open: $sqlFile : $!\n");
                return;
        };

		my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();

        my $statement   = '';
        my $inStatement = 0;

        for my $line (<$fh>) {
                chomp $line;

                # skip and strip comments & empty lines
                $line =~ s/\s*--.*?$//o;
                $line =~ s/^\s*//o;

                next if $line =~ /^--/;
                next if $line =~ /^\s*$/;

                if ($line =~ /^\s*(?:CREATE|SET|INSERT|UPDATE|DELETE|DROP|SELECT)\s+/oi) {
                        $inStatement = 1;
                }

                if ($line =~ /;/ && $inStatement) {

                        $statement .= $line;


                        debugMsg("Executing SQL statement: [$statement]\n");

                        eval { $dbh->do($statement) };

                        if ($@) {
                                msg("Couldn't execute SQL statement: [$statement] : [$@]\n");
                        }

                        $statement   = '';
                        $inStatement = 0;
                        next;
                }

                $statement .= $line if $inStatement;
        }

        $dbh->commit;

        close $fh;
}

my %musicInfoSCRItems = (
	'TRACKSTAT_RATING_DYNAMIC' => 'TRACKSTAT_RATING_DYNAMIC',
	'PLAYING (X_OF_Y) TRACKSTAT_RATING_DYNAMIC' => 'PLAYING (X_OF_Y) TRACKSTAT_RATING_DYNAMIC',
	'TRACKSTAT_RATING_STATIC' => 'TRACKSTAT_RATING_STATIC',
	'PLAYING (X_OF_Y) TRACKSTAT_RATING_STATIC' => 'PLAYING (X_OF_Y) TRACKSTAT_RATING_STATIC',
	'TRACKSTAT_RATING_NUMBER' => 'TRACKSTAT_RATING_NUMBER',
);

sub getMusicInfoSCRCustomItems() 
{
	return \%musicInfoSCRItems;
}

sub getMusicInfoSCRCustomItem()
{
	my $client = shift;
    my $formattedString  = shift;
	if ($formattedString =~ /TRACKSTAT_RATING_STATIC/) {
		my $playStatus = getTrackInfo($client);
		my $string = '  ' x 5;
		if($playStatus->currentSongRating()) {
			$string = ($playStatus->currentSongRating()?' *' x $playStatus->currentSongRating():'');
			my $left = 5 - $playStatus->currentSongRating();
			$string = $string . ('  ' x $left);
		}
		$formattedString =~ s/TRACKSTAT_RATING_STATIC/$string/g;
	}
	if ($formattedString =~ /TRACKSTAT_RATING_DYNAMIC/) {
		my $playStatus = getTrackInfo($client);
		my $string = ($playStatus->currentSongRating()?' *' x $playStatus->currentSongRating():'');
		$formattedString =~ s/TRACKSTAT_RATING_DYNAMIC/$string/g;
	}
	if ($formattedString =~ /TRACKSTAT_RATING_NUMBER/) {
		my $playStatus = getTrackInfo($client);
		my $string = ($playStatus->currentSongRating()?$playStatus->currentSongRating():'');
		$formattedString =~ s/TRACKSTAT_RATING_NUMBER/$string/g;
	}
	return $formattedString;
}

1;
