#         SongInfo::Modules::LastFM module
#    Copyright (c) 2010 Erland Isaksson (erland_i@hotmail.com)
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
                   
package Plugins::SongInfo::Modules::LastFM;

use Slim::Utils::Misc;
use XML::Simple;
use File::Spec::Functions qw(:ALL);
#use Data::Dumper;
use Slim::Utils::Prefs;
use Plugins::SongInfo::Validators;
use LWP::UserAgent;
my $prefs = preferences('plugin.songinfo');
my $serverPrefs = preferences('server');
use Slim::Utils::Log;
use Data::Dumper;
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.songinfo',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_SONGINFO',
});

# Please, do NOT use this key for other purposes than this plugin
# you can freely apply for your own key at http://www.lastfm.com/api
my $API_KEY = "719216c369dd619aa30debb89e96fdba";

sub getSongInfoFunctions {
	my $functions = {
		'lastfmsimilarartists' => {
			'name' => 'LastFM Similar Artists',
			'description' => "This module gets information about similar artists",
			'developedBy' => 'Erland Isaksson',
			'developedByLink' => 'http://erland.isaksson.info/donate',
			'dataproviderlink' => 'http://www.last.fm',
			'dataprovidername' => 'Audioscrobbler/LastFM',
			'function' => \&getSimilarArtists,
			'type' => 'text',
			'context' => 'artist',
			'properties' => [
				{
					'id' => 'lastfmsimilarartistpercent',
					'name' => 'Similarity percentage',
					'description' => 'The percentage of similarity that an artist must have to be included as a similar artist',
					'type' => 'text',
					'validate' => \&Plugins::SongInfo::Validators::isInt,
					'value' => 80
				},
			]
		},
		'lastfmsimilarartistsimages' => {
			'name' => 'LastFM Similar Artists',
			'description' => "This module gets images of similar artists",
			'developedBy' => 'Erland Isaksson',
			'developedByLink' => 'http://erland.isaksson.info/donate',
			'dataproviderlink' => 'http://www.last.fm',
			'dataprovidername' => 'Audioscrobbler/LastFM',
			'function' => \&getSimilarArtistsImages,
			'type' => 'text',
			'context' => 'artist',
			'properties' => [
				{
					'id' => 'lastfmsimilarartistpercent',
					'name' => 'Similarity percentage',
					'description' => 'The percentage of similarity that an artist must have to be included as a similar artist',
					'type' => 'text',
					'validate' => \&Plugins::SongInfo::Validators::isInt,
					'value' => 80
				},
			]
		},
		'lastfmtracktags' => {
			'name' => 'LastFM Song Tags',
			'description' => "This module gets information about LastFM tags of a song",
			'developedBy' => 'Erland Isaksson',
			'developedByLink' => 'http://erland.isaksson.info/donate',
			'dataproviderlink' => 'http://www.last.fm',
			'dataprovidername' => 'Audioscrobbler/LastFM',
			'function' => \&getTrackTags,
			'type' => 'text',
			'context' => 'track',
			'properties' => [
				{
					'id' => 'lastfmtagspercent',
					'name' => 'Tag percentage',
					'description' => 'The percentage a tag must have to be included',
					'type' => 'text',
					'validate' => \&Plugins::SongInfo::Validators::isInt,
					'value' => 10
				},
			]
		},
		'lastfmartisttags' => {
			'name' => 'LastFM Artist Tags',
			'description' => "This module gets information about LastFM tags of an artist",
			'developedBy' => 'Erland Isaksson',
			'developedByLink' => 'http://erland.isaksson.info/donate',
			'dataproviderlink' => 'http://www.last.fm',
			'dataprovidername' => 'Audioscrobbler/LastFM',
			'function' => \&getArtistTags,
			'type' => 'text',
			'context' => 'artist',
			'properties' => [
				{
					'id' => 'lastfmtagspercent',
					'name' => 'Tag percentage',
					'description' => 'The percentage a tag must have to be included',
					'type' => 'text',
					'validate' => \&Plugins::SongInfo::Validators::isInt,
					'value' => 10
				},
			]
		},
		'lastfmartistimages' => {
			'name' => 'LastFM Artist Images',
			'description' => "This module gets artist images from LastFM tags",
			'developedBy' => 'Erland Isaksson',
			'developedByLink' => 'http://erland.isaksson.info/donate',
			'dataproviderlink' => 'http://www.last.fm',
			'dataprovidername' => 'Audioscrobbler/LastFM',
			'function' => \&getArtistImages,
			'type' => 'image',
			'context' => 'artist',
			'properties' => [
			]
		},
		'lastfmalbumimage' => {
			'name' => 'LastFM Album Image',
			'description' => "This module gets album image from LastFM",
			'developedBy' => 'Erland Isaksson',
			'developedByLink' => 'http://erland.isaksson.info/donate',
			'dataproviderlink' => 'http://www.last.fm',
			'dataprovidername' => 'Audioscrobbler/LastFM',
			'function' => \&getAlbumImage,
			'type' => 'image',
			'context' => 'album',
			'properties' => [
			]
		},
		'lastfmartistbio' => {
			'name' => 'LastFM Artist Biography',
			'description' => "This module gets artist biography from LastFM",
			'developedBy' => 'Erland Isaksson',
			'developedByLink' => 'http://erland.isaksson.info/donate',
			'dataproviderlink' => 'http://www.last.fm',
			'dataprovidername' => 'Audioscrobbler/LastFM',
			'function' => \&getArtistInfoBiography,
			'type' => 'text',
			'context' => 'artist',
			'properties' => [
			]
		},
		'lastfmalbumdesc' => {
			'name' => 'LastFM Album Description',
			'description' => "This module gets album description from LastFM",
			'developedBy' => 'Erland Isaksson',
			'developedByLink' => 'http://erland.isaksson.info/donate',
			'dataproviderlink' => 'http://www.last.fm',
			'dataprovidername' => 'Audioscrobbler/LastFM',
			'function' => \&getAlbumInfoDescription,
			'type' => 'text',
			'context' => 'album',
			'properties' => [
			]
		},
		'lastfmtrackdesc' => {
			'name' => 'LastFM Track Description',
			'description' => "This module gets track description from LastFM",
			'developedBy' => 'Erland Isaksson',
			'developedByLink' => 'http://erland.isaksson.info/donate',
			'dataproviderlink' => 'http://www.last.fm',
			'dataprovidername' => 'Audioscrobbler/LastFM',
			'function' => \&getTrackInfoDescription,
			'type' => 'text',
			'context' => 'track',
			'properties' => [
			]
		},
		'lastfmtrackimage' => {
			'name' => 'LastFM Track Image',
			'description' => "This module gets album image from LastFM",
			'developedBy' => 'Erland Isaksson',
			'developedByLink' => 'http://erland.isaksson.info/donate',
			'dataproviderlink' => 'http://www.last.fm',
			'dataprovidername' => 'Audioscrobbler/LastFM',
			'function' => \&getTrackImage,
			'type' => 'image',
			'context' => 'track',
			'properties' => [
			]
		},
	};
	return $functions;
		
}

