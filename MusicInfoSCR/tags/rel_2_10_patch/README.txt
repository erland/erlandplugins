1. LICENSE
==========
Copyright (C) 2006 Erland Isaksson (erland_i@hotmail.com)

This code is a modification of the original code provided by:
MusicInfoSCR.pm by mh jan 2005, parts by kdf Dec 2003, fcm4711 Oct 2005
SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.

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
- *.patch (A patch to apply these changes to the original code)

4. INSTALLATION
===============
Unzip and copy MusicInfoSCR.pm to the Plugins directory in the Slimserver
installation.

5. USAGE
========
See http://www.herger.net/slim/ for information about normal usage of the
MusicInfoSCR plugin.

Developers:
To add custom items the following methods needs to be implemented in
your own plugin. The text shown in custom items will be replaced at
the following times:
- Screensaver activation
- Track change

getMusicInfoSCRCustomItems
- This method should return a map with all custom items implemented by
  your plugin. 

  Example code from the TrackStat plugin:
  my %musicInfoSCRItems = (
    'TRACKSTAT_RATING_DYNAMIC' => 'TRACKSTAT_RATING_DYNAMIC',
    'TRACKSTAT_RATING_NUMBER' => 'TRACKSTAT_RATING_NUMBER');
  sub getMusicInfoSCRCustomItems() 
  {
    return \%musicInfoSCRItems;
  }

getMusicInfoSCRCustomItem
- This methods will be called when one of your custom items is found. It
  is the responsiblity of your plugin to replace your custom items with 
  real information.

  Example code from the TrackStat plugin:
  sub getMusicInfoSCRCustomItem()
  {
    my $client = shift;
    my $formattedString  = shift;

    if ($formattedString =~ /TRACKSTAT_RATING_DYNAMIC/) {
      my $playStatus = getTrackInfo($client);
      my $string = ($playStatus->currentSongRating()?' *' x $playStatus->currentSongRating():'');
      $formattedString =~ s/TRACKSTAT_RATING_DYNAMIC/$string/g;
    }
    if ($formattedString =~ /TRACKSTAT_RATING_NUMBER/) {
      my $playStatus = getTrackInfo($client);
      my $string = ($playStatus->currentSongRating()?$playStatus->currentSongRating():'');
      $formattedString =~ s/TRACKSTAT_RATING_NUMBER/$string/g;
    }
    return $formattedString;
  }

