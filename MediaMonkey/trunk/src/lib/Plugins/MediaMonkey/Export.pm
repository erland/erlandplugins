#         MediaMonkey::Export module
# 				MediaMonkey plugin 
#
#    Copyright (c) 2008 Erland Isaksson (erland_i@hotmail.com)
#
#    Portions of code derived from the iTunesUpdate 1.5 plugin
#    Copyright (c) 2004-2006 James Craig (james.craig@london.com)
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
                   
package Plugins::MediaMonkey::Export;

use Slim::Utils::Prefs;
use Date::Parse qw(str2time);
use Fcntl ':flock'; # import LOCK_* constants
use POSIX qw(strftime);
use File::Spec::Functions qw(:ALL);
use File::Basename;
use DBI qw(:sql_types);
use Slim::Utils::Misc;
use Plugins::CustomScan::Validators;
use Slim::Utils::OSDetect;
use File::Slurp;

my $prefs = preferences('plugin.mediamonkey');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.mediamonkey',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_MEDIAMONKEY',
});

sub getCustomScanFunctions {
	my %functions = (
		'id' => 'mediamonkeyexport',
		'order' => '75',
		'defaultenabled' => 0,
		'name' => 'MediaMonkey Statistics Export',
		'description' => "This module exports statistic information in SqueezeCenter to MediaMonkey. The information exported are ratings, playcounts, last played time and added time.<br><br>Information is exported from TrackStat to an export file which will be placed in the specified output directory. Note that the generated MediaMonkey history file must be run with the MediaMonkey SqueezeSync vbscript to actually export the data to MediaMonkey. A complete export will generate a MediaMonkey_Complete.txt file, the continously written history file when playing and changing ratings will generate a MediaMonkey_Hist.txt file.<br><br>The export module is prepared for having separate libraries in MediaMonkey and SqueezeCenter, for example the MediaMonkey library can be on a Windows computer in mp3 format and the SqueezeCenter library can be on a Linux computer with flac format. The music path and file extension parameters will in this case be used to convert the exported data so it corresponds to the paths and files used in MediaMonkey. If you are running MediaMonkey and SqueezeCenter on the same computer towards the same library the music path and file extension parameters can typically be left empty.",
		'alwaysRescanTrack' => 1,
		'clearEnabled' => 0,
		'exitScanTrack' => \&exitScanTrack,
		'scanText' => 'Export',
		'properties' => [
			{
				'id' => 'mediamonkeyoutputdir',
				'name' => 'Output directory',
				'description' => 'Full path to the directory to write the export to',
				'type' => 'text',
				'validate' => \&Plugins::CustomScan::Validators::isDir,
				'value' => $serverPrefs->get('playlistdir')
			},
			{
				'id' => 'mediamonkeyextension',
				'name' => 'File extension in MediaMonkey',
				'description' => 'File extension in MediaMonkey (for example .mp3), empty means same file extension as in SqueezeCenter',
				'type' => 'text',
				'value' => ''
			},
			{
				'id' => 'mediamonkeymusicpath',
				'name' => 'Music path in MediaMonkey',
				'description' => 'Path to main music directory in MediaMonkey, empty means same music path as in SqueezeCenter',
				'type' => 'text',
				'value' => ''
			},
			{
				'id' => 'mediamonkeysqueezecentermusicpath',
				'name' => 'Music path in SqueezeCenter',
				'description' => 'Path to main music directory in SqueezeCenter, empty means same music path as in SqueezeCenter',
				'type' => 'text',
				'validate' => \&Plugins::CustomScan::Validators::isDirOrEmpty,
				'value' => ''
			},
			{
				'id' => 'mediamonkeydynamicupdate',
				'name' => 'Continously write history file',
				'description' => 'Continously write a history file when ratings are changed and songs are played in SqueezeCenter',
				'type' => 'checkbox',
				'value' => 0
			}
		]
	);
	my $properties = $functions{'properties'};
	if(Slim::Utils::OSDetect::isWindows()) {
		push @$properties,{
				'id' => 'mediamonkeyautorunimportscript',
				'name' => 'Run MediaMonkey SqueezeSync script automatically',
				'description' => 'Automatically run the MediaMonkey SqueezeSync script after each complete export from SqueezeCenter',
				'type' => 'checkbox',
				'value' => 1
			};
		push @$properties,{
				'id' => 'mediamonkeyimportscriptpath',
				'name' => 'Path to import script',
				'description' => 'Full path to the MediaMonkey SqueezeSync script you like to use, leave empty if you like to use the bundled version',
				'type' => 'text',
				'validate' => \&isFileOrEmpty,
				'value' => ''
			};
	};
	if(Plugins::MediaMonkey::Plugin::isPluginsInstalled(undef,"MultiLibrary::Plugin")) {
		my $values = getSQLPropertyValues("select id,name from multilibrary_libraries");
		my %library = (
			'id' => 'mediamonkeyexportlibraries',
			'name' => 'Libraries to limit the export to',
			'description' => 'Limit the export to songs in the selected libraries (None selected equals no limit)',
			'type' => 'multiplelist',
			'values' => $values,
			'value' => '',
		);
		push @$properties,\%library;
		my %dynamiclibrary = (
			'id' => 'mediamonkeyexportlibrariesdynamicupdate',
			'name' => 'Limit history to libraries',
			'description' => 'Limit the continously written history file to selected libraries',
			'type' => 'checkbox',
			'value' => 1
		);
		push @$properties,\%dynamiclibrary,
	}
	return \%functions;
		
}