sub getSimilarArtists {
	my $client = shift;
	my $callback = shift;
	my $errorCallback = shift;
	my $callbackParams = shift;
	my $artist = shift;
	my $params = shift;

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&getSimilarArtistsResponse, \&gotErrorViaHTTP, {
                client => $client, 
		errorCallback => $errorCallback,
                callback => $callback, 
                callbackParams => $callbackParams,
		params => $params,
        });
	$log->error("Making call to: http://ws.audioscrobbler.com/2.0/?method=artist.getsimilar&artist=".escape($artist->name())."&api_key=$API_KEY");
	$http->get("http://ws.audioscrobbler.com/2.0/?method=artist.getsimilar&artist=".escape($artist->name())."&api_key=$API_KEY");
}

sub getSimilarArtistsImages {
	my $client = shift;
	my $callback = shift;
	my $errorCallback = shift;
	my $callbackParams = shift;
	my $artist = shift;
	my $params = shift;

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&getSimilarArtistsResponse, \&gotErrorViaHTTP, {
                client => $client, 
		errorCallback => $errorCallback,
                callback => $callback, 
                callbackParams => $callbackParams,
		type => "images",
		params => $params,
        });
	$log->error("Making call to: http://ws.audioscrobbler.com/2.0/?method=artist.getsimilar&artist=".escape($artist->name())."&api_key=$API_KEY");
	$http->get("http://ws.audioscrobbler.com/2.0/?method=artist.getsimilar&artist=".escape($artist->name())."&api_key=$API_KEY");
}

