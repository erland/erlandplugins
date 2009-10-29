#    Copyright (c) 2007 Erland Isaksson (erland_i@hotmail.com)
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
package Plugins::TrackStat::Settings::Backup;

use strict;
use base qw(Plugins::TrackStat::Settings::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings;

my $prefs = preferences('plugin.trackstat');
my $log   = logger('plugin.trackstat');

my $plugin; # reference to main plugin

sub new {
	my $class = shift;
	$plugin   = shift;

	$class->SUPER::new($plugin);
}

sub name {
	return 'PLUGIN_TRACKSTAT_SETTINGS_BACKUP';
}

sub page {
	return 'plugins/TrackStat/settings/backup.html';
}

sub currentPage {
	return name();
}

sub pages {
	my %page = (
		'name' => name(),
		'page' => page(),
	);
	my @pages = (\%page);
	return \@pages;
}

sub prefs {
        return ($prefs, qw(backup_file backup_dir backup_time findalternativefiles));
}
sub handler {
	my ($class, $client, $paramRef) = @_;
	my $result = undef;
	my $callHandler = 1;
	if ($paramRef->{'saveSettings'}) {
		$result = $class->SUPER::handler($client, $paramRef);
		$callHandler = 0;
	}
	if($paramRef->{'refresh_tracks'}) {
		if($callHandler) {
			$paramRef->{'saveSettings'} = 1;
			$result = $class->SUPER::handler($client, $paramRef);
		}
		if(validatedOk($paramRef)) {
			Plugins::TrackStat::Storage::refreshTracks();
		}
	}elsif($paramRef->{'purge_tracks'}) {
		if($callHandler) {
			$paramRef->{'saveSettings'} = 1;
			$result = $class->SUPER::handler($client, $paramRef);
		}
		if(validatedOk($paramRef)) {
			Plugins::TrackStat::Storage::purgeTracks();
		}
	}elsif($paramRef->{'clear'}) {
		if($callHandler) {
			$paramRef->{'saveSettings'} = 1;
			$result = $class->SUPER::handler($client, $paramRef);
		}
		if(validatedOk($paramRef)) {
			Plugins::TrackStat::Storage::deleteAllTracks();
		}
	}elsif($paramRef->{'restore'}) {
		if($callHandler) {
			$paramRef->{'saveSettings'} = 1;
			$result = $class->SUPER::handler($client, $paramRef);
		}
		if(validatedOk($paramRef)) {
			Plugins::TrackStat::Plugin::restoreFromFile();
		}
	}elsif($paramRef->{'backup'}) {
		if($callHandler) {
			$paramRef->{'saveSettings'} = 1;
			$result = $class->SUPER::handler($client, $paramRef);
		}
		if(validatedOk($paramRef)) {
			Plugins::TrackStat::Plugin::backupToFile();
		}
	}elsif($callHandler) {
		$result = $class->SUPER::handler($client, $paramRef);
	}
		
	return $result;
}

sub validatedOk {
	my $paramRef = shift;
	if(defined($paramRef->{'validated'})) {
		my $validatedPrefs = $paramRef->{'validated'};
		for my $p (keys %$validatedPrefs) {
			if(!$validatedPrefs->{$p}) {
				return 0;
			}
		}
	}
	return 1;
	
}		
1;
