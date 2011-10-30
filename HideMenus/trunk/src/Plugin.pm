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

use strict;
use warnings;
                   
package Plugins::HideMenus::Plugin;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);

use LWP::UserAgent;
use JSON::XS;
use Data::Dumper;

use Plugins::HideMenus::MenuSettings;

my $prefs = preferences('plugin.hidemenus');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.hidemenus',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_HIDEMENUS',
});

my $PLUGINVERSION = undef;

sub getDisplayName()
{
	return string('PLUGIN_HIDEMENUS'); 
}

sub initPlugin
{
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	Plugins::HideMenus::MenuSettings->new($class);
	Slim::Menu::BrowseLibrary->registerNodeFilter(\&filterForMyMusic);
}

sub filterForMyMusic {
	my $client = shift;
	my $menuId = shift;

	if(!defined($prefs->get('menu_'.$menuId))) {
		return 1;
	}else {
		return $prefs->get('menu_'.$menuId);
	}
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
