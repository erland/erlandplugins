#                               CustomScan::Modules::Amazon module
#
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
#
#    Please respect amazon.com terms of service, the usage of the 
#    feeds are free but restricted to the Amazon Web Services Licensing Agreement
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

package Plugins::CustomScan::Modules::Amazon;

use strict;

use Slim::Utils::Misc;
#use Data::Dumper;
use XML::Simple;
use Text::Unidecode;
use POSIX qw(ceil);

my $lastCalled = undef;

sub getCustomScanFunctions {
	my %functions = (
		'id' => 'csamazon',
		'name' => 'Amazon',
		'scanAlbum' => \&scanAlbum,
	);
	return \%functions;
		
}

sub scanAlbum {
	my $album = shift;
	my @result = ();
	
	my $title = unidecode($album->title);
	my $artist = undef;
	my $contributors = $album->contributors;
	if(!$album->compilation) {
		$artist = unidecode($contributors->first->name);
	}
	my $url = undef;
	if($artist) {
		debugMsg("Scanning album: ".$title.", artist: ".$artist."\n");
		#
		# NOTE!!! 
		# The AWSAccessKeyId used in the url below is only intended for this application, so if you want to use this code to some other application, please register on amazon.com and get your own key
		$url = "http://webservices.amazon.com/onca/xml?Service=AWSECommerceService&AWSAccessKeyId=0AM2G9T8HTNEXHMDMXR2&Operation=ItemSearch&SearchIndex=Music&Artist=".escape($artist)."&Title=".escape($title)."&ResponseGroup=Reviews,Subjects";
	}else {
		debugMsg("Scanning album: ".$title."\n");
		#
		# NOTE!!! 
		# The AWSAccessKeyId used in the url below is only intended for this application, so if you want to use this code to some other application, please register on amazon.com and get your own key
		$url = "http://webservices.amazon.com/onca/xml?Service=AWSECommerceService&AWSAccessKeyId=0AM2G9T8HTNEXHMDMXR2&Operation=ItemSearch&SearchIndex=Music&Title=".escape($title)."&ResponseGroup=Reviews,Subjects";
	}
	debugMsg("Calling url: $url\n");
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
		my $xml = eval { XMLin($http->content, forcearray => ["Item","Subject","Review"], keyattr => []) };
		if ($@) {
			debugMsg("Got xml:\n".Dumper($xml)."\n");
			msg("AmazonScan: Failed to parse XML: $@\n");
		}
		if($xml) {
			my $hits = $xml->{'Items'}->{'Item'};
			#debugMsg("Got xml:\n".Dumper($xml)."\n");
			if($hits && scalar(@$hits)>0) {
				my $firstHit = $hits->[0];
				my $subjects = $firstHit->{'Subjects'}->{'Subject'};
				for my $subject (@$subjects) {
					my %item = (
						'name' => 'subject',
						'value' => $subject
					);
					push @result,\%item;
				}
				my $averageRating = $firstHit->{'CustomerReviews'}->{'AverageRating'};
				if(defined($averageRating)){
					my %item = (
						'name' => 'avgrating',
						'value' => ceil($averageRating*20)
					);
					push @result,\%item;
					my $writeRating = Plugins::CustomScan::Plugin::getCustomScanProperty("writeamazonrating");
					if($writeRating) {
						rateUnratedTracksOnAlbum($album,ceil($averageRating*20));
					}
				}
				my $asin = $firstHit->{'ASIN'};
				if(defined($asin)){
					my %item = (
						'name' => 'asin',
						'value' => $asin
					);
					push @result,\%item;
				}
				#URL can be accessed as: http://www.amazon.com/o/ASIN/<asin>
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


sub getCurrentDBH {
	return Slim::Schema->storage->dbh();
}

sub rateUnratedTracksOnAlbum {
	my $album = shift;
	my $rating = shift;
	return unless $album;
	
	my $sql = undef;
	my $trackStat;
	if ($::VERSION ge '6.5') {
		$trackStat = Slim::Utils::PluginManager::enabledPlugin("TrackStat",undef);
	}else {
		$trackStat = grep(/TrackStat/,Slim::Buttons::Plugins::enabledPlugins(undef));
	}
	if($trackStat) {
		$sql = "select tracks.url from tracks left join track_statistics on tracks.url = track_statistics.url where tracks.album=".$album->id." and (track_statistics.rating is null or track_statistics.rating=0)";
	}else {
		$sql = "select tracks.url from tracks where tracks.album=".$album->id." and (tracks.rating is null or tracks.rating=0)";
	}
	my $dbh = getCurrentDBH();
	my $sth = $dbh->prepare( $sql );
	my @unratedTracks = ();
	eval {
		$sth->execute();
		my $url;
		$sth->bind_columns( undef, \$url );
		while( $sth->fetch() ) {
			push @unratedTracks, $url;
		}
	};
	if( $@ ) {
		warn "Database error: $DBI::errstr\n";
		return;
   	}
	if(scalar(@unratedTracks)>0) {
		my @tracks = Slim::Schema->rs('Track')->search({ 'url' => \@unratedTracks });
		# We need a client to execute the TrackStat setrating command, so lets just get a random one
		my $client = Slim::Player::Client::clientRandom();
		for my $track (@tracks) {
			if($trackStat && defined($client)) {
				debugMsg("Setting TrackStat rating on ".$track->title." to $rating\n");
				my $request = $client->execute(['trackstat', 'setrating', $track->id, sprintf('%d%', $rating)]);
				$request->source('PLUGIN_CUSTOMSCAN');
			}else {
				debugMsg("Setting slimserver rating on ".$track->title." to $rating\n");
				# Run this within eval for now so it hides all errors until this is standard
				eval {
					$track->set('rating' => $rating);
					$track->update();
					Slim::Schema->forceCommit();
				};
			}
		}
	}
}

sub debugMsg
{
	my $message = join '','CustomScan:Amazon ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_customscan_showmessages"));
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
