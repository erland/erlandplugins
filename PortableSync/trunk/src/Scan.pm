#         PortableSync::Scan module
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
                   
package Plugins::PortableSync::Scan;

use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use DBI qw(:sql_types);
use HTML::Entities;
use File::Spec::Functions qw(:ALL);
use Slim::Schema;
use Slim::Utils::Unicode;
use Plugins::PortableSync::Modules::Folder;

my $prefs = preferences('plugin.portablesync');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.portablesync',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_PORTABLESYNC',
});

sub getCustomScanFunctions {
	my %functions = (
		'id' => 'portablescan',
		'order' => '75',
		'defaultenabled' => 1,
		'name' => 'Portable Synchronization',
		'description' => "This module scans the Squeezebox Server library and generates the contents of the portable libraries as defined in the Portable Sync plugin.",
		'alwaysRescanTrack' => 1,
		'requiresRefresh' => 0,
		'clearEnabled' => 0,
		'scanText' => 'Sync',
		'initScanTrack' => \&initScanTrack,
		'exitScanTrack' => \&exitScanTrack,
		'properties' => [
			{
				'id' => 'portablemountpath',
				'name' => 'Portable Mount Path',
				'description' => 'The path to your portable device',
				'type' => 'text',
				'value' => '/media/portable'
			},
		],
	);
	my $values = getSQLPropertyValues("select id,name from portable_libraries");
	my %libraries = (
		'id' => 'portablesynclibraries',
		'name' => 'Libraries to synchronize',
		'description' => 'The libraries that should be synchronized with your portable device',
		'type' => 'multiplelist',
		'values' => $values,
		'value' => ''
	);
	my $properties = $functions{'properties'};
	push @$properties,\%libraries;

	return \%functions;
}

sub getSQLPropertyValues {
	my $sqlstatements = shift;
	my @result =();
	my $dbh = Slim::Schema->storage->dbh();

	my $newUnicodeHandling = 0;
	if(UNIVERSAL::can("Slim::Utils::Unicode","hasEDD")) {
		$newUnicodeHandling = 1;
	}

	my $trackno = 0;
    	for my $sql (split(/[;]/,$sqlstatements)) {
	    	eval {
			$sql =~ s/^\s+//g;
			$sql =~ s/\s+$//g;
			my $sth = $dbh->prepare( $sql );
			$log->debug("Executing: $sql\n");
			$sth->execute() or do {
				warn "Error executing: $sql\n";
				$sql = undef;
			};
	
			if ($sql =~ /^SELECT+/oi) {
				$log->debug("Executing and collecting: $sql\n");
				my $id;
				my $name;
				$sth->bind_col( 1, \$id);
				$sth->bind_col( 2, \$name);
				while( $sth->fetch() ) {
					if($newUnicodeHandling) {
						my %item = (
							'id' => Slim::Utils::Unicode::utf8decode($id,'utf8'),
							'name' => Slim::Utils::Unicode::utf8decode($name,'utf8')
						);
						push @result, \%item;
					}else {
						my %item = (
							'id' => Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($id,'utf8')),
							'name' => Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($name,'utf8'))
						);
						push @result, \%item;
					}
				}
			}
			$sth->finish();
		};
		if( $@ ) {
			warn "Database error: $DBI::errstr\n";
		}		
	}
	return \@result;
}

sub getPortablePath {
	my $library = shift;
	my $path = shift;

	my $slimserverPath = $library->{'track'}->{'slimserverpath'};
	my $nativeRoot = $slimserverPath;
	if(!defined($nativeRoot) || $nativeRoot eq '') {
		$nativeRoot = $serverPrefs->get('audiodir');
	}
	$nativeRoot =~ s/\\/\\\\/isg;
	my $portablePath = $path;
	$portablePath =~ s/$nativeRoot//;
	my $portableExtension = $library->{'track'}->{'portableextension'};
	if(defined($portableExtension) && $portableExtension ne '') {
		if($portableExtension !~ /^\..*$/) {
			$portableExtension = ".".$portableExtension;
		}
		$portablePath =~ s/\.[^\.]+$/$portableExtension/;
	}
	$portablePath =~ s/^\///;
	$portablePath =~ s/^\\//;
	return $portablePath;
}

