# 			ConfigManager::Main module
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

package Plugins::InformationScreen::ConfigManager::Main;

use strict;

use base qw(Slim::Utils::Accessor);

use Plugins::InformationScreen::ConfigManager::TemplateParser;
use Plugins::InformationScreen::ConfigManager::ContentParser;
use Plugins::InformationScreen::ConfigManager::TemplateContentParser;
use Plugins::InformationScreen::ConfigManager::PluginLoader;
use Plugins::InformationScreen::ConfigManager::DirectoryLoader;
use Plugins::InformationScreen::ConfigManager::ParameterHandler;
use Plugins::InformationScreen::ConfigManager::ScreenWebAdminMethods;
use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);
use Slim::Utils::Prefs;

__PACKAGE__->mk_accessor( rw => qw(logHandler pluginPrefs pluginId pluginVersion downloadApplicationId supportDownloadError contentDirectoryHandler templateContentDirectoryHandler templateDirectoryHandler templateDataDirectoryHandler contentPluginHandler templatePluginHandler parameterHandler templateParser contentParser templateContentParser webAdminMethods addSqlErrorCallback templates items downloadVersion) );

my $prefs = preferences('plugin.informationscreen');

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new();
	$self->logHandler($parameters->{'logHandler'});
	$self->pluginPrefs($parameters->{'pluginPrefs'});
	$self->pluginId($parameters->{'pluginId'});
	$self->pluginVersion($parameters->{'pluginVersion'});
	$self->downloadApplicationId($parameters->{'downloadApplicationId'});
	$self->supportDownloadError($parameters->{'supportDownloadError'});
	$self->addSqlErrorCallback($parameters->{'addSqlErrorCallback'});
	$self->downloadVersion($parameters->{'downloadVersion'});

	$self->init();
	return $self;
}

