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

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;
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
use Text::Unidecode;
use SOAP::Lite;
use Slim::Utils::PluginManager;
use Slim::Control::Jive;
use POSIX qw(floor);

use Plugins::CustomBrowse::Settings;
use Plugins::CustomBrowse::EnabledMixers;
use Plugins::CustomBrowse::SqueezeCenterMenus;
use Plugins::CustomBrowse::EnabledMenus;
use Plugins::CustomBrowse::EnabledContextMenus;
use Plugins::CustomBrowse::ManageMenus;

use Plugins::CustomBrowse::ConfigManager::Main;
use Plugins::CustomBrowse::ConfigManager::ContextMain;

use Plugins::CustomBrowse::MenuHandler::Main;
use Plugins::CustomBrowse::MenuHandler::ParameterHandler;

use Plugins::CustomBrowse::iPeng::Reader;

my $manageMenuHandler = undef;

my $driver;
my $browseMenusFlat;
my $globalMixes;
my $contextBrowseMenusFlat;
my $templates;
my $mixer;
my $PLUGINVERSION = undef;
my $sqlerrors = '';
my %uPNPCache = ();
my $jiveMenu = undef;

my $configManager = undef;
my $contextConfigManager = undef;

my $menuHandler = undef;
my $contextMenuHandler = undef;

my $parameterHandler = undef;

my $DOWNLOAD_VERSION = 2;
my $prefs = preferences('plugin.custombrowse');
my $trackstatPrefs = preferences('plugin.trackstat');
my $serverPrefs = preferences('server');
my $musicmagicPrefs = preferences('plugin.musicmagic');
my $musicIPPrefs = preferences('plugin.musicip');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.custombrowse',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_CUSTOMBROWSE',
});

