# 				InformationScreen plugin 
#
#    Copyright (c) 2009 Erland Isaksson (erland_i@hotmail.com)
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

package Plugins::InformationScreen::Plugin;

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;
use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::DateTime;
use POSIX qw(strftime);
use Storable;
use Time::localtime;

use Plugins::InformationScreen::ConfigManager::Main;
use Plugins::InformationScreen::Settings;
use Plugins::InformationScreen::PlayerSettings;
use Plugins::InformationScreen::ManageScreens;
use Data::Dumper;
use Slim::Schema;

my $prefs = preferences('plugin.informationscreen');
my $serverPrefs = preferences('server');

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.informationscreen',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_INFORMATIONSCREEN',
});

# Information on each portable library
my $htmlTemplate = 'plugins/InformationScreen/index.html';
my $PLUGINVERSION = undef;

my $configManager = undef;
my $screens = undef;
my $manageScreenHandler = undef;
my $lastLayoutChange = time();

sub getDisplayName {
	return 'PLUGIN_INFORMATIONSCREEN';
}

sub getConfigManager {
	if(!defined($configManager)) {
		my %parameters = (
			'logHandler' => $log,
			'pluginPrefs' => $prefs,
			'pluginId' => 'MultiLibrary',
			'pluginVersion' => $PLUGINVERSION,
			'downloadApplicationId' => 'InformationScreen',
			'addSqlErrorCallback' => \&addSQLError,
			'downloadVersion' => 1,
		);
		$configManager = Plugins::InformationScreen::ConfigManager::Main->new(\%parameters);
	}
	return $configManager;
}

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	Plugins::InformationScreen::Settings->new($class);
	Plugins::InformationScreen::PlayerSettings->new($class);
	$manageScreenHandler = Plugins::InformationScreen::ManageScreens->new($class);
	Slim::Control::Request::addDispatch(['informationscreen','items'], [1, 1, 1, \&jiveItemsHandler]);
	
	Slim::Music::TitleFormatter::addFormat("SHORTTIME",\&titleFormatTime,1);
	Slim::Music::TitleFormatter::addFormat("TIME",\&titleFormatTime,1);
	Slim::Music::TitleFormatter::addFormat("DATE",\&titleFormatDate,1);
	Slim::Music::TitleFormatter::addFormat("WEEKDAY",\&titleFormatWeekday,1);
	Slim::Music::TitleFormatter::addFormat("SHORTWEEKDAY",\&titleFormatShortWeekday,1);

	checkDefaults();
}

sub prepareManagingScreens {
	my ($client, $params) = @_;
	Plugins::InformationScreen::Plugin::initScreens($client);
	$manageScreenHandler->prepare($client,$params);
}

sub checkDefaults {
        my $prefVal = $prefs->get('screen_directory');
	if (! defined $prefVal) {
		my $dir=$serverPrefs->get('playlistdir');
		$log->debug("Defaulting screen directory to:$dir\n");
		$prefs->set('screen_directory', $dir);
	}
}
sub getSortedScreenKeys {
	my $screens = shift;
	my @keys = keys %$screens;

	@keys = sort { 
		if(defined($screens->{$a}->{'order'}) && defined($screens->{$a}->{'order'})) {
			return $screens->{$a}->{'order'} <=> $screens->{$b}->{'order'};
		}
		if(defined($screens->{$a}->{'order'}) && !defined($screens->{$b}->{'order'})) {
			return $screens->{$a}->{'order'} <=> 50;
		}
		if(!defined($screens->{$a}->{'order'}) && defined($screens->{$b}->{'order'})) {
			return 50 <=> $screens->{$b}->{'order'};
		}
		return 50 <=> 50 
	} @keys;
	return @keys;
}