sub initScanTrack {
	my $context = shift;

	if(!defined($context->{'libraries'})) {
		$log->debug("Step: Retreiving available libraries\n");
		my $libraryHash = Plugins::PortableSync::Plugin::initLibraries();
		my @libraries = ();
		for my $key (keys %$libraryHash) {
			my $lib = $libraryHash->{$key};
			push @libraries,$lib;
			$log->debug("Added library ".$lib->{'name'}."\n");
		}
		$context->{'libraries'} = \@libraries;
		return 1;
	}elsif(defined($context->{'songs'})) {
		$log->debug("Step: Scanning song\n");
		my $sth = $context->{'songs'};
		my $trackId = undef;
		my $trackUrl = undef;
		my $trackMusicbrainzId = undef;
		$sth->bind_col(1, \$trackId);
		$sth->bind_col(2, \$trackUrl);
		$sth->bind_col(3, \$trackMusicbrainzId);
		if($sth->fetch()) {
			my $path = Slim::Utils::Misc::pathFromFileURL($trackUrl);
			$log->debug("Handling song ".$path."\n");
			my $library = $context->{'library'};
			my $portablePath = getPortablePath($library,$path);
			if( -e $path) {
				my $filesize = -s $path;
				$context->{'limitstatus'}->{'nooftracks'} = $context->{'limitstatus'}->{'nooftracks'}+1;
				$context->{'limitstatus'}->{'size'} = $context->{'limitstatus'}->{'size'}+$filesize;
				if((defined($context->{'limit'}->{'nooftracks'}) && $context->{'limitstatus'}->{'nooftracks'}>$context->{'limit'}->{'nooftracks'}) ||
					(defined($context->{'limit'}->{'size'}) && $context->{'limitstatus'}->{'size'}>($context->{'limit'}->{'size'}*1024*1024))) {

					$sth->finish();
					delete $context->{'songs'};
					$context->{'writexml'} = 1;
					return 1;
				}
				$log->debug("Storing song ".$path."\n");
				my $sql = "INSERT INTO portable_track (library,track,slimserverurl,musicbrainz_id,portablepath,portablefilesize) values (?,?,?,?,?,?)";
				my $sth = Slim::Schema->storage->dbh()->prepare( $sql );
				eval {
					$sth->bind_param(1, $library->{'libraryno'} , SQL_INTEGER);
					$sth->bind_param(2, $trackId , SQL_INTEGER);
					$sth->bind_param(3, $trackUrl , SQL_VARCHAR);
					if(defined($trackMusicbrainzId) && $trackMusicbrainzId =~ /.+-.+/) {
						$sth->bind_param(4,  $trackMusicbrainzId, SQL_VARCHAR);
					}else {
						$sth->bind_param(4,  undef, SQL_VARCHAR);
					}
					$sth->bind_param(5, $portablePath, SQL_VARCHAR);
					$sth->bind_param(6, $filesize, SQL_INTEGER);
					$sth->execute();
					commit(Slim::Schema->storage->dbh());
				};
				if( $@ ) {
				    warn "Database error: $@: $DBI::errstr\n";
				}
			}else {
				$log->debug("Invalid track: $path");
			}
		}else {
			$sth->finish();
			delete $context->{'songs'};
			$context->{'writexml'} = 1;
		}
		return 1;
	}elsif(defined($context->{'writexml'}) && defined($context->{'removesongs'})) {
		$log->debug("Step: Removing songs from portable device\n");
		my $library = $context->{'library'};
		my $portableMountPath = $library->{'track'}->{'portablemountpath'};
		if(defined($portableMountPath) && $portableMountPath eq '') {	
			$portableMountPath = undef;
		}
		my $sth = $context->{'removesongs'};
		my $trackId = undef;
		my $path = undef;
		$sth->bind_col(1, \$trackId);
		$sth->bind_col(2, \$path);
		if($sth->fetch()) {
			Plugins::PortableSync::Modules::Folder::keepSongInExistingLibrary($context,$path,$trackId);
		}else {
			$sth->finish();
			$log->debug("Preparing to delete files from portable device\n");
			my $continue = Plugins::PortableSync::Modules::Folder::exitExistingLibrary($context,$portableMountPath);
			delete $context->{'removesongs'};
			my $sql = "select tracks.id,portable_track.portablepath from tracks,portable_track where tracks.id=portable_track.track and portable_track.library=".$library->{'libraryno'};
			$log->debug("Retreiving tracks with:".$sql."\n");
			my $sth = Slim::Schema->storage->dbh()->prepare($sql);
			$sth->execute();
			$context->{'xmlsongs'} = $sth;

			if(!$continue) {
				delete $context->{'writexml'};
				return 1;
			}
		}
		return 1;
	}elsif(defined($context->{'writexml'}) && defined($context->{'xmlsongs'})) {
		$log->debug("Step: Writing song to portable device\n");
		my $sth = $context->{'xmlsongs'};
		my $trackId = undef;
		my $path = undef;
		$sth->bind_col(1, \$trackId);
		$sth->bind_col(2, \$path);
		if($sth->fetch()) {
			my $library = $context->{'library'};
			my $portableMountPath = $library->{'track'}->{'portablemountpath'};
			if(defined($portableMountPath) && $portableMountPath eq '') {	
				$portableMountPath = undef;
			}

			my $track = Slim::Schema->resultset('Track')->find($trackId);
			if(!$track) {
				$log->debug("File not found in Squeezebox Server database, skipping: $path\n");
				return 1;
			}

			Plugins::PortableSync::Modules::Folder::writeSong($context,$portableMountPath,$path,$track);
			$log->debug("Adding file: $path\n");
		}else {
			$sth->finish();
			Plugins::PortableSync::Modules::Folder::writeLibrary($context);
			delete $context->{'writexml'};
			delete $context->{'xmlsongs'};
		}
		return 1;
	}elsif(defined($context->{'writexml'}) && defined($context->{'library'})) {
		$log->debug("Step: Connecting to portable deivice\n");
		my $library = $context->{'library'};
		my $portableMountPath = $library->{'track'}->{'portablemountpath'};
		if(defined($portableMountPath) && $portableMountPath eq '') {	
			$portableMountPath = undef;
		}

		my $portableSyncLibraries = Plugins::CustomScan::Plugin::getCustomScanProperty("portablesynclibraries");
		if(defined($portableSyncLibraries) && $portableSyncLibraries eq '') {	
			$portableSyncLibraries = undef;
		}
		if(!defined($portableSyncLibraries)) {
			$log->debug("Not generating XML, no library is selected to be synchronized with portable device\n");
			delete $context->{'writexml'};
			return 1;
		}
		my $librarysql = "select id,name from portable_libraries where portable_libraries.id=".$library->{'libraryno'}." and portable_libraries.id in ($portableSyncLibraries)";
		$log->debug("Checking libraries with:".$librarysql."\n");
		my $librarysth = Slim::Schema->storage->dbh()->prepare($librarysql);
		$librarysth->execute();
		if(!$librarysth->fetch()) {
			$log->debug("Not generating XML, library shouldn't be synchronized with portable device: ".$library->{'name'}."\n");
			delete $context->{'writexml'};
			return 1;
		}
		$librarysth->finish();

		if(!defined($portableMountPath) || !(-d $portableMountPath)) {
			$log->debug("Not generating XML, Portable Mount path is not set or incorrect".(defined($portableMountPath)?": ".$portableMountPath:"")."\n");
			delete $context->{'writexml'};
			return 1;
		}

		if(!Plugins::PortableSync::Modules::Folder::initExistingLibrary($context,$portableMountPath)) {
			delete $context->{'writexml'};
			return 1;
		}

		my $sql = "select tracks.id,portable_track.portablepath from tracks,portable_track where tracks.id=portable_track.track and portable_track.library=".$library->{'libraryno'};
		$log->debug("Retreiving tracks with:".$sql."\n");
		my $sth = Slim::Schema->storage->dbh()->prepare($sql);
		$sth->execute();
		$context->{'removesongs'} = $sth;
		return 1;
	}elsif(defined($context->{'libraries'})) {
		$log->debug("Step: Getting next library\n");
		my $libraries = $context->{'libraries'};
		my $library = shift @$libraries;
		if(!defined($library)) {
			return undef;
		}
		$log->debug("Handling library ".$library->{'name'}."\n");
		my %limit = ();
		my %limitstatus = ();
		$context->{'limit'} = \%limit;
		$context->{'limitstatus'} = \%limitstatus;
		$context->{'limitstatus'}->{'size'} = 0;
		$context->{'limitstatus'}->{'nooftracks'} = 0;
		if(defined($library->{'track'}->{'limit'}->{'parameter'})) {
			my $parameters = $library->{'track'}->{'limit'}->{'parameter'};
			my @parameterArray = ();
			if(ref($parameters) ne 'ARRAY') {
				push @parameterArray,$parameters;
			}else {
				@parameterArray = @$parameters;
			}
			for my $p (@parameterArray) {
				if($p->{'id'} eq 'size' && $p->{'value'} ne '') {
					$context->{'limit'}->{'size'} = $p->{'value'};
				}elsif($p->{'id'} eq 'nooftracks' && $p->{'value'} ne '') {
					$context->{'limit'}->{'nooftracks'} = $p->{'value'};
				}
			}
		}
		my $sql = "DELETE FROM portable_track WHERE library=?";
		my $sth = Slim::Schema->storage->dbh()->prepare( $sql );
		eval {
			$sth->bind_param(1, $library->{'libraryno'} , SQL_INTEGER);
			$sth->execute();
			commit(Slim::Schema->storage->dbh());
		};
		if( $@ ) {
		    warn "Database error: $@: $DBI::errstr\n";
		}
		$sth->finish();

		$sql = $library->{'track'}->{'data'};
		my %parameters = (
			'library' => $library->{'libraryno'}
		);
		$sql = replaceParameters($sql,\%parameters);
		$log->debug("Retreiving tracks with:".$sql."\n");
		$sth = Slim::Schema->storage->dbh()->prepare($sql);
		$sth->execute();
		$context->{'library'} = $library;
		$context->{'songs'} = $sth;
		return 1;
	}
	return undef;
}

