# 				CustomBrowse plugin 
#
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
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

package Plugins::CustomBrowse::Plugin;

use strict;

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use File::Spec::Functions qw(:ALL);
use File::Slurp;
use XML::Simple;
use Data::Dumper;
use DBI qw(:sql_types);
use FindBin qw($Bin);
use HTML::Entities;
use Scalar::Util qw(blessed);

use Plugins::CustomBrowse::ConfigManager::Main;

use Plugins::CustomBrowse::MenuHandler::Main;

my $driver;
my $browseMenusFlat;
my $templates;
my $mixer;
my $PLUGINVERSION = '1.20';
my $sqlerrors = '';
my %uPNPCache = ();

my $configManager = undef;

my $menuHandler = undef;

my $supportDownloadError = undef;

sub getDisplayName {
	my $menuName = Slim::Utils::Prefs::get('plugin_custombrowse_menuname');
	if($menuName) {
		Slim::Utils::Strings::addStringPointer( uc 'PLUGIN_CUSTOMBROWSE', $menuName );
	}
	return 'PLUGIN_CUSTOMBROWSE';
}

my %choiceMapping = (
        'arrow_left' => 'exit_left',
        'arrow_right' => 'exit_right',
        'play' => 'dead',
	'play.single' => 'play_0',
	'play.hold' => 'create_mix',
        'add' => 'dead',
        'add.single' => 'add_0',
        'add.hold' => 'insert_0',
        'search' => 'passback',
        'stop' => 'passback',
        'pause' => 'passback',
	'0.hold' => 'saveRating_0',
	'1.hold' => 'saveRating_1',
	'2.hold' => 'saveRating_2',
	'3.hold' => 'saveRating_3',
	'4.hold' => 'saveRating_4',
	'5.hold' => 'saveRating_5',
	'6.hold' => 'saveRating_6',
	'7.hold' => 'saveRating_7',
	'8.hold' => 'saveRating_8',
	'9.hold' => 'saveRating_9',
	'0.single' => 'numberScroll_0',
	'1.single' => 'numberScroll_1',
	'2.single' => 'numberScroll_2',
	'3.single' => 'numberScroll_3',
	'4.single' => 'numberScroll_4',
	'5.single' => 'numberScroll_5',
	'6.single' => 'numberScroll_6',
	'7.single' => 'numberScroll_7',
	'8.single' => 'numberScroll_8',
	'9.single' => 'numberScroll_9',
	'0' => 'dead',
	'1' => 'dead',
	'2' => 'dead',
	'3' => 'dead',
	'4' => 'dead',
	'5' => 'dead',
	'6' => 'dead',
	'7' => 'dead',
	'8' => 'dead',
	'9' => 'dead'
);

# Returns the display text for the currently selected item in the menu
sub getDisplayText {
	my ($client, $item) = @_;

	my $id = undef;
	my $name = '';
	if($item) {
		$name = getMenuHandler()->getItemText($client,$item);
	}
	return $name;
}

# Returns the overlay to be display next to items in the menu
sub getOverlay {
	my ($client, $item) = @_;
	
	if($item) {
		return getMenuHandler()->getItemOverlay($client,$item);
	}else {
		return [undef,undef];
	}
}

sub setMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
        #readBrowseConfiguration($client);
        my $params = getMenuHandler()->getMenu($client,undef);
	if(defined($params)) {
		if(defined($params->{'useMode'})) {
			Slim::Buttons::Common::pushModeLeft($client, $params->{'useMode'}, $params->{'parameters'});
		}else {
			Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.CustomBrowse.Choice', $params);
		}
	}else {
	        $client->bumpRight();
	}
}

sub musicMagicMixable {
	my $class = shift;
	my $item  = shift;

	if(Slim::Utils::Prefs::get('musicmagic')) {
		if(UNIVERSAL::can("Plugins::MusicMagic::Plugin","mixable")) {
			debugMsg("Calling Plugins::MusicMagic::Plugin->mixable\n");
			my $enabled = eval { Plugins::MusicMagic::Plugin->mixable($item) };
			if ($@) {
				debugMsg("Error calling Plugins::MusicMagic::Plugin->mixable: $@\n");
			}
			if($enabled) {
				return 1;
			}
		}
	}
}

sub musicMagicMix {
	my $client = shift;
	my $item = shift;
	my $addOnly = shift;
	my $web = shift;

	my $trackUrls = undef;
	if(ref($item) eq 'Slim::Schema::Album') {
		my $trackObj = $item->tracks->next;
		if($trackObj) {
			$trackUrls = eval { Plugins::MusicMagic::Plugin::getMix($client,$trackObj->path,'album') };
		}
	}elsif(ref($item) eq 'Slim::Schema::Track') {
		$trackUrls = eval { Plugins::MusicMagic::Plugin::getMix($client,$item->path,'track') };
	}elsif(ref($item) eq 'Slim::Schema::Contributor') {
		$trackUrls = eval { Plugins::MusicMagic::Plugin::getMix($client,$item->name,'artist') };
	}elsif(ref($item) eq 'Slim::Schema::Genre') {
		$trackUrls = eval { Plugins::MusicMagic::Plugin::getMix($client,$item->name,'genre') };
	}elsif(ref($item) eq 'Slim::Schema::Year') {
		$trackUrls = eval { Plugins::MusicMagic::Plugin::getMix($client,$item->id,'year') };
	}
	if ($@) {
		debugMsg("Error calling MusicMagic plugin: $@\n");
	}
	if($trackUrls && scalar(@$trackUrls)>0) {
		debugMsg("Got mix with ".scalar(@$trackUrls)." tracks\n");
		my %playItem = (
			'playtype' => 'all',
			'itemname' => $mixer->{'mixname'}
		);
		my @tracks = Slim::Schema->rs('Track')->search({ 'url' => $trackUrls });

		my @trackItems = ();
		for my $track (@tracks) {
			my %trackItem = (
				'itemid' => $track->id,
				'itemurl' => $track->url,
				'itemname' => $track->title,
				'itemtype' => 'track'
			);
			push @trackItems,\%trackItem;
		}
		getMenuHandler()->playAddItem($client,\@trackItems,\%playItem,$addOnly);
		if(!$web) {
			Slim::Buttons::Common::popModeRight($client);
		}
	}else {
		if(!$web) {
			my $line2 = $client->doubleString('PLUGIN_CUSTOMBROWSE_MIX_NOTRACKS');
			$client->showBriefly({
				'line'    => [ undef, $line2 ],
				'overlay' => [ undef, $client->symbols('notesymbol') ],
			});
		}
	}
}

sub uPNPCallback {
	my $device = shift;
	my $event = shift;

	if($event eq 'add') {
		debugMsg("Adding uPNP ".$device->getfriendlyname."\n");
		$uPNPCache{$device->getudn} = $device;
	}else {
		debugMsg("Removing uPNP ".$device->getfriendlyname."\n");
		$uPNPCache{$device->getudn} = undef;
	}
}

sub getAvailableuPNPDevices {
	my @result = ();
	for my $key (keys %uPNPCache) {
		my $device = $uPNPCache{$key};
		my %item = (
			'id' => $device->getudn,
			'name' => $device->getfriendlyname,
			'value' => $device->getudn
		);
		push @result,\%item;
	}
	return \@result;
}