sub isAllowedInState {
	my $client = shift;
	my $item = shift;

	if(exists $item->{'includedstates'} && $item->{'includedstates'} ne "" && $item->{'includedstates'} ne "0") {
		my @allowedStates = split(/,/,$item->{'includedstates'});
		foreach my $allowedState (@allowedStates) {
			if($allowedState eq "off" && !$client->power()) {
				return 1;
			}elsif($allowedState eq "alarm" && Slim::Utils::Alarm->getCurrentAlarm($client)) {
				return 1;
			}elsif($allowedState eq "play" && $client->power() && Slim::Player::Source::playmode($client) eq 'play') {
				return 1;
			}elsif($allowedState eq "idle" && $client->power() && Slim::Player::Source::playmode($client) ne 'play') {
				return 1;
			}
		}
		$log->debug("Not including ".$item->{'id'}." since it's not allowed in this state (power=".$client->power().", playmode=".Slim::Player::Source::playmode($client).", alarm=".(Slim::Utils::Alarm->getCurrentAlarm($client)?1:0).")");
		return 0;
	}
	return 1;
}

sub isAllowedOnPlayer {
	my $client = shift;
	my $item = shift;

	my $selectedGroup = $prefs->client($client)->get('screengroup');
	if(!$selectedGroup || !exists $item->{'group'} || $item->{'group'} eq "") {
		return 1;
	}elsif($selectedGroup && exists $item->{'group'} && $selectedGroup eq $item->{'group'}) {
		return 1;
	}
	$log->debug("Not including ".$item->{'id'}.", it belongs to a screen configuration group (".$item->{'group'}.") which differs from the group configured for player ($selectedGroup)");
	return 0;
}

sub isAllowedDuringTime {
	my $client = shift;
	my $time = shift;
	my $item = shift;

	if((!exists $item->{'includeddays'} || $item->{'includeddays'} eq "") && (!exists $item->{'includedtime'} || $item->{'includedtime'} eq "")) {
		return 1;
	}
	if(exists $item->{'includedtime'}) {
		if($item->{'includedtime'} =~ /^(\d?\d)\D(\d\d)\s*-\s*(\d?\d)\D(\d\d)/) {
			my $startHour = $1;
			my $startMinute = $2;
			my $endHour = $3;
			my $endMinute = $4;

			if($startHour<$time->hour || ($startHour==$time->hour && $startMinute<=$time->min)) {
				if($endHour<$startHour || ($endHour==$startHour && $endMinute<$startMinute)) {
					# End time is on next day
				}elsif($endHour>$time->hour || ($endHour==$time->hour && $endMinute>=$time->min)) {
					# Time is between start and end time
				}else {
					$log->debug("Not including ".$item->{'id'}." only shown between $startHour:$startMinute to $endHour:$endMinute, it shouldn't be shown at ".$time->hour.":".$time->min);
					return 0;
				}
			}else {
				$log->debug("Not including ".$item->{'id'}." only shown between $startHour:$startMinute to $endHour:$endMinute, it shouldn't be shown at ".$time->hour.":".$time->min);
				return 0;
			}
		}else {
			$log->error("Invalid includedtime format: ".$time->{'includedtime'}." should be in the format 22:00-06:00 (enable during night) or 06:00-22:00 (enabled during day)")
		}
	}
	if(exists $item->{'includeddays'} && $item->{'includeddays'} ne "") {
		my @allowedDays = split(/,/,$item->{'includeddays'});
		if(grep $_ eq $time->wday, @allowedDays) {
			return 1;
		}else {
			$log->debug("Not including ".$item->{'id'}.", it shouldn't be shown this weekday");
			return 0;
		}
	}
	return 1;
}

sub isAllowedInSkin {
	my $client = shift;
	my $skin = shift;
	my $item = shift;

	if(exists $item->{'includedskins'} && $item->{'includedskins'} ne "") {
		my @allowedSkins = split(/,/,$item->{'includedskins'});
		if(grep $_ eq $skin, @allowedSkins) {
			return 1;
		}
		$log->debug("Not including ".$item->{'id'}." since it's not allowed in this skin ($skin)");
		return 0;
	}
	return 1;
}