$prefs->migrate(1, sub {
	$prefs->set('menu_directory', Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_directory') || $serverPrefs->get('playlistdir')  );
	$prefs->set('template_directory',  Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_template_directory')   || ''  );
	$prefs->set('context_template_directory',  Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_context_template_directory')   || ''  );
	$prefs->set('download_url',  Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_download_url')   || 'http://erland.homeip.net/datacollection/services/DataCollection'  );
	$prefs->set('image_cache', Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_image_cache') || ''  );
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_menuinsidebrowse'))) {
		$prefs->set('menuinsidebrowse', Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_menuinsidebrowse'));
	}
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_override_trackinfo'))) {
		$prefs->set('override_trackinfo', Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_override_trackinfo'));
	}
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_enable_mixerfunction'))) {
		$prefs->set('enable_mixerfunction', Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_enable_mixerfunction'));
	}
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_enable_web_mixerfunction'))) {
		$prefs->set('enable_web_mixerfunction', Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_enable_web_mixerfunction'));
	}
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_showmixbeforeexecuting'))) {
		$prefs->set('showmixbeforeexecuting', Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_showmixbeforeexecuting'));
	}
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_header_value_separator'))) {
		$prefs->set('header_value_separator', Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_header_value_separator'));
	}
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_menuname'))) {
		$prefs->set('menuname', Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_menuname'));
	}
	$prefs->set('single_web_mixerbutton', Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_single_web_mixerbutton') || 0  );

	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_slimservermenu_album_enabled'))) {
		$prefs->set('slimservermenu_album_enabled', Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_slimservermenu_album_enabled'));
	}
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_slimservermenu_artist_enabled'))) {
		$prefs->set('slimservermenu_artist_enabled', Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_slimservermenu_artist_enabled'));
	}
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_slimservermenu_genre_enabled'))) {
		$prefs->set('slimservermenu_genre_enabled', Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_slimservermenu_genre_enabled'));
	}
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_slimservermenu_year_enabled'))) {
		$prefs->set('slimservermenu_year_enabled', Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_slimservermenu_year_enabled'));
	}
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_slimservermenu_newmusic_enabled'))) {
		$prefs->set('slimservermenu_newmusic_enabled', Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_slimservermenu_newmusic_enabled'));
	}
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_slimservermenu_playlist_enabled'))) {
		$prefs->set('slimservermenu_playlist_enabled', Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_slimservermenu_playlist_enabled'));
	}

	my $properties = Slim::Utils::Prefs::OldPrefs->get('plugin_custombrowse_properties');
	if(defined($properties)) {
		my %propertiesHash = ();
		for my $property (@$properties) {
			if($property =~ /^([^=]+)=(.*)$/) {
				$propertiesHash{$1}=$2;
			}
		}
		$prefs->set('properties', \%propertiesHash);
	}
	1;
});

$prefs->setValidate('dir', 'menu_directory');
$prefs->setValidate('dir', 'template_directory');
$prefs->setValidate('dir', 'context_template_directory');
$prefs->setValidate('dir', 'image_cache');
$prefs->setValidate('hash','properties');

sub getDisplayName {
	my $menuName = $prefs->get('menuname');
	if($menuName) {
		Slim::Utils::Strings::setString( uc 'PLUGIN_CUSTOMBROWSE', $menuName );
	}
	return 'PLUGIN_CUSTOMBROWSE';
}

my %choiceMapping = (
        'arrow_left' => 'exit_left',
        'arrow_right' => 'exit_right',
	'knob_push' => 'exit_right',
        'play' => 'dead',
	'play.single' => 'play_0',
	'play.hold' => 'createmix',
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
	my $class = shift;
	my $client = shift;
	my $method = shift;
	
	setModeBrowse($client, $method);
}

sub setModeBrowse {
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

sub setModeContext {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	my $track = $client->modeParam('track');
	my %contextHash = ();
	if(defined($track) && !blessed($track)) {
		$track = Slim::Schema->objectForUrl({'url' => $track});
	}
	if(!defined($track)) {
		$contextHash{'itemtype'} = $client->modeParam('itemtype');
		$contextHash{'itemname'} = $client->modeParam('itemname');
		$contextHash{'itemid'} = $client->modeParam('itemid');
	}else {
		$contextHash{'itemtype'} = 'track';
		$contextHash{'itemname'} = Slim::Music::Info::standardTitle(undef, $track);
		$contextHash{'itemid'} = $track->id;
	}
	if($client->modeParam('library')) {
		$contextHash{'library'} = $client->modeParam('library');
		$contextHash{'itemtype'} = 'library'.$contextHash{'itemtype'};
	}
	
	my $menus = getContextMenuHandler()->getMenuItems($client,undef,\%contextHash,'player');
	my $currentMenu = undef;
	for my $menu (@$menus) {
		if($menu->{'id'} eq 'group_'.$contextHash{'itemtype'}) {
			$currentMenu = $menu;
		}
	}
        my $params = undef;
	if(defined($currentMenu)) {
		$params = getContextMenuHandler()->getMenu($client,$currentMenu,\%contextHash);
	}
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

	if($musicmagicPrefs->get('musicmagic') || $musicIPPrefs->get('musicip')) {
		if(UNIVERSAL::can("Slim::Plugin::MusicMagic::Plugin","mixable")) {
			$log->debug("Calling Slim::Plugin::MusicMagic::Plugin->mixable\n");
			my $enabled = eval { Slim::Plugin::MusicMagic::Plugin->mixable($item) };
			if ($@) {
				$log->warn("Error calling Slim::Plugin::MusicMagic::Plugin->mixable: $@\n");
			}
			if($enabled) {
				return 1;
			}
		}
	}
}

sub biographyMixable {
	my $class = shift;
	my $item  = shift;

	if(UNIVERSAL::can("Plugins::Biography::Plugin","getArtistFromArtistId")) {
		return 1;
	}
	return undef;
}

sub albumreviewMixable {
	my $class = shift;
	my $item  = shift;

	if(UNIVERSAL::can("Plugins::AlbumReview::Plugin","getAlbumFromAlbumId")) {
		return 1;
	}
	return undef;
}

sub musicMagicMix {
	my $client = shift;
	my $item = shift;
	my $addOnly = shift;
	my $interfaceType = shift;

	my $trackUrls = undef;
	if(ref($item) eq 'Slim::Schema::Album') {
		my $trackObj = $item->tracks->next;
		if($trackObj) {
			$trackUrls = eval { Slim::Plugin::MusicMagic::Plugin::getMix($client,$trackObj->path,'album') };
		}
	}elsif(ref($item) eq 'Slim::Schema::Track') {
		$trackUrls = eval { Slim::Plugin::MusicMagic::Plugin::getMix($client,$item->path,'track') };
	}elsif(ref($item) eq 'Slim::Schema::Contributor') {
		$trackUrls = eval { Slim::Plugin::MusicMagic::Plugin::getMix($client,$item->name,'artist') };
	}elsif(ref($item) eq 'Slim::Schema::Genre') {
		$trackUrls = eval { Slim::Plugin::MusicMagic::Plugin::getMix($client,$item->name,'genre') };
	}elsif(ref($item) eq 'Slim::Schema::Year') {
		$trackUrls = eval { Slim::Plugin::MusicMagic::Plugin::getMix($client,$item->id,'year') };
	}
	if ($@) {
		$log->warn("Error calling MusicMagic plugin: $@\n");
	}
	if($trackUrls && scalar(@$trackUrls)>0) {
		$log->debug("Got mix with ".scalar(@$trackUrls)." tracks\n");
		my %playItem = (
			'playtype' => 'all',
			'itemname' => $mixer->{'mixname'}
		);
		my @tracks = Slim::Schema->rs('Track')->search({ 'url' => $trackUrls });

		my @trackItems = ();
		for my $url (@$trackUrls) {
			for my $track (@tracks) {
				if($track->url eq $url) {
					my %trackItem = (
						'itemid' => $track->id,
						'itemurl' => $track->url,
						'itemname' => $track->title,
						'itemtype' => 'track'
					);
					push @trackItems,\%trackItem;
					last;
				}
			}
		}
		getMenuHandler()->playAddItem($client,\@trackItems,\%playItem,$addOnly,0);
		if($interfaceType eq 'player') {
			Slim::Buttons::Common::popModeRight($client);
		}
	}else {
		if($interfaceType eq 'player') {
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
		$log->debug("Adding uPNP ".$device->getfriendlyname."\n");
		$uPNPCache{$device->getudn} = $device;
	}else {
		$log->debug("Removing uPNP ".$device->getfriendlyname."\n");
		$uPNPCache{$device->getudn} = undef;
	}
}
sub getAvailableTitleFormats {
	my @result = ();
	my $titleFormats = $serverPrefs->get('titleFormat');

	foreach my $format ( @$titleFormats ) {
		my %item = (
			'id' => $format,
			'name' => $format,
			'value' => $format
		);
		push @result,\%item;
	}
	return \@result;
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

sub browseByMixable {
	my $class = shift;
	my $item  = shift;
	return mixable($class,$item);
}

sub browseByMix {
	my $client = shift;
	my $item = shift;
	my $addOnly = shift;
	my $interfaceType = shift;

	my %p = ();
	if(ref($item) eq 'Slim::Schema::Album' || ref($item) eq 'Slim::Schema::Age') {
		$p{'itemid'} = $item->id;
		$p{'itemname'} = $item->title; 
		$p{'itemtype'} = 'album';
	}elsif(ref($item) eq 'Slim::Schema::Track') {
		$p{'itemid'} = $item->id;
		$p{'itemname'} = Slim::Music::Info::standardTitle(undef, $item),; 
		$p{'itemtype'} = 'track';
	}elsif(ref($item) eq 'Slim::Schema::Contributor') {
		$p{'itemid'} = $item->id;
		$p{'itemname'} = $item->name; 
		$p{'itemtype'} = 'artist';
	}elsif(ref($item) eq 'Slim::Schema::Genre') {
		$p{'itemid'} = $item->id;
		$p{'itemname'} = $item->name; 
		$p{'itemtype'} = 'genre';
	}elsif(ref($item) eq 'Slim::Schema::Year') {
		$p{'itemid'} = $item->id;
		if($item->id) {
			$p{'itemname'} = $item->id; 
		}else {
			$p{'itemname'} = string('UNK'); 
		}
		$p{'itemtype'} = 'year';
	}elsif(ref($item) eq 'Slim::Schema::Playlist') {
		$p{'itemid'} = $item->id;
		$p{'itemname'} = $item->title; 
		$p{'itemtype'} = 'playlist';
	}
	if($interfaceType ne 'player' || !defined($p{'itemid'})) {
		$client->bumpRight();
		return;
	}
	Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.CustomBrowse.Context',\%p);
	$client->update();
}
sub mixerlink {
	my $item = shift;
	my $form = shift;
	my $descend = shift;
	
	if(!$contextBrowseMenusFlat) {
		readContextBrowseConfiguration();
	}

	my $contextId = undef;
	my $contextName = undef;
	my $contextType = undef;
	if(ref($item) eq 'Slim::Schema::Album' || ref($item) eq 'Slim::Schema::Age') {
		$contextId = $item->id;
		$contextName = $item->title; 
		$contextType = 'album';
	}elsif(ref($item) eq 'Slim::Schema::Track') {
		$contextId = $item->id;
		$contextName = Slim::Music::Info::standardTitle(undef, $item),; 
		$contextType = 'track';
		$form->{'noitems'} = 1;
	}elsif(ref($item) eq 'Slim::Schema::Contributor' &&  Slim::Schema->variousArtistsObject->id ne $item->id) {
		$contextId = $item->id;
		$contextName = $item->name; 
		$contextType = 'artist';
	}elsif(ref($item) eq 'Slim::Schema::Genre') {
		$contextId = $item->id;
		$contextName = $item->name; 
		$contextType = 'genre';
	}elsif(ref($item) eq 'Slim::Schema::Year') {
		$contextId = $item->id;
		if($item->id) {
			$contextName = $item->id; 
		}else {
			$contextName = string('UNK'); 
		}
		$contextType = 'year';
	}elsif(ref($item) eq 'Slim::Schema::Playlist') {
		$contextId = $item->id;
		$contextName = $item->title; 
		$contextType = 'playlist';
	}

	if(defined($contextType) && defined($contextId)) {
		my $menus = getContextMenuHandler()->getMenuItems(undef,undef,undef,'web');
		my $currentMenu = undef;
		for my $menu (@$menus) {
			if($menu->{'id'} eq 'group_'.$contextType) {
				$currentMenu=$menu;
			}
		}
		if(defined($currentMenu)) {
			$form->{'mixercontexttype'} = $contextType;
			$form->{'mixercontextid'} = $contextId;
			$form->{'mixercontextname'} = $contextName;
			$form->{'mixerlinks'}{'CUSTOMBROWSE'} = "plugins/CustomBrowse/mixerlink.html";
		}
	}
	return $form;
}

sub mixerFunction {
	my ($client, $noSettings) = @_;
	# look for parentParams (needed when multiple mixers have been used)
	my $paramref = defined $client->modeParam('parentParams') ? $client->modeParam('parentParams') : $client->modeParameterStack(-1);
	if(defined($paramref)) {
		if(!$contextBrowseMenusFlat) {
			readContextBrowseConfiguration($client);
		}

		my $listIndex = $paramref->{'listIndex'};
		my $items     = $paramref->{'listRef'};
		my $currentItem = $items->[$listIndex];
		my $hierarchy = $paramref->{'hierarchy'};
		my @levels    = split(",", $hierarchy);
		my $level     = $paramref->{'level'} || 0;
		my $mixerType = $levels[$level];
		if($mixerType eq 'contributor'  &&  Slim::Schema->variousArtistsObject->id ne $currentItem->id) {
			$mixerType='artist';
		}
		if($mixerType eq 'age') {
			$mixerType='album';
		}
		my $menus = getContextMenuHandler()->getMenuItems(undef,undef,undef,'player');
		my $currentMenu = undef;
		for my $menu (@$menus) {
			if($menu->{'id'} eq 'group_'.$mixerType) {
				$currentMenu=$menu;
			}
		}
		if(defined($currentMenu)) { 
			if($mixerType eq 'track') {
				my $itemobj = Slim::Schema->resultset('Track')->find($currentItem->id);
				my %p = (
					'itemtype' => 'track',
					'itemname' => Slim::Music::Info::standardTitle(undef, $itemobj),
					'itemid' => $currentItem->id
				);
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.CustomBrowse.Context',\%p);
				$client->update();
			}elsif($mixerType eq 'album') {
				my $itemobj = Slim::Schema->resultset('Album')->find($currentItem->id);
				my %p = (
					'itemtype' => 'album',
					'itemname' => $itemobj->title,
					'itemid' => $currentItem->id
				);
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.CustomBrowse.Context',\%p);
				$client->update();
			}elsif($mixerType eq 'artist') {
				my $itemobj = Slim::Schema->resultset('Contributor')->find($currentItem->id);
				my %p = (
					'itemtype' => 'artist',
					'itemname' => $itemobj->name,
					'itemid' => $currentItem->id
				);
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.CustomBrowse.Context',\%p);
				$client->update();
			}elsif($mixerType eq 'genre') {
				my $itemobj = Slim::Schema->resultset('Genre')->find($currentItem->id);
				my %p = (
					'itemtype' => 'genre',
					'itemname' => $itemobj->name,
					'itemid' => $currentItem->id
				);
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.CustomBrowse.Context',\%p);
				$client->update();
			}elsif($mixerType eq 'playlist') {
				my $itemobj = Slim::Schema->resultset('Playlist')->find($currentItem->id);
				my %p = (
					'itemtype' => 'playlist',
					'itemname' => $itemobj->title,
					'itemid' => $currentItem->id
				);
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.CustomBrowse.Context',\%p);
				$client->update();
			}elsif($mixerType eq 'year') {
				my $itemobj = Slim::Schema->resultset('Year')->find($currentItem->id);
				my %p = (
					'itemtype' => 'year',
					'itemname' => $itemobj->id,
					'itemid' => $currentItem->id
				);
				if(!$itemobj->id) {
					$p{'itemname'} = string('UNK'); 
				}
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.CustomBrowse.Context',\%p);
				$client->update();
			}else {
				$log->warn("Unknown mixertype = ".$mixerType."\n");
			}
		}else {
			$log->warn("No context menu found for ".$mixerType."\n");
		}
	}else {
		$log->warn("No parent parameter found\n");
	}

}


sub mixable {
        my $class = shift;
        my $item  = shift;
	my $blessed = blessed($item);

	if(!$contextBrowseMenusFlat) {
		readContextBrowseConfiguration();
	}
	
	my $itemType = undef;
	if(!$blessed) {
		return undef;
	}elsif($blessed eq 'Slim::Schema::Track') {
		$itemType = 'track';
	}elsif($blessed eq 'Slim::Schema::Year') {
		$itemType = 'year';
	}elsif($blessed eq 'Slim::Schema::Album') {
		$itemType = 'album';
	}elsif($blessed eq 'Slim::Schema::Age') {
		$itemType = 'album';
	}elsif($blessed eq 'Slim::Schema::Contributor' &&  Slim::Schema->variousArtistsObject->id ne $item->id) {
		$itemType = 'artist';
	}elsif($blessed eq 'Slim::Schema::Genre') {
		$itemType = 'genre';
	}elsif($blessed eq 'Slim::Schema::Playlist') {
		$itemType = 'playlist';
	}else {
		return undef;
	}
	my $menus = getContextMenuHandler()->getMenuItems(undef,undef,undef,'player');
	for my $menu (@$menus) {
		if($menu->{'id'} eq 'group_'.$itemType) {
			return 1;
		}
	}
        return undef;
}

sub playLink {
	my $self = shift;
	my $client = shift;
	my $keywords = shift;
	my $context = shift;

	my @result = ();
	
	my $objectId = undef;
	if(defined($keywords->{'trackid'})) {
		$objectId='track.id='.$keywords->{'trackid'};
	}elsif(defined($keywords->{'albumid'})) {
		$objectId='album.id='.$keywords->{'albumid'};
	}elsif(defined($keywords->{'contributorid'})) {
		$objectId='contributor.id='.$keywords->{'contributorid'};
	}elsif(defined($keywords->{'genreid'})) {
		$objectId='genre.id='.$keywords->{'genreid'};
	}elsif(defined($keywords->{'playlistid'})) {
		$objectId='playlist.id='.$keywords->{'playlistid'};
	}elsif(defined($keywords->{'yearid'})) {
		$objectId='year.id='.$keywords->{'yearid'};
	}
	if(defined($objectId)) {
		$objectId = getParameterHandler()->replaceParameters($client,$objectId,$keywords,$context);

		my %item1 = (
			'id' => 1,
			'name' => string('PLAY').":status_header.html?command=playlist&subcommand=loadtracks&$objectId"
		);
		push @result,\%item1;
		my %item2 = (
			'id' => 2,
			'name' => string('ADD').":status_header.html?command=playlist&subcommand=addtracks&$objectId"
		);
		push @result,\%item2;
		my %item3 = (
			'id' => 3,
			'name' => string('NEXT').":status_header.html?command=playlist&subcommand=inserttracks&$objectId"
		);
		push @result,\%item3;
	}
	return \@result;
}

sub albumImages {
	my $self = shift;
	my $client = shift;
	my $keywords = shift;
	my $context = shift;

	my @result = ();
	
	my %excludedImages = ();
	if(defined($keywords->{'excludedimages'})) {
		for my $image (split(/\,/,$keywords->{'excludedimages'})) {
			$excludedImages{$image} = $image;
		}
	}
	my $albumId = $keywords->{'albumid'};
	$albumId = getParameterHandler()->replaceParameters($client,$albumId,$keywords,$context);
	my $album = Slim::Schema->resultset('Album')->find($albumId);
	my @tracks = $album->tracks;

	my %dirs = ();
	for my $track (@tracks) {
		my $path = Slim::Utils::Misc::pathFromFileURL($track->url);
		if($path) {
			$path =~ s/^(.*)\/(.*?)$/$1/;
			if(!$dirs{$path}) {
				$dirs{$path} = $path;
			}
		}
	}
	for my $dir (keys %dirs) {
		my @dircontents = Slim::Utils::Misc::readDirectory($dir,"jpg|gif|png");
		for my $item (@dircontents) {
			next if -d catdir($dir, $item);
			next unless lc($item) =~ /\.(jpg|gif|png)$/;
			next if defined($excludedImages{$item});
			my $extension = $1;
			if(defined($extension)) {
				my %item = (
					'id' => $item,
					'name' => "plugins/CustomBrowse/custombrowse_albumimage.$extension?album=".$album->id."&file=".$item
				);
				push @result,\%item;
			}
		}
	}
	
	return \@result;
}

sub albumFiles {
	my $self = shift;
	my $client = shift;
	my $keywords = shift;
	my $context = shift;

	my @result = ();
	
	my $albumId = $keywords->{'albumid'};
	$albumId = getParameterHandler()->replaceParameters($client,$albumId,$keywords,$context);
	my $album = Slim::Schema->resultset('Album')->find($albumId);
	my @tracks = $album->tracks;

	my %dirs = ();
	for my $track (@tracks) {
		my $path = Slim::Utils::Misc::pathFromFileURL($track->url);
		if($path) {
			$path =~ s/^(.*)\/(.*?)$/$1/;
			if(!$dirs{$path}) {
				$dirs{$path} = $path;
			}
		}
	}
	for my $dir (keys %dirs) {
		my @dircontents = Slim::Utils::Misc::readDirectory($dir,"txt|pdf|htm");
		for my $item (@dircontents) {
			next if -d catdir($dir, $item);
			next unless lc($item) =~ /\.(txt|pdf|htm)$/;
			my $extension = $1;
			if(defined($extension)) {
				my %item = (
					'id' => $item,
					'name' => "$item: plugins/CustomBrowse/custombrowse_albumfile.$extension?album=".$album->id."&file=".$item
				);
				push @result,\%item;
			}
		}
	}
	
	return \@result;
}
sub imageCacheFiles {
	my $self = shift;
	my $client = shift;
	my $keywords = shift;
	my $context = shift;

	my @result = ();

	my $type = $keywords->{'type'};
	if(defined($type) && $type ne '') {
		$type = getParameterHandler()->replaceParameters($client,$type,$keywords,$context);
	}
	my $section = $keywords->{'section'};
	if(defined($section) && $section ne '') {
		$section = getParameterHandler()->replaceParameters($client,$section,$keywords,$context);
		# We don't want to allow .. for security reason
		if($section =~ /\.\./) {
			$section = undef;
		}
	}
	my $name = undef;

	my $contextParameter = '';
	if($type eq 'artist') {
		my $artistId = $keywords->{'artist'};
		$artistId = getParameterHandler()->replaceParameters($client,$artistId,$keywords,$context);
		$contextParameter = "&artist=$artistId";
		my $artist = Slim::Schema->resultset('Contributor')->find($artistId);
		if(defined($artist)) {
			$name = $artist->name;
			$context->{'itemname'} = $name;
		}
	}elsif($type eq 'album') {
		my $albumId = $keywords->{'album'};
		$albumId = getParameterHandler()->replaceParameters($client,$albumId,$keywords,$context);
		$contextParameter = "&album=$albumId";
		my $album = Slim::Schema->resultset('Album')->find($albumId);
		if(defined($album)) {
			$name = $album->title;
			$context->{'itemname'} = $name;
		}
	}elsif($type eq 'year') {
		my $yearId = $keywords->{'year'};
		$yearId = getParameterHandler()->replaceParameters($client,$yearId,$keywords,$context);
		$contextParameter = "&year=$yearId";
		if(defined($yearId)) {
			if(!$yearId) {
				$yearId=string('UNK'); 
			}
			$name = $yearId;
			$context->{'itemname'} = $name;
		}
	}elsif($type eq 'playlist') {
		my $playlistId = $keywords->{'playlist'};
		$playlistId = getParameterHandler()->replaceParameters($client,$playlistId,$keywords,$context);
		$contextParameter = "&playlist=$playlistId";
		my $playlist = Slim::Schema->resultset('Playlist')->find($playlistId);
		if(defined($playlist)) {
			$name = $playlist->title;
			$context->{'itemname'} = $name;
		}
	}elsif($type eq 'genre') {
		my $genreId = $keywords->{'genre'};
		$genreId = getParameterHandler()->replaceParameters($client,$genreId,$keywords,$context);
		$contextParameter = "&genre=$genreId";
		my $genre = Slim::Schema->resultset('Genre')->find($genreId);
		if(defined($genre)) {
			$name = $genre->name;
			$context->{'itemname'} = $name;
		}
	}elsif($type eq 'custom') {
		my $name = $keywords->{'custom'};
		$name = getParameterHandler()->replaceParameters($client,$name,$keywords,$context);
		$contextParameter = "&custom=$name";
		# We don't want to allow .. for security reason
		if($name =~ /\.\./) {
			$name = undef;
		}else {
			$context->{'itemname'} = $name;
		}
	}

	my $linkurl = $keywords->{'linkurl'};
	if(defined($linkurl) && $linkurl ne '') {
		$linkurl = getParameterHandler()->replaceParameters($client,$linkurl,$keywords,$context);
	}
	my $linkurlascii = $keywords->{'linkurlascii'};
	if($linkurlascii && defined($linkurl) && $linkurl ne '') {
		$linkurl = unidecode($linkurl);
	}

	my $dir = $prefs->get('image_cache');

	if(defined($dir) && defined($name)) {
		my $extension = undef;
		my $file = $name;
		$name =~ s/[:\"]/ /g;
		if(defined($section) && $section ne '') {
			$file = catfile($section,$name);
		}
		if(-f catfile($dir,$file.".png")) {
			$extension = ".png";
		}elsif(-f catfile($dir,$file.".jpg")) {
			$extension = ".jpg";
		}elsif(-f catfile($dir,$file.".gif")) {
			$extension = ".gif";
		}
		if(defined($extension)) {
			my %item = (
				'id' => $name,
				'name' => ($linkurl?$linkurl.": ":"")."plugins/CustomBrowse/custombrowse_imagecachefile$extension?type=$type".(defined($section)?"&section=$section":"")."$contextParameter"
			);
			push @result,\%item;
		}
	}
	return \@result;
}


sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	Plugins::CustomBrowse::Settings->new($class);
	Plugins::CustomBrowse::EnabledMixers->new($class);
	Plugins::CustomBrowse::SqueezeCenterMenus->new($class);
	Plugins::CustomBrowse::EnabledMenus->new($class);
	Plugins::CustomBrowse::EnabledContextMenus->new($class);
	$manageMenuHandler = Plugins::CustomBrowse::ManageMenus->new($class);

	$driver = $serverPrefs->get('dbsource');
	$driver =~ s/dbi:(.*?):(.*)$/$1/;
    
	if(UNIVERSAL::can("Slim::Schema","sourceInformation")) {
		my ($source,$username,$password);
		($driver,$source,$username,$password) = Slim::Schema->sourceInformation;
	}

	my $dbh = Slim::Schema->storage->dbh();
	if($driver eq 'SQLite') {
		$dbh->func('from_unixtime', 1, sub {
			my ($seconds) = @_;
			return Slim::Utils::DateTime::shortDateF($seconds).' '.Slim::Utils::DateTime::timeF($seconds);
		    }, 'create_function');
		$dbh->func('time_format', 2, sub {
			my ($str,$format) = @_;
			return $str;
		    }, 'create_function');
		$dbh->func('date_format', 2, sub {
			my ($str,$format) = @_;
			return $str;
		    }, 'create_function');
		$dbh->func('repeat', 2, sub {
			my ($str,$repititions) = @_;
			return $str x $repititions;
		    }, 'create_function');
		$dbh->func('floor', 1, sub {
			my ($number) = @_;
			if(!defined($number)) {
				$number = 0;
			}
			$number = floor($number); 
			return $number;
		    }, 'create_function');
		$dbh->func('floor', 2, sub {
			my ($number,$decimals) = @_;
			if(!defined($number)) {
				$number = 0;
			}
			if($decimals>0) {
				$number =~s/(^\d{1,}\.\d{$decimals})(.*$)/$1/; 
			}else {
				$number =~s/(^\d{1,})(.*$)/$1/; 
			}
			return $number;
		    }, 'create_function');
		$dbh->func('concat', 2, sub {
			my ($str1, $str2) = @_;
			return $str1.$str2;
		    }, 'create_function');
		$dbh->func('concat', 3, sub {
			my ($str1, $str2, $str3) = @_;
			return $str1.$str2.$str3;
		    }, 'create_function');
		$dbh->func('concat', 4, sub {
			my ($str1, $str2, $str3,$str4) = @_;
			return $str1.$str2.$str3.$str4;
		    }, 'create_function');
		$dbh->func('sec_to_time', 1, sub {
			my ($sec) = @_;
			if($sec/(60)>=60) {
				return int($sec/(60*60)%24).":".(($sec/60)%60).":".($sec%60);
			}else {
				return int(($sec/60)).":".($sec%60);
			}
		    }, 'create_function');
	}

	checkDefaults();
	if(UNIVERSAL::can("Slim::Utils::UPnPMediaServer","registerCallback")) {
		Slim::Utils::UPnPMediaServer::registerCallback( \&uPNPCallback );
	}

	my %choiceFunctions =  %{Slim::Buttons::Input::Choice::getFunctions()};
	$choiceFunctions{'createmix'} = sub {callCallbackWithArg('onCreateMix', @_)};
	$choiceFunctions{'saveRating'} = sub {
		my $client = shift;
		my $button = shift;
		my $digit = shift;
		my $listIndex = Slim::Buttons::Common::param($client,'listIndex');
		my $listRef = Slim::Buttons::Common::param($client,'listRef');
		my $item  = $listRef->[$listIndex];
		my $trackStat;
		$trackStat = grep(/TrackStat/, Slim::Utils::PluginManager->enabledPlugins($client));

		if($trackStat && defined($item->{'itemtype'}) && $item->{'itemtype'} eq 'track' && ($trackstatPrefs->get("rating_10scale") || $digit<=5)) {
			my $rating = $digit*20;
			if($trackstatPrefs->get("rating_10scale")) {
				$rating = $digit*10;
			}
			$rating .= '%';
			my $request = $client->execute(['trackstat', 'setrating', sprintf('%d', $item->{'itemid'}),$rating]);
			$request->source('PLUGIN_CUSTOMBROWSE');
			$client->showBriefly({'line' => [$client->string( 'PLUGIN_CUSTOMBROWSE_TRACKSTAT'), 
							$client->string( 'PLUGIN_CUSTOMBROWSE_TRACKSTAT_RATING').(' *' x $digit)]},
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

	Slim::Buttons::Common::addMode('PLUGIN.CustomBrowse.Browse', getFunctions(), \&setModeBrowse);
	Slim::Buttons::Common::addMode('PLUGIN.CustomBrowse.Context', getFunctions(), \&setModeContext);
	if(UNIVERSAL::can("Slim::Buttons::TrackInfo","getFunctions")) {
		Slim::Buttons::Common::addMode('PLUGIN.CustomBrowse.trackinfo',Slim::Buttons::TrackInfo::getFunctions(),\&Slim::Buttons::TrackInfo::setMode);
	}else {
		Slim::Buttons::Common::addMode('PLUGIN.CustomBrowse.trackinfo',undef,\&Slim::Buttons::TrackInfo::setMode);
	}
	if($prefs->get('override_trackinfo')) {
		Slim::Buttons::Common::addMode('trackinfo',getFunctions(),\&setModeContext);
	}

	my %submenu = (
		'useMode' => 'PLUGIN.CustomBrowse.Browse',
	);
	my $menuName = $prefs->get('menuname');
	if($menuName) {
		Slim::Utils::Strings::setString( uc 'PLUGIN_CUSTOMBROWSE', $menuName );
	}
	if($prefs->get('menuinsidebrowse')) {
		Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC',string('PLUGIN_CUSTOMBROWSE'),\%submenu);
	}
	delSlimserverPlayerMenus();
	addPlayerMenus();

	my %mixerMap = ();
	if($prefs->get("enable_web_mixerfunction")) {
		$mixerMap{'mixerlink'} = \&mixerlink;
	}
	if($prefs->get("enable_mixerfunction")) {
		$mixerMap{'mixer'} = \&mixerFunction;
		$mixerMap{'cliBase'} = {
			player => 0,
			cmd => ['custombrowse','stdmixjive'],
			params => {},
			itemsParams => 'params',
		};
		$mixerMap{'contextToken'} = 'PLUGIN_CUSTOMBROWSE_CONTEXTMIXER';
	}
	if($prefs->get("enable_web_mixerfunction") ||
		$prefs->get("enable_mixerfunction")) {

		Slim::Music::Import->addImporter($class, \%mixerMap);
	    	Slim::Music::Import->useImporter('Plugins::CustomBrowse::Plugin', 1);
	}
	Slim::Control::Request::addDispatch(['custombrowse','browse'], [1, 1, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowse','browsecontext'], [1, 1, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowse','play'], [1, 0, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowse','playcontext'], [1, 0, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowse','add'], [1, 0, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowse','addcontext'], [1, 0, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowse','insert'], [1, 0, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowse','insertcontext'], [1, 0, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowse','mixes'], [1, 1, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowse','mixescontext'], [1, 1, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowse','mix'], [1, 0, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowse','mixcontext'], [1, 0, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowse','browsejive'], [1, 1, 1, \&cliJiveHandler]);
	Slim::Control::Request::addDispatch(['custombrowse','browsejivecontext'], [1, 1, 1, \&cliJiveHandler]);
	Slim::Control::Request::addDispatch(['custombrowse','mixesjive'], [1, 1, 1, \&cliJiveMixesHandler]);
	Slim::Control::Request::addDispatch(['custombrowse','mixesjivecontext'], [1, 1, 1, \&cliJiveMixesHandler]);
	Slim::Control::Request::addDispatch(['custombrowse','mixjive'], [1, 1, 1, \&cliJiveMixHandler]);
	Slim::Control::Request::addDispatch(['custombrowse','mixjivecontext'], [1, 1, 1, \&cliJiveMixHandler]);
	Slim::Control::Request::addDispatch(['custombrowse','stdmixjive'], [1, 1, 1, \&cliJiveStandardMixesHandler]);

	Plugins::CustomBrowse::iPeng::Reader::read("CustomBrowse","iPengConfiguration");
}

sub postinitPlugin {
	eval {
		getConfigManager();
		getMenuHandler();
		readBrowseConfiguration();
		readContextBrowseConfiguration();
		registerJiveMenu();
		registerContextMenus();
	};
	if ($@) {
		$log->error("Failed to load Custom Browse:\n$@\n");
	}
}

sub registerContextMenus {
	if(UNIVERSAL::can("Plugins::ContextMenu::Public","registerContextChoice")) {
		my $contextMenuApi = $Plugins::ContextMenu::Plugin::apiVersion;
		if ( defined($contextMenuApi) && ($contextMenuApi >= 0.65) ) {
			Plugins::ContextMenu::Public::registerContextChoice( { 
				uid => 'plugin.CustomBrowse.browsebyselected',
				coderef => sub  {
					my $parameters = shift;
					
					my $client = $parameters->{'client'};
					my $selectedItem = $parameters->{'selected'};

					if($selectedItem && (ref($selectedItem) eq 'Slim::Schema::Contributor' || 
						ref($selectedItem) eq 'Slim::Schema::Album' ||
						ref($selectedItem) eq 'Slim::Schema::Track' ||
						ref($selectedItem) eq 'Slim::Schema::Playlist' ||
						ref($selectedItem) eq 'Slim::Schema::Year' ||
						ref($selectedItem) eq 'Slim::Schema::Genre')) {
						return ({
							'label' => $client->string('PLUGIN_CUSTOMBROWSE_CONTEXTMIXER'),
							'coderef' => \&contextMenuBrowseBy,
							'execargs' => ({
								'item' => $selectedItem,
							}),
						});
					}else {
						return undef;
					}
				},
				displayname => string('PLUGIN_CUSTOMBROWSE_CONTEXTMIXER'),
				pluginname => string('PLUGIN_CUSTOMBROWSE'),
			} );
		}
	}
}

sub contextMenuBrowseBy {
	my $params = shift;
	my $client = $params->{'client'};
	my $item = $params->{'execargs'}->{'item'};

	my %p = ();
	if($item && ref($item) eq 'Slim::Schema::Contributor') {
		%p = (
			'itemtype' => 'artist',
			'itemname' => $item->name,
			'itemid' => $item->id
		);
	}elsif($item && ref($item) eq 'Slim::Schema::Album') {
		%p = (
			'itemtype' => 'album',
			'itemname' => $item->title,
			'itemid' => $item->id
		);
	}elsif($item && ref($item) eq 'Slim::Schema::Track') {
		%p = (
			'itemtype' => 'track',
			'itemname' => Slim::Music::Info::standardTitle(undef, $item),
			'itemid' => $item->id
		);
	}elsif($item && ref($item) eq 'Slim::Schema::Playlist') {
		%p = (
			'itemtype' => 'playlist',
			'itemname' => $item->title,
			'itemid' => $item->id
		);
	}elsif($item && ref($item) eq 'Slim::Schema::Genre') {
		%p = (
			'itemtype' => 'genre',
			'itemname' => $item->name,
			'itemid' => $item->id
		);
	}elsif($item && ref($item) eq 'Slim::Schema::Year') {
		%p = (
			'itemtype' => 'year',
			'itemname' => ($item->id?$item->id:$client->string('UNK')),
			'itemid' => $item->id
		);
	}

	Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.CustomBrowse.Context',\%p);
	$client->update();
}
sub registerJiveMenu {
	my $client = shift;
	my @menuItems = (
		{
			text => Slim::Utils::Strings::string(getDisplayName()),
			weight => 80,
			id => 'custombrowse',
			window => { titleStyle => 'mymusic'},
			actions => {
				go => {
					cmd => ['custombrowse', 'browsejive'],
				},
			},
		},
	);
	if($prefs->get('menuinsidebrowse')) {
		Slim::Control::Jive::registerPluginMenu(\@menuItems,'myMusic');
	}else {
		Slim::Control::Jive::registerPluginMenu(\@menuItems,'extras');
	}
}

sub callCallbackWithArg {
        my $callbackName = shift;
        my $client       = shift;
        my $funct        = shift;
        my $functarg     = shift;

        my $valueRef = $client->modeParam('valueRef');
        my $callback = Slim::Buttons::Input::Choice::getParam($client, $callbackName);
        if (ref($callback) eq 'CODE') {

                my @args = ($client, $valueRef ? ($$valueRef) : undef, $functarg);

                eval { $callback->(@args) };

                if ($@) {

                        logError("Couldn't run callback: [$callbackName] : $@");
                
                } elsif (Slim::Buttons::Input::Choice::getParam($client,'pref')) {
                
                        $client->update;
                }


        } else {

                Slim::Buttons::Input::Choice::passback($client, $funct, $functarg);
        }
}

sub title {
	return 'PLUGIN_CUSTOMBROWSE_CONTEXTMIXER';
}

sub getParameterHandler {
	if(!defined($parameterHandler)) {
		my %parameters = (
			'logHandler' => $log,
			'pluginId' => 'CustomBrowse',
			'pluginVersion' => $PLUGINVERSION
		);
		$parameterHandler = Plugins::CustomBrowse::MenuHandler::ParameterHandler->new(\%parameters);
	}
	return $parameterHandler;
}
sub getMenuHandler {
	if(!defined($menuHandler)) {
		my %parameters = (
			'logHandler' => $log,
			'pluginId' => 'CustomBrowse',
			'pluginVersion' => $PLUGINVERSION,
			'menuTitle' => string('PLUGIN_CUSTOMBROWSE'),
			'menuMode' => 'PLUGIN.CustomBrowse.Choice',
			'displayTextCallback' => \&getDisplayText,
			'overlayCallback' => \&getOverlay,
			'requestSource' => 'PLUGIN_CUSTOMBROWSE',
			'addSqlErrorCallback' => \&addSQLError,
			'showMixBeforeExecuting' => $prefs->get('showmixbeforeexecuting')
		);

		$menuHandler = Plugins::CustomBrowse::MenuHandler::Main->new(\%parameters);
	}
	return $menuHandler;
}

sub getContextMenuHandler {
	if(!defined($contextMenuHandler)) {
		my %parameters = (
			'logHandler' => $log,
			'pluginId' => 'CustomBrowse',
			'pluginVersion' => $PLUGINVERSION,
			'menuTitle' => string('PLUGIN_CUSTOMBROWSE_CONTEXTMENU'),
			'menuMode' => 'PLUGIN.CustomBrowse.Choice',
			'displayTextCallback' => \&getDisplayText,
			'overlayCallback' => \&getOverlay,
			'requestSource' => 'PLUGIN_CUSTOMBROWSE',
			'addSqlErrorCallback' => \&addSQLError,
			'showMixBeforeExecuting' => $prefs->get('showmixbeforeexecuting')
		);
		$contextMenuHandler = Plugins::CustomBrowse::MenuHandler::Main->new(\%parameters);
	}
	return $contextMenuHandler;
}

sub getConfigManager {
	if(!defined($configManager)) {
		my %parameters = (
			'logHandler' => $log,
			'pluginId' => 'CustomBrowse',
			'downloadApplicationId' => 'CustomBrowse',
			'pluginVersion' => $PLUGINVERSION,
			'addSqlErrorCallback' => \&addSQLError,
			'downloadVersion' => $DOWNLOAD_VERSION,
		);
		$configManager = Plugins::CustomBrowse::ConfigManager::Main->new(\%parameters);
	}
	return $configManager;
}

sub registerMixHandler {
	my $id = shift;
	my $mixer = shift;

	getMenuHandler()->registerMixHandler($id,$mixer);
	getContextMenuHandler()->registerMixHandler($id,$mixer);
}

sub unregisterMixHandler {
	my $self = shift;
	my $id = shift;

	getMenuHandler()->unregisterMixHandler($id,$mixer);
	getContextMenuHandler()->unregisterMixHandler($id,$mixer);
}

sub getContextConfigManager {
	if(!defined($contextConfigManager)) {
		my %parameters = (
			'logHandler' => $log,
			'pluginId' => 'CustomBrowse',
			'downloadApplicationId' => 'CustomBrowseContext',
			'pluginVersion' => $PLUGINVERSION,
			'addSqlErrorCallback' => \&addSQLError,
			'downloadVersion' => $DOWNLOAD_VERSION,
		);
		$contextConfigManager = Plugins::CustomBrowse::ConfigManager::ContextMain->new(\%parameters);
	}
	return $contextConfigManager;
}

sub addPlayerMenus {
	my $client = shift;
	my $menus = getMenuHandler()->getMenuItems($client,undef,undef,'web');
        for my $menu (@$menus) {
            my $name = getMenuHandler()->getItemText($client,$menu);
            my $key = getMenuKey($client,$menu,$name);

            if($menu->{'enabledbrowse'} || ($name ne $key && $prefs->get('replaceplayermenus'))) {
		my %submenubrowse = (
			'useMode' => 'PLUGIN.CustomBrowse.Browse',
			'selectedMenu' => $menu->{'id'},
			'mainBrowseMenu' => 1
		);
		my %submenuhome = (
			'useMode' => 'PLUGIN.CustomBrowse.Browse',
			'selectedMenu' => $menu->{'id'},
			'mainBrowseMenu' => 1
		);
		Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC',$key,\%submenubrowse);
		Slim::Buttons::Home::addMenuOption($key,\%submenuhome);
            }else {
                Slim::Buttons::Home::delSubMenu('BROWSE_MUSIC',$key);
		Slim::Buttons::Home::delMenuOption($key);
            }
        }
}

sub addJivePlayerMenus {
	my $client = shift;
	my $menus = getMenuHandler()->getMenuItems($client,undef,undef,'jive');
        for my $menu (@$menus) {
            my $name = getMenuHandler()->getItemText($client,$menu);
            my $key = getJiveMenuKey($client,$menu,$name);
            if($menu->{'enabledbrowse'} || ($name ne $key && $prefs->get('replacecontrollermenus'))) {
		my %itemParams = ();
		if(defined($menu->{'contextid'})) {
			$itemParams{'hierarchy'} = $menu->{'contextid'};
		}else {
			$itemParams{'hierarchy'} = $menu->{'id'};
		}

		my $itemtype = undef;
		if(defined($menu->{'menu'})) {
			my $menuRef = $menu->{'menu'};
			my @submenus = ();
			if(ref($menuRef) eq 'ARRAY') {
				@submenus = @$menuRef;
			}else {
				push @submenus,$menuRef;
			}
			my $ignore = 0;
			foreach my $nextmenu (@submenus) {
				if(defined($nextmenu->{'itemtype'})) {
					if(!defined($itemtype)) {
						$itemtype = $nextmenu->{'itemtype'};
					}elsif($itemtype ne $nextmenu->{'itemtype'}) {
						$itemtype = "NOTUSED";
					}
				}
				if(defined($nextmenu->{'menutype'}) && $nextmenu->{'menutype'} eq 'mode') {
					$ignore = 1;
					last;
				}
			}
			if($ignore) {
				next;
			}
		}

		my %menuStyle = ();
		$menuStyle{titleStyle} = 'mymusic';
		if(defined($itemtype) && $itemtype eq 'album') {
			$menuStyle{'menuStyle'} = 'album';
		}
		my @menuItems = (
			{
				text => $name,
				weight => defined($menu->{'menuorder'})?$menu->{'menuorder'}:80,
				id => $menu->{'id'},
				window => \%menuStyle,
				actions => {
					go => {
						cmd => ['custombrowse', 'browsejive'],
						params => \%itemParams,
						itemsParams => 'params',
					},
				},
			},
		);
		if($menu->{'id'} ne $key && $prefs->get('replacecontrollermenus')) {
			Slim::Control::Jive::deleteMenuItem($key,$client);
		}
		Slim::Control::Jive::registerPluginMenu(\@menuItems,'myMusic');
            }else {
		Slim::Control::Jive::deleteMenuItem($menu->{'id'});
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
		},
		'browse' => sub  {
			my $client = shift;
			my $button = shift;
			my $args = shift;
			
			getMenuHandler()->browseTo($client, $args);
		},
	}
}

sub checkDefaults {

	my $prefVal = $prefs->get('menuinsidebrowse');
	if (! defined $prefVal) {
		$log->debug("Defaulting plugin_custombrowse_menuinsidebrowse to 1\n");
		$prefs->set('menuinsidebrowse', 1);
	}
        $prefVal = $prefs->get('menu_directory');
	if (! defined $prefVal) {
		my $dir=$serverPrefs->get('playlistdir');
		$log->debug("Defaulting plugin_custombrowse_directory to:$dir\n");
		$prefs->set('menu_directory', $dir);
	}
        $prefVal = $prefs->get('menuname');
	if (! defined $prefVal) {
		my $dir=$serverPrefs->get('playlistdir');
		$log->debug("Defaulting plugin_custombrowse_menuname to:".string('PLUGIN_CUSTOMBROWSE')."\n");
		$prefs->set('menuname', string('PLUGIN_CUSTOMBROWSE'));
	}
	$prefVal = $prefs->get('download_url');
	if (! defined $prefVal) {
		$log->debug("Defaulting plugin_custombrowse_download_url\n");
		$prefs->set('download_url', 'http://erland.homeip.net/datacollection/services/DataCollection');
	}
	$prefVal = $prefs->get('override_trackinfo');
	if (! defined $prefVal) {
		$log->debug("Defaulting plugin_custombrowse_override_trackinfo to 1\n");
		$prefs->set('override_trackinfo', 1);
	}
	$prefVal = $prefs->get('enable_web_mixerfunction');
	if (! defined $prefVal) {
		$log->debug("Defaulting plugin_custombrowse_enable_web_mixerfunction to 1\n");
		$prefs->set('enable_web_mixerfunction', 1);
	}
	$prefVal = $prefs->get('enable_mixerfunction');
	if (! defined $prefVal) {
		$log->debug("Defaulting plugin_custombrowse_enable_mixerfunction to 1\n");
		$prefs->set('enable_mixerfunction', 1);
	}
	$prefVal = $prefs->get('single_web_mixerbutton');
	if (! defined $prefVal) {
		$log->debug("Defaulting plugin_custombrowse_single_web_mixerbutton to 0\n");
		$prefs->set('single_web_mixerbutton', 0);
	}
	$prefVal = $prefs->get('showmixbeforeexecuting');
	if (! defined $prefVal) {
		$log->debug("Defaulting plugin_custombrowse_showmixbeforeexecuting to 1\n");
		$prefs->set('showmixbeforeexecuting', 1);
	}
	$prefVal = $prefs->get('header_value_separator');
	if (! defined $prefVal) {
		$log->debug("Defaulting plugin_custombrowse_header_value_separator to ,\n");
		$prefs->set('header_value_separator', ', ');
	}
	$prefVal = $prefs->get('replaceplayermenus');
	if (! defined $prefVal) {
		$prefs->set('replaceplayermenus', 1);
	}
	$prefVal = $prefs->get('replacewebmenus');
	if (! defined $prefVal) {
		$prefs->set('replacewebmenus', 1);
	}
	$prefVal = $prefs->get('replacecontrollermenus');
	if (! defined $prefVal) {
		$prefs->set('replacecontrollermenus', 0);
	}


	$prefVal = $prefs->get('properties');
	if (! $prefVal) {
		$log->debug("Defaulting plugin_custombrowse_properties\n");
		my %properties = ();
		$properties{'libraryDir'}=$serverPrefs->get('audiodir');
		$properties{'libraryAudioDirUrl'}=Slim::Utils::Misc::fileURLFromPath($serverPrefs->get('audiodir'));
		$properties{'mixsize'}='20';
		$prefs->set('properties', \%properties);
	}else {
	        my $properties = $prefs->get('properties');
		my $mixsize = undef;
		if(!defined($properties->{'mixsize'})) {
			$properties->{'mixsize'}='20';
			$prefs->set('properties', $properties);
		}
	}
	my $slimserverMenus = getSlimserverMenus();
	for my $menu (@$slimserverMenus) {
		$prefVal = $prefs->get('slimservermenu_'.$menu->{'id'}.'_enabled');
		if(defined $prefVal && !$prefVal && !defined($prefs->get('squeezecenter_'.$menu->{'id'}.'_menu'))) {
			$prefs->set('squeezecenter_'.$menu->{'id'}.'_menu','disabled');
			$prefs->delete('slimservermenu_'.$menu->{'id'}.'_enabled');
		}
	}
	$prefVal = $prefs->get('squeezecenter_ipengbrowsemore_menu');
	if(!defined $prefVal) {
		$prefs->set('squeezecenter_ipengbrowsemore_menu','custombrowse');
	}
}

sub webPages {
	my $class = shift;
	my %pages = (
                "CustomBrowse/custombrowse_list\.(?:htm|xml)"     => \&handleWebList,
                "CustomBrowse/custombrowse_header\.(?:htm|xml)"     => \&handleWebHeader,
                "CustomBrowse/custombrowse_contextheader\.(?:htm|xml)"     => \&handleWebHeader,
                "CustomBrowse/custombrowse_contextlist\.(?:htm|xml)"     => \&handleWebContextList,
                "CustomBrowse/custombrowse_settings\.(?:htm|xml)"     => \&handleWebSettings,
                "CustomBrowse/custombrowse_albumimage\.(?:jpg|gif|png)"     => \&handleWebAlbumImage,
                "CustomBrowse/custombrowse_albumfile\.(?:txt|pdf|htm)"     => \&handleWebAlbumFile,
                "CustomBrowse/custombrowse_imagecachefile\.(?:jpg|gif|png)"     => \&handleWebImageCacheFile,
                #"CustomBrowse/webadminmethods_edititems\.(?:htm|xml)"     => \&handleWebEditMenus,
                "CustomBrowse/webadminmethods_edititem\.(?:htm|xml)"     => \&handleWebEditMenu,
                "CustomBrowse/webadminmethods_hideitem\.(?:htm|xml)"     => \&handleWebHideMenu,
                "CustomBrowse/webadminmethods_showitem\.(?:htm|xml)"     => \&handleWebShowMenu,
                "CustomBrowse/webadminmethods_saveitem\.(?:htm|xml)"     => \&handleWebSaveMenu,
                "CustomBrowse/webadminmethods_savesimpleitem\.(?:htm|xml)"     => \&handleWebSaveSimpleMenu,
                "CustomBrowse/webadminmethods_savenewitem\.(?:htm|xml)"     => \&handleWebSaveNewMenu,
                "CustomBrowse/webadminmethods_savenewsimpleitem\.(?:htm|xml)"     => \&handleWebSaveNewSimpleMenu,
                "CustomBrowse/webadminmethods_removeitem\.(?:htm|xml)"     => \&handleWebRemoveMenu,
                "CustomBrowse/webadminmethods_newitemtypes\.(?:htm|xml)"     => \&handleWebNewMenuTypes,
                "CustomBrowse/webadminmethods_newitemparameters\.(?:htm|xml)"     => \&handleWebNewMenuParameters,
                "CustomBrowse/webadminmethods_newitem\.(?:htm|xml)"     => \&handleWebNewMenu,
		"CustomBrowse/webadminmethods_login\.(?:htm|xml)"      => \&handleWebLogin,
		"CustomBrowse/webadminmethods_downloadnewitems\.(?:htm|xml)"      => \&handleWebDownloadNewMenus,
		"CustomBrowse/webadminmethods_downloaditems\.(?:htm|xml)"      => \&handleWebDownloadMenus,
		"CustomBrowse/webadminmethods_downloaditem\.(?:htm|xml)"      => \&handleWebDownloadMenu,
		"CustomBrowse/webadminmethods_publishitemparameters\.(?:htm|xml)"      => \&handleWebPublishMenuParameters,
		"CustomBrowse/webadminmethods_publishitem\.(?:htm|xml)"      => \&handleWebPublishMenu,
		"CustomBrowse/webadminmethods_deleteitemtype\.(?:htm|xml)"      => \&handleWebDeleteMenuType,
                "CustomBrowse/custombrowse_mix\.(?:htm|xml)"     => \&handleWebMix,
                "CustomBrowse/custombrowse_executemix\.(?:htm|xml)"     => \&handleWebExecuteMix,
                "CustomBrowse/custombrowse_mixcontext\.(?:htm|xml)"     => \&handleWebMixContext,
                "CustomBrowse/custombrowse_executemixcontext\.(?:htm|xml)"     => \&handleWebExecuteMixContext,
                "CustomBrowse/custombrowse_mixlist\.(?:htm|xml)"     => \&handleWebMixList,
                "CustomBrowse/custombrowse_add\.(?:htm|xml)"     => \&handleWebAdd,
                "CustomBrowse/custombrowse_play\.(?:htm|xml)"     => \&handleWebPlay,
                "CustomBrowse/custombrowse_insert\.(?:htm|xml)"     => \&handleWebInsert,
                "CustomBrowse/custombrowse_addall\.(?:htm|xml)"     => \&handleWebAddAll,
                "CustomBrowse/custombrowse_insertall\.(?:htm|xml)"     => \&handleWebInsertAll,
                "CustomBrowse/custombrowse_playall\.(?:htm|xml)"     => \&handleWebPlayAll,
                "CustomBrowse/custombrowse_contextadd\.(?:htm|xml)"     => \&handleWebContextAdd,
                "CustomBrowse/custombrowse_contextinsert\.(?:htm|xml)"     => \&handleWebContextInsert,
                "CustomBrowse/custombrowse_contextplay\.(?:htm|xml)"     => \&handleWebContextPlay,
                "CustomBrowse/custombrowse_contextaddall\.(?:htm|xml)"     => \&handleWebContextAddAll,
                "CustomBrowse/custombrowse_contextinsertall\.(?:htm|xml)"     => \&handleWebContextInsertAll,
                "CustomBrowse/custombrowse_contextplayall\.(?:htm|xml)"     => \&handleWebContextPlayAll,
        );

        my $value = 'plugins/CustomBrowse/custombrowse_list.html';


	for my $page (keys %pages) {
		if(UNIVERSAL::can("Slim::Web::Pages","addPageFunction")) {
			Slim::Web::Pages->addPageFunction($page, $pages{$page});
		}else {
			Slim::Web::HTTP::addPageFunction($page, $pages{$page});
		}
	}

	if(defined($value)) {
		#readBrowseConfiguration();
		delSlimserverWebMenus();
		addWebMenus(undef,$value);
		my $menuName = $prefs->get('menuname');
		if($menuName) {
			Slim::Utils::Strings::setString( uc 'PLUGIN_CUSTOMBROWSE_CUSTOM_MENUNAME', $menuName );
		}
		if($prefs->get('menuinsidebrowse')) {
		        Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_CUSTOMBROWSE' => $value });
		        Slim::Web::Pages->addPageLinks("browseiPeng", { 'PLUGIN_CUSTOMBROWSE' => $value });
			Slim::Web::Pages->addPageLinks("icons", {'PLUGIN_CUSTOMBROWSE' => 'plugins/CustomBrowse/html/images/custombrowse.png'});
		}
		if(!defined($prefs->get('squeezecenter_ipengbrowsemore_menu')) || $prefs->get('squeezecenter_ipengbrowsemore_menu') eq 'custombrowse') {
			Slim::Utils::Strings::setString( uc 'PLUGIN_IPENG_CUSTOM_BROWSE_MORE', $menuName );
			Slim::Web::Pages->addPageLinks("browseiPeng", { 'PLUGIN_IPENG_CUSTOM_BROWSE_MORE' => $value });
			Slim::Web::Pages->addPageLinks("icons", {'PLUGIN_IPENG_CUSTOM_BROWSE_MORE' => 'plugins/CustomBrowse/html/images/custombrowse.png'});
		}
	}


	if($prefs->get('menuinsidebrowse')) {
	        return (\%pages);
	}else {
		Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_CUSTOMBROWSE' => $value });
	        Slim::Web::Pages->addPageLinks("pluginsiPeng", { 'PLUGIN_CUSTOMBROWSE' => $value });
		Slim::Web::Pages->addPageLinks("icons", {'PLUGIN_CUSTOMBROWSE' => 'plugins/CustomBrowse/html/images/custombrowse.png'});
	}
}

sub delSlimserverWebMenus {
	if($prefs->get('replacewebmenus')) {
		if($prefs->get('squeezecenter_artist_menu') eq 'disabled') {
			Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_ARTIST' => undef });
		}
		if($prefs->get('squeezecenter_genre_menu') eq 'disabled') {
			Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_GENRE' => undef });
		}
		if($prefs->get('squeezecenter_album_menu') eq 'disabled') {
			Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_ALBUM' => undef });
		}
		if($prefs->get('squeezecenter_year_menu') eq 'disabled') {
			Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_YEAR' => undef });
		}
		if($prefs->get('squeezecenter_newmusic_menu') eq 'disabled') {
			Slim::Web::Pages->addPageLinks("browse", {'BROWSE_NEW_MUSIC' => undef });
		}
		if($prefs->get('squeezecenter_playlist_menu') eq 'disabled') {
			Slim::Web::Pages->addPageLinks("browse", {'SAVED_PLAYLISTS' => undef });
		}
	}
}

sub delSlimserverPlayerMenus {
	if($prefs->get('squeezecenter_artist_menu') eq 'disabled') {
		Slim::Buttons::Home::delSubMenu("BROWSE_MUSIC", 'BROWSE_BY_ARTIST');
	}
	if($prefs->get('squeezecenter_genre_menu') eq 'disabled') {
		Slim::Buttons::Home::delSubMenu("BROWSE_MUSIC", 'BROWSE_BY_GENRE');
	}
	if($prefs->get('squeezecenter_album_menu') eq 'disabled') {
		Slim::Buttons::Home::delSubMenu("BROWSE_MUSIC", 'BROWSE_BY_ALBUM');
	}
	if($prefs->get('squeezecenter_year_menu') eq 'disabled') {
		Slim::Buttons::Home::delSubMenu("BROWSE_MUSIC", 'BROWSE_BY_YEAR');
	}
	if($prefs->get('squeezecenter_newmusic_menu') eq 'disabled') {
		Slim::Buttons::Home::delSubMenu("BROWSE_MUSIC", 'BROWSE_NEW_MUSIC');
	}
	if($prefs->get('squeezecenter_playlist_menu') eq 'disabled') {
		Slim::Buttons::Home::delSubMenu("BROWSE_MUSIC", 'SAVED_PLAYLISTS');
	}
}

sub getMenuKey {
	my $client = shift;
	my $menu = shift;
	my $default = shift;

	foreach my $key (qw(album artist genre year)) {
		my $replaceMenu = $prefs->get('squeezecenter_'.$key.'_menu');
		if(defined($replaceMenu) && $replaceMenu eq $menu->{'id'}) {
			return 'BROWSE_BY_'.uc($key);
		}
	}
	my $replaceMenu = $prefs->get('squeezecenter_newmusic_menu');
	if(defined($replaceMenu) && $replaceMenu eq $menu->{'id'}) {
		return 'BROWSE_NEW_MUSIC';
	}

	$replaceMenu = $prefs->get('squeezecenter_playlist_menu');
	if(defined($replaceMenu) && $replaceMenu eq $menu->{'id'}) {
		return 'SAVED_PLAYLISTS';
	}

	$replaceMenu = $prefs->get('squeezecenter_ipengbrowsemore_menu');
	if(defined($replaceMenu) && $replaceMenu eq $menu->{'id'}) {
		return 'PLUGIN_IPENG_CUSTOM_BROWSE_MORE';
	}
	return $default;
}

sub getJiveMenuKey {
	my $client = shift;
	my $menu = shift;
	my $default = shift;

	my $replaceMenu = $prefs->get('squeezecenter_album_menu');
	if(defined($replaceMenu) && $replaceMenu eq $menu->{'id'}) {
		return 'myMusicAlbums';
	}

	my $replaceMenu = $prefs->get('squeezecenter_artist_menu');
	if(defined($replaceMenu) && $replaceMenu eq $menu->{'id'}) {
		return 'myMusicArtists';
	}

	my $replaceMenu = $prefs->get('squeezecenter_genre_menu');
	if(defined($replaceMenu) && $replaceMenu eq $menu->{'id'}) {
		return 'myMusicGenres';
	}

	my $replaceMenu = $prefs->get('squeezecenter_year_menu');
	if(defined($replaceMenu) && $replaceMenu eq $menu->{'id'}) {
		return 'myMusicYears';
	}

	my $replaceMenu = $prefs->get('squeezecenter_newmusic_menu');
	if(defined($replaceMenu) && $replaceMenu eq $menu->{'id'}) {
		return 'myMusicNewMusic';
	}

	$replaceMenu = $prefs->get('squeezecenter_playlist_menu');
	if(defined($replaceMenu) && $replaceMenu eq $menu->{'id'}) {
		return 'myMusicPlaylists';
	}

	return $default;
}

sub addWebMenus {
	my $client = shift;
	my $value = shift;
	my $menus = getMenuHandler()->getMenuItems($client,undef,undef,'web');
        for my $menu (@$menus) {
            my $name = getMenuHandler()->getItemText($client,$menu);
            my $key = getMenuKey($client,$menu,$name);

            if ( !Slim::Utils::Strings::stringExists($key) ) {
               	Slim::Utils::Strings::setString( uc $key, $name );
            }
            if($menu->{'enabledbrowse'} || $key ne $name) {
		if(defined($menu->{'menu'}) && ref($menu->{'menu'}) ne 'ARRAY' && getMenuHandler()->hasCustomUrl($client,$menu->{'menu'})) {
			
			my $url = getMenuHandler()->getCustomUrl($client,$menu->{'menu'});
			$log->debug("Adding menu: $key = $name\n");
		        Slim::Web::Pages->addPageLinks("browse", { $key => $url });
		        Slim::Web::Pages->addPageLinks("browseiPeng", { $key => $url });
			Slim::Web::Pages->addPageLinks("icons", {$key => 'plugins/CustomBrowse/html/images/custombrowse.png'});
		}else {
			$log->debug("Adding menu: $key = $name\n");
		        Slim::Web::Pages->addPageLinks("browse", { $key => $value."?hierarchy=".$menu->{'id'}."&mainBrowseMenu=1"});
		        Slim::Web::Pages->addPageLinks("browseiPeng", { $key => $value."?hierarchy=".$menu->{'id'}."&mainBrowseMenu=1"});
			Slim::Web::Pages->addPageLinks("icons", {$key => 'plugins/CustomBrowse/html/images/custombrowse.png'});
		}
            }else {
		$log->debug("Removing menu: $key\n");
		Slim::Web::Pages->addPageLinks("browse", {$key => undef});
		Slim::Web::Pages->addPageLinks("browseiPeng", {$key => undef});
            }
        }
}
# Draws the plugin's web page
sub handleWebList {
        my ($client, $params) = @_;

	$sqlerrors = '';
	if(defined($params->{'cleancache'}) && $params->{'cleancache'}) {
		my $cache = Slim::Utils::Cache->new("FileCache/CustomBrowse");
		$cache->clear();
	}
	if(defined($params->{'refresh'})) {
		readBrowseConfiguration($client);
		readContextBrowseConfiguration($client);
	}
	my $items = getMenuHandler()->getPageItemsForContext($client,$params,undef,0,'web');
	my $context = getMenuHandler()->getContext($client,$params,1);

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
	$params->{'pluginCustomBrowseValueSeparator'} = $prefs->get("header_value_separator");
	if(defined($params->{'pluginCustomBrowseValueSeparator'})) {
		$params->{'pluginCustomBrowseValueSeparator'} =~ s/\\\\/\\/;
		$params->{'pluginCustomBrowseValueSeparator'} =~ s/\\n/\n/;
	}

	$params->{'pluginCustomBrowsePlayAddAll'} = 1;
	if(defined($context) && scalar(@$context)>0) {
		$params->{'pluginCustomBrowseCurrentContext'} = $context->[scalar(@$context)-1];
		$params->{'pluginCustomBrowseMenu'} = $context->[0];
	}
	if(defined($items->{'playable'}) && !$items->{'playable'}) {
		$params->{'pluginCustomBrowsePlayAddAll'} = 0;
	}
	if(defined($params->{'pluginCustomBrowseCurrentContext'})) {
		$params->{'pluginCustomBrowseHeaderItems'} = getHeaderItems($client,$params,$params->{'pluginCustomBrowseCurrentContext'},undef,"header");
		$params->{'pluginCustomBrowseFooterItems'} = getHeaderItems($client,$params,$params->{'pluginCustomBrowseCurrentContext'},undef,"footer");
	}
	if($sqlerrors && $sqlerrors ne '') {
		$params->{'pluginCustomBrowseError'} = $sqlerrors;
	}
	$params->{'pluginCustomBrowseVersion'} = $PLUGINVERSION;
	if($prefs->get("single_web_mixerbutton")) {
		$params->{'pluginCustomBrowseSingleMixButton'}=1;
	}
	if (Slim::Music::Import->stillScanning || (UNIVERSAL::can("Plugins::CustomScan::Plugin","isScanning") && eval { Plugins::CustomScan::Plugin::isScanning() })) {
		$params->{'pluginCustomBrowseScanWarning'} = 1;
	}

        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_list.html', $params);
}


sub handleWebHeader {
        my ($client, $params) = @_;

	$sqlerrors = '';

	my $context = undef;
	my $contextParams = undef;
	if($params->{'path'} =~ /contextheader/) {
		if(defined($params->{'contexttype'})) {
			if(defined($params->{'hierarchy'})) {
				my $regExp = "^group_".$params->{'contexttype'}.".*";
				if($params->{'hierarchy'} !~ /$regExp/) {
					$params->{'hierarchy'} = 'group_'.$params->{'contexttype'}.','.$params->{'hierarchy'};
				}
			}else {
				$params->{'hierarchy'} = 'group_'.$params->{'contexttype'};
			}
		}
		if(defined($params->{'contextid'})) {
			my %c = (
				'itemid' => $params->{'contextid'},
				'itemtype' => $params->{'contexttype'},
				'itemname' => $params->{'contextname'}
			);
			my $contextString = '';
			if(defined($c{'itemid'})) {
				$contextString .= "&contextid=".$c{'itemid'};
			}
			if(defined($c{'itemtype'})) {
				$contextString .= "&contexttype=".$c{'itemtype'};
			}
			if(defined($c{'itemname'})) {
				$contextString .= "&contextname=".escape($c{'itemname'});
			}
			$c{'itemurl'} = $contextString;
			if($params->{'noitems'}) {
				$c{'noitems'} = '&noitems=1';
			}
			$contextParams = \%c;
		}
		$context = getContextMenuHandler()->getContext($client,$params,1);
		if(scalar(@$context)>0) {
			if(defined($contextParams->{'itemname'})) {
				$context->[0]->{'name'} = Slim::Utils::Unicode::utf8decode($contextParams->{'itemname'},'utf8');
			}else {
				$context->[0]->{'name'} = "Context";
			}
		}
	
		for my $ctx (@$context) {
			$ctx->{'valueUrl'} .= $contextParams->{'itemurl'};
		}
	}else {
		$context = getMenuHandler()->getContext($client,$params,1);
	}

	$params->{'pluginCustomBrowseContext'} = $context;
	$params->{'pluginCustomBrowseSelectedOption'} = $params->{'option'};
	if($params->{'mainBrowseMenu'}) {
		$params->{'pluginCustomBrowseMainBrowseMenu'} = 1;
	}
	$params->{'pluginCustomBrowseValueSeparator'} = $prefs->get("header_value_separator");
	if(defined($params->{'pluginCustomBrowseValueSeparator'})) {
		$params->{'pluginCustomBrowseValueSeparator'} =~ s/\\\\/\\/;
		$params->{'pluginCustomBrowseValueSeparator'} =~ s/\\n/\n/;
	}

	if(defined($context) && scalar(@$context)>0) {
		$params->{'pluginCustomBrowseCurrentContext'} = $context->[scalar(@$context)-1];
	}
	if(defined($params->{'pluginCustomBrowseCurrentContext'})) {
		$params->{'pluginCustomBrowseHeaderItems'} = getHeaderItems($client,$params,$params->{'pluginCustomBrowseCurrentContext'},$contextParams,"header");
	}
	if($sqlerrors && $sqlerrors ne '') {
		$params->{'pluginCustomBrowseError'} = $sqlerrors;
	}
	$params->{'pluginCustomBrowseVersion'} = $PLUGINVERSION;
	if($prefs->get("single_web_mixerbutton")) {
		$params->{'pluginCustomBrowseSingleMixButton'}=1;
	}
	if (Slim::Music::Import->stillScanning || (UNIVERSAL::can("Plugins::CustomScan::Plugin","isScanning") && eval { Plugins::CustomScan::Plugin::isScanning() })) {
		$params->{'pluginCustomBrowseScanWarning'} = 1;
	}
	
	if(defined($params->{'customtemplate'}) && $params->{'customtemplate'} && $params->{'customtemplate'} !~ /\.\./ && $params->{'customtemplate'} !~ /\//) {
	        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/'.$params->{'customtemplate'}, $params);
	}else {
	        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_header.html', $params);
	}
}

sub getHeaderItems {
	my $client = shift;
	my $params = shift;
	my $currentContext = shift;
	my $context = shift;
	my $headerType = shift;

	my $result = undef;
	if(defined($currentContext)) {
		my $header = undef;
		my $useContext = 0;
		if(defined($currentContext->{'item'}->{'menuweb'.$headerType})) {
			$header = $currentContext->{'item'}->{'menuweb'.$headerType};
		} 
		if(!defined($header) && defined($currentContext->{'item'}->{'itemtype'}) && $currentContext->{'item'}->{'itemtype'} ne 'sql') {
			$header = $currentContext->{'item'}->{'itemtype'}.$headerType;
		}
		if(!defined($header) && defined($currentContext->{'type'})) {
			$header = $currentContext->{'type'}.$headerType;
		}
		if(!defined($header) && defined($context) && defined($context->{'itemtype'})) {
			$header = $context->{'itemtype'}.$headerType;
			$useContext = 1;
		}
		if(defined($header)) {
			my %c = (
				'itemid' => $currentContext->{'value'},
				'itemtype' => $header,
				'itemname' => $currentContext->{'name'}
			);
			if($useContext) {
				$c{'itemid'}=$context->{'itemid'};
				$c{'itemname'}=$context->{'itemname'};
			}
			my $contextString = '';
			$c{'itemurl'} = $contextString;
			$c{'hierarchy'} = '&hierarchy=';
			$params->{'hierarchy'} = 'group_'.$c{'itemtype'};
			$params->{'itemsperpage'}=100;
			delete $params->{'mainBrowseMenu'};
			my $headerResult = getContextMenuHandler()->getPageItemsForContext($client,$params,\%c,1,'web');
			my $headerItems = $headerResult->{'items'};
			if(defined($headerItems) && scalar(@$headerItems)>0) {
				$result = structureContextItems($headerItems);
			}
		}
	}
	return $result;
}
sub handleWebContextList {
        my ($client, $params) = @_;
	$sqlerrors = '';
	if(defined($params->{'refresh'})) {
		readBrowseConfiguration($client);
		readContextBrowseConfiguration($client);
	}
	if(defined($params->{'contexttype'})) {
		if(defined($params->{'hierarchy'})) {
			my $regExp = "^group_".$params->{'contexttype'}.".*";
			if($params->{'hierarchy'} !~ /$regExp/) {
				$params->{'hierarchy'} = 'group_'.$params->{'contexttype'}.','.$params->{'hierarchy'};
			}
		}else {
			$params->{'hierarchy'} = 'group_'.$params->{'contexttype'};
		}
	}
	my $contextParams = undef;
	if(defined($params->{'contextid'})) {
		my %c = (
			'itemid' => $params->{'contextid'},
			'itemtype' => $params->{'contexttype'},
			'itemname' => $params->{'contextname'}
		);
		my $contextString = '';
		if(defined($c{'itemid'})) {
			$contextString .= "&contextid=".$c{'itemid'};
		}
		if(defined($c{'itemtype'})) {
			$contextString .= "&contexttype=".$c{'itemtype'};
		}
		if(defined($c{'itemname'})) {
			$contextString .= "&contextname=".escape($c{'itemname'});
		}
		$c{'itemurl'} = $contextString;
		if($params->{'noitems'}) {
			$c{'noitems'} = '&noitems=1';
		}
		$contextParams = \%c;
	}
	my $items = getContextMenuHandler()->getPageItemsForContext($client,$params,$contextParams,0,'web');
	my $context = getContextMenuHandler()->getContext($client,$params,1);
	if(scalar(@$context)>0) {
		if(defined($contextParams->{'itemname'})) {
			$context->[0]->{'name'} = Slim::Utils::Unicode::utf8decode($contextParams->{'itemname'},'utf8');
		}else {
			$context->[0]->{'name'} = "Context";
		}
	}

	for my $ctx (@$context) {
		$ctx->{'valueUrl'} .= $contextParams->{'itemurl'};
	}
	if($items->{'artwork'}) {
		$params->{'pluginCustomBrowseArtworkSupported'} = 1;
	}
	$params->{'pluginCustomBrowsePageInfo'} = $items->{'pageinfo'};
	$params->{'pluginCustomBrowseOptions'} = $items->{'options'};

	# Make sure we only show play/add all if the items are of same type 
	my $playAllItems = $items->{'items'};
	my $prevItem = undef;
	for my $it (@$playAllItems) {
		if(defined($prevItem) && (!defined($prevItem->{'itemtype'}) || !defined($it->{'itemtype'}) || $prevItem->{'itemtype'} ne $it->{'itemtype'})) {
			$prevItem=undef;
			last;
		}else {
			$prevItem=$it;
		}
	}
	if(defined($prevItem)) {
		$params->{'pluginCustomBrowsePlayAddAll'} = 1;
	}

	if($params->{'path'} =~ /contextlist/) {
		if(defined($params->{'noitems'})) {
			$params->{'pluginCustomBrowseNoItems'}=1;
		}else {
			$params->{'pluginCustomBrowseItems'} = $items->{'items'};
		}
	}else {
		$params->{'pluginCustomBrowseItems'} = structureContextItems($items->{'items'});
	}
	$params->{'pluginCustomBrowseContext'} = $context;
	$params->{'pluginCustomBrowseSelectedOption'} = $params->{'option'};
	if($params->{'mainBrowseMenu'}) {
		$params->{'pluginCustomBrowseMainBrowseMenu'} = 1;
	}
	$params->{'pluginCustomBrowseValueSeparator'} = $prefs->get("header_value_separator");
	if(defined($params->{'pluginCustomBrowseValueSeparator'})) {
		$params->{'pluginCustomBrowseValueSeparator'} =~ s/\\\\/\\/;
		$params->{'pluginCustomBrowseValueSeparator'} =~ s/\\n/\n/;
	}

	if(defined($context) && scalar(@$context)>0) {
		$params->{'pluginCustomBrowseCurrentContext'} = $context->[scalar(@$context)-1];
	}
	if(defined($items->{'playable'}) && !$items->{'playable'}) {
		$params->{'pluginCustomBrowsePlayAddAll'} = 0;
	}
	
	if(defined($params->{'pluginCustomBrowseCurrentContext'})) {
		$params->{'pluginCustomBrowseHeaderItems'} = getHeaderItems($client,$params,$params->{'pluginCustomBrowseCurrentContext'},$contextParams,"header");
		$params->{'pluginCustomBrowseFooterItems'} = getHeaderItems($client,$params,$params->{'pluginCustomBrowseCurrentContext'},$contextParams,"footer");
	}
	if($sqlerrors && $sqlerrors ne '') {
		$params->{'pluginCustomBrowseError'} = $sqlerrors;
	}
	$params->{'pluginCustomBrowseVersion'} = $PLUGINVERSION;
	if($prefs->get("single_web_mixerbutton")) {
		$params->{'pluginCustomBrowseSingleMixButton'}=1;
	}
	if (Slim::Music::Import->stillScanning || (UNIVERSAL::can("Plugins::CustomScan::Plugin","isScanning") && eval { Plugins::CustomScan::Plugin::isScanning() })) {
		$params->{'pluginCustomBrowseScanWarning'} = 1;
	}

        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_contextlist.html', $params);
}

sub handleWebAlbumImage {
	my ($client, $params, $callback, $httpClient,$response) = @_;

	my $albumId = $params->{'album'};
	my $album = Slim::Schema->resultset('Album')->find($albumId);
	my @tracks = $album->tracks;

	my %dirs = ();
	for my $track (@tracks) {
		my $path = Slim::Utils::Misc::pathFromFileURL($track->url);
		if($path) {
			$path =~ s/^(.*)\/(.*?)$/$1/;
			if(!$dirs{$path}) {
				$dirs{$path} = $path;
			}
		}
	}
	for my $dir (keys %dirs) {
		next unless -f catfile($dir,$params->{'file'});
		$log->debug("Reading: ".catfile($dir,$params->{'file'})."\n");
		my $content = read_file(catfile($dir,$params->{'file'}));
		return \$content;
	}
	return undef;
}

sub handleWebAlbumFile {
	my ($client, $params, $callback, $httpClient,$response) = @_;

	my $albumId = $params->{'album'};
	my $album = Slim::Schema->resultset('Album')->find($albumId);
	my @tracks = $album->tracks;

	my %dirs = ();
	for my $track (@tracks) {
		my $path = Slim::Utils::Misc::pathFromFileURL($track->url);
		if($path) {
			$path =~ s/^(.*)\/(.*?)$/$1/;
			if(!$dirs{$path}) {
				$dirs{$path} = $path;
			}
		}
	}
	for my $dir (keys %dirs) {
		next unless -f catfile($dir,$params->{'file'});
		$log->debug("Reading: ".catfile($dir,$params->{'file'})."\n");
		my $content = read_file(catfile($dir,$params->{'file'}));
		return \$content;
	}
	return undef;
}

sub handleWebImageCacheFile {
	my ($client, $params, $callback, $httpClient,$response) = @_;
	my $type = $params->{'type'};
	my $name = undef;
	my $section = $params->{'section'};
	# We don't want to allow .. for security reason
	if(defined($section) && $section ne '') {
		if($section =~ /\.\./) {
			$section = undef;
		}
	}
	if(defined($type) && $type eq 'artist') {
		my $artistId = $params->{'artist'};
		my $artist = Slim::Schema->resultset('Contributor')->find($artistId);
		if(defined($artist)) {
			$name = $artist->name;
		}
	}elsif(defined($type) && $type eq 'album') {
		my $albumId = $params->{'album'};
		my $album = Slim::Schema->resultset('Album')->find($albumId);
		if(defined($album)) {
			$name = $album->title;
		}
	}elsif(defined($type) && $type eq 'genre') {
		my $genreId = $params->{'genre'};
		my $genre = Slim::Schema->resultset('Genre')->find($genreId);
		if(defined($genre)) {
			$name = $genre->name;
		}
	}elsif(defined($type) && $type eq 'playlist') {
		my $playlistId = $params->{'playlist'};
		my $playlist = Slim::Schema->resultset('Playlist')->find($playlistId);
		if(defined($playlist)) {
			$name = $playlist->title;
		}
	}elsif(defined($type) && $type eq 'year') {
		my $yearId = $params->{'year'};
		if(defined($yearId)) {
			if(!$yearId) {
				$yearId = string('UNK');
			}
			$name = $yearId;
		}
	}elsif(defined($type) && $type eq 'custom') {
		$name = $params->{'custom'};
		# We don't want to allow .. for security reason
		if($name =~ /\.\./) {
			$name = undef;
		}
	}

	my $dir = $prefs->get('image_cache');

	if(defined($dir) && defined($name)) {
		my $extension = undef;
		my $file = $name;
		$name =~ s/[:\"]/ /g;
		if(defined($section) && $section ne '') {
			$file = catfile($section,$name);
		}
		if(-f catfile($dir,$file.".png")) {
			$extension = ".png";
		}elsif(-f catfile($dir,$file.".jpg")) {
			$extension = ".jpg";
		}elsif(-f catfile($dir,$file.".gif")) {
			$extension = ".gif";
		}
		if(defined($extension)) {
			$log->debug("Reading: ".catfile($dir,$file.$extension)."\n");
			my $content = read_file(catfile($dir,$file.$extension));
			return \$content;
		}
	}
	return undef;
}

sub handleWebSettings {
        my ($client, $params) = @_;
	$params->{'pluginCustomBrowseVersion'} = $PLUGINVERSION;

	if(defined($params->{'refresh'})) {
		readBrowseConfiguration($client);
		readContextBrowseConfiguration($client);
	}

        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_settings.html', $params);
}

sub structureContextItems {
	my $items = shift;

	my @result = ();

	my $previous = undef;
	for my $item (@$items) {
		if($previous && $previous eq $item->{'itemname'}) {
			my $previousItem = @result[scalar(@result)-1];
			if(!defined($previousItem->{'multipleitems'})) {
				my @newArray = ();
				push @newArray,$previousItem;
				$previousItem->{'multipleitems'} = \@newArray;
			}
			my $previousItems = $previousItem->{'multipleitems'};
			push @$previousItems,$item;
			$previousItem->{'multipleitems'} = $previousItems;
			@result[scalar(@result)-1] = $previousItem;
		}else {
			push @result,$item;		
		}
		$previous = $item->{'itemname'}
	}
	return \@result;
}

sub prepareManagingMenus {
	my ($client, $params) = @_;
	Plugins::CustomBrowse::Plugin::readBrowseConfiguration($client,$params);
	$manageMenuHandler->prepare($client,$params);
}

sub prepareManagingContextMenus {
	my ($client, $params) = @_;
	Plugins::CustomBrowse::Plugin::readContextBrowseConfiguration($client,$params);
	$manageMenuHandler->prepare($client,$params);
}

sub handleWebEditMenus {
        my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webEditItems($client,$params);	
	}else {
		return getConfigManager()->webEditItems($client,$params);	
	}
}

sub handleWebEditMenu {
        my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webEditItem($client,$params);	
	}else {
		return getConfigManager()->webEditItem($client,$params);	
	}
}

sub handleWebHideMenu {
        my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		hideMenu($client,$params,getContextConfigManager(),1,'context_menu_');	
	}else {
		hideMenu($client,$params,getConfigManager(),1,'menu_');	
	}
	return handleWebEditMenus($client,$params);
}

sub handleWebShowMenu {
        my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		hideMenu($client,$params,getContextConfigManager(),0,'context_menu_');	
	}else {
		hideMenu($client,$params,getConfigManager(),0,'menu_');	
	}
	return handleWebEditMenus($client,$params);
}

sub handleWebDeleteMenuType {
	my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webDeleteItemType($client,$params);	
	}else {
		return getConfigManager()->webDeleteItemType($client,$params);	
	}
}

sub handleWebNewMenuTypes {
	my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webNewItemTypes($client,$params);	
	}else {
		return getConfigManager()->webNewItemTypes($client,$params);	
	}
}

sub handleWebNewMenuParameters {
	my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webNewItemParameters($client,$params);	
	}else {
		return getConfigManager()->webNewItemParameters($client,$params);	
	}
}

sub handleWebLogin {
	my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webLogin($client,$params);	
	}else {
		return getConfigManager()->webLogin($client,$params);	
	}
}

sub handleWebPublishMenuParameters {
	my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webPublishItemParameters($client,$params);	
	}else {
		return getConfigManager()->webPublishItemParameters($client,$params);	
	}
}

sub handleWebPublishMenu {
	my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webPublishItem($client,$params);	
	}else {
		return getConfigManager()->webPublishItem($client,$params);	
	}
}

sub handleWebDownloadMenus {
	my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webDownloadItems($client,$params);
	}else {
		return getConfigManager()->webDownloadItems($client,$params);
	}
}

sub handleWebDownloadNewMenus {
	my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webDownloadNewItems($client,$params);	
	}else {
		return getConfigManager()->webDownloadNewItems($client,$params);	
	}
}

sub handleWebDownloadMenu {
	my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webDownloadItem($client,$params);	
	}else {
		return getConfigManager()->webDownloadItem($client,$params);	
	}
}

