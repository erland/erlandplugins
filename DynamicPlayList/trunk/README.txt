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
connection to saved playlists so they are showed among the dynamic playlists. The
TrackStat plugin, RandomPlayList plugin and SQLPlayList plugin adds its own playlists
so they are available among the dynamic playlists.
In the SqueezeBox interface dynamic playlists are available in the "Dynamic Playlists" menu, but
you can also reach playlists which requests parameters from the user by holding down play button
on remote for a while on an item in one of the browse menues. There is also a PL button in the
web ui browse pages that does the same.

6. PLUGIN DEVELOPERS
====================
You can implement your own dynamic playlists by implementing the methods described below
in your plugin. The plugin must be enabled for it to be detected by DynamicPlaylist plugin.

# Returns a map with a an entry for each playlist, 'myplugin_mycoolplaylist' in the sample below
# The playlist entry must contain a 'name' but it can also contain additional items which you
# need later when tracks are requested for the playlist.
# The 'url' parameter is optional and will be a link in the web interface which the user
# can click on to get to the settings for the playlist
# The 'groups' parameter is optional and will but the playlist in the specified groups, in the example
# below the playlist will be available in: "Albums/Cool" and "Cool"
# The 'parameters' parameter is optional and will result in that the user is forced to select values
# for the specified parameters before the playlist is acutally played. Playlists with parameters will
# currently not be available in the CLI interface. If the first parameter is of type album, artist, playlist
# genre or year this will also result in a PL button in the browse pages, clicking on an artist in the
# browse page will set that artist id as the first parameter. More samples for parameter definitions can
# be found as a number of template playlists possible to create in the SQLPlayList plugin web ui.
# This method will be called by the DynamicPlaylist plugin whenever the playlists shall be shown
sub getDynamicPlayLists {
	my ($client) = @_;

	my %result = ();
        my %playlist = (
                'name' => 'My Cool Playlist',
                'url' => 'plugins/MyCoolPlugin/index.html',
                'groups' => [['Albums','Cool']['Cool']]
        );

	# *** Starting optional part for requesting parameters from the user ***
	my %parameter1 = (
		'id' => 1, # A number between 1-10
		'type' => 'album', # Can be one of: album, artist, genre, year, playlist, list, custom
		'name' => 'Choose album', # Text that should be shown to the user when asking for parameter
		'definition' => '' # Only valid if type is list or custom
	);	                   # If type = list the following will show the user Value1 and Value2 and the value
		                   # sent back to your plugin will be 1 or 2
        	                   # 1:Value1,2:Value
		                   # If type = custom the definition is a sql statement with two columns id and name
		                   # The following will show the user a list of all artist starting with "A"
		                   # select id,name from contributors where name like 'A%'
		                   # If type = custom the sql can also contain the text 'PlaylistParameter1' and this
		                   # will be replaced with the value of the first parameter
	                           
        my %parameter2 = (
                'id' => 2, # A number between 1-10
                'type' => 'custom', # Can be one of: album, artist, genre, year, playlist, list, custom
                'name' => 'Choose artist starting with A', # Text that should be shown to the user when asking for parameter
                'definition' => 'select id,name from artist where name like '\'A%\'' #See description above
        );
	
	my %parameters = (
		1 => \%parameter1, # The key 1 must match the 'id' value in the parameter
		2 => \%parameter2  # The key 2 must match the 'id' value in the parameter
	);
	$playlist{'parameters'} = \%parametrs;
	# *** Ending optional part for requesting parameters from the user ***

	my %playlist = (
		'name' => 'My Cool Playlist',
		'url' => 'plugins/MyCoolPlugin/index.html',
		'groups' => [['Albums','Cool']['Cool']]
	);
	$result{'myplugin_mycoolplaylist'} = \%playlist;
	return \%result;
}

# Returns the next tracks, this method will be called by DynamicPlaylist plugin when more tracks are needed
# playlist = This is the same map for the playlist as you returned in the getDynamicPlayLists method
# limit = The number of tracks that should be returned
# offset = The offset of the track from the beginning of the playlist
# parameters = The parameters together with the values the user has entered (The parameters part of the sample 
#              below is just to show how to read the parameters)
sub getNextDynamicPlayListTracks {
	my ($client,$playlist,$limit,$offset,$parameters) = @_;

	my @result = ();

	# *** Starting optional part for reading values for requested parameter values
	if($parameters->{1}->{'value'} eq '1') {
		# Do some stuff if first parameter is 1, this is just a stupid example that doesn't do anything useful
	}
	# *** Ending optional part for readin values for requested parameter values

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
Playlists which requests parameters from the user will currently not be available in the CLI
commands that read available playlists, the reason is simply that there is currently no way
to specify the parameter values in the CLI interface.

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
