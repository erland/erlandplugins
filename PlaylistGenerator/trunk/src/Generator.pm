#         Export module
#
#    Copyright (c) 2009 Erland Isaksson (erland_i@hotmail.com)
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
                   
package Plugins::PlaylistGenerator::Generator;

use Slim::Utils::Prefs;
use Date::Parse qw(str2time);
use Fcntl ':flock'; # import LOCK_* constants
use POSIX qw(strftime);
use File::Spec::Functions qw(:ALL);
use DBI qw(:sql_types);
use Slim::Utils::Misc;
use Slim::Player::Playlist;
use Time::Stopwatch;
use Plugins::PlaylistGenerator::Plugin;

my $prefs = preferences('plugin.playlistgenerator');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.playlistgenerator',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_PLAYLISTGENERATOR',
});

my @playlistTrackIds = ();
my @playlistTracks = ();
my @playlistsToGenerate = ();
my $currentPlaylist = undef;

sub init {
	my @selectedPlaylists = @_;
	$log->info("Start generating playlists at ".(strftime ("%Y-%m-%d %H:%M:%S",localtime())));
	Plugins::PlaylistGenerator::Plugin::initPlaylistDefinitions();
	my $playlists = Plugins::PlaylistGenerator::Plugin::getPlaylistDefinitions();
	@playlistsToGenerate = ();
	@playlistTrackIds = ();
	@playlistTracks = ();
	$currentPlaylist = undef;

	if(scalar(@selectedPlaylists)==0) {
		for my $playlist (keys %$playlists) {
			my $playlistName = $playlists->{$playlist}->{'id'};
			$log->debug("Preparing for generating $playlistName");
			push @playlistsToGenerate,$playlists->{$playlist};
		}
	}else {
		for my $playlist (@selectedPlaylists) {
			my $playlistName = $playlists->{$playlist}->{'id'};
			$log->debug("Preparing for generating $playlistName");
			push @playlistsToGenerate,$playlists->{$playlist};
		}
	}
	@playlistsToGenerate = sort { $a->{'generateorder'} <=> $b->{'generateorder'} } @playlistsToGenerate;

	return undef;
}

sub next
{
	my $timeMeasure = Time::Stopwatch->new();
	$timeMeasure->clear();
	$timeMeasure->start();

	if(scalar(@playlistTrackIds)==0 && scalar(@playlistTracks)==0) {
		$currentPlaylist = shift @playlistsToGenerate;
		if(defined($currentPlaylist)) {
			$log->info("Generating playlist ".$currentPlaylist->{'name'});
			my %empty = ();
			my $result = executePlaylistStatement($currentPlaylist,\%empty);
			if(!exists $result->{'error'}) {
				my $trackIds = $result->{'items'};
				@playlistTracks = ();
				@playlistTrackIds = @$trackIds;
				if(scalar(@playlistTrackIds)==0) {
					deletePlaylist($currentPlaylist->{'name'});
					$log->info("Finished fetching song references from database for playlist: ".$currentPlaylist->{'name'}.", no references found playlist deleted: It took ".$timeMeasure->getElapsedTime()." seconds");
				}else {
					$log->info("Finished fetching song references from database for playlist: ".$currentPlaylist->{'name'}.": It took ".$timeMeasure->getElapsedTime()." seconds");
					$log->info("Fetching ".scalar(@playlistTrackIds)." songs, this might take a while...");
				}
				$timeMeasure->stop();
				$timeMeasure->clear();
				return 1;
			}else {
				@playlistTracks = ();
				@playlistTrackIds = ();
				$log->warn("Error fetching song references from database for playlist: ".$currentPlaylist->{'name'}.": ".$result->{'error'}."It took ".$timeMeasure->getElapsedTime()." seconds");
				$timeMeasure->stop();
				$timeMeasure->clear();
				return 1;
			}
		}
	}elsif(scalar(@playlistTrackIds)>0) {
		my $trackId = shift @playlistTrackIds;
		my $track = Slim::Schema->resultset('Track')->find($trackId);
		if(defined($track)) {
			push @playlistTracks,$track;
		}
		return 1;

	}elsif(scalar(@playlistTrackIds)==0 && scalar(@playlistTracks)>0) {
		my $playlistDir = $serverPrefs->get('playlistdir');
		my $playlistObj = getPlaylist($playlistDir, $currentPlaylist->{'name'});
		$playlistObj->setTracks(\@playlistTracks);
		$playlistObj->update;

		$log->info("Finished updating playlist: ".$playlistObj->title." : It took ".$timeMeasure->getElapsedTime()." seconds");
		$timeMeasure->stop();
		$timeMeasure->clear();

		# Lets make sure streaming gets it time
		main::idleStreams();

		$timeMeasure->start();

		Slim::Schema->forceCommit;
	
		if(scalar($playlistObj->tracks())>0) {
			Slim::Player::Playlist::scheduleWriteOfPlaylist(undef,$playlistObj);
			$log->info("Finished writing playlist ".$playlistObj->title." : It took ".$timeMeasure->getElapsedTime()." seconds");
			$timeMeasure->stop();
			$timeMeasure->clear();

			# Lets make sure streaming gets it time
			main::idleStreams();

			$timeMeasure->start();
		}else {
			deletePlaylist($playlistObj->title);
			$log->info("Finished deleting playlist ".$playlistObj->title." : It took ".$timeMeasure->getElapsedTime()." seconds");
			$timeMeasure->stop();
			$timeMeasure->clear();

			# Lets make sure streaming gets it time
			main::idleStreams();

			$timeMeasure->start();
		}
		@playlistTracks = ();
		return 1;
	}


	$log->info("Finished generating playlists at ".(strftime ("%Y-%m-%d %H:%M:%S",localtime())));

	$timeMeasure->stop();
	$timeMeasure->clear();
	return undef;
}

