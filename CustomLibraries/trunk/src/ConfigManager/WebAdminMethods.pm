# 			ConfigManager::WebAdminMethods module
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

package Plugins::CustomLibraries::ConfigManager::WebAdminMethods;

use strict;
use base qw(Slim::Utils::Accessor);

use Slim::Utils::Prefs;
use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use POSIX qw(ceil);
use File::Spec::Functions qw(:ALL);
use File::Slurp;
use XML::Simple;
use Data::Dumper;
use DBI qw(:sql_types);
use FindBin qw($Bin);
use HTML::Entities;
use Scalar::Util qw(blessed);
use Data::Dumper;

__PACKAGE__->mk_accessor( rw => qw(logHandler pluginPrefs pluginId pluginVersion extension simpleExtension contentPluginHandler templatePluginHandler contentDirectoryHandler contentTemplateDirectoryHandler templateDirectoryHandler templateDataDirectoryHandler parameterHandler contentParser templateDirectories itemDirectories customTemplateDirectory customItemDirectory webCallbacks webTemplates template templateExtension templateDataExtension) );

my $utf8filenames = 1;
my $serverPrefs = preferences('server');
my $driver;

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new($parameters);
	$self->logHandler($parameters->{'logHandler'});
	$self->pluginPrefs($parameters->{'pluginPrefs'});
	$self->pluginId($parameters->{'pluginId'});
	$self->pluginVersion($parameters->{'pluginVersion'});
	$self->extension($parameters->{'extension'});
	$self->simpleExtension($parameters->{'simpleExtension'});
	$self->contentPluginHandler($parameters->{'contentPluginHandler'});
	$self->templatePluginHandler($parameters->{'templatePluginHandler'});
	$self->contentDirectoryHandler($parameters->{'contentDirectoryHandler'});
	$self->contentTemplateDirectoryHandler($parameters->{'contentTemplateDirectoryHandler'});
	$self->templateDirectoryHandler($parameters->{'templateDirectoryHandler'});
	$self->templateDataDirectoryHandler($parameters->{'templateDataDirectoryHandler'});
	$self->parameterHandler($parameters->{'parameterHandler'});
	$self->contentParser($parameters->{'contentParser'});
	$self->templateDirectories($parameters->{'templateDirectories'});
	$self->itemDirectories($parameters->{'itemDirectories'});
	$self->customTemplateDirectory($parameters->{'customTemplateDirectory'});
	$self->customItemDirectory($parameters->{'customItemDirectory'});
	$self->webCallbacks($parameters->{'webCallbacks'});
	$self->webTemplates($parameters->{'webTemplates'});

	if(defined($parameters->{'utf8filenames'})) {
		$utf8filenames = $parameters->{'utf8filenames'};
	}

	$self->templateExtension($parameters->{'templateDirectoryHandler'}->extension);
	$self->templateDataExtension($parameters->{'templateDataDirectoryHandler'}->extension);

	$driver = $serverPrefs->get('dbsource');
	$driver =~ s/dbi:(.*?):(.*)$/$1/;

	if(UNIVERSAL::can("Slim::Schema","sourceInformation")) {
		my ($source,$username,$password);
		($driver,$source,$username,$password) = Slim::Schema->sourceInformation;
	}

	return $self;
}


sub webEditItems {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $items = shift;

        $params->{'pluginWebAdminMethodsItems'} = $items;
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}

        return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webEditItems'}, $params);
}