sub handleWebNewMenu {
	my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webNewItem($client,$params);	
	}else {
		return getConfigManager()->webNewItem($client,$params);	
	}
}

sub handleWebSaveSimpleMenu {
	my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webSaveSimpleItem($client,$params);	
	}else {
		return getConfigManager()->webSaveSimpleItem($client,$params);	
	}
}

sub handleWebRemoveMenu {
	my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webRemoveItem($client,$params);	
	}else {
		return getConfigManager()->webRemoveItem($client,$params);	
	}
}

sub handleWebSaveNewSimpleMenu {
	my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webSaveNewSimpleItem($client,$params);	
	}else {
		return getConfigManager()->webSaveNewSimpleItem($client,$params);	
	}
}

sub handleWebSaveNewMenu {
	my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webSaveNewItem($client,$params);	
	}else {
		return getConfigManager()->webSaveNewItem($client,$params);	
	}
}

sub handleWebSaveMenu {
	my ($client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webSaveItem($client,$params);	
	}else {
		return getConfigManager()->webSaveItem($client,$params);	
	}
}



sub handleWebPlayAdd {
	my ($client, $params,$addOnly,$insert, $gotoparent,$usecontext) = @_;
	return unless $client;
	if(!defined($params->{'hierarchy'})) {
		readBrowseConfiguration($client);
	}
	my $items = undef;
	if($usecontext) {
		if(defined($params->{'contexttype'})) {
			if(defined($params->{'hierarchy'})) {
				my $regExp = "^group_".$params->{'contexttype'}.".*";
				if($params->{'hierarchy'} !~ /$regExp/) {
					$params->{'hierarchy'} = 'group_'.$params->{'contexttype'}.','.$params->{'hierarchy'};
				}
			}else {
				$params->{'hierarchy'} = 'group_'.$params->{'contexttype'};
			}
		}
		my $contextParams = undef;
		if(defined($params->{'contextid'})) {
			my %c = (
				'itemid' => $params->{'contextid'},
				'itemtype' => $params->{'contexttype'},
				'itemname' => $params->{'contextname'}
			);
			my $contextString = '';
			if(defined($c{'itemid'})) {
				$contextString .= "&contextid=".$c{'itemid'};
			}
			if(defined($c{'itemtype'})) {
				$contextString .= "&contexttype=".$c{'itemtype'};
			}
			if(defined($c{'itemname'})) {
				$contextString .= "&contextname=".escape($c{'itemname'});
			}
			$c{'itemurl'} = $contextString;
			$contextParams = \%c;
		}
		my $it = getContextMenuHandler()->getPageItem($client,$params,$contextParams,0,'web');
		getContextMenuHandler()->playAddItem($client,undef,$it,$addOnly,$insert,$contextParams);
	}else {
		my $it = getMenuHandler()->getPageItem($client,$params,undef,0,'web');
		getMenuHandler()->playAddItem($client,undef,$it,$addOnly,$insert,undef);
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
				$newHierarchy .= $hierarchyItem;
			}
			$i=$i+1;
		}
		if($newHierarchy ne '') {
			$params->{'hierarchy'} = $newHierarchy;
		}else {
			delete $params->{'hierarchy'};
		}
	}
	if($gotoparent) {
		$hierarchy = $params->{'hierarchy'};
		if($params->{'url_query'} =~ /[&?]hierarchy=/) {
			$params->{'url_query'} =~ s/([&?]hierarchy=)([^&]*)/$1$hierarchy/;
		}
		if($params->{'url_query'} =~ /[&?]hierarchy=&/) {
			$params->{'url_query'} =~ s/[&?]hierarchy=&//;
		}
	}
	if($usecontext) {
		$params->{'CustomBrowseReloadPath'} = 'plugins/CustomBrowse/custombrowse_contextlist.html';
		$params->{'CustomBrowseReloadQuery'} = $params->{'url_query'};
		return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_reload.html', $params);
	}else {
		$params->{'CustomBrowseReloadPath'} = 'plugins/CustomBrowse/custombrowse_list.html';
		$params->{'CustomBrowseReloadQuery'} = $params->{'url_query'};
		return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_reload.html', $params);
	}
}
sub handleWebPlay {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,0,0,1);
}

