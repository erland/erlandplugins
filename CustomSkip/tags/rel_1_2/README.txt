1. LICENSE
==========
Copyright (C) 2006 Erland Isaksson (erland_i@hotmail.com)

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
- A slimserver 6.5 installed and configured

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
This plugin makes it possible put a filter on all playlists, it works best together with the
Dynamic Playlist plugin but also works for other type of playlists. You are able to define a filter
and tracks matching the filter will not be played. By default the filtering is only activated for
Dynamic Playlist plugin playlists, goto the settings page if you want to activate the filtering
for other type of playlists.

6. PLUGIN DEVELOPERS
====================
You can implement your own filter types by implementing the methods described below
in your plugin. The plugin must be enabled for it to be detected by the Custom Skip plugin.

getCustomSkipFilterTypes:
-------------------------
# Returns an array with a an entry for each filter, 'album' in the sample below
# The filter entry must contain a 'name' but it can also contain additional items which you
# need later when tracks are filtered through the filter.
# This method will be called by the Custom Skip plugin when a list of existing filters is needed
# See the methods in the Plugin.pm file for a sample

checkCustomSkipFilterType:
--------------------------
# Returns 1 if the track shall be skipped else 0, this method will be called by Custom Skip plugin
# when a track shall be checked against a filter
# filter = This is the same map for the filter as you returned in the getCustomFilters method
# track = The track object of the track that shall be checked agains the filter
# See the method in the Plugin.pm file for a sample

