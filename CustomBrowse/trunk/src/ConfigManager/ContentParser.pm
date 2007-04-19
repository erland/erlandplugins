# 			ConfigManager::ContentParser module
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

package Plugins::CustomBrowse::ConfigManager::ContentParser;

use strict;
use base 'Class::Data::Accessor';
use Plugins::CustomBrowse::ConfigManager::BaseParser;
our @ISA = qw(Plugins::CustomBrowse::ConfigManager::BaseParser);

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

sub new {
	my $class = shift;
	my $parameters = shift;

	$parameters->{'contentType'} = 'menu';
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

	my %localcontext = ();
	if(!$globalcontext->{'onlylibrarysupported'}) {
		return $self->parseContent($client,$item,$content,$items,$globalcontext,\%localcontext);
	}else {
		return undef;
	}
}

sub checkContent {
	my $self = shift;
	my $xml = shift;
	my $globalcontext = shift;
	my $localcontext = shift;

	my $disabled = 0;
	my $forceEnabledBrowse = undef;
	if(defined($xml->{'enabledbrowse'})) {
		if(ref($xml->{'enabledbrowse'}) ne 'HASH') {
			$forceEnabledBrowse = $xml->{'enabledbrowse'};
		}else {
			$forceEnabledBrowse = '';
		}
	}elsif(defined($localcontext->{'forceenabledbrowse'})) {
		$forceEnabledBrowse = $localcontext->{'forceenabledbrowse'};
	}

	if(defined($xml->{'menu'}) && defined($xml->{'menu'}->{'id'})) {
		my $enabled = Slim::Utils::Prefs::get('plugin_custombrowse_menu_'.escape($xml->{'menu'}->{'id'}).'_enabled');
		if(defined($enabled) && !$enabled) {
			$disabled = 1;
		}elsif(!defined($enabled)) {
			if(defined($xml->{'defaultdisabled'}) && $xml->{'defaultdisabled'}) {
				$disabled = 1;
			}
		}
	}
	my $disabledBrowse = 1;
	if(defined($xml->{'menu'}) && defined($xml->{'menu'}->{'id'})) {
		my $enabled = Slim::Utils::Prefs::get('plugin_custombrowse_menubrowse_'.escape($xml->{'menu'}->{'id'}).'_enabled');
		if(defined($enabled) && $enabled) {
			$disabledBrowse = 0;
		}elsif(!defined($enabled)) {
			if(defined($xml->{'defaultenabledbrowse'}) && $xml->{'defaultenabledbrowse'}) {
				$disabledBrowse = 0;
			}
		}
	}
	
	$xml->{'menu'}->{'topmenu'} = 1;
	if(defined($localcontext) && defined($localcontext->{'simple'})) {
		$xml->{'menu'}->{'simple'} = 1;
	}
	if($localcontext->{'librarysupported'}) {
		$xml->{'menu'}->{'librarysupported'} = 1;
	}
	if(!$disabled) {
		$xml->{'menu'}->{'enabled'}=1;	
		if(!defined($forceEnabledBrowse)) {
			if($disabledBrowse) {
				$xml->{'menu'}->{'enabledbrowse'}=0;
			}else {
				$xml->{'menu'}->{'enabledbrowse'}=1;
			}
		}else {
			$xml->{'menu'}->{'forcedenabledbrowse'} = 1;
			$xml->{'menu'}->{'enabledbrowse'}=$forceEnabledBrowse;
		}
		if(defined($localcontext) && defined($localcontext->{'downloadidentifier'})) {
			$xml->{'menu'}->{'downloadeditem'} = 1;
		}
		if($globalcontext->{'source'} eq 'plugin' || $globalcontext->{'source'} eq 'builtin') {
			$xml->{'menu'}->{'defaultitem'} = 1;
		}else {
			$xml->{'menu'}->{'customitem'} = 1;
		}
	}elsif($disabled) {
		$xml->{'menu'}->{'enabled'}=0;
		if(!defined($forceEnabledBrowse)) {
			$xml->{'menu'}->{'enabledbrowse'}=0;
		}else {
			$xml->{'menu'}->{'forcedenabledbrowse'} = 1;
			$xml->{'menu'}->{'enabledbrowse'}=$forceEnabledBrowse;
		}
		if(defined($localcontext) && defined($localcontext->{'downloadidentifier'})) {
			$xml->{'menu'}->{'downloadeditem'} = 1;
		}
		if($globalcontext->{'source'} eq 'plugin' || $globalcontext->{'source'} eq 'builtin') {
			$xml->{'menu'}->{'defaultitem'} = 1;
		}else {
			$xml->{'menu'}->{'customitem'} = 1;
		}
	}
	return 1;
}
# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;
1;

__END__
