# 				Title Switcher plugin 
#
#    Copyright (c) 2008 Erland Isaksson (erland_i@hotmail.com)
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

package Plugins::TitleSwitcher::Plugin;

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;
use Plugins::TitleSwitcher::Settings;
use Storable;

our $PLUGINVERSION =  undef;

my $prefs = preferences('plugin.titleswitcher');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.titleswitcher',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_TITLESWITCHER',
});

my $customFormats = {};
my $reloadVersion = 0;

sub getDisplayName {
	return 'PLUGIN_TITLESWITCHER';
}

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	Plugins::TitleSwitcher::Settings->new();
	reloadFormats();
}

sub reloadFormats {
	my $formats = $prefs->get('formats');
	foreach my $format (keys %$formats) {
		$format = uc($format);
		my @formatParts = ();
		my @parts = split(/,/,$formats->{$format});
		foreach my $part (@parts) {
			my ($name,$time) = split(/:/,$part);
			if(!defined($time)) {
				$time = 5;
			}

			my %entry = (
				'format' => $name,
				'time' => $time,
			);
			push @formatParts,\%entry;
		}

		$customFormats->{$format} = {
			'parts' => \@formatParts,
		}
	}
	$reloadVersion++;
}

sub getMusicInfoSCRCustomItems {
	my $musicInfoSCRFormats = {};

	my $formats = $prefs->get('formats');
	foreach my $format (keys %$formats) {
		$format = uc($format);
		$musicInfoSCRFormats->{'TITLESWITCHER'.$format} = {
			'cb' => \&getTitleFormat,
			'cache' => 1,
		};
	}

	return $musicInfoSCRFormats;
}

sub getTitleFormat
{
	my $client = shift;
	my $song = shift;
	my $tag = shift;

	$log->debug("Requesting format $tag");
	if($tag =~ /^TITLESWITCHER(.*)$/) {
		my $format = $1;

		if($reloadVersion != $client->pluginData('reloadVersion') || !defined($client->pluginData('format')) ) {
			$client->pluginData('format' => {});
			$client->pluginData('reloadVersion' => $reloadVersion);
			$log->debug("Reloading formats for player: ".$client->name);
		}
		$log->debug("Parsing format $format");

		if(!$client->pluginData('format')->{$format} && exists($customFormats->{$format})) {
			$client->pluginData('format')->{$format} = Storable::dclone($customFormats->{$format});
		}

		if(exists($client->pluginData('format')->{$format})) {
			my $currentTime = time();
			if(!exists($client->pluginData('format')->{$format}->{'time'}) || $client->pluginData('format')->{$format}->{'time'}>$currentTime) {
				$client->pluginData('format')->{$format}->{'time'}=$currentTime;
				$client->pluginData('format')->{$format}->{'current'}=0;
			}
			my $currentIndex = $client->pluginData('format')->{$format}->{'current'};
			my $currentPartTime = 5;
			if(exists($client->pluginData('format')->{$format}->{'parts'}->[$client->pluginData('format')->{$format}->{'current'}]->{'time'})) {
				$currentPartTime = $client->pluginData('format')->{$format}->{'parts'}->[$client->pluginData('format')->{$format}->{'current'}]->{'time'};
			}

			if($currentTime-$client->pluginData('format')->{$format}->{'time'}>$currentPartTime) {
				my $parts = $client->pluginData('format')->{$format}->{'parts'};
				if(scalar(@$parts)>$client->pluginData('format')->{$format}->{'current'}+1) {
					$client->pluginData('format')->{$format}->{'current'}++;
					$client->pluginData('format')->{$format}->{'time'}=$currentTime;
				}else {
					$client->pluginData('format')->{$format}->{'current'}=0;
					$client->pluginData('format')->{$format}->{'time'}=$currentTime;
				}
				$log->debug("Switching to next format, part ".$client->pluginData('format')->{$format}->{'current'});
			}
			my $currentFormat = $client->pluginData('format')->{$format}->{'parts'}->[$client->pluginData('format')->{$format}->{'current'}]->{'format'};
			$log->debug("Getting strig for $currentFormat");
			my $result = Plugins::MusicInfoSCR::Info::getFormatString($client,$currentFormat);
			$log->debug("Returning $result");
			return $result;
		}
	}
	return undef;
}

sub getFunctions {
	return {}
}

1;

__END__
