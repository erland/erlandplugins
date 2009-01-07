#         TrackStat Amarok Export module
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


use strict;
use warnings;
                   
package Plugins::TrackStat::Amarok::Export;

use Slim::Utils::Misc;
use Slim::Utils::Unicode;
use DBI qw(:sql_types);
use Plugins::TrackStat::Storage;
use Plugins::TrackStat::Amarok::Common;
use Plugins::CustomScan::Validators;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.trackstat',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_TRACKSTAT',
});

my $amarokDbh = undef;

sub getCustomScanFunctions {
	my %functions = (
		'id' => 'amarokexport',
		'order' => '75',
		'defaultenabled' => 0,
		'name' => 'Amarok Statistics Export',
		'description' => "This module exports statistic information in SlimServer to Amarok media player. The information exported are ratings, playcounts, last played time and added time. The export module only supports Amarok running towards a MySQL database, by default Amarok runs with a SQLite database and then this scanning module doesn\'t work. The exported information is written directly to the Amarok database.<br><br>The export module is prepared for having separate libraries in Amarok and SlimServer, for example the Amarok library can be in mp3 format and the SlimServer library can be in flac format. The music path and file extension parameters will in this case be used to convert the exported data so it corresponds to the paths and files used in Amarok. If you are running Amarok and SlimServer on the same computer towards the same library the music path and file extension parameters can typically be left empty.",
		'developedBy' => 'Erland Isaksson',
		'developedByLink' => 'http://erland.isaksson.info/donate',
		'alwaysRescanTrack' => 1,
		'clearEnabled' => 0,
		'requiresRefresh' => 0,
		'scanTrack' => \&scanTrack,
		'initScanTrack' => \&initScanTrack,
		'exitScanTrack' => \&exitScanTrack,
		'scanText' => 'Export',
		'properties' => [
			{
				'id' => 'amarokdatabaseurl',
				'name' => 'Amarok database url',
				'description' => 'Database url to the Amarok database',
				'type' => 'text',
				'value' => 'dbi:mysql:hostname=127.0.0.1;port=3306;database=amarok'
			},
			{
				'id' => 'amarokdatabaseuser',
				'name' => 'Amarok database user',
				'description' => 'Username to the Amarok database',
				'type' => 'text',
				'value' => ''
			},
			{
				'id' => 'amarokdatabasepassword',
				'name' => 'Amarok database password',
				'description' => 'Password to the Amarok database',
				'type' => 'password',
				'value' => ''
			},
			{
				'id' => 'amarokextension',
				'name' => 'File extension in Amarok',
				'description' => 'File extension in Amarok (for example .mp3), empty means same file extension as in SlimServer',
				'type' => 'text',
				'value' => ''
			},
			{
				'id' => 'amarokmusicpath',
				'name' => 'Music path in Amarok',
				'description' => 'Path to main music directory in Amarok, empty means same music path as in SlimServer',
				'type' => 'text',
				'value' => ''
			},
			{
				'id' => 'amarokslimservermusicpath',
				'name' => 'Music path in SlimServer',
				'description' => 'Path to main music directory in SlimServer, empty means same music path as in SlimServer',
				'type' => 'text',
				'validate' => \&Plugins::CustomScan::Validators::isDirOrEmpty,
				'value' => ''
			},
			{
				'id' => 'amarokdynamicupdate',
				'name' => 'Dynamically update statistics',
				'description' => 'Continously write statistics to Amarok when ratings are changed and songs are played in SlimServer',
				'type' => 'checkbox',
				'value' => 0
			}
		]
	);
	if(Plugins::TrackStat::Plugin::isPluginsInstalled(undef,"MultiLibrary::Plugin")) {
		my $properties = $functions{'properties'};
		my $values = Plugins::TrackStat::Storage::getSQLPropertyValues("select id,name from multilibrary_libraries");
		my %library = (
			'id' => 'amarokexportlibraries',
			'name' => 'Libraries to limit the export to',
			'description' => 'Limit the export to songs in the selected libraries (None selected equals no limit)',
			'type' => 'multiplelist',
			'values' => $values,
			'value' => '',
		);
		push @$properties,\%library;
		my %dynamiclibrary = (
			'id' => 'amarokexportlibrariesdynamicupdate',
			'name' => 'Limit history to libraries',
			'description' => 'Limit the continously written history file to selected libraries',
			'type' => 'checkbox',
			'value' => 1
		);
		push @$properties,\%dynamiclibrary,
	}
	return \%functions;
		
}

sub initScanTrack {
	connectToAmarokDB();
	return undef;
}
sub connectToAmarokDB {
	if(!defined($amarokDbh)) {
		my $dsn = Plugins::CustomScan::Plugin::getCustomScanProperty("amarokdatabaseurl");
		my $user = Plugins::CustomScan::Plugin::getCustomScanProperty("amarokdatabaseuser");
		my $password = Plugins::CustomScan::Plugin::getCustomScanProperty("amarokdatabasepassword");
		eval {
			$amarokDbh = DBI->connect($dsn, $user, $password);
		};
		if( $@ ) {
			$log->warn("Database error: $DBI::errstr, $@\n");
			$amarokDbh = undef;
		}
	}
}
sub exitScanTrack {
	if(defined($amarokDbh)) {
		eval { 
			$amarokDbh->disconnect();
		};
		if( $@ ) {
			$log->warn("Database error: $DBI::errstr, $@\n");
		}
	}
	return undef;
}
sub scanTrack {
	my $track = shift;
	if(isAllowedToExport($track,1)) {
		return writeTrack($track);
	}
	my @result = ();
	return \@result;
}

