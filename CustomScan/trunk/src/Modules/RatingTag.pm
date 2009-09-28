#         CustomScan::Modules::RatingTag module
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
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
                   
package Plugins::CustomScan::Modules::RatingTag;

use Slim::Utils::Misc;
use MP3::Info;
use POSIX qw(floor);
use Slim::Utils::Prefs;
use Plugins::CustomScan::Validators;
my $prefs = preferences('plugin.customscan');
use Slim::Utils::Log;
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.customscan',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_CUSTOMSCAN',
});

my $trackStat;

sub getCustomScanFunctions {
	my %functions = (
		'id' => 'ratingtag',
		'name' => 'Rating Tag',
		'description' => "This module reads rating tags from the music files and stores them in the Squeezebox Server database. This is for example used by
            MediaMonkey and optionally also by Windows Media Player if you have choosed to store the rating information in the music files. The POPM tag available in the MP3 standard will always be read if available, but if the file also have a rating tag as specified below this will be used instead",
		'developedBy' => 'Erland Isaksson',
		'developedByLink' => 'http://erland.isaksson.info/donate',
		'alwaysRescanTrack' => 1,
		'scanInit' => \&scanInit,
		'scanTrack' => \&scanTrack,
		'properties' => [
			{
				'id' => 'writeratingtag',
				'name' => 'Write ratings to Squeezebox Server',
				'type' => 'checkbox',
				'value' => 1
			},
			{
				'id' => 'ratingtag',
				'name' => 'Rating tag name',
				'description' => 'The name of the rating tag to read ratings from, can be several tags separated by a comma',
				'type' => 'text',
				'value' => 'RATING'
			},
			{
				'id' => 'ratingtagmax',
				'name' => 'Max rating value',
				'description' => 'The value of maximum rating in the scanned tag, this is used to convert the rating to a value between 0-100 to be stored in Squeezebox Server',
				'type' => 'text',
				'validate' => \&Plugins::CustomScan::Validators::isInt,
				'value' => 100
			}
		]
	);
	return \%functions;
		
}

sub scanInit {
	$trackStat =  grep(/TrackStat/, Slim::Utils::PluginManager->enabledPlugins(undef));;
}

sub scanTrack {
	my $track = shift;
	my @result = ();
	$log->debug("Scanning track: ".$track->title."\n");

	my $writeratingtag = Plugins::CustomScan::Plugin::getCustomScanProperty("writeratingtag");
	if($track->content_type() eq 'mp3') {
		my $file = Slim::Utils::Misc::pathFromFileURL($track->url);
		my $rawTags = MP3::Info::get_mp3tag($file,2,1);
		for my $t (keys %$rawTags) {
			if($t eq 'POPM' || $t eq 'POP') {
				my @bytes = unpack "C*",$rawTags->{$t};
				my $email=1;
				my $rating = 0;
				my $emailText = '';
				for my $c (@bytes) {
					if($rating) {
						my $ratingNumber = undef;
						if($emailText =~ /Windows Media Player/) {
							$ratingNumber = floor($c*100/255);
							$ratingNumber = floor(20+$ratingNumber*80/100);
						}else {
							$ratingNumber = floor($c*100/255);
						}
						if($ratingNumber>100) {
							$ratingNumber=100;
						}
						if($ratingNumber) {
							my %item = (
								'name' => 'RATING',
								'value' => $ratingNumber
							);
							push @result,\%item;
							if($writeratingtag) {
								rateTrack($track,$ratingNumber);
							}
						}
						last;
					}
					if($email && $c==0) {
						$email = 0;
						$rating = 1;
					}elsif($email) {
						$emailText .= chr $c;
					}
				}
			}
		}
	}
	my $ratingtag = Plugins::CustomScan::Plugin::getCustomScanProperty("ratingtag");
	my $ratingtagmax = Plugins::CustomScan::Plugin::getCustomScanProperty("ratingtagmax");
	if($ratingtag && $ratingtagmax) {
		my @ratingTags = split(/\s*,\s*/,$ratingtag);
		my %ratingTagsHash = ();
		for my $tag (@ratingTags) {
			$ratingTagsHash{uc($tag)} = 1;
		}
		my $tags = Slim::Formats->readTags($track->url);
		if(defined($tags)) {
			for my $tag (keys %$tags) {
				my $ratingNumber = undef;
				if($tag eq 'WM/SharedUserRating' || $tag eq 'SHAREDUSERRATING') {
					$ratingNumber = $tags->{$tag};
					if($ratingNumber && $ratingNumber =~ /^\d+$/) {
						if($ratingNumber == 99) {
							$ratingNumber = 100;
						}else {
							$ratingNumber = floor((($ratingNumber/25)+1)*20);
						}
					}
				}elsif(defined($ratingTagsHash{uc($tag)})) {
					$ratingNumber = $tags->{$tag};
					if($ratingNumber && $ratingNumber =~ /^\d+$/) {
						$ratingNumber = floor($ratingNumber*100/$ratingtagmax);
						if($ratingNumber>100) {
							$ratingNumber=100;
						}
					}
				}
				if(defined($ratingNumber) && $ratingNumber) {
					$log->debug("Using $tag, adjusted rating is: $ratingNumber / 100");
					#Lets clear the result, so we ignore any MP3 POPM tag
					@result = ();
					my %item = (
						'name' => 'RATING',
						'value' => $ratingNumber
					);
					push @result,\%item;
					if($writeratingtag) {
						rateTrack($track,$ratingNumber);
					}
					last;
				}
			}
		}
	}
	return \@result;
}

sub rateTrack {
	my $track = shift;
	my $rating = shift;

	my $client = Slim::Player::Client::clientRandom();
	if($trackStat && defined($client)) {
		$log->debug("Setting TrackStat rating on ".$track->title." to $rating\n");
		my $ratingPercent = $rating."%";
		my $request = $client->execute(['trackstat', 'setrating', $track->id, $ratingPercent,"type:scan"]);
		$request->source('PLUGIN_CUSTOMSCAN');
	}else {
		$log->debug("Setting Squeezebox Server rating on ".$track->title." to $rating\n");
		# Run this within eval for now so it hides all errors until this is standard
		eval {
			if(UNIVERSAL::can(ref($track),"retrievePersistent")) {
				$track->rating($rating);
			}elsif(UNIVERSAL::can(ref($track),"persistent")) {
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

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
