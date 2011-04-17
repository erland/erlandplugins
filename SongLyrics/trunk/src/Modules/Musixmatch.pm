# 				Musixmatch module for Song Lyrics plugin 
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
                   
package Plugins::SongLyrics::Modules::Musixmatch;

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

my $API_KEY=undef;

sub init {
	#Please don't use this key in other applications, you can apply for one for free at musixmatch.com
	$API_KEY = Plugins::SongLyrics::Plugin::getKey("RrY3ol64enZIz7KjVOgEn2UHjJrm3f6klCeSMIVQ2edL9iIg\nrFjo4Q");
}

sub getLyrics {
        my $client = shift;
        my $params = shift;
        my $track = shift;
	my $trackTitle = shift;
	my $albumTitle = shift;
	my $artistName = shift;
	
	$log->info("Getting lyrics from musixmatch.com");
	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&getMusiXmatchTrackResponse, \&gotErrorViaHTTP, {
			client => $client, 
			params => $params,
			track => $track,
			trackTitle => $trackTitle,
			albumTitle => $albumTitle,
			artistName => $artistName,
			
		});
	if($trackTitle =~ /\s*\(fea.+\)$/) {
		$trackTitle =~ s/\s*\(fea.+\)$//;
	}
	if($trackTitle =~ /\s*\(Fea.+\)$/) {
		$trackTitle =~ s/\s*\(Fea.+\)$//;
	}
	$http->get("http://api.musixmatch.com/ws/1.1/track.search?apikey=".$API_KEY."&q_artist=".escape($artistName)."&q_track=".$trackTitle."&format=xml&page_size=1&f_has_lyrics=1");
}
sub getMusiXmatchTrackResponse {
	my $http = shift;
	my $params = $http->params();

	my $content = $http->content();
	my @result = ();
	if(defined($content)) {
		my $xml = eval { XMLin($content, forcearray => [], keyattr => []) };
		$log->debug("Got MusiXmatch track result: ".Dumper($xml));
		if(defined($xml) && defined($xml->{'body'}) && defined($xml->{'body'}->{'track_list'}) && defined($xml->{'body'}->{'track_list'}->{'track'})) {
			my $trackId = $xml->{'body'}->{'track_list'}->{'track'}->{'track_id'};
			if(defined($trackId)) {
				my $http = Slim::Networking::SimpleAsyncHTTP->new(\&getMusiXmatchLyricsResponse, \&gotErrorViaHTTP, {
						client => $params->{'client'}, 
						params => $params->{'params'},
						track => $params->{'track'},
						trackTitle => $params->{'trackTitle'},
						albumTitle => $params->{'albumTitle'},
						artistName => $params->{'artistName'},
				
					});
				$http->get("http://api.musixmatch.com/ws/1.1/track.lyrics.get?track_id=".$trackId."&format=xml&apikey=$API_KEY");
				return;
			}
		}
	}
	Plugins::SongLyrics::Plugin::executeNextHandler($params->{'client'},
		$params->{'params'},
		$params->{'track'},
		$params->{'trackTitle'},
		$params->{'albumTitle'},
		$params->{'artistName'});
}

sub getMusiXmatchLyricsResponse {
	my $http = shift;
	my $params = $http->params();

	my $content = $http->content();
	if(defined($content)) {
		my $xml = eval { XMLin($content, forcearray => [], keyattr => []) };
		$log->debug("Got MusiXmatch lyrics result: ".Dumper($xml));
		if(defined($xml) && defined($xml->{'body'}) && defined($xml->{'body'}->{'lyrics'}) && defined($xml->{'body'}->{'lyrics'}->{'lyrics_body'})) {
			my $text = $xml->{'body'}->{'lyrics'}->{'lyrics_body'};
			if(ref($text) ne 'HASH') {
				my %item = (
					'type' => 'text',
					'text' => $text,
					'providername' => "Lyrics delivered by musixmatch.com",
					'providerlink' => "http://musixmatch.com",
				);
				Plugins::SongLyrics::Plugin::returnResult($params->{'client'},$params->{'params'},\%item);
				return;
			}
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

        Plugins::SongLyrics::Plugin::executeNextHandler($params->{'client'},
                $params->{'params'},
                $params->{'track'},
                $params->{'trackTitle'},
                $params->{'albumTitle'},
                $params->{'artistName'});
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
