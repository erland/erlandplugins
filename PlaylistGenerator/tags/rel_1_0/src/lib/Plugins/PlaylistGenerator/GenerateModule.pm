#         Export module
#
#    Copyright (c) 2009 Erland Isaksson (erland_i@hotmail.com)
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
                   
package Plugins::PlaylistGenerator::GenerateModule;

use Slim::Utils::Prefs;
use Date::Parse qw(str2time);
use Fcntl ':flock'; # import LOCK_* constants
use POSIX qw(strftime);
use File::Spec::Functions qw(:ALL);
use DBI qw(:sql_types);
use Slim::Utils::Misc;
use Plugins::CustomScan::Validators;
use Slim::Player::Playlist;
use Time::Stopwatch;

my $prefs = preferences('plugin.playlistgenerator');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.playlistgenerator',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_PLAYLISTGENERATOR',
});


sub getPlaylists {
	my $playlistDefinitions = Plugins::PlaylistGenerator::Plugin::getPlaylistDefinitions();
	my @webPlaylistDefinitions = ();
	for my $key (keys %$playlistDefinitions) {
		my %webPlaylistDefinition = ();
		my $playlistDefinition = $playlistDefinitions->{$key};
		$webPlaylistDefinition{'id'} = $playlistDefinition->{'id'};
		$webPlaylistDefinition{'name'} = $playlistDefinition->{'name'};
		push @webPlaylistDefinitions,\%webPlaylistDefinition;
	}
	@webPlaylistDefinitions = sort { $a->{'name'} cmp $b->{'name'} } @webPlaylistDefinitions;
	return \@webPlaylistDefinitions;
}

sub getCustomScanFunctions {
	
	my %functions = (
		'id' => 'playlistgenerator',
		'order' => '75',
		'defaultenabled' => 0,
		'name' => 'Playlist Generator',
		'description' => "This module updates all static playlists that has been defined with the Playlist Generator plugin",
		'developedBy' => 'Erland Isaksson',
		'developedByLink' => 'http://erland.isaksson.info/donate', 
		'alwaysRescanTrack' => 1,
		'clearEnabled' => 0,
		'requiresRefresh' => 0,
		'initScanTrack' => \&initScanTrack,
		'exitScanTrack' => \&exitScanTrack,
		'scanText' => 'Generate',
		'properties' => [
			{
				'id' => 'playlistgeneratorplaylists',
				'name' => 'Playlists to generate',
				'description' => 'Playlists to generate, no selected means that all playlists will be generated',
				'type' => 'multiplelist',
				'values' => getPlaylists(),
				'value' => '',
			},
		]
	);
	return \%functions;
		
}
sub initScanTrack {
	my $playlists = Plugins::CustomScan::Plugin::getCustomScanProperty("playlistgeneratorplaylists")||'';
	my @selectedPlaylists = split(/,/,$playlists);
	if(scalar(@selectedPlaylists)>0) {
		Plugins::PlaylistGenerator::Generator::init(@selectedPlaylists);
	}else {
		Plugins::PlaylistGenerator::Generator::init();
	}
	return undef;
}

sub exitScanTrack
{
	return Plugins::PlaylistGenerator::Generator::next();
}


# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

# don't use the external one because it doesn't know about the difference
# between a param and not...
#*unescape = \&URI::Escape::unescape;
sub unescape {
        my $in      = shift;
        my $isParam = shift;

        $in =~ s/\+/ /g if $isParam;
        $in =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

        return $in;
}

1;

__END__