sub getSimilarArtistsResponse {
	my $http = shift;
	my $params = $http->params();

	my $content = $http->content();
	my @result = ();
	if(defined($content)) {
		my $xml = eval { XMLin($content, forcearray => ["artist"], keyattr => ["size"]) };
		my $artists = $xml->{'similarartists'}->{'artist'};
		if($artists) {
			my $limit = Plugins::SongInfo::Plugin::getSongInfoProperty('lastfmsimilarartistpercent');
			for my $artist (@$artists) {
				if(ref($artist) eq 'HASH' && $limit && ($artist->{'match'}*100)>$limit) {
					#my $artistObj = Slim::Schema->rs('Contributor')->search({name => $artist->{'name'})->single;
					if(defined($params->{'type'}) && $params->{'type'} eq "images") {
						my %item = (
							'type' => 'image',
							'text' => $artist->{'name'},
							'url' => $artist->{'image'}->{'mega'}->{'content'},
						);
						push @result,\%item;
					}else {
						my %item = (
							'type' => 'custom',
							'text' => $artist->{'name'},
						#	'value' => $artist->{'name'},
						);
						push @result,\%item;
					}
				}
			}
		}
	}
	sendResponse($params,\@result);
}

sub getTrackTags {
	my $client = shift;
	my $callback = shift;
	my $errorCallback = shift;
	my $callbackParams = shift;
	my $track = shift;
	my $params = shift;

	my $musicbrainz_id = "";
	if($track->musicbrainz_id) {
		$musicbrainz_id="&mbid=".$track->musicbrainz_id;
	}

	my $artist = "";
	if($track->artist()) {
		$artist="&artist=".$track->artist()->name;
	}

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&getTagsResponse, \&gotErrorViaHTTP, {
                client => $client, 
		errorCallback => $errorCallback,
                callback => $callback, 
                callbackParams => $callbackParams,
		params => $params,
        });
	$log->error("Making call to: http://ws.audioscrobbler.com/2.0/?method=track.gettoptags$artist$musicbrainz_id&track=".escape($track->title)."&api_key=$API_KEY");
	$http->get("http://ws.audioscrobbler.com/2.0/?method=track.gettoptags$artist$musicbrainz_id&track=".escape($track->title)."&api_key=$API_KEY");
}


sub getTagsResponse {
	my $http = shift;
	my $params = $http->params();

	my $content = $http->content();
	my @result = ();
	if(defined($content)) {
		my $xml = eval { XMLin($content, forcearray => ["tag"], keyattr => []) };
		my $tags = $xml->{'toptags'}->{'tag'};
		if($tags) {
			my $limit = Plugins::SongInfo::Plugin::getSongInfoProperty('lastfmsimilarartistpercent');
			for my $tag (@$tags) {
				if($limit && $tag->{'count'}>$limit) {
					my %item = (
						'type' => 'custom',
						'text' => $tag->{'name'},
						'value' => $tag->{'name'},
						'url' => $tag->{'url'}
					);
					push @result,\%item;
				}
			}
		}
	}
	sendResponse($params,\@result);
}

sub getArtistTags {
	my $client = shift;
	my $callback = shift;
	my $errorCallback = shift;
	my $callbackParams = shift;
	my $artist = shift;
	my $params = shift;

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&getTagsResponse, \&gotErrorViaHTTP, {
                client => $client, 
		errorCallback => $errorCallback,
                callback => $callback, 
                callbackParams => $callbackParams,
		params => $params,
        });
	$log->error("Making call to: http://ws.audioscrobbler.com/2.0/?method=artist.gettoptags&artist=".escape($artist->name())."&api_key=$API_KEY");
	$http->get("http://ws.audioscrobbler.com/2.0/?method=artist.gettoptags&artist=".escape($artist->name())."&api_key=$API_KEY");
}

sub getArtistImages {
	my $client = shift;
	my $callback = shift;
	my $errorCallback = shift;
	my $callbackParams = shift;
	my $artist = shift;
	my $params = shift;

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&getImagesResponse, \&gotErrorViaHTTP, {
                client => $client, 
		errorCallback => $errorCallback,
                callback => $callback, 
                callbackParams => $callbackParams,
		params => $params,
        });
	$log->error("Making call to: http://ws.audioscrobbler.com/2.0/?method=artist.getimages&artist=".escape($artist->name())."&api_key=$API_KEY");
	$http->get("http://ws.audioscrobbler.com/2.0/?method=artist.getimages&artist=".escape($artist->name())."&api_key=$API_KEY");
}