sub handleWebAdd {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,1,0,1);
}

sub handleWebInsert {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,1,1,1);
}

sub handleWebPlayAll {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,0,0,0);
}

sub handleWebAddAll {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,1,0,0);
}

sub handleWebInsertAll {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,1,1,0);
}

sub handleWebContextPlay {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,0,0,1,1);
}

sub handleWebContextAdd {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,1,0,1,1);
}

sub handleWebContextInsert {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,1,1,1,1);
}

sub handleWebContextPlayAll {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,0,0,0,1);
}

sub handleWebContextAddAll {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,1,0,0,1);
}

sub handleWebContextInsertAll {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,1,1,0,1);
}

sub handleWebMix {
	my ($client, $params) = @_;
	return unless $client;
	if(!defined($params->{'hierarchy'})) {
		readBrowseConfiguration($client);
	}
	
	my $result = retreiveMixList($client,$params);
	if(defined($result)) {
		return $result;
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
		$hierarchy = $newHierarchy;
	}
	$params->{'CustomBrowseReloadPath'} = 'plugins/CustomBrowse/custombrowse_list.html';
	if($params->{'url_query'} =~ /[&?]hierarchy=/) {
		$params->{'url_query'} =~ s/([&?]hierarchy=)([^&]*)/$1$hierarchy/;
	}
	if($params->{'url_query'} =~ /[&?]hierarchy=&/) {
		$params->{'url_query'} =~ s/[&?]hierarchy=&//;
	}
	$params->{'CustomBrowseReloadQuery'} = $params->{'url_query'};
	return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_reload.html', $params);
}

