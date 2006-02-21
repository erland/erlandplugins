1. LICENSE
==========
Copyright (C) 2006 Erland Isaksson (erland_i@hotmail.com)

Portions of code derived from the iTunes plugin included in slimserver
Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.

Portions of code derived from the iTunesUpdate 1.5 plugin
Copyright (c) 2004-2006 James Craig (james.craig@london.com)

Portions of code derived from the SlimScrobbler plugin
Copyright (c) 2004 Stewart Loving-Gibbard (sloving-gibbard@uswest.net)

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
- A slimserver 6.2.* installed and configured

3. FILES
========
This archive should contain the following files:
- readme.txt (this file)
- license.txt (the license)
- *.pm (The application itself)

4. INSTALLATION
===============
Unzip to the Plugins directory in the Slimserver
installation.

5. USAGE
========
This plugin for slimserver makes it possible to rate your songs and also handles statistic data about
play counts and last played time. The ratings and statistic data is stored in a separate database table
which will not be cleared during a complete rescan of the music library. Ratings and statistic data can also
be imported from an iTunes Music Library xml-file. You can make backup/restore of your ratings and statistic data
to a separate xml file to make it easier to backup the information to other storages. To be able to view the ratings
when listening to music it is recomended to install the latest version of MusicInfoSCR plugin provided at http://www.herger.net/slim-plugins/, 
you will need version 2.20 or later. It is also possible to view the ratings as a title format as described separately
below, note that if you choose to view title formats in MusicInfoSCR they will currently only be updated when the track changes. 
This means that if you change the rating it will not be possible to see the new rating until next time the track is played. 
An advantage of using title format is that you can view the rating in the slimserver web interface together with the track name
in track listings.

The play count and last playing time algoritm is based on the same logic in iTunes Update plugin, this means that play count
will not be increased if you just listen on the first secondes of a track, you have to listen to most of the track to update
play counts and last played time.

To rate a track just press the numbers 1-5 on the remote, you will see a message on the Squeezebox display which confirms
that the rating has been set.

The TrackStat plugin will add a number of items to the MusicInfoSCR screensaver plugin which makes it possible to show
the rating information for the current playing track directly on the screen on the Squeezebox. This requires the 2.20 or
later version of the MusicInfoSCR plugin provided at http://www.herger.net/slim-plugins/.

The ratings, play count and last play time information will be stored in a track_statistics table, see sql files in SQL
directory for exact layout of the table. If running slimserver under mysql, the database user configured for slimserver
have privileges to create the table it will be created automatically at startup. If the user does not have privileges to 
create the table it must be created manually with the SQL scripts provided in the SQL directory toghether with the plugin.

The plugin supports import of ratings, play counts and last play time from iTunes. To do this you will have to configure
a number of parameters for the TrackStat plugin in the plugins section of the slimserver settings web interface.

You can take a backup of the ratings, play counts, last play time information to an xml-file using the buttons provided in 
the plugins section of the slimserver settings web interface. This information can later be restored which makes this a suitable
way to store backups of the information on an external media.

At last you may also want to look at the SQLPlayList plugin provided at http://erland.homeip.net/download which makes it possible
to create smart playlists using SQL queries. This can be used toghether with the TrackStat plugin to setup playlists such as:
- All 4-5 rated songs
- All 4-5 rated songs in genre pop or rock
- All not rated songs

If you want to use title format to view the rating in web interface, MusicInfoSCR or Now Playing screen do as below, note that if you use
MusicInfoSCR it will work better if you use the builtin custom item support in MusicInfoSCR to show the rating instead of title formats. 
It is also possible to combine both title formats and MusicInfoSCR custom items.

1. Add a title format string in the web interface for server settings section for formatting, the strings can contain several 
   items and the TrackStat plugin will replace the following with rating information:
   TRACKSTATRATINGNUMBER
   TRACKSTATRATINGSTATIC
   TRACKSTATRATINGDYNAMIC
   A number of title formats is automatically added by the plugin so if you what to use one of them you can jump to the next step.
   Note that the current version of slimserver 6.2.* only supports these title formats toghether with other information if they are
   specified within () or {}, for example "TRACKNUM. TITLE (TRACKSTATRATINGDYNAMIC)". In slimserver 6.5 it also works to specify them
   without () such as: "TRACKNUM. TITLE TRACKSTATRATINGDYNAMIC"

2. If you want to show the ratings on the Now Playing screen goto the web interface client settings section for title format and select
   the title formats you registered in a previous step.

3. If you want to show the ratings on the MusicInfoSCR goto the web interface client settings section for plugins and select the title
   formats you registered in a previous step. Observe that there will also be the custom items added automatically available in the
   settings for MusicInfoSCR. The custom items for rating information contains the following text:
   TRACKSTAT_RATING_NUMBER
   TRACKSTAT_RATING_STATIC
   TRACKSTAT_RATING_DYNAMIC

4. If you want to show the ratings in the track listings in the web user interface goto the server settings section for formatting and
   select one of the title formats that contains rating information.
