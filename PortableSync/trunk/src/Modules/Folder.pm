#         PortableSync::Modules::Folder module
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
                   
package Plugins::PortableSync::Modules::Folder;

use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use File::Spec::Functions qw(:ALL);
use File::Copy;
use File::Basename qw(dirname);
use File::Path qw(mkpath);

my $prefs = preferences('plugin.portablesync');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.portablesync',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_PORTABLESYNC',
});

my %files_to_remove = ();

sub initExistingLibrary {
	my $context = shift;
	my $mountPath = shift;

	%files_to_remove=();
	initDirectoryContents($mountPath,undef,\%files_to_remove);
	return 1;
}

sub initDirectoryContents {
	my $path = shift;
	my $subpath = shift;
	my $files_to_remove = shift;

	my @dircontents = Slim::Utils::Misc::readDirectory($path);
	for my $item (@dircontents) {
		$item = Slim::Utils::Unicode::utf8decode($item);
		if(-d catdir($path,$item)) {
			my $dirpath = $item;
			if(defined($subpath)) {
				$dirpath = catdir($subpath,$item);
			}
			initDirectoryContents(catdir($path,$item),$dirpath,$files_to_remove);
		}else {
			if($subpath) {
				$files_to_remove->{catfile($subpath,$item)} = 1;
			}else {
				$files_to_remove->{$item} = 1;
			}
		}
	}
}

sub exitExistingLibrary {
	my $context = shift;
	my $mountPath = shift;

	my $nativeRoot = $serverPrefs->{'audiodir'};
	if(defined($nativeRoot)) {
		$nativeRoot =~ s/\\/\\\\/isg;
	}
	if(defined($nativeRoot) && $nativeRoot ne '' && $mountPath =~ /^$nativeRoot/) {
		$log->warn("Directory is below main music folder($nativeRoot): $mountPath");
		return 0;
	}

	for my $file (keys %files_to_remove) {
		my $fullpath = catfile($mountPath,$file);
		if(-e $fullpath) {
			$log->debug("Deleting file: $file\n");
			unlink($fullpath) or $log->debug("Failed to delete: $fullpath\n");
		}else {
			$log->debug("File doesn't exist, no reason to delete: $file\n");
		}
	}
	return 1;
}

sub keepSongInExistingLibrary {
	my $context = shift;
	my $path = shift;
	my $trackId = shift;

	delete $files_to_remove{$path};
	$log->debug("Do not remove $path");
	return 1;
}

sub writeSong {
	my $context = shift;
	my $mountPath = shift;
	my $path = shift;
	my $track = shift;

	my $target = catfile($mountPath,$path);
	my $source = Slim::Utils::Misc::pathFromFileURL($track->url);
	if($source eq $target) {
		$log->warn("Source and target is same file: $source");
		return 0;
	}
	my $nativeRoot = $serverPrefs->{'audiodir'};
	if(defined($nativeRoot)) {
		$nativeRoot =~ s/\\/\\\\/isg;
	}
	if(defined($nativeRoot) && $nativeRoot ne '' && $target =~ /^$nativeRoot/) {
		$log->warn("Target is below main music folder($nativeRoot): $target");
		return 0;
	}
	
	if(! (-d dirname($target))) {
		$log->debug("Creating directory: ".dirname($target));
		if(!mkpath(dirname($target))) {
			$log->warn("Failed to create directory on portable device, skipping: \"$target\"");
			return 0;
		}
	}else {
		$log->debug("Directory already exists: ".dirname($target));
	}
	if(!File::Copy::copy($source, $target)) {
#		unlink($target);
		$log->warn("Failed to copy file to portable device, skipping: \"$source\" to \"$target\"");
		return 0;
	}
	$log->debug("Copying: $source to: $target");
	return 1;
}

sub writeLibrary {
	my $context = shift;
}

1;

__END__
