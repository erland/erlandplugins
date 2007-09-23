# 			ConfigManager::MixParser module
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

package Plugins::CustomBrowse::ConfigManager::MixParser;

use strict;
use Plugins::CustomBrowse::ConfigManager::BaseParser;
our @ISA = qw(Plugins::CustomBrowse::ConfigManager::BaseParser);

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Data::Dumper;

sub new {
	my $class = shift;
	my $parameters = shift;

	$parameters->{'contentType'} = 'mix';
	my $self = $class->SUPER::new($parameters);
	bless $self,$class;
	return $self;
}


sub parse {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $content = shift;
	my $items = shift;
	my $globalcontext = shift;
	my $localcontext = shift;

	if($globalcontext->{'source'} ne 'plugin') {
		return $self->parseContent($client,$item,$content,$items,$globalcontext,$localcontext);
	}else {
		$content->{'id'} = $item;
		#debugMsg(Dumper($content));
		my $enabled = Slim::Utils::Prefs::get('plugin_custombrowse_mix_'.escape($content->{'id'}).'_enabled');
		if(!defined($enabled)) {
			if(defined($content->{'defaultdisabled'}) && $content->{'defaultdisabled'}) {
				$enabled = 0;
			}else {
				$enabled = 1;
			}
		}
		
		$content->{'enabled'}=$enabled;
		$self->debugCallback->("Adding mix: $item enabled=$enabled\n");
		$items->{$item} = $content;
		return undef;
	}
}


sub checkContent {
	my $self = shift;
	my $xml = shift;
	my $globalcontext = shift;
	my $localcontext = shift;
	my $disabled = 0;
	if(defined($xml->{'mix'}) && defined($xml->{'mix'}->{'id'})) {
		my $enabled = Slim::Utils::Prefs::get('plugin_custombrowse_mix_'.escape($xml->{'mix'}->{'id'}).'_enabled');
		if(defined($enabled) && !$enabled) {
			$disabled = 1;
		}elsif(!defined($enabled)) {
			if(defined($xml->{'defaultdisabled'}) && $xml->{'defaultdisabled'}) {
				$disabled = 1;
			}
		}
	}
	
	if(!$disabled) {
		$xml->{'mix'}->{'enabled'}=1;
	}elsif($disabled) {
		$xml->{'mix'}->{'enabled'}=0;
	}
	if($globalcontext->{'source'} eq 'plugin' || $globalcontext->{'source'} eq 'builtin') {
		$xml->{'mix'}->{'defaultitem'} = 1;
	}
	return 1;
}
# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
