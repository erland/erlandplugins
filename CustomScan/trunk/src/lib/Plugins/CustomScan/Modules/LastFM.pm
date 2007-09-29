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
use File::Spec::Functions qw(:ALL);
#use Data::Dumper;
use Slim::Utils::Prefs;
my $prefs = preferences('plugin.customscan');
use Slim::Utils::Log;
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.customscan',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_CUSTOMSCAN',
});

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
				'validate' => \&Slim::Utils::Validate::isInt,
				'value' => 80
			},
			{
				'id' => 'lastfmtagspercent',
				'name' => 'Tag percentage',
				'description' => 'The percentage a tag must have to be included',
				'type' => 'text',
				'validate' => \&Slim::Utils::Validate::isInt,
				'value' => 10
			},
			{
				'id' => 'lastfmpicturedir',
				'name' => 'Picture directory',
				'description' => 'The directory where LastFM pictures should be cached, if not specified they will not be cached',
				'type' => 'text',
				'validate' => \&validateIsDirOrEmpty,
				'value' => ''
			}
		]
	);
	return \%functions;
		
}

sub validateIsDirOrEmpty {
	my $arg = shift;
	if(!$arg || $arg eq '') {
		return $arg;
	}else {
		return Slim::Utils::Validate::isDir($arg);
	}
}

sub scanArtist {
	my $artist = shift;
	my @result = ();
	
	$log->debug("Scanning artist: ".$artist->name."\n");

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
		#$log->debug("Got xml:\n".Dumper($xml)."\n");
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
							#$log->debug("CustomScan::LastFM: Adding tag: ".$similarartist->{'name'}."\n");
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

			# **** Cache images if a picture directory has been specified **** 
			my $pictureDir=Plugins::CustomScan::Plugin::getCustomScanProperty("lastfmpicturedir");
			if(defined($pictureDir) && $pictureDir ne '' && -d $pictureDir) {
				my $url = $item{'value'};
				if($url =~ /.*\.([^.]+$)/) {
					my $extension = $1;
					$http = Slim::Player::Protocols::HTTP->new({
        					'url'    => $item{'value'},
				        	'create' => 0,
				    	});
				    	if(defined($http)) {
						my $file = catfile($pictureDir,$artist->name.".".$extension);
						my $fh;
						open($fh,"> $file") or do {
					            msg ("CustomScan:LastFM: Error saving image for ".$artist->name."\n");
						};
						if(defined($fh)) {
							print $fh $http->content();
							close $fh;
						}
					    	$http->close();
					}else {
						msg ("CustomScan:LastFM: Failed to download ".$artist->name." image: ".$item{'value'}."\n");
					}
				}
			}
		}
	    	if(defined($http)) {
			$http->close();
		}
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
		#$log->debug("Got xml:\n".Dumper($xml)."\n");
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
					#$log->debug("CustomScan::LastFM: Adding tag: ".$tag->{'name'}."\n");
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

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
