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
package Plugins::DynamicPlayList::PlaylistSettings;

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

sub new {
	my $class = shift;
	$plugin   = shift;

	$class->SUPER::new($plugin);
}

sub name {
	return 'PLUGIN_DYNAMICPLAYLIST_PLAYLISTSETTINGS';
}

sub page {
	return 'plugins/DynamicPlayList/settings/playlists.html';
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

sub handler {
	my ($class, $client, $paramRef) = @_;

	my ($playLists, $playListItems) = Plugins::DynamicPlayList::Plugin::initPlayLists($client);
	$paramRef->{'pluginDynamicPlayListPlayLists'} = $playLists;
	my @groupPath = ();
	my @groupResult = ();
	$paramRef->{'pluginDynamicPlayListGroups'} = Plugins::DynamicPlayList::Plugin::getPlayListGroups(\@groupPath,$playListItems,\@groupResult);

	if ($paramRef->{'saveSettings'}) {
		my $first = 1;
		my $sql = '';
		foreach my $playlist (keys %$playLists) {
			my $playlistid = "playlist_".$playLists->{$playlist}{'dynamicplaylistid'};
			if($paramRef->{$playlistid}) {
				$prefs->delete('playlist_'.$playlist.'_enabled');
			}else {
				$prefs->set('playlist_'.$playlist.'_enabled',0);
			}
			my $playlistfavouriteid = "playlistfavourite_".$playLists->{$playlist}{'dynamicplaylistid'};
			if($paramRef->{$playlistfavouriteid}) {
				$prefs->set('playlist_'.$playlist.'_favourite',1);
			}else {
				$prefs->delete('playlist_'.$playlist.'_favourite');
			}
		}
	
		savePlayListGroups($playListItems,$paramRef,"");
        }

	return $class->SUPER::handler($client, $paramRef);
}

sub savePlayListGroups {
	my $items = shift;
	my $paramRef = shift;
	my $path = shift;
	
	foreach my $itemKey (keys %$items) {
		my $item = $items->{$itemKey};
		if(!defined($item->{'playlist'}) && defined($item->{'name'})) {
			my $groupid = escape($path)."_".escape($item->{'name'});
			my $playlistid = "playlist_".$groupid;
			if($paramRef->{$playlistid}) {
				#$log->debug("Saving: plugin_dynamicplaylist_playlist_".escape($path)."_".escape($itemKey)."_enabled=1\n");
				$prefs->set('playlist_group_'.$groupid.'_enabled',1);
			}else {
				#$log->debug("Saving: plugin_dynamicplaylist_playlist_".escape($path)."_".escape($itemKey)."_enabled=0\n");
				$prefs->set('playlist_group_'.$groupid.'_enabled',0);
			}
			if(defined($item->{'childs'})) {
				savePlayListGroups($item->{'childs'},$paramRef,$path."_".$item->{'name'});
			}
		}
	}
}
		
1;