sub webEditItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $itemId = shift;
	my $itemHash = shift;
	my $templates = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	if(defined($itemId) && defined($itemHash->{$itemId})) {
		if(!defined($itemHash->{$itemId}->{'simple'})) {
			my $data = $self->contentPluginHandler->readDataFromPlugin($client,$itemHash->{$itemId});
			if(!defined($data)) {
				$data = $self->loadItemDataFromAnyDir($itemId);
			}
			if($data) {
				$data = encode_entities($data,"&<>\'\"");
			}
		        $params->{'pluginWebAdminMethodsEditItemData'} = $data;
			$params->{'pluginWebAdminMethodsEditItemFile'} = $itemId.".".$self->extension;
			$params->{'pluginWebAdminMethodsEditItemFileUnescaped'} = unescape($itemId.".".$self->extension);

			return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webEditItem'}, $params);
		}else {
			my $templateData = $self->loadTemplateValues($client,$itemId,$itemHash->{$itemId});

			if(defined($templateData)) {
				my $template = $templates->{lc($templateData->{'id'})};
				if(defined($template)) {
					my %currentParameterValues = ();
					my $templateDataParameters = $templateData->{'parameter'};
					for my $p (@$templateDataParameters) {
						my $values = $p->{'value'};
						if(!defined($values)) {
							my $tmp = $p->{'content'};
							if(defined($tmp)) {
								my @tmpArray = ($tmp);
								$values = \@tmpArray;
							}
						}
						my %valuesHash = ();
						for my $v (@$values) {
							if(ref($v) ne 'HASH') {
								$valuesHash{$v} = $v;
							}
						}
						if(!%valuesHash) {
							$valuesHash{''} = '';
						}
						$currentParameterValues{$p->{'id'}} = \%valuesHash;
					}
					if(defined($template->{'parameter'})) {
						my $parameters = $template->{'parameter'};
						if(ref($parameters) ne 'ARRAY') {
							my @parameterArray = ();
							if(defined($parameters)) {
								push @parameterArray,$parameters;
							}
							$parameters = \@parameterArray;
						}
						my @parametersToSelect = ();
						for my $p (@$parameters) {
							if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
								if(!defined($currentParameterValues{$p->{'id'}})) {
									my $value = $p->{'value'};
									if(defined($value) || ref($value) ne 'HASH') {
										my %valuesHash = ();
										$valuesHash{$value} = $value;
										$currentParameterValues{$p->{'id'}} = \%valuesHash;
									}
								}

								my $useParameter = 1;
								if(defined($p->{'requireplugins'})) {
									$useParameter = isPluginsInstalled($client,$p->{'requireplugins'});
								}
								if($useParameter) {
									$self->parameterHandler->addValuesToTemplateParameter($p,$currentParameterValues{$p->{'id'}});
									push @parametersToSelect,$p;
								}
							}
						}
						$params->{'pluginWebAdminMethodsEditItemParameters'} = \@parametersToSelect;
					}
					$params->{'pluginWebAdminMethodsEditItemTemplate'} = lc($templateData->{'id'});
					$params->{'pluginWebAdminMethodsEditItemFile'} = $itemId.".".$self->simpleExtension;
					$params->{'pluginWebAdminMethodsEditItemFileUnescaped'} = unescape($itemId.".".$self->simpleExtension);
					return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webEditSimpleItem'}, $params);
				}
			}
		}
	}
	return $self->webCallbacks->webEditItems($client,$params);
}

sub webDeleteItemType {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $templateId = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	my $templateDir = $self->customTemplateDirectory;
	if (defined $templateDir && -d $templateDir) {
		my $templateId = $templateId;
		my $path = catfile($templateDir, $templateId);
		if(-e $path) {
			$self->logHandler->debug("Deleting: ".$path."\n");
			unlink($path) or do {
				warn "Unable to delete file: ".$path.": $! \n";
			}
		}
		my $regex1 = "\\.".$self->templateExtension."\$";
		my $regex2 = ".".$self->templateDataExtension;
		$templateId =~ s/$regex1/$regex2/;
		$path = catfile($templateDir, $templateId);
		if(-e $path) {
			$self->logHandler->debug("Deleting: ".$path."\n");
			unlink($path) or do {
				warn "Unable to delete file: ".$path.": $! \n";
			}
		}
	}
	$self->changedTemplateConfiguration($client,$params);
	return $self->webCallbacks->webNewItemTypes($client,$params);
}

sub webNewItemTypes {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $templates = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	my @collections = ();
	my $structuredTemplates = $self->structureItemTypes($templates);

	for my $key (sort keys %$structuredTemplates) {
		my $name = $key;
		if($name eq 'AAA') {
			$name = 'Builtin items';
		}elsif($name eq 'ZZZ') {
			$name = 'Custom or downloaded items';
		}elsif($name =~ /^ZZZ(.+)$/) {
			$name = $1;
		}else {
			$name =~ s/^Plugins:://;
			$name =~ s/::Plugin$//;
			$name .= ' items';
		}
		my %collection = (
			'name' => $name,
			'templates' => $structuredTemplates->{$key}
		);
		push @collections,\%collection;
	}

	$params->{'pluginWebAdminMethodsTemplates'} = \@collections;
	$params->{'pluginWebAdminMethodsPostUrl'} = $self->webTemplates->{'webNewItemParameters'};
	
	return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webNewItemTypes'}, $params);
}

sub webNewItemParameters {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $templateId = shift;
	my $templates = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	$params->{'pluginWebAdminMethodsNewItemTemplate'} = $templateId;
	my $template = $templates->{$templateId};
	if(defined($template->{'parameter'})) {
		my $parameters = $template->{'parameter'};
		if(ref($parameters) ne 'ARRAY') {
			my @parameterArray = ();
			if(defined($parameters)) {
				push @parameterArray,$parameters;
			}
			$parameters = \@parameterArray;
		}
		my @parametersToSelect = ();
		for my $p (@$parameters) {
			if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
				my $useParameter = 1;
				if(defined($p->{'requireplugins'})) {
					$useParameter = isPluginsInstalled($client,$p->{'requireplugins'});
				}
				if($useParameter) {
					$self->parameterHandler->addValuesToTemplateParameter($p);
					push @parametersToSelect,$p;
				}
			}
		}
		$params->{'pluginWebAdminMethodsNewItemParameters'} = \@parametersToSelect;
	}
	return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webNewItemParameters'}, $params);
}


