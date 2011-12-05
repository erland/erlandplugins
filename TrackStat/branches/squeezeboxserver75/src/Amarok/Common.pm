#         TrackStat Amarok Common module
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
                   
package Plugins::TrackStat::Amarok::Common;

use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;

my $serverPrefs = preferences('server');

sub getAmarokPath {
	my $path = shift;

	my $amarokExtension = Plugins::CustomScan::Plugin::getCustomScanProperty("amarokextension");
	if(defined($amarokExtension) && $amarokExtension ne '') {
		if($amarokExtension !~ /^\..*$/) {
			$amarokExtension = ".".$amarokExtension;
		}
		$path =~ s/\.[^\.]+$/$amarokExtension/;
	}
	my $amarokMusicPath = Plugins::CustomScan::Plugin::getCustomScanProperty("amarokmusicpath");
	my $slimserverMusicPath = Plugins::CustomScan::Plugin::getCustomScanProperty("amarokslimservermusicpath");
	if(defined($amarokMusicPath) && $amarokMusicPath ne '') {
		my $nativeRoot = $slimserverMusicPath;
		if(!defined($nativeRoot) || $nativeRoot eq '') {
			$nativeRoot = $serverPrefs->get('audiodir');
		}
		$nativeRoot =~ s/\\/\\\\/isg;
		$path =~ s/$nativeRoot/$amarokMusicPath/;
	}
	if($path !~ /^\./) {
		$path = ".".$path;
	}
	return $path;
}


*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
