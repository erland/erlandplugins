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
- A slimserver 6.2.* or later installed and configured

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
you will need version 2.30 or later. To view the ratings you need to select one of the title formats that contains rating information.
For the Now Playing screen you do this in the player settings in the web interface in the title format section. For MusicInfoSCR
you just select one of the formats containing rating information in the configuration page for MusicInfoSCR.

Note! 
If you have been using the custom item support in MusicInfoSCR 2.20 you will need to change this to one of the standard
title formats since custom items are no longer supported in MusicInfoSCR 2.30 and later. If you have used the custom item 
support you may need to goto the player settings and click the Change button for the selected title format and to the MusicInfoSCR 
settings and click the Change button.

The play count and last playing time algoritm is based on the same logic in iTunes Update plugin, this means that play count
will not be increased if you just listen on the first secondes of a track, you have to listen to most of the track to update
play counts and last played time.

To rate a track just press the numbers 1-5 on the remote, you will see a message on the Squeezebox display which confirms
that the rating has been set. 

The TrackStat plugin will add a number of title formats which makes it possible to show the rating information for the current 
playing track directly on the screen on the Squeezebox in either Now Playing or MusicInfoSCR. Version 2.30 or
later of the MusicInfoSCR plugin provided at http://www.herger.net/slim-plugins/ is required if you want to use MusicInfoSCR.

The ratings, play count and last play time information will be stored in a track_statistics table, see sql files in SQL
directory for exact layout of the table. If running slimserver under mysql, the database user configured for slimserver
have privileges to create the table it will be created automatically at startup. If the user does not have privileges to 
create the table it must be created manually with the SQL scripts provided in the SQL directory toghether with the plugin.

The plugin supports import of ratings, play counts and last play time from iTunes. To do this you will have to configure
a number of parameters for the TrackStat plugin in the plugins section of the slimserver settings web interface.

You can take a backup of the ratings, play counts, last play time information to an xml-file using the buttons provided in 
the plugins section of the slimserver settings web interface. This information can later be restored which makes this a suitable
way to store backups of the information on an external media.

If you want to make sure your statistic data survives filename changes you have to make sure your files contains musicbrainz id tags.

At last you may also want to look at the SQLPlayList plugin provided at http://erland.homeip.net/download which makes it possible
to create smart playlists using SQL queries. This can be used toghether with the TrackStat plugin to setup playlists such as:
- All 4-5 rated songs
- All 4-5 rated songs in genre pop or rock
- All not rated songs

If you want to view the rating in web interface, MusicInfoSCR or Now Playing screen do as below. 

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
   formats you registered in a previous step. 

4. If you want to show the ratings in the track listings in the web user interface goto the server settings section for formatting and
   select one of the title formats that contains rating information.

6. PLUGIN DEVELOPERS
====================
TrackStat has a plugin interface for other plugin developers making it possible to attach your plugin to TrackStat so
it will get information about changed ratings, play counts and last played time. To do this you will need to implement
one or both of the following methods in your plugin. The method implementations below is just sample methods to show the
usage.


# This method will be called each time a rating value in TrackStat is changed by the user
# url = The url of the track on which the rating is changed
# rating = The new rating, a value between 0 - 100
sub setTrackStatRating {
	my ($client, $url, $rating) = @_;

	#
	# Call your own methods and do some interesting stuff here
	#
}


# This method will be called at the end of each played song
# url = The url of the track
# 
sub setTrackStatStatistic {
	my ($client,$url,$statistic)=@_;
	
	my $playCount = $statistic->{'playCount'};
	my $lastPlayed = $statistic->{'lastPlayed'};	
	my $musicbrainz_id = $statistic->{'mbId'};
	my $rating = $statistic->{'rating'};

	#
	# Call your own methods and do some interesting stuff here
	#
}


