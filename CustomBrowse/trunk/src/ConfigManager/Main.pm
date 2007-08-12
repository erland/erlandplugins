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

package Plugins::CustomBrowse::ConfigManager::Main;

use strict;

use base 'Class::Data::Accessor';

use Plugins::CustomBrowse::ConfigManager::TemplateParser;
use Plugins::CustomBrowse::ConfigManager::MixParser;
use Plugins::CustomBrowse::ConfigManager::ContentParser;
use Plugins::CustomBrowse::ConfigManager::TemplateContentParser;
use Plugins::CustomBrowse::ConfigManager::PluginLoader;
use Plugins::CustomBrowse::ConfigManager::DirectoryLoader;
use Plugins::CustomBrowse::ConfigManager::ParameterHandler;
use Plugins::CustomBrowse::ConfigManager::MenuWebAdminMethods;
use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_classaccessors( qw(debugCallback errorCallback pluginId pluginVersion downloadApplicationId supportDownloadError contentDirectoryHandler templateContentDirectoryHandler mixDirectoryHandler templateDirectoryHandler templateDataDirectoryHandler contentPluginHandler mixPluginHandler templatePluginHandler parameterHandler templateParser contentParser mixParser templateContentParser webAdminMethods addSqlErrorCallback templates items) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = {
		'debugCallback' => $parameters->{'debugCallback'},
		'errorCallback' => $parameters->{'errorCallback'},
		'pluginId' => $parameters->{'pluginId'},
		'downloadApplicationId' => $parameters->{'downloadApplicationId'},
		'pluginVersion' => $parameters->{'pluginVersion'},
		'supportDownloadError' => $parameters->{'supportDownloadError'},
		'addSqlErrorCallback' => $parameters->{'addSqlErrorCallback'}
	};

	$self->{'contentDirectoryHandler'} = undef;
	$self->{'templateContentDirectoryHandler'} = undef;
	$self->{'mixDirectoryHandler'} = undef;
	$self->{'templateDirectoryHandler'} = undef;
	$self->{'templateDataDirectoryHandler'} = undef;
	$self->{'contentPluginHandler'} = undef;
	$self->{'mixPluginHandler'} = undef;
	$self->{'templatePluginHandler'} = undef;
	$self->{'parameterHandler'} = undef;
	
	$self->{'templateParser'} = undef;
	$self->{'contentParser'} = undef;
	$self->{'mixParser'} = undef;
	$self->{'templateContentParser'} = undef;

	$self->{'webAdminMethods'} = undef;

	$self->{'templates'} = undef;
	$self->{'items'} = undef;

	bless $self,$class;
	$self->init();
	return $self;
}