sub getArtistInfoBiography {
	my $client = shift;
	my $callback = shift;
	my $errorCallback = shift;
	my $callbackParams = shift;
	my $artist = shift;
	my $params = shift;

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&getArtistInfoResponse, \&gotErrorViaHTTP, {
                client => $client, 
		errorCallback => $errorCallback,
                callback => $callback, 
                callbackParams => $callbackParams,
		type => "biography",
		params => $params,
        });
	my $musicbrainz_id = "";
	if($artist->musicbrainz_id) {
		$musicbrainz_id="&mbid=".$artist->musicbrainz_id;
	}

	$log->error("Making call to: http://ws.audioscrobbler.com/2.0/?method=artist.getinfo$musicbrainz_id&artist=".escape($artist->name())."&api_key=$API_KEY");
	$http->get("http://ws.audioscrobbler.com/2.0/?method=artist.getinfo$musicbrainz_id&artist=".escape($artist->name())."&api_key=$API_KEY");
}

sub getAlbumImage {
	my $client = shift;
	my $callback = shift;
	my $errorCallback = shift;
	my $callbackParams = shift;
	my $album = shift;
	my $params = shift;

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&getAlbumInfoResponse, \&gotErrorViaHTTP, {
                client => $client, 
		errorCallback => $errorCallback,
                callback => $callback, 
                callbackParams => $callbackParams,
		type => "images",
		params => $params,
        });

	my $musicbrainz_id = "";
	if($album->musicbrainz_id) {
		$musicbrainz_id="&mbid=".$album->musicbrainz_id;
	}

	my $artist = "";
	if($album->contributorid()) {
		my $obj = Slim::Schema->resultset('Contributor')->find($album->contributorid());
		if($obj) {
			$artist="&artist=".$obj->name;
		}
	}
	
	$log->error("Making call to: http://ws.audioscrobbler.com/2.0/?method=album.getinfo$musicbrainz_id$artist&album=".escape($album->title())."&api_key=$API_KEY");
	$http->get("http://ws.audioscrobbler.com/2.0/?method=album.getinfo$musicbrainz_id$artist&album=".escape($album->title())."&api_key=$API_KEY");
}

sub getAlbumInfoDescription {
	my $client = shift;
	my $callback = shift;
	my $errorCallback = shift;
	my $callbackParams = shift;
	my $album = shift;
	my $params = shift;

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&getAlbumInfoResponse, \&gotErrorViaHTTP, {
                client => $client, 
		errorCallback => $errorCallback,
                callback => $callback, 
                callbackParams => $callbackParams,
		type => "wiki",
		params => $params,
        });

	my $musicbrainz_id = "";
	if($album->musicbrainz_id) {
		$musicbrainz_id="&mbid=".$album->musicbrainz_id;
	}

	my $artist = "";
	if($album->contributorid()) {
		my $obj = Slim::Schema->resultset('Contributor')->find($album->contributorid());
		if($obj) {
			$artist="&artist=".escape($obj->name);
		}
	}
	
	$log->error("Making call to: http://ws.audioscrobbler.com/2.0/?method=album.getinfo$musicbrainz_id$artist&album=".escape($album->title())."&api_key=$API_KEY");
	$http->get("http://ws.audioscrobbler.com/2.0/?method=album.getinfo$musicbrainz_id$artist&album=".escape($album->title())."&api_key=$API_KEY");
}

sub getTrackImage {
	my $client = shift;
	my $callback = shift;
	my $errorCallback = shift;
	my $callbackParams = shift;
	my $track = shift;
	my $params = shift;

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&getTrackInfoResponse, \&gotErrorViaHTTP, {
                client => $client, 
		errorCallback => $errorCallback,
                callback => $callback, 
                callbackParams => $callbackParams,
		type => "images",
		params => $params,
        });

	my $musicbrainz_id = "";
	if($track->musicbrainz_id) {
		$musicbrainz_id="&mbid=".$track->musicbrainz_id;
	}

	my $artist = "";
	if($track->artist) {
		$artist="&artist=".escape($track->artist->name);
	}
	
	$log->error("Making call to: http://ws.audioscrobbler.com/2.0/?method=track.getinfo$musicbrainz_id$artist&track=".escape($track->title())."&api_key=$API_KEY");
	$http->get("http://ws.audioscrobbler.com/2.0/?method=track.getinfo$musicbrainz_id$artist&track=".escape($track->title())."&api_key=$API_KEY");
}

