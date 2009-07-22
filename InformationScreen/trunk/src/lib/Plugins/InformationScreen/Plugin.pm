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
	Slim::Control::Request::addDispatch(['informationscreen','items','_start','_itemsPerResponse'], [1, 1, 1, \&jiveItemsHandler]);

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

sub getCurrentScreen {
	my $client = shift;
	if(! defined $screens) {
		initScreens($client);
	}

	for my $key (keys %$screens) {
		return $screens->{$key};
	}
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

	my $listRef = $currentScreen->{'items'}->{'item'};

  	my $start = $request->getParam('_start') || 0;
	my $itemsPerResponse = $request->getParam('_itemsPerResponse') || scalar(@$listRef);

	my $cnt = 0;
	my $offsetCount = 0;
	foreach my $item (@$listRef) {
		if($cnt>=$start && $offsetCount<$itemsPerResponse) {
			$request->addResultLoop('item_loop',$offsetCount,'align',$item->{'align'});
			if($item->{'type'} eq 'titleformat') {
				my $song = Slim::Player::Playlist::song($client);
				my $text = Slim::Music::Info::displayText($client,$song,$item->{'data'});
				$request->addResultLoop('item_loop',$offsetCount,'text',$text);
			}elsif($item->{'type'} eq 'text') {
				$request->addResultLoop('item_loop',$offsetCount,'text',$item->{'data'});
			}elsif($item->{'type'} eq 'image') {
				$request->addResultLoop('item_loop',$offsetCount,'icon',$item->{'data'});
			}elsif($item->{'type'} eq 'icon') {
				$request->addResultLoop('item_loop',$offsetCount,'icon',$item->{'data'});
			}

			$offsetCount++;
		}
		$cnt++;
	}

	$request->addResult('offset',$start);
	$request->addResult('count',$cnt);
	$request->addResult('layout',$currentScreen->{'items'}->{'layout'});

	$request->setStatusDone();
	$log->debug("Exiting jiveItemsHandler");
}

sub initScreens {
	my $client = shift;

	my $itemConfiguration = getConfigManager()->readItemConfiguration($client,1);

	my $localScreens = $itemConfiguration->{'screens'};

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
