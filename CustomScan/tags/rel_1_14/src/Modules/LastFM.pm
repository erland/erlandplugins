#         CustomScan::Modules::LastFM module
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
# 
#    This scanning module uses the webservices from audioscrobbler.
#    Please respect audioscrobbler terms of service, the content of the 
#    feeds are licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License
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
                   
package Plugins::CustomScan::Modules::LastFM;

use Slim::Utils::Misc;
use XML::Simple;
#use Data::Dumper;

my $lastCalled = undef;

sub getCustomScanFunctions {
	my %functions = (
		'id' => 'cslastfm',
		'name' => 'LastFM',
		'description' => "This module scans lastfm.com for all your artists, the scanned information included similar artists and lastfm tags for the artist<br><br>Please note that the information read is only free to use for non commercial usage, see the LastFM licence for more information.<br><br>The LastFM module is quite slow, the reason for this is that LastFM restricts the number of calls per second towards their services in the licenses. Please respect these licensing rules. This also results in that slimserver will perform quite bad during scanning when this scanning module is active. The information will only be scanned once for each artist, so the next time it will only scan new artists and will be a lot faster due to this. Approximately scanning time for this module is 1-2 seconds per artist in your library",
		'dataproviderlink' => 'http://www.last.fm',
		'dataprovidername' => 'Audioscrobbler/LastFM',
		'scanArtist' => \&scanArtist,
		'properties' => [
			{
				'id' => 'lastfmsimilarartistpercent',
				'name' => 'Similarity percentage',
				'description' => 'The percentage of similarity that an artist must have to be included as a similar artist',
				'type' => 'text',
				'value' => 80
			},
			{
				'id' => 'lastfmtagspercent',
				'name' => 'Tag percentage',
				'description' => 'The percentage a tag must have to be included',
				'type' => 'text',
				'value' => 10
			}
		]
	);
	return \%functions;
		
}

sub scanArtist {
	my $artist = shift;
	my @result = ();
	
	debugMsg("Scanning artist: ".$artist->name."\n");

	# **** Scan for related artists and picture for artist **** 
	my $similarArtistLimit = Plugins::CustomScan::Plugin::getCustomScanProperty("lastfmsimilarartistpercent");
	if(!defined($similarArtistLimit)) {
		$similarArtistLimit = 80;
	}
	my $url = "http://ws.audioscrobbler.com/1.0/artist/".escape($artist->name)."/similar.xml";
	my $currentTime = time();

	# We need to wait for 1-2 seconds to not overload LastFM web services (this is specified in their license)
	if(defined($lastCalled) && $currentTime<($lastCalled+2)) {
		sleep(1);
	}
	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "$url",
		'create' => 0, 	 
	});
	$lastCalled = time();
	if(defined($http)) {
		my $xml = eval { XMLin($http->content, forcearray => ["artist"], keyattr => []) };
		#msg("Got xml:\n".Dumper($xml)."\n");
		my $similarartists = $xml->{'artist'};
		if($similarartists) {
			if(ref($similarartists) eq 'ARRAY') {
				for my $similarartist (@$similarartists) {
					if(ref($similarartist) eq 'HASH') {
						if($similarartist->{'match'}>$similarArtistLimit) {
							my %item = (
								'name' => 'similarartist',
								'value' => $similarartist->{'name'},
								'extravalue' => $similarartist->{'match'}
							);
							push @result,\%item;
							#msg("CustomScan::LastFM: Adding tag: ".$similarartist->{'name'}."\n");
						}
					}
				}
			}
		}
		if(defined($xml->{'picture'}) && $xml->{'picture'} ne '') {
			my %item = (
				'name' => 'picture',
				'value' => $xml->{'picture'}
			);
			push @result,\%item;
		}
		$http->close();
	}
	$http = undef;




	# **** Scan for top tags for artist **** 
	my $topTagsLimit = Plugins::CustomScan::Plugin::getCustomScanProperty("lastfmtagspercent");
	if(!defined($topTagsLimit)) {
		$topTagsLimit = 10;
	}
	$url = "http://ws.audioscrobbler.com/1.0/artist/".escape($artist->name)."/toptags.xml";
	$currentTime = time();

	# We need to wait for 1-2 seconds to not overload LastFM web services (this is specified in their license)
	if(defined($lastCalled) && $currentTime<($lastCalled+2)) {
		sleep(1);
	}
	$http = Slim::Player::Protocols::HTTP->new({
		'url'    => "$url",
		'create' => 0, 	 
	});
	$lastCalled = time();
	if(defined($http)) {
		my $xml = eval { XMLin($http->content, forcearray => ["tag"], keyattr => []) };
		#msg("Got xml:\n".Dumper($xml)."\n");
		my $tags = $xml->{'tag'};
		if($tags) {
			for my $tag (@$tags) {
				if($tag->{'count'}>$topTagsLimit) {
					my %item = (
						'name' => 'artisttag',
						'value' => $tag->{'name'},
						'extravalue' => $tag->{'count'}
					);
					push @result,\%item;
					#msg("CustomScan::LastFM: Adding tag: ".$tag->{'name'}."\n");
				}
			}
		}
		$http->close();
	}
	$http = undef;

	# Lets just add dummy item to store that we have scanned this artist
	my %item = (
		'name' => 'retrieved',
		'value' => 1
	);
	push @result,\%item;

	return \@result;
}


sub debugMsg
{
	my $message = join '','CustomScan:LastFM ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_customscan_showmessages"));
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