sub getCurrentScreen {
	my $client = shift;
	my $skin = shift;
	if(! defined $screens) {
		initScreens($client);
	}

	my $screen = undef;
	if(defined($client->pluginData('screen'))) {
		$screen = $client->pluginData('screen');
	}

	my @sortedScreenKeys = getSortedScreenKeys($screens);

	my $lastScreen = undef;
	my @enabledScreenKeys = ();
	my $currentTime = localtime();
	for my $key (@sortedScreenKeys) {
		if(isAllowedInState($client,$screens->{$key}) && isAllowedOnPlayer($client,$screens->{$key}) && isAllowedInSkin($client,$skin,$screens->{$key}) && isAllowedDuringTime($client,$currentTime,$screens->{$key}) && $screens->{$key}->{'enabled'}) {
			push @enabledScreenKeys,$key;
			$lastScreen = $key;
		}
	}

	my $currentTime = time();
	if(defined($screen) && defined($lastScreen) && $screen eq $lastScreen) {
		if($currentTime-$client->pluginData('lastSwitchTime') >= $screens->{$screen}->{'time'}) {
			$log->debug("This is the last screen, let's start from the beginning");
			$screen = undef;
		}
	}

	if(defined($screen) && 	!(grep $_ eq $screen, @enabledScreenKeys)) {
		$log->debug("Selected screen $screen is no longer enabled, let's start from the beginning");
		$screen = undef;
	}

	my $affected = 0;
	for (my $iteration=0; $iteration<2; $iteration++) {
		for my $key (@enabledScreenKeys) {
			if(!defined($screen)) {
				$client->pluginData('screen' => $key);
				$client->pluginData('lastSwitchTime'=> $currentTime);
				$screen = $key;
				$log->debug("Selecting screen $key");
			}
			if($key eq $screen) {
				if($currentTime-$client->pluginData('lastSwitchTime') >= $screens->{$key}->{'time'}) {
					$screen = undef;
				}else {
					if($client->pluginData('lastSwitchTime') != $currentTime) {
						$log->debug("Still time left $currentTime, ".$client->pluginData('lastSwitchTime')." of ".$screens->{$key}->{'time'}." seconds");
					}

					my $currentScreen = Storable::dclone($screens->{$key});
					if(preprocessScreen($client,$currentScreen)) {
						return $currentScreen;
					}else {
						$log->debug("Skipping screen (removed during preprocessing): $key");
						$screen = undef;
						$affected = 1;
					}
				}
			}
		}
		if(!$affected) {
			last;
		}
	}
	return undef;
}

sub jiveItemsHandler {
	$log->debug("Entering jiveItemsHandler");
	my $request = shift;
	my $client = $request->client();

	if (!$request->isQuery([['informationscreen'],['items']])) {
		$log->warn("Incorrect command");
		$request->setStatusBadDispatch();
		$log->debug("Exiting jiveItemsHandler");
		return;
	}
	if(!defined $client) {
		$log->warn("Client required");
		$request->setStatusNeedsClient();
		$log->debug("Exiting jiveItemsHandler");
		return;
	}

	my $params = $request->getParamsCopy();
	my $skin = $request->getParam('skinName');

	my $currentScreen = getCurrentScreen($client,$skin);

	my @empty = ();
	my $listRef = \@empty;
	if(defined($currentScreen)) {
		$listRef = $currentScreen->{'items'}->{'item'};
		if(ref($listRef) ne 'ARRAY') {
			my @empty = ();
			push @empty,$listRef;
			$listRef = \@empty;
		}
	}

  	my $start = $request->getParam('_start') || 0;
	my $itemsPerResponse = $request->getParam('_itemsPerResponse') || scalar(@$listRef);

	my $cnt = 0;
	my $offsetCount = 0;
	my @itemLoop = ();
	my $currentTime = localtime();
	foreach my $group (@$listRef) {
		if(isAllowedInState($client,$group) && isAllowedInSkin($client,$skin,$group) && isAllowedDuringTime($client,$currentTime,$group) && preprocessGroup($client,$group)) {
			if($cnt>=$start && $offsetCount<$itemsPerResponse) {
				my $itemArray = $group->{'item'};
				foreach my $item (@$itemArray) {
					preprocessItem($client,$item);
				}
				push @itemLoop,$group;
				$offsetCount++;
			}
		}else {
			$log->debug("Skipping top item (removed during preprocessing): ".$group->{'id'});
		}
		$cnt++;
	}

	$request->addResult('item_loop',\@itemLoop);

	$request->addResult('offset',$start);
	$request->addResult('count',$cnt);
	$request->addResult('layout',$currentScreen->{'id'});
	$request->addResult('style',$currentScreen->{'style'}) if exists $currentScreen->{'style'};
	$request->addResult('skin',$currentScreen->{'skin'}) if exists $currentScreen->{'skin'};
	$request->addResult('layoutChangedTime',$lastLayoutChange);

	$request->setStatusDone();
	$log->debug("Exiting jiveItemsHandler");
}

