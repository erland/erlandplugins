# 				TrackStat plugin 
#
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
#
#    Portions of code derived from the iTunes plugin included in slimserver
#    Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
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
use POSIX qw(strftime ceil);
use File::Spec::Functions qw(:ALL);
use DBI qw(:sql_types);

use FindBin qw($Bin);
use Plugins::TrackStat::Time::Stopwatch;
use Plugins::TrackStat::iTunes::Import;
use Plugins::TrackStat::MusicMagic::Import;
use Plugins::TrackStat::MusicMagic::Export;
use Plugins::TrackStat::Backup::File;
use Plugins::TrackStat::Storage;

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

# Plugins that supports ratings
my %ratingPlugins = ();

# Plugins that supports play count/last played time
my %playCountPlugins = ();

##################################################
### SLIMP3 Plugin API                          ###
##################################################

my %mapping = (
	'0.hold' => 'saveRating_0',
	'1.hold' => 'saveRating_1',
	'2.hold' => 'saveRating_2',
	'3.hold' => 'saveRating_3',
	'4.hold' => 'saveRating_4',
	'5.hold' => 'saveRating_5',
	'0.single' => 'numberScroll_0',
	'1.single' => 'numberScroll_1',
	'2.single' => 'numberScroll_2',
	'3.single' => 'numberScroll_3',
	'4.single' => 'numberScroll_4',
	'5.single' => 'numberScroll_5',
	'0' => 'dead',
	'1' => 'dead',
	'2' => 'dead',
	'3' => 'dead',
	'4' => 'dead',
	'5' => 'dead'
);

sub defaultMap { 
	return \%mapping; 
}

sub getDisplayName()
{
	return $::VERSION =~ m/6\./ ? 'PLUGIN_TRACKSTAT' : string('PLUGIN_TRACKSTAT'); 
}

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
		my $playStatus = getPlayerStatusForClient($client);
		if ($playStatus->isTiming() eq 'true') {
			# see if the string is already in the cache
			my $songKey;
	        my $song = $songKey = Slim::Player::Playlist::song($client);
	        if (Slim::Music::Info::isRemoteURL($song)) {
	                $songKey = Slim::Music::Info::getCurrentTitle($client, $song);
	        }
	        if($playStatus->currentTrackOriginalFilename() eq $songKey) {
				$playStatus->currentSongRating($digit);
			}
        	debugMsg("saveRating: $client, $songKey, $digit\n");
			Slim::Display::Animation::showBriefly( $client,
				$client->string( 'PLUGIN_TRACKSTAT'),
				$client->string( 'PLUGIN_TRACKSTAT_RATING').(' *' x $digit),
				3);
			rateSong($client,$songKey,$digit);
		}else {
			Slim::Display::Animation::showBriefly( $client,
				$client->string( 'PLUGIN_TRACKSTAT'),
				$client->string( 'PLUGIN_TRACKSTAT_RATING_NO_SONG'),
				3);
		}
	},
);
	
sub lines() 
{
	my $client = shift;
	my ($line1, $line2);
	$line1 = $client->string('PLUGIN_TRACKSTAT');

	if (my $playStatus = getTrackInfo($client)) {
		if ($playStatus->trackAlreadyLoaded() eq 'true') {
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
		} else {
			$line2 = $client->string('PLUGIN_TRACKSTAT_NOT_FOUND');
		}
	} else {
		$line2 = $client->string('PLUGIN_TRACKSTAT_NO_TRACK');
	}
	return ($line1, $line2);
}