sub isuPNPDeviceAvailable {
	my $client = shift;
	my $params = shift;
	if(defined($params->{'device'})) {
		if(defined($uPNPCache{$params->{'device'}})) {
			return 1;
		}
	}
	return 0;
}

sub initPlugin {
	my $class = shift;
	
	checkDefaults();
	Slim::Utils::UPnPMediaServer::registerCallback( \&uPNPCallback );
	my $soapLiteError = 0;
	eval "use SOAP::Lite";
	if ($@) {
		my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
		for my $plugindir (@pluginDirs) {
			next unless -d catdir($plugindir,"CustomBrowse","libs");
			push @INC,catdir($plugindir,"CustomBrowse","libs");
			last;
		}
		debugMsg("Using internal implementation of SOAP::Lite\n");
		eval "use SOAP::Lite";
		if ($@) {
			$soapLiteError = 1;
			msg("CustomBrowse: ERROR! Cant load internal implementation of SOAP::Lite, download/publish functionallity will not be available\n");
		}
	}

	my %choiceFunctions =  %{Slim::Buttons::Input::Choice::getFunctions()};
	$choiceFunctions{'create_mix'} = sub {Slim::Buttons::Input::Choice::callCallback('onCreateMix', @_)};
	$choiceFunctions{'saveRating'} = sub {
		my $client = shift;
		my $button = shift;
		my $digit = shift;
		my $listIndex = Slim::Buttons::Common::param($client,'listIndex');
		my $listRef = Slim::Buttons::Common::param($client,'listRef');
		my $item  = $listRef->[$listIndex];
		my $trackStat;
		$trackStat = Slim::Utils::PluginManager::enabledPlugin('TrackStat',$client);

		if($trackStat && defined($item->{'itemtype'}) && $item->{'itemtype'} eq 'track' && (Slim::Utils::Prefs::get("plugin_trackstat_rating_10scale") || $digit<=5)) {
			my $rating = $digit*20;
			if(Slim::Utils::Prefs::get("plugin_trackstat_rating_10scale")) {
				$rating = $digit*10;
			}
			$rating .= '%';
			my $request = $client->execute(['trackstat', 'setrating', sprintf('%d', $item->{'itemid'}),$rating]);
			$request->source('PLUGIN_CUSTOMBROWSE');
			$client->showBriefly(
				$client->string( 'PLUGIN_CUSTOMBROWSE_TRACKSTAT'),
				$client->string( 'PLUGIN_CUSTOMBROWSE_TRACKSTAT_RATING').(' *' x $digit),
				3);
		}
		
	};
	$choiceFunctions{'insert'} = sub {Slim::Buttons::Input::Choice::callCallback('onInsert', @_)};
	Slim::Buttons::Common::addMode('PLUGIN.CustomBrowse.Choice',\%choiceFunctions,\&Slim::Buttons::Input::Choice::setMode);
	for my $buttonPressMode (qw{repeat hold hold_release single double}) {
		if(!defined($choiceMapping{'play.' . $buttonPressMode})) {
			$choiceMapping{'play.' . $buttonPressMode} = 'dead';
		}
		if(!defined($choiceMapping{'add.' . $buttonPressMode})) {
			$choiceMapping{'add.' . $buttonPressMode} = 'dead';
		}
		if(!defined($choiceMapping{'search.' . $buttonPressMode})) {
			$choiceMapping{'search.' . $buttonPressMode} = 'passback';
		}
		if(!defined($choiceMapping{'stop.' . $buttonPressMode})) {
			$choiceMapping{'stop.' . $buttonPressMode} = 'passback';
		}
		if(!defined($choiceMapping{'pause.' . $buttonPressMode})) {
			$choiceMapping{'pause.' . $buttonPressMode} = 'passback';
		}
	}
        Slim::Hardware::IR::addModeDefaultMapping('PLUGIN.CustomBrowse.Choice',\%choiceMapping);

	Slim::Buttons::Common::addMode('PLUGIN.CustomBrowse', getFunctions(), \&setMode);

	my $templateDir = Slim::Utils::Prefs::get('plugin_custombrowse_template_directory');
	if(!defined($templateDir) || !-d $templateDir) {
		$supportDownloadError = 'You have to specify a template directory before you can download menus';
	}
	if(!defined($supportDownloadError) && $soapLiteError) {
		$supportDownloadError = "Could not use the internal web service implementation, please download and install SOAP::Lite manually";
	}


	eval {
		getConfigManager();
		getMenuHandler();
		readBrowseConfiguration();
	};
	if ($@) {
		errorMsg("Failed to load Custom Browse:\n$@\n");
	}
	my %submenu = (
		'useMode' => 'PLUGIN.CustomBrowse',
	);
	my $menuName = Slim::Utils::Prefs::get('plugin_custombrowse_menuname');
	if($menuName) {
		Slim::Utils::Strings::addStringPointer( uc 'PLUGIN_CUSTOMBROWSE', $menuName );
	}
	if(Slim::Utils::Prefs::get('plugin_custombrowse_menuinsidebrowse')) {
		Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC',string('PLUGIN_CUSTOMBROWSE'),\%submenu);
	}
	addPlayerMenus();
	delSlimserverPlayerMenus();
}

sub getMenuHandler {
	if(!defined($menuHandler)) {
		my %parameters = (
			'debugCallback' => \&debugMsg,
			'errorCallback' => \&errorMsg,
			'pluginId' => 'CustomBrowse',
			'pluginVersion' => $PLUGINVERSION,
			'menuTitle' => string('PLUGIN_CUSTOMBROWSE'),
			'menuMode' => 'PLUGIN.CustomBrowse.Choice',
			'displayTextCallback' => \&getDisplayText,
			'overlayCallback' => \&getOverlay,
			'requestSource' => 'PLUGIN_CUSTOMBROWSE'
		);
		$menuHandler = Plugins::CustomBrowse::MenuHandler::Main->new(\%parameters);
	}
	return $menuHandler;
}

sub getConfigManager {
	if(!defined($configManager)) {
		my %parameters = (
			'debugCallback' => \&debugMsg,
			'errorCallback' => \&errorMsg,
			'pluginId' => 'CustomBrowse',
			'pluginVersion' => $PLUGINVERSION,
			'supportDownloadError' => $supportDownloadError,
			'addSqlErrorCallback' => \&addSQLError
		);
		$configManager = Plugins::CustomBrowse::ConfigManager::Main->new(\%parameters);
	}
	return $configManager;
}
sub addPlayerMenus {
	my $client = shift;
	my $menus = getMenuHandler()->getMenuItems($client);
        for my $menu (@$menus) {
            my $name = getMenuHandler()->getItemText($client,$menu);
            if($menu->{'enabledbrowse'}) {
		my %submenubrowse = (
			'useMode' => 'PLUGIN.CustomBrowse',
			'selectedMenu' => $menu->{'id'},
			'mainBrowseMenu' => 1
		);
		my %submenuhome = (
			'useMode' => 'PLUGIN.CustomBrowse',
			'selectedMenu' => $menu->{'id'},
			'mainBrowseMenu' => 1
		);
		Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC',$name,\%submenubrowse);
		Slim::Buttons::Home::addMenuOption($name,\%submenuhome);
            }else {
                Slim::Buttons::Home::delSubMenu('BROWSE_MUSIC',$name);
		Slim::Buttons::Home::delMenuOption($name);
            }
        }
}