sub webNewItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $templateId = shift;
	my $templates = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	my $templateFile = $templateId;
	my $itemFile = $templateFile;
	my $regex1 = "\\.".$self->templateExtension."\$";
	my $regex2 = ".".$self->templateDataExtension;
	$templateFile =~ s/$regex1/$regex2/;
	$itemFile =~ s/$regex1//;

	my $template = $templates->{$templateId};
	my $menytype = $params->{'itemtype'};

	if(-e catfile($self->customItemDirectory,unescape($itemFile).".".$self->extension) || -e catfile($self->customItemDirectory,unescape($itemFile).".".$self->simpleExtension)) {
		my $i=1;
		while(-e catfile($self->customItemDirectory,unescape($itemFile).$i.".".$self->extension) || -e catfile($self->customItemDirectory,unescape($itemFile).$i.".".$self->simpleExtension)) {
			$i = $i + 1;
		}
		$itemFile .= $i;
	}
	if($menytype eq 'advanced') {
		$itemFile .= ".".$self->extension;
		my %templateParameters = ();
		if(defined($template->{'parameter'})) {
			my $parameters = $template->{'parameter'};
			my @parametersToSelect = ();
			for my $p (@$parameters) {
				if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
					my $useParameter = 1;
					if(defined($p->{'requireplugins'})) {
						$useParameter = isPluginsInstalled($client,$p->{'requireplugins'});
					}
					if($useParameter) {
						$self->parameterHandler->addValuesToTemplateParameter($p);
						my $value = $self->parameterHandler->getValueOfTemplateParameter($params,$p);
#						if(Slim::Utils::Unicode::encodingFromString($value) ne 'utf8') {
#							$value = Slim::Utils::Unicode::latin1toUTF8($value);
#						}
						$templateParameters{$p->{'id'}} = $value;
					}
				}
			}
		}
		addStandardParameters(\%templateParameters);

		my $templateFileData = undef;
		my $doParsing = 1;
		if(defined($template->{lc($self->templatePluginHandler->pluginId).'_plugin_'.$self->templatePluginHandler->contentType})) {
			my $pluginTemplate = $template->{lc($self->templatePluginHandler->pluginId).'_plugin_'.$self->templatePluginHandler->contentType};
			if(defined($pluginTemplate->{'type'}) && $pluginTemplate->{'type'} eq 'final') {
				$doParsing = 0;
			}
			$templateFileData = \$self->templatePluginHandler->readDataFromPlugin($client,$template,\%templateParameters);
		}else {
			$templateFileData = $templateFile;
		}
		my $itemData = undef;
		if($doParsing) {
			$itemData = $self->fillTemplate($templateFileData,\%templateParameters);
		}else {
			$itemData = $templateFileData;
		}
		$itemData = encode_entities($itemData,"&<>\'\"");
        	$params->{'pluginWebAdminMethodsEditItemData'} = $itemData;
		$params->{'pluginWebAdminMethodsEditItemFile'} = $itemFile;
		$params->{'pluginWebAdminMethodsEditItemFileUnescaped'} = unescape($itemFile);
		return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webNewItem'}, $params);
	}else {
		$itemFile .= ".".$self->simpleExtension;
		my %templateParameters = ();
		for my $p (keys %$params) {
			my $regexp = '^'.$self->parameterHandler->parameterPrefix.'_';
			if($p =~ /$regexp/) {
				$templateParameters{$p}=$params->{$p};
			}
		}
		$params->{'pluginWebAdminMethodsNewItemParameters'} = \%templateParameters;
		$params->{'pluginWebAdminMethodsNewItemTemplate'} = $templateId;
		$params->{'pluginWebAdminMethodsEditItemFile'} = $itemFile;
		$params->{'pluginWebAdminMethodsEditItemFileUnescaped'} = unescape($itemFile);
		return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webNewSimpleItem'}, $params);
	}
}

