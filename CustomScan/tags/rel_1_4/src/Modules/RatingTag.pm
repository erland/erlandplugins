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

my $trackStat;

sub getCustomScanFunctions {
	my %functions = (
		'id' => 'ratingtag',
		'name' => 'Rating Tag',
		'alwaysRescanTrack' => 1,
		'scanInit' => \&scanInit,
		'scanTrack' => \&scanTrack
	);
	return \%functions;
		
}

sub scanInit {
	if ($::VERSION ge '6.5') {
		$trackStat = Slim::Utils::PluginManager::enabledPlugin("TrackStat",undef);
	}else {
		$trackStat = grep(/TrackStat/,Slim::Buttons::Plugins::enabledPlugins(undef));
	}
}

sub scanTrack {
	my $track = shift;
	my @result = ();
	debugMsg("Scanning track: ".$track->title."\n");

	my $writeratingtag = Plugins::CustomScan::Plugin::getCustomScanProperty("writeratingtag");
	if(uc($track->url) =~ /MP3$/) {
		my %rawTags = ();
		my $file = Slim::Utils::Misc::pathFromFileURL($track->url);
		open(my $fh, $file);
		MP3::Info::_get_v2tag($fh, 2, 1, \%rawTags);
		for my $t (keys %rawTags) {
			if($t eq 'POPM') {
				my @bytes = unpack "C*",$rawTags{$t};
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
		close($fh);
	}
	my $ratingtag = Plugins::CustomScan::Plugin::getCustomScanProperty("ratingtag");
	my $ratingtagmax = Plugins::CustomScan::Plugin::getCustomScanProperty("ratingtagmax");
	if($ratingtag && $ratingtagmax) {
		my $tags = Slim::Formats->readTags($track->url);
		if(defined($tags)) {
			for my $tag (keys %$tags) {
				if(uc($tag) eq uc($ratingtag)) {
					my $ratingNumber = $tags->{$tag};
					if($ratingNumber && $ratingNumber =~ /^\d+$/) {
						$ratingNumber = floor($ratingNumber*100/$ratingtagmax);
						if($ratingNumber>100) {
							$ratingNumber=100;
						}
						if($ratingNumber) {
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
						}
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
		debugMsg("Setting TrackStat rating on ".$track->title." to $rating\n");
		my $ratingPercent = $rating."%";
		my $request = $client->execute(['trackstat', 'setrating', $track->id, $ratingPercent]);
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

sub debugMsg
{
	my $message = join '','CustomScan:RatingTag ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_customscan_showmessages"));
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