sub getFunctions {
	# Functions to allow mapping of mixes to keypresses
	return {
		'up' => sub  {
			my $client = shift;
			$client->bumpUp();
		},
		'down' => sub  {
			my $client = shift;
			$client->bumpDown();
		},
		'left' => sub  {
			my $client = shift;
			Slim::Buttons::Common::popModeRight($client);
		},
		'right' => sub  {
			my $client = shift;
			$client->bumpRight();
		}
	}
}

sub checkDefaults {

	my $prefVal = Slim::Utils::Prefs::get('plugin_custombrowse_showmessages');
	if (! defined $prefVal) {
		debugMsg("Defaulting plugin_custombrowse_showmessages to 0\n");
		Slim::Utils::Prefs::set('plugin_custombrowse_showmessages', 0);
	}

	$prefVal = Slim::Utils::Prefs::get('plugin_custombrowse_menuinsidebrowse');
	if (! defined $prefVal) {
		debugMsg("Defaulting plugin_custombrowse_menuinsidebrowse to 1\n");
		Slim::Utils::Prefs::set('plugin_custombrowse_menuinsidebrowse', 1);
	}
        $prefVal = Slim::Utils::Prefs::get('plugin_custombrowse_directory');
	if (! defined $prefVal) {
		my $dir=Slim::Utils::Prefs::get('playlistdir');
		debugMsg("Defaulting plugin_custombrowse_directory to:$dir\n");
		Slim::Utils::Prefs::set('plugin_custombrowse_directory', $dir);
	}
        $prefVal = Slim::Utils::Prefs::get('plugin_custombrowse_menuname');
	if (! defined $prefVal) {
		my $dir=Slim::Utils::Prefs::get('playlistdir');
		debugMsg("Defaulting plugin_custombrowse_menuname to:".string('PLUGIN_CUSTOMBROWSE')."\n");
		Slim::Utils::Prefs::set('plugin_custombrowse_menuname', string('PLUGIN_CUSTOMBROWSE'));
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_custombrowse_download_url');
	if (! defined $prefVal) {
		debugMsg("Defaulting plugin_custombrowse_download_url\n");
		Slim::Utils::Prefs::set('plugin_custombrowse_download_url', 'http://erland.homeip.net/datacollection/services/DataCollection');
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_custombrowse_properties');
	if (! $prefVal) {
		debugMsg("Defaulting plugin_custombrowse_properties\n");
		my @properties = ();
		push @properties, 'libraryDir='.Slim::Utils::Prefs::get('audiodir');
		push @properties, 'libraryAudioDirUrl='.Slim::Utils::Misc::fileURLFromPath(Slim::Utils::Prefs::get('audiodir'));
		push @properties, 'mixsize=20';
		Slim::Utils::Prefs::set('plugin_custombrowse_properties', \@properties);
	}else {
	        my @properties = Slim::Utils::Prefs::getArray('plugin_custombrowse_properties');
		my $mixsize = undef;
		for my $property (@properties) {
			if($property =~ /^mixsize=/) {
				$mixsize = 1;
			}
		}
		if(!$mixsize) {
			Slim::Utils::Prefs::push('plugin_custombrowse_properties', 'mixsize=20');
		}
	}
	my $slimserverMenus = getSlimserverMenus();
	for my $menu (@$slimserverMenus) {
		$prefVal = Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_'.$menu->{'id'}.'_enabled');
		if(! defined $prefVal) {
			Slim::Utils::Prefs::set('plugin_custombrowse_slimservermenu_'.$menu->{'id'}.'_enabled',1);
		}
	}
}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_custombrowse_directory','plugin_custombrowse_template_directory','plugin_custombrowse_menuname','plugin_custombrowse_menuinsidebrowse','plugin_custombrowse_properties','plugin_custombrowse_showmessages'],
	 GroupHead => string('PLUGIN_CUSTOMBROWSE_SETUP_GROUP'),
	 GroupDesc => string('PLUGIN_CUSTOMBROWSE_SETUP_GROUP_DESC'),
	 GroupLine => 1,
	 GroupSub  => 1,
	 Suppress_PrefSub  => 1,
	 Suppress_PrefLine => 1
	);
	my %setupPrefs =
	(
	plugin_custombrowse_showmessages => {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_CUSTOMBROWSE_SHOW_MESSAGES')
			,'changeIntro' => string('PLUGIN_CUSTOMBROWSE_SHOW_MESSAGES')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_custombrowse_showmessages"); }
		},
	plugin_custombrowse_menuinsidebrowse => {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_CUSTOMBROWSE_MENUINSIDEBROWSE')
			,'changeIntro' => string('PLUGIN_CUSTOMBROWSE_MENUINSIDEBROWSE')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_custombrowse_menuinsidebrowse"); }
		},		
	plugin_custombrowse_properties => {
			'validate' => \&validateProperty
			,'isArray' => 1
			,'arrayAddExtra' => 1
			,'arrayDeleteNull' => 1
			,'arrayDeleteValue' => ''
			,'arrayBasicValue' => ''
			,'inputTemplate' => 'setup_input_array_txt.html'
			,'changeAddlText' => string('PLUGIN_CUSTOMBROWSE_PROPERTIES')
			,'PrefSize' => 'large'
		},
	plugin_custombrowse_directory => {
			'validate' => \&Slim::Utils::Validate::isDir
			,'PrefChoose' => string('PLUGIN_CUSTOMBROWSE_DIRECTORY')
			,'changeIntro' => string('PLUGIN_CUSTOMBROWSE_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_custombrowse_directory"); }
		},
	plugin_custombrowse_template_directory => {
			'validate' => \&Slim::Utils::Validate::isDir
			,'PrefChoose' => string('PLUGIN_CUSTOMBROWSE_TEMPLATE_DIRECTORY')
			,'changeIntro' => string('PLUGIN_CUSTOMBROWSE_TEMPLATE_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_custombrowse_template_directory"); }
		},
	plugin_custombrowse_menuname => {
			'validate' => \&Slim::Utils::Validate::acceptAll
			,'PrefChoose' => string('PLUGIN_CUSTOMBROWSE_MENUNAME')
			,'changeIntro' => string('PLUGIN_CUSTOMBROWSE_MENUNAME')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_custombrowse_menuname"); }
		},
	);
	return (\%setupGroup,\%setupPrefs);
}

sub webPages {
	my %pages = (
                "custombrowse_list\.(?:htm|xml)"     => \&handleWebList,
                "webadminmethods_edititems\.(?:htm|xml)"     => \&handleWebEditMenus,
                "webadminmethods_edititem\.(?:htm|xml)"     => \&handleWebEditMenu,
                "webadminmethods_saveitem\.(?:htm|xml)"     => \&handleWebSaveMenu,
                "webadminmethods_savesimpleitem\.(?:htm|xml)"     => \&handleWebSaveSimpleMenu,
                "webadminmethods_savenewitem\.(?:htm|xml)"     => \&handleWebSaveNewMenu,
                "webadminmethods_savenewsimpleitem\.(?:htm|xml)"     => \&handleWebSaveNewSimpleMenu,
                "webadminmethods_removeitem\.(?:htm|xml)"     => \&handleWebRemoveMenu,
                "webadminmethods_newitemtypes\.(?:htm|xml)"     => \&handleWebNewMenuTypes,
                "webadminmethods_newitemparameters\.(?:htm|xml)"     => \&handleWebNewMenuParameters,
                "webadminmethods_newitem\.(?:htm|xml)"     => \&handleWebNewMenu,
		"webadminmethods_login\.(?:htm|xml)"      => \&handleWebLogin,
		"webadminmethods_downloadnewitems\.(?:htm|xml)"      => \&handleWebDownloadNewMenus,
		"webadminmethods_downloaditems\.(?:htm|xml)"      => \&handleWebDownloadMenus,
		"webadminmethods_downloaditem\.(?:htm|xml)"      => \&handleWebDownloadMenu,
		"webadminmethods_publishitemparameters\.(?:htm|xml)"      => \&handleWebPublishMenuParameters,
		"webadminmethods_publishitem\.(?:htm|xml)"      => \&handleWebPublishMenu,
		"webadminmethods_deleteitemtype\.(?:htm|xml)"      => \&handleWebDeleteMenuType,
                "custombrowse_mix\.(?:htm|xml)"     => \&handleWebMix,
                "custombrowse_executemix\.(?:htm|xml)"     => \&handleWebExecuteMix,
                "custombrowse_add\.(?:htm|xml)"     => \&handleWebAdd,
                "custombrowse_play\.(?:htm|xml)"     => \&handleWebPlay,
                "custombrowse_addall\.(?:htm|xml)"     => \&handleWebAddAll,
                "custombrowse_playall\.(?:htm|xml)"     => \&handleWebPlayAll,
		"custombrowse_selectmenus\.(?:htm|xml)" => \&handleWebSelectMenus,
		"custombrowse_saveselectmenus\.(?:htm|xml)" => \&handleWebSaveSelectMenus,
        );

        my $value = 'plugins/CustomBrowse/custombrowse_list.html';

        if (grep { /^CustomBrowse::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

                $value = undef;
        }
	if(defined($value)) {
		#readBrowseConfiguration();
		addWebMenus(undef,$value);
		my $menuName = Slim::Utils::Prefs::get('plugin_custombrowse_menuname');
		if($menuName) {
			Slim::Utils::Strings::addStringPointer( uc 'PLUGIN_CUSTOMBROWSE_CUSTOM_MENUNAME', $menuName );
		}
		if(Slim::Utils::Prefs::get('plugin_custombrowse_menuinsidebrowse')) {
		        Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_CUSTOMBROWSE' => $value });
		}
		delSlimserverWebMenus();
	}

	if(Slim::Utils::Prefs::get('plugin_custombrowse_menuinsidebrowse')) {
	        return (\%pages);
	}else {
		return (\%pages,$value);
	}
}

sub delSlimserverWebMenus {
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_artist_enabled')) {
		Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_ARTIST' => undef });
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_genre_enabled')) {
		Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_GENRE' => undef });
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_album_enabled')) {
		Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_ALBUM' => undef });
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_year_enabled')) {
		Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_YEAR' => undef });
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_newmusic_enabled')) {
		Slim::Web::Pages->addPageLinks("browse", {'BROWSE_NEW_MUSIC' => undef });
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_playlist_enabled')) {
		Slim::Web::Pages->addPageLinks("browse", {'SAVED_PLAYLISTS' => undef });
	}
}

sub delSlimserverPlayerMenus {
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_artist_enabled')) {
		Slim::Buttons::Home::delSubMenu("BROWSE_MUSIC", 'BROWSE_BY_ARTIST');
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_genre_enabled')) {
		Slim::Buttons::Home::delSubMenu("BROWSE_MUSIC", 'BROWSE_BY_GENRE');
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_album_enabled')) {
		Slim::Buttons::Home::delSubMenu("BROWSE_MUSIC", 'BROWSE_BY_ALBUM');
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_year_enabled')) {
		Slim::Buttons::Home::delSubMenu("BROWSE_MUSIC", 'BROWSE_BY_YEAR');
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_newmusic_enabled')) {
		Slim::Buttons::Home::delSubMenu("BROWSE_MUSIC", 'BROWSE_NEW_MUSIC');
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_playlist_enabled')) {
		Slim::Buttons::Home::delSubMenu("BROWSE_MUSIC", 'SAVED_PLAYLISTS');
	}
}

sub addWebMenus {
	my $client = shift;
	my $value = shift;
	my $menus = getMenuHandler()->getMenuItems($client);
        for my $menu (@$menus) {
            my $name = getMenuHandler()->getItemText($client,$menu);

            if ( !Slim::Utils::Strings::stringExists($name) ) {
               	Slim::Utils::Strings::addStringPointer( uc $name, $name );
            }
            if($menu->{'enabledbrowse'}) {
		if(defined($menu->{'menu'}) && ref($menu->{'menu'}) ne 'ARRAY' && getMenuHandler()->hasCustomUrl($client,$menu->{'menu'})) {
			
			my $url = getMenuHandler()->getCustomUrl($client,$menu->{'menu'});
			debugMsg("Adding menu: $name\n");
		        Slim::Web::Pages->addPageLinks("browse", { $name => $url });
		}else {
			debugMsg("Adding menu: $name\n");
		        Slim::Web::Pages->addPageLinks("browse", { $name => $value."?hierarchy=".escape($menu->{'id'} )."&mainBrowseMenu=1"});
		}
            }else {
		debugMsg("Removing menu: $name\n");
		Slim::Web::Pages->addPageLinks("browse", {$name => undef});
            }
        }
}
# Draws the plugin's web page
sub handleWebList {
        my ($client, $params) = @_;

	$sqlerrors = '';
	if(defined($params->{'refresh'})) {
		readBrowseConfiguration($client);
	}
	my $items = getMenuHandler()->getPageItemsForContext($client,$params);
	my $context = getMenuHandler()->getContext($client,$params);

	if($items->{'artwork'}) {
		$params->{'pluginCustomBrowseArtworkSupported'} = 1;
	}
	$params->{'pluginCustomBrowsePageInfo'} = $items->{'pageinfo'};
	$params->{'pluginCustomBrowseOptions'} = $items->{'options'};
	$params->{'pluginCustomBrowseItems'} = $items->{'items'};
	$params->{'pluginCustomBrowseContext'} = $context;
	$params->{'pluginCustomBrowseSelectedOption'} = $params->{'option'};
	if($params->{'mainBrowseMenu'}) {
		$params->{'pluginCustomBrowseMainBrowseMenu'} = 1;
	}

	if(defined($context) && scalar(@$context)>0) {
		$params->{'pluginCustomBrowseCurrentContext'} = $context->[scalar(@$context)-1];
	}
	if($sqlerrors && $sqlerrors ne '') {
		$params->{'pluginCustomBrowseError'} = $sqlerrors;
	}
	$params->{'pluginCustomBrowseVersion'} = $PLUGINVERSION;

        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_list.html', $params);
}


sub handleWebEditMenus {
        my ($client, $params) = @_;
	return getConfigManager()->webEditItems($client,$params);	
}

sub handleWebEditMenu {
        my ($client, $params) = @_;
	return getConfigManager()->webEditItem($client,$params);	
}

sub handleWebDeleteMenuType {
	my ($client, $params) = @_;
	return getConfigManager()->webDeleteItemType($client,$params);	
}

sub handleWebNewMenuTypes {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItemTypes($client,$params);	
}

sub handleWebNewMenuParameters {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItemParameters($client,$params);	
}

sub handleWebLogin {
	my ($client, $params) = @_;
	return getConfigManager()->webLogin($client,$params);	
}

sub handleWebPublishMenuParameters {
	my ($client, $params) = @_;
	return getConfigManager()->webPublishItemParameters($client,$params);	
}

sub handleWebPublishMenu {
	my ($client, $params) = @_;
	return getConfigManager()->webPublishItem($client,$params);	
}

sub handleWebDownloadMenus {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadItems($client,$params);	
}

sub handleWebDownloadNewMenus {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadNewItems($client,$params);	
}

sub handleWebDownloadMenu {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadItem($client,$params);	
}

sub handleWebNewMenu {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItem($client,$params);	
}

sub handleWebSaveSimpleMenu {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveSimpleItem($client,$params);	
}

sub handleWebRemoveMenu {
	my ($client, $params) = @_;
	return getConfigManager()->webRemoveItem($client,$params);	
}

sub handleWebSaveNewSimpleMenu {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveNewSimpleItem($client,$params);	
}

sub handleWebSaveNewMenu {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveNewItem($client,$params);	
}

sub handleWebSaveMenu {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveItem($client,$params);	
}



sub handleWebPlayAdd {
	my ($client, $params,$addOnly,$gotoparent) = @_;
	return unless $client;
	if(!defined($params->{'hierarchy'})) {
		readBrowseConfiguration($client);
	}
	my $items = getMenuHandler()->getPageItemsForContext($client,$params);
	if(defined($items->{'items'})) {
		my $playItems = $items->{'items'};
		foreach my $playItem (@$playItems) {
			debugMsg(($addOnly?"Adding ":"Playing ").$playItem->{'itemname'}."\n");
			getMenuHandler()->playAddItem($client,undef,$playItem,$addOnly,undef);
			$addOnly = 1;
		}
	}
	my $hierarchy = $params->{'hierarchy'};
	if(defined($hierarchy)) {
		my @hierarchyItems = (split /,/, $hierarchy);
		my $newHierarchy = '';
		my $i=0;
		my $noOfHierarchiesToUse = scalar(@hierarchyItems)-1;
		foreach my $hierarchyItem (@hierarchyItems) {
			if($i && $i<$noOfHierarchiesToUse) {
				$newHierarchy = $newHierarchy.',';
			}
			if($i<$noOfHierarchiesToUse) {
				$newHierarchy = $hierarchyItem;
			}
			$i=$i+1;
		}
		$params->{'hierarchy'} = $newHierarchy;
	}
	if(!$gotoparent) {
		$params->{'hierarchy'} = $hierarchy;
	}
	return handleWebList($client,$params);
}
sub handleWebPlay {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,0,1);
}

