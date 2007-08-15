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

package Plugins::DatabaseQuery::ConfigManager::Main;

use strict;

use base 'Class::Data::Accessor';

use Plugins::DatabaseQuery::ConfigManager::TemplateParser;
use Plugins::DatabaseQuery::ConfigManager::ContentParser;
use Plugins::DatabaseQuery::ConfigManager::TemplateContentParser;
use Plugins::DatabaseQuery::ConfigManager::PluginLoader;
use Plugins::DatabaseQuery::ConfigManager::DirectoryLoader;
use Plugins::DatabaseQuery::ConfigManager::ParameterHandler;
use Plugins::DatabaseQuery::ConfigManager::QueryWebAdminMethods;
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
			'errorCallback' => $self->errorCallback,
			'utf8filenames' => Slim::Utils::Prefs::get('plugin_DatabaseQuery_utf8filenames')
		);
		$self->templateParser(Plugins::DatabaseQuery::ConfigManager::TemplateParser->new(\%parserParameters));
		$self->contentParser(Plugins::DatabaseQuery::ConfigManager::ContentParser->new(\%parserParameters));

		my %parameters = (
			'debugCallback' => $self->debugCallback,
			'errorCallback' => $self->errorCallback,
			'criticalErrorCallback' => $self->addSqlErrorCallback,
			'parameterPrefix' => 'itemparameter'
		);
		$self->parameterHandler(Plugins::DatabaseQuery::ConfigManager::ParameterHandler->new(\%parameters));

		my %directoryHandlerParameters = (
			'debugCallback' => $self->debugCallback,
			'errorCallback' => $self->errorCallback,
		);
		$directoryHandlerParameters{'extension'} = "dataquery.xml";
		$directoryHandlerParameters{'parser'} = $self->contentParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = undef;
		$self->contentDirectoryHandler(Plugins::DatabaseQuery::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$directoryHandlerParameters{'extension'} = "xml";
		$directoryHandlerParameters{'identifierExtension'} = "xml";
		$directoryHandlerParameters{'parser'} = $self->templateParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = 1;
		$self->templateDirectoryHandler(Plugins::DatabaseQuery::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$directoryHandlerParameters{'extension'} = "template";
		$directoryHandlerParameters{'identifierExtension'} = "xml";
		$directoryHandlerParameters{'parser'} = $self->contentParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = 1;
		$self->templateDataDirectoryHandler(Plugins::DatabaseQuery::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		my %pluginHandlerParameters = (
			'debugCallback' => $self->debugCallback,
			'errorCallback' => $self->errorCallback,
			'pluginId' => $self->pluginId,
		);

		$pluginHandlerParameters{'listMethod'} = "getDatabaseQueryTemplates";
		$pluginHandlerParameters{'dataMethod'} = "getDatabaseQueryTemplateData";
		$pluginHandlerParameters{'contentType'} = "template";
		$pluginHandlerParameters{'contentParser'} = $self->templateParser;
		$pluginHandlerParameters{'templateContentParser'} = undef;
		$self->templatePluginHandler(Plugins::DatabaseQuery::ConfigManager::PluginLoader->new(\%pluginHandlerParameters));

		$parserParameters{'templatePluginHandler'} = $self->templatePluginHandler;
		$self->templateContentParser(Plugins::DatabaseQuery::ConfigManager::TemplateContentParser->new(\%parserParameters));

		$directoryHandlerParameters{'extension'} = "dataquery.values.xml";
		$directoryHandlerParameters{'parser'} = $self->templateContentParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = undef;
		$self->templateContentDirectoryHandler(Plugins::DatabaseQuery::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$pluginHandlerParameters{'listMethod'} = "getDatabaseQueryDataQueries";
		$pluginHandlerParameters{'dataMethod'} = "getDatabaseQueryDataQueryData";
		$pluginHandlerParameters{'contentType'} = "dataquery";
		$pluginHandlerParameters{'contentParser'} = $self->contentParser;
		$pluginHandlerParameters{'templateContentParser'} = $self->templateContentParser;
		$self->contentPluginHandler(Plugins::DatabaseQuery::ConfigManager::PluginLoader->new(\%pluginHandlerParameters));

		$self->initWebAdminMethods();
}
sub initWebAdminMethods {
	my $self = shift;

	my %webTemplates = (
		'webEditItems' => 'plugins/DatabaseQuery/databasequery_list.html',
		'webEditItem' => 'plugins/DatabaseQuery/webadminmethods_edititem.html',
		'webEditSimpleItem' => 'plugins/DatabaseQuery/webadminmethods_editsimpleitem.html',
		'webNewItem' => 'plugins/DatabaseQuery/webadminmethods_newitem.html',
		'webNewSimpleItem' => 'plugins/DatabaseQuery/webadminmethods_newsimpleitem.html',
		'webNewItemParameters' => 'plugins/DatabaseQuery/webadminmethods_newitemparameters.html',
		'webNewItemTypes' => 'plugins/DatabaseQuery/webadminmethods_newitemtypes.html',
		'webDownloadItem' => 'plugins/DatabaseQuery/webadminmethods_downloaditem.html',
		'webSaveDownloadedItem' => 'plugins/DatabaseQuery/webadminmethods_savedownloadeditem.html',
		'webPublishLogin' => 'plugins/DatabaseQuery/webadminmethods_login.html',
		'webPublishRegister' => 'plugins/DatabaseQuery/webadminmethods_register.html',
		'webPublishItemParameters' => 'plugins/DatabaseQuery/webadminmethods_publishitemparameters.html',
	);

	my @itemDirectories = ();
	my @templateDirectories = ();
	my $dir = Slim::Utils::Prefs::get("plugin_databasequery_dataqueries_directory");
	if (defined $dir && -d $dir) {
		push @itemDirectories,$dir
	}
	$dir = Slim::Utils::Prefs::get("plugin_databasequery_template_directory");
	if (defined $dir && -d $dir) {
		push @templateDirectories,$dir
	}
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		if( -d catdir($plugindir,"DatabaseQuery","DataQueries")) {
			push @itemDirectories, catdir($plugindir,"DatabaseQuery","DataQueries")
		}
		if( -d catdir($plugindir,"DatabaseQuery","Templates")) {
			push @templateDirectories, catdir($plugindir,"DatabaseQuery","Templates")
		}
	}
	my %webAdminMethodsParameters = (
		'pluginId' => $self->pluginId,
		'pluginVersion' => $self->pluginVersion,
		'downloadApplicationId' => $self->downloadApplicationId,
		'extension' => 'dataquery.xml',
		'simpleExtension' => 'dataquery.values.xml',
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
		'customTemplateDirectory' => Slim::Utils::Prefs::get("plugin_databasequery_template_directory"),
		'customItemDirectory' => Slim::Utils::Prefs::get("plugin_databasequery_dataqueries_directory"),
		'supportDownload' => 1,
		'supportDownloadError' => $self->supportDownloadError,
		'webCallbacks' => $self,
		'webTemplates' => \%webTemplates,
		'downloadUrl' => Slim::Utils::Prefs::get("plugin_databasequery_download_url"),
		'utf8filenames' => Slim::Utils::Prefs::get('plugin_databasequery_utf8filenames')
	);
	$self->webAdminMethods(Plugins::DatabaseQuery::ConfigManager::QueryWebAdminMethods->new(\%webAdminMethodsParameters));

}

sub readTemplateConfiguration {
	my $self = shift;
	my $client = shift;
	
	my %templates = ();
	my %globalcontext = ();
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		next unless -d catdir($plugindir,"DatabaseQuery","Templates");
		$globalcontext{'source'} = 'builtin';
		$self->templateDirectoryHandler()->readFromDir($client,catdir($plugindir,"DatabaseQuery","Templates"),\%templates,\%globalcontext);
	}

	$globalcontext{'source'} = 'plugin';
	$self->templatePluginHandler()->readFromPlugins($client,\%templates,undef,\%globalcontext);

	my $templateDir = Slim::Utils::Prefs::get('plugin_databasequery_template_directory');
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
	
	my $dir = Slim::Utils::Prefs::get("plugin_databasequery_dataqueries_directory");
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
		if( -d catdir($plugindir,"DatabaseQuery","DataQueries")) {
			$self->contentDirectoryHandler()->readFromDir($client,catdir($plugindir,"DatabaseQuery","DataQueries"),\%localItems,\%globalcontext);
			$self->templateContentDirectoryHandler()->readFromDir($client,catdir($plugindir,"DatabaseQuery","DataQueries"),\%localItems, \%globalcontext);
		}
	}
	if (!defined $dir || !-d $dir) {
		$self->debugCallback->("Skipping custom browse configuration scan - directory is undefined\n");
	}else {
		$globalcontext{'source'} = 'custom';
		$self->contentDirectoryHandler()->readFromDir($client,$dir,\%localItems,\%globalcontext);
		$self->templateContentDirectoryHandler()->readFromDir($client,$dir,\%localItems, \%globalcontext);
	}

	for my $key (keys %localItems) {
		postProcessItem($localItems{$key});
	}
	if($storeInCache) {
		$self->items(\%localItems);
	}

	my %result = (
		'dataqueries' => \%localItems,
		'templates' => $self->templates
	);
	return \%result;
}
sub postProcessItem {
	my $item = shift;
	
	if(defined($item->{'name'})) {
		$item->{'name'} =~ s/\\\\/\\/g;
		$item->{'name'} =~ s/\\\"/\"/g;
		$item->{'name'} =~ s/\\\'/\'/g;
	}
}

sub changedItemConfiguration {
        my ($self, $client, $params) = @_;
	Plugins::DatabaseQuery::Plugin::initDataQueries($client);
}

sub changedTemplateConfiguration {
        my ($self, $client, $params) = @_;
	$self->readTemplateConfiguration($client);
}

sub webEditItems {
        my ($self, $client, $params) = @_;
	return Plugins::DatabaseQuery::Plugin::handleWebList($client,$params);
}

sub webEditItem {
        my ($self, $client, $params) = @_;

	if(!defined($self->items)) {
		my $itemConfiguration = $self->readItemConfiguration($client);
		$self->items($itemConfiguration->{'dataqueries'});
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
		$self->items($itemConfiguration->{'dataqueries'});
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
		$self->items($itemConfiguration->{'dataqueries'});
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
		$self->items($itemConfiguration->{'dataqueries'});
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