sub handleWebMixContext {
	my ($client, $params) = @_;
	return unless $client;
	if(!defined($params->{'hierarchy'})) {
		readContextBrowseConfiguration($client);
	}
	
	if(defined($params->{'contexttype'})) {
		if(defined($params->{'hierarchy'})) {
			my $regExp = "^group_".$params->{'contexttype'}.".*";
			if($params->{'hierarchy'} !~ /$regExp/) {
				$params->{'hierarchy'} = 'group_'.$params->{'contexttype'}.','.$params->{'hierarchy'};
			}
		}else {
			$params->{'hierarchy'} = 'group_'.$params->{'contexttype'};
		}
	}
	my $contextParams = undef;
	if(defined($params->{'contextid'})) {
		my %c = (
			'itemid' => $params->{'contextid'},
			'itemtype' => $params->{'contexttype'},
			'itemname' => $params->{'contextname'}
		);
		my $contextString = '';
		if(defined($c{'itemid'})) {
			$contextString .= "&contextid=".$c{'itemid'};
		}
		if(defined($c{'itemtype'})) {
			$contextString .= "&contexttype=".$c{'itemtype'};
		}
		if(defined($c{'itemname'})) {
			$contextString .= "&contextname=".escape($c{'itemname'});
		}
		$c{'itemurl'} = $contextString;
		$contextParams = \%c;
	}

	my $result = retreiveMixList($client,$params,$contextParams);
	if(defined($result)) {
		return $result;
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
		$hierarchy = $newHierarchy;
	}
	$params->{'CustomBrowseReloadPath'} = 'plugins/CustomBrowse/custombrowse_contextlist.html';
	if($params->{'url_query'} =~ /[&?]hierarchy=/) {
		$params->{'url_query'} =~ s/([&?]hierarchy=)([^&]*)/$1$hierarchy/;
	}
	if($params->{'url_query'} =~ /[&?]hierarchy=&/) {
		$params->{'url_query'} =~ s/[&?]hierarchy=&//;
	}
	$params->{'CustomBrowseReloadQuery'} = $params->{'url_query'};
	return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_reload.html', $params);
}

