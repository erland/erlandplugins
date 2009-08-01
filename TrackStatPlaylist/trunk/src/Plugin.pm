# 				TrackStatPlaylist plugin 
#
#    Copyright (c) 2008 Erland Isaksson (erland_i@hotmail.com)
#
#    Portions of code derived from the iTunesUpdate 1.5 plugin
#    Copyright (c) 2004-2006 James Craig (james.craig@london.com)
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
                   
package Plugins::TrackStatPlaylist::Plugin;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;
use Slim::Player::Client;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);

use File::Spec::Functions qw(:ALL);
use DBI qw(:sql_types);

use Scalar::Util qw(blessed);

my $prefs = preferences('plugin.trackstatplaylist');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.trackstatplaylist',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_TRACKSTATPLAYLIST',
});

my $PLUGINVERSION = undef;

sub getDisplayName()
{
	return string('PLUGIN_TRACKSTATPLAYLIST'); 
}

sub getCustomScanFunctions {
	my @result = ();
	#eval "use Plugins::TrackStatPlaylist::Import";
	#if( $@ ) { $log->warn("Unable to load TrackStatPlaylist::Import: $@\n"); }
	eval "use Plugins::TrackStatPlaylist::Export";
	if( $@ ) { $log->warn("Unable to load TrackStatPlaylist::Export: $@\n"); }
	push @result,Plugins::TrackStatPlaylist::Export::getCustomScanFunctions();
	#push @result,Plugins::TrackStatPlaylist::Import::getCustomScanFunctions();
	return \@result;
}


sub initPlugin
{
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
}

sub postinitPlugin {
	if(isPluginsInstalled(undef,"CustomScan::Plugin")) {
		#eval "use Plugins::TrackStatPlaylist::Import";
		eval "use Plugins::TrackStatPlaylist::Export";
	}
}

sub setTrackStatRating {
	my ($client,$url,$rating,$type)=@_;
	$log->debug("Entering setTrackStatRating\n");

	my $track = undef;
	eval {
		$track = Slim::Schema->objectForUrl({
			'url' => $url
		});
	};
	if ($@) {
		$log->warn("Error retrieving track: $url\n");
	}
	if(isPluginsInstalled($client,"CustomScan::Plugin")) {
		Plugins::TrackStatPlaylist::Export::exportRating($client,$url,$rating,$track,$type);
	}
	$log->debug("Exiting setTrackStatRating\n");
}

sub setTrackStatStatistic {
	$log->debug("Entering setTrackStatStatistic\n");
	my ($client,$url,$statistic)=@_;
	
	my $playCount = $statistic->{'playCount'};
	my $lastPlayed = $statistic->{'lastPlayed'};	
	my $rating = $statistic->{'rating'};

	if(isPluginsInstalled($client,"CustomScan::Plugin")) {
		Plugins::TrackStatPlaylist::Export::exportStatistic($client,$url,$rating,$playCount,$lastPlayed);
	}
	$log->debug("Exiting setTrackStatStatistic\n");
}


sub isPluginsInstalled {
	my $client = shift;
	my $pluginList = shift;
	my $enabledPlugin = 1;
	foreach my $plugin (split /,/, $pluginList) {
		if($enabledPlugin) {
			$enabledPlugin = grep(/$plugin/, Slim::Utils::PluginManager->enabledPlugins($client));
		}
	}
	return $enabledPlugin;
}

1;

__END__
