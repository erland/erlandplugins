# 			ConfigManager::Main module
#
#    Copyright (c) 2007-2014 Erland Isaksson (erland_i@hotmail.com)
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

package Plugins::CustomLibraries::ConfigManager::Main;

use strict;

use base qw(Slim::Utils::Accessor);

use Plugins::CustomLibraries::ConfigManager::TemplateParser;
use Plugins::CustomLibraries::ConfigManager::ContentParser;
use Plugins::CustomLibraries::ConfigManager::TemplateContentParser;
use Plugins::CustomLibraries::ConfigManager::PluginLoader;
use Plugins::CustomLibraries::ConfigManager::DirectoryLoader;
use Plugins::CustomLibraries::ConfigManager::ParameterHandler;
use Plugins::CustomLibraries::ConfigManager::LibraryWebAdminMethods;
use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);
use Slim::Utils::Prefs;

__PACKAGE__->mk_accessor( rw => qw(logHandler pluginPrefs pluginId pluginVersion contentDirectoryHandler templateContentDirectoryHandler templateDirectoryHandler templateDataDirectoryHandler contentPluginHandler templatePluginHandler parameterHandler templateParser contentParser templateContentParser webAdminMethods addSqlErrorCallback templates items) );

my $prefs = preferences('plugin.customlibraries');
my $driver;

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new();
	$self->logHandler($parameters->{'logHandler'});
	$self->pluginPrefs($parameters->{'pluginPrefs'});
	$self->pluginId($parameters->{'pluginId'});
	$self->pluginVersion($parameters->{'pluginVersion'});
	$self->addSqlErrorCallback($parameters->{'addSqlErrorCallback'});

	my ($source,$username,$password);
	($driver,$source,$username,$password) = Slim::Schema->sourceInformation;

	$self->init();
	return $self;
}

