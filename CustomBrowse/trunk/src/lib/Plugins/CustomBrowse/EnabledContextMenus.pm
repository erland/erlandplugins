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
package Plugins::CustomBrowse::EnabledContextMenus;

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
	return 'PLUGIN_CUSTOMBROWSE_SETTINGS_ENABLEDCONTEXTMENUS';
}

sub page {
	return 'plugins/CustomBrowse/settings/enabledcontextmenus.html';
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
	my $contextBrowseMenusFlat = shift;
	my @contextMenus = ();
	for my $key (keys %$contextBrowseMenusFlat) {
		my %webmenu = ();
		my $menu = $contextBrowseMenusFlat->{$key};
		for my $key (keys %$menu) {
			$webmenu{$key} = $menu->{$key};
		} 
		if(defined($webmenu{'menuname'}) && defined($webmenu{'menugroup'})) {
			$webmenu{'menuname'} = $webmenu{'menugroup'}.'/'.$webmenu{'menuname'};
		}
		push @contextMenus,\%webmenu;
	}
	@contextMenus = sort { $a->{'menuname'} cmp $b->{'menuname'} } @contextMenus;
	return @contextMenus;
}
sub handler {
	my ($class, $client, $paramRef) = @_;

	my $contextBrowseMenusFlat = Plugins::CustomBrowse::Plugin::readContextBrowseConfiguration($client);

	my @contextMenus = initMenus($contextBrowseMenusFlat);
        $paramRef->{'pluginCustomBrowseContextMenus'} = \@contextMenus;

	if ($paramRef->{'saveSettings'}) {
	        foreach my $menu (keys %$contextBrowseMenusFlat) {
	                my $menuid = "context_menu_".escape($contextBrowseMenusFlat->{$menu}->{'id'});
	                if($paramRef->{$menuid}) {
	                        $prefs->set($menuid.'_enabled',1);
				$contextBrowseMenusFlat->{$menu}->{'enabled'}=1;
	                }else {
	                        $prefs->set($menuid.'_enabled',0);
				$contextBrowseMenusFlat->{$menu}->{'enabled'}=0;
	                }
	        }
		my @contextMenus = initMenus($contextBrowseMenusFlat);
	        $paramRef->{'pluginCustomBrowseContextMenus'} = \@contextMenus;
        }

	return $class->SUPER::handler($client, $paramRef);
}

# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

		
1;