sub webSaveSimpleItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $templateId = shift;
	my $templates = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	my $templateFile = $templateId;
	my $regex1 = "\\.".$self->templateExtension."\$";
	my $regex2 = ".".$self->templateDataExtension;
	$templateFile =~ s/$regex1/$regex2/;

	my $regex3 = "\\.".$self->simpleExtension."\$";
	my $itemFile = $params->{'file'};
	$itemFile =~ s/$regex3//;

	my $template = $templates->{$templateId};
	my $itemtype = $params->{'itemtype'};

	if($itemtype eq 'advanced') {
		$itemFile .= ".".$self->extension;
		my %templateParameters = ();
		if(defined($template->{'parameter'})) {
			my $parameters = $template->{'parameter'};
			if(ref($parameters) ne 'ARRAY') {
				my @parameterArray = ();
				if(defined($parameters)) {
					push @parameterArray,$parameters;
				}
				$parameters = \@parameterArray;
			}
			my @parametersToSelect = ();
			for my $p (@$parameters) {
				if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
					my $useParameter = 1;
					if(defined($p->{'requireplugins'})) {
						$useParameter = isPluginsInstalled($client,$p->{'requireplugins'});
					}
					if($useParameter) {
						if($self->parameterHandler->parameterIsSpecified($params,$p)) {
							$self->parameterHandler->addValuesToTemplateParameter($p);
						}
						my $value = $self->parameterHandler->getValueOfTemplateParameter($params,$p);
#						if(Slim::Utils::Unicode::encodingFromString($value) ne 'utf8') {
#							$value = Slim::Utils::Unicode::latin1toUTF8($value);
#						}
						$templateParameters{$p->{'id'}} = $value;
					}
				}
			}
		}
		addStandardParameters(\%templateParameters);

		my $templateFileData = undef;
		my $doParsing = 1;
		if(defined($template->{lc($self->templatePluginHandler->pluginId).'_plugin_'.$self->templatePluginHandler->contentType})) {
			my $pluginTemplate = $template->{lc($self->templatePluginHandler->pluginId).'_plugin_'.$self->templatePluginHandler->contentType};
			if(defined($pluginTemplate->{'type'}) && $pluginTemplate->{'type'} eq 'final') {
				$doParsing = 0;
			}
			$templateFileData = \$self->templatePluginHandler->readDataFromPlugin($client,$template,\%templateParameters);
		}else {
			$templateFileData = $templateFile;
		}
		my $itemData = undef;
		if($doParsing) {
			$itemData = $self->fillTemplate($templateFileData,\%templateParameters);
		}else {
			$itemData = $templateFileData;
		}
		$itemData = encode_entities($itemData,"&<>\'\"");
        	$params->{'pluginWebAdminMethodsEditItemData'} = $itemData;
		$params->{'pluginWebAdminMethodsEditItemDeleteSimple'} = $params->{'file'};
		$params->{'pluginWebAdminMethodsEditItemFile'} = $itemFile;
		$params->{'pluginWebAdminMethodsEditItemFileUnescaped'} = unescape($itemFile);
	        return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webEditItem'}, $params);
	}else {
		$params->{'pluginWebAdminMethodsError'} = undef;
	
		if (!$params->{'file'}) {
			$params->{'pluginWebAdminMethodsError'} = 'Filename is mandatory';
		}
	
		my $dir = $self->customItemDirectory;
		
		if (!defined $dir || !-d $dir) {
			$params->{'pluginWebAdminMethodsError'} = 'No custom dir configured';
		}
		my $file = unescape($params->{'file'});
		my $url = catfile($dir, $file);
		
		my $error = $self->checkSaveSimpleItem($client,$params);
		if(defined($error)) {
			$params->{'pluginWebAdminMethodsError'} = $error;
		}
		if(!$self->saveSimpleItem($client,$params,$url,$templateId,$templates)) {
		        return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webEditSimpleItem'}, $params);
		}else {
			$self->changedItemConfiguration($client,$params);
			return $self->webCallbacks->webEditItems($client,$params);
		}
	}
}

sub addStandardParameters {
	my $params = shift;

	my $version = $::VERSION;
	if($version =~ /^(\d+)\.(\d+).*/) {
		$params->{'SqueezeCenterVersion'} = "$1.$2";
	}else {
		$params->{'SqueezeCenterVersion'} = $version;
	}
	if($driver eq 'mysql') {
		$params->{'MySQL'} = 1;
		$params->{'RANDOMFUNCTION'} = "rand()";
	}else {
		$params->{'SQLite'} = 1;
		$params->{'RANDOMFUNCTION'} = "random()";
	}
}

sub webDeleteItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $itemId = shift;
	my $items = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	my $dir = $self->customItemDirectory;
	my $file = unescape($itemId);
	if(defined($items->{$itemId}->{'simple'})) {
		$file .= ".".$self->simpleExtension;
	}else {
		$file .= ".".$self->extension;
	}
	my $url = catfile($dir, $file);
	if(defined($dir) && -d $dir && $file && -e $url) {
		unlink($url) or do {
			warn "Unable to delete file: ".$url.": $! \n";
		}
	}		
	$self->changedItemConfiguration($client,$params);
	return $self->webCallbacks->webEditItems($client,$params);
}

