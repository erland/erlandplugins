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
use Slim::Utils::Prefs;
use Plugins::CustomScan::Validators;
use LWP::UserAgent;
my $prefs = preferences('plugin.customscan');
my $serverPrefs = preferences('server');

my $lastCalled = undef;

use Slim::Utils::Log;
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.customscan',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_CUSTOMSCAN',
});

sub getCustomScanFunctions {
	my %functions = (
		'id' => 'csamazon',
		'name' => 'Amazon',
		'description' => "This module scans amazon.com for all your albums, the scanned information is average customer ratings and amazon subjects/genres related to each album. <br><br><b>Note!</b><br>The Amazon module requires you to register for a access key to use Amazon web services, you can do this by go to amazon.com and select the \"Amazon Web Services\" link currently available in the bottom left menu under \"Amazon Services\"<br><br>Please note that the information read is free but the web service usage is restricted according to Amazon Web Services Licensing Agreement.<br><br>The Amazon module is quite slow, the reason for this is that Amazon restricts the number of calls per second towards their services in the licenses. Please respect these licensing rules. This also results in that SqueezeCenter will perform quite bad during scanning when this scanning module is active. The information will only be scanned once for each album, so the next time it will only scan new albums and will be a lot faster due to this. Approximately scanning time are 1-2 seconds per album in your library",
		'dataproviderlink' => 'http://www.amazon.com',
		'dataprovidername' => 'Amazon.com',
		'scanAlbum' => \&scanAlbum,
		'properties' => [
			{
				'id' => 'amazonaccesskey',
				'name' => 'Amazon Access Key',
				'description' => 'You need to apply for a amazon access key from amazon.com and enter it here',
				'type' => 'text',
				'value' => 'XXX'
			},
			{
				'id' => 'amazonmaxsubjectlength',
				'name' => 'Ignore genres longer than',
				'type' => 'text',
				'validate' => \&Plugins::CustomScan::Validators::isInt,
				'value' => 40
			},
			{
				'name' => 'Update SqueezeCenter ratings',
				'id' => 'writeamazonrating',
				'type' => 'checkbox',
				'value' => 0
			},
			{
				'id' => 'amazontimeout',
				'name' => 'Timeout',
				'description' => 'Timeout in requests towards Amazon web services',
				'type' => 'text',
				'value' => $serverPrefs->get("remotestreamtimeout")||15
			},
		]
	);
	return \%functions;
		
}

sub scanAlbum {
	my $album = shift;
	my @result = ();
	
	my $accessKey = Plugins::CustomScan::Plugin::getCustomScanProperty("amazonaccesskey");
	#If the user doesn't have a access key there is no use to continue
	if(!$accessKey || $accessKey eq 'XXX') {
		$log->warn("The Amazon scanning module wont work unless you register your amazon access key, see README.txt for more information\n");
		return \@result;
	}

	my $title = unidecode($album->title);
	my $artist = undef;
	my $contributors = $album->contributors;
	if(!$album->compilation) {
		$artist = unidecode($contributors->first->name);
	}
	my $url = undef;
	if($artist) {
		$log->debug("Scanning album: ".$title.", artist: ".$artist."\n");
		$url = "http://webservices.amazon.com/onca/xml?Service=AWSECommerceService&AWSAccessKeyId=$accessKey&Operation=ItemSearch&SearchIndex=Music&Artist=".escape($artist)."&Title=".escape($title)."&ResponseGroup=Reviews,Subjects";
	}else {
		$log->debug("Scanning album: ".$title."\n");
		$url = "http://webservices.amazon.com/onca/xml?Service=AWSECommerceService&AWSAccessKeyId=$accessKey&Operation=ItemSearch&SearchIndex=Music&Title=".escape($title)."&ResponseGroup=Reviews,Subjects";
	}
	$log->debug("Calling url: $url\n");
	my $currentTime = time();

	# We need to wait for 1-2 seconds to not overload Amazon web services (this is specified in their license)
	if(defined($lastCalled) && $currentTime<($lastCalled+2)) {
		sleep(1);
	}
	my $http = LWP::UserAgent->new;
	$lastCalled = time();
	$http->timeout(Plugins::CustomScan::Plugin::getCustomScanProperty("amazontimeout"));
	my $response = $http->get($url);
	if($response->is_success) {
		my $xml = eval { XMLin($response->content, forcearray => ["Item","Subject","Review"], keyattr => []) };
		if ($@) {
			$log->debug("Got xml:\n".Dumper($xml)."\n");
			$log->error("AmazonScan: Failed to parse XML: $@\n");
		}
		if($xml) {
			my $hits = $xml->{'Items'}->{'Item'};
			#$log->debug("Got xml:\n".Dumper($xml)."\n");
			if($hits && scalar(@$hits)>0) {
				my $firstHit = $hits->[0];
				my $maxSubjectLength = Plugins::CustomScan::Plugin::getCustomScanProperty("amazonmaxsubjectlength");
				my $subjects = $firstHit->{'Subjects'}->{'Subject'};
				for my $subject (@$subjects) {
					if(!defined($maxSubjectLength) || length($subject)<$maxSubjectLength) {
						my %item = (
							'name' => 'subject',
							'value' => $subject
						);
						push @result,\%item;
					}
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
			}else {
				if($artist) {
					$log->info("No amazon.com data found for $title by $artist");
				}else {
					$log->info("No amazon.com data found for $title");
				}
			}
		}
	}else {
		if($artist) {
			$log->warn("Unable to retrieve amazon.com data for $title by $artist: ".$response->status_line);
		}else {
			$log->warn("Unable to retrieve amazon.com data for $title: ".$response->status_line);
		}
	}

	if($response->is_success || $response->status_line =~ /^404/) {
		# Lets just add dummy item to store that we have scanned this artist
		my %item = (
			'name' => 'retrieved',
			'value' => 1
		);
		push @result,\%item;
	}
	$http = undef;

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
	my $trackStat = grep(/TrackStat/, Slim::Utils::PluginManager->enabledPlugins(undef));
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
				$log->debug("Setting TrackStat rating on ".$track->title." to $rating\n");
				my $request = $client->execute(['trackstat', 'setrating', $track->id, sprintf('%d%', $rating)]);
				$request->source('PLUGIN_CUSTOMSCAN');
			}else {
				$log->debug("Setting SqueezeCenter rating on ".$track->title." to $rating\n");
				# Run this within eval for now so it hides all errors until this is standard
				eval {
					if(UNIVERSAL::can(ref($track),"persistent")) {
						$track->persistent->set('rating' => $rating);
						$track->persistent->update();
					}else {
						$track->set('rating' => $rating);
						$track->update();
					}
					Slim::Schema->forceCommit();
				};
			}
		}
	}
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
