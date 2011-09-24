# 				CustomScan plugin 
#
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
#
#    The LastFM scanning module uses the webservices from audioscrobbler.
#    Please respect audioscrobbler terms of service, the content of the 
#    feeds are licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License
#
#    The Amazon scanning module uses the webservies from amazon.com
#    Please respect amazon.com terms of service, the usage of the 
#    feeds are free but restricted to the Amazon Web Services Licensing Acgreement
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

package Plugins::CustomScan::Importer;

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;
use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;
use POSIX qw(ceil);
use File::Spec::Functions qw(:ALL);
use DBI qw(:sql_types);
use FindBin qw($Bin);
use Plugins::CustomScan::Template::Reader;
use Plugins::CustomScan::Scanner;
use Plugins::CustomScan::MixedTagSQLPlayListHandler;
use Scalar::Util qw(blessed);

our $PLUGINVERSION =  undef;

my $prefs = preferences('plugin.customscan');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.customscan',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_CUSTOMSCAN',
});

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
        # Setup post processing work
        Slim::Music::Import->addImporter('Plugins::CustomScan::Scanner', {
                'type'          => 'post',
                'use'           => 1,
                'weight'        => 80,
        });
}

sub postinitPlugin {
	Plugins::CustomScan::Scanner::initScanner($PLUGINVERSION,0);
	Slim::Control::Request::addDispatch(['customscan', 'changedstatus', '_module','_status'],[0, 0, 0, undef]);
}

sub shutdownPlugin {
        $log->info("disabling\n");
	Plugins::CustomScan::Scanner::shutdownScanner();
}

sub getPluginModules {
	return Plugins::CustomScan::Scanner::getPluginModules();
}

1;

__END__