sub getTrackInfo {
		my $client = shift;
		my $playStatus = getPlayerStatusForClient($client);
		if ($playStatus->isTiming() eq 'true') {
			if ($playStatus->trackAlreadyLoaded() eq 'false') {
				my $ds = Slim::Music::Info::getCurrentDataStore();
				my $track     = $ds->objectForUrl($playStatus->currentTrackOriginalFilename());
				my $trackHandle = Plugins::TrackStat::Storage::findTrack( $playStatus->currentTrackOriginalFilename());
				my $playedCount = 0;
				my $playedDate = "";
				my $rating = 0;
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
				}
				
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
	 PrefOrder => ['plugin_trackstat_backup_file','plugin_trackstat_backup','plugin_trackstat_restore','plugin_trackstat_clear','plugin_trackstat_refresh_tracks','plugin_trackstat_purge_tracks','plugin_trackstat_itunes_import','plugin_trackstat_itunes_library_file','plugin_trackstat_itunes_library_music_path','plugin_trackstat_itunes_replace_extension','plugin_trackstat_musicmagic_enabled','plugin_trackstat_musicmagic_host','plugin_trackstat_musicmagic_port','plugin_trackstat_musicmagic_library_music_path','plugin_trackstat_musicmagic_replace_extension','plugin_trackstat_musicmagic_slimserver_replace_extension','plugin_trackstat_musicmagic_import','plugin_trackstat_musicmagic_export','plugin_trackstat_dynamicplaylist','plugin_trackstat_web_list_length','plugin_trackstat_playlist_length','plugin_trackstat_playlist_per_artist_length','plugin_trackstat_showmessages'],
	 GroupHead => string('PLUGIN_TRACKSTAT_SETUP_GROUP'),
	 GroupDesc => string('PLUGIN_TRACKSTAT_SETUP_GROUP_DESC'),
	 GroupLine => 1,
	 GroupSub  => 1,
	 Suppress_PrefSub  => 1,
	 Suppress_PrefLine => 1
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
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_showmessages"); }
		},		
	plugin_trackstat_dynamicplaylist => {
			'validate'     => \&Slim::Web::Setup::validateTrueFalse
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_DYNAMICPLAYLIST')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_DYNAMICPLAYLIST')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist"); }
		},		
	plugin_trackstat_web_list_length => {
			'validate'     => \&Slim::Web::Setup::validateInt
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_WEB_LIST_LENGTH')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_WEB_LIST_LENGTH')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_web_list_length"); }
		},		
	plugin_trackstat_playlist_length => {
			'validate'     => \&Slim::Web::Setup::validateInt
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_PLAYLIST_LENGTH')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_PLAYLIST_LENGTH')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_playlist_length"); }
		},		
	plugin_trackstat_playlist_per_artist_length => {
			'validate'     => \&Slim::Web::Setup::validateInt
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_PLAYLIST_PER_ARTIST_LENGTH')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_PLAYLIST_PER_ARTIST_LENGTH')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_playlist_per_artist_length"); }
		},		
	plugin_trackstat_backup_file => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_BACKUP_FILE')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_BACKUP_FILE')
			,'rejectMsg' => string('SETUP_BAD_FILE')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_backup_file"); }
		},
	plugin_trackstat_backup => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll
			,'onChange' => sub { backupToFile(); }
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MAKING_BACKUP')
			,'ChangeButton' => string('PLUGIN_TRACKSTAT_BACKUP')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
	plugin_trackstat_refresh_tracks => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll
			,'onChange' => sub { Plugins::TrackStat::Storage::refreshTracks(); }
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_TRACKSTAT_REFRESHING_TRACKS')
			,'ChangeButton' => string('PLUGIN_TRACKSTAT_REFRESH_TRACKS')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
	plugin_trackstat_purge_tracks => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll
			,'onChange' => sub { Plugins::TrackStat::Storage::purgeTracks(); }
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_TRACKSTAT_PURGING_TRACKS')
			,'ChangeButton' => string('PLUGIN_TRACKSTAT_PURGE_TRACKS')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
	plugin_trackstat_restore => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll
			,'onChange' => sub { restoreFromFile(); }
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_TRACKSTAT_RESTORING_BACKUP')
			,'ChangeButton' => string('PLUGIN_TRACKSTAT_RESTORE')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
	plugin_trackstat_clear => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll
			,'onChange' => sub { Plugins::TrackStat::Storage::deleteAllTracks(); }
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_TRACKSTAT_CLEARING')
			,'ChangeButton' => string('PLUGIN_TRACKSTAT_CLEAR')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
	plugin_trackstat_itunes_library_file => {
			'validate' => \&Slim::Web::Setup::validateIsFile
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_ITUNES_LIBRARY_FILE')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_ITUNES_LIBRARY_FILE')
			,'rejectMsg' => string('SETUP_BAD_FILE')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_itunes_library_file"); }
		},
	plugin_trackstat_itunes_library_music_path => {
			'validate' => \&Slim::Web::Setup::validateIsDir
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_ITUNES_MUSIC_DIRECTORY')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_ITUNES_MUSIC_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_itunes_library_music_path"); }
		},
	plugin_trackstat_itunes_replace_extension => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_ITUNES_REPLACE_EXTENSION')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_ITUNES_REPLACE_EXTENSION')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_itunes_replace_extension"); }
		},
	plugin_trackstat_musicmagic_enabled => {
			'validate'     => \&Slim::Web::Setup::validateTrueFalse
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_ENABLED')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_ENABLED')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_enabled"); }
		},		
	plugin_trackstat_musicmagic_host => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_HOST')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_HOST')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_host"); }
		},
	plugin_trackstat_musicmagic_port => {
			'validate' => \&Slim::Web::Setup::validateInt
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_PORT')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_PORT')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_port"); }
		},
	plugin_trackstat_musicmagic_library_music_path => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_MUSIC_DIRECTORY')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_MUSIC_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_library_music_path"); }
		},
	plugin_trackstat_musicmagic_replace_extension => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_REPLACE_EXTENSION')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_REPLACE_EXTENSION')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_replace_extension"); }
		},
	plugin_trackstat_musicmagic_slimserver_replace_extension => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_SLIMSERVER_REPLACE_EXTENSION')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_SLIMSERVER_REPLACE_EXTENSION')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_slimserver_replace_extension"); }
		},
	plugin_trackstat_itunes_import => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll
			,'onChange' => sub { importFromiTunes(); }
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_TRACKSTAT_ITUNES_IMPORTING')
			,'ChangeButton' => string('PLUGIN_TRACKSTAT_ITUNES_IMPORT_BUTTON')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
	plugin_trackstat_musicmagic_import => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll
			,'onChange' => sub { importFromMusicMagic(); }
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_IMPORTING')
			,'ChangeButton' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_IMPORT_BUTTON')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
	plugin_trackstat_musicmagic_export => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll
			,'onChange' => sub { exportToMusicMagic(); }
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_EXPORTING')
			,'ChangeButton' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_EXPORT_BUTTON')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
	);
	return (\%setupGroup,\%setupPrefs);
}

sub webPages {
	my %pages = (
		"index\.htm" => \&handleWebIndex,
		"mostplayed\.htm" => \&handleWebMostPlayed,
		"mostplayedalbums\.htm" => \&handleWebMostPlayedAlbums,
		"mostplayedartists\.htm" => \&handleWebMostPlayedArtists,
		"lastplayed\.htm" => \&handleWebLastPlayed,
		"toprated\.htm" => \&handleWebTopRated,
		"topratedalbums\.htm" => \&handleWebTopRatedAlbums,
		"topratedartists\.htm" => \&handleWebTopRatedArtists,
		"leastplayed\.htm" => \&handleWebLeastPlayed,
		"leastplayedalbums\.htm" => \&handleWebLeastPlayedAlbums,
		"leastplayedartists\.htm" => \&handleWebLeastPlayedArtists,
		"firstplayed\.htm" => \&handleWebFirstPlayed
	);

	return (\%pages,"index.html");
}

sub baseWebPage {
	my ($client, $params) = @_;
	if($params->{trackstatcmd} and $params->{trackstatcmd} eq 'listlength') {
		Slim::Utils::Prefs::set("plugin_trackstat_web_list_length",$params->{listlength});
	}	
	# without a player, don't do anything
	if ($client = Slim::Player::Client::getClient($params->{player})) {
		if (my $playStatus = getTrackInfo($client)) {
			if ($params->{trackstatcmd} and $params->{trackstatcmd} eq 'rating') {
				my $songKey;
		        my $song = $songKey = Slim::Player::Playlist::song($client);
		        if (Slim::Music::Info::isRemoteURL($song)) {
		                $songKey = Slim::Music::Info::getCurrentTitle($client, $song);
		        }
		        if($playStatus->currentTrackOriginalFilename() eq $songKey) {
					if (!$playStatus->currentSongRating()) {
						$playStatus->currentSongRating(0);
					}
					if ($params->{trackstatrating} eq 'up' and $playStatus->currentSongRating() < 5) {
						$playStatus->currentSongRating($playStatus->currentSongRating() + 1);
					} elsif ($params->{trackstatrating} eq 'down' and $playStatus->currentSongRating() > 0) {
						$playStatus->currentSongRating($playStatus->currentSongRating() - 1);
					} elsif ($params->{trackstatrating} >= 0 or $params->{trackstatrating} <= 5) {
						$playStatus->currentSongRating($params->{trackstatrating});
					}
					
					rateSong($client,$songKey,$playStatus->currentSongRating());
				}
			}
			$params->{playing} = $playStatus->trackAlreadyLoaded();
			$params->{refresh} = $playStatus->currentTrackLength();
			$params->{track} = $playStatus->currentSongTrack();
			$params->{rating} = $playStatus->currentSongRating();
			$params->{lastPlayed} = $playStatus->lastPlayed();
			$params->{playCount} = $playStatus->playCount();
		} else {
			$params->{refresh} = 60;
		}
	}
	$params->{'pluginTrackStatListLength'} = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
	$params->{refresh} = 60 if (!$params->{refresh} || $params->{refresh} > 60);
	$params->{'pluginTrackStatVersion'} = $::VERSION;
}
	
