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
- A slimserver 6.2.*, 6.3.* or 6.5 installed and configured

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
This plugin makes it possible to create custom browse menus.

You define a new playlist by creating a *.cb.xml file with the contents
as described below. This file will be found by the CustomBrowse
plugin if you put it in the directory you have specified
in the settings page for the CustomBrowse plugin in the web
interface. The easiest way to learn how to define a custom menu
is probably to look at the samples that is delived with the plugin and
are stored in the CustomBrowse/Playlists directory. Some definitions and
samples of the format can be found below.

The following example shows how an "Albums" menu could be
defined.
=========================================================================================
<?xml version="1.0" encoding="utf-8"?>
<custombrowse>
        <menu>
                <id>albums</id>
                <menuname>Albums</menuname>
                <menu>
                        <id>album</id>
			<menuname>Songs</menuname>
                        <itemtype>album</itemtype>
                        <menutype>sql</menutype>
			<menulinks>alpha</menulinks>
                        <menudata>
                                select albums.id,albums.title,left(albums.titlesort,1) from tracks,albums
                                where
                                        tracks.audio=1 and
                                        albums.id=tracks.album
                                group by albums.id
                                order by albums.titlesort asc
                        </menudata>
                        <menu>
                                <id>track</id>
                                <itemtype>track</itemtype>
                                <itemformat>track</itemformat>
                                <menutype>sql</menutype>
                                <menudata>
                                        select tracks.id,tracks.title from tracks
                                        where
                                                tracks.audio=1 and
                                                tracks.album={album}
                                        order by tracks.tracknum,tracks.titlesort asc
                                </menudata>
                                <menu>
                                        <id>trackdetails</id>
                                        <menutype>trackdetails</menutype>
                                        <menudata>track</menudata>
                                </menu>
                        </menu>
                </menu>
        </menu>
</custombrowse>
=======================================================================================

The principle for the different elements are as follows:

menu = Defines a new sub menu

id = Identification for a specific menu, must be uniqe on the same level.
     The id element is mandatory for all menus.

menuname = Title of the menu, this element is required on the top menu level, its
           never used for dynamic menus in the player interface. In the web interface
           this value is used for the navigation links at the top. The menuname element 
           is mandatory for static menus with no menutype element.

itemtype = Type of items in the menu, should only be available if the menu items
           represents a single unique database object. The following values are allowed:
           album, artist, genre, year, playlist, track
           Only elements with one of these item types can be played with the play button.
           The itemtype element is optional, its basically used to indicate if the item
           should be possible to play/add or not. Note that its important that the item
           really represent the item type set.

itemformat = The formatting type that should be applied to the menu item. Currently 
             only "track" is supported. The itemformat element is optional.

menutype = Type of menu. This element defines how items should be retrieved for dynamic
           menus. The menutype element is mandatory for dynamic menus, its currently not
           used for static menus. The following values are currently supported.

           Value         Description
           ------------  -----------------------------------------------------------------
           sql           Retrieves menu items by executing a SQL statement. The SQL 
                         statement is defined in the menudata element.

           trackdetails  Enter track details mode for the selected track, the menudata
                         element contains the id of the menu where the track identifier
                         can be found.

           mode          Enters this mode. Modes are typically implemented by all plugins
                         and represent their plugin menu. But modes are also available for
                         a number of internal slimserver menus.

           folder        Lists all sub directories as a menu item, the parent directory
                         is defined in the menudata element.

menulinks = Defines the type of navigation links that should be available in the web interface.
            Currently the only allowed value is "alpha". If this element exist for a menytype=sql
            the SQL statement must contain a third column that contains the navigation letter
            for each row.

menuurl = Defines the url that shall be used as link in web interface for menus with
          menutype=mode. 

menudata = Defines parameters needed for retrieval of dynamic menu data. This element
           contains different information dependent on the value of the menutype element. The 
           menudata element is mandatory for dynamic menus, its currently not used for static
           menus.
           
           menytype      menudata
           --------      -------------------------------------------------------------------
           sql           One or several SQL statements which should return two or tree columns. 
                         The first column will be used as id internally and the second column
                         is the text that is displayed. The third column is optional and is only
                         required if menulinks=alpha has been defined. The first column should 
                         typically be the id column in the table, for example tracks.id. Text within
                         {} will be replaced by looking up the selected item in the parent
                         menu with the id specified within {}. Keywords will be replaced in
                         this field. The third column is optional and when it exists it shall
                         contain the letter which the item shall be linked to, typically the first
                         letter in the sort column in the database.

           trackdetails  The id of the parent menu that contains the track that should be
                         displayed. 

           mode          The name of the mode that should be entered. For plugins the mode
                         are typically: "PLUGIN.xxx" where xxx is the name of the *.pm file
                         which contains the plugin code.
                         For example TrackStat mode is:
                         PLUGIN.TrackStat::Plugin
                         And DynamicPlayList mode is:
                         PLUGIN.DynamicPlayList
           
           folder        The directory where sub folders shall be read. This value can
                         also contain keywords which will be replaced. 
                         
Keywords
--------
Currently the following keywords are supported in those element that supports keyword replacment.
A keyword will be replaced with the real value before its used.

{custombrowse.audiodir} = The music directory
{custombrowse.audiodirurl} = The url of the music directory
{property.xxx} = The value of the xxx configuration parameter, slimserver.pref for exact name.
