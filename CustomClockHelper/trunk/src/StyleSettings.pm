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

use Data::Dumper;

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
			if($property ne "items") {
				my %p = (
					'id' => $property,
					'value' => $style->{$property}
				);
				push @properties,\%p;
			}
		}
	}

	my @availableProperties = qw(name models contributors background backgroundtype backgrounddynamic clockposx clockposy);
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
		if($item->{'id'} =~ /^models$/) {
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
			my @values = ();
			push @values,{id=>'black',name=>'black'};				
			push @values,{id=>'white',name=>'white'};				
			push @values,{id=>'lightgray',name=>'lightgray'};				
			push @values,{id=>'gray',name=>'gray'};				
			push @values,{id=>'darkgray',name=>'darkgray'};				
			$item->{'values'} = \@values;
		}elsif($item->{'id'} =~ /^backgrounddynamic$/) {
			$item->{'type'} = 'singlelist';
			my @values = ();
			push @values,{id=>'false',name=>'false'};				
			push @values,{id=>'true',name=>'true'};				
			$item->{'values'} = \@values;
		}
	}

	@properties = sort { 		
		if($a->{'id'} eq 'name') {
			return -1;
		}elsif($b->{'id'} eq 'name') {
			return 1;
		}elsif($a->{'id'} eq 'contributors') {
			return -1;
		}elsif($b->{'id'} eq 'contributors') {
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

	my @availableItems = ();
	my $id = 1;
	if(defined($style) && defined($style->{'items'})) {
		my $items = $style->{'items'};
		for my $item (@$items) {
			my $entry = {
				'id' => $id
			};
			if($item->{'itemtype'} =~ /sdttext$/) {
				$entry->{'name'} = "Item #".$id." (".$item->{'itemtype'}."): ".($item->{'period'} ne ""?$item->{'period'}.":":"").$item->{'sdtformat'};
			}elsif($item->{'itemtype'} =~ /^sdtsport/) {
				$entry->{'name'} = "Item #".$id." (".$item->{'itemtype'}."): ".($item->{'sport'} ne ""?$item->{'sport'}:"");
			}elsif($item->{'itemtype'} =~ /text$/) {
				$entry->{'name'} = "Item #".$id." (".$item->{'itemtype'}."): ".$item->{'text'};
			}elsif($item->{'itemtype'} =~ /image$/) {
				$entry->{'name'} = "Item #".$id." (".$item->{'itemtype'}.")";
			}elsif($item->{'itemtype'} =~ /sdticon$/) {
				$entry->{'name'} = "Item #".$id." (".$item->{'itemtype'}."): ".$item->{'period'};
			}elsif($item->{'itemtype'} =~ /sdtweathermapicon$/) {
				$entry->{'name'} = "Item #".$id." (".$item->{'itemtype'}."): ".$item->{'location'};
			}else {
				$entry->{'name'} = "Item #".$id." (".$item->{'itemtype'}.")";
			}
			push @availableItems,$entry;
			$id++;
		}
	}
	if($params->{'itemnew'}) {
		my $entry = {
			'id' => $id,
			'name' => "New item..."
		};
		$params->{'pluginCustomClockHelperStyleItemNo'} = $id;
		push @availableItems,$entry;
	}
	$params->{'pluginCustomClockHelperStyleItems'} = \@availableItems;

	my @itemproperties = ();
	if(defined($style) && defined($style->{'items'}) && $params->{'pluginCustomClockHelperStyleItemNo'}) {
		my $items = $style->{'items'};
		my $currentItem = $items->[$params->{'pluginCustomClockHelperStyleItemNo'}-1];
		my $itemtype = $currentItem->{'itemtype'} || "timetext";
		for my $property (keys %$currentItem) {
			if($currentItem->{$property} ne "" && isItemTypeParameter($itemtype,$property)) {
				my %p = (
					'id' => $property,
					'value' => $currentItem->{$property}
				);
				push @itemproperties,\%p;
			}
		}
		my @availableProperties = getItemTypeParameters($itemtype);
		foreach my $availableProperty (@availableProperties) {
			my $found = 0;
			foreach my $property (@itemproperties) {
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
				push @itemproperties,\%p;
			}
		}	
		foreach my $item (@itemproperties) {
			if($item->{'id'} =~ /color$/) {
				$item->{'type'} = 'optionalsinglecombobox';
				my @values = ();
				push @values,{id=>'white',name=>'white'};				
				push @values,{id=>'lightgray',name=>'lightgray'};				
				push @values,{id=>'gray',name=>'gray'};				
				push @values,{id=>'darkgray',name=>'darkgray'};				
				push @values,{id=>'lightred',name=>'lightred'};				
				push @values,{id=>'red',name=>'red'};				
				push @values,{id=>'darkred',name=>'darkred'};				
				push @values,{id=>'black',name=>'black'};				
				push @values,{id=>'lightyellow',name=>'lightyellow'};				
				push @values,{id=>'yellow',name=>'yellow'};				
				push @values,{id=>'darkyellow',name=>'darkyellow'};				
				push @values,{id=>'lightblue',name=>'lightblue'};				
				push @values,{id=>'blue',name=>'blue'};				
				push @values,{id=>'darkblue',name=>'darkblue'};				
				push @values,{id=>'lightgreen',name=>'lightgreen'};				
				push @values,{id=>'green',name=>'green'};				
				push @values,{id=>'darkgreen',name=>'darkgreen'};				
				$item->{'values'} = \@values;
			}elsif($item->{'id'} eq 'sdtformat') {
				$item->{'type'} = 'optionalsinglecombobox';
				my @values = ();
				if($currentItem->{'period'} !~ /^d\d+/) {
					push @values,{id=>'%1',name=>'Time'};				
					push @values,{id=>'%2',name=>'Date'};				
					push @values,{id=>'%y',name=>'Period Covered (ie Today)'};				
					push @values,{id=>'%e',name=>'Temperature (F)'};				
					push @values,{id=>'%v',name=>'Brief Forecast (ie Sunny)'};				
					push @values,{id=>'%E',name=>'Temperature (C)'};				
					push @values,{id=>'%t',name=>'Temperature (F)'};				
					push @values,{id=>'%T',name=>'Temperature (C)'};
					push @values,{id=>'%z',name=>'High/Low (F)'};				
					push @values,{id=>'%Z',name=>'High/Low (C)'};				
					push @values,{id=>'%a',name=>'Average High/Low (F)'};				
					push @values,{id=>'%A',name=>'Average High/Low (C)'};				
					push @values,{id=>'%c',name=>'Record High/Low (F)'};				
					push @values,{id=>'%C',name=>'Record High/Low (C)'};				
					push @values,{id=>'%g',name=>'Record High/Low Year'};				
					push @values,{id=>'%m',name=>'Dew Point (F)'};				
					push @values,{id=>'%M',name=>'Dew Point (C)'};				
					push @values,{id=>'%d',name=>'Dew Point (F)'};				
					push @values,{id=>'%D',name=>'Dew Point (C)'};				
					push @values,{id=>'%f',name=>'Feels-Like Temperature (F)'};				
					push @values,{id=>'%F',name=>'Feels-Like Temperature (C)'};				
					push @values,{id=>'%h',name=>'Humidity'};				
					push @values,{id=>'%H',name=>'Humidity'};				
					push @values,{id=>'%j',name=>'Wind Speed (mi/hr)'};				
					push @values,{id=>'%J',name=>'Wind Speed (km/hr)'};				
					push @values,{id=>'%K',name=>'Wind Speed (m/s)'};				
					push @values,{id=>'%w',name=>'Wind Speed (mi/hr)'};				
					push @values,{id=>'%W',name=>'Wind Speed (km/hr)'};				
					push @values,{id=>'%q',name=>'Wind Speed (kt/hr)'};				
					push @values,{id=>'%Q',name=>'Wind Speed (m/s)'};				
					push @values,{id=>'%x',name=>'Precipitation'};				
					push @values,{id=>'%l',name=>'Barometric Preassure (inHg)'};				
					push @values,{id=>'%p',name=>'Barometric Preassure (inHg)'};				
					push @values,{id=>'%L',name=>'Barometric Preassure (hPa)'};				
					push @values,{id=>'%P',name=>'Barometric Preassure (hPa)'};				
					push @values,{id=>'%s',name=>'Sunrise'};				
					push @values,{id=>'%S',name=>'Sunset'};				
					push @values,{id=>'%u',name=>'UV Index (Value)'};				
					push @values,{id=>'%U',name=>'UV Index (Text)'};				
					push @values,{id=>'%b',name=>'Past 24-hr Precip'};				
					push @values,{id=>'%B',name=>'Past 24-hr Snowfall'};
				}
				if($currentItem->{'period'} =~ /^d\d+/) {
					push @values,{id=>'%_3',name=>'dx Weekday'};
					push @values,{id=>'%_4',name=>'dx Date'};
					push @values,{id=>'%_5',name=>'dx High (F)'};
					push @values,{id=>'%_6',name=>'dx High (C)'};
					push @values,{id=>'%_7',name=>'dx Low (F)'};
					push @values,{id=>'%_8',name=>'dx Low (C)'};
					push @values,{id=>'%_9',name=>'dx Precip'};
					push @values,{id=>'%_0',name=>'dx Condition'};
				}
				$item->{'values'} = \@values;
			}elsif($item->{'id'} eq 'sport') {
				$item->{'type'} = 'optionalsinglecombobox';
				my @values = ();
				push @values,{id=>'mlb',name=>'Baseball (MLB)'};				
				push @values,{id=>'nfl',name=>'Football (NFL)'};				
				push @values,{id=>'nba',name=>'Basketball (NBA)'};				
				push @values,{id=>'nhl',name=>'Hockey (NHL)'};				
				$item->{'values'} = \@values;
			}elsif($item->{'id'} eq 'gamestatus') {
				$item->{'type'} = 'optionalsinglelist';
				my @values = ();
				push @values,{id=>'active',name=>'Active'};				
				push @values,{id=>'activeandfinal',name=>'Active or completed'};				
				push @values,{id=>'final',name=>'Completed'};				
				$item->{'values'} = \@values;
			}elsif($item->{'id'} =~ /^itemtype$/) {
				$item->{'type'} = 'singlelist';
				my @values = ();
				push @values,{id=>'text',name=>'text'};				
				push @values,{id=>'timetext',name=>'timetext'};				
				push @values,{id=>'tracktext',name=>'tracktext'};				
				push @values,{id=>'trackplayingtext',name=>'trackplayingtext'};				
				push @values,{id=>'trackstoppedtext',name=>'trackstoppedtext'};				
				push @values,{id=>'switchingtracktext',name=>'switchingtracktext'};				
				push @values,{id=>'switchingtrackplayingtext',name=>'switchingtrackplayingtext'};				
				push @values,{id=>'switchingtrackstoppedtext',name=>'switchingtrackstoppedtext'};				
				push @values,{id=>'alarmtimetext',name=>'alarmtimetext'};				
				push @values,{id=>'clockimage',name=>'clockimage'};				
				push @values,{id=>'hourimage',name=>'hourimage'};				
				push @values,{id=>'minuteimage',name=>'minuteimage'};				
				push @values,{id=>'secondimage',name=>'secondimage'};				
				push @values,{id=>'playstatusicon',name=>'playstatusicon'};				
				push @values,{id=>'shufflestatusicon',name=>'shufflestatusicon'};				
				push @values,{id=>'repeatstatusicon',name=>'repeatstatusicon'};				
				push @values,{id=>'alarmicon',name=>'alarmicon'};				
				push @values,{id=>'ratingicon',name=>'ratingicon'};				
				push @values,{id=>'ratingplayingicon',name=>'ratingplayingicon'};				
				push @values,{id=>'ratingstoppedicon',name=>'ratingstoppedicon'};				
				push @values,{id=>'wirelessicon',name=>'wirelessicon'};				
				push @values,{id=>'sleepicon',name=>'sleepicon'};				
				push @values,{id=>'batteryicon',name=>'batteryicon'};				
				push @values,{id=>'covericon',name=>'covericon'};				
				push @values,{id=>'coverplayingicon',name=>'coverplayingicon'};				
				push @values,{id=>'coverstoppedicon',name=>'coverstoppedicon'};				
				push @values,{id=>'covernexticon',name=>'covernexticon'};				
				push @values,{id=>'covernextplayingicon',name=>'covernextplayingicon'};				
				push @values,{id=>'covernextstoppedicon',name=>'covernextstoppedicon'};				
				push @values,{id=>'rotatingimage',name=>'rotatingimage'};				
				push @values,{id=>'elapsedimage',name=>'elapsedimage'};				
				push @values,{id=>'analogvumeter',name=>'analogvumeter'};				
				push @values,{id=>'digitalvumeter',name=>'digitalvumeter'};				
				push @values,{id=>'spectrummeter',name=>'spectrummeter'};				
				my $request = Slim::Control::Request::executeRequest(undef,['can','gallery','random','?']);
				my $result = $request->getResult("_can");
				if($result) {
					my $request = Slim::Control::Request::executeRequest(undef,['can','gallery','favorites','?']);
					$result = $request->getResult("_can");
					if($result) {
						push @values,{id=>'galleryicon',name=>'galleryicon'};				
					}
				}
				$request = Slim::Control::Request::executeRequest(undef,['can','sdtMacroString','?']);
				$result = $request->getResult("_can");
				if($result) {
					push @values,{id=>'sdttext',name=>'sdttext'};				
				}
				$request = Slim::Control::Request::executeRequest(undef,['can','SuperDateTime','?']);
				$result = $request->getResult("_can");
				if($result) {
					push @values,{id=>'sdticon',name=>'sdticon'};				
					push @values,{id=>'sdtsporttext',name=>'sdtsporttext'};				
				}
				$request = Slim::Control::Request::executeRequest(undef,['can','sdtVersion','?']);
				$result = $request->getResult("_can");
				if($result) {
					push @values,{id=>'sdtsporttexticon',name=>'sdtsporttexticon'};				
					push @values,{id=>'sdtweathermapicon',name=>'sdtweathermapicon'};				
				}
				$request = Slim::Control::Request::executeRequest(undef,['can','songinfoitems','?']);
				$result = $request->getResult("_can");
				if($result) {
					push @values,{id=>'songinfoicon',name=>'songinfoicon'};				
				}
				$item->{'values'} = \@values;
			}elsif($item->{'id'} =~ /^animate$/) {
				$item->{'type'} = 'singlelist';
				my @values = ();
				push @values,{id=>'true',name=>'true'};				
				push @values,{id=>'false',name=>'false'};				
				$item->{'values'} = \@values;
			}elsif($item->{'id'} =~ /^scrolling$/) {
				$item->{'type'} = 'singlelist';
				my @values = ();
				push @values,{id=>'false',name=>'false'};				
				push @values,{id=>'true',name=>'true'};				
				$item->{'values'} = \@values;
			}elsif($item->{'id'} =~ /dynamic$/) {
				$item->{'type'} = 'singlelist';
				my @values = ();
				push @values,{id=>'false',name=>'false'};				
				push @values,{id=>'true',name=>'true'};				
				$item->{'values'} = \@values;
			}elsif($item->{'id'} =~ /^period$/) {
				$item->{'type'} = 'optionalsinglecombobox';
				my @values = ();
				push @values,{id=>'-1',name=>'C'};				
				push @values,{id=>'0',name=>'1'};				
				push @values,{id=>'1',name=>'2'};				
				push @values,{id=>'2',name=>'3'};				
				push @values,{id=>'d1',name=>'d1'};				
				push @values,{id=>'d2',name=>'d2'};				
				push @values,{id=>'d3',name=>'d3'};				
				push @values,{id=>'d4',name=>'d4'};				
				push @values,{id=>'d5',name=>'d5'};				
				push @values,{id=>'d6',name=>'d6'};				
				push @values,{id=>'d7',name=>'d7'};				
				push @values,{id=>'d8',name=>'d8'};				
				push @values,{id=>'d9',name=>'d9'};				
				push @values,{id=>'d10',name=>'d10'};				
				$item->{'values'} = \@values;
			}elsif($item->{'id'} =~ /^align$/) {
				$item->{'type'} = 'optionalsinglelist';
				my @values = ();
				push @values,{id=>'left',name=>'left'};				
				push @values,{id=>'center',name=>'center'};				
				push @values,{id=>'right',name=>'right'};				
				push @values,{id=>'top',name=>'top'};				
				push @values,{id=>'bottom',name=>'bottom'};				
				push @values,{id=>'top-left',name=>'top-left'};				
				push @values,{id=>'top-right',name=>'top-right'};				
				push @values,{id=>'bottom-left',name=>'bottom-left'};				
				push @values,{id=>'bottom-right',name=>'bottom-right'};				
				$item->{'values'} = \@values;
			}elsif($item->{'id'} eq 'channels') {
				$item->{'type'} = 'optionalsinglelist';
				my @values = ();
				push @values,{id=>'left',name=>'left'};				
				push @values,{id=>'right',name=>'right'};				
				push @values,{id=>'left+right',name=>'left+right'};				
				push @values,{id=>'mono',name=>'mono'};				
				$item->{'values'} = \@values;
			}elsif($item->{'id'} =~ /^favorite$/) {
				$item->{'type'} = 'optionalsinglelist';
				my $request = Slim::Control::Request::executeRequest(undef,['gallery','favorites']);
				my $result = $request->getResult("item_loop");
				my @values = ();
				for my $entry (@$result) {
					push @values,{id=>$entry->{'id'}, name=>$entry->{'title'}};
				}
				$item->{'values'} = \@values;
			}elsif($item->{'id'} =~ /^layout$/ &&  $itemtype eq 'sdtsporttexticon') {
				$item->{'type'} = 'singlelist';
				my @values = ();
				push @values,{id=>'vertical',name=>'vertical'};				
				push @values,{id=>'horizontal',name=>'horizontal'};				
				$item->{'values'} = \@values;
			}elsif($item->{'id'} =~ /^logotype$/ &&  $itemtype eq 'sdtsporttexticon') {
				$item->{'type'} = 'optionalsinglelist';
				my @values = ();
				push @values,{id=>'team',name=>'team'};				
				push @values,{id=>'league',name=>'league'};				
				$item->{'values'} = \@values;
			}elsif($item->{'id'} =~ /^teamorder$/ &&  $itemtype =~ /^sdtsport/) {
				$item->{'type'} = 'singlelist';
				my @values = ();
				push @values,{id=>'home-away',name=>'home-away'};				
				push @values,{id=>'away-home',name=>'away-home'};				
				$item->{'values'} = \@values;
			}elsif($item->{'id'} =~ /^show(icon|name|score|time)$/ &&  $itemtype eq 'sdtsporttexticon') {
				$item->{'type'} = 'singlelist';
				my @values = ();
				push @values,{id=>'true',name=>'true'};				
				push @values,{id=>'false',name=>'false'};				
				$item->{'values'} = \@values;
			}elsif($item->{'id'} =~ /^location$/ &&  $itemtype eq 'sdtweathermapicon') {
				$item->{'type'} = 'optionalsinglelist';
				my $request = Slim::Control::Request::executeRequest($client,['SuperDateTime','wetmapURL']);
				my $result = $request->getResult("wetmapURL");
				my @values = ();
				for my $entry (keys %$result) {
					push @values,{id=>$entry, name=>$entry};
				}
				$item->{'values'} = \@values;
			}elsif($item->{'id'} =~ /^songinfomodule$/) {
				$item->{'type'} = 'singlelist';
				my $request = Slim::Control::Request::executeRequest(undef,['songinfomodules','type:image']);
				my $result = $request->getResult("item_loop");
				my @values = ();
				for my $entry (@$result) {
					push @values,{id=>$entry->{'id'}, name=>$entry->{'name'}};
				}
				$item->{'values'} = \@values;
			}elsif($item->{'id'} eq 'text' && $itemtype eq 'timetext') {
				$item->{'type'} = 'optionalsinglecombobox';
				my @values = ();
				push @values,{id=>'%I1:%M',name=>'5:46'};				
				push @values,{id=>'%I:%M',name=>'05:46'};				
				push @values,{id=>'%I1:%M%p',name=>'5:46pm'};				
				push @values,{id=>'%H:%M',name=>'17:46'};				
				push @values,{id=>'%Y-%m-%d',name=>'2010-04-15'};				
				push @values,{id=>'%d1 %B',name=>'15 April'};				
				push @values,{id=>'%B',name=>'April'};				
				push @values,{id=>'%A %m1 %B',name=>'Wednesday 15 April'};				
				push @values,{id=>'%a %m1 %b',name=>'Wed 15 Apr'};				
				push @values,{id=>'%H:%M:%S',name=>'17:46:13'};				
				$item->{'values'} = \@values;
			}elsif($item->{'id'} eq 'text' && $itemtype eq 'alarmtimetext') {
				$item->{'type'} = 'optionalsinglecombobox';
				my @values = ();
				push @values,{id=>'%I1:%M',name=>'5:46'};				
				push @values,{id=>'%I:%M',name=>'05:46'};				
				push @values,{id=>'%I1:%M%p',name=>'5:46pm'};				
				push @values,{id=>'%H:%M',name=>'17:46'};				
				$item->{'values'} = \@values;
			}
		}
		@itemproperties = sort { 		
			if($a->{'id'} eq 'itemtype') {
				return -1;
			}elsif($b->{'id'} eq 'itemtype') {
				return 1;
			}elsif($a->{'id'} eq 'color') {
				return -1;
			}elsif($b->{'id'} eq 'color') {
				return 1;
			}elsif($a->{'id'} eq 'posx') {
				return -1;
			}elsif($b->{'id'} eq 'posx') {
				return 1;
			}elsif($a->{'id'} eq 'posy') {
				return -1;
			}elsif($b->{'id'} eq 'posy') {
				return 1;
			}else {
				return $a->{'id'} cmp $b->{'id'};
			}
		} @itemproperties;
		$params->{'pluginCustomClockHelperStyleItemProperties'} = \@itemproperties;
	}

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
	if($models ne "") {
		$styleName = $name." - ".$models;
	}
	if($params->{'delete'}) {
		Plugins::CustomClockHelper::Plugin->setStyle($client,$oldStyleName);
	}elsif($name && $styleName) {
		my $itemId = $params->{'pluginCustomClockHelperStyleItemNo'};
		my $oldStyle = Plugins::CustomClockHelper::Plugin->getStyle($oldStyleName);
		if($itemId && $itemId>0) {
			my $items = $oldStyle->{'items'};
			if($params->{'itemdelete'}) {
				splice(@$items,$itemId-1,1);
				$style = $oldStyle;
				if(scalar(@$items)<$itemId) {
					$params->{'pluginCustomClockHelperStyleItemNo'} = $itemId-1;
				}
			} else {
				my $itemStyle = {};
				foreach my $property (keys %$params) {
					if($property =~ /^itemproperty_(.*)$/) {
						my $propertyId = $1;
						if($propertyId =~ /color$/) {
							my $value = $params->{'itemproperty_'.$propertyId};
							if($value =~ /^0x[0-9a-f]{2}[0-9a-f]{2}[0-9a-f]{2}$/i) {
								# No transparency by default
								$params->{'itemproperty_'.$propertyId} = $value."ff";
							}elsif($value =~ /^0x[0-9a-f]{2}[0-9a-f]{2}[0-9a-f]{2}[0-9a-f]{2}$/i) {
								# Do nothing we already have a valid hex value
							}elsif($value =~ /^[0-9a-f]{2}[0-9a-f]{2}[0-9a-f]{2}[0-9a-f]{2}$/i) {
								# add 0x prefix
								$params->{'itemproperty_'.$propertyId} = "0x".$value;
							}elsif($value =~ /^[0-9a-f]{2}[0-9a-f]{2}[0-9a-f]{2}$/i) {
								# No transparency by default
								# add 0x prefix
								$params->{'itemproperty_'.$propertyId} = "0x".$value."ff";
							}elsif($value =~ /\d+/) {
								$log->warn("Invalid color: $value");
								$params->{'itemproperty_'.$propertyId} = ""
							}
						}
						$itemStyle->{$propertyId} = $params->{'itemproperty_'.$propertyId};
					}
				}
				splice(@$items,$itemId-1,1,$itemStyle);
				$style->{'items'} = $items;
			}
		}else {
			$style->{'items'} = $oldStyle->{'items'};
		}
		if(!$params->{'itemdelete'}) {
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
			if(!exists $style->{'items'}) {
				my @empty = ();
				$style->{'items'} = \@empty;
			}
			my $models = $style->{'models'};
			@$models = sort { $a cmp $b } @$models;
		}
		if($oldStyleName && $styleName ne $oldStyleName) {
			Plugins::CustomClockHelper::Plugin->renameAndSetStyle($client,$oldStyleName,$styleName,$style);
		}else {
			Plugins::CustomClockHelper::Plugin->setStyle($client,$styleName,$style);
		}
		return $style;	
	}
	return undef;
}

sub isItemTypeParameter {
	my $itemType = shift;
	my $parameter = shift;
	
	my @parameters = getItemTypeParameters($itemType);
	my %params;
	undef %params;
	for (@parameters) { $params{$_} = 1 }
	return $params{$parameter};
}

sub getItemTypeParameters {
	my $itemType = shift;

	if($itemType eq 'sdttext') {	
		return qw(itemtype visibilitygroup visibilityorder visibilitytime sdtformat period color posx posy width align fonturl fontfile fontsize margin animate order);
	}elsif($itemType eq 'sdtsporttext') {	
		return qw(itemtype visibilitygroup visibilityorder visibilitytime text teamorder separator interval sport gamestatus noofscores scrolling color posx posy width align fonturl fontfile fontsize lineheight height margin animate order);
	}elsif($itemType eq 'sdtsporttexticon') {	
		return qw(itemtype visibilitygroup visibilityorder visibilitytime layout showicon showname showscore showtime logotype separator separatorwidth scorewidth timewidth scoreheight reverseteams text interval sport gamestatus scorecolor color posx posy width fonturl fontfile timefontsize scorefontsize fontsize teamorder timeheight textheight iconsize margin animate order);
	}elsif($itemType =~ /text$/) {	
		return qw(itemtype visibilitygroup visibilityorder visibilitytime text color posx posy width align fonturl fontfile fontsize margin animate order);
	}elsif($itemType =~ /^cover/) {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy size align order);
	}elsif($itemType =~ /^elapsedimage$/) {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy dynamic width initialangle finalangle url.rotating url.playingrotating url.stoppedrotating url.slidingx url.playingslidingx url.stoppedslidingx url.clippingx url.playingclippingx url.stoppedclippingx);
	}elsif($itemType =~ /^rotatingimage$/) {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy dynamic speed url url.playing url.playingrotating url.stopped url.stoppedrotating);
	}elsif($itemType =~ /clockimage$/) {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy dynamic url url.hour url.minute url.second url.alarmhour url.alarmminute);
	}elsif($itemType =~ /image$/) {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy dynamic url);
	}elsif($itemType eq 'timeicon') {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy width order url url.background text);
	}elsif($itemType eq 'alarmicon') {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy order framewidth framerate url url.set url.active url.snooze);
	}elsif($itemType =~ /^rating.*icon$/) {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy order framewidth framerate url.0 url.1 url.2 url.3 url.4 url.5);
	}elsif($itemType eq 'batteryicon') {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy order framewidth framerate url url.NONE url.AC url.4 url.3 url.2 url.1 url.0 url.CHARGING);
	}elsif($itemType eq 'wirelessicon') {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy order framewidth framerate url url.3 url.2 url.1 url.NONE url.ERROR url.SERVERERROR);
	}elsif($itemType eq 'sleepicon') {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy order framewidth framerate url.ON url.OFF);
	}elsif($itemType eq 'playstatusicon') {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy order framewidth framerate url.play url.stop url.pause);
	}elsif($itemType eq 'repeatstatusicon') {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy order framewidth framerate url.song url.playlist);
	}elsif($itemType eq 'shufflestatusicon') {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy order framewidth framerate url.songs url.albums);
	}elsif($itemType eq 'galleryicon') {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy order width height interval favorite);
	}elsif($itemType eq 'sdticon') {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy order framewidth framerate width height period dynamic);
	}elsif($itemType eq 'sdtweathermapicon') {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy order width height location interval);
	}elsif($itemType eq 'songinfoicon') {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy order width height songinfomodule interval);
	}elsif($itemType =~ /icon$/) {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy order framewidth framerate dynamic url);
	}elsif($itemType eq 'analogvumeter') {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy width height order channels url);
	}elsif($itemType eq 'spectrummeter') {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy width height order channels backgroundcolor capcolor barcolor attr.capHeight attr.capSpace attr.barsInBin attr.barWidth attr.barSpace attr.binSpace);
	}elsif($itemType eq 'digitalvumeter') {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime posx posy width height order channels url url.tickcap url.tickon url.tickoff);
	}else {
		return qw(itemtype visibilitygroup visibilityorder visibilitytime);
	}
}
# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;
		
1;
