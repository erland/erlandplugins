#         TrackStat::Backup module
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
                   
package Plugins::TrackStat::Backup::File;

use Date::Parse qw(str2time);
use Fcntl ':flock'; # import LOCK_* constants
use POSIX qw(strftime);
use File::Spec::Functions qw(:ALL);
use File::Basename;
use XML::Parser;
use DBI qw(:sql_types);

use Slim::Utils::Misc;


my $backupParser;
my $backupParserNB;
my $backupFile;
my $isScanning = 0;
my $opened = 0;
my $inTrack;
my $inValue;
my %item;
my $currentKey;

sub backupToFile
{
	my $filename = shift;

	my $sql = "SELECT url, musicbrainz_id, playCount, added, lastPlayed, rating FROM track_statistics";

	my $dbh = Slim::Music::Info::getCurrentDataStore()->dbh();
	my $sth = $dbh->prepare( $sql );
	$sth->execute();

	debugMsg("Backup to: $filename\n");
	my $output = FileHandle->new($filename, ">") or do {
		warn "Could not open $filename for writing.";
		return;
	};
	print $output '<?xml version="1.0" encoding="UTF-8"?>'."\n";
	print $output "<TrackStat>\n";

	my( $url, $mbId, $playCount, $added, $lastPlayed, $rating );
	eval {
		$sth->bind_columns( undef, \$url, \$mbId, \$playCount, \$added, \$lastPlayed, \$rating );
		my $result;
		while( $sth->fetch() ) {
			if($url) {
				$url = escape($url);
				debugMsg("Backing up: $url\n");
				print $output "	<track>\n		<url>$url</url>\n";
				if($mbId) {
					print $output "		<musicbrainzId>$mbId</musicbrainzId>\n";
				}
				if($playCount) {
					print $output "		<playCount>$playCount</playCount>\n";
				}
				if($lastPlayed) {
					print $output "		<lastPlayed>$lastPlayed</lastPlayed>\n";
				}
				if($added) {
					print $output "		<added>$added</added>\n";
				}
				if($rating) {
					print $output "		<rating>$rating</rating>\n";
				}
				print $output "	</track>\n";
			}
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}

	print $output "</TrackStat>\n";
	close $output;
	$sth->finish();
	msg("TrackStat:Backup: Backup completed at ".(strftime ("%Y-%m-%d %H:%M:%S",localtime()))."\n");
}

sub restoreFromFile
{
	$backupFile = shift;
	debugMsg("Restore from: $backupFile\n");
	$backupParser = XML::Parser->new(
		'ErrorContext'     => 2,
		'ProtocolEncoding' => 'UTF-8',
		'NoExpand'         => 1,
		'NoLWP'            => 1,
		'Handlers'         => {

			'Start' => \&handleStartElement,
			'Char'  => \&handleCharElement,
			'End'   => \&handleEndElement,
		},
	);

	Slim::Utils::Scheduler::add_task(\&scanFunction);
}

sub stopScan {

	if (stillScanning()) {

		debugMsg("Was stillScanning - stopping old scan.\n");

		Slim::Utils::Scheduler::remove_task(\&scanFunction);
		$isScanning = 0;
		$opened = 0;
		
		close(BACKUPFILE);
		$backupParser = undef;
		resetScanState();
	}
}

sub stillScanning {
	return $isScanning;
}

sub doneScanning {
	debugMsg("done Scanning: unlocking and closing\n");

	if (defined $backupParserNB) {

		# This spews, but it's harmless.
		eval { $backupParserNB->parse_done };
	}

	$backupParserNB = undef;
	$backupParser   = undef;

	$opened = 0;

	$isScanning = 0;

	# Don't leak filehandles.
	close(BACKUPFILE);

	msg("TrackStat:Backup: Restore completed at ".(strftime ("%Y-%m-%d %H:%M:%S",localtime()))."\n");

	# Take the scanner off the scheduler.
	Slim::Utils::Scheduler::remove_task(\&scanFunction);
}

sub resetScanState {

	debugMsg("Resetting scan state.\n");

	$inTrack = 0;
	$inValue = 0;
	%item = ();
	$currentKey = undef;
}

sub scanFunction {
	# this assumes that iTunes uses file locking when writing the xml file out.
	if (!$opened) {
		open(BACKUPFILE, $backupFile) || do {
			warn "Couldn't open backup file: $backupFile";
			return 0;
		};

		$opened = 1;

		resetScanState();

		if (defined $backupParser) {

			debugMsg("Created a new Non-blocking XML parser.\n");

			$backupParserNB = $backupParser->parse_start();

		} else {

			debugMsg("No backupParser was defined!\n");
		}
	}

	# parse a little more from the stream.
	if (defined $backupParserNB) {

		debugMsg("Parsing next bit of XML..\n");

		local $/ = '</track>';
		my $line;

		for (my $i = 0; $i < 25; $i++) {
			$line .= <BACKUPFILE>;
		}

		$line =~ s/&#(\d*);/escape(chr($1))/ge;

		$backupParserNB->parse_more($line);

		return 1;
	}

	debugMsg("No backupParserNB defined!\n");

	return 0;
}

sub handleStartElement {
	my ($p, $element) = @_;

	# Don't care about the outer <dict> right after <plist>
	if ($inTrack) {
		$currentKey = $element;
		$inValue = 1;
	}
	if ($element eq 'track') {
		$inTrack = 1;
	}
	

}

sub handleCharElement {
	my ($p, $value) = @_;

	if ($inValue && $currentKey) {
		$item{$currentKey} = $value;
	}
}

sub handleEndElement {
	my ($p, $element) = @_;

	$inValue = 0;
	
	# Done reading this entry - add it to the database.
	if ($inTrack && $element eq 'track') {

		$inTrack = 0;

		$item{'url'} = unescape($item{'url'});
		restoreTrack(\%item);

		%item = ();
	}

	# Finish up
	if ($element eq 'TrackStat') {
		debugMsg("iTunes: Finished scanning iTunes XML\n");

		doneScanning();

		return 0;
	}
}

sub restoreTrack 
{
	my $curTrack = shift;
	
	my $url       = $curTrack->{'url'};
	my $mbId      = $curTrack->{'musicbrainzId'};
	my $playCount = $curTrack->{'playCount'};
	my $lastPlayed = $curTrack->{'lastPlayed'};
	my $added = $curTrack->{'added'};
	my $rating   = $curTrack->{'rating'};

	Plugins::TrackStat::Storage::saveTrack($url,$mbId,$playCount,$added,$lastPlayed,$rating);	
}
# A wrapper to allow us to uniformly turn on & off debug messages
sub debugMsg
{
	my $message = join '','TrackStat:Backup: ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_trackstat_showmessages"));
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
