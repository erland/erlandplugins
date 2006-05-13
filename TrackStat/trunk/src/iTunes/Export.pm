#         TrackStat::iTunes module
# 				TrackStat plugin 
#
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
#
#    Portions of code derived from the iTunesUpdate 1.7.2 plugin
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
                   
package Plugins::TrackStat::iTunes::Export;

use Date::Parse qw(str2time);
use Fcntl ':flock'; # import LOCK_* constants
use POSIX qw(strftime);
use File::Spec::Functions qw(:ALL);
use File::Basename;
use DBI qw(:sql_types);

use Slim::Utils::Misc;


my $backupFile;

sub startExport
{
	my $dir = Slim::Utils::Prefs::get('plugin_trackstat_itunes_export_dir');
	my $filename = catfile($dir,"TrackStat_iTunes_Complete.txt");
	my $replaceExtension = Slim::Utils::Prefs::get('plugin_trackstat_itunes_export_replace_extension');
	my $replacePath = Slim::Utils::Prefs::get('plugin_trackstat_itunes_export_library_music_path');
	my $nativeRoot = Slim::Utils::Prefs::get('audiodir');
	$nativeRoot =~ s/\\/\//isg;
	if(defined($replacePath) && $replacePath ne '') {
		$replacePath =~ s/\\/\//isg;
	}
	
	debugMsg("Exporting to iTunes: $filename\n");

	my $sql = "SELECT track_statistics.url, tracks.title, track_statistics.lastPlayed, track_statistics.playCount, track_statistics.rating FROM track_statistics,tracks where track_statistics.url=tracks.url and (track_statistics.lastPlayed is not null or track_statistics.rating>0)";

	my $ds = Slim::Music::Info::getCurrentDataStore();
	my $dbh = $ds->dbh();
	my $sth = $dbh->prepare( $sql );

	my $output = FileHandle->new($filename, ">") or do {
		warn "Could not open $filename for writing.";
		return;
	};

	my( $url, $title, $lastPlayed, $playCount, $rating );
	eval {
		$sth->execute();
		$sth->bind_columns( undef, \$url, \$title, \$lastPlayed, \$playCount, \$rating );
		my $result;
		while( $sth->fetch() ) {
			if($url) {
				if(!defined($rating)) {
					$rating='';
				}
				if(!defined($playCount)) {
					$playCount=1;
				}
				my $path = Slim::Utils::Misc::pathFromFileURL($url);
				if($replaceExtension) {
					$path =~ s/\.[^.]*$/$replaceExtension/isg;
				}

				if(defined($replacePath) && $replacePath ne '') {
					$path =~ s/\\/\//isg;
					$path =~ s/$nativeRoot/$replacePath/isg;
				}
				$title = Slim::Utils::Unicode::utf8decode($title,'utf8');
				
				if($lastPlayed) {
					my $timestr = strftime ("%Y%m%d%H%M%S", localtime $lastPlayed);
					print $output "$title|||$path|played|$timestr|$rating|$playCount\n";
				}elsif($rating && $rating>0) {
					print $output "$title|||$path|rated||$rating|\n";
				}
			}
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();

	close $output;
	debugMsg("Exporting to iTunes completed at ".(strftime ("%Y-%m-%d %H:%M:%S",localtime()))."\n");
}

# A wrapper to allow us to uniformly turn on & off debug messages
sub debugMsg
{
	my $message = join '','TrackStat::iTunes::Export: ',@_;
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