sub handleWebAdd {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,1,1);
}

sub handleWebPlayAll {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,0,0);
}

sub handleWebAddAll {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,1,0);
}

sub handleWebMix {
	my ($client, $params) = @_;
	return unless $client;
	if(!defined($params->{'hierarchy'})) {
		readBrowseConfiguration($client);
	}
	my $item = undef;
	my $nextitem = undef;
	my $contextItems = getMenuHandler()->getContext($client,$params);
	my @contexts = @$contextItems;

	my $currentcontext = undef;
	if(scalar(@contexts)>1) {
		my $context = @contexts[scalar(@contexts)-2];
		$item = $context->{'item'};
		$item->{'parameters'} = $context->{'parameters'};
	}
	if(scalar(@contexts)>0) {
		$currentcontext = @contexts[scalar(@contexts)-1];
		$nextitem = $currentcontext->{'item'};
		$nextitem->{'parameters'} = $currentcontext->{'parameters'};
	}
	my $items = getMenuHandler()->getMenuItems($client,$item);
	my $selecteditem = undef;
	for my $it (@$items) {
		if($it->{'itemid'} eq $params->{$nextitem->{'id'}}) {
			$selecteditem = $it;
		}
	}
	if(defined($selecteditem)) {
		my $mixes = getMenuHandler()->getWebMixes($client,$selecteditem);
		if(scalar(@$mixes)>1) {
			$params->{'pluginCustomBrowseMixes'} = $mixes;
			$params->{'pluginCustomBrowseItemUrl'} = $currentcontext->{'url'}.$currentcontext->{'valueUrl'};
			pop @$contextItems;
			$params->{'pluginCustomBrowseContext'} = $contextItems;
			return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_listmixes.html', $params);
		}elsif(scalar(@$mixes)>0) {
			if(!defined(@$mixes->[0]->{'url'})) {
				$params->{'mix'} = @$mixes->[0]->{'id'};
				return handleWebExecuteMix($client,$params);
			}else {
				$params->{'pluginCustomBrowseRedirect'} = @$mixes->[0]->{'url'};
				return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_redirect.html', $params);
			}
		}
	}
	
	#Go back to current page if no mixers could be found
	my $hierarchy = $params->{'hierarchy'};
	if(defined($hierarchy)) {
		my @hierarchyItems = (split /,/, $hierarchy);
		my $newHierarchy = '';
		my $i=0;
		my $noOfHierarchiesToUse = scalar(@hierarchyItems)-1;
		foreach my $hierarchyItem (@hierarchyItems) {
			if($i && $i<$noOfHierarchiesToUse) {
				$newHierarchy = $newHierarchy.',';
			}
			if($i<$noOfHierarchiesToUse) {
				$newHierarchy = $hierarchyItem;
			}
			$i=$i+1;
		}
		$params->{'hierarchy'} = $newHierarchy;
	}
	return handleWebList($client,$params);
}