sub prepareSong {
	my $path = shift;
	my $trackId = shift;

	my $fh = {};

	my $track = Slim::Schema->resultset('Track')->find($trackId);
	if(!$track) {
		$log->debug("File not found in Squeezebox Server database, skipping: $path\n");
		return;
	}


	my $artist = $track->artist;
	my $album = $track->album;
	my $genre = $track->genre;

	$fh->{artist}      = $artist->name      if $artist->name;
	$fh->{album}       = $album->title      if $album->title;
	$fh->{genre}       = $genre->name       if $genre->name;
	$fh->{rating}      = $track->rating     if $track->rating;
	$fh->{playcount}   = $track->playcount  if $track->playcount;
	$fh->{title}       = $track->title      if $track->title;
	$fh->{songnum}     = $track->tracknum   if $track->tracknum;

	#Set the addtime to unixtime(now)+MACTIME (the iPod uses mactime)
	#This breaks perl < 5.8 if we don't use int(time()) !
	$fh->{addtime} = int(time());

	#Ugly workaround to avoid a warning while running mktunes.pl:
	#All (?) int-values returned by wtf_is won't go above 0xffffffff
	#Thats fine because almost everything inside an mhit can handle this.
	#But bpm and srate are limited to 0xffff
	# -> We fix this silently to avoid ugly warnings while running mktunes.pl
	$fh->{bpm}   = 0xFFFF if defined($fh->{bpm}) && $fh->{bpm}   > 0xFFFF;
	$fh->{srate} = 0xFFFF if defined($fh->{srate}) && $fh->{srate} > 0xFFFF;

	# TODO: Implement replay gain conversions later
	$fh->{volume} = 0;
use Data::Dumper;
$log->debug("GOT: ".Dumper($fh));
	return $fh;
}

sub exitScanTrack {
	my $context = shift;

#	if(!defined($context->{'library'})) {
#		my $libraryHash = Plugins::PortableSync::Plugin::initLibraries();
#		$context->{'libraries'} = \@libraries;
#		return 1;

	return undef;
}
sub replaceParameters {
    my $originalValue = shift;
    my $parameters = shift;

    if(defined($parameters)) {
        for my $param (keys %$parameters) {
            my $value = encode_entities($parameters->{$param},"&<>\'\"");
	    $value = Slim::Utils::Unicode::utf8on($value);
	    $value = Slim::Utils::Unicode::utf8encode_locale($value);
            $originalValue =~ s/\{$param\}/$value/g;
        }
    }
    return $originalValue;
}

sub commit {
	my $dbh = shift;
	if (!$dbh->{'AutoCommit'}) {
		$dbh->commit();
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