sub init {
	my $self = shift;
		my %parserParameters = (
			'pluginId' => $self->pluginId,
			'pluginVersion' => $self->pluginVersion,
			'logHandler' => $self->logHandler,
			'cacheName' => "PluginCache/CustomLibraries",
			'utf8filenames' => $prefs->get('utf8filenames')
		);
		$parserParameters{'cachePrefix'} = "PluginCache/CustomLibraries/Templates";
		$self->templateParser(Plugins::CustomLibraries::ConfigManager::TemplateParser->new(\%parserParameters));
		$parserParameters{'cachePrefix'} = "PluginCache/CustomLibraries/Libraries";
		$self->contentParser(Plugins::CustomLibraries::ConfigManager::ContentParser->new(\%parserParameters));

		my %parameters = (
			'logHandler' => $self->logHandler,
			'criticalErrorCallback' => $self->addSqlErrorCallback,
			'parameterPrefix' => 'itemparameter'
		);
		$self->parameterHandler(Plugins::CustomLibraries::ConfigManager::ParameterHandler->new(\%parameters));

		my %directoryHandlerParameters = (
			'logHandler' => $self->logHandler,
			'cacheName' => "PluginCache/CustomLibraries",
			'cachePrefix' => "PluginCache/CustomLibraries/Files",
		);
		$directoryHandlerParameters{'extension'} = "cl.xml";
		$directoryHandlerParameters{'parser'} = $self->contentParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = undef;
		$self->contentDirectoryHandler(Plugins::CustomLibraries::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$directoryHandlerParameters{'extension'} = "xml";
		$directoryHandlerParameters{'identifierExtension'} = "xml";
		$directoryHandlerParameters{'parser'} = $self->templateParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = 1;
		$self->templateDirectoryHandler(Plugins::CustomLibraries::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$directoryHandlerParameters{'extension'} = "template";
		$directoryHandlerParameters{'identifierExtension'} = "xml";
		$directoryHandlerParameters{'parser'} = $self->contentParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = 1;
		$self->templateDataDirectoryHandler(Plugins::CustomLibraries::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		my %pluginHandlerParameters = (
			'logHandler' => $self->logHandler,
			'pluginId' => $self->pluginId,
			'pluginVersion' => $self->pluginVersion,
		);

		$pluginHandlerParameters{'listMethod'} = "getCustomLibrariesTemplates";
		$pluginHandlerParameters{'dataMethod'} = "getCustomLibrariesTemplateData";
		$pluginHandlerParameters{'contentType'} = "template";
		$pluginHandlerParameters{'contentParser'} = $self->templateParser;
		$pluginHandlerParameters{'templateContentParser'} = undef;
		$self->templatePluginHandler(Plugins::CustomLibraries::ConfigManager::PluginLoader->new(\%pluginHandlerParameters));

		$parserParameters{'templatePluginHandler'} = $self->templatePluginHandler;
		$parserParameters{'cachePrefix'} = "PluginCache/CustomLibraries/Libraries";
		$self->templateContentParser(Plugins::CustomLibraries::ConfigManager::TemplateContentParser->new(\%parserParameters));

		$directoryHandlerParameters{'extension'} = "cl.values.xml";
		$directoryHandlerParameters{'parser'} = $self->templateContentParser;
		$directoryHandlerParameters{'includeExtensionInIdentifier'} = undef;
		$self->templateContentDirectoryHandler(Plugins::CustomLibraries::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

		$pluginHandlerParameters{'listMethod'} = "getCustomLibrariesLibraries";
		$pluginHandlerParameters{'dataMethod'} = "getCustomLibrariesLibraryData";
		$pluginHandlerParameters{'contentType'} = "library";
		$pluginHandlerParameters{'contentParser'} = $self->contentParser;
		$pluginHandlerParameters{'templateContentParser'} = $self->templateContentParser;
		$self->contentPluginHandler(Plugins::CustomLibraries::ConfigManager::PluginLoader->new(\%pluginHandlerParameters));

		$self->initWebAdminMethods();
}
sub initWebAdminMethods {
	my $self = shift;

	my %webTemplates = (
		'webEditItems' => 'plugins/CustomLibraries/customlibraries_list.html',
		'webEditItem' => 'plugins/CustomLibraries/webadminmethods_edititem.html',
		'webEditSimpleItem' => 'plugins/CustomLibraries/webadminmethods_editsimpleitem.html',
		'webNewItem' => 'plugins/CustomLibraries/webadminmethods_newitem.html',
		'webNewSimpleItem' => 'plugins/CustomLibraries/webadminmethods_newsimpleitem.html',
		'webNewItemParameters' => 'plugins/CustomLibraries/webadminmethods_newitemparameters.html',
		'webNewItemTypes' => 'plugins/CustomLibraries/webadminmethods_newitemtypes.html',
	);

	my @itemDirectories = ();
	my @templateDirectories = ();
	my $dir = catdir(Slim::Utils::OSDetect::dirsFor('prefs'), 'customlibraries');
	if (defined $dir && -d $dir) {
		push @itemDirectories,$dir
	}
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		if( -d catdir($plugindir,"CustomLibraries","Libraries")) {
			push @itemDirectories, catdir($plugindir,"CustomLibraries","Libraries")
		}
		if( -d catdir($plugindir,"CustomLibraries","Templates")) {
			push @templateDirectories, catdir($plugindir,"CustomLibraries","Templates")
		}
	}
	my %webAdminMethodsParameters = (
		'pluginId' => $self->pluginId,
		'pluginVersion' => $self->pluginVersion,
		'pluginPrefs' => $self->pluginPrefs,
		'extension' => 'cl.xml',
		'simpleExtension' => 'cl.values.xml',
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
		'customItemDirectory' => catdir(Slim::Utils::OSDetect::dirsFor('prefs'), 'customlibraries'),
		'webCallbacks' => $self,
		'webTemplates' => \%webTemplates,
		'utf8filenames' => $prefs->get('utf8filenames'),
	);
	$self->webAdminMethods(Plugins::CustomLibraries::ConfigManager::LibraryWebAdminMethods->new(\%webAdminMethodsParameters));

}

sub readTemplateConfiguration {
	my $self = shift;
	my $client = shift;
	
	my %templates = ();
	my %globalcontext = ();
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		$self->logHandler->debug("Checking for dir: ".catdir($plugindir,"CustomLibraries","Templates")."\n");
		next unless -d catdir($plugindir,"CustomLibraries","Templates");
		$globalcontext{'source'} = 'builtin';
		$self->templateDirectoryHandler()->readFromDir($client,catdir($plugindir,"CustomLibraries","Templates"),\%templates,\%globalcontext);
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
	
	my $dir = catdir(Slim::Utils::OSDetect::dirsFor('prefs'), 'customlibraries');
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
		$self->logHandler->debug("Checking for dir: ".catdir($plugindir,"CustomLibraries","Menus")."\n");
		if( -d catdir($plugindir,"CustomLibraries","Libraries")) {
			$self->contentDirectoryHandler()->readFromDir($client,catdir($plugindir,"CustomLibraries","Libraries"),\%localItems,\%globalcontext);
			$self->templateContentDirectoryHandler()->readFromDir($client,catdir($plugindir,"CustomLibraries","Libraries"),\%localItems, \%globalcontext);
		}
	}
	$self->logHandler->debug("Checking for dir: $dir\n");
	if (!defined $dir || !-d $dir) {
		$self->logHandler->debug("Skipping configuration scan - directory is undefined\n");
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
		'libraries' => \%localItems,
		'templates' => $self->templates
	);
	return \%result;
}
sub postProcessItem {
	my $item = shift;
	
	if(defined($item->{'name'})) {
		if($driver eq 'SQLite') {
			$item->{'name'} =~ s/\'\'/\'/g;
		}else {
			$item->{'name'} =~ s/\\\\/\\/g;
			$item->{'name'} =~ s/\\\"/\"/g;
			$item->{'name'} =~ s/\\\'/\'/g;
		}
	}
}

sub changedItemConfiguration {
        my ($self, $client, $params) = @_;
	Plugins::CustomLibraries::Plugin::initLibraries($client);
	Plugins::CustomLibraries::Plugin::refreshLibraries();
	#if(UNIVERSAL::can("Plugins::CustomBrowse::Plugin","readBrowseConfiguration")) {
	#	no strict 'refs';
	#	eval { &{"Plugins::CustomBrowse::Plugin::readBrowseConfiguration"}($client) };
	#	use strict 'refs';
	#}
}

sub changedTemplateConfiguration {
        my ($self, $client, $params) = @_;
	$self->readTemplateConfiguration($client);
}

sub webEditItems {
        my ($self, $client, $params) = @_;
	return Plugins::CustomLibraries::Plugin::handleWebList($client,$params);
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
