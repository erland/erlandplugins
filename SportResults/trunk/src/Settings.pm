#    Copyright (c) 2010 Erland Isaksson (erland_i@hotmail.com)
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
package Plugins::SportResults::Settings;

use strict;
use base qw(Plugins::SportResults::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings;

my $prefs = preferences('plugin.sportresults');
my $log   = logger('plugin.sportresults');

my $plugin; # reference to main plugin

sub new {
	my $class = shift;
	$plugin   = shift;

	$class->SUPER::new($plugin,1);
}

sub name {
	return 'PLUGIN_SPORTRESULTS';
}

sub page {
	return 'plugins/SportResults/settings/basic.html';
}

sub currentPage {
	return Slim::Utils::Strings::string('PLUGIN_SPORTRESULTS_SETTINGS');
}

sub pages {
	my %page = (
		'name' => name(),
		'page' => page(),
	);
	my @pages = (\%page);
	return \@pages;
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my $disabledSports = $prefs->get('disabledsports') || {};
	my $disabledCountries = $prefs->get('disabledcountries') || {};
	my $disabledLeagues = $prefs->get('disabledleagues') || {};

	my $availableCountries = Plugins::SportResults::Plugin::getAvailableCountries();
	my $availableSports = Plugins::SportResults::Plugin::getAvailableSports();
	my $availableLeagues = Plugins::SportResults::Plugin::getAvailableLeagues();

	if($paramRef->{'saveSettings'}) {
		foreach my $sport (keys %$availableSports) {
			if(!$paramRef->{'sport_'.$sport}) {
				$disabledSports->{$sport} = $availableSports->{$sport};
			}else {
				delete $disabledSports->{$sport};
			}
		}
		$prefs->set('disabledsports',$disabledSports);

		foreach my $country (keys %$availableCountries) {
			if(!$paramRef->{'country_'.$country}) {
				$disabledCountries->{$country} = $availableCountries->{$country};
			}else {
				delete $disabledCountries->{$country};
			}
		}
		$prefs->set('disabledcountries',$disabledCountries);

		foreach my $league (keys %$availableLeagues) {
			if(!$paramRef->{'league_'.$league}) {
				$disabledLeagues->{$league} = $availableLeagues->{$league};
			}else {
				delete $disabledLeagues->{$league};
			}
		}
		$prefs->set('disabledleagues',$disabledLeagues);
	}
	my @webCountries = ();
	for my $country (keys %$availableCountries) {
		my $entry = {
			id => $country,
			name => $availableCountries->{$country},
		};
		if(defined($disabledCountries->{$country}) && $disabledCountries->{$country}) {
			$entry->{'enabled'} = 0;
		}else {
			$entry->{'enabled'} = 1;
		}
		push @webCountries,$entry;
	}
	@webCountries = sort { $a->{'name'} cmp $b->{'name'} } @webCountries;
	$paramRef->{'pluginSportResultsCountries'} = \@webCountries;

	my @webSports = ();
	for my $sport (keys %$availableSports) {
		my $entry = {
			id => $sport,
			name => $availableSports->{$sport},
		};
		if(defined($disabledSports->{$sport}) && $disabledSports->{$sport}) {
			$entry->{'enabled'} = 0;
		}else {
			$entry->{'enabled'} = 1;
		}
		push @webSports,$entry;
	}
	@webSports = sort { $a->{'name'} cmp $b->{'name'} } @webSports;
	$paramRef->{'pluginSportResultsSports'} = \@webSports;

	my @webLeagues = ();
	for my $league (keys %$availableLeagues) {
		my $entry = {
			id => $league,
			name => $availableLeagues->{$league},
		};
		if(defined($disabledLeagues->{$league}) && $disabledLeagues->{$league}) {
			$entry->{'enabled'} = 0;
		}else {
			$entry->{'enabled'} = 1;
		}
		push @webLeagues,$entry;
	}
	@webLeagues = sort { $a->{'name'} cmp $b->{'name'} } @webLeagues;
	$paramRef->{'pluginSportResultsLeagues'} = \@webLeagues;

	my $result = $class->SUPER::handler($client, $paramRef);

	return $result;
}

		
1;
