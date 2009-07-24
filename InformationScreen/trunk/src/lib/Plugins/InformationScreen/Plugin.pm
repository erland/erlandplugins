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
use POSIX qw(strftime);

use Plugins::InformationScreen::ConfigManager::Main;
use Plugins::InformationScreen::Settings;
use Plugins::InformationScreen::ManageScreens;

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
	$manageScreenHandler = Plugins::InformationScreen::ManageScreens->new($class);
	Slim::Control::Request::addDispatch(['informationscreen','items'], [1, 1, 1, \&jiveItemsHandler]);

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
sub getCurrentScreen {
	my $client = shift;
	if(! defined $screens) {
		initScreens($client);
	}

	my $screen = undef;
	if(defined($client->pluginData('screen'))) {
		$screen = $client->pluginData('screen');
	}

	my @sortedScreenKeys = getSortedScreenKeys($screens);

	my $lastScreen = undef;
	for my $key (@sortedScreenKeys) {
		$lastScreen = $key;
	}

	my $currentTime = time();
	if(defined($screen) && defined($lastScreen) && $screen eq $lastScreen) {
		if($currentTime-$client->pluginData('lastSwitchTime') >= $screens->{$screen}->{'time'}) {
			$log->debug("This is the last screen, let's start from the beginning");
			$screen = undef;
		}
	}

	for my $key (@sortedScreenKeys) {
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
				$log->debug("Still time left $currentTime, ".$client->pluginData('lastSwitchTime')." of ".$screens->{$key}->{'time'}." seconds");
				return $screens->{$key};
			}
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

	my $currentScreen = getCurrentScreen($client);

	my $listRef = ();
	if(defined($currentScreen)) {
		$listRef = $currentScreen->{'items'}->{'group'};
	}

  	my $start = $request->getParam('_start') || 0;
	my $itemsPerResponse = $request->getParam('_itemsPerResponse') || scalar(@$listRef);

	my $cnt = 0;
	my $offsetCount = 0;
	my @itemLoop = ();
	foreach my $group (@$listRef) {
		if(!exists $group->{'includedskins'} || isSkinIncluded($group->{'includedskins'},$request->getParam('skin'))) {
			if(!exists $group->{'excludedskins'} || !isSkinExcluded($group->{'excludedskins'},$request->getParam('skin'))) {
				if($cnt>=$start && $offsetCount<$itemsPerResponse) {
					preprocessItems($client,$group);
					push @itemLoop,$group;
					$offsetCount++;
				}
			}
		}
		$cnt++;
	}
	$request->addResult('item_loop',\@itemLoop);

	$request->addResult('offset',$start);
	$request->addResult('count',$cnt);
	$request->addResult('layout',$currentScreen->{'layout'});
	$request->addResult('style',$currentScreen->{'style'}) if exists $currentScreen->{'style'};
	$request->addResult('skin',$currentScreen->{'skin'}) if exists $currentScreen->{'skin'};
	$request->addResult('layoutChangedTime',$lastLayoutChange);

	$request->setStatusDone();
	$log->debug("Exiting jiveItemsHandler");
}

sub isSkinIncluded {
	my $allowedSkins = shift;
	my $currentSkin = shift;

	my @allowedSkinsArray = split(/,/,$allowedSkins);
	foreach my $skin (@allowedSkinsArray) {
		if($skin eq $currentSkin) {
			return 1;
		}
	}
	return 0;
}

sub isSkinExcluded {
	my $allowedSkins = shift;
	my $currentSkin = shift;

	my @allowedSkinsArray = split(/,/,$allowedSkins);
	foreach my $skin (@allowedSkinsArray) {
		if($skin eq $currentSkin) {
			return 0;
		}
	}
	return 1;
}

sub preprocessItems {
	my $client = shift;
	my $group = shift;

	my $items = $group->{'item'};
	my @itemArray = ();
	if(ref($items) eq 'ARRAY') {
		@itemArray = @$items;
	}else {
		push @itemArray,$items;
	}

	foreach my $item (@itemArray) {
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
			$item->{'value'} = strftime($item->{'preprocessingData'},localtime(time()));

		}elsif(exists $item->{'preprocessing'} && $item->{'preprocessing'} eq 'function') {
			no strict 'refs';
			$log->debug("Calling: ".$item->{'preprocessingData'});
			eval { &{$item->{'preprocessingData'}}($client,$item) };
			if ($@) {
				$log->warn("Error preprocessing $item->{'id'} with ".$item->{'preprocessingData'}.": $@");
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
}

sub preprocessingShuffleMode {
	my $client = shift;
	my $item = shift;

	my $shuffle = Slim::Player::Playlist::shuffle($client);
	if($shuffle == 1) {
		$item->{'style'} = "shuffleSong";
	}elsif($shuffle == 2) {
		$item->{'style'} = "shuffleAlbum";
	}else {
		$item->{'style'} = "shuffleOff";
	}
}

sub preprocessingRepeatMode {
	my $client = shift;
	my $item = shift;

	my $repeat = Slim::Player::Playlist::repeat($client);
	if($repeat == 1) {
		$item->{'style'} = "repeatSong";
	}elsif($repeat == 2) {
		$item->{'style'} = "repeatPlaylist";
	}else {
		$item->{'style'} = "repeatOff";
	}
}

sub preprocessingPlayMode {
	my $client = shift;
	my $item = shift;

	my $playMode = Slim::Player::Source::playmode($client);
	if($playMode eq 'play') {
		$item->{'style'} = "pause";
	}else {
		$item->{'style'} = "play";
	}
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
		$keyword =~ s/\bPLAYING\b/$string/;
	}
	if($keyword =~ /\bPLAYLIST\b/) {
                if (my $string = $client->currentPlaylist()) {
                        my $string = Slim::Music::Info::standardTitle($client, $string);
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
		$keyword =~ s/\bX_OF_Y\b/$string/;
	}
	if($keyword =~ /\bX_Y\b/) {
                my $songIndex = Slim::Player::Source::playingSongIndex($client);
                
                my $string = sprintf("%d/%d", 
                                (Slim::Player::Source::playingSongIndex($client) + 1), 
                                Slim::Player::Playlist::count($client));
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
			$keyword =~ s/\bVOLUME\b/$volume/;
		}else {
			$keyword =~ s/\bVOLUME\b//;
		}
	}
	my $song = Slim::Player::Playlist::song($client);
	return Slim::Music::Info::displayText($client,$song,$keyword);
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
	Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_INFORMATIONSCREEN' => 'plugins/InformationScreen/informationscreen_list.html' });
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
