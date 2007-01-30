# 				Remove Played Songs plugin 
#
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

package Plugins::RemovePlayedSongs::Plugin;

use strict;

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use File::Spec::Functions qw(:ALL);
use DBI qw(:sql_types);

my $curIndex = undef;
my $curSong = undef;
sub getDisplayName {
	return 'PLUGIN_REMOVEPLAYEDSONGS';
}


sub initPlugin {
	my $class = shift;
	Slim::Control::Request::subscribe(\&newSongCallback, [['playlist'], ['newsong']]);
	Slim::Control::Request::subscribe(\&playlistClearedCallback, [['playlist'], ['delete','clear','loadtracks','playtracks','load','play','loadalbum','playalbum']]);
}

sub shutdownPlugin {
	Slim::Control::Request::unsubscribe(\&newSongCallback);
	Slim::Control::Request::unsubscribe(\&playlistClearedCallback);
}

sub newSongCallback 
{
	my $request = shift;
	my $client = undef;
	my $command = undef;
	
	$client = $request->client();	
	if (defined($client) && !defined($client->master) && $request->getRequest(0) eq 'playlist') {
		my $index = Slim::Player::Source::playingSongIndex($client);
		my $song = Slim::Player::Playlist::song($client);
		if($index>0 && defined($curIndex)) {
			my $firstSong = Slim::Player::Playlist::song($client,0);
			my $prevSong = Slim::Player::Playlist::song($client,$curIndex);
			if(defined($prevSong) && defined($curSong) && $prevSong->url eq $curSong->url) {
				Slim::Player::Playlist::removeTrack($client,$curIndex);	
				if($curIndex<$index) {
					$index = $index - 1;
				}
			}elsif(defined($firstSong) && defined($curSong) && $firstSong->url eq $curSong->url) {
				Slim::Player::Playlist::removeTrack($client,0);	
				$index = $index - 1;
			}
		}
		$curSong = $song;
		$curIndex = $index;
	}	
}

sub playlistClearedCallback
{
	$curIndex = undef;
	$curSong = undef;
}


sub strings {
	return <<EOF;
PLUGIN_REMOVEPLAYEDSONGS
	EN	Remove Played Songs

EOF

}

1;

__END__