sub webSaveNewSimpleItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $templateId = shift;
	my $templates = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	$params->{'pluginWebAdminMethodsError'} = undef;

	if (!$params->{'file'}) {
		$params->{'pluginWebAdminMethodsError'} = 'All fields are mandatory';
	}

	my $dir = $self->customItemDirectory;
	
	if (!defined $dir || !-d $dir) {
		$params->{'pluginWebAdminMethodsError'} = 'No custom dir configured';
	}
	my $file = unescape($params->{'file'});
	my $customFile = $file;
	my $regexp1 = ".".$self->simpleExtension."\$";
	$regexp1 =~ s/\./\\./;
	my $regexp2 = ".".$self->extension;
	$customFile =~ s/$regexp1/$regexp2/;
	my $url = catfile($dir, $file);
	my $customUrl = catfile($dir, $customFile);

	if(!defined($params->{'pluginWebAdminMethodsError'}) && -e $url && !$params->{'overwrite'}) {
		$params->{'pluginWebAdminMethodsError'} = 'Invalid filename, file already exist';
	}
	if(!defined($params->{'pluginWebAdminMethodsError'}) && -e $customUrl && !$params->{'overwrite'}) {
		$params->{'pluginWebAdminMethodsError'} = 'Invalid filename, customized item with this name already exist';
	}

	my $error = $self->checkSaveSimpleItem($client,$params);
	if(defined($error)) {
		$params->{'pluginWebAdminMethodsError'} = $error;
	}
	if(!$self->saveSimpleItem($client,$params,$url,$templateId,$templates)) {
	        return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webNewSimpleItem'}, $params);
	}else {
		if($params->{'overwrite'}) {
			if(-e $customUrl) {
				$self->logHandler->debug("Deleting $url\n");
				unlink($customUrl) or do {
					warn "Unable to delete file: ".$customUrl.": $! \n";
				}
			}
		}
		$self->changedItemConfiguration($client,$params);
		return $self->webCallbacks->webEditItems($client,$params);
	}
}

sub webSaveNewItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	$params->{'pluginWebAdminMethodsError'} = undef;

	if (!$params->{'text'} || !$params->{'file'}) {
		$params->{'pluginWebAdminMethodsError'} = 'All fields are mandatory';
	}

	my $dir = $self->customItemDirectory;
	
	if (!defined $dir || !-d $dir) {
		$params->{'pluginWebAdminMethodsError'} = 'No custom dir configured';
	}
	my $file = unescape($params->{'file'});
	my $url = catfile($dir, $file);
	
	if(!defined($params->{'pluginWebAdminMethodsError'}) && -e $url) {
		$params->{'pluginWebAdminMethodsError'} = 'Invalid filename, file already exist';
	}

	if(!$self->saveItem($client,$params,$url)) {
	        return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webNewItem'}, $params);
	}else {
		$self->changedItemConfiguration($client,$params);
		return $self->webCallbacks->webEditItems($client,$params);
	}
}

sub webSaveItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;

	if(defined($params->{'redirect'})) {
		$params->{'pluginWebAdminMethodsRedirect'} = $params->{'redirect'};
	}
	if(defined($params->{'webadminmethodshandler'})) {
		$params->{'pluginWebAdminMethodsHandler'} = $params->{'webadminmethodshandler'};
	}
	$params->{'pluginWebAdminMethodsError'} = undef;

	if (!$params->{'text'} || !$params->{'file'}) {
		$params->{'pluginWebAdminMethodsError'} = 'All fields are mandatory';
	}

	my $dir = $self->customItemDirectory;
	
	if (!defined $dir || !-d $dir) {
		$params->{'pluginWebAdminMethodsError'} = 'No custom dir configured';
	}
	my $file = unescape($params->{'file'});
	my $url = catfile($dir, $file);
	
	if(!$self->saveItem($client,$params,$url)) {
	        return Slim::Web::HTTP::filltemplatefile($self->webTemplates->{'webEditItem'}, $params);
	}else {
		if(defined($params->{'deletesimple'})) {
			my $file = unescape($params->{'deletesimple'});
			my $url = catfile($dir, $file);
			if(-e $url) {
				unlink($url) or do {
					warn "Unable to delete file: ".$url.": $! \n";
				}
			}
		}
		$self->changedItemConfiguration($client,$params);
		return $self->webCallbacks->webEditItems($client,$params);
	}
}

sub changedItemConfiguration {
	my $self = shift;
	my $client = shift;
	my $params = shift;

	$self->webCallbacks->changedItemConfiguration($client,$params);
}

sub changedTemplateConfiguration {
	my $self = shift;
	my $client = shift;
	my $params = shift;

	$self->webCallbacks->changedTemplateConfiguration($client,$params);
}

sub checkSaveItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;

	return undef;
}

sub checkSaveSimpleItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;

	return undef;
}