sub preprocessScreen {
	my $client = shift;
	my $screen = shift;

	if(exists $screen->{'preprocessing'} && $screen->{'preprocessing'} eq 'function') {
		no strict 'refs';
		$log->debug("Calling: ".$screen->{'preprocessingData'});
		my $result = eval { &{$screen->{'preprocessingData'}}($client,$screen) };
		if ($@) {
			$log->warn("Error preprocessing ".$screen->{'id'}." with ".$screen->{'preprocessingData'}.": $@");
		}
		use strict 'refs';
		return $result;
	}
	return 1;
}

sub preprocessGroup {
	my $client = shift;
	my $group = shift;

	if(exists $group->{'preprocessing'} && $group->{'preprocessing'} eq 'function') {
		no strict 'refs';
		$log->debug("Calling: ".$group->{'preprocessingData'});
		my $result = eval { &{$group->{'preprocessingData'}}($client,$group) };
		if ($@) {
			$log->warn("Error preprocessing ".$group->{'id'}." with ".$group->{'preprocessingData'}.": $@");
		}
		use strict 'refs';
		return $result;
	}
	return 1;
}

sub preprocessItem {
	my $client = shift;
	my $item = shift;

	if(exists $item->{'preprocessing'} && $item->{'preprocessing'} eq 'titleformat') {
		my @formatParts = split(/\\n/,$item->{'preprocessingData'});
		$item->{'value'} = "";
		foreach my $part (@formatParts) {
			if($item->{'value'} ne "") {
				$item->{'value'} .= "\n";
			}
			$item->{'value'} .= getKeywordValues($client,$part);
		}

	}elsif(exists $item->{'preprocessing'} && $item->{'preprocessing'} eq 'datetime') {
		$item->{'value'} = strftime($item->{'preprocessingData'},CORE::localtime(time()));

	}elsif(exists $item->{'preprocessing'} && $item->{'preprocessing'} eq 'function') {
		no strict 'refs';
		$log->debug("Calling: ".$item->{'preprocessingData'});
		eval { &{$item->{'preprocessingData'}}($client,$item) };
		if ($@) {
			$log->warn("Error preprocessing ".$item->{'id'}." with ".$item->{'preprocessingData'}.": $@");
		}
		use strict 'refs';

	}elsif(exists $item->{'preprocessing'} && $item->{'preprocessing'} eq 'artwork') {
		my $song = Slim::Player::Playlist::song($client);
		if(defined($song)) {
			if ( $song->isRemoteURL ) {
				my $handler = Slim::Player::ProtocolHandlers->handlerForURL($song->url);

				if ( $handler && $handler->can('getMetadataFor') ) {

					my $meta = $handler->getMetadataFor( $client, $song->url );

					if ( $meta->{cover} ) {
						$item->{'icon'} = $meta->{cover};
					}
					elsif ( $meta->{icon} ) {
						$item->{'icon-id'} = $meta->{icon};
					}
				}
			        
				# If that didn't return anything, use default cover
				if ( !$item->{'icon-id'} && !$item->{'icon'} ) {
					$item->{'icon-id'} = '/html/images/radio.png';
				}
			}else {
				if ( my $album = $song->album ) {
					$item->{'icon-id'} = ( $album->artwork || 0 ) + 0;
				}
			}
		}
	}
}