sub isFileOrEmpty {
	my $arg = shift;
	if(!$arg || $arg eq '') {
		return $arg;
	}else {
		return Plugins::CustomScan::Validators::isFile($arg);
	}
}

sub exitScanTrack
{
	my $dir = Plugins::CustomScan::Plugin::getCustomScanProperty("mediamonkeyoutputdir");
	if(!defined($dir) || ! -e $dir) {
		$log->warn("Failed, an output directory must be specified\n");
		return undef;
	}
	my $filename = catfile($dir,"MediaMonkey_Complete.txt");

	my $libraries = Plugins::CustomScan::Plugin::getCustomScanProperty("mediamonkeyexportlibraries");
	$log->debug("Exporting to MediaMonkey: $filename\n");

	my $sql = undef;
	if($libraries && Plugins::MediaMonkey::Plugin::isPluginsInstalled(undef,"MultiLibrary::Plugin")) {
		if(Plugins::MediaMonkey::Plugin::isPluginsInstalled(undef,"TrackStat::Plugin")) {
			$sql = "SELECT track_statistics.url, tracks.title, track_statistics.lastPlayed, track_statistics.playCount, track_statistics.rating, track_statistics.added FROM track_statistics,tracks,multilibrary_track where track_statistics.url=tracks.url and (track_statistics.added is not null or track_statistics.lastPlayed is not null or track_statistics.rating>0) and tracks.id=multilibrary_track.track and multilibrary_track.library in ($libraries)";
		}else {
			$sql = "SELECT tracks.url, tracks.title, tracks_persistent.lastPlayed, tracks_persistent.playCount, tracks_persistent.rating, tracks_persistent.added FROM tracks_persistent,tracks,multilibrary_track where tracks_persistent.track=tracks.id and (tracks_persistent.added is not null or tracks_persistent.lastPlayed is not null or tracks_persistent.rating>0) and tracks.id=multilibrary_track.track and multilibrary_track.library in ($libraries)";
		}
	}else {
		if(Plugins::MediaMonkey::Plugin::isPluginsInstalled(undef,"TrackStat::Plugin")) {
			$sql = "SELECT track_statistics.url, tracks.title, track_statistics.lastPlayed, track_statistics.playCount, track_statistics.rating, track_statistics.added FROM track_statistics,tracks where track_statistics.url=tracks.url and (track_statistics.added is not null or track_statistics.lastPlayed is not null or track_statistics.rating>0)";
		}else {
			$sql = "SELECT tracks.url, tracks.title, tracks_persistent.lastPlayed, tracks_persistent.playCount, tracks_persistent.rating, tracks_persistent.added FROM tracks_persistent,tracks where tracks_persistent.track=tracks.id and (tracks_persistent.added is not null or tracks_persistent.lastPlayed is not null or tracks_persistent.rating>0)";
		}
	}

	my $dbh = Slim::Schema->storage->dbh();
	$log->debug("Retreiving tracks with: $sql\n");
	my $sth = $dbh->prepare( $sql );

	my $output = FileHandle->new($filename, ">") or do {
		$log->warn("Could not open $filename for writing.\n");
		return undef;
	};

	my $count = 0;
	my( $url, $title, $lastPlayed, $playCount, $rating, $added );
	eval {
		$sth->execute();
		$sth->bind_columns( undef, \$url, \$title, \$lastPlayed, \$playCount, \$rating, \$added );
		my $result;
		while( $sth->fetch() ) {
			if($url) {
				if(!defined($rating) || !$rating) {
					$rating='';
				}
				if(!defined($playCount)) {
					$playCount=1;
				}
				my $path = getMediaMonkeyURL($url);
				$title = Slim::Utils::Unicode::utf8decode($title,'utf8');
				
				if($lastPlayed) {
					$count++;
					my $timestr = strftime ("%Y%m%d%H%M%S", localtime $lastPlayed);
					print $output "$title|||$path|played|$timestr|$rating|$playCount|$added\n";
				}elsif($rating && $rating>0) {
					$count++;
					print $output "$title|||$path|rated||$rating||$added\n";
				}
			}
		}
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr,$@\n");
	}
	$sth->finish();

	close $output;
	if(Plugins::CustomScan::Plugin::getCustomScanProperty('mediamonkeyautorunimportscript')) {
		my $scriptPath = Plugins::CustomScan::Plugin::getCustomScanProperty('mediamonkeyimportscriptpath');
		if(!$scriptPath) {
			my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
			for my $plugindir (@pluginDirs) {
				$scriptPath = catfile($plugindir,'MediaMonkey','SqueezeSync.vbs');
				next unless -r $scriptPath;
			}
		} 		
	 	if($scriptPath && -r $scriptPath && Slim::Utils::OSDetect::isWindows()) {

			$log->debug("Running MediaMonkey import script...");
			eval {
				runVBScript($scriptPath,$filename);
			};
			if($@) {
				$log->warn("Script error: $@\n");
			}
			$log->debug("Finished running MediaMonkey import script");
		}
	}
	$log->info("Exporting to MediaMonkey completed at ".(strftime ("%Y-%m-%d %H:%M:%S",localtime())).", exported $count songs\n");
	return undef;
}