sub saveItem 
{
	my ($self, $client, $params, $url) = @_;
	my $fh;

	my $regexp = ".".$self->extension."\$";
	$regexp =~ s/\./\\./;
	if(!($url =~ /$regexp/)) {
		$params->{'pluginWebAdminMethodsError'} = 'Filename must end with .'.$self->extension;
	}
	my $data = undef;
	$data = Slim::Utils::Unicode::utf8decode_locale($params->{'text'});
	$data =~ s/\r+\n/\n/g; # Remove any extra \r character, will create duplicate linefeeds on Windows if not removed
	if(!($params->{'pluginWebAdminMethodsError'}) && defined($self->contentParser)) {
		my %items = ();
		my %globalcontext = (
			'source' => 'custom'
		);
		my $error =  $self->contentParser->parse($client,'test',$data,\%items,\%globalcontext);

		if($error) {
			$params->{'pluginWebAdminMethodsError'} = "Reading configuration: <br>".$error;
		}else {
			my $errorMsg = $self->checkSaveItem($client,$params,$items{'test'});
			if(defined($errorMsg)) {
				$params->{'pluginWebAdminMethodsError'} = $errorMsg;
			}
		}
	}

	if(!($params->{'pluginWebAdminMethodsError'})) {
		$self->logHandler->debug("Opening configuration file: $url\n");
		open($fh,"> $url") or do {
	            $params->{'pluginWebAdminMethodsError'} = "Error saving $url: ".$!;
		};
	}
	if(!($params->{'pluginWebAdminMethodsError'})) {

		$self->logHandler->debug("Writing to file: $url\n");
		my $encoding = Slim::Utils::Unicode::encodingFromString($data);
		if($encoding eq 'utf8') {
			$data = Slim::Utils::Unicode::utf8toLatin1($data);
		}
		print $fh $data;
		$self->logHandler->debug("Writing to file succeeded\n");
		close $fh;
	}
	
	if($params->{'pluginWebAdminMethodsError'}) {
		$params->{'pluginWebAdminMethodsEditItemFile'} = $params->{'file'};
		$params->{'pluginWebAdminMethodsEditItemData'} = encode_entities($params->{'text'});
		$params->{'pluginWebAdminMethodsEditItemFileUnescaped'} = unescape($params->{'pluginWebAdminMethodsEditItemFile'});
		return undef;
	}else {
		return 1;
	}
}

sub saveSimpleItem {
	my ($self, $client, $params, $url,$templateId,$templates) = @_;
	my $fh;

	my $regexp = $self->simpleExtension;
	$regexp =~ s/\./\\./;
	$regexp = ".*".$regexp."\$";
	if(!($url =~ /$regexp/)) {
		$params->{'pluginWebAdminMethodsError'} = "Filename must end with ".$self->simpleExtension;
	}

	if(!($params->{'pluginWebAdminMethodsError'})) {
		$self->logHandler->debug("Opening configuration file: $url\n");
		open($fh,"> $url") or do {
	            $params->{'pluginWebAdminMethodsError'} = "Error saving $url:".$!;
		};
	}
	if(!($params->{'pluginWebAdminMethodsError'})) {
		my $template = $templates->{$templateId};
		my %templateParameters = ();
		my $data = "";
		$data .= "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<".lc($self->pluginId).">\n\t<template>\n\t\t<id>".$templateId."</id>";
		if(defined($template->{'parameter'})) {
			my $parameters = $template->{'parameter'};
			my @parametersToSelect = ();
			if(ref($parameters) ne 'ARRAY') {
				my @parameterArray = ();
				if(defined($parameters)) {
					push @parameterArray,$parameters;
				}
				$parameters = \@parameterArray;
			}
			for my $p (@$parameters) {
				if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
					my $useParameter = 1;
					if(defined($p->{'requireplugins'})) {
						$useParameter = isPluginsInstalled($client,$p->{'requireplugins'});
					}
					if($useParameter) {
						if($self->parameterHandler->parameterIsSpecified($params,$p)) {
							$self->parameterHandler->addValuesToTemplateParameter($p);
						}
						my $value = $self->parameterHandler->getXMLValueOfTemplateParameter($params,$p);
						my $rawValue = '';
						if(defined($p->{'rawvalue'}) && $p->{'rawvalue'}) {
							$rawValue = " rawvalue=\"1\"";
						}
						if($p->{'quotevalue'}) {
							$data .= "\n\t\t<parameter type=\"text\" id=\"".$p->{'id'}."\" quotevalue=\"1\"$rawValue>";
						}else {
							$data .= "\n\t\t<parameter type=\"text\" id=\"".$p->{'id'}."\"$rawValue>";
						}
						$data .= $value.'</parameter>';
					}
				}
			}
		}
		$data .= "\n\t</template>\n</".lc($self->pluginId).">\n";
		my $encoding = Slim::Utils::Unicode::encodingFromString($data);
		if($encoding eq 'utf8') {
			$data = Slim::Utils::Unicode::utf8toLatin1($data);
		}
		$self->logHandler->debug("Writing to file: $url\n");
		print $fh $data;
		$self->logHandler->debug("Writing to file succeeded\n");
		close $fh;
	}
	
	if($params->{'pluginWebAdminMethodsError'}) {
		my $template = $templates->{$templateId};
		if(defined($template->{'parameter'})) {
			my @templateDataParameters = ();
			my $parameters = $template->{'parameter'};
			if(ref($parameters) ne 'ARRAY') {
				my @parameterArray = ();
				if(defined($parameters)) {
					push @parameterArray,$parameters;
				}
				$parameters = \@parameterArray;
			}
			for my $p (@$parameters) {
				my $useParameter = 1;
				if(defined($p->{'requireplugins'})) {
					$useParameter = isPluginsInstalled($client,$p->{'requireplugins'});
				}
				if($useParameter) {
					$self->parameterHandler->addValuesToTemplateParameter($p);
					my $value = $self->parameterHandler->getXMLValueOfTemplateParameter($params,$p);
					if(defined($value) && $value ne '') {
						my $valueData = '<data>'.$value.'</data>';
						my $xmlValue = eval { XMLin($valueData, forcearray => ['value'], keyattr => []) };
						if(defined($xmlValue)) {
							$xmlValue->{'id'} = $p->{'id'};
							push @templateDataParameters,$xmlValue;
						}
					}
				}
			}			
			my %currentParameterValues = ();
			for my $p (@templateDataParameters) {
				my $values = $p->{'value'};
				my %valuesHash = ();
				for my $v (@$values) {
					if(ref($v) ne 'HASH') {
						$valuesHash{$v} = $v;
					}
				}
				if(!%valuesHash) {
					$valuesHash{''} = '';
				}
				$currentParameterValues{$p->{'id'}} = \%valuesHash;
			}

			my @parametersToSelect = ();
			for my $p (@$parameters) {
				if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
					my $useParameter = 1;
					if(defined($p->{'requireplugins'})) {
						$useParameter = isPluginsInstalled($client,$p->{'requireplugins'});
					}
					if($useParameter) {
						$self->parameterHandler->setValueOfTemplateParameter($p,$currentParameterValues{$p->{'id'}});
						push @parametersToSelect,$p;
					}
				}
			}
			my %templateParameters = ();
			for my $p (keys %$params) {
				my $regexp = '^'.$self->parameterHandler->parameterPrefix.'_';
				if($p =~ /$regexp/) {
					$templateParameters{$p}=$params->{$p};
				}
			}

			$params->{'pluginWebAdminMethodsEditItemParameters'} = \@parametersToSelect;
			$params->{'pluginWebAdminMethodsNewItemParameters'} =\%templateParameters;
		}
		$params->{'pluginWebAdminMethodsNewItemTemplate'} = $templateId;
		$params->{'pluginWebAdminMethodsEditItemTemplate'} = $templateId;
		$params->{'pluginWebAdminMethodsEditItemFile'} = $params->{'file'};
		$params->{'pluginWebAdminMethodsEditItemFileUnescaped'} = unescape($params->{'pluginWebAdminMethodsEditItemFile'});
		return undef;
	}else {
		return 1;
	}
}



