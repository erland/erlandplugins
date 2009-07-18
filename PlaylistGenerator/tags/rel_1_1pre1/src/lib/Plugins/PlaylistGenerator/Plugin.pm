# 				PlaylistGenerator plugin 
#
#    Copyright (c) 2007 Erland Isaksson (erland_i@hotmail.com)
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

package Plugins::PlaylistGenerator::Plugin;

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
use HTML::Entities;
use FindBin qw($Bin);
use DBI qw(:sql_types);

use Plugins::PlaylistGenerator::Generator;
use Plugins::PlaylistGenerator::Settings;

use Plugins::PlaylistGenerator::ConfigManager::Main;

use Slim::Schema;

my $prefs = preferences('plugin.playlistgenerator');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.playlistgenerator',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_PLAYLISTGENERATOR',
});

$prefs->migrate(1, sub {
	$prefs->set('playlistdefinitions_directory', $serverPrefs->get('playlistdir')  );
	$prefs->set('template_directory',  ''  );
	$prefs->set('download_url',  'http://erland.isaksson.info/datacollection/services/DataCollection'  );
	1;
});
$prefs->setValidate('dir','playlistdefinitions_directory');
$prefs->setValidate('dir','template_directory');

# Information on each clients playlistgenerator
my $htmlTemplate = 'plugins/PlaylistGenerator/playlistgenerator_list.html';
my $playlistDefinitions = undef;
my $sqlerrors = '';
my $soapLiteError = 0;
my $PLUGINVERSION = undef;

my $configManager = undef;

sub getDisplayName {
	return 'PLUGIN_PLAYLISTGENERATOR';
}

sub initPlaylistDefinitions {
	my $client = shift;

	my $itemConfiguration = getConfigManager()->readItemConfiguration($client,1);

	my $localplaylistDefinitions = $itemConfiguration->{'playlistdefinitions'};

	$playlistDefinitions = $localplaylistDefinitions;
}

sub getPlaylistDefinitions {
	my $client = shift;
	if(!defined($playlistDefinitions)) {
		initPlaylistDefinitions($client);
	}
	return $playlistDefinitions;
}

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	Plugins::PlaylistGenerator::Settings->new($class);
	checkDefaults();
}

sub postinitPlugin {
	eval {
		initPlaylistDefinitions();
	};
	if( $@ ) {
	    	$log->warn("Startup error: $@\n");
	}		
}

sub getCustomScanFunctions {
	my @result = ();
	eval "use Plugins::PlaylistGenerator::GenerateModule";
	if( $@ ) { $log->warn("Unable to load GenerateModule: $@\n"); }
	push @result,Plugins::PlaylistGenerator::GenerateModule::getCustomScanFunctions();
	return \@result;
}

sub getConfigManager {
	if(!defined($configManager)) {
		my %parameters = (
			'logHandler' => $log,
			'pluginPrefs' => $prefs,
			'pluginId' => 'PlaylistGenerator',
			'pluginVersion' => $PLUGINVERSION,
			'downloadApplicationId' => 'PlaylistGenerator',
			'addSqlErrorCallback' => \&addSQLError,
			'downloadVersion' => 1,
		);
		$configManager = Plugins::PlaylistGenerator::ConfigManager::Main->new(\%parameters);
	}
	return $configManager;
}

