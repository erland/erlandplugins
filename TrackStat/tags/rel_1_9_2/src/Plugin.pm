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
use POSIX qw(strftime);
use File::Spec::Functions qw(:ALL);
use DBI qw(:sql_types);

use FindBin qw($Bin);
use Plugins::TrackStat::Time::Stopwatch;
use Plugins::TrackStat::iTunes::Import;
use Plugins::TrackStat::Backup::File;

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
				if (my($playedCount, $playedDate, $rating) = getTrackFromStorage($playStatus)) {
					$playStatus->trackAlreadyLoaded('true');
					$playStatus->lastPlayed($playedDate);
					$playStatus->playCount($playedCount);
					#don't overwrite the user's rating
					if ($playStatus->currentSongRating() eq '') {
						$playStatus->currentSongRating($rating);
					}
				} else {
					$playStatus->trackAlreadyLoaded('notfound');
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
	 PrefOrder => ['plugin_trackstat_backup_file','plugin_trackstat_backup','plugin_trackstat_restore','plugin_trackstat_clear','plugin_trackstat_itunes_import','plugin_trackstat_itunes_library_file','plugin_trackstat_itunes_library_music_path','plugin_trackstat_itunes_replace_extension','plugin_trackstat_web_list_length','plugin_trackstat_showmessages'],
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
	plugin_trackstat_web_list_length => {
			'validate'     => \&Slim::Web::Setup::validateInt
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_WEB_LIST_LENGTH')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_WEB_LIST_LENGTH')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_web_list_length"); }
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
			,'onChange' => sub { clearAllData(); }
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
	plugin_trackstat_itunes_import => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll
			,'onChange' => sub { importFromiTunes(); }
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_TRACKSTAT_ITUNES_IMPORTING')
			,'ChangeButton' => string('PLUGIN_TRACKSTAT_ITUNES_IMPORT_BUTTON')
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
		"lastplayed\.htm" => \&handleWebLastPlayed,
		"toprated\.htm" => \&handleWebTopRated,
		"topratedalbums\.htm" => \&handleWebTopRatedAlbums,
		"topratedartists\.htm" => \&handleWebTopRatedArtists,
		"leastplayed\.htm" => \&handleWebLeastPlayed,
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
	
sub handleWebIndex {
	my ($client, $params) = @_;

	baseWebPage($client, $params);
    my $ds     = Slim::Music::Info::getCurrentDataStore();

	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub handleWebMostPlayed {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

	my $driver = Slim::Utils::Prefs::get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
    my $orderBy;
    if($driver eq 'mysql') {
    	$orderBy = "rand()";
    }else {
    	$orderBy = "random()";
    }
    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    my $sql = "select tracks.url,track_statistics.playCount,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    collectWebSongs($client,$params,$sql);
	$params->{'songlist'} = 'MOSTPLAYED';
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub handleWebLeastPlayed {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

	my $driver = Slim::Utils::Prefs::get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
    my $orderBy;
    if($driver eq 'mysql') {
    	$orderBy = "rand()";
    }else {
    	$orderBy = "random()";
    }
    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    my $sql = "select tracks.url,track_statistics.playCount,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.playCount asc,tracks.playCount asc,$orderBy limit $listLength;";
    collectWebSongs($client,$params,$sql);
	$params->{'songlist'} = 'LEASTPLAYED';
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub collectWebSongs {
	my $client = shift;
	my $params = shift;
	my $sql = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->execute();

		my( $url, $playCount, $lastPlayed, $rating );
		$sth->bind_columns( undef, \$url, \$playCount, \$lastPlayed, \$rating );
		my $itemNumber = 0;
		while( $sth->fetch() ) {
			my $track = $ds->objectForUrl($url);
		  	my %trackInfo = ();
			my $fieldInfo = Slim::DataStores::Base->fieldInfo;
            my $levelInfo = $fieldInfo->{'track'};
			
            &{$levelInfo->{'listItem'}}($ds, \%trackInfo, $track);
		  	$trackInfo{'title'} = Slim::Music::Info::standardTitle(undef,$track);
		  	$trackInfo{'lastPlayed'} = $lastPlayed;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
            $trackInfo{'skinOverride'}     = $params->{'skinOverride'};
            $trackInfo{'song_count'}       = $playCount;
            $trackInfo{'attributes'}       = '&track='.$track->id;
            $trackInfo{'itemobj'}          = $track;
            $trackInfo{'listtype'} = 'track';
            		  	
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
}

sub collectWebAlbums {
	my $client = shift;
	my $params = shift;
	my $sql = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->execute();

		my( $id, $rating );
		$sth->bind_columns( undef, \$id, \$rating );
		my $itemNumber = 0;
		while( $sth->fetch() ) {
			my $album = $ds->objectForId('album',$id);
		  	my %trackInfo = ();
			my $fieldInfo = Slim::DataStores::Base->fieldInfo;
            my $levelInfo = $fieldInfo->{'album'};
			
            &{$levelInfo->{'listItem'}}($ds, \%trackInfo, $album);
		  	$trackInfo{'title'} = undef;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
            $trackInfo{'skinOverride'}     = $params->{'skinOverride'};
            $trackInfo{'attributes'}       = '&album='.$album->id;
            $trackInfo{'itemobj'}{'album'} = $album;
            $trackInfo{'listtype'} = 'album';
		  	
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
}

sub collectWebArtists {
	my $client = shift;
	my $params = shift;
	my $sql = shift;
    my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->execute();

		my( $id, $rating );
		$sth->bind_columns( undef, \$id, \$rating );
		my $itemNumber = 0;
		while( $sth->fetch() ) {
			my $artist = $ds->objectForId('artist',$id);
		  	my %trackInfo = ();
			my $fieldInfo = Slim::DataStores::Base->fieldInfo;
            my $levelInfo = $fieldInfo->{'artist'};
			
            &{$levelInfo->{'listItem'}}($ds, \%trackInfo, $artist);
		  	$trackInfo{'title'} = undef;
		  	$trackInfo{'rating'} = ($rating && $rating>0?($rating+10)/20:0);
		  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
			$trackInfo{'player'} = $params->{'player'};
            $trackInfo{'skinOverride'}     = $params->{'skinOverride'};
            $trackInfo{'attributes'}       = '&artist='.$artist->id;
            $trackInfo{'itemobj'}{'artist'} = $artist;
            $trackInfo{'listtype'} = 'artist';
            		  	
		  	push @{$params->{'browse_items'}},\%trackInfo;
		  	$itemNumber++;
		  
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
}

sub handleWebLastPlayed {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

	my $driver = Slim::Utils::Prefs::get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
    my $orderBy;
    if($driver eq 'mysql') {
    	$orderBy = "rand()";
    }else {
    	$orderBy = "random()";
    }
    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    my $sql = "select tracks.url,track_statistics.playCount,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.lastPlayed desc,tracks.lastPlayed desc,$orderBy limit $listLength;";
    collectWebSongs($client,$params,$sql);
	$params->{'songlist'} = 'LASTPLAYED';
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub handleWebFirstPlayed {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

	my $driver = Slim::Utils::Prefs::get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
    my $orderBy;
    if($driver eq 'mysql') {
    	$orderBy = "rand()";
    }else {
    	$orderBy = "random()";
    }
    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    my $sql = "select tracks.url,track_statistics.playCount,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.lastPlayed asc,tracks.lastPlayed asc,$orderBy limit $listLength;";
    collectWebSongs($client,$params,$sql);
	$params->{'songlist'} = 'FIRSTPLAYED';
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub handleWebTopRated {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

	my $driver = Slim::Utils::Prefs::get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
    my $orderBy;
    if($driver eq 'mysql') {
    	$orderBy = "rand()";
    }else {
    	$orderBy = "random()";
    }
    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    my $sql = "select tracks.url,track_statistics.playCount,track_statistics.lastPlayed,track_statistics.rating from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.audio=1 order by track_statistics.rating desc,track_statistics.playCount desc,tracks.playCount desc,$orderBy limit $listLength;";
    collectWebSongs($client,$params,$sql);
	$params->{'songlist'} = 'TOPRATED';
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub handleWebTopRatedAlbums {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

	my $driver = Slim::Utils::Prefs::get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
    my $orderBy;
    if($driver eq 'mysql') {
    	$orderBy = "rand()";
    }else {
    	$orderBy = "random()";
    }
    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    my $sql = "select albums.id,avg(track_statistics.rating) as avgrating from tracks left join track_statistics on tracks.url = track_statistics.url join albums on tracks.album=albums.id group by tracks.album order by avgrating desc,$orderBy limit $listLength;";
    collectWebAlbums($client,$params,$sql);
	$params->{'songlist'} = 'TOPRATEDALBUMS';
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub handleWebTopRatedArtists {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

	my $driver = Slim::Utils::Prefs::get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
    
    my $orderBy;
    if($driver eq 'mysql') {
    	$orderBy = "rand()";
    }else {
    	$orderBy = "random()";
    }
    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    my $sql = "select contributors.id,avg(track_statistics.rating) as avgrating from tracks left join track_statistics on tracks.url = track_statistics.url join contributor_track on tracks.id=contributor_track.track join contributors on contributors.id = contributor_track.contributor group by contributors.id order by avgrating desc,$orderBy limit $listLength;";
    collectWebArtists($client,$params,$sql);
	$params->{'songlist'} = 'TOPRATEDARTISTS';
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
		# set default web list length to same as items per page
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_web_list_length"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_web_list_length",Slim::Utils::Prefs::get("itemsPerPage"));
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
		debugMsg("Comparing: $titleformat WITH $format\n");
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
			sendTrackToStorage($playStatus);
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

sub sendTrackToStorage($)
{
	my ($playStatus) = @_;

	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = $ds->objectForUrl($playStatus->currentTrackOriginalFilename());
	my $trackHandle = searchTrackInStorage( $playStatus->currentTrackOriginalFilename());
	my $sql;
	my $url = $track->url;

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
	if(!$lastPlayed) {
		$lastPlayed = time();
	}

	if ($trackHandle) {
		$sql = ("UPDATE track_statistics set playCount=$playCount, lastPlayed=$lastPlayed where url=?");
	}else {
		$sql = ("INSERT INTO track_statistics (url,playCount,lastPlayed) values (?,$playCount,$lastPlayed)");
	}
	my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->bind_param(1, $url , SQL_VARCHAR);
		$sth->execute();
		$dbh->commit();
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    $dbh->rollback(); #just die if rollback is failing
	}
	$sth->finish();
}

sub sendRatingToStorage {
	my ($url,$rating) = @_;
	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $trackHandle = searchTrackInStorage( $url);
	my $sql;
	
	debugMsg("Store rating\n");
    #ratings are 0-5 stars, 100 = 5 stars
	$rating = $rating * 20;

	if ($trackHandle) {
		$sql = ("UPDATE track_statistics set rating=$rating where url=?");
	} else {
		$sql = ("INSERT INTO track_statistics (url,rating) values (?,$rating)");
	}
	my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
	my $sth = $dbh->prepare( $sql );
	eval {
		$sth->bind_param(1, $url , SQL_VARCHAR);
		$sth->execute();
		$dbh->commit();
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    $dbh->rollback(); #just die if rollback is failing
	}

	$sth->finish();
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
		debugMsg("Track: ", $playStatus->currentTrackOriginalFilename," not found\n");
		return undef;
	}
	return $playedCount, $playedDate,$rating;
}


sub rateSong($$$) {
	my ($client,$url,$digit)=@_;

	debugMsg("Changing song rating to: $digit\n");
	sendRatingToStorage($url,$digit);
	Slim::Music::Info::clearFormatDisplayCache();
}

sub searchTrackInStorage {
	my $track_url = shift;
	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = $ds->objectForUrl($track_url);
	
	return 0 unless $track;
	debugMsg("URL: ".$track->url."\n");

	# create searchString and remove duplicate/trailing whitespace as well.
    my $searchString = "";
	$searchString .= $track->url;

	return 0 unless length($searchString) >= 1;

	my $sql = ("SELECT url, playCount, lastPlayed, rating FROM track_statistics where url=?");

	my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
	my $sth = $dbh->prepare( $sql );
	my $result = undef;
	eval {
		$sth->bind_param(1, $searchString , SQL_VARCHAR);
		$sth->execute();

		my( $url, $playCount, $lastPlayed, $rating );
		$sth->bind_columns( undef, \$url, \$playCount, \$lastPlayed, \$rating );
		while( $sth->fetch() ) {
		  $result = TrackInfo->new( url => $url, playCount => $playCount, lastPlayed => $lastPlayed, rating => $rating );
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
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

sub getRatingDynamicCustomItem
{
	my $track = shift;
	my $trackHandle = searchTrackInStorage( $track->url);
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
	my $trackHandle = searchTrackInStorage( $track->url);
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
	my $trackHandle = searchTrackInStorage( $track->url);
	my $string = '';
	if($trackHandle && $trackHandle->rating) {
		my $rating = $trackHandle->rating / 20;
		$string = ($rating?$rating:'');
	}
	return $string;
}

sub importFromiTunes()
{
	Plugins::TrackStat::iTunes::Import::startScan();
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
sub clearAllData()
{
	my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
	my $sth = $dbh->prepare( "delete from track_statistics" );
	
	$sth->execute();
	$dbh->commit();

	$sth->finish();
	msg("TrackStat: Clear all data finished at: ".time()."\n");
}

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
	EN	Number of songs on web

SETUP_PLUGIN_TRACKSTAT_WEB_LIST_LENGTH_DESC
	EN	Number songs that should be shown in the web interface for TrackStat when choosing to view statistic information

PLUGIN_TRACKSTAT_WEB_LIST_LENGTH
	EN	Number of songs

PLUGIN_TRACKSTAT_RESTORE
	EN	Restore from file

SETUP_PLUGIN_TRACKSTAT_RESTORE
	EN	Restore from file

SETUP_PLUGIN_TRACKSTAT_RESTORE_DESC
	EN	Restore TrackStat information from the file specified as backup file.<br><b>Warning!</b> This will overwrite any TrackStat information that exist with the information in the file

PLUGIN_TRACKSTAT_RESTORING_BACKUP
	EN	Restoring TrackStat backup from file...

PLUGIN_TRACKSTAT_CLEAR
	EN	Remove all data

SETUP_PLUGIN_TRACKSTAT_CLEAR
	EN	Remove all data

SETUP_PLUGIN_TRACKSTAT_CLEAR_DESC
	EN	This will remove all existing TrackStat data.<br><b>Warning!</b> if you have not made an backup of the information it will be lost forever.

PLUGIN_TRACKSTAT_NO_TRACK
	EN	No statistics found

PLUGIN_TRACKSTAT_NOT_FOUND
	EN	No statistics found

PLUGIN_TRACKSTAT_CLEARING
	EN	Removing all TrackStat data

PLUGIN_TRACKSTAT_RATING_NO_SONG
	EN	No song playing

PLUGIN_TRACKSTAT_SONGLIST_TOPRATED
	EN	Top rated songs

PLUGIN_TRACKSTAT_SONGLIST_MOSTPLAYED
	EN	Most played songs

PLUGIN_TRACKSTAT_SONGLIST_LASTPLAYED
	EN	Last played songs

PLUGIN_TRACKSTAT_SONGLIST_FIRSTPLAYED
	EN	Songs played long ago

PLUGIN_TRACKSTAT_SONGLIST_LEASTPLAYED
	EN	Least played songs

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDALBUMS
	EN	Top rated albums

PLUGIN_TRACKSTAT_SONGLIST_TOPRATEDARTISTS
	EN	Top rated artists

PLUGIN_TRACKSTAT_SONGLIST_MENUHEADER
	EN	Choose statistics to view

EOF

}
1;
