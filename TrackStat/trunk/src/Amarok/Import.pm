#         TrackStat Amarok Import module
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
                   
package Plugins::TrackStat::Amarok::Import;

use Slim::Utils::Misc;
use Slim::Utils::Unicode;
use DBI qw(:sql_types);
use Plugins::TrackStat::Storage;
use Plugins::TrackStat::Amarok::Common;

my $amarokDbh = undef;

sub getCustomScanFunctions {
	my %functions = (
		'id' => 'amarokimport',
		'order' => '70',
		'defaultenabled' => 0,
		'name' => 'Amarok Statistics',
		'description' => "This module imports statistic information to SlimServer from Amarok media player. The information imported are ratings, playcounts and last played time. The import module only supports Amarok running towards a MySQL database, by default Amarok runs with a SQLite database and then this scanning module doesn\'t work. The imported information is read directly from the Amarok database.<br><br>The import module is prepared for having separate libraries in Amarok and SlimServer, for example the Amarok library in mp3 format and the SlimServer library in flac format. The music path and file extension parameters will in this case be used to convert the imported data so it corresponds to the paths and files used in SlimServer. If you are running Amarok and SlimServer on the same computer towards the same library the music path and file extension parameters can typically be left empty.",
		'alwaysRescanTrack' => 1,
		'scanTrack' => \&scanTrack,
		'initScanTrack' => \&initScanTrack,
		'exitScanTrack' => \&exitScanTrack,
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
				'validate' => \&Plugins::TrackStat::Plugin::validateIsDirOrEmpty,
				'value' => ''
			}
		]
	);
	return \%functions;
		
}

sub initScanTrack {
	my $dsn = Plugins::CustomScan::Plugin::getCustomScanProperty("amarokdatabaseurl");
	my $user = Plugins::CustomScan::Plugin::getCustomScanProperty("amarokdatabaseuser");
	my $password = Plugins::CustomScan::Plugin::getCustomScanProperty("amarokdatabasepassword");
	eval {
		$amarokDbh = DBI->connect($dsn, $user, $password);
	};
	if( $@ ) {
		warn "Database error: $DBI::errstr, $@\n";
		$amarokDbh = undef;
	}
	return undef;
}

sub exitScanTrack {
	if(defined($amarokDbh)) {
		eval { 
			$amarokDbh->disconnect();
		};
		if( $@ ) {
			warn "Database error: $DBI::errstr, $@\n";
		}
	}
	return undef;
}

sub scanTrack {
	my $track = shift;
	my @result = ();

	return \@result unless defined $amarokDbh;

	my $path = Plugins::TrackStat::Amarok::Common::getAmarokPath($track->path);

	my $amarokSth = $amarokDbh->prepare("select accessdate,percentage,rating,playcounter from statistics where url=?");
	eval {
		$amarokSth->bind_param(1, $path , SQL_VARCHAR);
		$amarokSth->execute();
		my $lastplayed;
		my $rating;
		my $percentage;
		my $playcount;
		$amarokSth->bind_col( 1, \$lastplayed);
		$amarokSth->bind_col( 2, \$percentage);
		$amarokSth->bind_col( 3, \$rating);
		$amarokSth->bind_col( 4, \$playcount);
		if( $amarokSth->fetch() ) {
			if(defined($rating)) {
				$rating = $rating*10;
			}
			debugMsg("Importing track: ".$path.", ".(defined($rating)?"Rating:".$rating:"").", ".(defined($playcount)?"Playcount:".$playcount:"")."\n");
			Plugins::TrackStat::Storage::mergeTrack($track->url,undef,$playcount,$lastplayed,$rating);
		}
		$amarokSth->finish();
	};
	if( $@ ) {
		warn "Database error: $DBI::errstr, $@\n";
	}

	return \@result;
}

sub debugMsg
{
	my $message = join '','TrackStat::Amarok::Import: ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_trackstat_showmessages"));
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