sub OLEError {
	$log->error(Win32::OLE->LastError());
}

sub runVBScript {
	my $script = shift;
	my $filename = shift;

	# read_file from File::Slurp
	my $scriptCode = eval { read_file($script) };
	if($@) {
		$log->warn("Couldn't read script file: $@");
		return;
	}
	if(!defined $scriptCode) {
		$log->warn("Couldn't read script file");
		return;
	}

	require Win32::OLE;
	import Win32::OLE;
	Win32::OLE->Option(Warn => \&OLEError);
	Win32::OLE->Option(CP => Win32::OLE::CP_UTF8());
	my $vbscript = Win32::OLE->new('ScriptControl');
	$vbscript->{Language} = 'VBScript';
	$vbscript->AddCode($scriptCode);
	$vbscript->Run("SqueezeSync",$filename);
	undef $vbscript;
}

sub getMediaMonkeyURL {
	my $url = shift;
	my $replaceExtension = Plugins::CustomScan::Plugin::getCustomScanProperty("mediamonkeyextension");
	my $replacePath = Plugins::CustomScan::Plugin::getCustomScanProperty("mediamonkeymusicpath");
	my $nativeRoot = Plugins::CustomScan::Plugin::getCustomScanProperty("mediamonkeysqueezecentermusicpath");
	if(!defined($nativeRoot) || $nativeRoot eq '') {
		# Use MediaMonkey import path as backup
		$nativeRoot = $serverPrefs->get('audiodir');
	}
	$nativeRoot =~ s/\\/\//isg;
	if(defined($replacePath) && $replacePath ne '') {
		$replacePath =~ s/\\/\//isg;
	}

	my $path = Slim::Utils::Misc::pathFromFileURL($url);
	if($replaceExtension) {
		$path =~ s/\.[^.]*$/$replaceExtension/isg;
	}

	if(defined($replacePath) && $replacePath ne '') {
		$path =~ s/\\/\//isg;
		$path =~ s/$nativeRoot/$replacePath/isg;
	}

	return $path;
}	

