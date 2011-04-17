# 				Song Lyrics plugin 
#
#    Copyright (c) 2010 Erland Isaksson (erland_i@hotmail.com)
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
                   
package Plugins::SongLyrics::Plugin;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);
use XML::Simple;
use Slim::Utils::Timers;
use Time::HiRes;

use LWP::UserAgent;
use JSON::XS;
use Data::Dumper;
use Crypt::Tea;

use Plugins::SongLyrics::Modules::LyricsFly;
use Plugins::SongLyrics::Modules::ChartLyrics;
use Plugins::SongLyrics::Modules::Musixmatch;

my $prefs = preferences('plugin.songlyrics');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.songlyrics',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_SONGLYRICS',
});

my $PLUGINVERSION = undef;

my $KEY = undef;

my @lyricsHandlers = (
#	\&Plugins::SongLyrics::Modules::LyricsFly::getLyrics, 
	\&Plugins::SongLyrics::Modules::Musixmatch::getLyrics, 
	\&Plugins::SongLyrics::Modules::ChartLyrics::getLyrics,
);

sub getDisplayName()
{
	return string('PLUGIN_SONGLYRICS'); 
}

sub getKey {
	my $key = shift;
	return Crypt::Tea::decrypt($key,$KEY);
}

sub initPlugin
{
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	$KEY = Slim::Utils::PluginManager->dataForPlugin($class)->{'id'};

	Plugins::SongLyrics::Modules::LyricsFly::init();
	Plugins::SongLyrics::Modules::ChartLyrics::init();
	Plugins::SongLyrics::Modules::Musixmatch::init();

	if(UNIVERSAL::can("Plugins::SongInfo::Plugin","registerInformationModule")) {
                Plugins::SongInfo::Plugin::registerInformationModule('songlyrics',{
                        'name' => string('SONGLYRICS'),
                        'description' => string('PLUGIN_SONGLYRICS_MODULE_DESC'),
                        'developedBy' => 'Erland Isaksson',
			'developedByLink' => 'http://erland.isaksson.info/donate',
			'dataprovidername' => 'musixmatch.com or chartlyrics.com',
                        'function' => \&getSongLyrics,
                        'type' => 'text',
                        'context' => 'track',
                        'jivemenu' => 1,
                        'playermenu' => 1,
                        'webmenu' => 1,
                        'properties' => [
                        ]
                });
        }
}

sub getSongLyrics {
        my $client = shift;
        my $callback = shift;
        my $errorCallback = shift;
        my $callbackParams = shift;
        my $track = shift;
        my $params = shift;
	my $trackTitle = shift;
	my $albumTitle = shift;
	my $artistName = shift;

	my $paramsStructure = {
		'current' => -1,
		'callback' => $callback,
		'errorCallback' => $errorCallback,
		'callbackParams' => $callbackParams,
		'params' => $params,
	};
	executeNextHandler($client,$paramsStructure,$track,$trackTitle,$albumTitle,$artistName);
}

sub executeNextHandler {
	my $client = shift;
	my $params = shift;
	my $track = shift;
	my $trackTitle = shift;
	my $albumTitle = shift;
	my $artistName = shift;

	$params->{'current'} = $params->{'current'}+1;
	$log->debug("Getting lyrics from handler: ".$params->{'current'});
	if(scalar(@lyricsHandlers)>$params->{'current'}) {
		my $handler = $lyricsHandlers[$params->{'current'}];
		$handler->($client,
			$params,
			$track,
			$trackTitle,
			$albumTitle,
			$artistName);
	}else {	
		returnResult($client,$params,undef);
	}
}

sub returnResult {
	my $client = shift;
	my $params = shift;
	my $result = shift;

	my @resultArray = ();
	if(defined($result)) {
		push @resultArray,$result;
	}else {
		$log->info("Lyrics could not be found");
	}
	eval { 
		&{$params->{'callback'}}($client,$params->{'callbackParams'},\@resultArray); 
	};
	if( $@ ) {
	    $log->error("Error sending response: $@");
	}
}

sub returnError {
	my $client = shift;
	my $params = shift;

	eval { 
		&{$params->{'errorCallback'}}($client,$params->{'callbackParams'}); 
	};
	if( $@ ) {
	    $log->error("Error sending response: $@");
	}
}


*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
