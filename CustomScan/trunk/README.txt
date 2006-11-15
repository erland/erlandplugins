1. LICENSE
==========
Copyright (C) 2006 Erland Isaksson (erland_i@hotmail.com)

The LastFM scanning module uses the webservices from audioscrobbler.
Please respect audioscrobbler terms of service, the content of the 
feeds are licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License

The Amazon scanning module uses the webservies from amazon.com
Please respect amazon.com terms of service, the usage of the 
feeds are free but restricted to the Amazon Web Services Licensing Agreement.

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
- A slimserver 6.5.* or later installed and configured

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
This plugin makes it possible to get more information about artist, albums, tracks than available from the standard slimserver scan.
The purpose of the plugin is provide a framework for scanning modules that retrieves additional information from various places, it
includes the following scanning modules by default.

CustomTag = A scanning module that reads additional tags from the music files that are not normally stored in the slimserver database.
            The tags read can be configured as a "customtags" property in the Custom Scan settings page in the web interface.
            By default read tags will be splitted in same way as genres in standard slimserver, if you don't want the tag to be splitted you can also
            add it to a "singlecustomtags" property in the Custom Scan settings page in the web interface.

LastFM = A scanning module that reads a number of different information from the LastFM database. Please note that the information read
         is only free to use for non commercial usage, see the licence for more information.
         The module currently reads the following additional information for all artists:
         - LastFM tags for the artist (Percent limit of read tags can be configured with a lastfmtagspercent property)
         - Picture url for the artist
         - Similar artists to the scanned artist (Percent limit of similarity of read artists can be configured with a lastfmsimilarartistpercent property)

Amazon = A scanning module that read a number of different information from the amazon.com database related to albums. 
                 Please note that the information read is free but the web service usage is restricted according to Amazon Web Services Licensing Agreement.
                 The module currently read the following additional information for all albums:
                 - Average customer review
                 - Subjects/genres for the album
                 - ASIN (unique amazon id for the album)
                 The Amazon module can also optionally set the ratings in slimserver/TrackStat, this functionallity is disabled by default but you can
                 enable it by setting the "writeamazonrating" property to 1 in the Custom Scan settings page in the web interface.
                 The Amazon module requires you to register for a access key to use Amazon web services, you can do this by go to amazon.com and
                 select the "Amazon Web Services" link currently available in the bottom left menu under "Amazon Services". You then enter the
                 Access Key Id in the "amazonaccesskey" property in the Custom Scan settings page. For example "amazonaccesskey=0AAAAAAABBBBBBCCCC2"

NOTE!!!
The Amazon and LastFM modules are quite slow, the reason for this is that Amazon and LastFM restricts the number of calls per second towards 
their services in the licenses. Please respect these licensing rules. This also results in that slimserver will perform quite bad during scanning when
these scanning modules are active. The information will only be scanned once for each artist/album, so the next time it will only scan new artists/albums
and will be a lot fast due to this. Approximately scanning time for these modules are:
- LastFM: 1-2 seconds per artist in your library
- Amazon: 1-2 seconds per album in your library

The information read by the above modules is just stored in a separate table in the database and cannot be viewed in standard slimserver.
If you install the SQLPlayList plugin you can use the read information to create smart playlists.
If you install the Custom Browse plugin you can use the read information to create browse menus.

There are a number of different settings available in the Custom Scan settings page in the web interface to turn on/off automatic scanning
after a standard slimserver rescan. Also, please note that the LastFM module will make slimserver work slowly during rescan due to licensing
rules on LastFM that don't allow many requests in a short time.

The scanned data are stored in the following three tables in the database
customscan_contributor_attributes
customscan_album_attributes
customscan_track_attributes

See the next section for more information about how to write your own scanning module. 

In the Custom Scan section of the "Server Settings"/"Plugins" in the web interface it is possible to choose which custom information that should be
available as title formats. It is only possible to make custom track information available as title formats. You use a custom title format as follows:
1. Goto "Server Settings/"Plugins" and goto the "Title Formats" parameter in the section for the "Custom Scan" plugin.
2. Select the title format you like to use, note the exact text
3. Goto "Server Settings"/"Formatting"/"Title Format"
4. Add the text from step 2 in one of the existing title formats or at the last line as a completely new title format. You can combine several title format in
    a long string, for example if you would like a track to be displayed as: "1. A nice track (Erland)" where Erland is the OWNER tag scanned with Custom Scan
    you would enter:
    TRACKNUM. TITLE (CUSTOMSCAN_CUSTOMTAG_OWNER)
5. To actually start using the the title format you:
    For Web Interface listings: Goto "Server Settings"/"Formatting"/"Title Format" and select the title format you want to use by selecting the radio button.
    For SqueezeBox Display: Goto "Player Settings for xxx"/"Title Format" and select the title format you want to use bt selecting the title format and 
                                           selecting the radio button between it

6. PLUGIN DEVELOPERS
====================
A scanning module is implemented in a separate plugin by implemeting a getCustomScanFunctions function. You can see the included LastFM and
CustomTag scanning modules for more detailed samples about the implementation of this function. Basically it shall return a map with the 
following keys:

id = A unique identifier of the scanning module, will be used as module when storing the information in the database
name = A user friendly name of the scanning module that shall be shown to the user
scanArtist = A pointer to the function that shall be called when scanning an artist, if not specified artists will not be scanned by this module.
scanAlbum = A pointer to the function that shall be called when scanning an album, if not specified albums will not be scanned by this module.
scanTrack = A pointer to the function that shall be called when scanning a track, if not specified tracks will not be scanned by this module.
alwaysRescanArtist = If set to 1, old artist data will always be deleted before scanning. If not specified only artists with no previous data will be scanned.
alwaysRescanAlbum = If set to 1, old album data will always be deleted before scanning. If not specified only albums with no previous data will be scanned.
alwaysRescanTrack = If set to 1, old track data will always be deleted before scanning. If not specified only tracks with no previous data will be scanned.

scanArtist function will get a contributor object as in-parameter when called, it will be called once for each artist in the slimserver database.
scanAlbum function will get an album object as in-parameter when called, it will be called once for each album in the slimserver database.
scanTrack function will get an track object as in-parameter when called, it will be called once for each track in the slimserver database.

If you want to have some simple settings for your scanning module, you can either implement a web interface in your plugin for setting it or you can
choose to let the user specify it as a Custom Scan property in the Custom Scan settings page. You use the Plugins::CustomScan::Plugin::getCustomScanProperty function 
to retreive a Custom Scan property from your scanning module.

See the included scanning modules in the Modules directory for sample implementations of the different functions.