sub handleWebExecuteMix {
	my ($client, $params) = @_;
	return unless $client;
	if(!defined($params->{'hierarchy'})) {
		readBrowseConfiguration($client);
	}
	my $item = undef;
	my $nextitem = undef;
	my $contextItems = getMenuHandler()->getContext($client,$params);
	my @contexts = @$contextItems;

	my $currentcontext = undef;
	if(scalar(@contexts)>1) {
		my $context = @contexts[scalar(@contexts)-2];
		$item = $context->{'item'};
		$item->{'parameters'} = $context->{'parameters'};
	}
	if(scalar(@contexts)>0) {
		$currentcontext = @contexts[scalar(@contexts)-1];
		$nextitem = $currentcontext->{'item'};
		$nextitem->{'parameters'} = $currentcontext->{'parameters'};
	}
	my $items = getMenuHandler()->getMenuItems($client,$item);
	my $selecteditem = undef;
	for my $it (@$items) {
		if($it->{'itemid'} eq $params->{$nextitem->{'id'}}) {
			$selecteditem = $it;
		}
	}
	if(defined($selecteditem)) {
		my $mixes = getMenuHandler()->getMixes($client,$selecteditem,1);
		for my $mix (@$mixes) {
			if($mix->{'id'} eq $params->{'mix'}) {
				getMenuHandler->executeMix($client,$mix,0,$selecteditem,1);
				last;
			}
		}
	}
	
	#Go back to current page if no mixers could be found
	my $hierarchy = $params->{'hierarchy'};
	if(defined($hierarchy)) {
		my @hierarchyItems = (split /,/, $hierarchy);
		my $newHierarchy = '';
		my $i=0;
		my $noOfHierarchiesToUse = scalar(@hierarchyItems)-1;
		foreach my $hierarchyItem (@hierarchyItems) {
			if($i && $i<$noOfHierarchiesToUse) {
				$newHierarchy = $newHierarchy.',';
			}
			if($i<$noOfHierarchiesToUse) {
				$newHierarchy = $hierarchyItem;
			}
			$i=$i+1;
		}
		$params->{'hierarchy'} = $newHierarchy;
	}
	return handleWebList($client,$params);
}