sub handleWebMixList {
	my ($client, $params) = @_;
	return unless $client;
	my %c = (
		'itemid' => $params->{'contextid'},
		'itemtype' => $params->{'contexttype'},
		'itemname' => $params->{'contextname'}
	);
	my $contextString = '';
	if(defined($c{'itemid'})) {
		$contextString .= "&contextid=".$c{'itemid'};
	}
	if(defined($c{'itemtype'})) {
		$contextString .= "&contexttype=".$c{'itemtype'};
	}
	if(defined($c{'itemname'})) {
		$contextString .= "&contextname=".escape($c{'itemname'});
	}
	my %p = (
		'hierarchy' => 'group_'.$params->{'contexttype'}
	);
	$p{'contexttype'} = $params->{'contexttype'};
	$p{'contextid'} = $params->{'contextid'};
	$p{'contextname'} = $params->{'contextname'};
	my $contextItems = getContextMenuHandler()->getContext($client,\%p);

	my @contexts = @$contextItems;

	my $currentcontext = undef;
	if(scalar(@contexts)>0) {
		$currentcontext = @contexts[scalar(@contexts)-1];
	}

	my $mixes = getContextMenuHandler()->getPreparedMixes($client,\%c,'web');
	$params->{'pluginCustomBrowseMixes'} = $mixes;
	$params->{'pluginCustomBrowseItemUrl'} = $currentcontext->{'url'}.$currentcontext->{'valueUrl'};

	$params->{'pluginCustomBrowseItemUrl'} .= $contextString;

	$params->{'pluginCustomBrowseContext'} = $contextItems;
	$params->{'pluginCustomBrowseContextMixUrl'} = 1;
	
	return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_listmixes.html', $params);
}

sub retreiveMixList {
	my ($client, $params, $contextParams) = @_;
	my $item = undef;
	my $nextitem = undef;
	my $contextItems = undef;
	if($contextParams) {
		$contextItems = getContextMenuHandler()->getContext($client,$params);
	}else {
		$contextItems = getMenuHandler()->getContext($client,$params);
	}
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
	my $items = undef;
	if($contextParams) {
		$items = getContextMenuHandler()->getMenuItems($client,$item,$contextParams,'web');
	}else {
		$items = getMenuHandler()->getMenuItems($client,$item,undef,'web');
	}
	my $selecteditem = undef;
	for my $it (@$items) {
		my $id = $nextitem->{'id'};
		if(defined($nextitem->{'contextid'})) {
			$id = $nextitem->{'contextid'};
		}
		if($it->{'itemid'} eq $params->{$id}) {
			$selecteditem = $it;
		}
	}
	if(defined($selecteditem)) {
		my $mixes = undef;
		if($contextParams) {
			$mixes = getContextMenuHandler()->getPreparedMixes($client,$selecteditem,'web');
		}else {
			$mixes = getMenuHandler()->getPreparedMixes($client,$selecteditem,'web');
		}
		if(scalar(@$mixes)>1) {
			$params->{'pluginCustomBrowseMixes'} = $mixes;
			$params->{'pluginCustomBrowseItemUrl'} = $currentcontext->{'url'}.$currentcontext->{'valueUrl'};
			if($contextParams && defined($contextParams->{'itemurl'})) {
				$params->{'pluginCustomBrowseItemUrl'} .= $contextParams->{'itemurl'};
			}
			pop @$contextItems;
			$params->{'pluginCustomBrowseContext'} = $contextItems;
			if($contextParams) {
				$params->{'pluginCustomBrowseContextMixUrl'} = 1;
			}
			return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_listmixes.html', $params);
		}elsif(scalar(@$mixes)>0) {
			if(!defined(@$mixes->[0]->{'url'})) {
				$params->{'mix'} = @$mixes->[0]->{'id'};
				if($contextParams) {
					return handleWebExecuteMixContext($client,$params);
				}else {
					return handleWebExecuteMix($client,$params);
				}
			}else {
				$params->{'pluginCustomBrowseRedirect'} = @$mixes->[0]->{'url'};
				return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_redirect.html', $params);
			}
		}
	}
	return undef;
}

sub handleWebExecuteMix {
	my ($client, $params) = @_;
	return unless $client;
	if(!defined($params->{'hierarchy'})) {
		readBrowseConfiguration($client);
	}

	executeMix($client,$params,undef,'web');

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
				$newHierarchy .= $hierarchyItem;
			}
			$i=$i+1;
		}
		$params->{'hierarchy'} = $newHierarchy;
		$hierarchy = $newHierarchy;
	}
	$params->{'CustomBrowseReloadPath'} = 'plugins/CustomBrowse/custombrowse_list.html';
	if($params->{'url_query'} =~ /[&?]hierarchy=/) {
		$params->{'url_query'} =~ s/([&?]hierarchy=)([^&]*)/$1$hierarchy/;
	}
	if($params->{'url_query'} =~ /[&?]hierarchy=&/) {
		$params->{'url_query'} =~ s/[&?]hierarchy=&//;
	}
	$params->{'CustomBrowseReloadQuery'} = $params->{'url_query'};
	return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_reload.html', $params);
}

sub handleWebExecuteMixContext {
	my ($client, $params) = @_;
	return unless $client;
	if(!defined($params->{'hierarchy'})) {
		readContextBrowseConfiguration($client);
	}

	if(defined($params->{'contexttype'})) {
		if(defined($params->{'hierarchy'})) {
			my $regExp = "^group_".$params->{'contexttype'}.".*";
			if($params->{'hierarchy'} !~ /$regExp/) {
				$params->{'hierarchy'} = 'group_'.$params->{'contexttype'}.','.$params->{'hierarchy'};
			}
		}else {
			$params->{'hierarchy'} = 'group_'.$params->{'contexttype'};
		}
	}
	my $contextParams = undef;
	if(defined($params->{'contextid'})) {
		my %c = (
			'itemid' => $params->{'contextid'},
			'itemtype' => $params->{'contexttype'},
			'itemname' => $params->{'contextname'}
		);
		my $contextString = '';
		if(defined($c{'itemid'})) {
			$contextString .= "&contextid=".$c{'itemid'};
		}
		if(defined($c{'itemtype'})) {
			$contextString .= "&contexttype=".$c{'itemtype'};
		}
		if(defined($c{'itemname'})) {
			$contextString .= "&contextname=".escape($c{'itemname'});
		}
		$c{'itemurl'} = $contextString;
		$contextParams = \%c;
	}

	executeMix($client,$params,$contextParams,'web');

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
				$newHierarchy .= $hierarchyItem;
			}
			$i=$i+1;
		}
		$params->{'hierarchy'} = $newHierarchy;
		$hierarchy = $newHierarchy;
	}
	$params->{'CustomBrowseReloadPath'} = 'plugins/CustomBrowse/custombrowse_contextlist.html';
	if($params->{'url_query'} =~ /[&?]hierarchy=/) {
		$params->{'url_query'} =~ s/([&?]hierarchy=)([^&]*)/$1$hierarchy/;
	}
	if($params->{'url_query'} =~ /[&?]hierarchy=&/) {
		$params->{'url_query'} =~ s/[&?]hierarchy=&//;
	}
	$params->{'CustomBrowseReloadQuery'} = $params->{'url_query'};
	return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_reload.html', $params);
}

