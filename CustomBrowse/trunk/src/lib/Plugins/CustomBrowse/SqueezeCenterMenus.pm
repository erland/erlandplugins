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
package Plugins::CustomBrowse::SqueezeCenterMenus;

use strict;
use base qw(Plugins::CustomBrowse::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;

my $prefs = preferences('plugin.custombrowse');
my $log   = logger('plugin.custombrowse');

my $plugin; # reference to main plugin

sub new {
	my $class = shift;
	$plugin   = shift;

	$class->SUPER::new($plugin);
}

sub name {
	return 'PLUGIN_CUSTOMBROWSE_SETTINGS_SLIMSERVERMENUS';
}

sub page {
	return 'plugins/CustomBrowse/settings/squeezecentermenus.html';
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

sub initMenus {
	my $browseMenusFlat = shift;
	my @menus = ();
	my %addedGroups = ();
	for my $key (keys %$browseMenusFlat) {
		my %webmenu = ();
		my $menu = $browseMenusFlat->{$key};
		if(defined($menu->{'menugroup'})) {
			my @groups = split('/',$menu->{'menugroup'});
			my $group = pop @groups;
			if(!exists $addedGroups{$group}) {
				$webmenu{'menuname'} = $group;
				$webmenu{'id'} = 'group_'.escape($group);
				push @menus,\%webmenu;
				$addedGroups{$group}=1;
			}
		}else {
			for my $key (keys %$menu) {
				$webmenu{$key} = $menu->{$key};
			} 
			push @menus,\%webmenu;
		}
	}
	@menus = sort { $a->{'menuname'} cmp $b->{'menuname'} } @menus;
	return @menus;
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	$paramRef->{'pluginCustomBrowseSlimserverMenus'} = Plugins::CustomBrowse::Plugin::getSlimserverMenus();
	my $browseMenusFlat = Plugins::CustomBrowse::Plugin::readBrowseConfiguration($client);

        # Pass on the current pref values and now playing info

	my @menus = initMenus($browseMenusFlat);
	
        $paramRef->{'pluginCustomBrowseMenus'} = \@menus;
	
	if ($paramRef->{'saveSettings'}) {
			my $slimserverMenus = $paramRef->{'pluginCustomBrowseSlimserverMenus'};
			foreach my $menu (@$slimserverMenus) {
				my $menuid = "squeezecenter_".escape($menu->{'id'}."_menu");
				if($paramRef->{$menuid}) {
					$prefs->set($menuid,$paramRef->{$menuid});
				}else {
					$prefs->set($menuid,'');
				}
		}
	}

	my $squeezecenterMenus = $paramRef->{'pluginCustomBrowseSlimserverMenus'};
	foreach my $m (@$squeezecenterMenus) {
		$paramRef->{'squeezecenter_'.$m->{'id'}.'_menu'} = $prefs->get('squeezecenter_'.$m->{'id'}.'_menu');
	}

	return $class->SUPER::handler($client, $paramRef);
}

# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

		
1;