sub writeTrack {
	my $track = shift;
	my $forceRating = shift;
	my $forcePlayCount = shift;
	my $forceLastPlayed = shift;

	my @result = ();

	return \@result unless defined $amarokDbh;

	# Getting statistic information
	my $trackHandle = Plugins::TrackStat::Storage::findTrack( $track->url,undef,$track);
	if(defined($trackHandle)) {	
		my $rating = defined($forceRating)?$forceRating:$trackHandle->rating;
		my $playCount = defined($forcePlayCount)?$forcePlayCount:$trackHandle->playCount;
		my $lastPlayed = defined($forceLastPlayed)?$forceLastPlayed:$trackHandle->lastPlayed;
		my $added = $trackHandle->added;

		my $percentage = undef;
		if(defined($rating)) {
			$percentage = $rating;
			$rating = $rating/10;
		}
		my $path = Plugins::TrackStat::Amarok::Common::getAmarokPath($track->path);

		my $amarokSth = $amarokDbh->prepare("replace into statistics (url,deviceid,createdate,accessdate,percentage,rating,playcounter,uniqueid,deleted) select tags.url,tags.deviceid,?,?,?,?,?,uniqueid.uniqueid,0 from tags,uniqueid where tags.url=uniqueid.url and tags.url=?");

		$log->debug("Exporting track: ".$path."\n");
		eval {
			$amarokSth->bind_param(1, $added , SQL_VARCHAR);
			$amarokSth->bind_param(2, $lastPlayed , SQL_INTEGER);
			$amarokSth->bind_param(3, $percentage , SQL_FLOAT);
			$amarokSth->bind_param(4, $rating , SQL_INTEGER);
			$amarokSth->bind_param(5, $playCount , SQL_INTEGER);
			$amarokSth->bind_param(6, $path , SQL_VARCHAR);
			my $count = $amarokSth->execute();
			if($count ne "0E0") {
				$log->debug("Track exported: ".$path."\n");
			}
			$amarokSth->finish();
		};
		if( $@ ) {
		    $log->warn("Database error: $DBI::errstr, $@\n");
		}
		$amarokSth = $amarokDbh->prepare("update tags set createdate=? where url=?");

		eval {
			$amarokSth->bind_param(1, $added , SQL_INTEGER);
			$amarokSth->bind_param(2, $path , SQL_VARCHAR);
			$amarokSth->execute();
			$amarokSth->finish();
		};
		if( $@ ) {
		    $log->warn("Database error: $DBI::errstr, $@\n");
		}
	}
	
	return \@result;
}

sub exportRating {
	my $url = shift;
	my $rating = shift;
	my $track = shift;

	if(Plugins::CustomScan::Plugin::getCustomScanProperty("amarokdynamicupdate") && isAllowedToExport($track)) {
		connectToAmarokDB();
		writeTrack($track,$rating);
	}
}

sub isAllowedToExport {
	my $track = shift;
	my $force = shift;

	my $include = 1;
	my $libraries = Plugins::CustomScan::Plugin::getCustomScanProperty("amarokexportlibraries");
	if((defined($force) || Plugins::CustomScan::Plugin::getCustomScanProperty("amarokexportlibrariesdynamicupdate")) && $libraries  && Plugins::TrackStat::Plugin::isPluginsInstalled(undef,"MultiLibrary::Plugin")) {
		my $sql = "SELECT tracks.id FROM tracks,multilibrary_track where tracks.id=multilibrary_track.track and tracks.id=".$track->id." and multilibrary_track.library in ($libraries)";
		my $dbh = Plugins::TrackStat::Storage::getCurrentDBH();
		$log->debug("Executing: $sql\n");
		eval {
			my $sth = $dbh->prepare( $sql );
			$sth->execute();
			$sth->bind_columns( undef, \$include);
			if( !$sth->fetch() ) {
				$log->debug("Ignoring track, not part of selected libraries: ".$track->url."\n");
				$include = 0;
			}
			$sth->finish();
		};
		if($@) {
			$log->warn("Database error: $DBI::errstr, $@\n");
		}
	}
	return $include;
}

sub exportStatistic {
	my $url = shift;
	my $rating = shift;
	my $playCount = shift;
	my $lastPlayed = shift;

	my  $track = undef;
	eval {
		$track = Plugins::TrackStat::Storage::objectForUrl($url);
	};
	if ($@) {
		$log->warn("Error retrieving track: $url\n");
	}
	if($track) {
		if(Plugins::CustomScan::Plugin::getCustomScanProperty("amarokdynamicupdate") && isAllowedToExport($track)) {
			connectToAmarokDB();
			writeTrack($track,$rating,$playCount,$lastPlayed);
		}
	}
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