sub structureItemTypes {
	my $self = shift;
	my $templates = shift;
	
	my %templatesHash = ();
	
	for my $key (keys %$templates) {
		my $plugin = $templates->{$key}->{lc($self->templatePluginHandler->pluginId).'_plugin'};
		if(defined($templates->{$key}->{'customtemplate'})) {
			$plugin = 'ZZZ';
			if(defined($templates->{$key}->{'downloadsection'})) {
				$plugin .= $templates->{$key}->{'downloadsection'};
			}
		}
		if(!defined($plugin)) {
			$plugin = 'AAA';
		}
		my $array = $templatesHash{$plugin};
		if(!defined($array)) {
			my @newArray = ();
			$array = \@newArray;
			$templatesHash{$plugin} = $array;
		}
		push @$array,$templates->{$key};
	}
	for my $key (keys %templatesHash) {
		my $array = $templatesHash{$key};
		my @sortedArray = sort { uc($a->{'name'}) cmp uc($b->{'name'}) } @$array;
		$templatesHash{$key} = \@sortedArray;
	}
	return \%templatesHash;
}

sub loadItemDataFromAnyDir {
	my $self = shift;
	my $itemId = shift;
	my $data = undef;

	my $directories = $self->itemDirectories;
	for my $dir (@$directories) {
		$data = $self->contentDirectoryHandler->readDataFromDir($dir,$itemId);
		if(defined($data)) {
			last;
		}
	}
	return $data;
}

sub loadTemplateFromAnyDir {
	my $self = shift;
	my $templateId = shift;
	my $data = undef;

	my $directories = $self->templateDirectories;
	for my $dir (@$directories) {
		$data = $self->templateDirectoryHandler->readDataFromDir($dir,$templateId);
		if(defined($data)) {
			last;
		}
	}
	return $data;
}

sub loadTemplateDataFromAnyDir {
	my $self = shift;
	my $templateId = shift;
	my $data = undef;

	my $directories = $self->templateDirectories;
	for my $dir (@$directories) {
		$data = $self->templateDataDirectoryHandler->readDataFromDir($dir,$templateId);
		if(defined($data)) {
			last;
		}
	}
	return $data;
}