sub exportRating {
	my $url = shift;
	my $rating = shift;
	my $track = shift;

	if(Plugins::CustomScan::Plugin::getCustomScanProperty("mediamonkeydynamicupdate")) {
		my $mediamonkeyurl = getMediaMonkeyURL($url);
		my $dir = Plugins::CustomScan::Plugin::getCustomScanProperty("mediamonkeyoutputdir");
		if(!defined($dir) || !-e $dir) {
			$log->warn("Failed to write history file, an output directory must be specified\n");
			return;
		}
		my $filename = catfile($dir,"MediaMonkey_Hist.txt");
		my $output = FileHandle->new($filename, ">>") or do {
			$log->warn("Could not open $filename for writing.\n");
			return;
		};
		if(!defined($track)) {
			$track = Slim::Schema->objectForUrl({
				'url' => $url
			});
		}
		
		if(isAllowedToExport($track)) {
			print $output "".$track->title."|||$mediamonkeyurl|rated||$rating\n";
		}
		close $output;
	}
}

sub isAllowedToExport {
	my $track = shift;

	my $include = 1;
	my $libraries = Plugins::CustomScan::Plugin::getCustomScanProperty("mediamonkeyexportlibraries");
	if(Plugins::CustomScan::Plugin::getCustomScanProperty("mediamonkeyexportlibrariesdynamicupdate") && $libraries  && Plugins::MediaMonkey::Plugin::isPluginsInstalled(undef,"MultiLibrary::Plugin")) {
		my $sql = "SELECT tracks.id FROM tracks,multilibrary_track where tracks.id=multilibrary_track.track and tracks.id=".$track->id." and multilibrary_track.library in ($libraries)";
		my $dbh = Slim::Schema->storage->dbh();
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
			$log->debug("Database error: $DBI::errstr, $@\n");
		}
	}
	return $include;
}
sub exportStatistic {
	my $url = shift;
	my $rating = shift;
	my $playCount = shift;
	my $lastPlayed = shift;

	if(Plugins::CustomScan::Plugin::getCustomScanProperty("mediamonkeydynamicupdate")) {
		my $mediamonkeyurl = getMediaMonkeyURL($url);
		my $dir = Plugins::CustomScan::Plugin::getCustomScanProperty("mediamonkeyoutputdir");
		if(!defined($dir) || !-e $dir) {
			$log->warn("Failed to write history file, an output directory must be specified\n");
			return;
		}
		my $filename = catfile($dir,"MediaMonkey_Hist.txt");
		my $output = FileHandle->new($filename, ">>") or do {
			$log->warn("Could not open $filename for writing.\n");
			return;
		};
		my $track = Slim::Schema->objectForUrl({
				'url' => $url
			});
		if(!defined $rating) {
			$rating = '';
		}
		if(defined $lastPlayed && isAllowedToExport($track)) {
			my $timestr = strftime ("%Y%m%d%H%M%S", localtime $lastPlayed);
			print $output "".$track->title."|||$mediamonkeyurl|played|$timestr|$rating\n";
		}
		close $output;
	}
}

sub getSQLPropertyValues {
	my $sqlstatements = shift;
	my @result =();
	my $dbh = Slim::Schema->storage->dbh();
	my $trackno = 0;
    	for my $sql (split(/[;]/,$sqlstatements)) {
	    	eval {
			$sql =~ s/^\s+//g;
			$sql =~ s/\s+$//g;
			my $sth = $dbh->prepare( $sql );
			$log->debug("Executing: $sql\n");
			$sth->execute() or do {
				$log->warn("Error executing: $sql\n");
				$sql = undef;
			};
	
			if ($sql =~ /^SELECT+/oi) {
				$log->debug("Executing and collecting: $sql\n");
				my $id;
				my $name;
				$sth->bind_col( 1, \$id);
				$sth->bind_col( 2, \$name);
				while( $sth->fetch() ) {
					my %item = (
						'id' => Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($id,'utf8')),
						'name' => Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($name,'utf8'))
					);
					push @result, \%item;
				}
			}
			$sth->finish();
		};
		if( $@ ) {
			$log->warn("Database error: $DBI::errstr\n");
		}		
	}
	return \@result;
}

# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

# don't use the external one because it doesn't know about the difference
# between a param and not...
#*unescape = \&URI::Escape::unescape;
sub unescape {
        my $in      = shift;
        my $isParam = shift;

        $in =~ s/\+/ /g if $isParam;
        $in =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

        return $in;
}

1;

__END__