# Draws the plugin's select menus web page
sub handleWebSelectMenus {
        my ($client, $params) = @_;

	if(!defined($browseMenusFlat)) {
		readBrowseConfiguration($client);
	}
        # Pass on the current pref values and now playing info
	my @menus = ();
	for my $key (keys %$browseMenusFlat) {
		my %webmenu = ();
		my $menu = $browseMenusFlat->{$key};
		for my $key (keys %$menu) {
			$webmenu{$key} = $menu->{$key};
		} 
		if(defined($webmenu{'menuname'}) && defined($webmenu{'menugroup'})) {
			$webmenu{'menuname'} = $webmenu{'menugroup'}.'/'.$webmenu{'menuname'};
		}
		push @menus,\%webmenu;
	}
	@menus = sort { $a->{'menuname'} cmp $b->{'menuname'} } @menus;

        $params->{'pluginCustomBrowseMenus'} = \@menus;
        $params->{'pluginCustomBrowseMixes'} = getMenuHandler()->getGlobalMixes();

	$params->{'pluginCustomBrowseSlimserverMenus'} = getSlimserverMenus();

        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_selectmenus.html', $params);
}

sub getSlimserverMenus {
	my @slimserverMenus = ();
	my %browseByAlbum = (
		'id' => 'album',
		'name' => string('BROWSE_BY_ALBUM'),
		'enabled' => Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_album_enabled')
	);
	push @slimserverMenus,\%browseByAlbum;
	my %browseByArtist = (
		'id' => 'artist',
		'name' => string('BROWSE_BY_ARTIST'),
		'enabled' => Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_artist_enabled')
	);
	push @slimserverMenus,\%browseByArtist;
	my %browseByGenre = (
		'id' => 'genre',
		'name' => string('BROWSE_BY_GENRE'),
		'enabled' => Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_genre_enabled')
	);
	push @slimserverMenus,\%browseByGenre;
	my %browseByYear = (
		'id' => 'year',
		'name' => string('BROWSE_BY_YEAR'),
		'enabled' => Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_year_enabled')
	);
	push @slimserverMenus,\%browseByYear;
	my %browseNewMusic = (
		'id' => 'newmusic',
		'name' => string('BROWSE_NEW_MUSIC'),
		'enabled' => Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_newmusic_enabled')
	);
	push @slimserverMenus,\%browseNewMusic;
	my %browsePlaylist = (
		'id' => 'playlist',
		'name' => string('SAVED_PLAYLISTS').' (Player menu)',
		'enabled' => Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_playlist_enabled')
	);
	push @slimserverMenus,\%browsePlaylist;
	return \@slimserverMenus;
}

# Draws the plugin's web page
sub handleWebSaveSelectMenus {
        my ($client, $params) = @_;

	if(!defined($browseMenusFlat)) {
		readBrowseConfiguration($client);
	}
        foreach my $menu (keys %$browseMenusFlat) {
                my $menuid = "menu_".escape($browseMenusFlat->{$menu}->{'id'});
                my $menubrowseid = "menubrowse_".escape($browseMenusFlat->{$menu}->{'id'});
                if($params->{$menuid}) {
                        Slim::Utils::Prefs::set('plugin_custombrowse_'.$menuid.'_enabled',1);
			$browseMenusFlat->{$menu}->{'enabled'}=1;
			if(!defined($browseMenusFlat->{$menu}->{'forceenabledbrowse'})) {
				if($params->{$menubrowseid}) {
                	        	Slim::Utils::Prefs::set('plugin_custombrowse_'.$menubrowseid.'_enabled',1);
					$browseMenusFlat->{$menu}->{'enabledbrowse'}=1;
		                }else {
	        			Slim::Utils::Prefs::set('plugin_custombrowse_'.$menubrowseid.'_enabled',0);
					$browseMenusFlat->{$menu}->{'enabledbrowse'}=0;
	                	}
			}
                }else {
                        Slim::Utils::Prefs::set('plugin_custombrowse_'.$menuid.'_enabled',0);
			$browseMenusFlat->{$menu}->{'enabled'}=0;
			if(!defined($browseMenusFlat->{$menu}->{'forceenabledbrowse'})) {
				$browseMenusFlat->{$menu}->{'enabledbrowse'}=0;
			}
                }
        }
	my $browseMixes = getMenuHandler()->getGlobalMixes();
        foreach my $mix (keys %$browseMixes) {
                my $mixid = "mix_".escape($browseMixes->{$mix}->{'id'});
                if($params->{$mixid}) {
                        Slim::Utils::Prefs::set('plugin_custombrowse_'.$mixid.'_enabled',1);
			$browseMixes->{$mix}->{'enabled'}=1;
                }else {
                        Slim::Utils::Prefs::set('plugin_custombrowse_'.$mixid.'_enabled',0);
			$browseMixes->{$mix}->{'enabled'}=0;
                }
        }
	my $slimserverMenus = getSlimserverMenus();
        foreach my $menu (@$slimserverMenus) {
                my $menuid = "slimservermenu_".escape($menu->{'id'});
                if($params->{$menuid}) {
                        Slim::Utils::Prefs::set('plugin_custombrowse_'.$menuid.'_enabled',1);
                }else {
                        Slim::Utils::Prefs::set('plugin_custombrowse_'.$menuid.'_enabled',0);
                }
        }
	$params->{'refresh'} = 1;
        handleWebList($client, $params);
}