sub init {
	my $self = shift;
		my %parserParameters = (
			'pluginId' => $self->pluginId,
			'pluginVersion' => $self->pluginVersion,
			'debugCallback' => $self->debugCallback,
			'errorCallback' => $self->errorCallback
		);
		$self->templateParser(Plugins::CustomBrowse::ConfigManager::TemplateParser->new(\%parserParameters));
		$self->contentParser(Plugins::CustomBrowse::ConfigManager::ContentParser->new(\%parserParameters));
		$self->mixParser(Plugins::CustomBrowse::ConfigManager::MixParser->new(\%parserParameters));

		my %parameters = (
			'debugCallback' => $self->debugCallback,
			'errorCallback' => $self->errorCallback,
			'criticalErrorCallback' => $self->addSqlErrorCallback,
			'parameterPrefix' => 'itemparameter'
		);
		$self->parameterHandler(Plugins::CustomBrowse::ConfigManager::ParameterHandler->new(\%parameters));

		my %directoryHandlerParameters = (
			'debugCallback' => $self->debugCallback,
			'errorCallback' => $self->errorCallback,
		);
		$directoryHandlerParameters{'extension'} = "cb.xml";
		$directoryHandlerParameters{'parser'} = $self->contentParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = undef;
		$self->contentDirectoryHandler(Plugins::CustomBrowse::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$directoryHandlerParameters{'extension'} = "cb.mix.xml";
		$directoryHandlerParameters{'parser'} = $self->mixParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = undef;
		$self->mixDirectoryHandler(Plugins::CustomBrowse::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$directoryHandlerParameters{'extension'} = "xml";
		$directoryHandlerParameters{'identifierExtension'} = "xml";
		$directoryHandlerParameters{'parser'} = $self->templateParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = 1;
		$self->templateDirectoryHandler(Plugins::CustomBrowse::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$directoryHandlerParameters{'extension'} = "template";
		$directoryHandlerParameters{'identifierExtension'} = "xml";
		$directoryHandlerParameters{'parser'} = $self->contentParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = 1;
		$self->templateDataDirectoryHandler(Plugins::CustomBrowse::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		my %pluginHandlerParameters = (
			'debugCallback' => $self->debugCallback,
			'errorCallback' => $self->errorCallback,
			'pluginId' => $self->pluginId,
		);

		$pluginHandlerParameters{'listMethod'} = "getCustomBrowseMixes";
		$pluginHandlerParameters{'dataMethod'} = undef;
		$pluginHandlerParameters{'contentType'} = "mix";
		$pluginHandlerParameters{'contentParser'} = $self->mixParser;
		$pluginHandlerParameters{'templateContentParser'} = undef;
		$self->mixPluginHandler(Plugins::CustomBrowse::ConfigManager::PluginLoader->new(\%pluginHandlerParameters));

		$pluginHandlerParameters{'listMethod'} = "getCustomBrowseTemplates";
		$pluginHandlerParameters{'dataMethod'} = "getCustomBrowseTemplateData";
		$pluginHandlerParameters{'contentType'} = "template";
		$pluginHandlerParameters{'contentParser'} = $self->templateParser;
		$pluginHandlerParameters{'templateContentParser'} = undef;
		$self->templatePluginHandler(Plugins::CustomBrowse::ConfigManager::PluginLoader->new(\%pluginHandlerParameters));

		$parserParameters{'templatePluginHandler'} = $self->templatePluginHandler;
		$self->templateContentParser(Plugins::CustomBrowse::ConfigManager::TemplateContentParser->new(\%parserParameters));

		$directoryHandlerParameters{'extension'} = "cb.values.xml";
		$directoryHandlerParameters{'parser'} = $self->templateContentParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = undef;
		$self->templateContentDirectoryHandler(Plugins::CustomBrowse::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$pluginHandlerParameters{'listMethod'} = "getCustomBrowseMenus";
		$pluginHandlerParameters{'dataMethod'} = "getCustomBrowseMenuData";
		$pluginHandlerParameters{'contentType'} = "menu";
		$pluginHandlerParameters{'contentParser'} = $self->contentParser;
		$pluginHandlerParameters{'templateContentParser'} = $self->templateContentParser;
		$self->contentPluginHandler(Plugins::CustomBrowse::ConfigManager::PluginLoader->new(\%pluginHandlerParameters));

		$self->initWebAdminMethods();
}

sub initWebAdminMethods {
	my $self = shift;

	my %webTemplates = (
		'webEditItems' => 'plugins/CustomBrowse/webadminmethods_edititems.html',
		'webEditItem' => 'plugins/CustomBrowse/webadminmethods_edititem.html',
		'webEditSimpleItem' => 'plugins/CustomBrowse/webadminmethods_editsimpleitem.html',
		'webNewItem' => 'plugins/CustomBrowse/webadminmethods_newitem.html',
		'webNewSimpleItem' => 'plugins/CustomBrowse/webadminmethods_newsimpleitem.html',
		'webNewItemParameters' => 'plugins/CustomBrowse/webadminmethods_newitemparameters.html',
		'webNewItemTypes' => 'plugins/CustomBrowse/webadminmethods_newitemtypes.html',
		'webDownloadItem' => 'plugins/CustomBrowse/webadminmethods_downloaditem.html',
		'webSaveDownloadedItem' => 'plugins/CustomBrowse/webadminmethods_savedownloadeditem.html',
		'webPublishLogin' => 'plugins/CustomBrowse/webadminmethods_login.html',
		'webPublishRegister' => 'plugins/CustomBrowse/webadminmethods_register.html',
		'webPublishItemParameters' => 'plugins/CustomBrowse/webadminmethods_publishitemparameters.html',
	);

	my @itemDirectories = ();
	my @templateDirectories = ();
	my $dir = Slim::Utils::Prefs::get("plugin_custombrowse_directory");
	if (defined $dir && -d $dir) {
		push @itemDirectories,$dir
	}
	$dir = Slim::Utils::Prefs::get("plugin_custombrowse_template_directory");
	if (defined $dir && -d $dir) {
		push @templateDirectories,$dir
	}
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		if( -d catdir($plugindir,"CustomBrowse","Menus")) {
			push @itemDirectories, catdir($plugindir,"CustomBrowse","Menus")
		}
		if( -d catdir($plugindir,"CustomBrowse","Templates")) {
			push @templateDirectories, catdir($plugindir,"CustomBrowse","Templates")
		}
	}
	my %webAdminMethodsParameters = (
		'pluginId' => $self->pluginId,
		'pluginVersion' => $self->pluginVersion,
		'downloadApplicationId' => $self->downloadApplicationId,
		'extension' => 'cb.xml',
		'simpleExtension' => 'cb.values.xml',
		'debugCallback' => $self->debugCallback,
		'errorCallback' => $self->errorCallback,
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
		'customTemplateDirectory' => Slim::Utils::Prefs::get("plugin_custombrowse_template_directory"),
		'customItemDirectory' => Slim::Utils::Prefs::get("plugin_custombrowse_directory"),
		'supportDownload' => 1,
		'supportDownloadError' => $self->supportDownloadError,
		'webCallbacks' => $self,
		'webTemplates' => \%webTemplates,
		'downloadUrl' => Slim::Utils::Prefs::get("plugin_custombrowse_download_url")
	);
	$self->webAdminMethods(Plugins::CustomBrowse::ConfigManager::MenuWebAdminMethods->new(\%webAdminMethodsParameters));

}
sub readTemplateConfiguration {
	my $self = shift;
	my $client = shift;
	
	my %templates = ();
	my %globalcontext = ();
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		next unless -d catdir($plugindir,"CustomBrowse","Templates");
		$globalcontext{'source'} = 'builtin';
		$self->templateDirectoryHandler()->readFromDir($client,catdir($plugindir,"CustomBrowse","Templates"),\%templates,\%globalcontext);
	}

	$globalcontext{'source'} = 'plugin';
	$self->templatePluginHandler()->readFromPlugins($client,\%templates,undef,\%globalcontext);

	my $templateDir = Slim::Utils::Prefs::get('plugin_custombrowse_template_directory');
	if($templateDir && -d $templateDir) {
		$globalcontext{'source'} = 'custom';
		$self->templateDirectoryHandler()->readFromDir($client,$templateDir,\%templates,\%globalcontext);
	}
	return \%templates;
}

sub readItemConfiguration {
	my $self = shift;
	my $client = shift;
	my $onlyWithLibrarySupport = shift;
	my $excludedPlugins = shift;
	my $storeInCache = shift;
	my $forceRefreshTemplates = shift;
	
	my $dir = Slim::Utils::Prefs::get("plugin_custombrowse_directory");
    	$self->debugCallback->("Searching for item configuration in: $dir\n");
    
	my %localItems = ();
	my %localMixes = ();

	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');

	my %globalcontext = ();
	if(!defined($self->templates) || !$onlyWithLibrarySupport || $forceRefreshTemplates) {
		$self->templates($self->readTemplateConfiguration());
	}
	$globalcontext{'source'} = 'plugin';
	$globalcontext{'templates'} = $self->templates;
	if($onlyWithLibrarySupport) {
		$globalcontext{'onlylibrarysupported'} = 1;
	}

	if(!$onlyWithLibrarySupport) {
		$self->mixPluginHandler->readFromPlugins($client,\%localMixes,$excludedPlugins,\%globalcontext);
	}
	$self->contentPluginHandler->readFromPlugins($client,\%localItems,$excludedPlugins,\%globalcontext);
	for my $plugindir (@pluginDirs) {
		$globalcontext{'source'} = 'builtin';
		if( -d catdir($plugindir,"CustomBrowse","Menus")) {
			if(!$onlyWithLibrarySupport) {
				$self->contentDirectoryHandler()->readFromDir($client,catdir($plugindir,"CustomBrowse","Menus"),\%localItems,\%globalcontext);
			}
			$self->templateContentDirectoryHandler()->readFromDir($client,catdir($plugindir,"CustomBrowse","Menus"),\%localItems, \%globalcontext);
		}
		if(!$onlyWithLibrarySupport) {
			if( -d catdir($plugindir,"CustomBrowse","Mixes")) {
				$self->mixDirectoryHandler()->readFromDir($client,catdir($plugindir,"CustomBrowse","Mixes"),\%localMixes,\%globalcontext);
			}
		}
	}
	if (!defined $dir || !-d $dir) {
		$self->debugCallback->("Skipping custom browse configuration scan - directory is undefined\n");
	}else {
		$globalcontext{'source'} = 'custom';
		if(!$onlyWithLibrarySupport) {
			$self->contentDirectoryHandler()->readFromDir($client,$dir,\%localItems,\%globalcontext);
		}
		$self->templateContentDirectoryHandler()->readFromDir($client,$dir,\%localItems, \%globalcontext);
		if(!$onlyWithLibrarySupport) {
			$self->mixDirectoryHandler()->readFromDir($client,$dir,\%localMixes,\%globalcontext);
		}
	}

	for my $key (keys %localItems) {
		postProcessItem($localItems{$key});
	}

	if($storeInCache) {
		$self->items(\%localItems);
	}

	my %result = (
		'menus' => \%localItems,
		'templates' => $self->templates
	);
	if(!$onlyWithLibrarySupport) {
		$result{'mixes'} = \%localMixes;
	}
	return \%result;
}

sub postProcessItem {
	my $item = shift;
	
	if(defined($item->{'menuname'})) {
		$item->{'menuname'} =~ s/\\\\/\\/g;
		$item->{'menuname'} =~ s/\\\"/\"/g;
		$item->{'menuname'} =~ s/\\\'/\'/g;
	}
	if(defined($item->{'menugroup'})) {
		$item->{'menugroup'} =~ s/\\\\/\\/g;
		$item->{'menugroup'} =~ s/\\\"/\"/g;
		$item->{'menugroup'} =~ s/\\\'/\'/g;
	}
}

sub changedItemConfiguration {
        my ($self, $client, $params) = @_;
#	Plugins::CustomBrowse::Plugin::readBrowseConfiguration($client);
}

sub changedTemplateConfiguration {
        my ($self, $client, $params) = @_;
#	$self->readTemplateConfiguration($client);
}

sub webEditItems {
        my ($self, $client, $params) = @_;
	
	Plugins::CustomBrowse::Plugin::readBrowseConfiguration($client);
	my $items = $self->items;

	my @webitems = ();
	for my $key (keys %$items) {
		my %webitem = ();
		my $item = $items->{$key};
		for my $key (keys %$item) {
			$webitem{$key} = $item->{$key};
		} 
		if(defined($webitem{'menuname'}) && defined($webitem{'menugroup'})) {
			$webitem{'menuname'} = $webitem{'menugroup'}.'/'.$webitem{'menuname'};
		}
		push @webitems,\%webitem;
	}
	@webitems = sort { $a->{'menuname'} cmp $b->{'menuname'} } @webitems;
	return $self->webAdminMethods->webEditItems($client,$params,\@webitems);	
}

sub webEditItem {
        my ($self, $client, $params) = @_;

	if(!defined($self->items)) {
		my $itemConfiguration = $self->readItemConfiguration($client);
		$self->items($itemConfiguration->{'menus'});
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
		$self->items($itemConfiguration->{'menus'});
	}

	return $self->webAdminMethods->webPublishItemParameters($client,$params,$params->{'item'},$self->items->{$params->{'item'}}->{'menuname'},$self->items,$self->templates);	
}

sub webPublishItem {
        my ($self, $client, $params) = @_;

	if(!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}
	if(!defined($self->items)) {
		my $itemConfiguration = $self->readItemConfiguration($client);
		$self->items($itemConfiguration->{'menus'});
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
		$self->items($itemConfiguration->{'menus'});
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
