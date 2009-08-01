#         TrackStat::RestoreModule module
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
# 
#    Portions of code derived from the iTunes plugin included with slimserver
#    SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
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
                   
package Plugins::TrackStat::Backup::RestoreModule;

use Slim::Utils::Prefs;
use Date::Parse qw(str2time);
use Fcntl ':flock'; # import LOCK_* constants
use POSIX qw(strftime);
use File::Spec::Functions qw(:ALL);
use DBI qw(:sql_types);
use Slim::Utils::Misc;
use Plugins::CustomScan::Validators;
use Plugins::TrackStat::Storage;
use Plugins::TrackStat::Backup::File;

my $prefs = preferences('plugin.trackstat');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.trackstat',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_TRACKSTAT',
});

my $scanningStep = 0;

sub getCustomScanFunctions {
	my %functions = (
		'id' => 'trackstatrestore',
		'order' => '75',
		'defaultenabled' => 0,
		'name' => 'TrackStat Restore',
		'description' => "This module restore the TrackStat statistics data from file",
		'alwaysRescanTrack' => 1,
		'clearEnabled' => 0,
		'requiresRefresh' => 0,
		'scanWarning' => "This will remove your TrackStat statistics with data from the specified file, are you sure you want to continue ?",
		'initScanTrack' => \&initScanTrack,
		'exitScanTrack' => \&exitScanTrack,
		'scanExit' => \&scanExit,
		'scanText' => 'Restore',
		'properties' => [
			{
				'id' => 'trackstatbackupfile',
				'name' => 'Restore from file',
				'description' => 'File with TrackStat data to restore statistics information from',
				'type' => 'text',
				'validate' => \&Plugins::CustomScan::Validators::isFile,
				'value' => $prefs->get("backup_file")
			},
			{
				'id' => 'trackstatrestoremerge',
				'name' => 'Merge with existing',
				'description' => 'Merge the restored information with the existing information in TrackStat, unselecting this means that the existing statistics in the database will be deleted before its restored from file',
				'type' => 'checkbox',
				'value' => 1
			},
		]
	);
	return \%functions;
		
}
sub initScanTrack {
	$scanningStep = 0;
	return undef;
}

sub exitScanTrack
{
	if($scanningStep == 0) {
		$log->info("Deleting existing TrackStat statistics");
		if(!Plugins::CustomScan::Plugin::getCustomScanProperty("trackstatrestoremerge")) {
			Plugins::TrackStat::Storage::deleteAllTracks();
		}
		$scanningStep++;
		return 1;
	}elsif($scanningStep == 1) {
		my $file = Plugins::CustomScan::Plugin::getCustomScanProperty("trackstatbackupfile");
		Plugins::TrackStat::Backup::File::initRestore($file);
		$scanningStep++;
		return 1;
	}elsif($scanningStep == 2) {
		my $success = Plugins::TrackStat::Backup::File::scanFunction();
		if($success && Plugins::TrackStat::Backup::File::stillScanning()) {
			return 1;
		}else {
			return undef;
		}
	}
}

sub scanExit
{
	Plugins::TrackStat::Backup::File::stopScan();
	return undef;
}

1;

__END__
