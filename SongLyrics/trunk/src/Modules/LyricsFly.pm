# 				LyricsFly module for Song Lyrics plugin 
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
                   
package Plugins::SongLyrics::Modules::LyricsFly;

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

my $prevRequest = Time::HiRes::time();
my $lastRequest = Time::HiRes::time();

sub init {
	#Please don't use this key in other applications, you can apply for one for free at lyricsfly.com
	if(!defined($API_KEY) || $API_KEY !~ /temporary.API.access/) {
		$API_KEY = Plugins::SongLyrics::Plugin::getKey("YOZVbVbovftAlDGdSg6-M43wGmtbi4yA37cJ28pCiKpA0Ne_\n37cPPKE1vSpgIFUrn44iDd56NtIyl6Bj8nnVkw");
	}
}

sub getLyrics {
        my $client = shift;
        my $params = shift;
        my $track = shift;
	my $trackTitle = shift;
	my $albumTitle = shift;
	my $artistName = shift;

	$log->info("Getting lyrics from lyricsfly.com");
	my $query = "";
	if($artistName) {
		$query="&a=".$artistName."&t=".$trackTitle;
	}else {
		$query="&l=".$trackTitle;
	}

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&getLyricsFlyResponse, \&gotErrorViaHTTP, {
                client => $client, 
		params => $params,
		track => $track,
		trackTitle => $trackTitle,
		albumTitle => $albumTitle,
		artistName => $artistName,
        });
	$prevRequest = $lastRequest;
	$lastRequest = Time::HiRes::time;
	$log->debug("Making call to: http://api.lyricsfly.com/api/api.php?i=???".$query);
	$http->get("http://api.lyricsfly.com/api/api.php?i=".$API_KEY.$query);
}

sub getLyricsFlyResponse {
	my $http = shift;
	my $params = $http->params();

	my $content = $http->content();
	if(defined($content)) {
		my $xml = eval { XMLin($content, forcearray => ["sg"], keyattr => []) };
		if($xml->{'status'} eq '200' || $xml->{'status'} eq '300') {
			$log->debug("Got lyrics: ".Dumper($xml));
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
					'providerlink' => "http://lyricsfly.com",
				);
				Plugins::SongLyrics::Plugin::returnResult($params->{'client'},$params->{'params'},\%item);
				return;
			}
		}elsif($xml->{'status'} eq '204') {
			$log->debug("Failed to get lyrics from lyricsfly.com, not found");
		}elsif($xml->{'status'} eq '402') {
			# Our request is too soon, let's request again in the specified time interval
			my $nextCall = $prevRequest+($xml->{'delay'}/1000)+0.5;
			$log->info("Request too soon after ".$prevRequest." at ".Time::HiRes::time().", needs to wait ".$xml->{'delay'}.", requesting again at $nextCall");
			my @timerParams = ();
			push @timerParams, $params->{'params'};
			push @timerParams, $params->{'track'};
			push @timerParams, $params->{'trackTitle'};
			push @timerParams, $params->{'albumTitle'};
			push @timerParams, $params->{'artistName'};

			Slim::Utils::Timers::setTimer($params->{'client'}, $nextCall, \&getLyrics,@timerParams);
			return;
		}else {
			$log->info("Failed to get lyrics from lyricsfly.com, status: ".$xml->{'status'});
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
