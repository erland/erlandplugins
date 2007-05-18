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

package Plugins::MultiLibrary::ConfigManager::Main;

use strict;

use base 'Class::Data::Accessor';

use Plugins::MultiLibrary::ConfigManager::TemplateParser;
use Plugins::MultiLibrary::ConfigManager::ContentParser;
use Plugins::MultiLibrary::ConfigManager::TemplateContentParser;
use Plugins::MultiLibrary::ConfigManager::PluginLoader;
use Plugins::MultiLibrary::ConfigManager::DirectoryLoader;
use Plugins::MultiLibrary::ConfigManager::ParameterHandler;
use Plugins::MultiLibrary::ConfigManager::LibraryWebAdminMethods;
use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_classaccessors( qw(debugCallback errorCallback pluginId pluginVersion downloadApplicationId supportDownloadError contentDirectoryHandler templateContentDirectoryHandler templateDirectoryHandler templateDataDirectoryHandler contentPluginHandler templatePluginHandler parameterHandler templateParser contentParser templateContentParser webAdminMethods addSqlErrorCallback templates items) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = {
		'debugCallback' => $parameters->{'debugCallback'},
		'errorCallback' => $parameters->{'errorCallback'},
		'pluginId' => $parameters->{'pluginId'},
		'pluginVersion' => $parameters->{'pluginVersion'},
		'downloadApplicationId' => $parameters->{'downloadApplicationId'},
		'supportDownloadError' => $parameters->{'supportDownloadError'},
		'addSqlErrorCallback' => $parameters->{'addSqlErrorCallback'}
	};

	$self->{'contentDirectoryHandler'} = undef;
	$self->{'templateContentDirectoryHandler'} = undef;
	$self->{'templateDirectoryHandler'} = undef;
	$self->{'templateDataDirectoryHandler'} = undef;
	$self->{'contentPluginHandler'} = undef;
	$self->{'templatePluginHandler'} = undef;
	$self->{'parameterHandler'} = undef;
	
	$self->{'templateParser'} = undef;
	$self->{'contentParser'} = undef;
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
		$self->templateParser(Plugins::MultiLibrary::ConfigManager::TemplateParser->new(\%parserParameters));
		$self->contentParser(Plugins::MultiLibrary::ConfigManager::ContentParser->new(\%parserParameters));

		my %parameters = (
			'debugCallback' => $self->debugCallback,
			'errorCallback' => $self->errorCallback,
			'criticalErrorCallback' => $self->addSqlErrorCallback,
			'parameterPrefix' => 'itemparameter'
		);
		$self->parameterHandler(Plugins::MultiLibrary::ConfigManager::ParameterHandler->new(\%parameters));

		my %directoryHandlerParameters = (
			'debugCallback' => $self->debugCallback,
			'errorCallback' => $self->errorCallback,
		);
		$directoryHandlerParameters{'extension'} = "ml.xml";
		$directoryHandlerParameters{'parser'} = $self->contentParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = undef;
		$self->contentDirectoryHandler(Plugins::MultiLibrary::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$directoryHandlerParameters{'extension'} = "xml";
		$directoryHandlerParameters{'identifierExtension'} = "xml";
		$directoryHandlerParameters{'parser'} = $self->templateParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = 1;
		$self->templateDirectoryHandler(Plugins::MultiLibrary::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$directoryHandlerParameters{'extension'} = "template";
		$directoryHandlerParameters{'identifierExtension'} = "xml";
		$directoryHandlerParameters{'parser'} = $self->contentParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = 1;
		$self->templateDataDirectoryHandler(Plugins::MultiLibrary::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		my %pluginHandlerParameters = (
			'debugCallback' => $self->debugCallback,
			'errorCallback' => $self->errorCallback,
			'pluginId' => $self->pluginId,
		);

		$pluginHandlerParameters{'listMethod'} = "getMultiLibraryTemplates";
		$pluginHandlerParameters{'dataMethod'} = "getMultiLibraryTemplateData";
		$pluginHandlerParameters{'contentType'} = "template";
		$pluginHandlerParameters{'contentParser'} = $self->templateParser;
		$pluginHandlerParameters{'templateContentParser'} = undef;
		$self->templatePluginHandler(Plugins::MultiLibrary::ConfigManager::PluginLoader->new(\%pluginHandlerParameters));

		$parserParameters{'templatePluginHandler'} = $self->templatePluginHandler;
		$self->templateContentParser(Plugins::MultiLibrary::ConfigManager::TemplateContentParser->new(\%parserParameters));

		$directoryHandlerParameters{'extension'} = "ml.values.xml";
		$directoryHandlerParameters{'parser'} = $self->templateContentParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = undef;
		$self->templateContentDirectoryHandler(Plugins::MultiLibrary::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$pluginHandlerParameters{'listMethod'} = "getMultiLibraryLibraries";
		$pluginHandlerParameters{'dataMethod'} = "getMultiLibraryLibraryData";
		$pluginHandlerParameters{'contentType'} = "library";
		$pluginHandlerParameters{'contentParser'} = $self->contentParser;
		$pluginHandlerParameters{'templateContentParser'} = $self->templateContentParser;
		$self->contentPluginHandler(Plugins::MultiLibrary::ConfigManager::PluginLoader->new(\%pluginHandlerParameters));

		$self->initWebAdminMethods();
}
sub initWebAdminMethods {
	my $self = shift;

	my %webTemplates = (
		'webEditItems' => 'plugins/MultiLibrary/multilibrary_list.html',
		'webEditItem' => 'plugins/MultiLibrary/webadminmethods_edititem.html',
		'webEditSimpleItem' => 'plugins/MultiLibrary/webadminmethods_editsimpleitem.html',
		'webNewItem' => 'plugins/MultiLibrary/webadminmethods_newitem.html',
		'webNewSimpleItem' => 'plugins/MultiLibrary/webadminmethods_newsimpleitem.html',
		'webNewItemParameters' => 'plugins/MultiLibrary/webadminmethods_newitemparameters.html',
		'webNewItemTypes' => 'plugins/MultiLibrary/webadminmethods_newitemtypes.html',
		'webDownloadItem' => 'plugins/MultiLibrary/webadminmethods_downloaditem.html',
		'webSaveDownloadedItem' => 'plugins/MultiLibrary/webadminmethods_savedownloadeditem.html',
		'webPublishLogin' => 'plugins/MultiLibrary/webadminmethods_login.html',
		'webPublishRegister' => 'plugins/MultiLibrary/webadminmethods_register.html',
		'webPublishItemParameters' => 'plugins/MultiLibrary/webadminmethods_publishitemparameters.html',
	);

	my @itemDirectories = ();
	my @templateDirectories = ();
	my $dir = Slim::Utils::Prefs::get("plugin_multilibrary_library_directory");
	if (defined $dir && -d $dir) {
		push @itemDirectories,$dir
	}
	$dir = Slim::Utils::Prefs::get("plugin_multilibrary_template_directory");
	if (defined $dir && -d $dir) {
		push @templateDirectories,$dir
	}
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		if( -d catdir($plugindir,"MultiLibrary","Libraries")) {
			push @itemDirectories, catdir($plugindir,"MultiLibrary","Libraries")
		}
		if( -d catdir($plugindir,"MultiLibrary","Templates")) {
			push @templateDirectories, catdir($plugindir,"MultiLibrary","Templates")
		}
	}
	my %webAdminMethodsParameters = (
		'pluginId' => $self->pluginId,
		'pluginVersion' => $self->pluginVersion,
		'downloadApplicationId' => $self->downloadApplicationId,
		'extension' => 'ml.xml',
		'simpleExtension' => 'ml.values.xml',
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
		'customTemplateDirectory' => Slim::Utils::Prefs::get("plugin_multilibrary_template_directory"),
		'customItemDirectory' => Slim::Utils::Prefs::get("plugin_multilibrary_library_directory"),
		'supportDownload' => 1,
		'supportDownloadError' => $self->supportDownloadError,
		'webCallbacks' => $self,
		'webTemplates' => \%webTemplates,
		'downloadUrl' => Slim::Utils::Prefs::get("plugin_multilibrary_download_url")
	);
	$self->webAdminMethods(Plugins::MultiLibrary::ConfigManager::LibraryWebAdminMethods->new(\%webAdminMethodsParameters));

}

sub readTemplateConfiguration {
	my $self = shift;
	my $client = shift;
	
	my %templates = ();
	my %globalcontext = ();
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		next unless -d catdir($plugindir,"MultiLibrary","Templates");
		$globalcontext{'source'} = 'builtin';
		$self->templateDirectoryHandler()->readFromDir($client,catdir($plugindir,"MultiLibrary","Templates"),\%templates,\%globalcontext);
	}

	$globalcontext{'source'} = 'plugin';
	$self->templatePluginHandler()->readFromPlugins($client,\%templates,undef,\%globalcontext);

	my $templateDir = Slim::Utils::Prefs::get('plugin_multilibrary_template_directory');
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
	
	my $dir = Slim::Utils::Prefs::get("plugin_multilibrary_library_directory");
    	$self->debugCallback->("Searching for item configuration in: $dir\n");
    
	my %localItems = ();

	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');

	my %globalcontext = ();
	$self->templates($self->readTemplateConfiguration());

	$globalcontext{'source'} = 'plugin';
	$globalcontext{'templates'} = $self->templates;

	$self->contentPluginHandler->readFromPlugins($client,\%localItems,undef,\%globalcontext);
	for my $plugindir (@pluginDirs) {
		$globalcontext{'source'} = 'builtin';
		if( -d catdir($plugindir,"MultiLibrary","Libraries")) {
			$self->contentDirectoryHandler()->readFromDir($client,catdir($plugindir,"MultiLibrary","Libraries"),\%localItems,\%globalcontext);
			$self->templateContentDirectoryHandler()->readFromDir($client,catdir($plugindir,"MultiLibrary","Libraries"),\%localItems, \%globalcontext);
		}
	}
	if (!defined $dir || !-d $dir) {
		$self->debugCallback->("Skipping custom browse configuration scan - directory is undefined\n");
	}else {
		$globalcontext{'source'} = 'custom';
		$self->contentDirectoryHandler()->readFromDir($client,$dir,\%localItems,\%globalcontext);
		$self->templateContentDirectoryHandler()->readFromDir($client,$dir,\%localItems, \%globalcontext);
	}

	if($storeInCache) {
		$self->items(\%localItems);
	}

	my %result = (
		'libraries' => \%localItems,
		'templates' => $self->templates
	);
	return \%result;
}

sub changedItemConfiguration {
        my ($self, $client, $params) = @_;
	Plugins::MultiLibrary::Plugin::initLibraries($client);
	if(Slim::Utils::Prefs::get("plugin_multilibrary_refresh_save")) {
		Plugins::MultiLibrary::Plugin::refreshLibraries();
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
	return Plugins::MultiLibrary::Plugin::handleWebList($client,$params);
}

sub webEditItem {
        my ($self, $client, $params) = @_;

	if(!defined($self->items)) {
		my $itemConfiguration = $self->readItemConfiguration($client);
		$self->items($itemConfiguration->{'libraries'});
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
		$self->items($itemConfiguration->{'libraries'});
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
		$self->items($itemConfiguration->{'libraries'});
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
		$self->items($itemConfiguration->{'libraries'});
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
