#    Copyright (c) 2007 Erland Isaksson (erland_i@hotmail.com)
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
package Plugins::DynamicPlayList::FilterSettings;

use strict;
use base qw(Plugins::DynamicPlayList::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;

my $prefs = preferences('plugin.dynamicplaylist');
my $log   = logger('plugin.dynamicplaylist');

my $plugin; # reference to main plugin
my $filters;

sub new {
	my $class = shift;
	$plugin   = shift;

	$class->SUPER::new($plugin);
}

sub name {
	return 'PLUGIN_DYNAMICPLAYLIST_FILTERSETTINGS';
}

sub page {
	return 'plugins/DynamicPlayList/settings/filters.html';
}

sub currentPage {
	return name();
}

sub pages {
	my ($class, $client, $paramRef) = @_;
	if(!defined($filters)) {
		$filters = Plugins::DynamicPlayList::Plugin::initFilters();
	}
	my @pages = ();
	if(scalar(keys %$filters)>0) {
		my %page = (
			'name' => name(),
			'page' => page(),
		);
		push @pages,\%page;
	}
	return \@pages;
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	$filters = Plugins::DynamicPlayList::Plugin::initFilters();
	$paramRef->{'pluginDynamicPlayListFilters'} = $filters;

	if ($paramRef->{'saveSettings'}) {
		my $first = 1;
		my $sql = '';
		foreach my $key (keys %$filters) {
			my $filterid = "filter_".$filters->{$key}{'dynamicplaylistfilterid'};
			if($paramRef->{$filterid}) {
				$prefs->set('filter_'.$key.'_enabled',1);
			}else {
				$prefs->set('filter_'.$key.'_enabled',0);
			}
		}
		$filters = Plugins::DynamicPlayList::Plugin::initFilters();
		$paramRef->{'pluginDynamicPlayListFilters'} = $filters;
        }

	return $class->SUPER::handler($client, $paramRef);
}

		
1;
