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
package Plugins::CustomBrowse::EnabledMixers;

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
	return 'PLUGIN_CUSTOMBROWSE_SETTINGS_ENABLEDMIXERS';
}

sub page {
	return 'plugins/CustomBrowse/settings/enabledmixers.html';
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

	my $browseMenusFlat = Plugins::CustomBrowse::Plugin::readBrowseConfiguration($client);
	$paramRef->{'pluginCustomBrowseMixes'} = Plugins::CustomBrowse::Plugin::getMenuHandler()->getGlobalMixes();

	if ($paramRef->{'saveSettings'}) {
		my $browseMixes = $paramRef->{'pluginCustomBrowseMixes'};
		foreach my $mix (keys %$browseMixes) {
			my $mixid = "mix_".escape($browseMixes->{$mix}->{'id'});
			if($paramRef->{$mixid}) {
				$prefs->set($mixid.'_enabled',1);
				$browseMixes->{$mix}->{'enabled'}=1;
			}else {
				$prefs->set($mixid.'_enabled',0);
				$browseMixes->{$mix}->{'enabled'}=0;
			}
		}
	}

	return $class->SUPER::handler($client, $paramRef);
}

# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

		
1;