sub init {
	my $self = shift;
		my %parserParameters = (
			'pluginId' => $self->pluginId,
			'pluginVersion' => $self->pluginVersion,
			'logHandler' => $self->logHandler,
			'utf8filenames' => $prefs->get('utf8filenames')
		);
		$parserParameters{'cacheName'} = "FileCache/InformationScreen".$self->pluginVersion."/Templates";
		$self->templateParser(Plugins::InformationScreen::ConfigManager::TemplateParser->new(\%parserParameters));
		$parserParameters{'cacheName'} = "FileCache/InformationScreen".$self->pluginVersion."/Screens";
		$self->contentParser(Plugins::InformationScreen::ConfigManager::ContentParser->new(\%parserParameters));

		my %parameters = (
			'logHandler' => $self->logHandler,
			'criticalErrorCallback' => $self->addSqlErrorCallback,
			'parameterPrefix' => 'itemparameter'
		);
		$self->parameterHandler(Plugins::InformationScreen::ConfigManager::ParameterHandler->new(\%parameters));

		my %directoryHandlerParameters = (
			'logHandler' => $self->logHandler,
			'cacheName' => "FileCache/InformationScreen/".$self->pluginVersion."/Files",
		);
		$directoryHandlerParameters{'extension'} = "screen.xml";
		$directoryHandlerParameters{'parser'} = $self->contentParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = undef;
		$self->contentDirectoryHandler(Plugins::InformationScreen::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$directoryHandlerParameters{'extension'} = "xml";
		$directoryHandlerParameters{'identifierExtension'} = "xml";
		$directoryHandlerParameters{'parser'} = $self->templateParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = 1;
		$self->templateDirectoryHandler(Plugins::InformationScreen::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$directoryHandlerParameters{'extension'} = "template";
		$directoryHandlerParameters{'identifierExtension'} = "xml";
		$directoryHandlerParameters{'parser'} = $self->contentParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = 1;
		$self->templateDataDirectoryHandler(Plugins::InformationScreen::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		my %pluginHandlerParameters = (
			'logHandler' => $self->logHandler,
			'pluginId' => $self->pluginId,
		);

		$pluginHandlerParameters{'listMethod'} = "getInformationScreenTemplates";
		$pluginHandlerParameters{'dataMethod'} = "getInformationScreenTemplateData";
		$pluginHandlerParameters{'contentType'} = "template";
		$pluginHandlerParameters{'contentParser'} = $self->templateParser;
		$pluginHandlerParameters{'templateContentParser'} = undef;
		$self->templatePluginHandler(Plugins::InformationScreen::ConfigManager::PluginLoader->new(\%pluginHandlerParameters));

		$parserParameters{'templatePluginHandler'} = $self->templatePluginHandler;
		$parserParameters{'cacheName'} = "FileCache/InformationScreen".$self->pluginVersion."/Screens";
		$self->templateContentParser(Plugins::InformationScreen::ConfigManager::TemplateContentParser->new(\%parserParameters));

		$directoryHandlerParameters{'extension'} = "screen.values.xml";
		$directoryHandlerParameters{'parser'} = $self->templateContentParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = undef;
		$self->templateContentDirectoryHandler(Plugins::InformationScreen::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$pluginHandlerParameters{'listMethod'} = "getInformationScreenScreens";
		$pluginHandlerParameters{'dataMethod'} = "getInformationScreenScreenData";
		$pluginHandlerParameters{'contentType'} = "screen";
		$pluginHandlerParameters{'contentParser'} = $self->contentParser;
		$pluginHandlerParameters{'templateContentParser'} = $self->templateContentParser;
		$self->contentPluginHandler(Plugins::InformationScreen::ConfigManager::PluginLoader->new(\%pluginHandlerParameters));

		$self->initWebAdminMethods();
}
sub initWebAdminMethods {
	my $self = shift;

	my %webTemplates = (
		'webEditItems' => 'plugins/InformationScreen/webadminmethods_edititems.html',
		'webEditItem' => 'plugins/InformationScreen/webadminmethods_edititem.html',
		'webEditSimpleItem' => 'plugins/InformationScreen/webadminmethods_editsimpleitem.html',
		'webNewItem' => 'plugins/InformationScreen/webadminmethods_newitem.html',
		'webNewSimpleItem' => 'plugins/InformationScreen/webadminmethods_newsimpleitem.html',
		'webNewItemParameters' => 'plugins/InformationScreen/webadminmethods_newitemparameters.html',
		'webNewItemTypes' => 'plugins/InformationScreen/webadminmethods_newitemtypes.html',
		'webDownloadItem' => 'plugins/InformationScreen/webadminmethods_downloaditem.html',
		'webSaveDownloadedItem' => 'plugins/InformationScreen/webadminmethods_savedownloadeditem.html',
		'webPublishLogin' => 'plugins/InformationScreen/webadminmethods_login.html',
		'webPublishRegister' => 'plugins/InformationScreen/webadminmethods_register.html',
		'webPublishItemParameters' => 'plugins/InformationScreen/webadminmethods_publishitemparameters.html',
	);

	my @itemDirectories = ();
	my @templateDirectories = ();
	my $dir = $prefs->get("screen_directory");
	if (defined $dir && -d $dir) {
		push @itemDirectories,$dir
	}
	$dir = $prefs->get("template_directory");
	if (defined $dir && -d $dir) {
		push @templateDirectories,$dir
	}
	my $internalSupportDownloadError = undef;
	if(!defined($dir) || !-d $dir) {
		$internalSupportDownloadError = 'You have to specify a template directory before you can download screen templates';
	}
	if(defined($self->supportDownloadError)) {
		$internalSupportDownloadError = $self->supportDownloadError;
	}
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		if( -d catdir($plugindir,"InformationScreen","Screens")) {
			push @itemDirectories, catdir($plugindir,"InformationScreen","Screens")
		}
		if( -d catdir($plugindir,"InformationScreen","Templates")) {
			push @templateDirectories, catdir($plugindir,"InformationScreen","Templates")
		}
	}
	my %webAdminMethodsParameters = (
		'pluginId' => $self->pluginId,
		'pluginVersion' => $self->pluginVersion,
		'pluginPrefs' => $self->pluginPrefs,
		'downloadApplicationId' => $self->downloadApplicationId,
		'extension' => 'screen.xml',
		'simpleExtension' => 'screen.values.xml',
		'logHandler' => $self->logHandler,
		'contentPluginHandler' => $self->contentPluginHandler,
		'templatePluginHandler' => $self->templatePluginHandler,
		'contentDirectoryHandler' => $self->contentDirectoryHandler,
		'contentTemplateDirectoryHandler' => $self->templateContentDirectoryHandler,
		'templateDirectoryHandler' => $self->templateDirectoryHandler,
		'templateDataDirectoryHandler' => $self->templateDataDirectoryHandler,
		'parameterHandler' => $self->parameterHandler,
		'contentParser' => $self->contentParser,
		'templateDirectories' => \@templateDirectories,
		'itemDirectories' => \@itemDirectories,
		'customTemplateDirectory' => $prefs->get("template_directory"),
		'customItemDirectory' => $prefs->get("screen_directory"),
		'supportDownload' => 1,
		'supportDownloadError' => $internalSupportDownloadError,
		'webCallbacks' => $self,
		'webTemplates' => \%webTemplates,
		'downloadUrl' => $prefs->get("download_url"),
		'utf8filenames' => $prefs->get('utf8filenames'),
		'downloadVersion' => $self->downloadVersion,
	);
	$self->webAdminMethods(Plugins::InformationScreen::ConfigManager::ScreenWebAdminMethods->new(\%webAdminMethodsParameters));

}

sub readTemplateConfiguration {
	my $self = shift;
	my $client = shift;
	
	my %templates = ();
	my %globalcontext = ();
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		$self->logHandler->debug("Checking for dir: ".catdir($plugindir,"InformationScreen","Templates")."\n");
		next unless -d catdir($plugindir,"InformationScreen","Templates");
		$globalcontext{'source'} = 'builtin';
		$self->templateDirectoryHandler()->readFromDir($client,catdir($plugindir,"InformationScreen","Templates"),\%templates,\%globalcontext);
	}

	$globalcontext{'source'} = 'plugin';
	$self->templatePluginHandler()->readFromPlugins($client,\%templates,undef,\%globalcontext);

	my $templateDir = $prefs->get('template_directory');
	$self->logHandler->debug("Checking for dir: $templateDir\n");
	if($templateDir && -d $templateDir) {
		$globalcontext{'source'} = 'custom';
		$self->templateDirectoryHandler()->readFromDir($client,$templateDir,\%templates,\%globalcontext);
	}
	return \%templates;
}

sub readItemConfiguration {
	my $self = shift;
	my $client = shift;
	my $storeInCache = shift;
	
	my $dir = $prefs->get("screen_directory");
    	$self->logHandler->debug("Searching for item configuration in: $dir\n");
    
	my %localItems = ();

	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');

	my %globalcontext = ();
	$self->templates($self->readTemplateConfiguration());

	$globalcontext{'source'} = 'plugin';
	$globalcontext{'templates'} = $self->templates;

	$self->contentPluginHandler->readFromPlugins($client,\%localItems,undef,\%globalcontext);
	for my $plugindir (@pluginDirs) {
		$globalcontext{'source'} = 'builtin';
		$self->logHandler->debug("Checking for dir: ".catdir($plugindir,"InformationScreen","Menus")."\n");
		if( -d catdir($plugindir,"InformationScreen","Screens")) {
			$self->contentDirectoryHandler()->readFromDir($client,catdir($plugindir,"InformationScreen","Screens"),\%localItems,\%globalcontext);
			$self->templateContentDirectoryHandler()->readFromDir($client,catdir($plugindir,"InformationScreen","Screens"),\%localItems, \%globalcontext);
		}
	}
	$self->logHandler->debug("Checking for dir: $dir\n");
	if (!defined $dir || !-d $dir) {
		$self->logHandler->debug("Skipping custom browse configuration scan - directory is undefined\n");
	}else {
		$globalcontext{'source'} = 'custom';
		$self->contentDirectoryHandler()->readFromDir($client,$dir,\%localItems,\%globalcontext);
		$self->templateContentDirectoryHandler()->readFromDir($client,$dir,\%localItems, \%globalcontext);
	}

	for my $key (keys %localItems) {
		$self->postProcessItem($localItems{$key});
	}
	if($storeInCache) {
		$self->items(\%localItems);
	}

	my %result = (
		'screens' => \%localItems,
		'templates' => $self->templates
	);
	return \%result;
}
sub postProcessItem {
	my $self = shift;
	my $item = shift;
	
	if(ref($item) eq 'HASH') {
		foreach my $key (keys %$item) {
			if($key eq 'value' || $key eq 'icon' || $key eq 'name' || $key eq 'preprocessingData') {
				$self->logHandler->debug("Postprocessing $key to replace \\, \" and \'");
				$item->{$key} =~ s/\\\\/\\/g;
				$item->{$key} =~ s/\\\"/\"/g;
				$item->{$key} =~ s/\\\'/\'/g;
				my $thisItem = $item->{$key};
				if($key eq 'value' && ref($thisItem) eq 'HASH' && scalar(keys %$thisItem)==0) {
					$item->{$key} = '';
				}
			}elsif(ref($item->{$key}) eq 'HASH') {
				$self->postProcessItem($item->{$key});
			}elsif(ref($item->{$key}) eq 'ARRAY') {
				my $items = $item->{$key};
				foreach my $it (@$items) {
					$self->postProcessItem($it);
				}
			}
		}
	}
}

sub changedItemConfiguration {
        my ($self, $client, $params) = @_;
	Plugins::InformationScreen::Plugin::initScreens($client);
	if($prefs->get("refresh_save")) {
		Plugins::InformationScreen::Plugin::refreshScreens();
		if(UNIVERSAL::can("Plugins::CustomBrowse::Plugin","readBrowseConfiguration")) {
			no strict 'refs';
			eval { &{"Plugins::CustomBrowse::Plugin::readBrowseConfiguration"}($client) };
			use strict 'refs';
		}
	}
}

sub changedTemplateConfiguration {
        my ($self, $client, $params) = @_;
	$self->readTemplateConfiguration($client);
}

sub webEditItems {
        my ($self, $client, $params) = @_;
	
	Plugins::InformationScreen::Plugin::prepareManagingScreens($client,$params);
	my $items = $self->items;

	my @webitems = ();
	for my $key (keys %$items) {
		my %webitem = ();
		my $item = $items->{$key};
		for my $key (keys %$item) {
			$webitem{$key} = $item->{$key};
		} 
		push @webitems,\%webitem;
	}
	@webitems = sort { $a->{'screenname'} cmp $b->{'screenname'} } @webitems;
	return $self->webAdminMethods->webEditItems($client,$params,\@webitems);	
}

sub webEditItem {
        my ($self, $client, $params) = @_;

	if(!defined($self->items)) {
		my $itemConfiguration = $self->readItemConfiguration($client);
		$self->items($itemConfiguration->{'screens'});
	}
	if(!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}
	
	return $self->webAdminMethods->webEditItem($client,$params,$params->{'item'},$self->items,$self->templates);	
}


sub webDeleteItemType {
        my ($self, $client, $params) = @_;
	return $self->webAdminMethods->webDeleteItemType($client,$params,$params->{'itemtemplate'});	
}


sub webNewItemTypes {
        my ($self, $client, $params) = @_;

	$self->templates($self->readTemplateConfiguration($client));
	
	return $self->webAdminMethods->webNewItemTypes($client,$params,$self->templates);	
}

sub webNewItemParameters {
        my ($self, $client, $params) = @_;

	if(!defined($self->templates) || !defined($self->templates->{$params->{'itemtemplate'}})) {
		$self->templates($self->readTemplateConfiguration($client));
	}
	return $self->webAdminMethods->webNewItemParameters($client,$params,$params->{'itemtemplate'},$self->templates);	
}

sub webLogin {
        my ($self, $client, $params) = @_;

	return $self->webAdminMethods->webPublishLogin($client,$params,$params->{'item'});	
}


sub webPublishItemParameters {
        my ($self, $client, $params) = @_;

	if(!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}
	if(!defined($self->items)) {
		my $itemConfiguration = $self->readItemConfiguration($client);
		$self->items($itemConfiguration->{'screens'});
	}

	return $self->webAdminMethods->webPublishItemParameters($client,$params,$params->{'item'},$self->items->{$params->{'item'}}->{'name'},$self->items,$self->templates);	
}

sub webPublishItem {
        my ($self, $client, $params) = @_;

	if(!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}
	if(!defined($self->items)) {
		my $itemConfiguration = $self->readItemConfiguration($client);
		$self->items($itemConfiguration->{'screens'});
	}

	return $self->webAdminMethods->webPublishItem($client,$params,$params->{'item'},$self->items,$self->templates);	
}

sub webDownloadItems {
        my ($self, $client, $params) = @_;
	return $self->webAdminMethods->webDownloadItems($client,$params);	
}

sub webDownloadNewItems {
        my ($self, $client, $params) = @_;

	if(!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}

	return $self->webAdminMethods->webDownloadNewItems($client,$params,$self->templates);	
}

sub webDownloadItem {
        my ($self, $client, $params) = @_;
	return $self->webAdminMethods->webDownloadItem($client,$params,$params->{'itemtemplate'});	
}

sub webNewItem {
        my ($self, $client, $params) = @_;

	if(!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}
	
	return $self->webAdminMethods->webNewItem($client,$params,$params->{'itemtemplate'},$self->templates);	
}

sub webSaveSimpleItem {
        my ($self, $client, $params) = @_;

	if(!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}
	$params->{'items'} = $self->items;
	
	return $self->webAdminMethods->webSaveSimpleItem($client,$params,$params->{'itemtemplate'},$self->templates);	
}

sub webRemoveItem {
        my ($self, $client, $params) = @_;

	if(!defined($self->items)) {
		my $itemConfiguration = $self->readItemConfiguration($client);
		$self->items($itemConfiguration->{'screens'});
	}
	return $self->webAdminMethods->webDeleteItem($client,$params,$params->{'item'},$self->items);	
}

sub webSaveNewSimpleItem {
        my ($self, $client, $params) = @_;

	if(!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}
	$params->{'items'} = $self->items;
	
	return $self->webAdminMethods->webSaveNewSimpleItem($client,$params,$params->{'itemtemplate'},$self->templates);	
}

sub webSaveNewItem {
        my ($self, $client, $params) = @_;
	$params->{'items'} = $self->items;
	return $self->webAdminMethods->webSaveNewItem($client,$params);	
}

sub webSaveItem {
        my ($self, $client, $params) = @_;
	$params->{'items'} = $self->items;
	return $self->webAdminMethods->webSaveItem($client,$params);	
}

1;

__END__