sub exit
{
}

sub executePlaylistStatement {
	my $dataQuery = shift;

	my $sql = $dataQuery->{'statement'} if exists $dataQuery->{'statement'};

	my @statements = ();
	if(ref($sql) eq 'ARRAY') {
		for my $statement (@$sql) {
			push  @statements,$statement;
		}
	}else {
		push @statements,$sql;
	}
	my %result = ();
	if(scalar(@statements)==0) {
		$result{'error'} .= "No query defined";
	}
	for my $sql (@statements) {
		if(defined($sql)) {
			$sql =~ s/^\s*(.*)\s*$/$1/;
		}
		my @objectIds = ();
		eval {
			if(defined($sql)) {
				$log->debug("Executing: $sql\n");
				my $sth = Slim::Schema->storage->dbh()->prepare($sql);
				$sth->execute();
				my $objectId;
				$sth->bind_col(1,\$objectId);
				while( $sth->fetch() ) 	 {
					push @objectIds,$objectId;
				}
				$sth->finish();
			}else {
				if(!defined($result{'error'})) {
					$result{'error'} = '';
				}else {
					$result{'error'} .= "\n";
				}
				$result{'error'} .= "No query defined";
			}
		};
		if($@) {
			if(!defined($result{'error'})) {
				$result{'error'} = '';
			}else {
				$result{'error'} .= "\n";
			}
			$result{'error'} .= "$@, $DBI::errstr";
		}else {
			$result{'items'} = \@objectIds;
		}
	}
	return \%result;
}

sub executePlaylistStatementAsObjectList {
	my $playlistDefinition = shift;

	my $result = executePlaylistStatement($playlistDefinition);
	if(!exists $result->{'error'}) {
		my @objects = ();
		my $objectIds = $result->{'items'};
		for my $id (@$objectIds) {
			my $object = Slim::Schema->resultset('Track')->find($id);
			if(defined($object)) {
				push @objects,$object;
			}
			# Lets make sure streaming gets it time
			main::idleStreams();
		}
		$result->{'items'} = \@objects;
	}
	return $result
}


sub getPlaylist {
	my $playlistDir = shift;
	my $title = shift;

	my $titlesort = Slim::Utils::Text::ignoreCaseArticles($title);
	my $playlistObj = Slim::Schema->rs('Playlist')->updateOrCreate({
		'url' => Slim::Utils::Misc::fileURLFromPath(catfile($playlistDir, Slim::Utils::Unicode::utf8encode_locale($title).".m3u")),
		'attributes' => {
			'TITLE' => $title,
			'CT'	=> 'ssp',
		},
	});
	$playlistObj->set_column('titlesort',$titlesort);
	$playlistObj->set_column('titlesearch',$titlesort);
	$playlistObj->update;
	return $playlistObj;
}


sub deletePlaylist {
	my $title = shift;

	my $playlistDir = $serverPrefs->get('playlistdir');

	if($title && $playlistDir) {
		my $playlistObj = getPlaylist($playlistDir, $title);

		Slim::Player::Playlist::removePlaylistFromDisk($playlistObj);
		my @tracks = ();
		$playlistObj->setTracks(\@tracks);
		$playlistObj->delete;
		$playlistObj = undef;
		Slim::Schema->forceCommit;
	}
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