sub handlePlayAddWebPage {
	my ($client, $params) = @_;

	if ($client = Slim::Player::Client::getClient($params->{player})) {
		my $first = 1;
		if($params->{trackstatcmd} and $params->{trackstatcmd} eq 'play') {
			$client->execute(['stop']);
			$client->execute(['power', '1']);
		}elsif($params->{trackstatcmd} and $params->{trackstatcmd} eq 'add') {
			$first = 0;
		}else {
			return;
		}
		my $objs = $params->{'browse_items'};
		
		for my $item (@$objs) {
			if($item->{'listtype'} eq 'track') {
				my $track = $item->{'itemobj'};
				if($first==1) {
					debugMsg("Loading track = ".$track->title."\n");
					$client->execute(['playlist', 'loadtracks', sprintf('track=%d', $track->id)]);
				}else {
					debugMsg("Adding track = ".$track->title."\n");
					$client->execute(['playlist', 'addtracks', sprintf('track=%d', $track->id)]);
				}
			}elsif($item->{'listtype'} eq 'album') {
				my $album = $item->{'itemobj'}{'album'};
				if($first==1) {
					debugMsg("Loading album = ".$album->title."\n");
					$client->execute(['playlist', 'loadtracks', sprintf('album=%d', $album->id)]);
				}else {
					debugMsg("Adding album = ".$album->title."\n");
					$client->execute(['playlist', 'addtracks', sprintf('album=%d', $album->id)]);
				}
			}elsif($item->{'listtype'} eq 'artist') {
				my $artist = $item->{'itemobj'}{'artist'};
				if($first==1) {
					debugMsg("Loading artist = ".$artist->name."\n");
					$client->execute(['playlist', 'loadtracks', sprintf('artist=%d', $artist->id)]);
				}else {
					debugMsg("Adding artist = ".$artist->name."\n");
					$client->execute(['playlist', 'addtracks', sprintf('artist=%d', $artist->id)]);
				}
			}
			$first = 0;
		}
	}
}

sub handleWebIndex {
	my ($client, $params) = @_;

	baseWebPage($client, $params);
    my $ds     = Slim::Music::Info::getCurrentDataStore();

	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub handleWebMostPlayed {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    Plugins::TrackStat::Storage::getMostPlayedTracksWeb($params,$listLength);
	$params->{'songlist'} = 'MOSTPLAYED';
	handlePlayAddWebPage($client,$params);
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub handleWebLeastPlayed {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    Plugins::TrackStat::Storage::getLeastPlayedTracksWeb($params,$listLength);
	$params->{'songlist'} = 'LEASTPLAYED';
	handlePlayAddWebPage($client,$params);
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}



sub handleWebLastPlayed {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    Plugins::TrackStat::Storage::getLastPlayedTracksWeb($params,$listLength);
	$params->{'songlist'} = 'LASTPLAYED';
	handlePlayAddWebPage($client,$params);
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub handleWebFirstPlayed {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    Plugins::TrackStat::Storage::getFirstPlayedTracksWeb($params,$listLength);
	$params->{'songlist'} = 'FIRSTPLAYED';
	handlePlayAddWebPage($client,$params);
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub handleWebTopRated {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

	my $driver = Slim::Utils::Prefs::get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    Plugins::TrackStat::Storage::getTopRatedTracksWeb($params,$listLength);
	$params->{'songlist'} = 'TOPRATED';
	handlePlayAddWebPage($client,$params);
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub handleWebTopRatedAlbums {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    Plugins::TrackStat::Storage::getTopRatedAlbumsWeb($params,$listLength);
	$params->{'songlist'} = 'TOPRATEDALBUMS';
	handlePlayAddWebPage($client,$params);
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub handleWebMostPlayedAlbums {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    Plugins::TrackStat::Storage::getMostPlayedAlbumsWeb($params,$listLength);
	$params->{'songlist'} = 'MOSTPLAYEDALBUMS';
	handlePlayAddWebPage($client,$params);
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub handleWebLeastPlayedAlbums {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    Plugins::TrackStat::Storage::getLeastPlayedAlbumsWeb($params,$listLength);
	$params->{'songlist'} = 'LEASTPLAYEDALBUMS';
	handlePlayAddWebPage($client,$params);
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub handleWebTopRatedArtists {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    Plugins::TrackStat::Storage::getTopRatedArtistsWeb($params,$listLength);
	$params->{'songlist'} = 'TOPRATEDARTISTS';
	handlePlayAddWebPage($client,$params);
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub handleWebMostPlayedArtists {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    Plugins::TrackStat::Storage::getMostPlayedArtistsWeb($params,$listLength);
	$params->{'songlist'} = 'MOSTPLAYEDARTISTS';
	handlePlayAddWebPage($client,$params);
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub handleWebLeastPlayedArtists {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    Plugins::TrackStat::Storage::getLeastPlayedArtistsWeb($params,$listLength);
	$params->{'songlist'} = 'LEASTPLAYEDARTISTS';
	handlePlayAddWebPage($client,$params);
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

		# this will enable DynamicPlaylist integration by default
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist"))) { 
			debugMsg("First run - setting dynamicplaylist ON\n");
			Slim::Utils::Prefs::set("plugin_trackstat_dynamicplaylist", 1 ); 
		}
		# set default web list length to same as items per page
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_web_list_length"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_web_list_length",Slim::Utils::Prefs::get("itemsPerPage"));
		}
		# set default playlist length to same as items per page
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_playlist_length"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_playlist_length",Slim::Utils::Prefs::get("itemsPerPage"));
		}
		# set default playlist per artist/album length to 10
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_playlist_per_artist_length"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_playlist_per_artist_length",10);
		}
		# disable music magic integration by default
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_enabled"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_musicmagic_enabled",0);
		}

		# set default music magic port
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_port"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_musicmagic_port",Slim::Utils::Prefs::get('MMSport'));
		}

		# set default music magic host
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_host"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_musicmagic_host",Slim::Utils::Prefs::get('MMSHost'));
		}

		# disable music magic integration by default
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_enabled"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_musicmagic_enabled",0);
		}

		installHook();
		
		Plugins::TrackStat::Storage::init();

		no strict 'refs';
		my @enabledplugins;
		if ($::VERSION ge '6.5') {
			@enabledplugins = Slim::Utils::PluginManager::enabledPlugins();
		}else {
			@enabledplugins = Slim::Buttons::Plugins::enabledPlugins();
		}
		for my $plugin (@enabledplugins) {
			if(UNIVERSAL::can("Plugins::$plugin","setTrackStatRating")) {
				debugMsg("Added rating support for $plugin\n");
				$ratingPlugins{$plugin} = "Plugins::${plugin}::setTrackStatRating";
			}
			if(UNIVERSAL::can("Plugins::$plugin","setTrackStatStatistic")) {
				debugMsg("Added play count support for $plugin\n");
				$playCountPlugins{$plugin} = "Plugins::${plugin}::setTrackStatStatistic";
			}
		}
		use strict 'refs';
	}
	addTitleFormat('TRACKNUM. ARTIST - TITLE (TRACKSTATRATINGDYNAMIC)');
	addTitleFormat('TRACKNUM. TITLE (TRACKSTATRATINGDYNAMIC)');
	addTitleFormat('PLAYING (X_OF_Y) (TRACKSTATRATINGSTATIC)');
	addTitleFormat('PLAYING (X_OF_Y) TRACKSTATRATINGSTATIC');
	addTitleFormat('TRACKSTATRATINGNUMBER');

	if ($::VERSION ge '6.5') {
		
		Slim::Music::TitleFormatter::addFormat('TRACKSTATRATINGDYNAMIC',\&getRatingDynamicCustomItem);
		Slim::Music::TitleFormatter::addFormat('TRACKSTATRATINGSTATIC',\&getRatingStaticCustomItem);
		Slim::Music::TitleFormatter::addFormat('TRACKSTATRATINGNUMBER',\&getRatingNumberCustomItem);
	}else {
		Slim::Music::Info::addFormat('TRACKSTATRATINGDYNAMIC',\&getRatingDynamicCustomItem);
		Slim::Music::Info::addFormat('TRACKSTATRATINGSTATIC',\&getRatingStaticCustomItem);
		Slim::Music::Info::addFormat('TRACKSTATRATINGNUMBER',\&getRatingNumberCustomItem);
	}
}

