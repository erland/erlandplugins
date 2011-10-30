#    Copyright (c) 2011 Erland Isaksson (erland@isaksson.info)
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
package Plugins::HideMenus::MenuSettings;

use strict;
use base qw(Plugins::HideMenus::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;

my $prefs = preferences('plugin.hidemenus');
my $log   = logger('plugin.hidemenus');

my $plugin; # reference to main plugin

sub new {
	my $class = shift;
	$plugin   = shift;

	$class->SUPER::new($plugin,1);
}

sub name {
	return 'PLUGIN_HIDEMENUS';
}


sub page {
	return 'plugins/HideMenus/settings/menus.html';
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

	if ($paramRef->{'saveSettings'}) {
		my $menus = getMenus();
		foreach my $menu (@$menus) {
			my $menuid = "menu_".$menu->{'id'};
			if($paramRef->{$menuid}) {
				$prefs->set($menuid,1);
			}else {
				$prefs->set($menuid,0);
			}
		}
        }
	$paramRef->{'pluginHideMenusMenus'} = getMenus();

	return $class->SUPER::handler($client, $paramRef);
}

sub getMenus {
	my @menus = ();
	push @menus, {
		id => 'myMusicArtists',
		name => 'BROWSE_BY_ARTIST',
	};
	push @menus, {
		id => 'myMusicAlbums',
		name => 'BROWSE_BY_ALBUM',
	};
	push @menus, {
		id => 'myMusicGenres',
		name => 'BROWSE_BY_GENRE',
	};
	push @menus, {
		id => 'myMusicYears',
		name => 'BROWSE_BY_YEAR',
	};
	push @menus, {
		id => 'myMusicNewMusic',
		name => 'BROWSE_NEW_MUSIC',
	};
	push @menus, {
		id => 'myMusicMusicFolder',
		name => 'BROWSE_MUSIC_FOLDER',
	};
	push @menus, {
		id => 'myMusicPlaylists',
		name => 'SAVED_PLAYLISTS',
	};
	foreach my $menu (@menus) {
		$menu->{'active'} = !defined($prefs->get('menu_'.$menu->{'id'}))?1:$prefs->get('menu_'.$menu->{'id'});
	}
	return \@menus;
}

1;
