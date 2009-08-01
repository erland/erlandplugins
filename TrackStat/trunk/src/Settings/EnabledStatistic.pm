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
package Plugins::TrackStat::Settings::EnabledStatistic;

use strict;
use base qw(Plugins::TrackStat::Settings::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;

my $prefs = preferences('plugin.trackstat');
my $log   = logger('plugin.trackstat');

my $plugin; # reference to main plugin

sub new {
	my $class = shift;
	$plugin   = shift;

	$class->SUPER::new($plugin);
}

sub name {
	return 'PLUGIN_TRACKSTAT_SETTINGS_ENABLEDSTATISTIC';
}

sub page {
	return 'plugins/TrackStat/settings/enabledstatistic.html';
}

sub currentPage {
	return name();
}

sub pages {
	my %page = (
		'name' => name(),
		'page' => page(),
	);
	my @pages = (\%page);
	return \@pages;
}

sub initStatisticItems {
	my $statistics = shift;
	my @statisticItems = ();
	for my $item (keys %$statistics) {
		my %itemData = ();
		$itemData{'id'} = $statistics->{$item}->{'id'};
		if(defined($statistics->{$item}->{'namefunction'})) {
			$itemData{'name'} = eval {&{$statistics->{$item}->{'namefunction'}}()};
			if( $@ ) {
				$log->warn("Error calling namefunction: $@\n");
			}
		}else {
			$itemData{'name'} = $statistics->{$item}->{'name'};
		}
		$itemData{'enabled'} = $statistics->{$item}->{'trackstat_statistic_enabled'};
		push @statisticItems, \%itemData;
	}
	@statisticItems = sort { $a->{'name'} cmp $b->{'name'} } @statisticItems;
	return @statisticItems;
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my $statistics = Plugins::TrackStat::Plugin::getStatisticPlugins();
	my @statisticItems = initStatisticItems($statistics);
	$paramRef->{'pluginTrackStatStatisticItems'} = \@statisticItems;
	$paramRef->{'pluginTrackStatNoOfStatisticItemsPerColumn'} = scalar(@statisticItems)/2;

	if ($paramRef->{'saveSettings'}) {
		my $first = 1;
		foreach my $statistic (keys %$statistics) {
			my $statisticid = "statistic_".$statistics->{$statistic}->{'id'};
			if($paramRef->{$statisticid}) {
				$prefs->set('statistics_'.$statistic.'_enabled',1);
				$statistics->{$statistic}->{'trackstat_statistic_enabled'} = 1;
			}else {
				$prefs->set('statistics_'.$statistic.'_enabled',0);
				$statistics->{$statistic}->{'trackstat_statistic_enabled'} = 0;
			}
		}
		Plugins::TrackStat::Plugin::initStatisticPlugins();
		my $statistics = Plugins::TrackStat::Plugin::getStatisticPlugins();
		my @statisticItems = initStatisticItems($statistics);
		$paramRef->{'pluginTrackStatStatisticItems'} = \@statisticItems;
		$paramRef->{'pluginTrackStatNoOfStatisticItemsPerColumn'} = scalar(@statisticItems)/2;
        }

	return $class->SUPER::handler($client, $paramRef);
}


# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;
		
1;