sub addTitleFormat
{
	my $titleformat = shift;
	foreach my $format ( Slim::Utils::Prefs::getArray('titleFormat') ) {
		if($titleformat eq $format) {
			return;
		}
	}
	my $arrayMax = Slim::Utils::Prefs::getArrayMax('titleFormat');
	debugMsg("Adding at $arrayMax: $titleformat");
	Slim::Utils::Prefs::set('titleFormat',$titleformat,$arrayMax+1);
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
	client => '$',

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

# Set the appropriate default values for this playerStatus struct
sub setPlayerStatusDefaults($$)
{
	# Parameter - client
	my $client = shift;

	# Parameter - Player status structure.
	# Uses pass-by-reference
	my $playerStatusToSetRef = shift;

	# Client reference
	$playerStatusToSetRef->client($client);
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
	if ($::VERSION ge '6.5') {
		Slim::Control::Request::subscribe(\&Plugins::TrackStat::Plugin::commandCallback65,[['mode', 'play', 'stop', 'pause', 'playlist']]);
	} else {
		Slim::Control::Command::setExecuteCallback(\&commandCallback62);
	}
	$TRACKSTAT_HOOK=1;
}

# Unhook the plugin's play event callback function. 
# Do this as the plugin shuts down, if possible.
sub uninstallHook()
{
	debugMsg("Hook deactivated.\n");
	if ($::VERSION ge '6.5') {
		Slim::Control::Request::unsubscribe(\&Plugins::TrackStat::Plugin::commandCallback65);
	} else {
		Slim::Control::Command::clearExecuteCallback(\&commandCallback62);
	}
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
sub commandCallback62($) 
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


# This gets called during playback events.
# We look for events we are interested in, and start and stop our various
# timers accordingly.
sub commandCallback65($) 
{
	# These are the two passed parameters
	my $request=shift;
	my $client = $request->client();

	# Get the PlayerStatus
	my $playStatus = getPlayerStatusForClient($client);

	######################################
	### Open command
	######################################

	# This is the chief way we detect a new song being played, NOT play.
	# should be using playlist,newsong now...
	if ($request->isCommand([['playlist'],['open']]) )
	{
		openCommand($playStatus,$request->getParam('_path'));
	}

	######################################
	### Play command
	######################################

	if( ($request->isCommand([['playlist'],['play']])) or ($request->isCommand([['mode','play']])) )
	{
		playCommand($playStatus);
	}

	######################################
	### Pause command
	######################################

	if ($request->isCommand([['pause']]))
	{
		pauseCommand($playStatus,$request->getParam('_newValue'));
	}

	if ($request->isCommand([['mode'],['pause']]))
	{  
		# "mode pause" will always put us into pause mode, so fake a "pause 1".
		pauseCommand($playStatus, 1);
	}

	######################################
	### Stop command
	######################################

	if ( ($request->isCommand([["stop"]])) or ($request->isCommand([['mode'],['stop']])) )
	{
		stopCommand($playStatus);
	}

	######################################
	### Stop command
	######################################

	if ( $request->isCommand([['playlist'],['sync']]) )
	{
		# If this player syncs with another, we treat it as a stop,
		# since whatever it is presently playing (if anything) will end.
		stopCommand($playStatus);
	}

	######################################
	## Power command
	######################################
	if ( $request->isCommand([['power']]))
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
			markedAsPlayed($playStatus->client,$playStatus->currentTrackOriginalFilename);
			# We could also log to history at this point as well...
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

sub markedAsPlayed {
	my $client = shift;
	my $url = shift;
	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = $ds->objectForUrl($url);
	my $trackHandle = Plugins::TrackStat::Storage::findTrack( $url);

	my $playCount;
	if($trackHandle && $trackHandle->playCount) {
		$playCount = $trackHandle->playCount + 1;
	}elsif($track->playCount){
		$playCount = $track->playCount;
	}else {
		$playCount = 1;
	}

	my $lastPlayed = $track->lastPlayed;
	if(!$lastPlayed) {
		$lastPlayed = time();
	}
	my $mbId = undef;
	my $rating = undef;
	if ($trackHandle) {
		$mbId = $trackHandle->mbId;
		$rating = $trackHandle->rating;
	}
	 
	Plugins::TrackStat::Storage::savePlayCountAndLastPlayed($url,$mbId,$playCount,$lastPlayed);
	my %statistic = (
		'url' => $url,
		'playCount' => $playCount,
		'lastPlayed' => $lastPlayed,
		'rating' => $rating,
		'mbId' => $mbId,
	);
	no strict 'refs';
	for my $item (keys %playCountPlugins) {
		debugMsg("Calling $item\n");
		eval { &{$playCountPlugins{$item}}($client,$url,\%statistic) };
	}
	use strict 'refs';
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




sub rateSong($$$) {
	my ($client,$url,$digit)=@_;

	debugMsg("Changing song rating to: $digit\n");
	my $rating = $digit * 20;
	Plugins::TrackStat::Storage::saveRating($url,undef,$rating);
	no strict 'refs';
	for my $item (keys %ratingPlugins) {
		debugMsg("Calling $item\n");
		eval { &{$ratingPlugins{$item}}($client,$url,$rating) };
	}
	use strict 'refs';
	Slim::Music::Info::clearFormatDisplayCache();
}

sub setTrackStatRating {
	my ($client,$url,$rating)=@_;
	$rating = $rating / 20;
	if ($::VERSION ge '6.5') {
		my $ds = Slim::Music::Info::getCurrentDataStore();
		my $track = $ds->objectForUrl($url);
		# Run this within eval for now so it hides all errors until this is standard
		eval {
			$track->set('rating' => $rating);
			$track->update();
			$ds->forceCommit();
		};
	}

	$url = getMusicMagicURL($url);
	
	my $hostname = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_host");
	my $port = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_port");
	my $musicmagicurl = "http://$hostname:$port/api/setRating?song=$url&rating=$rating";
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
    }else {
		debugMsg("Failure setting Music Magic rating\n");
    }
}

sub setTrackStatStatistic {
	my ($client,$url,$statistic)=@_;
	
	my $playCount = $statistic->{'playCount'};
	my $lastPlayed = $statistic->{'lastPlayed'};	
	$url = getMusicMagicURL($url);
	
	my $hostname = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_host");
	my $port = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_port");
	my $musicmagicurl = "http://$hostname:$port/api/setPlayCount?song=$url&count=$playCount";
	debugMsg("Calling: $musicmagicurl\n");
	my $http = Slim::Player::Protocols::HTTP->new({
        'url'    => "$musicmagicurl",
        'create' => 0,
    });
    if(defined($http)) {
    	my $result = $http->content;
    	chomp $result;
    	if($result eq "1") {
			debugMsg("Success setting Music Magic play count\n");
		}else {
			debugMsg("Error setting Music Magic play count, error code = $result\n");
		}
    	$http->close();
    }else {
		debugMsg("Failure setting Music Magic play count\n");
    }

	$musicmagicurl = "http://$hostname:$port/api/setLastPlayed?song=$url&time=$lastPlayed";
	debugMsg("Calling: $musicmagicurl\n");
	$http = Slim::Player::Protocols::HTTP->new({
        'url'    => "$musicmagicurl",
        'create' => 0,
    });
    if(defined($http)) {
    	my $result = $http->content;
    	chomp $result;
    	if($result eq "1") {
			debugMsg("Success setting Music Magic last played\n");
		}else {
			debugMsg("Error setting Music Magic last played, error code = $result\n");
		}
    	$http->close();
    }else {
		debugMsg("Failure setting Music Magic last played\n");
    }
}
	
sub getMusicMagicURL {
	my $url = shift;
	my $replacePath = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_library_music_path");
	if(defined(!$replacePath) && $replacePath ne '') {
		$replacePath = escape($replacePath);
		my $nativeRoot = Slim::Utils::Prefs::get('audiodir');
		my $nativeUrl = Slim::Utils::Misc::fileURLFromPath($nativeRoot);
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
	return $url;
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

sub getRatingDynamicCustomItem
{
	my $track = shift;
	my $trackHandle = Plugins::TrackStat::Storage::findTrack( $track->url);
	my $string = '';
	if($trackHandle && $trackHandle->rating) {
		my $rating = $trackHandle->rating / 20;
		$string = ($rating?' *' x $rating:'');
	}
	return $string;
}

sub getRatingStaticCustomItem
{
	my $track = shift;
	my $trackHandle = Plugins::TrackStat::Storage::findTrack( $track->url);
	my $string = '  ' x 5;
	if($trackHandle && $trackHandle->rating) {
		my $rating = $trackHandle->rating / 20;
		debugMsg("rating = $rating\n");
		if($rating) {
			$string = ($rating?' *' x $rating:'');
			my $left = 5 - $rating;
			$string = $string . ('  ' x $left);
		}
	}
	return $string;
}

sub getRatingNumberCustomItem
{
	my $track = shift;
	my $trackHandle = Plugins::TrackStat::Storage::findTrack( $track->url);
	my $string = '';
	if($trackHandle && $trackHandle->rating) {
		my $rating = $trackHandle->rating / 20;
		$string = ($rating?$rating:'');
	}
	return $string;
}

sub importFromiTunes()
{
	Plugins::TrackStat::iTunes::Import::startImport();
}

sub importFromMusicMagic()
{
	Plugins::TrackStat::MusicMagic::Import::startImport();
}

sub exportToMusicMagic()
{
	Plugins::TrackStat::MusicMagic::Export::startExport();
}

sub backupToFile() 
{
	my $backupfile = Slim::Utils::Prefs::get("plugin_trackstat_backup_file");
	if($backupfile) {
		Plugins::TrackStat::Backup::File::backupToFile($backupfile);
	}
}

sub restoreFromFile()
{
	my $backupfile = Slim::Utils::Prefs::get("plugin_trackstat_backup_file");
	if($backupfile) {
		Plugins::TrackStat::Backup::File::restoreFromFile($backupfile);
	}
}

sub getDynamicPlayLists {
	my ($client) = @_;
	my %result = ();

	return \%result unless Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist");
	
	my %currentResultMostPlayedTrack = (
		'id' => 'mostplayed',
		'name' => $client->string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYED'),
	);
	my $id = "trackstat_mostplayed";
	$result{$id} = \%currentResultMostPlayedTrack;

	my %currentResultLeastPlayedTrack = (
		'id' => 'leastplayed',
		'name' => $client->string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYED'),
	);
	$id = "trackstat_leastplayed";
	$result{$id} = \%currentResultLeastPlayedTrack;

	my %currentResultLastPlayedTrack = (
		'id' => 'lastplayed',
		'name' => $client->string('PLUGIN_TRACKSTAT_SONGLIST_LASTPLAYED'),
	);
	$id = "trackstat_lastplayed";
	$result{$id} = \%currentResultLastPlayedTrack;

	my %currentResultFirstPlayedTrack = (
		'id' => 'firstplayed',
		'name' => $client->string('PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED'),
	);
	$id = "trackstat_firstplayed";
	$result{$id} = \%currentResultFirstPlayedTrack;

	my %currentResultTopRatedTrack = (
		'id' => 'toprated',
		'name' => $client->string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATED'),
	);
	$id = "trackstat_toprated";
	$result{$id} = \%currentResultTopRatedTrack;

	my %currentResultTopRatedAlbum = (
		'id' => 'topratedalbums',
		'name' => $client->string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS'),
	);
	$id = "trackstat_topratedalbums";
	$result{$id} = \%currentResultTopRatedAlbum;

	my %currentResultLeastPlayedAlbum = (
		'id' => 'leastplayedalbums',
		'name' => $client->string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDALBUMS'),
	);
	$id = "trackstat_leastplayedalbums";
	$result{$id} = \%currentResultLeastPlayedAlbum;

	my %currentResultMostPlayedAlbum = (
		'id' => 'mostplayedalbums',
		'name' => $client->string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDALBUMS'),
	);
	$id = "trackstat_mostplayedalbums";
	$result{$id} = \%currentResultMostPlayedAlbum;

	my %currentResultTopRatedArtist = (
		'id' => 'topratedartists',
		'name' => $client->string('PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDARTISTS'),
	);
	$id = "trackstat_topratedartists";
	$result{$id} = \%currentResultTopRatedArtist;

	my %currentResultLeastPlayedArtist = (
		'id' => 'leastplayedartists',
		'name' => $client->string('PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDARTISTS'),
	);
	$id = "trackstat_leastplayedartists";
	$result{$id} = \%currentResultLeastPlayedArtist;

	my %currentResultMostPlayedArtist = (
		'id' => 'mostplayedartists',
		'name' => $client->string('PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDARTISTS'),
	);
	$id = "trackstat_mostplayedartists";
	$result{$id} = \%currentResultMostPlayedArtist;

	return \%result;
}

sub getNextDynamicPlayListTracks {
	my ($client,$dynamicplaylist,$limit,$offset) = @_;

	my @result = ();

    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_playlist_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    my $artistListLength = Slim::Utils::Prefs::get("plugin_trackstat_playlist_per_artist_length");
    if(!defined $artistListLength || $artistListLength==0) {
    	$artistListLength = 10;
    }
	debugMsg("Got: ".$dynamicplaylist->{'id'}.", $limit\n");
	if($dynamicplaylist->{'id'} eq 'mostplayed') {
		return Plugins::TrackStat::Storage::getMostPlayedTracks($listLength,$limit);
	}elsif($dynamicplaylist->{'id'} eq 'leastplayed') {
		return Plugins::TrackStat::Storage::getLeastPlayedTracks($listLength,$limit);
	}elsif($dynamicplaylist->{'id'} eq 'lastplayed') {
		return Plugins::TrackStat::Storage::getLastPlayedTracks($listLength,$limit);
	}elsif($dynamicplaylist->{'id'} eq 'firstplayed') {
		return Plugins::TrackStat::Storage::getFirstPlayedTracks($listLength,$limit);
	}elsif($dynamicplaylist->{'id'} eq 'toprated') {
		return Plugins::TrackStat::Storage::getTopRatedTracks($listLength,$limit);
	}elsif($dynamicplaylist->{'id'} eq 'topratedalbums') {
		return Plugins::TrackStat::Storage::getTopRatedAlbumTracks($listLength);
	}elsif($dynamicplaylist->{'id'} eq 'mostplayedalbums') {
		return Plugins::TrackStat::Storage::getMostPlayedAlbumTracks($listLength);
	}elsif($dynamicplaylist->{'id'} eq 'leastplayedalbums') {
		return Plugins::TrackStat::Storage::getLeastPlayedAlbumTracks($listLength);
	}elsif($dynamicplaylist->{'id'} eq 'topratedartists') {
		return Plugins::TrackStat::Storage::getTopRatedArtistTracks($listLength,$artistListLength);
	}elsif($dynamicplaylist->{'id'} eq 'mostplayedartists') {
		return Plugins::TrackStat::Storage::getMostPlayedArtistTracks($listLength,$artistListLength);
	}elsif($dynamicplaylist->{'id'} eq 'leastplayedartists') {
		return Plugins::TrackStat::Storage::getLeastPlayedArtistTracks($listLength,$artistListLength);
	}
	debugMsg("Got ".scalar(@result)." tracks\n");
	return \@result;
}

# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

sub strings() 
{ 
	return <<EOF
PLUGIN_TRACKSTAT
	EN	TrackStat

PLUGIN_TRACKSTAT_ACTIVATED
	EN	TrackStat Activated...

PLUGIN_TRACKSTAT_NOTACTIVATED
	EN	TrackStat Not Activated...

PLUGIN_TRACKSTAT_TRACK
	EN	Track:
	
PLUGIN_TRACKSTAT_RATING
	EN	Rating:
	
PLUGIN_TRACKSTAT_LAST_PLAYED
	EN	Played:
	
PLUGIN_TRACKSTAT_PLAY_COUNT
	EN	Play Count:
	
PLUGIN_TRACKSTAT_SETUP_GROUP
	EN	TrackStat settings

PLUGIN_TRACKSTAT_SETUP_GROUP_DESC
	EN	The TrackStat plugin provides a possiblilty to keep the statistic information in a safe place which survives rescans of the music library. It also makes it possible to give each track a rating.<br>Statistic information about rating, play counts and last played time can also be imported from iTunes.

PLUGIN_TRACKSTAT_SHOW_MESSAGES
	EN	Write messages to log

SETUP_PLUGIN_TRACKSTAT_SHOWMESSAGES
	EN	Debug logging

SETUP_PLUGIN_TRACKSTAT_SHOWMESSAGES_DESC
	EN	This will turn on/off debug logging of the TrackStat plugin

PLUGIN_TRACKSTAT_DYNAMICPLAYLIST
	EN	Enable Dynamic Playlists

SETUP_PLUGIN_TRACKSTAT_DYNAMICPLAYLIST
	EN	Dynamic Playlists integration 

SETUP_PLUGIN_TRACKSTAT_DYNAMICPLAYLIST_DESC
	EN	This will turn on/off integration with Dynamic Playlists plugin making the statistics available as playlists

PLUGIN_TRACKSTAT_ITUNES_IMPORTING
	EN	Importing from iTunes...

PLUGIN_TRACKSTAT_ITUNES_IMPORT_BUTTON
	EN	Import from iTunes

SETUP_PLUGIN_TRACKSTAT_ITUNES_IMPORT
	EN	Import from iTunes

SETUP_PLUGIN_TRACKSTAT_ITUNES_IMPORT_DESC
	EN	Import information from the specified iTunes Music Library.xml file. This means that any existing rating, play counts or last played information in iTunes will overwrite any existing information.

PLUGIN_TRACKSTAT_ITUNES_LIBRARY_FILE
	EN	Path to iTunes Music Library.xml

SETUP_PLUGIN_TRACKSTAT_ITUNES_LIBRARY_FILE
	EN	iTunes Music Library file

SETUP_PLUGIN_TRACKSTAT_ITUNES_LIBRARY_FILE_DESC
	EN	This parameter shall be the full path to the iTunes Music Library.xml file that should be used when importing information from iTunes.

PLUGIN_TRACKSTAT_ITUNES_MUSIC_DIRECTORY
	EN	Path to iTunes Music

SETUP_PLUGIN_TRACKSTAT_ITUNES_LIBRARY_MUSIC_PATH
	EN	Music directory

SETUP_PLUGIN_TRACKSTAT_ITUNES_LIBRARY_MUSIC_PATH_DESC
	EN	The begining of the paths of the music imported from iTunes will be replaced with this path. This makes it possible to have the music in a different directory in iTunes compared to the directory where the music is accessible on the slimserver computer.

PLUGIN_TRACKSTAT_ITUNES_REPLACE_EXTENSION
	EN	File extension to use in files imported from iTunes
	
SETUP_PLUGIN_TRACKSTAT_ITUNES_REPLACE_EXTENSION
	EN	iTunes import extension
	
SETUP_PLUGIN_TRACKSTAT_ITUNES_REPLACE_EXTENSION_DESC
	EN	The file extensions of the music files i imported from iTunes can be replaced with this extension. This makes it possible to have .mp3 files in iTunes and have .flac files in slimserver with the same name besides the extension. This is usefull if flac2mp3 is used to convert flac files to mp3 for usage with iTunes.
	
PLUGIN_TRACKSTAT_MUSICMAGIC_ENABLED
	EN	Enable Music Magic integration

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_ENABLED
	EN	Music Magic Integration

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_ENABLED_DESC
	EN	Enable ratings, play counts and last played time to be sent to Music Magic

PLUGIN_TRACKSTAT_MUSICMAGIC_HOST
	EN	Hostname

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_HOST
	EN	Music Magic server hostname

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_HOST_DESC
	EN	Hostname of Music Magic server, default is localhost

PLUGIN_TRACKSTAT_MUSICMAGIC_PORT
	EN	Port

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_PORT
	EN	Music Magic server port

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_PORT_DESC
	EN	Port on Music Magic server, default is 10002

PLUGIN_TRACKSTAT_MUSICMAGIC_MUSIC_DIRECTORY
	EN	Music directory

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_LIBRARY_MUSIC_PATH
	EN	Music Magic music path

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_LIBRARY_MUSIC_PATH_DESC
	EN	The begining of the paths of the music will be replaced with this path when calling Music Magic for setting ratings and play counts. This makes it possible to have the music in a different directory in Music Magic compared to the directory where the music is accessible on the slimserver computer.

PLUGIN_TRACKSTAT_MUSICMAGIC_REPLACE_EXTENSION
	EN	File extension to use when calling Music Magic

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_REPLACE_EXTENSION
	EN	Music Magic export extension

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_REPLACE_EXTENSION_DESC
	EN	The file extensions of to use when sending ratings and play counts to Music Magic, this is the extension used for files in Music Magic. This makes it possible to have .mp3 files in Music Magic and have .flac files in slimserver with the same name besides the extension. This is usefull if flac2mp3 is used to convert flac files to mp3 for usage with Music Magic.

PLUGIN_TRACKSTAT_MUSICMAGIC_SLIMSERVER_REPLACE_EXTENSION
	EN	File extension to use when importing from Music Magic

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_SLIMSERVER_REPLACE_EXTENSION
	EN	Music Magic import extension

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_SLIMSERVER_REPLACE_EXTENSION_DESC
	EN	The file extensions of to use when importing tracks from Music Magic, this is the extension used for files in slimserver. This makes it possible to have .mp3 files in Music Magic and have .flac files in slimserver with the same name besides the extension. This is usefull if flac2mp3 is used to convert flac files to mp3 for usage with Music Magic.

PLUGIN_TRACKSTAT_MUSICMAGIC_IMPORTING
	EN	Importing from Music Magic...

PLUGIN_TRACKSTAT_MUSICMAGIC_IMPORT_BUTTON
	EN	Import from Music Magic

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_IMPORT
	EN	Music Magic import

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_IMPORT_DESC
	EN	Import information from the specified Music Magic server. This means that any existing rating, play counts or last played information in Music Magic will overwrite any existing information. 

PLUGIN_TRACKSTAT_MUSICMAGIC_EXPORTING
	EN	Exporting to Music Magic...

PLUGIN_TRACKSTAT_MUSICMAGIC_EXPORT_BUTTON
	EN	Export to Music Magic

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_EXPORT
	EN	Music Magic export

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_EXPORT_DESC
	EN	Export information from TrackStat to the specified Music Magic server. This means that any existing rating, play counts or last played information in TrackStat will overwrite any existing information in Music Magic. Note that an export to Music Magic might take some time.

PLUGIN_TRACKSTAT_BACKUP_FILE
	EN	Backup file

SETUP_PLUGIN_TRACKSTAT_BACKUP_FILE
	EN	Backup file

SETUP_PLUGIN_TRACKSTAT_BACKUP_FILE_DESC
	EN	File used for TrackStat information backup. This file must be in a place where the user which is running slimserver has read/write access.

PLUGIN_TRACKSTAT_BACKUP
	EN	Backup to file

SETUP_PLUGIN_TRACKSTAT_BACKUP
	EN	Backup to file

SETUP_PLUGIN_TRACKSTAT_BACKUP_DESC
	EN	Do backup of all TrackStat information to the file specified as backup file

PLUGIN_TRACKSTAT_MAKING_BACKUP
	EN	Making TrackStat backup to file...

SETUP_PLUGIN_TRACKSTAT_WEB_LIST_LENGTH
	EN	Number of songs/albums/artists on web

SETUP_PLUGIN_TRACKSTAT_WEB_LIST_LENGTH_DESC
	EN	Number songs/albums/artists that should be shown in the web interface for TrackStat when choosing to view statistic information

PLUGIN_TRACKSTAT_WEB_LIST_LENGTH
	EN	Number of songs/albums/artists on web

SETUP_PLUGIN_TRACKSTAT_PLAYLIST_LENGTH
	EN	Number of songs/albums/artists in playlists

SETUP_PLUGIN_TRACKSTAT_PLAYLIST_LENGTH_DESC
	EN	Number songs/albums/artists that should be used when selecting tracks in DynamicPlaylist plugin

PLUGIN_TRACKSTAT_PLAYLIST_LENGTH
	EN	Number of songs/albums/artists in playlists

SETUP_PLUGIN_TRACKSTAT_PLAYLIST_PER_ARTIST_LENGTH
	EN	Number of songs per artist in playlists

SETUP_PLUGIN_TRACKSTAT_PLAYLIST_PER_ARTIST_LENGTH_DESC
	EN	Number songs for each artists used when selecting artist playlists in DynamicPlaylist plugin. This means that selecting "Top rated artist" will play this number of tracks for an artist before changing to next artist.

PLUGIN_TRACKSTAT_PLAYLIST_PER_ARTIST_LENGTH
	EN	Number of songs for each artist in playlists

PLUGIN_TRACKSTAT_RESTORE
	EN	Restore from file

SETUP_PLUGIN_TRACKSTAT_RESTORE
	EN	Restore from file

SETUP_PLUGIN_TRACKSTAT_RESTORE_DESC
	EN	Restore TrackStat information from the file specified as backup file.<br><b>WARNING!</b><br>This will overwrite any TrackStat information that exist with the information in the file

PLUGIN_TRACKSTAT_RESTORING_BACKUP
	EN	Restoring TrackStat backup from file...

PLUGIN_TRACKSTAT_CLEAR
	EN	Remove all data

SETUP_PLUGIN_TRACKSTAT_CLEAR
	EN	Remove all data

SETUP_PLUGIN_TRACKSTAT_CLEAR_DESC
	EN	This will remove all existing TrackStat data.<br><b>WARNING!</b><br>If you have not made an backup of the information it will be lost forever.

PLUGIN_TRACKSTAT_NO_TRACK
	EN	No statistics found

PLUGIN_TRACKSTAT_NOT_FOUND
	EN	Can't find current track

PLUGIN_TRACKSTAT_CLEARING
	EN	Removing all TrackStat data

PLUGIN_TRACKSTAT_RATING_NO_SONG
	EN	No song playing

PLUGIN_TRACKSTAT_SONGLIST_TOPRATED
	EN	Top rated songs

PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYED
	EN	Most played songs

PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDALBUMS
	EN	Most played albums

PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYEDARTISTS
	EN	Most played artists

PLUGIN_TRACKSTAT_SONGLIST_LASTPLAYED
	EN	Last played songs

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED
	EN	Songs played long ago

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYED
	EN	Least played songs

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDALBUMS
	EN	Least played albums

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYEDARTISTS
	EN	Least played artists

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS
	EN	Top rated albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDARTISTS
	EN	Top rated artists

PLUGIN_TRACKSTAT_SONGLIST_MENUHEADER
	EN	Choose statistics to view

PLUGIN_TRACKSTAT_PURGING_TRACKS
	EN	Delete unused statistic

PLUGIN_TRACKSTAT_PURGE_TRACKS
	EN	Delete unused statistic

SETUP_PLUGIN_TRACKSTAT_PURGE_TRACKS
	EN	Delete unused statistic after rescan

SETUP_PLUGIN_TRACKSTAT_PURGE_TRACKS_DESC
	EN	This deletes statistic data for all tracks that no longer exists in a database after a rescan, note that if you have changed filename of a track and performed a rescan it till be detected as a completely new track if it does not contain MusicBrainz Id's. Due to this the old file in statistic data will be deleted if you perform this operation. <br><b>WARNING!</b><br>Deleted statistic data will not be possible to get back, so perform a backup of statistic data before you perform this operation.

PLUGIN_TRACKSTAT_REFRESHING_TRACKS
	EN	Refresh statistic data

PLUGIN_TRACKSTAT_REFRESH_TRACKS
	EN	Refresh statistic

SETUP_PLUGIN_TRACKSTAT_REFRESH_TRACKS
	EN	Refresh statistic after rescan

SETUP_PLUGIN_TRACKSTAT_REFRESH_TRACKS_DESC
	EN	Refresh TrackStat information after a complete rescan, this is only neccesary if you have changed some filenames or directory names. As long as you only have added new files you don't need to perform a refresh. The refresh operation will not destroy or remove any data, it will just make sure the TrackStat information is synchronized with the standard slimserver database.

EOF

}
1;
