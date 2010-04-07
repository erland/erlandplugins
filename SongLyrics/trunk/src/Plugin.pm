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

use LWP::UserAgent;
use JSON::XS;
use Data::Dumper;
use Crypt::Tea;

my $prefs = preferences('plugin.songlyrics');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.songlyrics',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_SONGLYRICS',
});

my $PLUGINVERSION = undef;

my $API_KEY="4232b1161401f867b-temporary.API.access";

sub getDisplayName()
{
	return string('PLUGIN_SONGLYRICS'); 
}

sub initPlugin
{
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};

	if(UNIVERSAL::can("Plugins::SongInfo::Plugin","registerInformationModule")) {
                Plugins::SongInfo::Plugin::registerInformationModule('songlyrics',{
                        'name' => 'Song Lyrics',
                        'description' => "This module gets song lyrics for the specified song, the lyrics are provided by http://lyricsfly.com",
                        'developedBy' => 'Erland Isaksson',
			'developedByLink' => 'http://erland.isaksson.info/donate',
			'dataproviderlink' => 'http://lyricsfly.com',
			'dataprovidername' => 'lyricsfly.com',
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
	if($API_KEY !~ /temporary.API.access/) {
		$API_KEY = Crypt::Tea::decrypt($API_KEY,Slim::Utils::PluginManager->dataForPlugin($class)->{'id'});
	}
}

sub getSongLyrics {
        my $client = shift;
        my $callback = shift;
        my $errorCallback = shift;
        my $callbackParams = shift;
        my $track = shift;
        my $params = shift;

	my $query = "";
	if($track->artist()) {
		$query="&a=".$track->artist()->name."&t=".$track->title();
	}else {
		$query="&l=".$track->title();
	}

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&getSongLyricsResponse, \&gotErrorViaHTTP, {
                client => $client, 
		errorCallback => $errorCallback,
                callback => $callback, 
                callbackParams => $callbackParams,
		params => $params,
        });
	$log->debug("Making call to: http://api.lyricsfly.com/api/api.php?i=???".$query);
	$http->get("http://api.lyricsfly.com/api/api.php?i=".$API_KEY.$query);
}

sub getSongLyricsResponse {
	my $http = shift;
	my $params = $http->params();

	my $content = $http->content();
	my @result = ();
	if(defined($content)) {
		my $xml = eval { XMLin($content, forcearray => ["sg"], keyattr => []) };
		if($xml->{'status'} eq '200' || $xml->{'status'} eq '300') {
			my $lyrics = $xml->{'sg'};
			if($lyrics && scalar(@$lyrics)>0) {
				my $firstLyrics = pop @$lyrics;
				my $text = $firstLyrics->{'tx'};
				$text =~ s/\[br\]//mg;
				$text =~ s/Lyrics delivered by lyricsfly.com//mg;
				my %item = (
					'type' => 'text',
					'text' => $text,
					'providername' => "Lyrics delivered by lyricsfly.com",
					'providerlink' => "http://lyricsfly.com/search/correction.php?".$firstLyrics->{'cs'}."&id=".$firstLyrics->{'id'},
				);
				push @result,\%item;
			}
		}elsif($xml->{'status'} eq '204') {
			$log->info("Failed to get lyrics, not found");
		}else {
			$log->warn("Failed to get lyrics, status: ".$xml->{'status'});
		}
	}

	eval { 
		&{$params->{'callback'}}($params->{'client'},$params->{'callbackParams'},\@result); 
	};
	if( $@ ) {
	    $log->error("Error sending response: $@");
	}
}

sub gotErrorViaHTTP {
	my $http = shift;
	my $params = $http->params();

	eval { 
		&{$params->{'errorCallback'}}($params->{'client'},$params->{'callbackParams'}); 
	};
	if( $@ ) {
	    $log->error("Error sending response: $@");
	}
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