sub executeMix {
	my $client = shift;
	my $params = shift;
	my $contextParams = shift;
	my $interfaceType = shift;

	my $item = undef;
	my $nextitem = undef;
	my $contextItems = undef;
	if($contextParams) {
		$contextItems = getContextMenuHandler()->getContext($client,$params);
	}else {
		$contextItems = getMenuHandler()->getContext($client,$params);
	}
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
	my $items = undef;
	if($contextParams) {
		$items = getContextMenuHandler()->getMenuItems($client,$item,$contextParams,$interfaceType);
	}else {
		$items = getMenuHandler()->getMenuItems($client,$item,undef,$interfaceType);
	}
	my $selecteditem = undef;
	for my $it (@$items) {
		my $id = $nextitem->{'id'};
		if(defined($nextitem->{'contextid'})) {
			$id = $nextitem->{'contextid'};
		}
		if($it->{'itemid'} eq $params->{$id}) {
			$selecteditem = $it;
		}
	}
	if(defined($selecteditem)) {
		my $mixes = undef;
		if($contextParams) {
			$mixes = getContextMenuHandler()->getMixes($client,$selecteditem,$interfaceType);
		}else {
			$mixes = getMenuHandler()->getMixes($client,$selecteditem,$interfaceType);
		}
		for my $mix (@$mixes) {
			if($mix->{'id'} eq $params->{'mix'}) {
				if($interfaceType eq 'jive' && exists $mix->{'mixjive'}) {
					my @commandparts = split(/ /,$mix->{'mixjive'});
					my @executableCommand = ();
					for my $part (@commandparts) {
						if($contextParams) {
							$part = getContextMenuHandler()->itemParameterHandler->replaceParameters($client,$part,$selecteditem);
						}else {
							$part = getMenuHandler()->itemParameterHandler->replaceParameters($client,$part,$selecteditem);
						}
						push @executableCommand,$part;
					}
					$log->debug("Execute: ".join(' ',@executableCommand));
					my $request = $client->execute(\@executableCommand);
					return $request->getResults();
				}else {
					if($contextParams) {
						getContextMenuHandler()->executeMix($client,$mix,0,$selecteditem,$interfaceType);
					}else {
						getMenuHandler()->executeMix($client,$mix,0,$selecteditem,$interfaceType);
					}
				}
				last;
			}
		}
	}
	return undef;
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

sub getSlimserverMenus {
	my @slimserverMenus = ();
	my %browseByAlbum = (
		'id' => 'album',
		'name' => string('BROWSE_BY_ALBUM'),
		'enabled' => !$prefs->get('squeezecenter_album_menu')
	);
	push @slimserverMenus,\%browseByAlbum;
	my %browseByArtist = (
		'id' => 'artist',
		'name' => string('BROWSE_BY_ARTIST'),
		'enabled' => !$prefs->get('squeezecenter_artist_menu')
	);
	push @slimserverMenus,\%browseByArtist;
	my %browseByGenre = (
		'id' => 'genre',
		'name' => string('BROWSE_BY_GENRE'),
		'enabled' => !$prefs->get('squeezecenter_genre_menu')
	);
	push @slimserverMenus,\%browseByGenre;
	my %browseByYear = (
		'id' => 'year',
		'name' => string('BROWSE_BY_YEAR'),
		'enabled' => !$prefs->get('squeezecenter_year_menu')
	);
	push @slimserverMenus,\%browseByYear;
	my %browseNewMusic = (
		'id' => 'newmusic',
		'name' => string('BROWSE_NEW_MUSIC'),
		'enabled' => !$prefs->get('squeezecenter_newmusic_menu')
	);
	push @slimserverMenus,\%browseNewMusic;
	my %browsePlaylist = (
		'id' => 'playlist',
		'name' => string('SAVED_PLAYLISTS').' (Player menu)',
		'enabled' => !$prefs->get('squeezecenter_playlist_menu')
	);
	push @slimserverMenus,\%browsePlaylist;
	my %iPengBrowseMore = (
		'id' => 'ipengbrowsemore',
		'name' => 'Browse More (iPeng skin)',
		'enabled' => !$prefs->get('squeezecenter_ipengbrowsemore_menu')
	);
	push @slimserverMenus,\%iPengBrowseMore;
	return \@slimserverMenus;
}


sub cliJiveHandler {
	$log->debug("Entering cliJiveHandler\n");
	my $request = shift;
	my $client = $request->client();

	if (!$request->isQuery([['custombrowse'],['browsejive']]) && !$request->isQuery([['custombrowse'],['browsejivecontext']])) {
		$log->warn("Incorrect command\n");
		$request->setStatusBadDispatch();
		$log->debug("Exiting cliJiveHandler\n");
		return;
	}
	if(!defined $client) {
		$log->warn("Client required\n");
		$request->setStatusNeedsClient();
		$log->debug("Exiting cliJiveHandler\n");
		return;
	}
	my $context = undef;
	if ($request->isQuery([['custombrowse'],['browsejivecontext']])) {
		$context = {
			'itemtype' => $request->getParam('contexttype'),
			'itemid' => $request->getParam('contextid'),
			'itemname' => $request->getParam('contextname'),
		};
	}else {
	}

	cliJiveHandlerImpl($client,$request,$context);
}

sub cliJiveMixHandler {
	$log->debug("Entering cliJiveMixHandler\n");
	my $request = shift;
	my $client = $request->client();

	if (!$request->isQuery([['custombrowse'],['mixjive']]) && !$request->isQuery([['custombrowse'],['mixjivecontext']])) {
		$log->warn("Incorrect command\n");
		$request->setStatusBadDispatch();
		$log->debug("Exiting cliJiveHandler\n");
		return;
	}
	if(!defined $client) {
		$log->warn("Client required\n");
		$request->setStatusNeedsClient();
		$log->debug("Exiting cliJiveHandler\n");
		return;
	}
	my $context = undef;
	if ($request->isQuery([['custombrowse'],['mixjivecontext']])) {
		$context = {
			'itemtype' => $request->getParam('contexttype'),
			'itemid' => $request->getParam('contextid'),
			'itemname' => $request->getParam('contextname'),
		};
	}else {
	}

	cliJiveMixHandlerImpl($client,$request,$context);
}

sub cliJiveMixHandlerImpl {
	my $client = shift;
	my $request = shift;
	my $browseContext = shift;
	my $cmd = shift;

	if(!$browseMenusFlat) {
		readBrowseConfiguration($client);
	}
	my $params = $request->getParamsCopy();

	for my $k (keys %$params) {
		$log->debug("Got: $k=".$params->{$k}."\n");
	}

	my $start = $request->getParam('start');
	if(!defined($start)) {
		$start = $request->getParam('_start');
		if(!defined($start)) {
			$start = $request->getParam('_p2');
		}
	}
	if(!defined($start) || $start eq '') {
		$start=0;
	}
	$params->{'start'}=$start;
	my $itemsPerPage = $request->getParam('itemsPerResponse');
	if(!defined($itemsPerPage)) {
		$itemsPerPage = $request->getParam('_itemsPerResponse');
		if(!defined($itemsPerPage)) {
			$itemsPerPage = $request->getParam('_p3');
		}
	}
	if(defined($itemsPerPage) || $itemsPerPage ne '') {
		$params->{'itemsperpage'}=$itemsPerPage;
	}

	$params->{'mix'} = $request->getParam('mixid');

	if(defined($browseContext) && defined($browseContext->{'itemtype'})) {
		if(defined($params->{'hierarchy'})) {
			my $regExp = "^group_".$browseContext->{'itemtype'}.".*";
			if($params->{'hierarchy'} !~ /$regExp/) {
				$params->{'hierarchy'} = 'group_'.$browseContext->{'itemtype'}.','.$params->{'hierarchy'};
			}
		}else {
			$params->{'hierarchy'} = 'group_'.$browseContext->{'itemtype'};
		}
	}

	$log->debug("Starting to prepare CLI mix command\n");

	my $result = undef;
	if(defined($browseContext)) {
		$result = executeMix($client,$params,$browseContext,'jive');
	}else {
		$result = executeMix($client,$params,undef,'jive');
	}
	if(defined($result)) {
		$request->setRawResults($result);
	}
	$request->setStatusDone();
}

sub cliJiveHandlerImpl {
	my $client = shift;
	my $request = shift;
	my $browseContext = shift;

	if(!$browseMenusFlat) {
		readBrowseConfiguration($client);
	}
	my $params = $request->getParamsCopy();

	for my $k (keys %$params) {
		$log->debug("Got: $k=".$params->{$k}."\n");
	}

	my $start = $request->getParam('start');
	if(!defined($start)) {
		$start = $request->getParam('_start');
		if(!defined($start)) {
			$start = $request->getParam('_p2');
		}
	}
	if(!defined($start) || $start eq '') {
		$start=0;
	}
	if($start>0) {
		# Decrease to compensate for "Play All" item on first chunk
		$start--;
	}
	$params->{'start'}=$start;
	my $itemsPerPage = $request->getParam('itemsPerResponse');
	if(!defined($itemsPerPage)) {
		$itemsPerPage = $request->getParam('_itemsPerResponse');
		if(!defined($itemsPerPage)) {
			$itemsPerPage = $request->getParam('_p3');
		}
	}
	if(defined($itemsPerPage) || $itemsPerPage ne '') {
		$params->{'itemsperpage'}=$itemsPerPage;
	}
	if(defined($params->{'hierarchy'})) {
		#I am not sure why this is needed, but it solves the case where menu id is non ascii characters
		$params->{'hierarchy'} = unescape($params->{'hierarchy'});
		$params->{'hierarchy'} = Slim::Utils::Unicode::utf8on($params->{'hierarchy'});
	}

	my $menuResult = undef;
	my $context = undef;
	if (!defined($browseContext)) {
		$log->debug("Executing CLI browsejive command\n");
		$menuResult = getMenuHandler()->getPageItemsForContext($client,$params,undef,0,'jive');	
		$context = getMenuHandler()->getContext($client,$params,1);
	}else {
		$log->debug("Executing CLI browsejivecontext command\n");
		if(defined $browseContext->{'itemtype'}) {
			$params->{'contexttype'} = $browseContext->{'itemtype'};
		}
		if(defined $browseContext->{'itemid'}) {
			$params->{'contextid'} = $browseContext->{'itemid'};
		}
		if(defined $browseContext->{'itemname'}) {
			$params->{'contextname'} = $browseContext->{'itemname'};
		}
		if(defined($params->{'contexttype'})) {
			if(defined($params->{'hierarchy'})) {
				my $regExp = "^group_".$params->{'contexttype'}.".*";
				if($params->{'hierarchy'} !~ /$regExp/) {
					$params->{'hierarchy'} = 'group_'.$params->{'contexttype'}.','.$params->{'hierarchy'};
				}
			}else {
				$params->{'hierarchy'} = 'group_'.$params->{'contexttype'};
			}
		}
		$menuResult = getContextMenuHandler()->getPageItemsForContext($client,$params,$browseContext,0,'jive');	
		$context = getContextMenuHandler()->getContext($client,$params,1);
		if(scalar(@$context)>0) {
			if(defined($browseContext->{'itemname'})) {
				$context->[0]->{'name'} = Slim::Utils::Unicode::utf8decode($browseContext->{'itemname'},'utf8');
			}else {
				$context->[0]->{'name'} = "Context";
			}
		}
	}
	my $currentContext = undef;
	if(defined($context) && scalar(@$context)>0) {
		$currentContext = $context->[scalar(@$context)-1];
	}
	my $menuItems = $menuResult->{'items'};
	my $count = $menuResult->{'pageinfo'}->{'totalitems'};
	my %baseParams = ();
	foreach my $param (keys %$params) {
		if($param ne 'hierarchy' && $param ne 'start' && $param ne 'itemsperpage' && $param !~ /^_/) {
			$baseParams{$param} = $params->{$param};
		}
	}
	my $baseMenu = {
		'actions' => {
			'go' => {
				'cmd' => ['custombrowse', 'browsejive'],
				'params' => \%baseParams,
				'itemsParams' => 'params',
			},
			'add' => {
				'cmd' => ['custombrowse', 'add'],
				'params' => \%baseParams,
				'itemsParams' => 'params',
			},
			'add-hold' => {
				'cmd' => ['custombrowse', 'insert'],
				'params' => \%baseParams,
				'itemsParams' => 'params',
			},
			'play' => {
				'cmd' => ['custombrowse', 'play'],
				'params' => \%baseParams,
				'itemsParams' => 'params',
			},
		}
	};
	if (defined($browseContext)) {
		$baseMenu->{'actions'}->{'go'}->{'cmd'} = ['custombrowse', 'browsejivecontext'];
		$baseMenu->{'actions'}->{'play'}->{'cmd'} = ['custombrowse', 'playcontext'];
		$baseMenu->{'actions'}->{'add'}->{'cmd'} = ['custombrowse', 'addcontext'];
		$baseMenu->{'actions'}->{'add-hold'}->{'cmd'} = ['custombrowse', 'insertcontext'];
	}
	$request->addResult('base',$baseMenu);

	my $cnt = 0;
	if(scalar(@$menuItems)>1 && defined($menuResult->{'playable'}) && $menuResult->{'playable'} && defined($currentContext) && $start==0) {
		my %itemParams = ();
		%itemParams = %{$currentContext->{'parameters'}};
		$itemParams{'hierarchy'} = $currentContext->{'valuePath'};
		my $actions = {
			'go' => undef,
			'add-hold' => undef,
		};
		$request->addResultLoop('item_loop',$cnt,'playAction','play');
		$request->addResultLoop('item_loop',$cnt,'playHoldAction','play');
		$request->addResultLoop('item_loop',$cnt,'style','itemplay');
		$request->addResultLoop('item_loop',$cnt,'params',\%itemParams);
		$request->addResultLoop('item_loop',$cnt,'actions',$actions);
		$request->addResultLoop('item_loop',$cnt,'text',string('JIVE_PLAY_ALL'));
		$cnt++;

		if(defined($itemsPerPage) && scalar(@$menuItems)>=$itemsPerPage) {
			$log->debug("Removing item to make space for play all item, requested $itemsPerPage and got ".(scalar(@$menuItems))." items");
			# Remove last menu item
			my $popped = pop @$menuItems;
		}else {
			$count++;
		}
	}
	foreach my $item (@$menuItems) {
		my $name;
		my $itemkey;
		if(defined($item->{'itemvalue'})) {
			$name = $item->{'itemname'}.': '.$item->{'itemvalue'};
		}else {
			$name = $item->{'itemname'};
		}
		my $jivePattern = undef;
		if(defined($item->{'itemtype'}) && defined($item->{$item->{'itemtype'}.'jivepattern'})) {
			$jivePattern = $item->{$item->{'itemtype'}.'jivepattern'};
		}elsif(defined($item->{'jivepattern'})) {
			$jivePattern = $item->{'jivepattern'};
		}
		if(defined($jivePattern)) {
			if($name =~ /$jivePattern/) {
				if(defined($1)) {
					$name = $1; 
					if(defined($2)) {
						$name .= "\n".$2; 
					}
					if(defined($3)) {
						$name .= "\n".$3; 
					}
				}
			}
		}
		my $firstRowName = $name;
		if($firstRowName =~ /^(.*?)\n/) {
			$firstRowName = $1;
		}
		if(defined($item->{'itemlink'})) {
			$itemkey = $item->{'itemlink'};
		}

		my $itemtype = undef;
		if(defined($item->{'menu'})) {
			my $menuRef = $item->{'menu'};
			my @submenus = ();
			if(ref($menuRef) eq 'ARRAY') {
				@submenus = @$menuRef;
			}else {
				push @submenus,$menuRef;
			}
			my $ignore = 0;
			foreach my $nextmenu (@submenus) {
				if(defined($nextmenu->{'itemtype'})) {
					if(!defined($itemtype)) {
						$itemtype = $nextmenu->{'itemtype'};
					}elsif($itemtype ne $nextmenu->{'itemtype'}) {
						$itemtype = "NOTUSED";
					}
				}
				if(defined($nextmenu->{'menutype'}) && $nextmenu->{'menutype'} eq 'mode') {
					$ignore = 1;
					last;
				}
			}
			if($ignore) {
				$count=$count-1;
				next;
			}
		}
		if((defined($itemtype) && $itemtype eq 'album')) {
			if($menuResult->{'artwork'}) {
				$request->addResultLoop('item_loop',$cnt,'window',{'titleStyle' => 'album', 'menuStyle' => 'album'});
			}elsif($item->{'coverThumb'}) {
				$request->addResultLoop('item_loop',$cnt,'window',{'titleStyle' => 'album', 'icon-id' => $item->{'coverThumb'}});
			}else {
				$request->addResultLoop('item_loop',$cnt,'window',{'menuStyle' => 'album'});
			}

		}elsif($menuResult->{'artwork'} && defined($item->{'coverThumb'})) {
			if(defined($item->{'itemsubtype'}) && $item->{'itemsubtype'} eq 'album') {
				$request->addResultLoop('item_loop',$cnt,'window',{'menuStyle' => 'album','text'=>$firstRowName,'icon-id'=>''});
			}else {
				$request->addResultLoop('item_loop',$cnt,'window',{'titleStyle' => 'album'});
			}
		}elsif(defined($item->{'coverThumb'})) {
			if(defined($item->{'itemsubtype'}) && $item->{'itemsubtype'} eq 'album') {
				$request->addResultLoop('item_loop',$cnt,'window',{'titleStyle' => 'album', 'icon-id' => $item->{'coverThumb'}});
			}else {
				$request->addResultLoop('item_loop',$cnt,'window',{'titleStyle' => 'album', 'icon-id' => $item->{'coverThumb'}});
			}
		}elsif(defined($item->{'itemsubtype'}) && $item->{'itemsubtype'} eq 'album') {
			$request->addResultLoop('item_loop',$cnt,'window',{'menuStyle' => 'album'});
		}elsif(defined($item->{'itemtype'}) && $item->{'itemtype'} eq 'album') {
			$request->addResultLoop('item_loop',$cnt,'window',{'titleStyle' => 'album'});
		}

		my %itemParams = ();
		if(defined($item->{'contextid'})) {
			if(defined($params->{'hierarchy'}) && $params->{'hierarchy'} ne '') {
				$itemParams{'hierarchy'} = $params->{'hierarchy'}.','.$item->{'contextid'};
			}else {
				$itemParams{'hierarchy'} = $item->{'contextid'};
			}
			$itemParams{$item->{'contextid'}} = $item->{'itemid'};
		}else {
			if(defined($params->{'hierarchy'}) && $params->{'hierarchy'} ne '') {
				$itemParams{'hierarchy'} = $params->{'hierarchy'}.','.$item->{'id'};
			}else {
				$itemParams{'hierarchy'} = $item->{'id'};
			}
			$itemParams{$item->{'id'}} = $item->{'itemid'};
		}
		if($itemkey) {
			$itemParams{'textkey'} = $itemkey;
			#$request->addResultLoop('item_loop',$cnt,'textkey',$itemkey);
		}
		my $actions = undef;
		if(defined($item->{'mixes'})) {
			foreach my $p (keys %baseParams) {
				if(!exists $itemParams{$p}) {
					$itemParams{$p}=$baseParams{$p};
				}
			}
			$actions = {
				'play-hold' => {
					'cmd' => ['custombrowse', 'mixesjive'],
					'params' => \%itemParams,
					'itemsParams' => 'params',
				},
			};
			if (defined($browseContext)) {
				$actions->{'play-hold'}->{'cmd'} = ['custombrowse', 'mixesjivecontext'];
			}
			$request->addResultLoop('item_loop',$cnt,'playHoldAction','go');
		}
		if(defined($item->{'playtype'}) && $item->{'playtype'} eq 'none') {
			foreach my $p (keys %baseParams) {
				$itemParams{$p}=$baseParams{$p};
			}
			if(!defined($actions)) {
				$actions = {};
			}
			$actions->{'go'} = {
				'cmd' => ['custombrowse', 'browsejive'],
				'params' => \%itemParams,
				'itemsParams' => 'params',
			};
			if (defined($browseContext)) {
				$actions->{'go'}->{'cmd'} = ['custombrowse', 'browsejivecontext'];
			}
		}else {
			$request->addResultLoop('item_loop',$cnt,'params',\%itemParams);
		}

		if(defined($actions)) {
			$request->addResultLoop('item_loop',$cnt,'actions',$actions);
		}

		$request->addResultLoop('item_loop',$cnt,'text',$name);
		if($menuResult->{'artwork'} || (defined($item->{'itemtype'}) && $item->{'itemtype'} eq 'album')) {
			if(defined($item->{'coverThumb'})) {
				$request->addResultLoop('item_loop',$cnt,'icon-id',$item->{'coverThumb'});
			}
		}
		if(defined($item->{'menu'})) {
			my @submenus = ();
			if(ref($item->{'menu'}) eq 'ARRAY') {
				my $m = $item->{'menu'};
				@submenus = @$m;
			}else {
				push @submenus,$item->{'menu'};
			}
			my $songInfo = 0;
			my $mode = 0;
			foreach my $submenu (@submenus) {
				if(defined($submenu->{'menutype'}) && $submenu->{'menutype'} eq 'trackdetails') {
					$songInfo = 1;
					last;
				}elsif(defined($submenu->{'menutype'}) && $submenu->{'menutype'} eq 'mode') {
					$mode = 1;
					last;
				}
			}
			if($songInfo) {
				if($::VERSION ge '7.4') {
					my $songInfoParams = {
						track_id => $item->{'itemid'},
						menu => 'nowhere',
					};
					my $actions = {
						'go' => {
							'cmd' => ['trackinfo','items'],
							'params' => $songInfoParams,
						},
					};
					$request->addResultLoop('item_loop',$cnt,'actions',$actions);
				}else {
					my $songInfoParams = {
						track_id => $item->{'itemid'},
						menu => 'nowhere',
						cmd => 'load',
					};
					my $actions = {
						'go' => {
							'cmd' => ['songinfo'],
							'params' => $songInfoParams,
						},
					};
					$request->addResultLoop('item_loop',$cnt,'actions',$actions);
				}
			}elsif($mode) {
				$request->addResultLoop('item_loop',$cnt,'style','itemNoAction');
			}
		}elsif(!defined($item->{'menufunction'})) {
			$request->addResultLoop('item_loop',$cnt,'style','itemNoAction');
		}
		$cnt++;
	}
	if($start>0) {
		$start++;
	}
	$request->addResult('offset',$start);
	$request->addResult('count',$count);

	$request->setStatusDone();
	$log->debug("Exiting cliJiveHandler\n");
}

sub cliJiveMixesHandler {
	$log->debug("Entering cliJiveHandler\n");
	my $request = shift;
	my $client = $request->client();

	if (!$request->isQuery([['custombrowse'],['mixesjive']]) && !$request->isQuery([['custombrowse'],['mixesjivecontext']])) {
		$log->warn("Incorrect command\n");
		$request->setStatusBadDispatch();
		$log->debug("Exiting cliJiveMixesHandler\n");
		return;
	}
	if(!defined $client) {
		$log->warn("Client required\n");
		$request->setStatusNeedsClient();
		$log->debug("Exiting cliJiveMixesHandler\n");
		return;
	}

	if(!$browseMenusFlat) {
		readBrowseConfiguration($client);
	}
	my $params = $request->getParamsCopy();

	$log->debug("Starting to prepare CLI mixes command\n");
	$params->{'hierarchy'} =~ s/^(.*)(,.+?)$/$1/;
	my $attr = $2;
	$attr =~ s/^,(.*)$/$1/;
	my $itemid = $params->{$attr};
	my $menuResult = undef;
	$params->{'start'}=0;
	$params->{'itemsperpage'}=100000;
	if($request->isQuery([['custombrowse'],['mixesjive']])) {
		$menuResult = getMenuHandler()->getPageItemsForContext($client,$params,undef,0,'jive');	
	}else {
		my $context = {
			'itemtype' => $request->getParam('contexttype'),
			'itemid' => $request->getParam('contextid'),
			'itemname' => $request->getParam('contextname'),
		};
		$menuResult = getContextMenuHandler()->getPageItemsForContext($client,$params,$context,0,'jive');	
	}

	if(defined($menuResult) && defined($menuResult->{'items'})) {
		my $items = $menuResult->{'items'};
		foreach my $item (@$items) {
			if($item->{'itemid'} eq $itemid) {
				if(defined($item->{'mixes'})) {
					my %baseParams = ();
					foreach my $param (keys %$params) {
						if($param ne 'hierarchy' && $param ne 'start' && $param ne 'itemsperpage' && $param !~ /^_/) {
							$baseParams{$param} = $params->{$param};
						}
					}

					my $baseMenu = {
						'actions' => {
							'go' => {
								'cmd' => ['custombrowse', 'mixjive'],
								'params' => \%baseParams,
								'itemsParams' => 'params',
							},
							'add' => {
								'cmd' => ['custombrowse', 'mixjive'],
								'params' => \%baseParams,
								'itemsParams' => 'params',
							},
							'play' => {
								'cmd' => ['custombrowse', 'mixjive'],
								'params' => \%baseParams,
								'itemsParams' => 'params',
							},
						},
					};
					if($request->isQuery([['custombrowse'],['mixesjivecontext']])) {
						$baseMenu->{'actions'}->{'go'}->{'cmd'} = ['custombrowse', 'mixjivecontext'];
						$baseMenu->{'actions'}->{'add'}->{'cmd'} = ['custombrowse', 'mixjivecontext'];
						$baseMenu->{'actions'}->{'play'}->{'cmd'} = ['custombrowse', 'mixjivecontext'];
					}
					$request->addResult('base',$baseMenu);


					my $mixes = $item->{'mixes'};
				  	$request->addResult('count',scalar(@$mixes));
				  	$request->addResult('offset',0);
					my $mixno = 0;
					for my $mix (@$mixes) {
						my %itemParams = ();
						if(defined($item->{'contextid'})) {
							if(defined($params->{'hierarchy'}) && $params->{'hierarchy'} ne '') {
								$itemParams{'hierarchy'} = $params->{'hierarchy'}.','.$item->{'contextid'};
							}else {
								$itemParams{'hierarchy'} = $item->{'contextid'};
							}
							$itemParams{$item->{'contextid'}} = $item->{'itemid'};
						}else {
							if(defined($params->{'hierarchy'}) && $params->{'hierarchy'} ne '') {
								$itemParams{'hierarchy'} = $params->{'hierarchy'}.','.$item->{'id'};
							}else {
								$itemParams{'hierarchy'} = $item->{'id'};
							}
							$itemParams{$item->{'id'}} = $item->{'itemid'};
						}
						$itemParams{'mixid'} = $mix->{'id'};
						$request->addResultLoop('item_loop',$mixno,'params',\%itemParams);

					  	$request->addResultLoop('item_loop',$mixno,'text',$mix->{'name'});
						$mixno++;

					}
				}
				last;
			}
		}
	}

	$request->setStatusDone();
	$log->debug("Exiting cliJiveMixesHandler\n");
}

sub cliJiveStandardMixesHandler {
	$log->debug("Entering cliJiveStandardMixesHandler\n");
	my $request = shift;
	my $client = $request->client();

	if (!$request->isQuery([['custombrowse'],['stdmixjive']])) {
		$log->warn("Incorrect command\n");
		$request->setStatusBadDispatch();
		$log->debug("Exiting cliJiveStandardMixesHandler\n");
		return;
	}
	if(!defined $client) {
		$log->warn("Client required\n");
		$request->setStatusNeedsClient();
		$log->debug("Exiting cliJiveStandardMixesHandler\n");
		return;
	}

	if(!$browseMenusFlat) {
		readBrowseConfiguration($client);
	}
	my $params = $request->getParamsCopy();

	for my $k (keys %$params) {
		$log->debug("Got: $k=".$params->{$k}."\n");
	}

	my $objecttype = undef;
	my $itemId = undef;
	if($request->getParam('song_id')) {
		$objecttype = 'track';
		$itemId = $request->getParam('song_id');
	}elsif($request->getParam('track_id')) {
		$objecttype = 'track';
		$itemId = $request->getParam('track_id');
	}elsif($request->getParam('album_id')) {
		$objecttype = 'album';
		$itemId = $request->getParam('album_id');
	}elsif($request->getParam('artist_id')) {
		$objecttype = 'artist';
		$itemId = $request->getParam('artist_id');
	}elsif($request->getParam('contributor_id')) {
		$objecttype = 'artist';
		$itemId = $request->getParam('contributor_id');
	}elsif($request->getParam('genre_id')) {
		$objecttype = 'genre';
		$itemId = $request->getParam('genre_id');
	}elsif($request->getParam('year')) {
		$objecttype = 'year';
		$itemId = $request->getParam('year');
	}elsif($request->getParam('playlist')) {
		$objecttype = 'playlist';
		$itemId = $request->getParam('playlist');
	}

	$log->debug("Executing CLI mixjive command\n");

	my $cnt = 0;
	if(defined($objecttype)) {
		my $context = {
			'itemtype' => $objecttype,
			'itemid' => $itemId,
			'itemname' => undef,
		};
		cliJiveHandlerImpl($client,$request,$context);
	}else {
		$request->addResult('offset',0);
		$request->addResult('count',$cnt);
		$request->setStatusDone();
	}
	$log->debug("Exiting cliJiveStandardMixesHandler\n");
}

sub cliHandler {
	$log->debug("Entering cliHandler\n");
	my $request = shift;
	my $client = $request->client();

	my $cmd = undef;	
	if ($request->isQuery([['custombrowse'],['browse']])) {
		$cmd = 'browse';
	}elsif ($request->isQuery([['custombrowse'],['browsecontext']])) {
		$cmd = 'browsecontext';
	}elsif ($request->isCommand([['custombrowse'],['play']])) {
		$cmd = 'play';
	}elsif ($request->isCommand([['custombrowse'],['playcontext']])) {
		$cmd = 'playcontext';
	}elsif ($request->isCommand([['custombrowse'],['add']])) {
		$cmd = 'add';
	}elsif ($request->isCommand([['custombrowse'],['addcontext']])) {
		$cmd = 'addcontext';
	}elsif ($request->isCommand([['custombrowse'],['insert']])) {
		$cmd = 'insert';
	}elsif ($request->isCommand([['custombrowse'],['insertcontext']])) {
		$cmd = 'insertcontext';
	}elsif ($request->isQuery([['custombrowse'],['mixes']])) {
		$cmd = 'mixes';
	}elsif ($request->isQuery([['custombrowse'],['mixescontext']])) {
		$cmd = 'mixescontext';
	}elsif ($request->isCommand([['custombrowse'],['mix']])) {
		$cmd = 'mix';
	}elsif ($request->isCommand([['custombrowse'],['mixcontext']])) {
		$cmd = 'mixcontext';
	}else {
		$log->warn("Incorrect command\n");
		$request->setStatusBadDispatch();
		$log->debug("Exiting cliHandler\n");
		return;
	}
	if(!defined $client) {
		$log->warn("Client required\n");
		$request->setStatusNeedsClient();
		$log->debug("Exiting cliHandler\n");
		return;
	}
	
	if(!$browseMenusFlat) {
		readBrowseConfiguration($client);
	}
	my $paramNo = 2;
	my $params = $request->getParamsCopy();
	if($cmd =~ /^browse/) {
	  	my $start = $request->getParam('start');
		if(!defined($start)) {
			$start = $request->getParam('_start');
			if(!defined($start)) {
				$start = $request->getParam('_p'.$paramNo);
			}
		}
		if(!defined($start) || $start eq '') {
			$log->warn("_start not defined\n");
			$request->setStatusBadParams();
			$log->debug("Exiting cliHandler\n");
			return;
		}
		$params->{'start'}=$start;
		$paramNo++;
	  	my $itemsPerPage = $request->getParam('itemsPerResponse');
		if(!defined($itemsPerPage)) {
			$itemsPerPage = $request->getParam('_itemsPerResponse');
			if(!defined($itemsPerPage)) {
				$itemsPerPage = $request->getParam('_p'.$paramNo);
			}
		}
		if(!defined($itemsPerPage) || $itemsPerPage eq '') {
			$log->warn("_itemsPerResponse not defined\n");
			$request->setStatusBadParams();
			$log->debug("Exiting cliHandler\n");
			return;
		}
		$params->{'itemsperpage'}=$itemsPerPage;
		$paramNo++;
	}
	my %emptyHash = ();
	my $context = \%emptyHash;
	if($cmd =~ /context$/) {
		my $contexttype = $request->getParam('contexttype');
		if(!defined($contexttype)) {
			$contexttype = $request->getParam('_contexttype');
			if(!defined($contexttype)) {
				$contexttype = $request->getParam('_p'.$paramNo)
			}
		}
	  	if(!defined $contexttype || $contexttype eq '') {
			$log->warn("contexttype not defined\n");
			$request->setStatusBadParams();
			$log->debug("Exiting cliHandler\n");
			return;
	  	}
		$paramNo++;
		my $contextid = $request->getParam('contextid');
		if(!defined($contextid)) {
			$contextid = $request->getParam('_contextid');
			if(!defined($contextid)) {
				$contextid = $request->getParam('_p'.$paramNo)
			}
		}
	  	if(!defined $contextid || $contextid eq '') {
			$log->warn("contextid not defined\n");
			$request->setStatusBadParams();
			$log->debug("Exiting cliHandler\n");
			return;
	  	}
		$paramNo++;

		my %localContext = (
			'itemtype' => $contexttype,
			'itemid' => $contextid
		);
		$context = \%localContext;
	}
	if($cmd eq 'mix' || $cmd eq 'mixcontext') {
		$params->{'mix'} = $request->getParam('mixid');
		if(!defined($params->{'mix'})) {
			$params->{'mix'} = $request->getParam('_mixid');
			if(!defined($params->{'mix'})) {
				$params->{'mix'} = $request->getParam('_p'.$paramNo);
			}
		}
		$paramNo++;
	}

	for my $k (keys %$params) {
		$log->debug("Got: $k=".$params->{$k}."\n");
	}
	if(defined($context->{'itemtype'})) {
		if(defined($params->{'hierarchy'})) {
			my $regExp = "^group_".$context->{'itemtype'}.".*";
			if($params->{'hierarchy'} !~ /$regExp/) {
				$params->{'hierarchy'} = 'group_'.$context->{'itemtype'}.','.$params->{'hierarchy'};
			}
		}else {
			$params->{'hierarchy'} = 'group_'.$context->{'itemtype'};
		}
	}
	if($cmd =~ /^browse/) {
		$log->debug("Starting to prepare CLI browse/browsecontext command\n");
		my $menuResult = undef;
		if($cmd eq 'browse') {
			$log->debug("Executing CLI browse command\n");
			$menuResult = getMenuHandler()->getPageItemsForContext($client,$params,undef,0,'cli');	
		}else {
			$log->debug("Executing CLI browsecontext command\n");
			$menuResult = getContextMenuHandler()->getPageItemsForContext($client,$params,$context,0,'cli');	
		}
		prepareCLIBrowseResponse($request,$menuResult->{'items'});
	}elsif($cmd =~ /^play/ || $cmd =~ /^add/ || $cmd =~ /^insert/) {
		$log->debug("Starting to prepare CLI play/add/insert/playcontext/addcontext/insertcontext command\n");
		my $menuResult = undef;
		if($cmd =~ /context$/) {
			$menuResult = getContextMenuHandler()->getPageItem($client,$params,$context,0,'cli');
		}else {
			$menuResult = getMenuHandler()->getPageItem($client,$params,undef,0,'cli');	
		}
		my $addOnly = 0;
		my $insert = 0;
		if($cmd =~ /^add/) {
			$addOnly = 1;
		}elsif($cmd =~ /^insert/) {
			$addOnly = 1;
			$insert = 1;
		}
		if(defined($menuResult)) {
			if($cmd =~ /context$/) {
				getContextMenuHandler()->playAddItem($client,undef,$menuResult,$addOnly,$insert,$context);
			}else {
				getMenuHandler()->playAddItem($client,undef,$menuResult,$addOnly,$insert,undef);
			}
		}
	}elsif($cmd =~ /^mixes/) {
		$log->debug("Starting to prepare CLI mixes command\n");
		$params->{'hierarchy'} =~ s/^(.*)(,.+?)$/$1/;
		my $attr = $2;
		$attr =~ s/^,(.*)$/$1/;
		my $itemid = $params->{$attr};
		my $menuResult = undef;
		$params->{'start'}=0;
		$params->{'itemsperpage'}=100000;
		if($cmd =~ /context$/) {
			$menuResult = getContextMenuHandler()->getPageItemsForContext($client,$params,$context,0,'cli');	
		}else {
			$menuResult = getMenuHandler()->getPageItemsForContext($client,$params,undef,0,'cli');	
		}
		if(defined($menuResult) && defined($menuResult->{'items'})) {
			my $items = $menuResult->{'items'};
			foreach my $item (@$items) {
				if($item->{'itemid'} eq $itemid) {
					if(defined($item->{'mixes'})) {
						my $mixes = $item->{'mixes'};
					  	$request->addResult('count',scalar(@$mixes));
						my $mixno = 0;
						for my $mix (@$mixes) {
						  	$request->addResultLoop('@mixes',$mixno,'mixid',$mix->{'id'});
						  	$request->addResultLoop('@mixes',$mixno,'mixname',$mix->{'name'});
							$mixno++;
						}
					}
					last;
				}
			}
		}
	}elsif($cmd =~ /^mix/) {
		$log->debug("Starting to prepare CLI mix command\n");
		if($cmd =~ /context$/) {
			executeMix($client,$params,$context,'cli');
		}else {
			executeMix($client,$params,undef,'cli');
		}
	}
	$request->setStatusDone();
	$log->debug("Exiting cliHandler\n");
}

sub prepareCLIBrowseResponse {
	my $request = shift;
	my $items = shift;

  	my $count = scalar(@$items);
  	$request->addResult('count',$count);

	$count = 0;
	foreach my $item (@$items) {
		if(defined($item->{'contextid'})) {
			$request->addResultLoop('@items', $count,'level', $item->{'contextid'});
		}else {
			$request->addResultLoop('@items', $count,'level', $item->{'id'});
		}
		$request->addResultLoop('@items', $count,'itemid', $item->{'itemid'});
		if(defined($item->{'itemvalue'})) {
			$request->addResultLoop('@items', $count,'itemname', $item->{'itemvalue'});
		}else {
			$request->addResultLoop('@items', $count,'itemname', $item->{'itemname'});
		}
		if(defined($item->{'itemtype'})) {
			$request->addResultLoop('@items', $count,'itemtype', $item->{'itemtype'});
			$request->addResultLoop('@items', $count,'itemcontext', $item->{'itemtype'});
		}elsif($item->{'id'} =~ /^group_/) {
			$request->addResultLoop('@items', $count,'itemtype', 'group');
		}else {
			$request->addResultLoop('@items', $count,'itemtype', 'custom');
		}
		if(defined($item->{'playtype'}) && $item->{'playtype'} eq 'none') {
			$request->addResultLoop('@items', $count,'itemplayable', '0');
		}else {
			$request->addResultLoop('@items', $count,'itemplayable', '1');
		}
		if(defined($item->{'playtype'}) && $item->{'playtype'} eq 'none') {
			$request->addResultLoop('@items', $count,'itemplayable', '0');
		}else {
			$request->addResultLoop('@items', $count,'itemplayable', '1');
		}
		if(defined($item->{'mixes'})) {
		  	$request->addResultLoop('@items',$count,'itemmixable','1');
		}else {
		  	$request->addResultLoop('@items',$count,'itemmixable','0');
		}
		$count++;
	}
}

sub readBrowseConfiguration {
	my $client = shift;

	my $itemConfiguration = getConfigManager()->readItemConfiguration($client,undef,undef,1,1);
	my $localBrowseMenus = $itemConfiguration->{'menus'};
	$templates = $itemConfiguration->{'templates'};

	my @menus = ();
	getMenuHandler()->setMenuItems($localBrowseMenus);
	$browseMenusFlat = $localBrowseMenus;
	$globalMixes = $itemConfiguration->{'mixes'};
	getMenuHandler()->setGlobalMixes($globalMixes);
	
	my $value = 'plugins/CustomBrowse/custombrowse_list.html';
	if (!grep(/CustomBrowse/, Slim::Utils::PluginManager->enabledPlugins($client))) {
		$value = undef;
	}
	delSlimserverWebMenus();
	delSlimserverPlayerMenus();
	addWebMenus($client,$value);
	addPlayerMenus($client);
	addJivePlayerMenus($client);
	return $browseMenusFlat;
}

sub readContextBrowseConfiguration {
	my $client = shift;

	my $itemConfiguration = getContextConfigManager()->readItemConfiguration($client,undef,undef,1,1);
	my $localBrowseMenus = $itemConfiguration->{'menus'};
	$templates = $itemConfiguration->{'templates'};

	my @menus = ();
	getContextMenuHandler()->setMenuItems($localBrowseMenus);
	$contextBrowseMenusFlat = $localBrowseMenus;
	if(!defined($globalMixes)) {
		readBrowseConfiguration($client);
	}
	getContextMenuHandler()->setGlobalMixes($globalMixes);
	return $contextBrowseMenusFlat;
}

sub itemFormatPath {
        my $self = shift;
        my $client = shift;
        my $item = shift;
	if($item->{'itemname'} =~ /^file:\/\//i) {
		my $path = Slim::Utils::Misc::pathFromFileURL($item->{'itemname'});
		return Slim::Utils::Unicode::utf8decode($path,'utf8')
	}else {
		return $item->{'itemname'};
	}
}

sub getMultiLibraryMenus {
	my $client = shift;
	return getMultiLibraryInformation($client,getConfigManager(),getMenuHandler());
}

sub getMultiLibraryContextMenus {
	my $client = shift;
	return getMultiLibraryInformation($client,getContextConfigManager(),getContextMenuHandler());
}

sub getMultiLibraryInformation {
	my $client = shift;
	my $cfgMgr = shift;
	my $menuHandler = shift;

	my $itemConfiguration = $cfgMgr->readItemConfiguration($client,1,'Plugins::MultiLibrary::Plugin');
    	$templates = $itemConfiguration->{'templates'};
	my $localBrowseMenus = $itemConfiguration->{'menus'};
	foreach my $menu (keys %$localBrowseMenus) {
		$menuHandler->copyKeywords(undef,$localBrowseMenus->{$menu});
	}
    
	my @result = ();
	for my $menuKey (keys %$localBrowseMenus) {
		my $menu = $localBrowseMenus->{$menuKey};
		if(defined($menu->{'simple'})) {
			if($menu->{'librarysupported'}) {
				my $xml = $cfgMgr->webAdminMethods->loadTemplateValues($client,$menuKey,$localBrowseMenus->{$menuKey});
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
					if(!$found && ($tp->{'id'} eq 'library' || $tp->{'id'} eq 'menuname' || $tp->{'id'} eq 'menugroup' || $tp->{'id'} eq 'includedclients' || $tp->{'id'} eq 'excludedclients' || $tp->{'id'} eq 'activelibrary' || $tp->{'id'} eq 'contextlibrary')) {
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
					}elsif($p->{'id'} eq 'contextlibrary') {
						my @values = ();
						push @values,'{contextlibrary}';
						$p->{'value'} = \@values;
					}elsif($p->{'id'} eq 'activelibrary') {
						my @values = ();
						push @values,'{activelibrary}';
						$p->{'value'} = \@values;
					}elsif($p->{'id'} eq 'objecttype') {
						my $currentValues = $p->{'value'};
						my $objecttype = undef;
						if(defined($currentValues) && scalar(@$currentValues)>0) {
							$objecttype = 'library'.$currentValues->[0];
						}else {
							$objecttype = 'library'
						}
						my @values = ();
						push @values,$objecttype;
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

sub addSQLError {
	my $error = shift;
	$sqlerrors .= $error;
}

1;

__END__
