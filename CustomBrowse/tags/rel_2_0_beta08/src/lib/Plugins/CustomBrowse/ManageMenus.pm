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
package Plugins::CustomBrowse::ManageMenus;

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
	return 'PLUGIN_CUSTOMBROWSE_SETTINGS_MANAGEMENUS';
}

sub page {
	return 'plugins/CustomBrowse/webadminmethods_edititems.html';
}

sub currentPage {
	my ($class, $client, $params) = @_;
	if($params->{'webadminmethodshandler'}) {
		return Slim::Utils::Strings::string('PLUGIN_CUSTOMBROWSE_SETTINGS_MANAGECONTEXTMENUS');
	}else {
		return Slim::Utils::Strings::string('PLUGIN_CUSTOMBROWSE_SETTINGS_MANAGEMENUS');
	}
}

sub pages {
	my %pageMenu = (
		'name' => Slim::Utils::Strings::string('PLUGIN_CUSTOMBROWSE_SETTINGS_MANAGEMENUS'),
		'page' => page(),
	);
	my %pageContextMenu = (
		'name' => Slim::Utils::Strings::string('PLUGIN_CUSTOMBROWSE_SETTINGS_MANAGECONTEXTMENUS'),
		'page' => page().'?webadminmethodshandler=context',
	);
	my @pages = (\%pageMenu,\%pageContextMenu);
	return \@pages;
}

sub prepare {
	my ($class, $client, $params) = @_;
	$class->SUPER::handler($client, $params);
}

sub handler {
	my ($class, $client, $params) = @_;
	if($params->{'webadminmethodshandler'} eq 'context') {
		$params->{'pluginWebAdminMethodsHandler'} = 'context';
	}
	return Plugins::CustomBrowse::Plugin::handleWebEditMenus($client,$params);
}

		
1;
