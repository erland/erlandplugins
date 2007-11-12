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
package Plugins::MultiLibrary::Settings;

use strict;
use base qw(Plugins::MultiLibrary::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings;

my $prefs = preferences('plugin.multilibrary');
my $log   = logger('plugin.multilibrary');

my $plugin; # reference to main plugin

sub new {
	my $class = shift;
	$plugin   = shift;

	$class->SUPER::new($plugin);
}

sub name {
	return 'PLUGIN_MULTILIBRARY_SETTINGS';
}

sub page {
	return 'plugins/MultiLibrary/settings/basic.html';
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
        return ($prefs, qw(library_directory template_directory refresh_save refresh_rescan refresh_startup question_startup custombrowse_menus utf8filenames));
}
sub handler {
	my ($class, $client, $paramRef) = @_;

	# TODO: Handle properties attribute
	my $result = $class->SUPER::handler($client, $paramRef);
	if ($paramRef->{'saveSettings'}) {
		Plugins::MultiLibrary::Plugin::getConfigManager()->initWebAdminMethods();
	}	
	return $result;
}

		
1;
