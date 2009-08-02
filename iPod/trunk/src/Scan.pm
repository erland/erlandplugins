#         iPod::Scan module
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
                   
package Plugins::iPod::Scan;

use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use DBI qw(:sql_types);
use HTML::Entities;
use File::Spec::Functions qw(:ALL);
use GNUpod::FileMagic;
use GNUpod::CustomXMLhelper;
use GNUpod::FooBar;
use File::Copy;
use Slim::Schema;
use Slim::Utils::Unicode;

my $prefs = preferences('plugin.ipod');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.ipod',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_IPOD',
});

use constant MACTIME => GNUpod::FooBar::MACTIME;

my %dupdb_file = ();
my %dupdb_normal = ();
my %dupdb_lazy = ();
my %dupdb_podcast = ();
my %files_to_remove = ();

sub getCustomScanFunctions {
	my %functions = (
		'id' => 'ipodscan',
		'order' => '75',
		'defaultenabled' => 1,
		'name' => 'iPod Synchronization',
		'description' => "This module scans the Squeezebox Server library and generates the contents of the iPod libraries as defined in the iPod plugin.",
		'alwaysRescanTrack' => 1,
		'clearEnabled' => 0,
		'scanText' => 'Sync',
		'initScanTrack' => \&initScanTrack,
		'exitScanTrack' => \&exitScanTrack,
		'properties' => [
			{
				'id' => 'ipodmountpath',
				'name' => 'iPod Mount Path',
				'description' => 'The path to your iPod',
				'type' => 'text',
				'value' => '/media/ipod'
			},
		],
	);
	my $values = getSQLPropertyValues("select id,name from ipod_libraries");
	my %libraries = (
		'id' => 'ipodsynclibraries',
		'name' => 'Libraries to synchronize',
		'description' => 'The libraries that should be synchronized with your iPod',
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

sub initScanTrack {
	my $context = shift;
	my $iPodMountPath = Plugins::CustomScan::Plugin::getCustomScanProperty("ipodmountpath");
	if(defined($iPodMountPath) && $iPodMountPath eq '') {	
		$iPodMountPath = undef;
	}

	if(!defined($context->{'libraries'})) {
		$log->debug("Step: Retreiving available libraries\n");
		my $libraryHash = Plugins::iPod::Plugin::initLibraries();
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
			my $slimserverPath = $library->{'track'}->{'slimserverpath'};
			my $iPodPath = $library->{'track'}->{'ipodpath'};
			my $iPodExtension = $library->{'track'}->{'ipodextension'};
			if(defined($iPodExtension) && $iPodExtension ne '') {
				if($iPodExtension !~ /^\..*$/) {
					$iPodExtension = ".".$iPodExtension;
				}
				$path =~ s/\.[^\.]+$/$iPodExtension/;
			}
			if(defined($iPodPath) && $iPodPath ne '') {
				my $nativeRoot = $slimserverPath;
				if(!defined($nativeRoot) || $nativeRoot eq '') {
					$nativeRoot = $serverPrefs->get('audiodir');
				}
				$nativeRoot =~ s/\\/\\\\/isg;
				$path =~ s/$nativeRoot/$iPodPath/;
			}
			if( -e $path ) {
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
				my $sql = "INSERT INTO ipod_track (library,track,slimserverurl,musicbrainz_id,ipodpath,ipodfilesize) values (?,?,?,?,?,?)";
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
					$sth->bind_param(5, $path, SQL_VARCHAR);
					$sth->bind_param(6, $filesize, SQL_INTEGER);
					$sth->execute();
					commit(Slim::Schema->storage->dbh());
				};
				if( $@ ) {
				    warn "Database error: $@: $DBI::errstr\n";
				}
			}
		}else {
			$sth->finish();
			delete $context->{'songs'};
			$context->{'writexml'} = 1;
		}
		return 1;
	}elsif(defined($context->{'writexml'}) && defined($context->{'removesongs'})) {
		$log->debug("Step: Removing songs from iPod\n");
		my $library = $context->{'library'};
		my $sth = $context->{'removesongs'};
		my $trackId = undef;
		my $path = undef;
		$sth->bind_col(1, \$trackId);
		$sth->bind_col(2, \$path);
		if($sth->fetch()) {
			if(-e $path) {

				my $media_h;
				my $fh;
				if(!(($fh, $media_h) = prepareSong($path,$trackId))) {
					return 1;
				}
				
				my $wtf_ftyp = $media_h->{ftyp};      #'codec' .. maybe ALAC
				my $wtf_frmt = $media_h->{format};    #container ..maybe M4A
				my $wtf_ext  = $media_h->{extension}; #Possible extensions (regexp!)

				my $duppath = shift;
				if(!($duppath = checkduppath($fh))) {
					return 1;
				}

				delete $files_to_remove{$duppath};
				$log->debug("Do not remove $path = $duppath\n");
			}else {
				$log->debug("File does not exist, skipping: $path\n");
			}
		}else {
			$sth->finish();
			$log->debug("Preparing to delete files from iPod\n");
			for my $file (keys %files_to_remove) {
				my $transformedFile = $file;
				$transformedFile =~ s/:/\//g;
				$transformedFile =~ s/^\///;  # Remove / in beginning of path
				my $fullpath = catfile($iPodMountPath,$transformedFile);
				if(-e $fullpath) {
					$log->debug("Deleteing file: $fullpath\n");
					unlink($fullpath) or $log->debug("Failed to delete: $fullpath\n");
				}else {
					$log->debug("File doesn't exist, no reason to delete: $fullpath\n");
				}
			}
			delete $context->{'removesongs'};
			my $sql = "select tracks.id,ipod_track.ipodpath from tracks,ipod_track where tracks.id=ipod_track.track and ipod_track.library=".$library->{'libraryno'};
			$log->debug("Retreiving tracks with:".$sql."\n");
			my $sth = Slim::Schema->storage->dbh()->prepare($sql);
			$sth->execute();
			$context->{'xmlsongs'} = $sth;

			my %opts = (
				_no_sync => 0,
				mount => $iPodMountPath
			);
			my $con = GNUpod::FooBar::connect(\%opts);
			if($con->{status}) {
				$log->debug("Not writing XML file, ".$con->{status}."\n");
				delete $context->{'writexml'};
				return 1;
			}
			
			GNUpod::CustomXMLhelper::initxml();
			%dupdb_file = ();
			%dupdb_normal = ();
			%dupdb_lazy = ();
			%dupdb_podcast = ();
			if(!GNUpod::CustomXMLhelper::doxml($con->{xml})) {
				$log->debug("Not writing XML file, failed to parse ".$con->{xml}."\n");
				delete $context->{'writexml'};
				return 1;
			}
			$context->{'gnupodconnection'} = $con;
		}
		return 1;
	}elsif(defined($context->{'writexml'}) && defined($context->{'xmlsongs'})) {
		$log->debug("Step: Writing song to iPod\n");
		my $sth = $context->{'xmlsongs'};
		my $trackId = undef;
		my $path = undef;
		$sth->bind_col(1, \$trackId);
		$sth->bind_col(2, \$path);
		if($sth->fetch()) {
			if(-e $path) {
				my $library = $context->{'library'};

				my $track = Slim::Schema->resultset('Track')->find($trackId);
				if(!$track) {
					$log->debug("File not found in Squeezebox Server database, skipping: $path\n");
					return 1;
				}

				my $media_h;
				my $fh;
				if(!(($fh, $media_h) = prepareSong($path,$trackId))) {
					return 1;
				}

				my $wtf_ftyp = $media_h->{ftyp};      #'codec' .. maybe ALAC
				my $wtf_frmt = $media_h->{format};    #container ..maybe M4A
				my $wtf_ext  = $media_h->{extension}; #Possible extensions (regexp!)

				if(my $dup = checkdup($fh)) {
	                        	#create_playlist_now($opts{playlist}, $dup);
					$log->debug("Skipping, already exists in iPod: $path\n");
					return 1;
				}

				($fh->{path}, my $target) = GNUpod::CustomXMLhelper::getpath($iPodMountPath,$path,{
								format=>$wtf_frmt, 
								extension=>$wtf_ext, 
								keepfile=>0});

				if(!defined($target) || $target eq '') {
					$log->debug("No target file could be generated, skipping: $path\n");
					return 1;
				}
				
				if(!File::Copy::copy($path, $target)) {
					unlink($target);
					$log->debug("Failed to copy file to iPod, skipping: \"$path\" to \"$target\"\n");
					return 1;
				}
				
				$log->debug("Adding file: $path\n");
				my $id = GNUpod::CustomXMLhelper::mkfile({file=>$fh},{addid=>1}); #Try to add an id
                        	#create_playlist_now($opts{playlist}, $id);
			}else {
				$log->debug("File does not exist, skipping: $path\n");
			}
		}else {
			$sth->finish();
			if(defined($context->{'gnupodconnection'})) {
				GNUpod::CustomXMLhelper::writexml($context->{'gnupodconnection'}, {automktunes=>0});
			}
			delete $context->{'gnupodconnection'};
			delete $context->{'writexml'};
			delete $context->{'xmlsongs'};
		}
		return 1;
	}elsif(defined($context->{'writexml'}) && defined($context->{'library'})) {
		$log->debug("Step: Connecting to iPod\n");
		my $library = $context->{'library'};
		my $iPodSyncLibraries = Plugins::CustomScan::Plugin::getCustomScanProperty("ipodsynclibraries");
		if(defined($iPodSyncLibraries) && $iPodSyncLibraries eq '') {	
			$iPodSyncLibraries = undef;
		}
		if(!defined($iPodSyncLibraries)) {
			$log->debug("Not generating XML, no library is selected to be synchronized with iPod\n");
			delete $context->{'writexml'};
			return 1;
		}
		my $librarysql = "select id,name from ipod_libraries where ipod_libraries.id=".$library->{'libraryno'}." and ipod_libraries.id in ($iPodSyncLibraries)";
		$log->debug("Checking libraries with:".$librarysql."\n");
		my $librarysth = Slim::Schema->storage->dbh()->prepare($librarysql);
		$librarysth->execute();
		if(!$librarysth->fetch()) {
			$log->debug("Not generating XML, library shouldn't be synchronized with iPod: ".$library->{'name'}."\n");
			delete $context->{'writexml'};
			return 1;
		}
		$librarysth->finish();

		if(!defined($iPodMountPath) || !(-d $iPodMountPath)) {
			$log->debug("Not generating XML, iPod Mount path is not set or incorrect".(defined($iPodMountPath)?": ".$iPodMountPath:"")."\n");
			delete $context->{'writexml'};
			return 1;
		}
		my $ipodXMLDir = catdir($iPodMountPath,'iPod_Control');
		if(!(-e $ipodXMLDir)) {
			$log->debug("Not writing XML file, iPod not mounted at ".$iPodMountPath."\n");
			delete $context->{'writexml'};
			return 1;
		}

		my %opts = (
			_no_sync => 0,
			mount => $iPodMountPath
		);
		my $con = GNUpod::FooBar::connect(\%opts);
		if($con->{status}) {
			$log->debug("Not writing XML file, ".$con->{status}."\n");
			delete $context->{'writexml'};
			return 1;
		}

		my %parameters = (
			'newfile' => \&Plugins::iPod::Scan::newFileCallback,
			'newpl' => \&Plugins::iPod::Scan::newPlaylistCallback
		);
		GNUpod::CustomXMLhelper::set_callbacks(\%parameters);
		GNUpod::CustomXMLhelper::initxml();
		%dupdb_file = ();
		%dupdb_normal = ();
		%dupdb_lazy = ();
		%dupdb_podcast = ();
		%files_to_remove = ();
		if(!GNUpod::CustomXMLhelper::doxml($con->{xml})) {
			$log->debug("Not writing XML file, failed to parse ".$con->{xml}."\n");
			delete $context->{'writexml'};
			return 1;
		}
		$context->{'gnupodconnection'} = $con;

		my $sql = "select tracks.id,ipod_track.ipodpath from tracks,ipod_track where tracks.id=ipod_track.track and ipod_track.library=".$library->{'libraryno'};
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
		my $sql = "DELETE FROM ipod_track WHERE library=?";
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

	#Get the filetype
	my ($fh,$media_h,$converter) =  GNUpod::FileMagic::wtf_is($path, {
								noIDv1=>0, 
								noIDv2=>0,
								decode=>0});

	if(!$fh) {
		$log->debug("Unknown file type, skipping: $path\n");
		return;
	}

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
	$fh->{addtime} = int(time())+MACTIME;

	#Ugly workaround to avoid a warning while running mktunes.pl:
	#All (?) int-values returned by wtf_is won't go above 0xffffffff
	#Thats fine because almost everything inside an mhit can handle this.
	#But bpm and srate are limited to 0xffff
	# -> We fix this silently to avoid ugly warnings while running mktunes.pl
	$fh->{bpm}   = 0xFFFF if defined($fh->{bpm}) && $fh->{bpm}   > 0xFFFF;
	$fh->{srate} = 0xFFFF if defined($fh->{srate}) && $fh->{srate} > 0xFFFF;

	# TODO: Implement replay gain conversions later
	$fh->{volume} = 0;

	return ($fh,$media_h);
}

sub newFileCallback {
	if(!defined($files_to_remove{$_[0]->{file}->{path}})) {
		$files_to_remove{$_[0]->{file}->{path}} = 1;
		$dupdb_file{lc($_[0]->{file}->{title})."/$_[0]->{file}->{bitrate}/$_[0]->{file}->{time}/$_[0]->{file}->{filesize}"}= $_[0]->{file}->{path}||-1;
		$dupdb_normal{lc($_[0]->{file}->{title})."/$_[0]->{file}->{bitrate}/$_[0]->{file}->{time}/$_[0]->{file}->{filesize}"}= $_[0]->{file}->{id}||-1;

		#This is worse than _normal, but the only way to detect dups *before* re-encoding...
		$dupdb_lazy{lc($_[0]->{file}->{title})."/".lc($_[0]->{file}->{album})."/".lc($_[0]->{file}->{artist})}= $_[0]->{file}->{id}||-1;
        
		#Add podcast infos if it is an podcast
		if($_[0]->{file}->{podcastguid}) {
		        $dupdb_podcast{$_[0]->{file}->{podcastguid}."\0".$_[0]->{file}->{podcastrss}}++;
		}
        
		$log->debug("Adding file from XML: ".$_[0]->{file}->{title}."\n");
		GNUpod::CustomXMLhelper::mkfile($_[0],{addid=>1});
	}
}

sub newPlaylistCallback {
	GNUpod::CustomXMLhelper::mkfile($_[0],{$_[2]."name"=>$_[1]});
}

sub checkdup {
	my($fh, $from_lazy) = @_;

	if($from_lazy) {
		my $key = lc($fh->{title})."/".lc($fh->{album})."/".lc($fh->{artist});
		return  $dupdb_lazy{Slim::Utils::Unicode::utf8off($key)} 
	}else {
		my $key = lc($fh->{title})."/$fh->{bitrate}/$fh->{time}/$fh->{filesize}";
		return $dupdb_normal{Slim::Utils::Unicode::utf8off($key)};
	}
}

sub checkduppath {
	my($fh, $from_lazy) = @_;

	if($from_lazy) {
		my $key = lc($fh->{title})."/".lc($fh->{album})."/".lc($fh->{artist});
		if(exists $dupdb_lazy{Slim::Utils::Unicode::utf8off($key)}) {
			$key = lc($fh->{title})."/$fh->{bitrate}/$fh->{time}/$fh->{filesize}";
			return $dupdb_file{Slim::Utils::Unicode::utf8off($key)};
		}
	}else {
		my $key = lc($fh->{title})."/$fh->{bitrate}/$fh->{time}/$fh->{filesize}";
		if(exists $dupdb_normal{Slim::Utils::Unicode::utf8off($key)}) {
			return $dupdb_file{Slim::Utils::Unicode::utf8off($key)};
		}
	}
	return;
}

sub exitScanTrack {
	my $context = shift;

#	if(!defined($context->{'library'})) {
#		my $libraryHash = Plugins::iPod::Plugin::initLibraries();
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