sub albumArtExists {
	my $client = shift;
	my $screen = shift;

	my $song = Slim::Player::Playlist::song($client);
	if(defined($song)) {
		if ( $song->isRemoteURL ) {
			my $handler = Slim::Player::ProtocolHandlers->handlerForURL($song->url);

			if ( $handler && $handler->can('getMetadataFor') ) {

				my $meta = $handler->getMetadataFor( $client, $song->url );

				if ( $meta->{cover} ) {
					return 1;
				}
				elsif ( $meta->{icon} ) {
					return 1;
				}
			}
		}else {
			if ( my $album = $song->album ) {
				return 1 if $album->artwork;
			}
		}
	}
	return 0;
}

sub preprocessingShuffleMode {
	my $client = shift;
	my $group = shift;

	my $shuffle = Slim::Player::Playlist::shuffle($client);
	if($shuffle == 1) {
		$group->{'style'} = "shuffleSong";
	}elsif($shuffle == 2) {
		$group->{'style'} = "shuffleAlbum";
	}else {
		$group->{'style'} = "shuffleOff";
	}
	my @empty = ();
	return \@empty;
}

sub preprocessingRepeatMode {
	my $client = shift;
	my $group = shift;

	my $repeat = Slim::Player::Playlist::repeat($client);
	if($repeat == 1) {
		$group->{'style'} = "repeatSong";
	}elsif($repeat == 2) {
		$group->{'style'} = "repeatPlaylist";
	}else {
		$group->{'style'} = "repeatOff";
	}
	my @empty = ();
	return \@empty;
}

sub preprocessingPlayMode {
	my $client = shift;
	my $group = shift;

	my $playMode = Slim::Player::Source::playmode($client);
	if($playMode eq 'play') {
		$group->{'style'} = "pause";
	}else {
		$group->{'style'} = "play";
	}
	my @empty = ();
	return \@empty;
}