sub loadTemplateValues {
	my $self = shift;
	my $client = shift;
	my $itemId = shift;
	my $item = shift;
	my $templateData = undef;

	#my $itemItem = $items->{$item};
	my $content  = $self->contentPluginHandler->readDataFromPlugin($client,$item);
	if ( $content ) {
		my $xml = eval { XMLin($content, forcearray => ["parameter","value"], keyattr => []) };
		#$self->logHandler->debug(Dumper($valuesXml));
		if ($@) {
			$self->logHandler->warn("Failed to parse configuration because:\n$@\n");
		}else {
			$templateData = $xml->{'template'};
		}
	}

	my $itemDirectories = $self->itemDirectories;
	for my $dir (@$itemDirectories) {
		$content = $self->contentTemplateDirectoryHandler->readDataFromDir($dir,$itemId);
		if(defined($content)) {
			my $xml = eval { XMLin($content, forcearray => ["parameter","value"], keyattr => []) };
			#$self->logHandler->debug(Dumper($valuesXml));
			if ($@) {
				$self->logHandler->warn("Failed to parse configuration because:\n$@\n");
			}else {
				$templateData = $xml->{'template'};
			}
		}
		if(defined($templateData)) {
			last;
		}
	}
	return $templateData;
}

sub isPluginsInstalled {
	my $client = shift;
	my $pluginList = shift;
	my $enabledPlugin = 1;
	foreach my $plugin (split /,/, $pluginList) {
		if($enabledPlugin) {
			$enabledPlugin = grep(/$plugin/, Slim::Utils::PluginManager->enabledPlugins($client));
		}
	}
	return $enabledPlugin;
}

sub getTemplate {
	my $self = shift;
	if(!defined($self->template)) {
		$self->template(Template->new({
	
	                INCLUDE_PATH => $self->templateDirectories,
	                COMPILE_DIR => catdir( $serverPrefs->get('cachedir'), 'templates' ),
	                FILTERS => {
	                        'string'        => \&Slim::Utils::Strings::string,
	                        'getstring'     => \&Slim::Utils::Strings::getString,
	                        'resolvestring' => \&Slim::Utils::Strings::resolveString,
	                        'nbsp'          => \&nonBreaking,
	                        'uri'           => \&URI::Escape::uri_escape_utf8,
	                        'unuri'         => \&URI::Escape::uri_unescape,
	                        'utf8decode'    => \&Slim::Utils::Unicode::utf8decode,
	                        'utf8encode'    => \&Slim::Utils::Unicode::utf8encode,
	                        'utf8on'        => \&Slim::Utils::Unicode::utf8on,
	                        'utf8off'       => \&Slim::Utils::Unicode::utf8off,
	                        'fileurl'       => \&fileURLFromPath,
	                },
	
	                EVAL_PERL => 1,
	        }));
	}
	return $self->template;
}

sub fileURLFromPath {
	my $path = shift;
	if($utf8filenames) {
		$path = Slim::Utils::Unicode::utf8off($path);
	}else {
		$path = Slim::Utils::Unicode::utf8on($path);
	}
	$path = decode_entities($path);
	if($driver eq 'SQLite') {
		$path =~ s/\'\'/\'/g;
	}else {
		$path =~ s/\\\\/\\/g;
		$path =~ s/\\\"/\"/g;
		$path =~ s/\\\'/\'/g;
	}
	$path = Slim::Utils::Misc::fileURLFromPath($path);
	$path = Slim::Utils::Unicode::utf8on($path);
	if($driver eq 'SQLite') {
		$path =~ s/%/\\%/g;
		$path =~ s/\'/\'\'/g;
	}else {
		$path =~ s/\\/\\\\/g;
		$path =~ s/%/\\%/g;
		$path =~ s/\"/\\\"/g;
		$path =~ s/\'/\\\'/g;
	}
	$path = encode_entities($path,"&<>\'\"");
	return $path;
}

sub fillTemplate {
	my $self = shift;
	my $filename = shift;
	my $params = shift;

	
	my $output = '';
	$params->{'LOCALE'} = 'utf-8';
	my $template = $self->getTemplate();
	if(!$template->process($filename,$params,\$output)) {
		$self->logHandler->warn("ERROR parsing template: ".$template->error()."\n");
	}
	return $output;
}

sub niceFault {
	my $fault = shift;
	if(defined($fault)) {
		$fault =~ s/^.*?Exception.*?:\s*//;
	}
	return $fault;
}

sub getProxy {
	my $self = shift;
        my $proxy = $serverPrefs->get('webproxy');
	if(defined($proxy) && $proxy ne '') {
		$self->logHandler->debug("Connecting through proxy: $proxy\n");
		return proxy => ['http' => 'http://'.$proxy]
	}else {
		return ();
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
1;

__END__
