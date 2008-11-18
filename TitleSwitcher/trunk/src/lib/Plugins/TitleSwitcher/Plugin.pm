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
use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;
use File::Spec::Functions qw(:ALL);
use DBI qw(:sql_types);
use FindBin qw($Bin);
use Plugins::TitleSwitcher::Settings;
use Storable;

my @pluginDirs = ();
our $PLUGINVERSION =  undef;

my $prefs = preferences('plugin.titleswitcher');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.titleswitcher',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_TITLESWITCHER',
});

my $customFormats = {};
my $clientFormats = {};

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
	$clientFormats = {};
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
		$log->debug("Parsing format $format");

		if(!exists($clientFormats->{$client->id}->{$format}) && exists($customFormats->{$format})) {
			$clientFormats->{$client->id}->{$format} = Storable::dclone($customFormats->{$format});
		}

		if(exists($clientFormats->{$client->id}->{$format})) {
			my $currentTime = time();
			if(!exists($clientFormats->{$client->id}->{$format}->{'time'}) || $clientFormats->{$client->id}->{$format}->{'time'}>$currentTime) {
				$clientFormats->{$client->id}->{$format}->{'time'}=$currentTime;
				$clientFormats->{$client->id}->{$format}->{'current'}=0;
			}
			my $currentIndex = $clientFormats->{$client->id}->{$format}->{'current'};
			my $currentPartTime = 5;
			if(exists($clientFormats->{$client->id}->{$format}->{'parts'}->[$clientFormats->{$client->id}->{$format}->{'current'}]->{'time'})) {
				$currentPartTime = $clientFormats->{$client->id}->{$format}->{'parts'}->[$clientFormats->{$client->id}->{$format}->{'current'}]->{'time'};
			}

			if($currentTime-$clientFormats->{$client->id}->{$format}->{'time'}>$currentPartTime) {
				my $parts = $clientFormats->{$client->id}->{$format}->{'parts'};
				if(scalar(@$parts)>$clientFormats->{$client->id}->{$format}->{'current'}+1) {
					$clientFormats->{$client->id}->{$format}->{'current'}++;
					$clientFormats->{$client->id}->{$format}->{'time'}=$currentTime;
				}else {
					$clientFormats->{$client->id}->{$format}->{'current'}=0;
					$clientFormats->{$client->id}->{$format}->{'time'}=$currentTime;
				}
				$log->debug("Switching to next format, part ".$clientFormats->{$client->id}->{$format}->{'current'});
			}
			my $currentFormat = $clientFormats->{$client->id}->{$format}->{'parts'}->[$clientFormats->{$client->id}->{$format}->{'current'}]->{'format'};
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