sub getKeywordValues {
	my $client = shift;
	my $keyword = shift;

	if($keyword =~ /\bPLAYING\b/) {
		my $mode = Slim::Player::Source::playmode($client);
		my $string = $client->string('PLAYING');
		if($mode eq 'pause') {
			$string = $client->string('PAUSED');
		}elsif($mode eq 'stop') {
			$string = $client->string('STOPPED');
		}
		$log->debug("Replacing PLAYING with $string");
		$keyword =~ s/\bPLAYING\b/$string/;
	}
	if($keyword =~ /\bPLAYLIST\b/) {
                if (my $string = $client->currentPlaylist()) {
                        my $string = Slim::Music::Info::standardTitle($client, $string);
			$log->debug("Replacing PLAYLIST with $string");
			$keyword =~ s/\bPLAYLIST\b/$string/;
                }else {
			$keyword =~ s/\bPLAYLIST\b//;
		}
	}
	if($keyword =~ /\bX_OF_Y\b/) {
                my $songIndex = Slim::Player::Source::playingSongIndex($client);
                
                my $string = sprintf("%d %s %d", 
                                (Slim::Player::Source::playingSongIndex($client) + 1), 
                                $client->string('OUT_OF'), Slim::Player::Playlist::count($client));
		$log->debug("Replacing X_OF_Y with $string");
		$keyword =~ s/\bX_OF_Y\b/$string/;
	}
	if($keyword =~ /\bX_Y\b/) {
                my $songIndex = Slim::Player::Source::playingSongIndex($client);
                
                my $string = sprintf("%d/%d", 
                                (Slim::Player::Source::playingSongIndex($client) + 1), 
                                Slim::Player::Playlist::count($client));
		$log->debug("Replacing X_Y with $string");
		$keyword =~ s/\bX_Y\b/$string/;
	}
	if($keyword =~ /\bALARM\b/) {
                my $currentAlarm = Slim::Utils::Alarm->getCurrentAlarm($client);
                my $nextAlarm = Slim::Utils::Alarm->getNextAlarm($client);

		my $string = "";
                # Include the next alarm time in the overlay if there's room
                if (defined $currentAlarm || ( defined $nextAlarm && ($nextAlarm->nextDue - time < 86400) )) {
                        # Remove seconds from alarm time
                        my $timeStr = Slim::Utils::DateTime::timeF($nextAlarm->time % 86400, undef, 1);
                        $timeStr =~ s/(\d?\d\D\d\d)\D\d\d/$1/;
                        $string = $timeStr;
			$log->debug("Replacing ALARM with $string");
                }

		$keyword =~ s/\bALARM\b/$string/;
	}
	if($keyword =~ /\bPLAYTIME\b/) {
		my $songTime = Slim::Player::Source::songTime($client);
		if(defined($songTime)) {
			my $hrs = int($songTime / (60 * 60));
			my $min = int(($songTime - $hrs * 60 * 60) / 60);
			my $sec = $songTime - ($hrs * 60 * 60 + $min * 60);
		
			if ($hrs) {
			        $songTime = sprintf("%d:%02d:%02d", $hrs, $min, $sec);
			} else {
			        $songTime = sprintf("%02d:%02d", $min, $sec);
			}
			$log->debug("Replacing PLAYTIME with $songTime");
			$keyword =~ s/\bPLAYTIME\b/$songTime/;
		}else {
			$keyword =~ s/\bPLAYTIME\b//;
		}
	}
	if($keyword =~ /\bDURATION\b/) {
		my $songDuration = Slim::Player::Source::playingSongDuration($client);
		if(defined $songDuration && $songDuration>0) {
			my $hrs = int($songDuration / (60 * 60));
			my $min = int(($songDuration - $hrs * 60 * 60) / 60);
			my $sec = $songDuration - ($hrs * 60 * 60 + $min * 60);
		
			if ($hrs) {
			        $songDuration = sprintf("%d:%02d:%02d", $hrs, $min, $sec);
			} else {
			        $songDuration = sprintf("%02d:%02d", $min, $sec);
			}
			$log->debug("Replacing DURATION with $songDuration");
			$keyword =~ s/\bDURATION\b/$songDuration/;
		}else {
			$keyword =~ s/\bDURATION\b//;
		}
	}
	if($keyword =~ /\bPLAYTIME_PROGRESS\b/) {
		my $songTime = Slim::Player::Source::songTime($client);
		my $songDuration = Slim::Player::Source::playingSongDuration($client);
		if(defined $songTime && defined $songDuration && $songDuration>0) {
			my $progress = int(100*$songTime/$songDuration);
			$log->debug("Replacing PLAYTIME_PROGRESS with $progress");
			$keyword =~ s/\bPLAYTIME_PROGRESS\b/$progress/;
		}else {
			$keyword =~ s/\bPLAYTIME_PROGRESS\b//;
		}
	}
	if($keyword =~ /\bVOLUME\b/) {
		if($client->hasVolumeControl()) {
			my $minVolume = $client->minVolume();
			my $maxVolume = $client->maxVolume();
			my $volume = $client->volume()-$client->minVolume();
			$volume = int(100*(($volume-$minVolume)/($maxVolume-$minVolume)));
			$log->debug("Replacing VOLUME with $volume");
			$keyword =~ s/\bVOLUME\b/$volume/;
		}else {
			$keyword =~ s/\bVOLUME\b//;
		}
	}

	my $song = Slim::Player::Playlist::song($client);

	$log->debug("Replacing remaining keywords in: $keyword");
	if(defined($song)) {
		$keyword = Slim::Music::Info::displayText($client,$song,$keyword);
	}else {
		$keyword = Slim::Music::Info::displayText($client,undef,$keyword,{})
	}
	$log->debug("Final string after all replacements are: $keyword");
	return $keyword;
}

sub titleFormatShortWeekday {
	my $time = time();
	return Slim::Utils::DateTime::timeF($time, "%a");
}
sub titleFormatWeekday {
	my $time = time();
	return Slim::Utils::DateTime::timeF($time, "%A");
}
sub titleFormatDate {
	my $time = time();
	return Slim::Utils::DateTime::shortDateF($time);
}
sub titleFormatTime {
	my $time = time();
	return Slim::Utils::DateTime::timeF($time);
}
sub titleFormatShortTime {
	my $time = time();
	my $timeStr = Slim::Utils::DateTime::timeF($time);
	$timeStr =~ s/(\d?\d\D\d\d)\D\d\d/$1/;
	return $timeStr;
}

