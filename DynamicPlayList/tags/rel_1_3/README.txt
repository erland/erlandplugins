1. LICENSE
==========
Copyright (C) 2006 Erland Isaksson (erland_i@hotmail.com)

Portions of code derived from the Random Mix plugin:
Originally written by Kevin Deane-Freeman (slim-mail (A_t) deane-freeman.com).
New world order by Dan Sully - <dan | at | slimdevices.com>
Fairly substantial rewrite by Max Spicer

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

2. PREREQUISITES
================
- A slimserver 6.2.* or 6.5 installed and configured

3. FILES
========
This archive should contain the following files:
- readme.txt (this file)
- license.txt (the license)
- *.pm (The application itself)

4. INSTALLATION
===============
Unzip to the Plugins directory in the Slimserver installation.

5. USAGE
========
This plugin makes it possible manage all dynamic playlists in the same menu on the
Squeezebox and in the same list in the slimserver web interface. The plugin today implements
Random Mix playlists connection and a connection to saved playlists so they are
showed among the dynamic playlists.

6. PLUGIN DEVELOPERS
====================
You can implement your own dynamic playlists by implementing the methods described below
in your plugin. The plugin must be enabled for it to be detected by DynamicPlaylist plugin.

# Returns a map with a an entry for each playlist, 'myplugin_mycoolplaylist' in the sample below
# The playlist entry must contain a 'name' but it can also contain additional items which you
# need later when tracks are requested for the playlist.
# The 'url' parameter is optional and will be a link in the web interface which the user
# can click on to get to the settings for the playlist
# This method will be called by the DynamicPlaylist plugin whenever the playlists shall be shown
sub getDynamicPlayLists {
	my ($client) = @_;

	my %result = ();
	my %playlist = (
		'name' => 'My Cool Playlist',
		'url' => 'plugins/MyCoolPlugin/index.html'
	);
	$result{'myplugin_mycoolplaylist'} = \%playlist;
	return \%result;
}

# Returns the next tracks, this method will be called by DynamicPlaylist plugin when more tracks are needed
# playlist = This is the same map for the playlist as you returned in the getDynamicPlayLists method
# limit = The number of tracks that should be returned
# offset = The offset of the track from the beginning of the playlist
sub getNextDynamicPlayListTracks {
	my ($client,$playlist,$limit,$offset) = @_;

	my @result = ();
	my $items = $ds->find({
		'field'  => 'track',
		'find'   => {'audio' => 1},
		'sortBy' => 'random',
		'limit'  => $limit,
		'cache'  => 0,
	});

	for my $track (@$items) {
		push @result, $track;
	}
	return \@result;
}

7. CLI DEVELOPERS
=================
DynamicPlaylist plugin offers a CLI interfase with the following commands.
If you want the answers to look the same in both slimserver 6.5 and 6.2 you will
need to use the version of the commands with a MAC address of the SqueezeBox first.

Get all enabled playlists
-------------------------
dynamicplaylist playlists
00:04:20:06:22:b3 dynamicplaylist playlists

Get both enabled and disabled playlists
---------------------------------------
dynamicplaylist playlists all
00:04:20:06:22:b3 dynamicplaylist playlists all

Start playing playlist dynamicplaylist_random_track
---------------------------------------------------
00:04:20:06:22:b3 dynamicplaylist playlist play dynamicplaylist_random_track

Add songs from playlist dynamicplaylist_random_track to currently playing playlist
----------------------------------------------------------------------------------
00:04:20:06:22:b3 dynamicplaylist playlist add dynamicplaylist_random_track

Stop adding songs to currently playing playlist
----------------------------------------------------------------------------------
00:04:20:06:22:b3 dynamicplaylist playlist stop