sub webPages {

	my %pages = (
		"PlaylistGenerator/playlistgenerator_list\.(?:htm|xml)"     => \&handleWebList,
		"PlaylistGenerator/playlistgenerator_refreshplaylistdefinitions\.(?:htm|xml)"     => \&handleWebRefreshPlaylistDefinitions,
                "PlaylistGenerator/webadminmethods_edititem\.(?:htm|xml)"     => \&handleWebEditPlaylistDefinition,
                "PlaylistGenerator/webadminmethods_saveitem\.(?:htm|xml)"     => \&handleWebSavePlaylistDefinition,
                "PlaylistGenerator/webadminmethods_savesimpleitem\.(?:htm|xml)"     => \&handleWebSaveSimplePlaylistDefinition,
                "PlaylistGenerator/webadminmethods_savenewitem\.(?:htm|xml)"     => \&handleWebSaveNewPlaylistDefinition,
                "PlaylistGenerator/webadminmethods_savenewsimpleitem\.(?:htm|xml)"     => \&handleWebSaveNewSimplePlaylistDefinition,
                "PlaylistGenerator/webadminmethods_removeitem\.(?:htm|xml)"     => \&handleWebRemovePlaylistDefinition,
                "PlaylistGenerator/webadminmethods_newitemtypes\.(?:htm|xml)"     => \&handleWebNewPlaylistDefinitionTypes,
                "PlaylistGenerator/webadminmethods_newitemparameters\.(?:htm|xml)"     => \&handleWebNewPlaylistDefinitionParameters,
                "PlaylistGenerator/webadminmethods_newitem\.(?:htm|xml)"     => \&handleWebNewPlaylistDefinition,
		"PlaylistGenerator/webadminmethods_login\.(?:htm|xml)"      => \&handleWebLogin,
		"PlaylistGenerator/webadminmethods_downloadnewitems\.(?:htm|xml)"      => \&handleWebDownloadNewPlaylistDefinitions,
		"PlaylistGenerator/webadminmethods_downloaditems\.(?:htm|xml)"      => \&handleWebDownloadPlaylistDefinitions,
		"PlaylistGenerator/webadminmethods_downloaditem\.(?:htm|xml)"      => \&handleWebDownloadPlaylistDefinition,
		"PlaylistGenerator/webadminmethods_publishitemparameters\.(?:htm|xml)"      => \&handleWebPublishPlaylistDefinitionParameters,
		"PlaylistGenerator/webadminmethods_publishitem\.(?:htm|xml)"      => \&handleWebPublishPlaylistDefinition,
		"PlaylistGenerator/webadminmethods_deleteitemtype\.(?:htm|xml)"      => \&handleWebDeletePlaylistDefinitionType,
	);

	for my $page (keys %pages) {
		if(UNIVERSAL::can("Slim::Web::Pages","addPageFunction")) {
			Slim::Web::Pages->addPageFunction($page, $pages{$page});
		}else {
			Slim::Web::HTTP::addPageFunction($page, $pages{$page});
		}
	}

	Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_PLAYLISTGENERATOR' => 'plugins/PlaylistGenerator/playlistgenerator_list.html' });
}


# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	# Pass on the current pref values and now playing info
	if(!defined($params->{'donotrefresh'})) {
		if(defined($params->{'cleancache'}) && $params->{'cleancache'}) {
			my $cache = Slim::Utils::Cache->new("FileCache/PlaylistGenerator");
			$cache->clear();
		}
		initPlaylistDefinitions($client);
	}
	if($params->{'execute'}) {
		my $playlistId = $params->{'file'};
		$playlistId =~ s/\.playlistdefinition\.xml$//;
		$playlistId =~ s/\.playlistdefinition\.values\.xml$//;
		$params->{'type'} = $playlistId;
		return executePlaylistDefinition($client, $params);
	}

	my $name = undef;
	my @webPlaylistDefinitions = ();
	for my $key (keys %$playlistDefinitions) {
		my %webPlaylistDefinition = ();
		my $playlistDefinition = $playlistDefinitions->{$key};
		for my $attr (keys %$playlistDefinition) {
			$webPlaylistDefinition{$attr} = $playlistDefinition->{$attr};
		}
		push @webPlaylistDefinitions,\%webPlaylistDefinition;
	}
	@webPlaylistDefinitions = sort { $a->{'name'} cmp $b->{'name'} } @webPlaylistDefinitions;

	$params->{'pluginPlaylistGeneratorPlaylistDefinitions'} = \@webPlaylistDefinitions;
	$params->{'pluginPlaylistGeneratorVersion'} = $PLUGINVERSION;
	if(defined($params->{'pluginPlaylistGeneratorRedirect'})) {
		return Slim::Web::HTTP::filltemplatefile('plugins/PlaylistGenerator/playlistgenerator_redirect.html', $params);
	}else {
		return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
	}
}