sub initScreens {
	my $client = shift;

	my $itemConfiguration = getConfigManager()->readItemConfiguration($client,1);

	my $localScreens = $itemConfiguration->{'screens'};
	$lastLayoutChange = time();

	$screens = $localScreens;
}
sub webPages {

	my %pages = (
		"InformationScreen/informationscreen_list\.(?:htm|xml)"     => \&handleWebList,
		"InformationScreen/informationscreen_refreshscreens\.(?:htm|xml)"     => \&handleWebRefreshScreens,
                "InformationScreen/webadminmethods_edititem\.(?:htm|xml)"     => \&handleWebEditScreen,
                "InformationScreen/webadminmethods_hideitem\.(?:htm|xml)"     => \&handleWebHideMenu,
                "InformationScreen/webadminmethods_showitem\.(?:htm|xml)"     => \&handleWebShowMenu,
                "InformationScreen/webadminmethods_saveitem\.(?:htm|xml)"     => \&handleWebSaveScreen,
                "InformationScreen/webadminmethods_savesimpleitem\.(?:htm|xml)"     => \&handleWebSaveSimpleScreen,
                "InformationScreen/webadminmethods_savenewitem\.(?:htm|xml)"     => \&handleWebSaveNewScreen,
                "InformationScreen/webadminmethods_savenewsimpleitem\.(?:htm|xml)"     => \&handleWebSaveNewSimpleScreen,
                "InformationScreen/webadminmethods_removeitem\.(?:htm|xml)"     => \&handleWebRemoveScreen,
                "InformationScreen/webadminmethods_newitemtypes\.(?:htm|xml)"     => \&handleWebNewScreenTypes,
                "InformationScreen/webadminmethods_newitemparameters\.(?:htm|xml)"     => \&handleWebNewScreenParameters,
                "InformationScreen/webadminmethods_newitem\.(?:htm|xml)"     => \&handleWebNewScreen,
		"InformationScreen/webadminmethods_login\.(?:htm|xml)"      => \&handleWebLogin,
		"InformationScreen/webadminmethods_downloadnewitems\.(?:htm|xml)"      => \&handleWebDownloadNewScreens,
		"InformationScreen/webadminmethods_downloaditems\.(?:htm|xml)"      => \&handleWebDownloadScreens,
		"InformationScreen/webadminmethods_downloaditem\.(?:htm|xml)"      => \&handleWebDownloadScreen,
		"InformationScreen/webadminmethods_publishitemparameters\.(?:htm|xml)"      => \&handleWebPublishScreenParameters,
		"InformationScreen/webadminmethods_publishitem\.(?:htm|xml)"      => \&handleWebPublishScreen,
		"InformationScreen/webadminmethods_deleteitemtype\.(?:htm|xml)"      => \&handleWebDeleteScreenType,
	);

	for my $page (keys %pages) {
		if(UNIVERSAL::can("Slim::Web::Pages","addPageFunction")) {
			Slim::Web::Pages->addPageFunction($page, $pages{$page});
		}else {
			Slim::Web::HTTP::addPageFunction($page, $pages{$page});
		}
	}
	#Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_INFORMATIONSCREEN' => 'plugins/InformationScreen/informationscreen_list.html' });
}


# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	# Pass on the current pref values and now playing info
	if(!defined($params->{'donotrefresh'})) {
		if(defined($params->{'cleancache'}) && $params->{'cleancache'}) {
			my $cache = Slim::Utils::Cache->new("FileCache/InformationScreen");
			$cache->clear();
		}
		initScreens($client);
	}
	my $name = undef;
	my @webscreens = ();
	for my $key (keys %$screens) {
		my %webscreen = ();
		my $lib = $screens->{$key};
		for my $attr (keys %$lib) {
			$webscreen{$attr} = $lib->{$attr};
		}
		if(!isScreenEnabledForClient($client,\%webscreen)) {
			$webscreen{'enabled'} = 0;
		}

		push @webscreens,\%webscreen;
	}
	@webscreens = sort { $a->{'name'} cmp $b->{'name'} } @webscreens;

	$params->{'pluginInformationScreenScreens'} = \@webscreens;
	my $templateDir = $prefs->get('template_directory');
	if(!defined($templateDir) || !-d $templateDir) {
		$params->{'pluginInformationScreenDownloadMessage'} = 'You have to specify a template directory before you can download screens';
	}
	$params->{'pluginInformationScreenDownloadMessage'} = 'Download not supported in this version';

	$params->{'pluginInformationScreenVersion'} = $PLUGINVERSION;
	if(defined($params->{'redirect'})) {
		return Slim::Web::HTTP::filltemplatefile('plugins/InformationScreen/informationscreen_redirect.html', $params);
	}else {
		return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
	}
}

