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

The easiest way to creat new menus is to use the "Edit menus/Create new menu" link
in the web interface. You will be able to select type of menu and enter a few parameters for
the new menu.

You can also define a new menu by creating a *.cb.xml file with the contents
as described below. This file will be found by the CustomBrowse
plugin if you put it in the directory you have specified
in the settings page for the CustomBrowse plugin in the web
interface. The easiest way to learn how to define a custom menu
is probably to look at the samples that is delived with the plugin and
are stored in the CustomBrowse/Menus directory. Some definitions and
samples of the format can be found below.
It is also possible to create globaly available mixes accessible by holding play down on on
an item. These has to be put in a *.cb.mix.xml file and stored in the same directory as
the menu definitions. You can look at the CustomBrowse/Mixes directory in the installed
plugin to see some samples. Mixes can also be defined in a specific menu as described below
for the "mix" element.

The following example shows how an "Albums" menu could be
defined.
=========================================================================================
<?xml version="1.0" encoding="utf-8"?>
<custombrowse>
        <menu>
                <menuname>Albums</menuname>
                <menu>
                        <id>album</id>
			<menuname>Songs</menuname>
                        <itemtype>album</itemtype>
			<itemformat>album</itemformat>
                        <menutype>sql</menutype>
			<menulinks>alpha</menulinks>
			<option>
				<id>bytitle</id>
				<name>Sort by title</name>
				<menulinks>alpha</menulinks>
				<keyword name="orderby" value="albums.titlesort asc"/>
			</option>
			<option>
				<id>byyear</id>
				<name>Sort by year</name>
				<menulinks>number</menulinks>
				<keyword name="orderby" value="albums.year desc, albums.titlesort asc"/>
			</option>
                        <menudata>
                                select albums.id,albums.title,left(albums.titlesort,1) from tracks,albums
                                where
                                        tracks.audio=1 and
                                        albums.id=tracks.album
                                group by albums.id
                                order by {orderby}
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
     The id element is mandatory for all menus besides the top menu. The top menu will
     allways get id equal to the filename.

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
             only "track" and "album" is supported. The itemformat element is optional.
             If item format "album" is specified this will enable the gallery view button
             in the web interface.

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
            Currently the only allowed value is "alpha" and "number". Not specifying this element
            is the same as setting it to "number"
            
            number = Standard positional navigation using numeric buttons on SqueezeBox and
                     page number links in web interface.

            alpha = If this element exist for a menytype=sql the SQL statement must contain a 
                    third column that contains the navigation letter for each row. The menulinks 
                    element also affects the SqueezeBox navigation in the way that this will
                    enable navigation by letters using numeric buttons.

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
                         
keyword = Defines a keyword that can be used in SQL statements and will be replaced before
          actually executing the SQL. Keywords can be defined on all levels in the menu
          structure. If the same keyword exist both in a the current menu and the parent
          menu the value of the keyword in the current menu will be used. You can also define
          keywords in option element and then this will override keywords defined directly in
          the menu element or in one of the parent menus.
          The keyword element requires two attributes:
          
          name = The name of the keyword, this name should be used when using the keyword
          value = The value of the keyword, the keyword will be replaced by this text if it is
                  used in a SQL statement.

option = Makes a drop list available in the web user interface where its possible to select one
         of the options defined for the menu. Typically the option element is used to make it
         possible to select different sort order for the menu items. The option element is
         optional and is not required if you don't want any drop list in the user interface.
         The option element must have the following sub elements:
         
         id = A unique id of the option
         name = The text that should be displayed to the user
         
         The option can also optionally contain the following elements which then will override
         the same elements directly inside menu.
 
         menulinks
         menudata
         keyword

playtype = The playtype element indicates what should happen if you press play on an item
           in the menu. The playtype element is optional and if not specified the logic will
           be:
           1. Play the selected item if its itemtype is supported
           2. Play all items in the sub menu if the itemtype is not supported

           The supported values of the playtype element are:
           all    = Play all items in the current menu instead of just playing the selected, this
                    is useful for makeing play on a track play all tracks on that album.
           sql    = Play the tracks with the ids returned from the SQL statement in the playdata
                    element.
           none   = Nothing shall happend when play/add is pressed

playdata = Contains custom data for the playtype element. This element is optional and is only
           required for some of the different play types.

           playtype	playdata
           --------     ---------------------------------------------------------------------
           all          Not used

           sql          A SQL statement that returns the track identifiers of the tracks that
                        should be played. The SQL statement should return two columns the track
                        identifier and the track title.

mix = A main element for a mix definition, can contain sub elemetnts: mixtype, mixdata, mixcategory, 
      mixchecktype, mixcheckdata

mixtype = Type of mix, allowed values:

          allforcategory = All globaly defined mixes for the category specified in mixdata shall be included here 
          sql	         = Mix is defined by a SQL statement
          mode           = Mix is defined by a mode
          function       = Mix is defined by a function

mixcategory = Only valid for globaly defined mixes.
              Defines the category of the mix, menu items without any local defined mix elements will include
              the categories with the value of itemtype. This also means that its preferable if the
              mixcategory element is set to one of:

              album
              artist
              playlist
              year
              track
              genre

mixdata = Contains custom data for the mixtype element. The allowed values are:
          
          mixtype          mixdata
          -------          -------
          allforcategory   The name of the category to include global mixes for

          sql              An SQL statement returning one column with the id of the object to include in
                           the mix

          mode             The name of the mode to enter when mix is launched

          function         The complete name of the function to execute when the mix is launched.
                           The following parameters will be sent to the function:
                           $client - The client from where the mix was started
                           $item - The object which were selected when the mix was started
                           $addOnly - 1 if add was pressed, else 0

mixchecktype = Type of method to check if mix should be available, can be one of:
               
               sql      = An SQL statement is execuced and if it returns any rows the mix is enabled. The SQL
                          is defined by mixcheckdata element or by mixdata if mixcheckdata does not exist.
               function = A function is executed and if it returns non 0 the mix is enabled

mixcheckdata = Contains custom data for the mixchecktype element. The allowed values are:
         
               mixchecktype     mixcheckdata
               ------------     ------------
               sql              An SQL statement returning a single column, it it returns one or several rows
                                the mix is enabled. 

               function         The complete name of the function to execute, if it returns non 0 the mix is enabled.
                                The following parameters will be sent to the function:
                                $class - The class in which the function exists
                                $item - The object which were selected when the mix requested

Keywords
--------
Currently the following keywords are supported in those element that supports keyword replacment.
A keyword will be replaced with the real value before its used.

{custombrowse.audiodir} = The music directory
{custombrowse.audiodirurl} = The url of the music directory
{property.xxx} = The value of the xxx configuration parameter, slimserver.pref for exact name.
{xxx} The value of the keyword with name xxx or the id of the selected item in the menu with id xxx

Keywords can also be defined as a keyword element in the xml file, this is useful for example
to change keyword values in different option element, but might also be usefull if you want to
define some part of a SQL statement in one place instead of repeating it in every statement.