sub handleWebRefreshPlaylistDefinitions {
	my ($client, $params) = @_;

	return handleWebList($client,$params);
}

sub executePlaylistDefinition {
	my ($client, $params, $prepareResponseForSending, $httpClient, $response) = @_;

	initPlaylistDefinitions($client);
	if($params->{'type'}) {
		my $dataQueryId = unescape($params->{'type'});
		if(defined($playlistDefinitions->{$dataQueryId})) {
			my $playlistDefinition = $playlistDefinitions->{$dataQueryId};
			Plugins::PlaylistGenerator::Generator::init($playlistDefinition->{'id'});
			while(Plugins::PlaylistGenerator::Generator::next()) {
				# Lets make sure streaming gets it time
				main::idleStreams();
			}
			Plugins::PlaylistGenerator::Generator::exit();

			my $playlistDir = $serverPrefs->get('playlistdir');
			my $playlistObj = Plugins::PlaylistGenerator::Generator::getPlaylist($playlistDir, $playlistDefinition->{'name'});
			$params->{'pluginPlaylistGeneratorRedirect'} = 'browsedb.html?hierarchy=playlist,playlistTrack&artwork=1&level=1&&playlist.id='.$playlistObj->id;
		}

	}
	# We need to delete the execute flag so it doesn't execute a second time
	delete $params->{'execute'};
	return handleWebList($client,$params);
}

sub handleWebEditPlaylistDefinition {
        my ($client, $params) = @_;
	return getConfigManager()->webEditItem($client,$params);	
}

sub handleWebDeletePlaylistDefinitionType {
	my ($client, $params) = @_;
	return getConfigManager()->webDeleteItemType($client,$params);	
}

sub handleWebNewPlaylistDefinitionTypes {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItemTypes($client,$params);	
}

sub handleWebNewPlaylistDefinitionParameters {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItemParameters($client,$params);	
}

sub handleWebLogin {
	my ($client, $params) = @_;
	return getConfigManager()->webLogin($client,$params);	
}

sub handleWebPublishPlaylistDefinitionParameters {
	my ($client, $params) = @_;
	return getConfigManager()->webPublishItemParameters($client,$params);	
}

sub handleWebPublishPlaylistDefinition {
	my ($client, $params) = @_;
	return getConfigManager()->webPublishItem($client,$params);	
}

sub handleWebDownloadPlaylistDefinitions {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadItems($client,$params);	
}

sub handleWebDownloadNewPlaylistDefinitions {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadNewItems($client,$params);	
}

sub handleWebDownloadPlaylistDefinition {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadItem($client,$params);	
}

sub handleWebNewPlaylistDefinition {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItem($client,$params);	
}

sub handleWebSaveSimplePlaylistDefinition {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveSimpleItem($client,$params);	
}

sub handleWebRemovePlaylistDefinition {
	my ($client, $params) = @_;
	return getConfigManager()->webRemoveItem($client,$params);	
}

sub handleWebSaveNewSimplePlaylistDefinition {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveNewSimpleItem($client,$params);	
}

sub handleWebSaveNewPlaylistDefinition {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveNewItem($client,$params);	
}

sub handleWebSavePlaylistDefinition {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveItem($client,$params);	
}


sub checkDefaults {
	my $prefVal = $prefs->get('playlistdefinitions_directory');
	if (! defined $prefVal || $prefVal eq '') {
		# Default to standard playlist definitions directory
		my $dir=$serverPrefs->get('playlistdir');
		$log->debug("Defaulting playlistdefinitions_directory to:$dir\n");
		$prefs->set('playlistdefinitions_directory', $dir);
	}
	$prefVal = $prefs->get('download_url');
	if (! defined $prefVal) {
		$prefs->set('download_url', 'http://erland.isaksson.info/datacollection/services/DataCollection');
	}
}


sub getCurrentDBH {
	return Slim::Schema->storage->dbh();
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
