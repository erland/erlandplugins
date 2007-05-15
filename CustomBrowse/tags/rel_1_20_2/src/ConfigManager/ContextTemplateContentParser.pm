# 			ConfigManager::ContextTemplateContentParser module
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

package Plugins::CustomBrowse::ConfigManager::ContextTemplateContentParser;

use strict;
use base 'Class::Data::Accessor';
use Plugins::CustomBrowse::ConfigManager::ContextContentParser;
our @ISA = qw(Plugins::CustomBrowse::ConfigManager::ContextContentParser);

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use File::Spec::Functions qw(:ALL);
use File::Slurp;
use FindBin qw($Bin);

__PACKAGE__->mk_classaccessors( qw(templatePluginHandler) );

sub new {
	my $class = shift;
	my $parameters = shift;

	$parameters->{'contentType'} = 'menu';
	my $self = $class->SUPER::new($parameters);
	$self->{'templatePluginHandler'} = $parameters->{'templatePluginHandler'};
	bless $self,$class;
	return $self;
}

sub loadTemplate {
	my $self = shift;
	my $client = shift;
	my $template = shift;
	my $parameters = shift;

	$self->debugCallback->("Searching for template: ".$template->{'id'}."\n");
	my $templateFileData = undef;
	my $doParsing = 1;
	if(defined($template->{lc($self->pluginId).'_plugin_template'})) {
		my $pluginTemplate = $template->{lc($self->pluginId).'_plugin_template'};
		if(defined($pluginTemplate->{'type'}) && $pluginTemplate->{'type'} eq 'final') {
			$doParsing = 0;
		}
		$templateFileData = $self->templatePluginHandler->readDataFromPlugin($client,$template,$parameters);
	}else {
		my $templateFile = $template->{'id'};
		$templateFile =~ s/\.xml$/.template/;
		my $templateDir = Slim::Utils::Prefs::get("plugin_custombrowse_context_template_directory");
		my $path = undef;
		if (defined $templateDir && -d $templateDir && -e catfile($templateDir,$templateFile)) {
			$path = catfile($templateDir,$templateFile);
		}else {
			my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
			for my $plugindir (@pluginDirs) {
				if( -d catdir($plugindir,"CustomBrowse","ContextTemplates") && -e catfile($plugindir,"CustomBrowse","ContextTemplates",$templateFile)) {
					$path = catfile($plugindir,"CustomBrowse","ContextTemplates",$templateFile);
				}
			}
		}
		if(defined($path)) {
			$self->debugCallback->("Reading template: $templateFile\n");
			$templateFileData = eval { read_file($path) };
			if ($@) {
				$self->errorCallback->("Unable to open file: $path\nBecause of:\n$@\n");
			}
		}
	}
	if(!defined($templateFileData)) {
		return undef;
	}
	my %result = (
		'data' => \$templateFileData,
		'parse' => $doParsing
	);
	return \%result;
}

sub parse {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $content = shift;
	my $items = shift;
	my $globalcontext = shift;
	my %localcontext = ();
        $localcontext{'simple'} = 1;
	return $self->parseTemplateContent($client,$item,$content,$items,$globalcontext->{'templates'},$globalcontext,\%localcontext);
}


sub checkTemplateParameters {
	my $self = shift;
	my $template = shift;
	my $parameters = shift;
	my $globalcontext = shift;
	my $localcontext = shift;

	my $librarySupported = 0;
	for my $key (keys %$parameters) {
		if($key eq 'library') {
			$librarySupported = 1;
			$localcontext->{'librarysupported'} = 1;
		}
	}
	return 1;
}

sub checkTemplateValues {
	my $self = shift;
	my $template = shift;
	my $xml = shift;
	my $globalcontext = shift;
	my $localcontext = shift;

	if(defined($template->{'downloadidentifier'})) {
		$localcontext->{'downloadidentifier'} = $template->{'downloadidentifier'};
	}
	return 1;
}
# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