sub readBrowseConfiguration {
	my $client = shift;

	my $itemConfiguration = getConfigManager()->readItemConfiguration($client,undef,undef,1);
	my $localBrowseMenus = $itemConfiguration->{'menus'};
	$templates = $itemConfiguration->{'templates'};

	my @menus = ();
	getMenuHandler()->setMenuItems($localBrowseMenus);
	$browseMenusFlat = $localBrowseMenus;
	getMenuHandler()->setGlobalMixes($itemConfiguration->{'mixes'});
	
	my $value = 'plugins/CustomBrowse/custombrowse_list.html';
	if (grep { /^CustomBrowse::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {
		$value = undef;
	}
	addWebMenus($client,$value);
	delSlimserverWebMenus();
	delSlimserverPlayerMenus();
	addPlayerMenus($client);
}

sub getMultiLibraryMenus {
	my $client = shift;

	my $itemConfiguration = getConfigManager()->readItemConfiguration($client,1,'MultiLibrary::Plugin');
    	$templates = $itemConfiguration->{'templates'};
	my $localBrowseMenus = $itemConfiguration->{'menus'};
	foreach my $menu (keys %$localBrowseMenus) {
		getMenuHandler()->copyKeywords(undef,$localBrowseMenus->{$menu});
	}
    
	my @result = ();
	for my $menuKey (keys %$localBrowseMenus) {
		my $menu = $localBrowseMenus->{$menuKey};
		if(defined($menu->{'simple'})) {
			if($menu->{'librarysupported'}) {
				my $xml = getConfigManager()->webAdminMethods->loadTemplateValues($client,$menuKey,$localBrowseMenus->{$menuKey});
				my $templateId = $xml->{'id'};
				my $template = $templates->{$templateId};
				my $templateParameters = $template->{'parameter'};
				my $valueParameters = $xml->{'parameter'};
				for my $tp (@$templateParameters) {
					my $found = 0;
					for my $vp (@$valueParameters) {
						if($vp->{'id'} eq $tp->{'id'}) {
							$found = 1;
							last;
						}
					}
					if(!$found && ($tp->{'id'} eq 'library' || $tp->{'id'} eq 'menuname' || $tp->{'id'} eq 'menugroup' || $tp->{'id'} eq 'includedclients' || $tp->{'id'} eq 'excludedclients')) {
						my %newParameter = (
							'id' => $tp->{'id'},
							'quotevalue' => $tp->{'quotevalue'}
						);
						push @$valueParameters,\%newParameter;
					}
				}
				my $data = "";
				$data .= "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<custombrowse>\n\t<template>\n\t\t<id>".$templateId."</id>";
				my $menuname = undef;
				my $menugroup = undef;
				for my $p (@$valueParameters) {
					if($p->{'id'} eq 'menuname') {
						my $values = $p->{'value'};
						if(defined($values) && scalar(@$values)>0) {
							$menuname = $values->[0];
						}
					}elsif($p->{'id'} eq 'library') {
						my @values = ();
						push @values,'{libraryno}';
						$p->{'value'} = \@values;
					}elsif($p->{'id'} eq 'menugroup') {
						my $currentValues = $p->{'value'};
						if(defined($currentValues) && scalar(@$currentValues)>0) {
							$menugroup = $currentValues->[0];
						}
						my @values = ();
						push @values,'{libraryname}';
						$p->{'value'} = \@values;
					}elsif($p->{'id'} eq 'includedclients') {
						my @values = ();
						push @values,'{includedclients}';
						$p->{'value'} = \@values;
					}elsif($p->{'id'} eq 'excludedclients') {
						my @values = ();
						push @values,'{excludedclients}';
						$p->{'value'} = \@values;
					}
					my $values = $p->{'value'};
					my $value = '';
					if(defined($values)) {
						if(scalar(@$values)>0) {
							for my $v (@$values) {
								$value .= '<value>';
								$value .= $v;
								$value .= '</value>';
							}
						}
					}
					if($p->{'quotevalue'}) {
						$data .= "\n\t\t<parameter type=\"text\" id=\"".$p->{'id'}."\" quotevalue=\"1\">";
					}else {
						$data .= "\n\t\t<parameter type=\"text\" id=\"".$p->{'id'}."\">";
					}
					$data .= $value.'</parameter>';
				}
				$data .= "\n\t</template>\n</custombrowse>\n";
				if(defined($menuname)) {
					my %menu = (
						'id' => $menuKey,
						'name' => $menuname,
						'group' => $menugroup,
						'content' => $data
					);
					push @result,\%menu;
				}
			}
		}
	}
	return \@result;
}

sub validateProperty {
	my $arg = shift;
	if($arg eq '' || $arg =~ /^[a-zA-Z0-9_]+\s*=\s*.+$/) {
		return $arg;
	}else {
		return undef;
	}
}

sub validateIntOrEmpty {
	my $arg = shift;
	if(!$arg || $arg eq '' || $arg =~ /^\d+$/) {
		return $arg;
	}
	return undef;
}

sub commit {
	my $dbh = shift;
	if (!$dbh->{'AutoCommit'}) {
		$dbh->commit();
	}
}

sub rollback {
	my $dbh = shift;
	if (!$dbh->{'AutoCommit'}) {
		$dbh->rollback();
	}
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

# A wrapper to allow us to uniformly turn on & off debug messages
sub debugMsg
{
	my $message = join '','CustomBrowse: ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_custombrowse_showmessages"));
}

sub addSQLError {
	my $error = shift;
	$sqlerrors .= $error;
}
sub strings {
	return <<EOF;
PLUGIN_CUSTOMBROWSE
	EN	Custom Browse

PLUGIN_CUSTOMBROWSE_SETUP_GROUP
	EN	Custom Browse

PLUGIN_CUSTOMBROWSE_SETUP_GROUP_DESC
	EN	Custom Browse is a plugin which makes it possible to create your own menus

PLUGIN_CUSTOMBROWSE_SHOW_MESSAGES
	EN	Show debug messages

PLUGIN_CUSTOMBROWSE_MENUINSIDEBROWSE
	EN	Show Custom Browse menu inside Browse menu (requires slimserver restart)

PLUGIN_CUSTOMBROWSE_PROPERTIES
	EN	Properties to use in queries and menus

SETUP_PLUGIN_CUSTOMBROWSE_SHOWMESSAGES
	EN	Debugging

SETUP_PLUGIN_CUSTOMBROWSE_MENUINSIDEBROWSE
	EN	Menu position

SETUP_PLUGIN_CUSTOMBROWSE_PROPERTIES
	EN	Properties to use in queries and menus

PLUGIN_CUSTOMBROWSE_DIRECTORY
	EN	Browse configuration directory

PLUGIN_CUSTOMBROWSE_TEMPLATE_DIRECTORY
	EN	Browse templates directory

SETUP_PLUGIN_CUSTOMBROWSE_DIRECTORY
	EN	Browse configuration directory

SETUP_PLUGIN_CUSTOMBROWSE_TEMPLATE_DIRECTORY
	EN	Browse templates directory

PLUGIN_CUSTOMBROWSE_MENUNAME
	EN	Menu name

SETUP_PLUGIN_CUSTOMBROWSE_MENUNAME
	EN	Menu name (Slimserver 6.5 only, requires restart)

PLUGIN_CUSTOMBROWSE_SELECT_MENUS
	EN	Enable/Disable menus/mixers

PLUGIN_CUSTOMBROWSE_SELECT_MENUS_TITLE
	EN	Select enabled menus

PLUGIN_CUSTOMBROWSE_SELECT_MENUS_BROWSE_TITLE
	EN	Show in<br>browse and home menu

PLUGIN_CUSTOMBROWSE_SELECT_MENUS_NONE
	EN	No Menus

PLUGIN_CUSTOMBROWSE_SELECT_MENUS_ALL
	EN	All Menus

PLUGIN_CUSTOMBROWSE_SELECT_MIXES_TITLE
	EN	Select enabled mixers

PLUGIN_CUSTOMBROWSE_SELECT_MIXES_NONE
	EN	No Mixers

PLUGIN_CUSTOMBROWSE_SELECT_MIXES_ALL
	EN	All Mixers

PLUGIN_CUSTOMBROWSE_SELECT_SLIMSERVER_MENUS_TITLE
	EN	Select enabled slimserver menus (changes requires slimserver restart)

PLUGIN_CUSTOMBROWSE_NO_ITEMS_FOUND
	EN	No matching songs, albums or artists were found

PLUGIN_CUSTOMBROWSE_EDIT_MENUS
	EN	Edit menus

PLUGIN_CUSTOMBROWSE_EDIT_ITEM_FILENAME
	EN	Filename

PLUGIN_CUSTOMBROWSE_EDIT_ITEM_DATA
	EN	Menu configuration

PLUGIN_CUSTOMBROWSE_NEW_ITEM_TYPES_TITLE
	EN	Select type of menu to create

PLUGIN_CUSTOMBROWSE_NEW_ITEM
	EN	Create new menu

PLUGIN_CUSTOMBROWSE_NEW_ITEM_PARAMETERS_TITLE
	EN	Please enter menu parameters

PLUGIN_CUSTOMBROWSE_EDIT_ITEM_PARAMETERS_TITLE
	EN	Please enter menu parameters

PLUGIN_CUSTOMBROWSE_REMOVE_ITEM_QUESTION
	EN	Are you sure you want to delete this menu ?

PLUGIN_CUSTOMBROWSE_REMOVE_ITEM_TYPE_QUESTION
	EN	Removing a menu type might cause problems later if it is used in existing menus, are you really sure you want to delete this menu type ?

PLUGIN_CUSTOMBROWSE_REMOVE_ITEM
	EN	Delete

PLUGIN_CUSTOMBROWSE_MIX_NOTRACKS
	EN	Unable to create mix

PLUGIN_CUSTOMBROWSE_REFRESH
	EN	Refresh

PLUGIN_CUSTOMBROWSE_ITEMTYPE
	EN	Customize configuration

PLUGIN_CUSTOMBROWSE_ITEMTYPE_SIMPLE
	EN	Use predefined

PLUGIN_CUSTOMBROWSE_ITEMTYPE_ADVANCED
	EN	Customize

PLUGIN_CUSTOMBROWSE_TRACKSTAT
	EN	TrackStat

PLUGIN_CUSTOMBROWSE_TRACKSTAT_RATING
	EN	Rating:

PLUGIN_CUSTOMBROWSE_LOGIN_USER
	EN	Username

PLUGIN_CUSTOMBROWSE_LOGIN_PASSWORD
	EN	Password

PLUGIN_CUSTOMBROWSE_LOGIN_FIRSTNAME
	EN	First name

PLUGIN_CUSTOMBROWSE_LOGIN_LASTNAME
	EN	Last name

PLUGIN_CUSTOMBROWSE_LOGIN_EMAIL
	EN	e-mail

PLUGIN_CUSTOMBROWSE_ANONYMOUSLOGIN
	EN	Anonymous

PLUGIN_CUSTOMBROWSE_LOGIN
	EN	Login

PLUGIN_CUSTOMBROWSE_REGISTERLOGIN
	EN	Register &amp; Login

PLUGIN_CUSTOMBROWSE_REGISTER_TITLE
	EN	Register a new user

PLUGIN_CUSTOMBROWSE_LOGIN_TITLE
	EN	Login

PLUGIN_CUSTOMBROWSE_DOWNLOAD_ITEMS
	EN	Download more menus

PLUGIN_CUSTOMBROWSE_PUBLISH_ITEM
	EN	Publish

PLUGIN_CUSTOMBROWSE_PUBLISH
	EN	Publish

PLUGIN_CUSTOMBROWSE_PUBLISHPARAMETERS_TITLE
	EN	Please specify information about the menu

PLUGIN_CUSTOMBROWSE_PUBLISH_NAME
	EN	Name

PLUGIN_CUSTOMBROWSE_PUBLISH_DESCRIPTION
	EN	Description

PLUGIN_CUSTOMBROWSE_PUBLISH_ID
	EN	Unique identifier

PLUGIN_CUSTOMBROWSE_LASTCHANGED
	EN	Last changed

PLUGIN_CUSTOMBROWSE_PUBLISHMESSAGE
	EN	Thanks for choosing to publish your menu. The advantage of publishing a menu is that other users can use it and it will also be used for ideas of new functionallity in the Custom Browse plugin. Publishing a menu is also a great way of improving the functionality in the Custom Browse plugin by showing the developer what types of menus you use, besides those already included with the plugin.

PLUGIN_CUSTOMBROWSE_REGISTERMESSAGE
	EN	You can choose to publish your menu either anonymously or by registering a user and login. The advantage of registering is that other people will be able to see that you have published the menu, you will get credit for it and you will also be sure that no one else can update or change your published menu. The e-mail adress will only be used to contact you if I have some questions to you regarding one of your menus, it will not show up on any web pages. If you already have registered a user, just hit the Login button.

PLUGIN_CUSTOMBROWSE_LOGINMESSAGE
	EN	You can choose to publish your menu either anonymously or by registering a user and login. The advantage of registering is that other people will be able to see that you have published the menu, you will get credit for it and you will also be sure that no one else can update or change your published menu. Hit the &quot;Register &amp; Login&quot; button if you have not previously registered.

PLUGIN_CUSTOMBROWSE_PUBLISHMESSAGE_DESCRIPTION
	EN	It is important that you enter a good description of your menu, describe what your menu do and if it is based on one of the existing menus it is a good idea to mention this and describe which extensions you have made. <br><br>It is also a good idea to try to make the &quot;Unique identifier&quot; as uniqe as possible as this will be used for filename when downloading the menu. This is especially important if you have choosen to publish your menu anonymously as it can easily be overwritten if the identifier is not unique. Please try to not use spaces and language specific characters in the unique identifier since these could cause problems on some operating systems.

PLUGIN_CUSTOMBROWSE_REFRESH_DOWNLOADED_ITEMS
	EN	Download last version of existing menus

PLUGIN_CUSTOMBROWSE_DOWNLOAD_TEMPLATE_OVERWRITE_WARNING
	EN	A menu type with that name already exists, please change the name or select to overwrite the existing menu type

PLUGIN_CUSTOMBROWSE_DOWNLOAD_TEMPLATE_OVERWRITE
	EN	Overwrite existing

PLUGIN_CUSTOMBROWSE_PUBLISH_OVERWRITE
	EN	Overwrite existing

PLUGIN_CUSTOMBROWSE_DOWNLOAD_TEMPLATE_NAME
	EN	Unique identifier

PLUGIN_CUSTOMBROWSE_EDIT_ITEM_OVERWRITE
	EN	Overwrite existing

PLUGIN_CUSTOMBROWSE_SELECT_MIXES
	EN	Select mix to create

PLUGIN_CUSTOMBROWSE_DOWNLOAD_QUESTION
	EN	This operation will download latest version of all menus, this might take some time. Please note that this will overwrite any local changes you have made in built-in or previously downloaded menu types. Are you sure you want to continue ?
EOF

}

1;

__END__
