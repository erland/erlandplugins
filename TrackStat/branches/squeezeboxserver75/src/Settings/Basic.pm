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
package Plugins::TrackStat::Settings::Basic;

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

	$class->SUPER::new($plugin,1);
}

sub name {
	return 'PLUGIN_TRACKSTAT';
}

sub page {
	return 'plugins/TrackStat/settings/basic.html';
}

sub currentPage {
	return Slim::Utils::Strings::string('PLUGIN_TRACKSTAT_SETTINGS');
}

sub pages {
	my %page = (
		'name' => Slim::Utils::Strings::string('PLUGIN_TRACKSTAT_SETTINGS'),
		'page' => page(),
	);
	my @pages = (\%page);
	return \@pages;
}

sub prefs {
        return ($prefs, qw(dynamicplaylist dynamicplaylist_norepeat min_song_length song_threshold_length min_song_percent refresh_startup refresh_rescan history_enabled long_urls));
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