sub getTrackInfoDescription {
	my $client = shift;
	my $callback = shift;
	my $errorCallback = shift;
	my $callbackParams = shift;
	my $track = shift;
	my $params = shift;

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&getTrackInfoResponse, \&gotErrorViaHTTP, {
                client => $client, 
		errorCallback => $errorCallback,
                callback => $callback, 
                callbackParams => $callbackParams,
		type => "wiki",
		params => $params,
        });

	my $musicbrainz_id = "";
	if($track->musicbrainz_id) {
		$musicbrainz_id="&mbid=".$track->musicbrainz_id;
	}

	my $artist = "";
	if($track->artist) {
		$artist="&artist=".escape($track->artist->name);
	}
	
	$log->error("Making call to: http://ws.audioscrobbler.com/2.0/?method=track.getinfo$musicbrainz_id$artist&track=".escape($track->title())."&api_key=$API_KEY");
	$http->get("http://ws.audioscrobbler.com/2.0/?method=track.getinfo$musicbrainz_id$artist&track=".escape($track->title())."&api_key=$API_KEY");
}

sub getArtistInfoResponse {
	my $http = shift;
	my $params = $http->params();

	my $content = $http->content();
	my @result = ();
	if(defined($content)) {
		my $xml = eval { XMLin($content, forcearray => [], keyattr => ["size"]) };
		my $artist = $xml->{'artist'};
		if($artist && defined($artist->{'bio'})) {
			my %item = (
				'type' => 'text',
				'text' => $artist->{'bio'}->{'content'},
			);
			push @result,\%item;
		}
	}
	sendResponse($params,\@result);
}

sub getAlbumInfoResponse {
	my $http = shift;
	my $params = $http->params();

	my $content = $http->content();
	my @result = ();
	if(defined($content)) {
		my $xml = eval { XMLin($content, forcearray => [], keyattr => ["size"]) };
		my $album = $xml->{'album'};
		if($album) {
			if(defined($params->{'type'}) && $params->{'type'} eq "images") {
				my %item = (
					'type' => 'image',
					'text' => $album->{'name'},
					'value' => $album->{'name'},
					'url' => $album->{'image'}->{'extralarge'}->{'content'},
				);
				push @result,\%item;
			}elsif(defined($album->{'wiki'})) {
				my %item = (
					'type' => 'text',
					'text' => $album->{'wiki'}->{'content'},
				);
				push @result,\%item;
			}
		}
	}
	sendResponse($params,\@result);
}

sub getTrackInfoResponse {
	my $http = shift;
	my $params = $http->params();

	my $content = $http->content();
	my @result = ();
	if(defined($content)) {
		my $xml = eval { XMLin($content, forcearray => [], keyattr => ["size"]) };
		my $track = $xml->{'track'};
		if($track) {
			if(defined($params->{'type'}) && $params->{'type'} eq "images") {
				my %item = (
					'type' => 'image',
					'text' => $track->{'name'}." - ".$track->{'album'}->{'title'},
					'url' => $track->{'album'}->{'image'}->{'extralarge'}->{'content'},
				);
				push @result,\%item;
			}elsif(defined($track->{'wiki'})) {
				my %item = (
					'type' => 'text',
					'text' => $track->{'wiki'}->{'content'},
				);
				push @result,\%item;
			}
		}
	}
	sendResponse($params,\@result);
}

sub getImagesResponse {
	my $http = shift;
	my $params = $http->params();

	my $content = $http->content();
	my @result = ();
	if(defined($content)) {
$log->error("GOT: ".Dumper($content));
		my $xml = eval { XMLin($content, forcearray => ["image"], keyattr => ["name"]) };
		my $images = $xml->{'images'}->{'image'};
		if($images) {
			for my $image (@$images) {
				my %item = (
					'type' => 'image',
					'text' => $image->{'title'},
					'url' => $image->{'sizes'}->{'size'}->{'original'}->{'content'},
				);
				push @result,\%item;
			}
		}
	}
	sendResponse($params,\@result);
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

sub sendResponse {
	my $params = shift;
	my $result = shift;

	eval { 
		&{$params->{'callback'}}($params->{'client'},$params->{'callbackParams'},$result); 
	};
	if( $@ ) {
	    $log->error("Error sending response: $@");
	}
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
