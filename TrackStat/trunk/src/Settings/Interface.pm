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
package Plugins::TrackStat::Settings::Interface;

use strict;
use base qw(Plugins::TrackStat::Settings::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings;

my $prefs = preferences('plugin.trackstat');
my $log   = logger('plugin.trackstat');

my $plugin; # reference to main plugin

sub new {
	my $class = shift;
	$plugin   = shift;

	$class->SUPER::new($plugin);
}

sub name {
	return 'PLUGIN_TRACKSTAT_SETTINGS_INTERFACE';
}

sub page {
	return 'plugins/TrackStat/settings/interface.html';
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

sub prefs {
        return ($prefs, qw(web_flatlist player_flatlist deep_hierarchy web_list_length player_list_length web_refresh web_show_mixerlinks web_enable_mixerfunction enable_mixerfunction force_grouprating recent_number_of_days recentadded_number_of_days min_artist_tracks min_album_tracks disablenumberscroll));
}
sub handler {
	my ($class, $client, $paramRef) = @_;

	if ($paramRef->{'saveSettings'}) {
		# Handled by SUPER handler
	}	
	my $result = $class->SUPER::handler($client, $paramRef);
	return $result;
}

		
1;
