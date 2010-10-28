# 				ChartLyrics module for Song Lyrics plugin 
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
                   
package Plugins::SongLyrics::Modules::ChartLyrics;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);
use XML::Simple;
use Slim::Utils::Timers;
use Time::HiRes;

use LWP::UserAgent;
use JSON::XS;
use Data::Dumper;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.songlyrics',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_SONGLYRICS',
});

sub init {
}

sub getLyrics {
        my $client = shift;
        my $params = shift;
        my $track = shift;
	my $trackTitle = shift;
	my $albumTitle = shift;
	my $artistName = shift;

	$log->info("Getting lyrics from chartlyrics.com");
	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&getChartLyricsResponse, \&gotErrorViaHTTP, {
			client => $client, 
			params => $params,
			track => $track,
			trackTitle => $trackTitle,
			albumTitle => $albumTitle,
			artistName => $artistName,
			
		});
	$http->get("http://api.chartlyrics.com/apiv1.asmx/SearchLyricDirect?artist=".$artistName."&song=".$trackTitle);
}
sub getChartLyricsResponse {
	my $http = shift;
	my $params = $http->params();

	my $content = $http->content();
	if(defined($content)) {
		my $xml = eval { XMLin($content, forcearray => [], keyattr => []) };
		$log->debug("Got lyrics: ".Dumper($xml));
		if(defined($xml) && defined($xml->{'Lyric'}) && ref($xml->{'Lyric'}) ne 'HASH' && $xml->{'Lyric'} ne "") {
				my $text = $xml->{'Lyric'};
				my %item = (
					'type' => 'text',
					'text' => $text,
					'providername' => "Lyrics delivered by chartlyrics.com",
					'providerlink' => "http://chartlyrics.com",
				);
				Plugins::SongLyrics::Plugin::returnResult($params->{'client'},$params->{'params'},\%item);
				return;
		}
	}
	Plugins::SongLyrics::Plugin::executeNextHandler($params->{'client'},
		$params->{'params'},
		$params->{'track'},
		$params->{'trackTitle'},
		$params->{'albumTitle'},
		$params->{'artistName'});
}

sub gotErrorViaHTTP {
	my $http = shift;
	my $params = $http->params();

	Plugins::SongLyrics::Plugin::returnError($params->{'client'},$params->{'params'});
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