sub isScreenEnabledForClient {
	my $client = shift;
	my $library = shift;
	
	if(defined($library->{'includedclients'})) {
		if(defined($client)) {
			my @clients = split(/,/,$library->{'includedclients'});
			for my $clientName (@clients) {
				if($client->name eq $clientName) {
					return 1;
				}
			}
		}
		return 0;
	}elsif(defined($library->{'excludedclients'} && ref($library->{'excludedclients'}) ne 'HASH')) {
		if(defined($client)) {
			my @clients = split(/,/,$library->{'excludedclients'});
			for my $clientName (@clients) {
				if($client->name eq $clientName) {
					return 0;
				}
			}
		}
		return 1;
	}else {
		return 1;
	}
}

sub handleWebRefreshScreens {
	my ($client, $params) = @_;

	initScreens($client);
	return handleWebList($client,$params);
}

sub handleWebEditScreens {
        my ($client, $params) = @_;
	return getConfigManager()->webEditItems($client,$params);	
}


sub handleWebEditScreen {
        my ($client, $params) = @_;
	return getConfigManager()->webEditItem($client,$params);	
}

sub handleWebHideMenu {
        my ($client, $params) = @_;
	hideMenu($client,$params,getConfigManager(),1,'screen_');	
	return handleWebEditScreens($client,$params);
}

sub handleWebShowMenu {
        my ($client, $params) = @_;
	hideMenu($client,$params,getConfigManager(),0,'screen_');	
	return handleWebEditScreens($client,$params);
}

sub hideMenu {
	my $client = shift;
	my $params = shift;
	my $cfgMgr = shift;
	my $hide = shift;
	my $prefix = shift;

	my $items = $cfgMgr->items();
	my $itemId = escape($params->{'item'});
	if(defined($items->{$itemId})) {
		if($hide) {
			$prefs->set($prefix.$itemId.'_enabled',0);
			$items->{$itemId}->{'enabled'}=0;
		}else {
			$prefs->set($prefix.$itemId.'_enabled',1);
			$items->{$itemId}->{'enabled'}=1;
		}
	}
}

sub handleWebDeleteScreenType {
	my ($client, $params) = @_;
	return getConfigManager()->webDeleteItemType($client,$params);	
}

sub handleWebNewScreenTypes {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItemTypes($client,$params);	
}

sub handleWebNewScreenParameters {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItemParameters($client,$params);	
}

sub handleWebLogin {
	my ($client, $params) = @_;
	return getConfigManager()->webLogin($client,$params);	
}

sub handleWebPublishScreenParameters {
	my ($client, $params) = @_;
	return getConfigManager()->webPublishItemParameters($client,$params);	
}

sub handleWebPublishScreen {
	my ($client, $params) = @_;
	return getConfigManager()->webPublishItem($client,$params);	
}

sub handleWebDownloadScreens {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadItems($client,$params);	
}

sub handleWebDownloadNewScreens {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadNewItems($client,$params);	
}

sub handleWebDownloadScreen {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadItem($client,$params);	
}

sub handleWebNewScreen {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItem($client,$params);	
}

sub handleWebSaveSimpleScreen {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveSimpleItem($client,$params);	
}

sub handleWebRemoveScreen {
	my ($client, $params) = @_;
	return getConfigManager()->webRemoveItem($client,$params);	
}

sub handleWebSaveNewSimpleScreen {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveNewSimpleItem($client,$params);	
}

sub handleWebSaveNewScreen {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveNewItem($client,$params);	
}

sub handleWebSaveScreen {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveItem($client,$params);	
}

sub addSQLError {
	my $error = shift;
	$log->error("Error: $error");
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
