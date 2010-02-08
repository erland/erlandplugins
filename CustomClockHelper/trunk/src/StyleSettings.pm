#    Copyright (c) 2009 Erland Isaksson (erland_i@hotmail.com)
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
package Plugins::CustomClockHelper::StyleSettings;

use strict;
use base qw(Plugins::CustomClockHelper::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings;

my $prefs = preferences('plugin.customclockhelper');
my $log   = logger('plugin.customclockhelper');

my $plugin; # reference to main plugin

sub new {
	my $class = shift;
	$plugin   = shift;

	$class->SUPER::new($plugin,1);
}

sub name {
	return 'PLUGIN_CUSTOMCLOCKHELPER';
}

sub page {
	return 'plugins/CustomClockHelper/settings/stylesettings.html';
}

sub currentPage {
	my ($class, $client, $params) = @_;
	if(defined($params->{'pluginCustomClockHelperStyle'})) {
		return Slim::Utils::Strings::string('PLUGIN_CUSTOMCLOCKHELPER_STYLESETTINGS')." ".$params->{'pluginCustomClockHelperStyle'};
	}else {
		return Slim::Utils::Strings::string('PLUGIN_CUSTOMCLOCKHELPER_STYLESETTINGS')." ".Slim::Utils::Strings::string('SETUP_PLUGIN_CUSTOMCLOCKHELPER_NEWSTYLE');
	}
}

sub pages {
	my ($class, $client, $params) = @_;
	my @pages = ();
	my $styles = Plugins::CustomClockHelper::Plugin::getStyles();

	my %page = (
		'name' => Slim::Utils::Strings::string('PLUGIN_CUSTOMCLOCKHELPER_STYLESETTINGS')." ".Slim::Utils::Strings::string('SETUP_PLUGIN_CUSTOMCLOCKHELPER_NEWSTYLE'),
		'page' => page(),
	);
	push @pages,\%page;
	for my $key (keys %$styles) {
		my %page = (
			'name' => Slim::Utils::Strings::string('PLUGIN_CUSTOMCLOCKHELPER_STYLESETTINGS')." ".$key,
			'page' => page()."?style=".escape($key),
		);
		push @pages,\%page;
	}
	return \@pages;
}

sub handler {
	my ($class, $client, $params) = @_;

	my $style = undef;
	if(defined($params->{'saveSettings'})) {
		$style = saveHandler($class, $client, $params);
	}elsif(defined($params->{'style'})) {
		$style = Plugins::CustomClockHelper::Plugin->getStyle($params->{'style'});
	}

	my @properties = ();
	if(defined($style)) {
		for my $property (keys %$style) {
			my %p = (
				'id' => $property,
				'value' => $style->{$property}
			);
			push @properties,\%p;
		}
	}

	my @availableProperties = qw(name models mode background minuteimage hourimage secondimage clockimage backgroundtype item1 item1color item1margin item1height item2position item1size item2 item2color item2margin item2align item2height item2position item2size item3 item3color item3margin item3align item3height item3position item3size nowplaying nowplayingreplacement nowplayingcolor nowplayingmargin nowplayingheight nowplayingposition nowplayingsize coversize coverpositionx coverpositiony);
	foreach my $availableProperty (@availableProperties) {
		my $found = 0;
		foreach my $property (@properties) {
			if($property->{'id'} eq $availableProperty) {
				$found = 1;
				last;
			}
		}
		if(!$found) {
			my %p = (
				'id' => $availableProperty,
				'value' => '',
			);
			push @properties,\%p;
		}
	}	
	foreach my $item (@properties) {
		if($item->{'id'} =~ /color$/) {
			$item->{'type'} = 'optionalsinglelist';
			my @values = qw(white lightgray gray darkgray lightred red darkred);
			$item->{'values'} = \@values;
		}elsif($item->{'id'} =~ /^models$/) {
			$item->{'type'} = 'checkboxes';
			my @values;
			foreach my $value qw(controller radio touch) {
				my %v = (
					'value' => $value
				);
				my $currentValues = undef;
				if(ref($item->{'value'}) eq 'ARRAY') {
					$currentValues = $item->{'value'};
				}else {
					my @empty = ();
					$currentValues = \@empty;
				}
				
				foreach my $currentValue (@$currentValues) {
					if($currentValue eq $value) {
						$v{'selected'} = 1;
					}
				}
				push @values,\%v;
			}
			$item->{'values'} = \@values;
		}elsif($item->{'id'} =~ /^backgroundtype$/) {
			$item->{'type'} = 'optionalsinglelist';
			my @values = qw(solidblack cover coverblack);
			$item->{'values'} = \@values;
		}elsif($item->{'id'} =~ /^mode$/) {
			$item->{'type'} = 'singlelist';
			my @values = qw(analog digital);
			$item->{'values'} = \@values;
		}elsif($item->{'id'} =~ /^nowplayingreplacement$/) {
			$item->{'type'} = 'optionalsinglelist';
			my @values = qw(auto none);
			$item->{'values'} = \@values;
		}elsif($item->{'id'} =~ /^nowplaying$/) {
			$item->{'type'} = 'optionalsinglelist';
			my @values = qw(true false);
			$item->{'values'} = \@values;
		}
	}

	@properties = sort { 		
		if($a->{'id'} eq 'name') {
			return -1;
		}elsif($b->{'id'} eq 'name') {
			return 1;
		}elsif($a->{'id'} eq 'models') {
			return -1;
		}elsif($b->{'id'} eq 'models') {
			return 1;
		}elsif($a->{'id'} eq 'mode') {
			return -1;
		}elsif($b->{'id'} eq 'mode') {
			return 1;
		}else {
			return $a->{'id'} cmp $b->{'id'};
		}
	} @properties;

	if(defined($style)) {
		$params->{'pluginCustomClockHelperStyle'} = Plugins::CustomClockHelper::Plugin::getStyleKey($style);
	}
	$params->{'pluginCustomClockHelperStyleProperties'} = \@properties;

	return $class->SUPER::handler($client, $params);
}

sub saveHandler {
	my ($class, $client, $params) = @_;

	my $style = {};
	my $styleName = $params->{'style'};
	my $oldStyleName = $styleName;
	my $name = $params->{'property_name'};
	my $models = "";
	foreach my $model qw(controller radio touch) {
		if($params->{'property_models_'.$model}) {
			if($models ne "") {
				$models.=",";
			}
			$models.=$model;
		}
	}
	$styleName = $name." - ".$models;
	if($params->{'delete'}) {
		Plugins::CustomClockHelper::Plugin->setStyle($client,$oldStyleName);
	}elsif($name && $styleName) {
		foreach my $property (keys %$params) {
			if($property =~ /^property_(.*)$/) {
				my $propertyId = $1;
				if($propertyId =~ /^models_(.*)$/) {
					my $model = $1;
					if(!defined($style->{'models'})) {
						my @empty = ();
						$style->{'models'} = \@empty;
					}
					my $models = $style->{'models'};
					push @$models,$model;
				}else {
					$style->{$propertyId} = $params->{'property_'.$propertyId};
				}
			}
		}
		my $models = $style->{'models'};
		@$models = sort { $a cmp $b } @$models;
		if($oldStyleName && $styleName ne $oldStyleName) {
			Plugins::CustomClockHelper::Plugin->renameAndSetStyle($client,$oldStyleName,$styleName,$style);
		}else {
			Plugins::CustomClockHelper::Plugin->setStyle($client,$styleName,$style);
		}
		return $style;	
	}
	return undef;
}

# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;
		
1;
