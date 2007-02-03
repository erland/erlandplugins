# 				DynamicPlayList plugin 
#
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
#
#    Portions of code derived from the Random Mix plugin:
#    Originally written by Kevin Deane-Freeman (slim-mail (A_t) deane-freeman.com).
#    New world order by Dan Sully - <dan | at | slimdevices.com>
#    Fairly substantial rewrite by Max Spicer

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

package Plugins::DynamicPlayList::Plugin;

use strict;

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use File::Spec::Functions qw(:ALL);
use Class::Struct;
use DBI qw(:sql_types);
use FindBin qw($Bin);
use Scalar::Util qw(blessed);
use Plugins::DynamicPlayList::Template::Reader;

my $PLUGINVERSION = '1.12';

my $driver;
my %stopcommands = ();
# Information on each clients dynamicplaylist
my %mixInfo      = ();
my $htmlTemplate = 'plugins/DynamicPlayList/dynamicplaylist_list.html';
my $ds = getCurrentDS();
my $filters = undef;
my $playLists = undef;
my $playListTypes = undef;
my $playListItems = undef;

my %plugins = ();
my %filterPlugins = ();
my %disablePlaylist = (
	'dynamicplaylistid' => 'disable', 
	'name' => ''
);
my %disable = (
	'playlist' => \%disablePlaylist
);
	
sub getDisplayName {
	return 'PLUGIN_DYNAMICPLAYLIST';
}

sub getCustomSkipFilterTypes {
	my @result = ();

	my %recentlyaddedalbums = (
		'id' => 'dynamicplaylist_recentlyaddedalbum',
		'name' => 'Recently added album',
		'description' => 'Skip songs from albums that have been recently added to current dynamic playlist',
		'parameters' => [
			{
				'id' => 'nooftracks',
				'type' => 'singlelist',
				'name' => 'Songs between',
				'data' => '1=1 song,2=2 songs,2=3 songs,4=4 songs,5=5 songs,10=10 songs,20=20 songs,30=30 songs,50=50 songs',
				'value' => 10 
			}
		]
	);
	push @result, \%recentlyaddedalbums;
	my %recentlyaddedartists = (
		'id' => 'dynamicplaylist_recentlyaddedartist',
		'name' => 'Recently added artist',
		'description' => 'Skip songs by artists that have been recently added to current dynamic playlist',
		'parameters' => [
			{
				'id' => 'nooftracks',
				'type' => 'singlelist',
				'name' => 'Songs between',
				'data' => '1=1 song,2=2 songs,2=3 songs,4=4 songs,5=5 songs,10=10 songs,20=20 songs,30=30 songs,50=50 songs',
				'value' => 10 
			}
		]
	);
	push @result, \%recentlyaddedartists;
	return \@result;
}

sub checkCustomSkipFilterType {
	my $client = shift;
	my $filter = shift;
	my $track = shift;

	my $currentTime = time();
	my $parameters = $filter->{'parameter'};
	my $sql = undef;
	my $result = 0;
	my $dbh = getCurrentDBH();
	if($filter->{'id'} eq 'dynamicplaylist_recentlyaddedartist') {
		my $matching = 0;
		for my $parameter (@$parameters) {
			if($parameter->{'id'} eq 'nooftracks') {
				my $values = $parameter->{'value'};
				my $nooftracks = $values->[0] if(defined($values) && scalar(@$values)>0);

				my $artist = $track->artist();
				if(defined($artist) && defined($client) && defined($nooftracks)) {
					my $artistid = $artist->id;
					my $clientid = $dbh->quote($client->macaddress());
					$sql = "select dynamicplaylist_history.position from dynamicplaylist_history join contributor_track on contributor_track.track=dynamicplaylist_history.id where contributor_track.contributor=$artistid and dynamicplaylist_history.client=$clientid and dynamicplaylist_history.position>(select position from dynamicplaylist_history where dynamicplaylist_history.client=$clientid and skipped=0 order by position desc limit 1 offset $nooftracks)"
				}
				last;
			}
		}
	}elsif($filter->{'id'} eq 'dynamicplaylist_recentlyaddedalbum') {
		for my $parameter (@$parameters) {
			if($parameter->{'id'} eq 'nooftracks') {
				my $values = $parameter->{'value'};
				my $nooftracks = $values->[0] if(defined($values) && scalar(@$values)>0);

				my $album = $track->album();

				if(defined($album) && defined($client) && defined($nooftracks)) {
					my $albumid = $album->id;
					my $clientid = $dbh->quote($client->macaddress());
					$sql = "select dynamicplaylist_history.position from dynamicplaylist_history join tracks on tracks.id=dynamicplaylist_history.id where tracks.album=$albumid and dynamicplaylist_history.client=$clientid and dynamicplaylist_history.position>(select position from dynamicplaylist_history where dynamicplaylist_history.client=$clientid and skipped=0 order by position desc limit 1 offset $nooftracks)"
				}
				last;
			}
		}
	}
	if(defined($sql)) {
		eval {
			my $sth = $dbh->prepare( $sql );
			debugMsg("Executing skip filter SQL: $sql\n");
			$sth->execute() or do {
	            		debugMsg("Error executing: $sql\n");
	            		$sql = undef;
			};
			if(defined($sql)) {
				my $position;
				$sth->bind_columns( undef, \$position);
				if( $sth->fetch() ) {
					$result = 1;
				}
			}
		}
	}
	return $result;
}

sub filterTracks {
	my $client = shift;
	my $items = shift;
	initFilters();
	my @resultItems = ();
	for my $item (@$items) {
		my $result = 1;
		for my $key (keys %$filters) {
			last unless defined($result) && ($result==1 || $result==-1);

			my $filter = $filters->{$key};
			if($filter->{'dynamicplaylistenabled'}) {
				my $id = $filter->{'dynamicplaylistfilterid'};
				my $plugin = $filterPlugins{$id};
				no strict 'refs';
				debugMsg("Calling: $plugin :: executeDynamicPlayListFilter with: ".$filter->{'name'}.", ".$item->title."\n");
				my $res =  eval { &{"${plugin}::executeDynamicPlayListFilter"}($client,$filter,$item) };
				if($result==1 || !defined($res) || $res==0) {
					$result = $res;
				}
				if ($@) {
					debugMsg("Error filtering tracks with $plugin: $@\n");
				}
				use strict 'refs';
			}
		}
		my $skipped = 1;
		if(defined($result) && $result == 1) {
			$skipped = 0;
			push @resultItems,$item;
		}
		if(!defined($result) || $result != -1) {
			addToPlayListHistory($client,$item,$skipped);
		}
	}
	return \@resultItems;
}

# Find tracks matching parameters and add them to the playlist
sub findAndAdd {
	my ($client, $type, $offset, $limit, $addOnly) = @_;

	debugMsg("Starting random selection of $limit items for type: $type\n");
	
	my $playlist = getPlayList($client,$type);
	my $items = undef;
	my $filteredItems = undef;
	my $noOfItems = 0;
	my $noOfFilteredItems = 0;
	my $noOfRetiresDueToFilteredTracks = Slim::Utils::Prefs::get('plugin_dynamicplaylist_skipped_tracks_retries')|| 20;
	for my $i (1..$noOfRetiresDueToFilteredTracks) {
		$items = getTracksForPlaylist($client,$playlist,$limit,$offset+$noOfItems);
		return 0 if !defined $items || scalar(@$items)==0;

		$noOfItems = $noOfItems + (scalar @$items);
		debugMsg("Find returned ".(scalar @$items)." items\n");
		
		$filteredItems = filterTracks($client,$items);
		if(defined($filteredItems) && scalar(@$filteredItems)>0) {
			$noOfFilteredItems = (scalar @$filteredItems);
			debugMsg("Find returned ".$noOfFilteredItems." items after filtering\n");
			last;
		}else {
			if(defined($limit)) {
				$limit = Slim::Utils::Prefs::get('plugin_dynamicplaylist_number_of_tracks');
			}
		}
	}
	return 0 if !defined $filteredItems || scalar(@$filteredItems)==0;
			
	# Pull the first track off to add / play it if needed.
	my $item = shift @{$filteredItems};

	if ($item && ref($item)) {
		my $string = $item->title;
		debugMsg("".($addOnly ? 'Adding ' : 'Playing ')."$type: $string, ".($item->id)."\n");

		# Replace the current playlist with the first item / track or add it to end
		my $request = $client->execute(['playlist', $addOnly ? 'addtracks' : 'loadtracks',
		                  sprintf('%s=%d', getLinkAttribute('track'),$item->id)]);
		
		if ($::VERSION ge '6.5') {
			# indicate request source
			$request->source('PLUGIN_DYNAMICPLAYLIST');
		}

		# Add the remaining items to the end
		if (! defined $limit || $limit > 1 || $noOfItems>1) {
			debugMsg("Adding ".(scalar @$filteredItems)." tracks to end of playlist\n");
			if($noOfFilteredItems>1) {
				$request = $client->execute(['playlist', 'addtracks', 'listRef', $filteredItems]);
				if ($::VERSION ge '6.5') {
					$request->source('PLUGIN_DYNAMICPLAYLIST');
				}
			}
		}
	} 
	return $noOfItems;
}


# Add random tracks to playlist if necessary
sub playRandom {
	# If addOnly, then track(s) are appended to end.  Otherwise, a new playlist is created.
	my ($client, $type, $addOnly, $showFeedback, $forcedAdd) = @_;

	# disable this during the course of this function, since we don't want
	# to retrigger on commands we send from here.
	if ($::VERSION ge '6.5') {
	} else {
		Slim::Control::Command::clearExecuteCallback(\&commandCallback62);
	}

	debugMsg("playRandom called with type $type\n");
	
	# Whether to keep adding tracks after generating the initial playlist
	my $continuousMode = Slim::Utils::Prefs::get('plugin_dynamicplaylist_keep_adding_tracks');;
	
	# If this is a new mix, clear playlist history
	if ($continuousMode && !$addOnly || !$mixInfo{$client} || $mixInfo{$client}->{'type'} ne $type) {
		clearPlayListHistory($client);
	}
	my $offset = $mixInfo{$client}->{'offset'};
	if (!$mixInfo{$client}->{'type'} || $mixInfo{$client}->{'type'} ne $type || !$addOnly) {
		$offset = 0;
	}

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);
	my $songsRemaining = Slim::Player::Playlist::count($client) - $songIndex - 1;
	debugMsg("$songsRemaining songs remaining, songIndex = $songIndex\n");

	# Work out how many items need adding
	my $numItems = 0;

	if($type ne 'disable') {
		# Add new tracks if there aren't enough after the current track
		my $numRandomTracks = Slim::Utils::Prefs::get('plugin_dynamicplaylist_number_of_tracks');
		if (! $addOnly) {
			$numItems = $numRandomTracks;
		} elsif ($songsRemaining < $numRandomTracks - 1) {
			$numItems = $numRandomTracks - 1 - $songsRemaining;
		} elsif( $addOnly && $forcedAdd ) {
			# Add a single track if add button is pushed when the playlist is full
			$numItems = 1;
		} else {
			debugMsg("$songsRemaining items remaining so not adding new track\n");
		}
	}

	my $count = 0;
	if ($numItems) {
		unless ($addOnly) {
			$client->execute(['stop']);
			$client->execute(['power', '1']);
		}
		Slim::Player::Playlist::shuffle($client, 0);
		
		# String to show with showBriefly
		my $string = '';

		my $playlist = getPlayList($client,$type);
		if($playlist) {
			$string = $playlist->{'name'};
		}

		# Strings for non-track modes could be long so need some time to scroll
		my $showTime = 5;
		
		# Add tracks 
		$count = findAndAdd($client,
                        $type,
            			$offset,
                        $numItems,
			            # 2nd time round just add tracks to end
					    $addOnly);

		$offset += $count;
		if($count>0) {
			# Do a show briefly the first time things are added, or every time a new album/artist/year
			# is added
			if (!$addOnly || $type ne $mixInfo{$client}->{'type'}) {
				# Don't do showBrieflys if visualiser screensavers are running as the display messes up
				if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
					$client->showBriefly(string($addOnly ? 'ADDING_TO_PLAYLIST' : 'NOW_PLAYING'),
										 $string, $showTime);
				}
			}
		}elsif($showFeedback) {
				if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
					$client->showBriefly(string('PLUGIN_DYNAMICPLAYLIST_NOW_PLAYING_FAILED'),
										 string('PLUGIN_DYNAMICPLAYLIST_NOW_PLAYING_FAILED')." ".$string, $showTime);
				}
		}
		# Never show random as modified, since its a living playlist
		$client->currentPlaylistModified(0);		
	}
	
	if ($::VERSION ge '6.5') {
	}else {
		Slim::Control::Command::setExecuteCallback(\&commandCallback62);
	}
	if ($type eq 'disable') {
		debugMsg("cyclic mode ended\n");
		# Don't do showBrieflys if visualiser screensavers are running as the display messes up
		if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
			$client->showBriefly(string('PLUGIN_DYNAMICPLAYLIST'), string('PLUGIN_DYNAMICPLAYLIST_DISABLED'));
		}
		$mixInfo{$client} = undef;
	} else {
		if(!$numItems || $numItems==0 || $count>0) {
			debugMsg(($addOnly?"Adding ":"Playing ").($continuousMode ? 'continuous' : 'static')." $type with ".Slim::Player::Playlist::count($client)." items\n");

			if (!$addOnly) {
				# Record current mix type and the time it was started.
				# Do this last to prevent menu items changing too soon
				$mixInfo{$client}->{'type'} = $type;
			}
			if($mixInfo{$client}->{'type'} eq $type) {
				$mixInfo{$client}->{'offset'} = $offset;
			}
		}else {
			$mixInfo{$client}->{'type'} = undef;
		}
	}
}

# Returns the display text for the currently selected item in the menu
sub getDisplayText {
	my ($client, $item) = @_;

	my $id = undef;
	my $name = '';
	if($item) {
		$name = $item->{'name'};
		if(defined($item->{'playlist'})) {
			$name = $item->{'playlist'}->{'name'};
			$id = $item->{'playlist'}->{'dynamicplaylistid'};
		}
	}
	# if showing the current mode, show altered string
	if ($mixInfo{$client} && defined($mixInfo{$client}->{'type'}) && $id eq $mixInfo{$client}->{'type'}) {
		return $name." (".string('PLUGIN_DYNAMICPLAYLIST_PLAYING').")";
		
	# if a mode is active, handle the temporarily added disable option
	} elsif ($id eq 'disable' && $mixInfo{$client}) {
		return string('PLUGIN_DYNAMICPLAYLIST_PRESS_RIGHT');
	} else {
		return $name;
	}
}

# Returns the display text for the currently selected item in the menu
sub getChooseParametersDisplayText {
	my ($client, $item) = @_;

	my $name = '';
	if($item) {
		$name = $item->{'name'};
	}
	return $name;
}

# Returns the overlay to be display next to items in the menu
sub getOverlay {
	my ($client, $item) = @_;

	# Put the right arrow by genre filter and notesymbol by mixes
	if (defined($item->{'playlist'}) && $item->{'playlist'}->{'dynamicplaylistid'} eq 'disable') {
		return [undef, Slim::Display::Display::symbol('rightarrow')];
	}elsif(!defined($item->{'playlist'})) {
		return [undef, Slim::Display::Display::symbol('rightarrow')];
	}elsif (!defined($mixInfo{$client}) || !defined($mixInfo{$client}->{'type'}) || $item->{'playlist'}->{'dynamicplaylistid'} ne $mixInfo{$client}->{'type'}) {
		if(defined($item->{'playlist'}->{'parameters'})) {
			return [Slim::Display::Display::symbol('rightarrow'), Slim::Display::Display::symbol('notesymbol')];
		}else {
			return [undef, Slim::Display::Display::symbol('notesymbol')];
		}
	}elsif(defined($item->{'playlist'}->{'parameters'})) {
		return [Slim::Display::Display::symbol('rightarrow'), undef];
	}
	return [undef, undef];
}

# Returns the overlay to be display next to items in the menu
sub getChooseParametersOverlay {
	my ($client, $item) = @_;

	return [undef, Slim::Display::Display::symbol('rightarrow')];
}

# Do what's necessary when play or add button is pressed
sub handlePlayOrAdd {
	my ($client, $item, $add) = @_;
	debugMsg("".($add ? 'Add' : 'Play')."$item\n");
	
	# reconstruct the list of options, adding and removing the 'disable' option where applicable
#	my $listRef = Slim::Buttons::Common::param($client, 'listRef');
#		
#	if ($item eq 'disable') {
#		pop @$listRef;
#		
#	# only add disable option if starting a mode from idle state
#	} elsif (! $mixInfo{$client}) {
#		push @$listRef, \%disable;
#	}
#	Slim::Buttons::Common::param($client, 'listRef', $listRef);

	# Clear any current mix type in case user is restarting an already playing mix
	$mixInfo{$client} = undef;

	# Go go go!
	playRandom($client, $item, $add, 1, 1);
}
sub getCurrentPlayList {
	my $client = shift;
	if (defined($client) && $mixInfo{$client}) {
		return $mixInfo{$client}->{'type'};
	}
	return undef;
}
sub getPlayList {
	my $client = shift;
	my $type = shift;
	
	return undef unless $type;

	debugMsg("Get playlist: $type\n");
	if(!$playLists) {
		initPlayLists($client);
	}
	return undef unless $playLists;
	
	return $playLists->{$type};
}
sub getDefaultGroups {
	my $groupPath = Slim::Utils::Prefs::get('plugin_dynamicplaylist_ungrouped');
	if(defined($groupPath) && $groupPath ne "") {
		my @groups = split(/\//,$groupPath);
		my @mainGroups = [@groups];
		return \@mainGroups;
	}
	return undef;
}

sub initPlayListTypes {
	if(!$playLists) {
		initPlayLists();
	}
	my %localPlayListTypes = ();
	for my $playlistId (keys %$playLists) {
		my $playlist = $playLists->{$playlistId};
		if($playlist->{'dynamicplaylistenabled'}) {
			if(defined($playlist->{'parameters'})) {
				my $parameter1 = $playlist->{'parameters'}->{'1'};
				if(defined($parameter1)) {
					if($parameter1->{'type'} eq 'album' || $parameter1->{'type'} eq 'artist' || $parameter1->{'type'} eq 'year' || $parameter1->{'type'} eq 'genre' || $parameter1->{'type'} eq 'playlist') {
						$localPlayListTypes{$parameter1->{'type'}} = 1;
					}
				}
			}
		}
	}
	$playListTypes = \%localPlayListTypes;
}

sub initPlayLists {
	my $client = shift;
	
	debugMsg("Searching for playlists\n");
	
	my %localPlayLists = ();
	my %localPlayListItems = ();
	
	no strict 'refs';
	my @enabledplugins;
	if ($::VERSION ge '6.5') {
		@enabledplugins = Slim::Utils::PluginManager::enabledPlugins();
	}else {
		@enabledplugins = Slim::Buttons::Plugins::enabledPlugins();
	}
	for my $plugin (@enabledplugins) {
		if(UNIVERSAL::can("Plugins::$plugin","getDynamicPlayLists") && UNIVERSAL::can("Plugins::$plugin","getNextDynamicPlayListTracks")) {
			debugMsg("Getting dynamic playlists for: $plugin\n");
			my $items = eval { &{"Plugins::${plugin}::getDynamicPlayLists"}($client) };
			if ($@) {
				debugMsg("Error getting playlists from $plugin: $@\n");
			}
			for my $item (keys %$items) {
				$plugins{$item} = "Plugins::${plugin}";
				my $playlist = $items->{$item};
				debugMsg("Got dynamic playlists: ".$playlist->{'name'}."\n");
				$playlist->{'dynamicplaylistid'} = $item;
				$playlist->{'dynamicplaylistplugin'} = $plugin;
				my $enabled = Slim::Utils::Prefs::get('plugin_dynamicplaylist_playlist_'.$item.'_enabled');
				if(!defined $enabled) {
					$enabled = Slim::Utils::Prefs::get('plugin_dynamicplaylist_enabled_playlist_'.$item);
					if(defined $enabled) {
						Slim::Utils::Prefs::delete('plugin_dynamicplaylist_enabled_playlist_'.$item);
						Slim::Utils::Prefs::set('plugin_dynamicplaylist_playlist_'.$item.'_enabled',$enabled);
					}
				}
				if(!defined $enabled || $enabled) {
					$playlist->{'dynamicplaylistenabled'} = 1;
				}else {
					$playlist->{'dynamicplaylistenabled'} = 0;
				}

				my $favourite = Slim::Utils::Prefs::get('plugin_dynamicplaylist_playlist_'.$item.'_favourite');
				if(defined($favourite) && $favourite) {
					$playlist->{'dynamicplaylistfavourite'} = 1;
				}else {
					$playlist->{'dynamicplaylistfavourite'} = 0;
				}

				if(defined($playlist->{'parameters'})) {
					foreach my $p (keys %{$playlist->{'parameters'}}) {
						if(defined($playLists) 
							&& defined($playLists->{$item}) 
							&& defined($playLists->{$item}->{'parameters'})
							&& defined($playLists->{$item}->{'parameters'}->{$p})
							&& defined($playLists->{$item}->{'parameters'}->{$p}->{'name'})
							&& $playLists->{$item}->{'parameters'}->{$p}->{'name'} eq $playlist->{'parameters'}->{$p}->{'name'}
							&& defined($playLists->{$item}->{'parameters'}->{$p}->{'value'})) {
							
							debugMsg("Use already existing value for PlaylistParameter$p=".$playLists->{$item}->{'parameters'}->{$p}->{'value'}."\n");	
							$playlist->{'parameters'}->{$p}->{'value'}=$playLists->{$item}->{'parameters'}->{$p}->{'value'};
						}
					}
				}

				$localPlayLists{$item} = $playlist;
				my $groups = $playlist->{'groups'};
				if(!defined($groups)) {
					$groups = getDefaultGroups();
				}
				if(!defined($groups)) {
					my @emptyArray = ();
					$groups = \@emptyArray;
				}
				if($favourite && Slim::Utils::Prefs::get("plugin_dynamicplaylist_favouritesname")) {
					my @favouriteGroups = ();
					for my $g (@$groups) {
						push @favouriteGroups,$g;
					}
					my @favouriteGroup = ();
					push @favouriteGroup, Slim::Utils::Prefs::get("plugin_dynamicplaylist_favouritesname");
					push @favouriteGroups,\@favouriteGroup;
					$groups = \@favouriteGroups;
				}
				if(scalar(@$groups)>0) {
					for my $currentgroups (@$groups) {
						my $currentLevel = \%localPlayListItems;
						my $grouppath = '';
						my $enabled = 1;
						for my $group (@$currentgroups) {
							$grouppath .= "_".escape($group);
							#debugMsg("Got group: ".$grouppath."\n");
							my $existingItem = $currentLevel->{'dynamicplaylistgroup_'.$group};
							if(defined($existingItem)) {
								if($enabled) {
									$enabled = Slim::Utils::Prefs::get('plugin_dynamicplaylist_playlist_group_'.$grouppath.'_enabled');
									if(!defined($enabled)) {
										$enabled = 1;
									}
								}
								if($enabled && $playlist->{'dynamicplaylistenabled'}) {
									$existingItem->{'dynamicplaylistenabled'} = 1;
								}
								$currentLevel = $existingItem->{'childs'};
							}else {
								my %level = ();
								my %currentItemGroup = (
									'childs' => \%level,
									'name' => $group,
									'value' => $grouppath
								);
								if($enabled) {
									$enabled = Slim::Utils::Prefs::get('plugin_dynamicplaylist_playlist_group_'.$grouppath.'_enabled');
									if(!defined($enabled)) {
										$enabled = 1;
									}
								}
								if($enabled && $playlist->{'dynamicplaylistenabled'}) {
									#debugMsg("Enabled: plugin_dynamicplaylist_playlist_".$grouppath."_enabled=1\n");
									$currentItemGroup{'dynamicplaylistenabled'} = 1;
								}else {
									#debugMsg("Enabled: plugin_dynamicplaylist_playlist_".$grouppath."_enabled=0\n");
									$currentItemGroup{'dynamicplaylistenabled'} = 0;
								}

								$currentLevel->{'dynamicplaylistgroup_'.$group} = \%currentItemGroup;
								$currentLevel = \%level;
							}
						}
						my %currentGroupItem = (
							'playlist' => $playlist,
							'dynamicplaylistenabled' => $playlist->{'dynamicplaylistenabled'},
							'value' => $playlist->{'dynamicplaylistid'}
						);
						$currentLevel->{$item} = \%currentGroupItem;
					}
				}else {
					my %currentItem = (
						'playlist' => $playlist,
						'dynamicplaylistenabled' => $playlist->{'dynamicplaylistenabled'},
						'value' => $playlist->{'dynamicplaylistid'}
					);
					$localPlayListItems{$item} = \%currentItem;
				}
			}
			#printPlayListItems('',\%localPlayListItems);
		}
	}
	use strict 'refs';

	$playLists = \%localPlayLists;
	$playListItems = \%localPlayListItems;
}


sub initFilters {
	debugMsg("Searching for filters\n");
	
	my %localFilters = ();
	
	no strict 'refs';
	my @enabledplugins;
	if ($::VERSION ge '6.5') {
		@enabledplugins = Slim::Utils::PluginManager::enabledPlugins();
	}else {
		@enabledplugins = Slim::Buttons::Plugins::enabledPlugins();
	}
	for my $plugin (@enabledplugins) {
		if(UNIVERSAL::can("Plugins::$plugin","getDynamicPlayListFilters") && UNIVERSAL::can("Plugins::$plugin","executeDynamicPlayListFilter")) {
			debugMsg("Getting filters for: $plugin\n");
			my $items = eval { &{"Plugins::${plugin}::getDynamicPlayListFilters"}() };
			if ($@) {
				debugMsg("Error getting filters from $plugin: $@\n");
			}
			for my $item (keys %$items) {
				$filterPlugins{$item} = "Plugins::${plugin}";
				my $filter = $items->{$item};
				debugMsg("Got filters: ".$filter->{'name'}."\n");
				$filter->{'dynamicplaylistfilterid'} = $item;
				$filter->{'dynamicplaylistfilterplugin'} = $plugin;
				my $enabled = Slim::Utils::Prefs::get('plugin_dynamicplaylist_filter_'.$item.'_enabled');
				if((defined($enabled) && $enabled) || (!defined($enabled) && defined($filter->{'defaultenabled'}) && $filter->{'defaultenabled'})) {
					$filter->{'dynamicplaylistenabled'} = 1;
				}else {
					$filter->{'dynamicplaylistenabled'} = 0;
				}

				$localFilters{$item} = $filter;
			}
		}
	}
	use strict 'refs';

	$filters = \%localFilters;
}

sub addParameterValues {
	my $client = shift;
	my $listRef = shift;
	my $parameter = shift;
	
	debugMsg("Getting values for ".$parameter->{'name'}." of type ".$parameter->{'type'}."\n");
	my $sql = undef;
	if(lc($parameter->{'type'}) eq 'album') {
		$sql = "select id,title,substr(titlesort,1,1) from albums order by titlesort";
	}elsif(lc($parameter->{'type'}) eq 'artist') {
		$sql = "select id,name,substr(namesort,1,1) from contributors where namesort is not null order by namesort";
	}elsif(lc($parameter->{'type'}) eq 'genre') {
		$sql = "select id,name,substr(namesort,1,1) from genres order by namesort";
	}elsif(lc($parameter->{'type'}) eq 'year') {
		$sql = "select year,year from tracks where year is not null group by year order by year desc";
	}elsif(lc($parameter->{'type'}) eq 'playlist') {
		$sql = "select playlist_track.playlist,tracks.title,substr(tracks.titlesort,1,1) from tracks, playlist_track where tracks.id=playlist_track.playlist group by playlist_track.playlist order by titlesort";
	}elsif(lc($parameter->{'type'}) eq 'list') {
		my $value = $parameter->{'definition'};
		if(defined($value) && $value ne "" ) {
			my @values = split(/,/,$value);
			if(@values) {
				for my $valueItem (@values) {
					my @valueItemArray = split(/:/,$valueItem);
					my $id = shift @valueItemArray;
					my $name = shift @valueItemArray;
					my $sortlink = shift @valueItemArray;
					
					if(defined($id)) {
						my %listitem = (
							'id' => $id,
							'value' => $id
						);
						if(defined($name)) {
							$listitem{'name'}=$name;
						}else {
							$listitem{'name'}=$id;
						}
						if(defined($sortlink)) {
							$listitem{'sortlink'}=$sortlink;
						}
					  	push @$listRef, \%listitem;
					}
				}
			}else {
				debugMsg("Error, invalid parameter value: $value\n");
			}
		}
	}elsif(lc($parameter->{'type'}) eq 'custom') {
		if(defined($parameter->{'definition'}) && lc($parameter->{'definition'}) =~ /^select/ ) {
			$sql = $parameter->{'definition'};
			for (my $i=1;$i<$parameter->{'id'};$i++) {
				my $parameter = $client->param('dynamicplaylist_parameter_'.$i);
				my $value = $parameter->{'id'};
				my $parameterid = "\'PlaylistParameter".$i."\'";
				debugMsg("Replacing ".$parameterid." with ".$value."\n");
				$sql =~ s/$parameterid/$value/g;
			}
			my $activeLibrary = 0;
			if(isPluginsInstalled($client,'MultiLibrary::Plugin')) {
				$activeLibrary = $client->prefGet('plugin_multilibrary_activelibraryno');
				if(!defined($activeLibrary)) {
					$activeLibrary = 0;
				}
			}
			my $parameterid = "\'PlaylistActiveLibrary\'";
			debugMsg("Replacing $parameterid with ".$activeLibrary."\n");
			$sql =~ s/$parameterid/$activeLibrary/g;
		}
	}
	
	if(defined($sql)) {
		my $dbh = getCurrentDBH();
		eval {
			my $sth = $dbh->prepare( $sql );
			debugMsg("Executing value list: $sql\n");
			$sth->execute() or do {
	            		debugMsg("Error executing: $sql\n");
	            		$sql = undef;
			};
			if(defined($sql)) {
				my $id;
				my $name;
				my $sortlink = undef;
				eval {
					$sth->bind_columns( undef, \$id,\$name,\$sortlink);
				};
				if( $@ ) {
					$sth->bind_columns( undef, \$id,\$name);
				}
				while( $sth->fetch() ) {
					my %listitem = (
						'id' => $id,
						'value' => $id,
						'name' => Slim::Utils::Unicode::utf8decode($name,'utf8')
					);
					if(defined($sortlink)) {
						$listitem{'sortlink'} = Slim::Utils::Unicode::utf8decode($sortlink,'utf8');
					}
				  	push @$listRef, \%listitem;
			  	}
			  	debugMsg("Added ".scalar(@$listRef)." items to value list\n");
			}
			$sth->finish();
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		}		
	}
}

sub isPluginsInstalled {
	my $client = shift;
	my $pluginList = shift;
	my $enabledPlugin = 1;
	foreach my $plugin (split /,/, $pluginList) {
		if($enabledPlugin) {
			if ($::VERSION ge '6.5') {
				$enabledPlugin = Slim::Utils::PluginManager::enabledPlugin($plugin,$client);
			}else {
				$enabledPlugin = grep(/$plugin/,Slim::Buttons::Plugins::enabledPlugins($client));
			}
		}
	}
	return $enabledPlugin;
}

sub printPlayListItems {
	my $currentpath = shift;
	my $items = shift;
	return;
	for my $itemKey (keys %$items) {
		my $item = $items->{$itemKey};
		if(defined($item->{'playlist'})) {
			my $playlist = $item->{'playlist'};
			debugMsg("Got: ".$currentpath."/".$playlist->{'name'}." (enabled=".$item->{'dynamicplaylistenabled'}.", ".$playlist->{'dynamicplaylistid'}.",".$playlist->{'dynamicplaylistplugin'}.")\n");
		}else {
			my $childs = $item->{'childs'};
			#debugMsg("Got Group: ".$item->{'name'}." = ".$item->{'dynamicplaylistenabled'}."\n");
			printPlayListItems($currentpath."/".$item->{'name'},$childs);
		}
	}
}

sub setMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my @listRef = ();
	initFilters();
	initPlayLists($client);
	initPlayListTypes();
	my $playlisttype = $client->param('playlisttype');
	my $showFlat = Slim::Utils::Prefs::get('plugin_dynamicplaylist_flatlist');
	if($showFlat || defined($client->param('flatlist'))) {
		foreach my $flatItem (sort keys %$playLists) {
			my $playlist = $playLists->{$flatItem};
			if($playlist->{'dynamicplaylistenabled'}) {
				my %flatPlaylistItem = (
					'playlist' => $playlist,
					'dynamicplaylistenabled' => 1,
					'value' => $playlist->{'dynamicplaylistid'}
				);
				if(!defined($playlisttype)) {
					push @listRef, \%flatPlaylistItem;
				}else {
					if(defined($playlist->{'parameters'}) && defined($playlist->{'parameters'}->{'1'}) && $playlist->{'parameters'}->{'1'}->{'type'} eq $playlisttype) {
						push @listRef, \%flatPlaylistItem;
					}
				}
			}
		}
	}else {
		foreach my $menuItemKey (sort keys %$playListItems) {
			if($playListItems->{$menuItemKey}->{'dynamicplaylistenabled'}) {
				if(!defined($playlisttype)) {
					push @listRef, $playListItems->{$menuItemKey};
				}else {
					if(defined($playListItems->{$menuItemKey}->{'playlist'})) {
						my $playlist = $playListItems->{$menuItemKey}->{'playlist'};
						if(defined($playlist->{'parameters'}) && defined($playlist->{'parameters'}->{'1'}) && $playlist->{'parameters'}->{'1'}->{'type'} eq $playlisttype) {
							push @listRef, $playListItems->{$menuItemKey};
						}
					}else {
						push @listRef, $playListItems->{$menuItemKey};
					}
				}
			}
		}
		my $playlistgroup = $client->param('selectedgroup');
		if($playlistgroup) {
			for my $item (@listRef) {
				if(!defined($item->{'playlist'}) && defined($item->{'childs'}) && $item->{'name'} eq $playlistgroup) {
					Slim::Buttons::Common::pushModeLeft($client,'INPUT.Choice',getSetModeDataForSubItems($client,$item,$item->{'childs'}));
					return;
				}
			}
		}
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header     => '{PLUGIN_DYNAMICPLAYLIST} {count}',
		listRef    => \@listRef,
		name       => \&getDisplayText,
		overlayRef => \&getOverlay,
		modeName   => 'PLUGIN.DynamicPlayList',
		onPlay     => sub {
			my ($client, $item) = @_;
			if(defined($item->{'playlist'})) {
				my $playlist = $item->{'playlist'};
				if(defined($playlist->{'parameters'})) {
					my %parameterValues = ();
					my $i=1;
					while(defined($client->param('dynamicplaylist_parameter_'.$i))) {
						$parameterValues{'dynamicplaylist_parameter_'.$i} = $client->param('dynamicplaylist_parameter_'.$i);
						$i++;
					}
					if(defined($client->param('extrapopmode'))) {
						$parameterValues{'extrapopmode'} = $client->param('extrapopmode');
					}
					requestFirstParameter($client,$playlist,0,\%parameterValues);
				}else {
					handlePlayOrAdd($client, $item->{'playlist'}->{'dynamicplaylistid'}, 0);
				}
			}
		},
		onAdd      => sub {
			my ($client, $item) = @_;
			my $playlist = $item->{'playlist'};
			if(defined($item->{'playlist'})) {
				if(defined($playlist->{'parameters'})) {
					my %parameterValues = ();
					my $i=1;
					while(defined($client->param('dynamicplaylist_parameter_'.$i))) {
						$parameterValues{'dynamicplaylist_parameter_'.$i} = $client->param('dynamicplaylist_parameter_'.$i);
						$i++;
					}
					if(defined($client->param('extrapopmode'))) {
						$parameterValues{'extrapopmode'} = $client->param('extrapopmode');
					}
					requestFirstParameter($client,$playlist,0,\%parameterValues);
				}else {
					handlePlayOrAdd($client, $item->{'playlist'}->{'dynamicplaylistid'}, 1);
				}
			}
		},
		onRight    => sub {
			my ($client, $item) = @_;
			if(defined($item->{'playlist'}) && $item->{'playlist'}->{'dynamicplaylistid'} eq 'disable') {
				handlePlayOrAdd($client, $item->{'playlist'}->{'dynamicplaylistid'}, 0);
			}elsif(defined($item->{'childs'})) {
				Slim::Buttons::Common::pushModeLeft($client,'INPUT.Choice',getSetModeDataForSubItems($client,$item,$item->{'childs'}));
			}elsif(defined($item->{'playlist'}) && defined($item->{'playlist'}->{'parameters'})) {
				my %parameterValues = ();
				my $i=1;
				while(defined($client->param('dynamicplaylist_parameter_'.$i))) {
					$parameterValues{'dynamicplaylist_parameter_'.$i} = $client->param('dynamicplaylist_parameter_'.$i);
					$i++;
				}
				if(defined($client->param('extrapopmode'))) {
					$parameterValues{'extrapopmode'} = $client->param('extrapopmode');
				}
				requestFirstParameter($client,$item->{'playlist'},0,\%parameterValues)
			}else {
				$client->bumpRight();
			}
		},
	);
	my $i=1;
	while(defined($client->param('dynamicplaylist_parameter_'.$i))) {
		$params{'dynamicplaylist_parameter_'.$i} = $client->param('dynamicplaylist_parameter_'.$i);
		$i++;
	}
	if(defined($client->param('extrapopmode'))) {
		$params{'extrapopmode'} = $client->param('extrapopmode');
	}
	
	# if we have an active mode, temporarily add the disable option to the list.
	if ($mixInfo{$client} && $mixInfo{$client}->{'type'} ne "") {
		push @{$params{listRef}},\%disable;
	}

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub setModeChooseParameters {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $parameterId = $client->param('dynamicplaylist_nextparameter');
	my $playlist = $client->param('dynamicplaylist_selectedplaylist');
	if(!defined($playlist)) {
		my $playlistId = $client->param('dynamicplaylist_selectedplaylistid');
		if(defined($playlistId)) {
			$playlist = getPlayList($client,$playlistId);
		}
	}
	
	my $parameter= $playlist->{'parameters'}->{$parameterId};

	my @listRef = ();
	addParameterValues($client,\@listRef, $parameter);

	my $sorted = '0';
	if(scalar(@listRef)>0) {
		my $firstItem = @listRef->[0];
		if(defined($firstItem->{'sortlink'})) {
			$sorted = 'L';
		}
	}
	my $name = $parameter->{'name'};
	my %params = (
		header     => "$name {count}",
		listRef    => \@listRef,
		lookupRef  => sub {
				my ($index) = @_;
				my $sortListRef = Slim::Buttons::Common::param($client,'listRef');
				my $sortItem  = $sortListRef->[$index];
				if(defined($sortItem->{'sortlink'})) {
					return $sortItem->{'sortlink'};
				}else {
					return $sortItem->{'name'};
				}
			},
		isSorted   => $sorted,
		name       => \&getChooseParametersDisplayText,
		overlayRef => \&getChooseParametersOverlay,
		modeName   => 'PLUGIN.DynamicPlayList.ChooseParameters',
		onRight    => sub {
			my ($client, $item) = @_;
			requestNextParameter($client,$item,$parameterId,$playlist);
		},
		onPlay    => sub {
			my ($client, $item) = @_;
			requestNextParameter($client,$item,$parameterId,$playlist,0);
		},
		onAdd    => sub {
			my ($client, $item) = @_;
			requestNextParameter($client,$item,$parameterId,$playlist,1);
		},
		dynamicplaylist_nextparameter => $parameterId,
		dynamicplaylist_selectedplaylist => $playlist,
		dynamicplaylist_addonly => $client->param('dynamicplaylist_addonly')
	);
	for(my $i=1;$i<$parameterId;$i++) {
		$params{'dynamicplaylist_parameter_'.$i} = $client->param('dynamicplaylist_parameter_'.$i);
	}
	if(defined($client->param('extrapopmode'))) {
		$params{'extrapopmode'} = $client->param('extrapopmode');
	}

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub getSetModeDataForSubItems {
	my $client = shift;
	my $currentItem = shift;
	my $items = shift;

	my @listRefSub = ();
	foreach my $menuItemKey (sort keys %$items) {
		if($items->{$menuItemKey}->{'dynamicplaylistenabled'}) {
			my $playlisttype = $client->param('playlisttype');
			if(!defined($playlisttype)) {
				push @listRefSub, $items->{$menuItemKey};
			}else {
				if(defined($items->{$menuItemKey}->{'playlist'})) {
					my $playlist = $items->{$menuItemKey}->{'playlist'};
					if(defined($playlist->{'parameters'}) && defined($playlist->{'parameters'}->{'1'}) && $playlist->{'parameters'}->{'1'}->{'type'} eq $playlisttype) {
						push @listRefSub, $items->{$menuItemKey};
					}
				}else {
					push @listRefSub, $items->{$menuItemKey};
				}
			}
		}
	}
	
	my %params = (
		header     => '{PLUGIN_DYNAMICPLAYLIST} {count}',
		listRef    => \@listRefSub,
		name       => \&getDisplayText,
		overlayRef => \&getOverlay,
		modeName   => 'PLUGIN.DynamicPlayList'.$currentItem->{'value'},
		onPlay     => sub {
			my ($client, $item) = @_;
			if(defined($item->{'playlist'})) {
				my $playlist = $item->{'playlist'};
				if(defined($playlist->{'parameters'})) {
					my %parameterValues = ();
					my $i=1;
					while(defined($client->param('dynamicplaylist_parameter_'.$i))) {
						$parameterValues{'dynamicplaylist_parameter_'.$i} = $client->param('dynamicplaylist_parameter_'.$i);
						$i++;
					}
					if(defined($client->param('extrapopmode'))) {
						$parameterValues{'extrapopmode'} = $client->param('extrapopmode');
					}
					requestFirstParameter($client,$playlist,0,\%parameterValues);
				}else {
					handlePlayOrAdd($client, $item->{'playlist'}->{'dynamicplaylistid'}, 0);
				}
			}
		},
		onAdd      => sub {
			my ($client, $item) = @_;
			if(defined($item->{'playlist'})) {
				my $playlist = $item->{'playlist'};
				if(defined($playlist->{'parameters'})) {
					my %parameterValues = ();
					my $i=1;
					while(defined($client->param('dynamicplaylist_parameter_'.$i))) {
						$parameterValues{'dynamicplaylist_parameter_'.$i} = $client->param('dynamicplaylist_parameter_'.$i);
						$i++;
					}
					if(defined($client->param('extrapopmode'))) {
						$parameterValues{'extrapopmode'} = $client->param('extrapopmode');
					}
					requestFirstParameter($client,$playlist,1,\%parameterValues);
				}else {
					handlePlayOrAdd($client, $item->{'playlist'}->{'dynamicplaylistid'}, 1);
				}
			}
		},
		onRight    => sub {
			my ($client, $item) = @_;
			if(defined($item->{'childs'})) {
				Slim::Buttons::Common::pushModeLeft($client,'INPUT.Choice',getSetModeDataForSubItems($client,$item,$item->{'childs'}));
			}elsif(defined($item->{'playlist'}) && defined($item->{'playlist'}->{'parameters'})) {
				my %parameterValues = ();
				my $i=1;
				while(defined($client->param('dynamicplaylist_parameter_'.$i))) {
					$parameterValues{'dynamicplaylist_parameter_'.$i} = $client->param('dynamicplaylist_parameter_'.$i);
					$i++;
				}
				if(defined($client->param('extrapopmode'))) {
					$parameterValues{'extrapopmode'} = $client->param('extrapopmode');
				}
				requestFirstParameter($client,$item->{'playlist'},0,\%parameterValues);
			}else {
				$client->bumpRight();
			}
		}
	);
	return \%params;
}

sub requestNextParameter {
	my $client = shift;
	my $item = shift;
	my $parameterId = shift;
	my $playlist = shift;
	my $addOnly = shift;
	
	if(!defined($addOnly)) {
		$addOnly = $client->param('dynamicplaylist_addonly');
	}
	$client->param('dynamicplaylist_parameter_'.$parameterId,$item);
	if(defined($playlist->{'parameters'}->{$parameterId+1})) {
		my %nextParameter = (
			'dynamicplaylist_nextparameter' => $parameterId+1,
			'dynamicplaylist_selectedplaylist' => $playlist,
			'dynamicplaylist_addonly' => $addOnly
		);
		my $i;
		for($i=1;$i<=$parameterId;$i++) {
			$nextParameter{'dynamicplaylist_parameter_'.$i} = $client->param('dynamicplaylist_parameter_'.$i);
		}
		Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.DynamicPlayList.ChooseParameters',\%nextParameter);
	}else {
		for(my $i=1;$i<=$parameterId;$i++) {
			$playlist->{'parameters'}->{$i}->{'value'} = $client->param('dynamicplaylist_parameter_'.$i)->{'id'};
		}
		for(my $i=1;$i<=$parameterId;$i++) {
			Slim::Buttons::Common::popMode($client);
		}
		if(defined($client->param('extrapopmode'))) {
			Slim::Buttons::Common::popMode($client);
		}
		handlePlayOrAdd($client, $playlist->{'dynamicplaylistid'}, $addOnly);

		$client->update();
	}
}


sub requestFirstParameter {
	my $client = shift;
	my $playlist = shift;
	my $addOnly = shift;
	my $params = shift;

	my %nextParameters = (
		'dynamicplaylist_selectedplaylist' => $playlist,
		'dynamicplaylist_addonly' => $addOnly
	);
	foreach my $pk (keys %$params) {
		$nextParameters{$pk} = $params->{$pk};
	}
	my $i = 1;
	while(defined($nextParameters{'dynamicplaylist_parameter_'.$i})) {
		$i++;
	}
	$nextParameters{'dynamicplaylist_nextparameter'}=$i;

	if(defined($playlist->{'parameters'}) && defined($playlist->{'parameters'}->{$nextParameters{'dynamicplaylist_nextparameter'}})) {
		Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.DynamicPlayList.ChooseParameters',\%nextParameters);
	}else {
		for($i=1;$i<$nextParameters{'dynamicplaylist_nextparameter'};$i++) {
			$playlist->{'parameters'}->{$i}->{'value'} = $params->{'dynamicplaylist_parameter_'.$i}->{'id'};
		}
		for(my $i=1;$i<$nextParameters{'dynamicplaylist_nextparameter'};$i++) {
			Slim::Buttons::Common::popMode($client);
		}
		if(defined($nextParameters{'extrapopmode'})) {
			Slim::Buttons::Common::popMode($client);
		}
		handlePlayOrAdd($client, $playlist->{'dynamicplaylistid'}, $addOnly);
		$client->update();
	}
}

sub commandCallback62 {
	my ($client, $paramsRef) = @_;

	my $slimCommand = $paramsRef->[0];

	# we dont care about generic ir blasts
	return if $slimCommand eq 'ir';
	
	return if $slimCommand ne "dynamicplaylist" && !defined $mixInfo{$client}->{'type'};
	
	debugMsg("received command ".(join(' ', @$paramsRef))."\n");

	if (!defined $client) {
		return;
	}
	
	debugMsg("while in mode: ".($mixInfo{$client}->{'type'}).", from ".($client->name)."\n");

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);

	if ($slimCommand eq 'newsong'
		|| $slimCommand eq 'playlist' && $paramsRef->[1] eq 'delete' && $paramsRef->[2] > $songIndex) {

		if(defined $mixInfo{$client}->{'type'}) {
	        if ($::d_plugins) {
				if ($slimCommand eq 'newsong') {
					debugMsg("new song detected ($songIndex)\n");
				} else {
					debugMsg("deletion detected ($paramsRef->[2]");
				}
			}
			
			my $songsToKeep = Slim::Utils::Prefs::get('plugin_dynamicplaylist_number_of_old_tracks');
			if ($songIndex && $songsToKeep ne '') {
				debugMsg("Stripping off completed track(s)\n");

				Slim::Control::Command::clearExecuteCallback(\&commandCallback62);
				# Delete tracks before this one on the playlist
				for (my $i = 0; $i < $songIndex - $songsToKeep; $i++) {
					Slim::Control::Command::execute($client, ['playlist', 'delete', 0]);
				}
				Slim::Control::Command::setExecuteCallback(\&commandCallback62);
			}

			playRandom($client, $mixInfo{$client}->{'type'}, 1, 0);
		}else {
			debugMsg("Ignoring command, no dynamic playlist is playing\n");
		}
	} elsif (($slimCommand eq 'playlist') && exists $stopcommands{$paramsRef->[1]}) {
		if(defined $mixInfo{$client}->{'type'}) {
			debugMsg("cyclic mode ending due to playlist: ".(join(' ', @$paramsRef))." command\n");
			playRandom($client, 'disable');
		}else {
			debugMsg("Ignoring command, no dynamic playlist is playing\n");
		}
	} elsif ( ($slimCommand eq "dynamicplaylist") ) 
	{	
		if(scalar(@$paramsRef) ge 2) {
			if($paramsRef->[1] eq "playlists") {
				cliGetPlaylists62($client,\@$paramsRef);
			}elsif($paramsRef->[1] eq "playlist") {
				if(scalar(@$paramsRef) ge 3) {
					if($paramsRef->[2] eq "play") {
						cliPlayPlaylist62($client,\@$paramsRef);
					}elsif($paramsRef->[2] eq "add") {
						cliAddPlaylist62($client,\@$paramsRef);
					}elsif($paramsRef->[2] eq "stop") {
						cliStopPlaylist62($client,\@$paramsRef);
					}
				}
			}
		}
	}

}

sub commandCallback65 {
	my $request = shift;
	
	my $client = $request->client();

	if (defined($request->source()) && $request->source() eq 'PLUGIN_DYNAMICPLAYLIST') {
		return;
	}elsif(defined($request->source())) {
		debugMsg("received command initiated by".$request->source()."\n");
	}
	debugMsg("received command ".($request->getRequestString())."\n");

	# because of the filter this should never happen
	# in addition there are valid commands (rescan f.e.) that have no
	# client so the bt() is strange here
	if (!defined $client || !defined $mixInfo{$client}->{'type'}) {

		return;
	}
	
	debugMsg("while in mode: ".($mixInfo{$client}->{'type'}).", from ".($client->name)."\n");

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);

	if ($request->isCommand([['playlist'], ['newsong']])
		|| $request->isCommand([['playlist'], ['delete']]) && $request->getParam('_index') > $songIndex) {

        if ($::d_plugins) {
			if ($request->isCommand([['playlist'], ['newsong']])) {
				debugMsg("new song detected ($songIndex)\n");
			} else {
				debugMsg("deletion detected (".($request->getParam('_index')).")\n");
			}
		}
		
		my $songsToKeep = Slim::Utils::Prefs::get('plugin_dynamicplaylist_number_of_old_tracks');
		if ($songIndex && $songsToKeep ne '') {
			debugMsg("Stripping off completed track(s)\n");

			# Delete tracks before this one on the playlist
			for (my $i = 0; $i < $songIndex - $songsToKeep; $i++) {
				my $request = $client->execute(['playlist', 'delete', 0]);
				$request->source('PLUGIN_DYNAMICPLAYLIST');
			}
		}

		playRandom($client, $mixInfo{$client}->{'type'}, 1, 0);
	} elsif ($request->isCommand([['playlist'], [keys %stopcommands]])) {

		debugMsg("cyclic mode ending due to playlist: ".($request->getRequestString())." command\n");
		playRandom($client, 'disable');
	}
}

sub mixable {
        my $class = shift;
        my $item  = shift;
	my $blessed = blessed($item);

	if(!$playListTypes) {
		initPlayListTypes();
	}

	if(!$blessed) {
		return undef;
	}elsif($blessed eq 'Slim::Schema::Track') {
		return 1 if($playListTypes->{'track'});
	}elsif($blessed eq 'Slim::Schema::Year') {
		return 1 if($playListTypes->{'year'} && $item->id);
	}elsif($blessed eq 'Slim::Schema::Album') {
		return 1 if($playListTypes->{'album'});
	}elsif($blessed eq 'Slim::Schema::Age') {
		return 1 if($playListTypes->{'album'});
	}elsif($blessed eq 'Slim::Schema::Contributor') {
		return 1 if($playListTypes->{'artist'});
	}elsif($blessed eq 'Slim::Schema::Genre') {
		return 1 if($playListTypes->{'genre'});
	}elsif($blessed eq 'Slim::Schema::Playlist') {
		return 1 if($playListTypes->{'playlist'});
	}
        return undef;
}


sub mixerFunction {
	my ($client, $noSettings) = @_;
	# look for parentParams (needed when multiple mixers have been used)
	my $paramref = defined $client->param('parentParams') ? $client->param('parentParams') : $client->modeParameterStack(-1);
	if(defined($paramref)) {
		if(!$playListTypes) {
			initPlayListTypes();
		}

		my $listIndex = $paramref->{'listIndex'};
		my $items     = $paramref->{'listRef'};
		my $currentItem = $items->[$listIndex];
		my $hierarchy = $paramref->{'hierarchy'};
		my @levels    = split(",", $hierarchy);
		my $level     = $paramref->{'level'} || 0;
		my $mixerType = $levels[$level];
		if($mixerType eq 'contributor') {
			$mixerType='artist';
		}
		if($mixerType eq 'age') {
			$mixerType='album';
		}
		if($playListTypes->{$mixerType}) { 
			if($mixerType eq 'album') {
				my %p = (
					'id' => $currentItem->id,
					'name' => $currentItem->title
				);
				my %params = (
					'dynamicplaylist_parameter_1' => \%p,
					'playlisttype' => 'album',
					'flatlist' => 1,
					'extrapopmode' => 1
				);
				debugMsg("Calling album playlists with ".$params{'dynamicplaylist_parameter_1'}->{'name'}."(".$params{'dynamicplaylist_parameter_1'}->{'id'}.")\n");
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.DynamicPlayList',\%params);
				$client->update();
			}elsif($mixerType eq 'year') {
				my %p = (
					'id' => $currentItem,
					'name' => $currentItem
				);
				if ($::VERSION ge '6.5') {
					$p{'id'} = $currentItem->id;
					$p{'name'} = $currentItem->name;
				}
				my %params = (
					'dynamicplaylist_parameter_1' => \%p,
					'playlisttype' => 'year',
					'flatlist' => 1,
					'extrapopmode' => 1
				);
				debugMsg("Calling year playlists with ".$params{'dynamicplaylist_parameter_1'}->{'name'}."(".$params{'dynamicplaylist_parameter_1'}->{'id'}.")\n");
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.DynamicPlayList',\%params);
				$client->update();
			}elsif($mixerType eq 'artist') {
				my %p = (
					'id' => $currentItem->id,
					'name' => $currentItem->name
				);
				my %params = (
					'dynamicplaylist_parameter_1' => \%p,
					'playlisttype' => 'artist',
					'flatlist' => 1,
					'extrapopmode' => 1
				);
				debugMsg("Calling artist playlists with ".$params{'dynamicplaylist_parameter_1'}->{'name'}."(".$params{'dynamicplaylist_parameter_1'}->{'id'}.")\n");
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.DynamicPlayList',\%params);
				$client->update();
			}elsif($mixerType eq 'genre') {
				my %p = (
					'id' => $currentItem->id,
					'name' => $currentItem->name
				);
				my %params = (
					'dynamicplaylist_parameter_1' => \%p,
					'playlisttype' => 'genre',
					'flatlist' => 1,
					'extrapopmode' => 1
				);
				debugMsg("Calling album playlists with ".$params{'dynamicplaylist_parameter_1'}->{'name'}."(".$params{'dynamicplaylist_parameter_1'}->{'id'}.")\n");
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.DynamicPlayList',\%params);
				$client->update();
			}elsif($mixerType eq 'playlist') {
				my %p = (
					'id' => $currentItem->id,
					'name' => $currentItem->title
				);
				my %params = (
					'dynamicplaylist_parameter_1' => \%p,
					'playlisttype' => 'playlist',
					'flatlist' => 1,
					'extrapopmode' => 1
				);
				debugMsg("Calling playlist playlists with ".$params{'dynamicplaylist_parameter_1'}->{'name'}."(".$params{'dynamicplaylist_parameter_1'}->{'id'}.")\n");
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.DynamicPlayList',\%params);
				$client->update();
			}else {
				debugMsg("Unknown playlisttype = ".$mixerType."\n");
			}
		}else {
			debugMsg("No playlist found for ".$mixerType."\n");
		}
	}else {
		debugMsg("No parent parameter found\n");
	}

}

sub mixerlink {
    my $item = shift;
    my $form = shift;
    my $descend = shift;
#		debugMsg("***********************************\n");
#		for my $it (keys %$form) {
#			debugMsg("form{$it}=".$form->{$it}."\n");
#		}
#		debugMsg("***********************************\n");
	
	my $levelName = $form->{'levelName'};
	if(!$playListTypes) {
		initPlayListTypes();
	}
	if($form->{'noDynamicPlayListButton'}) {
		if ($::VERSION lt '6.5') {
    		Slim::Web::Pages::addLinks("mixer", {'DYNAMICPLAYLIST' => undef});
    	}
	}elsif(defined($levelName) && ($levelName eq 'artist' || $levelName eq 'contributor' || $levelName eq 'album' || $levelName eq 'genre' || $levelName eq 'playlist')) {
		if($levelName eq 'contributor') {
			$levelName = 'artist';
		}
		if($playListTypes->{$levelName}) {
			$form->{'dynamicplaylist_playlisttype'} = $levelName;
			if ($::VERSION ge '6.5') {
	        	$form->{'mixerlinks'}{'DYNAMICPLAYLIST'} = "plugins/DynamicPlayList/mixerlink65.html";
	        }else {
	    			Slim::Web::Pages::addLinks("mixer", {'DYNAMICPLAYLIST' => "plugins/DynamicPlayList/mixerlink.html"}, 1);
	        }
	    }else {
	    	if ($::VERSION lt '6.5') {
	    		Slim::Web::Pages::addLinks("mixer", {'DYNAMICPLAYLIST' => undef});
	    	}
	    }
    }elsif(defined($levelName) && $levelName eq 'year') {
		$form->{'dynamicplaylist_playlisttype'} = $levelName;
	    	$form->{'yearid'} = $item->id;
    	if(defined($form->{'yearid'})) {
			if($playListTypes->{$levelName}) {
				if ($::VERSION ge '6.5') {
	    			$form->{'mixerlinks'}{'DYNAMICPLAYLIST'} = "plugins/DynamicPlayList/mixerlink65.html";
	    		}else {
	    			Slim::Web::Pages::addLinks("mixer", {'DYNAMICPLAYLIST' => "plugins/DynamicPlayList/mixerlink.html"}, 1);
	    		}
		    }else {
		    	if ($::VERSION lt '6.5') {
		    		Slim::Web::Pages::addLinks("mixer", {'DYNAMICPLAYLIST' => undef});
		    	}
		    }
    	}
    }else {
    	my $attributes = $form->{'attributes'};
		my $album;
    	my $playlist = undef;
    	if(defined($attributes) && $attributes =~ /\&?playlist=(\d+)/) {
    		$playlist = $1;
    	}elsif(defined($attributes) && $attributes =~ /\&?playlist\.id=(\d+)/) {
    		$playlist = $1;
    	}
    	if(defined($playlist)) {
    		$form->{'playlist'} = $playlist;
    	}else {
    		my $album;
			if(defined($form->{'levelName'}) && $form->{'levelName'} eq 'age') {
				$form->{'dynamicplaylist_playlisttype'} = 'album';
				$form->{'albumid'} = $item->id;
			}
		}
	
    	if(defined($form->{'albumid'}) || defined($form->{'playlist'})) {
			if($playListTypes->{$form->{'dynamicplaylist_playlisttype'}}) {
				if ($::VERSION ge '6.5') {
	    			$form->{'mixerlinks'}{'DYNAMICPLAYLIST'} = "plugins/DynamicPlayList/mixerlink65.html";
	    		}else {
	    			Slim::Web::Pages::addLinks("mixer", {'DYNAMICPLAYLIST' => "plugins/DynamicPlayList/mixerlink.html"}, 1);
	    		}
	    	}else {
		    	if ($::VERSION lt '6.5') {
		    		Slim::Web::Pages::addLinks("mixer", {'DYNAMICPLAYLIST' => undef});
		    	}
	    	}
    	}
    }
    return $form;
}

sub initPlugin {
	my $class = shift;
	
	# playlist commands that will stop random play
	%stopcommands = (
		'clear'		 => 1,
		'loadtracks' => 1, # multiple play
		'playtracks' => 1, # single play
		'load'		 => 1, # old style url load (no play)
		'play'		 => 1, # old style url play
		'loadalbum'	 => 1, # old style multi-item load
		'playalbum'	 => 1, # old style multi-item play
	);
	
	checkDefaults();
	initDatabase();
	clearPlayListHistory();
	Slim::Buttons::Common::addMode('PLUGIN.DynamicPlayList.ChooseParameters', getFunctions(), \&setModeChooseParameters);
	Slim::Buttons::Common::addMode('PLUGIN.DynamicPlayList', getFunctions(), \&setMode);
	
		my %mixerMap = ();
		if(Slim::Utils::Prefs::get("plugin_dynamicplaylist_web_show_mixerlinks")) {
			$mixerMap{'mixerlink'} = \&mixerlink;
		}
		if(Slim::Utils::Prefs::get("plugin_dynamicplaylist_enable_mixerfunction")) {
			$mixerMap{'mixer'} = \&mixerFunction;
		}
		if(Slim::Utils::Prefs::get("plugin_dynamicplaylist_web_show_mixerlinks") ||
			Slim::Utils::Prefs::get("plugin_dynamicplaylist_enable_mixerfunction")) {

			if ($::VERSION ge '6.5') {
				Slim::Music::Import->addImporter($class, \%mixerMap);
			    	Slim::Music::Import->useImporter('Plugins::DynamicPlayList::Plugin', 1);
			}else {
				Slim::Music::Import::addImporter('DYNAMICPLAYLIST', \%mixerMap);
			    	Slim::Music::Import::useImporter('DYNAMICPLAYLIST', 1);
			}
		}

	if ($::VERSION ge '6.5') {
		# set up our subscription
		Slim::Control::Request::subscribe(\&commandCallback65, 
			[['playlist'], ['newsong', 'delete', keys %stopcommands]]);
		Slim::Control::Request::addDispatch(['dynamicplaylist','playlists','_all'], [1, 1, 0, \&cliGetPlaylists]);
		Slim::Control::Request::addDispatch(['dynamicplaylist','playlist','play', '_playlistid'], [1, 0, 0, \&cliPlayPlaylist]);
		Slim::Control::Request::addDispatch(['dynamicplaylist','playlist','add', '_playlistid'], [1, 0, 0, \&cliAddPlaylist]);
		Slim::Control::Request::addDispatch(['dynamicplaylist','playlist','stop'], [1, 0, 0, \&cliStopPlaylist]);
	}else {
		Slim::Control::Command::setExecuteCallback(\&commandCallback62);
	}
	initFilters();
}
sub title {
	return 'DYNAMICPLAYLIST';
}

sub initDatabase {
	$driver = Slim::Utils::Prefs::get('dbsource');
    $driver =~ s/dbi:(.*?):(.*)$/$1/;
	my $dbh = getCurrentDBH();
	my $st = $dbh->table_info();
	my $tblexists;
	while (my ( $qual, $owner, $table, $type ) = $st->fetchrow_array()) {
		if($table eq "dynamicplaylist_history") {
			$tblexists=1;
		}
	}
	unless ($tblexists) {
		debugMsg("Create database table\n");
		executeSQLFile("dbcreate.sql");
	}
	eval { $dbh->do("select skipped from dynamicplaylist_history limit 1;") };
	if ($@) {
		debugMsg("Create database table column skipped in dynamicplaylist_history\n");
		executeSQLFile("dbupgrade_skipped.sql");
	}

}

sub shutdownPlugin {
	if ($::VERSION ge '6.5') {
		Slim::Control::Request::unsubscribe(\&commandCallback65);
	}else {
		Slim::Control::Command::clearExecuteCallback(\&commandCallback62);
	}
	if(Slim::Utils::Prefs::get("plugin_dynamicplaylist_web_show_mixerlinks") ||
		Slim::Utils::Prefs::get("plugin_dynamicplaylist_enable_mixerfunction")) {
		if ($::VERSION ge '6.5') {
			Slim::Music::Import->useImporter('Plugins::DynamicPlayList::Plugin', 0);
		}else {
			Slim::Music::Import::useImporter('DYNAMICPLAYLIST', 0);
		}
	}
}

sub webPages {

	my %pages = (
		"dynamicplaylist_list\.(?:htm|xml)"     => \&handleWebList,
		"dynamicplaylist_mix\.(?:htm|xml)"      => \&handleWebMix,
		"dynamicplaylist_mixparameters\.(?:htm|xml)"	=> \&handleWebMixParameters,
		"dynamicplaylist_settings\.(?:htm|xml)" => \&handleWebSettings,
		"dynamicplaylist_selectplaylists\.(?:htm|xml)" => \&handleWebSelectPlaylists,
		"dynamicplaylist_saveselectplaylists\.(?:htm|xml)" => \&handleWebSaveSelectPlaylists,
		"dynamicplaylist_selectfilters\.(?:htm|xml)" => \&handleWebSelectFilters,
		"dynamicplaylist_saveselectfilters\.(?:htm|xml)" => \&handleWebSaveSelectFilters,
	);

	my $value = $htmlTemplate;

	if (grep { /^DynamicPlayList::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

		$value = undef;
	} 

	#Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_DYNAMICPLAYLIST' => $value });

	return (\%pages,$value);
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	# Pass on the current pref values and now playing info
	initFilters();
	initPlayLists($client);
	initPlayListTypes();
	my $playlist = undef;
	if(defined($client) && defined($mixInfo{$client}) && defined($mixInfo{$client}->{'type'})) {
		$playlist = getPlayList($client,$mixInfo{$client}->{'type'});
	}
	my $name = undef;
	if($playlist) {
		$name = $playlist->{'name'};
	}
	$params->{'pluginDynamicPlayListContext'} = getPlayListContext($client,$params,$playListItems,1);
	$params->{'pluginDynamicPlayListGroups'} = getPlayListGroupsForContext($client,$params,$playListItems,1);
	$params->{'pluginDynamicPlayListPlayLists'} = getPlayListsForContext($client,$params,$playListItems,1,$params->{'playlisttype'});
	$params->{'pluginDynamicPlayListContextName'} = getPlayListFilterDescription($client,$params);
	$params->{'pluginDynamicPlayListNumTracks'} = Slim::Utils::Prefs::get('plugin_dynamicplaylist_number_of_tracks');
	$params->{'pluginDynamicPlayListNumOldTracks'} = Slim::Utils::Prefs::get('plugin_dynamicplaylist_number_of_old_tracks');
	$params->{'pluginDynamicPlayListContinuousMode'} = Slim::Utils::Prefs::get('plugin_dynamicplaylist_keep_adding_tracks');
	$params->{'pluginDynamicPlayListNowPlaying'} = $name;
	if ($::VERSION ge '6.5') {
		$params->{'pluginDynamicPlayListSlimserver65'} = 1;
	}
	$params->{'pluginDynamicPlayListVersion'} = $PLUGINVERSION;
	
	return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
}

# Handles play requests from plugin's web page
sub handleWebMix {
	my ($client, $params) = @_;
	if (defined $client && $params->{'type'}) {
		my $playlist = getPlayList($client,$params->{'type'});
		if(!defined($playlist)) {
			debugMsg("Playlist not found:".$params->{'type'}."\n");
		}elsif(defined($playlist->{'parameters'})) {
			return handleWebMixParameters($client,$params);
		}else {
			playRandom($client, $params->{'type'}, $params->{'addOnly'}, 1, 1);
		}
	}
	return handleWebList($client, $params);
}

sub handleWebMixParameters {
	my ($client,$params) = @_;
	debugMsg("Entering handleWebMixParameters\n");
	my $parameterId = 1;
	my @parameters = ();
	my $playlist = getPlayList($client,$params->{'type'});
	
	my $i=1;
	while(defined($params->{'dynamicplaylist_parameter_'.$i})) {
		$parameterId = $parameterId +1;
		my %value = (
			'id' => $params->{'dynamicplaylist_parameter_'.$i}
		);
		$client->param('dynamicplaylist_parameter_'.$i,\%value);
		debugMsg("Storing parameter $i=".$value{'id'}."\n");

		if($params->{'dynamicplaylist_parameter_changed'} eq $i) {
			last;
		}
		$i++;
	}
	if(defined($playlist->{'parameters'}->{$parameterId})) {
		for(my $i=1;$i<$parameterId;$i++) {
			my @parameterValues = ();
			my $parameter = $playlist->{'parameters'}->{$i};
			addParameterValues($client,\@parameterValues,$parameter);
			my %webParameter = (
				'parameter' => $parameter,
				'values' => \@parameterValues,
				'value' => $params->{'dynamicplaylist_parameter_'.$i}
			);
			push @parameters,\%webParameter;
		}
		
		my $parameter = $playlist->{'parameters'}->{$parameterId};
		debugMsg("Getting values for: ".$parameter->{'name'}."\n");
		my @parameterValues = ();
		addParameterValues($client,\@parameterValues,$parameter);
		my %currentParameter = (
			'parameter' => $parameter,
			'values' => \@parameterValues
		);
		push @parameters,\%currentParameter;
		$params->{'pluginDynamicPlayListPlaylist'} = $playlist;
		$params->{'pluginDynamicPlayListPlaylistId'} = $params->{'type'};
		$params->{'pluginDynamicPlayListAddOnly'} = $params->{'addOnly'};
		$params->{'pluginDynamicPlayListMixParameters'} = \@parameters;
		my $currentPlaylistId = getCurrentPlayList($client);
		if(defined($currentPlaylistId)) {
			debugMsg("Setting current playlist id to ".$currentPlaylistId."\n");
			my $currentPlaylist = getPlayList($client,$currentPlaylistId);
			if(defined($currentPlaylist)) {
				debugMsg("Setting current playlist to ".$currentPlaylist->{'name'}."\n");
				$params->{'pluginDynamicPlayListNowPlaying'} = $currentPlaylist->{'name'};
			}
		}
		if ($::VERSION ge '6.5') {
			$params->{'pluginDynamicPlayListSlimserver65'} = 1;
		}
		debugMsg("Exiting handleWebMixParameters\n");
		return Slim::Web::HTTP::filltemplatefile('plugins/DynamicPlayList/dynamicplaylist_mixparameters.html', $params);
	}else {
		for(my $i=1;$i<$parameterId;$i++) {
			$playlist->{'parameters'}->{$i}->{'value'} = $client->param('dynamicplaylist_parameter_'.$i)->{'id'};
		}
		playRandom($client, $params->{'type'}, $params->{'addOnly'}, 1, 1);
		debugMsg("Exiting handleWebMixParameters\n");
		return handleWebList($client,$params);
	}
}

# Handles settings changes from plugin's web page
sub handleWebSettings {
	my ($client, $params) = @_;

	if ($params->{'numTracks'} =~ /^[0-9]+$/) {
		Slim::Utils::Prefs::set('plugin_dynamicplaylist_number_of_tracks', $params->{'numTracks'});
	} else {
		debugMsg("Invalid value for numTracks\n");
	}
	if ($params->{'numOldTracks'} eq '' || $params->{'numOldTracks'} =~ /^[0-9]+$/) {
		Slim::Utils::Prefs::set('plugin_dynamicplaylist_number_of_old_tracks', $params->{'numOldTracks'});	
	} else {
		debugMsg("Invalid value for numOldTracks\n");
	}
	Slim::Utils::Prefs::set('plugin_dynamicplaylist_keep_adding_tracks', $params->{'continuousMode'} ? 1 : 0);

	# Pass on to check if the user requested a new mix as well
	handleWebMix($client, $params);
}

# Draws the plugin's select playlist web page
sub handleWebSelectPlaylists {
	my ($client, $params) = @_;

	# Pass on the current pref values and now playing info
	initPlayLists($client);
	initPlayListTypes();
	my $playlist = getPlayList($client,$mixInfo{$client}->{'type'});
	my $name = undef;
	if($playlist) {
		$name = $playlist->{'name'};
	}
	$params->{'pluginDynamicPlayListPlayLists'} = $playLists;
	my @groupPath = ();
	my @groupResult = ();
	$params->{'pluginDynamicPlayListGroups'} = getPlayListGroups(\@groupPath,$playListItems,\@groupResult);
	$params->{'pluginDynamicPlayListNowPlaying'} = $name;
	if ($::VERSION ge '6.5') {
		$params->{'pluginDynamicPlayListSlimserver65'} = 1;
	}
	
	return Slim::Web::HTTP::filltemplatefile('plugins/DynamicPlayList/dynamicplaylist_selectplaylists.html', $params);
}

sub handleWebSelectFilters {
	my ($client, $params) = @_;

	# Pass on the current pref values and now playing info
	initFilters();
	initPlayLists($client);
	initPlayListTypes();
	my $playlist = getPlayList($client,$mixInfo{$client}->{'type'});
	my $name = undef;
	if($playlist) {
		$name = $playlist->{'name'};
	}
	$params->{'pluginDynamicPlayListNowPlaying'} = $name;
	if ($::VERSION ge '6.5') {
		$params->{'pluginDynamicPlayListSlimserver65'} = 1;
	}
	$params->{'pluginDynamicPlayListFilters'} = $filters;
	if ($::VERSION ge '6.5') {
		$params->{'pluginDynamicPlayListSlimserver65'} = 1;
	}
	
	return Slim::Web::HTTP::filltemplatefile('plugins/DynamicPlayList/dynamicplaylist_selectfilters.html', $params);
}
sub getPlayListContext {
	my $client = shift;
	my $params = shift;
	my $currentItems = shift;
	my $level = shift;
	my @result = ();
	debugMsg("Get playlist context for level=$level\n");
	if(defined($params->{'group'.$level})) {
		my $group = unescape($params->{'group'.$level});
		debugMsg("Getting group: $group\n");
		my $item = $currentItems->{'dynamicplaylistgroup_'.$group};
		if(defined($item) && !defined($item->{'playlist'})) {
			my $currentUrl = "&group".$level."=".escape($group);
			my %resultItem = (
				'url' => $currentUrl,
				'name' => $group,
				'dynamicplaylistenabled' => $item->{'dynamicplaylistenabled'}
			);
			debugMsg("Adding context: $group\n");
			push @result, \%resultItem;

			if(defined($item->{'childs'})) {
				my $childResult = getPlayListContext($client,$params,$item->{'childs'},$level+1);
				for my $child (@$childResult) {
					$child->{'url'} = $currentUrl.$child->{'url'};
					debugMsg("Adding child context: ".$child->{'name'}."\n");
					push @result,$child;
				}
			}
		}
	}
	return \@result;
}

sub getPlayListFilterDescription {
	my $client = shift;
	my $params = shift;
	if(defined($params->{'playlisttype'})) {
		my $parameter1 = $params->{'dynamicplaylist_parameter_1'};
		if(defined($parameter1)) {
			if($params->{'playlisttype'} eq 'album') {
				my $album = objectForId('album',$parameter1);
				if(defined($album)) {
					return $album->title;
				}
			}elsif($params->{'playlisttype'} eq 'artist') {
				my $artist = objectForId('artist',$parameter1);
				if(defined($artist)) {
					return $artist->name;
				}
			}elsif($params->{'playlisttype'} eq 'genre') {
				my $genre = objectForId('genre',$parameter1);
				if(defined($genre)) {
					return $genre->name;
				}
			}elsif($params->{'playlisttype'} eq 'year') {
				return $parameter1;
			}elsif($params->{'playlisttype'} eq 'playlist') {
				my $playlist = objectForId('playlist',$parameter1);
				if(defined($playlist)) {
					return $playlist->title;
				}
			}
		}
	}
	return undef;
}
sub getPlayListGroupsForContext {
	my $client = shift;
	my $params = shift;
	my $currentItems = shift;
	my $level = shift;
	my @result = ();
	
	if(Slim::Utils::Prefs::get('plugin_dynamicplaylist_flatlist') || $params->{'flatlist'}) {
		return \@result;
	}

	if(defined($params->{'group'.$level})) {
		my $group = unescape($params->{'group'.$level});
		debugMsg("Getting group: $group\n");
		my $item = $currentItems->{'dynamicplaylistgroup_'.$group};
		if(defined($item) && !defined($item->{'playlist'})) {
			if(defined($item->{'childs'})) {
				return getPlayListGroupsForContext($client,$params,$item->{'childs'},$level+1);
			}else {
				return \@result;
			}
		}
	}else {
		my $currentLevel;
		my $url = "";
		for ($currentLevel=1;$currentLevel<$level;$currentLevel++) {
			$url.="&group".$currentLevel."=".$params->{'group'.$currentLevel};
		}
		for my $itemKey (keys %$currentItems) {
			my $item = $currentItems->{$itemKey};
			if(!defined($item->{'playlist'}) && defined($item->{'name'})) {
				my $currentUrl = $url."&group".$level."=".escape($item->{'name'});
				my %resultItem = (
					'url' => $currentUrl,
					'name' => $item->{'name'},
					'dynamicplaylistenabled' => $item->{'dynamicplaylistenabled'}
				);
				debugMsg("Adding group: $itemKey\n");
				push @result, \%resultItem;
			}
		}
	}
	@result = sort { $a->{'name'} cmp $b->{'name'} } @result;
	return \@result;
}

sub getPlayListsForContext {
	my $client = shift;
	my $params = shift;
	my $currentItems = shift;
	my $level = shift;
	my $playlisttype = shift;
	my @result = ();
	
	if(Slim::Utils::Prefs::get('plugin_dynamicplaylist_flatlist') || $params->{'flatlist'}) {
		foreach my $itemKey (keys %$playLists) {
			my $playlist = $playLists->{$itemKey};
			if(!defined($playlisttype) || (defined($playlist->{'parameters'}) && defined($playlist->{'parameters'}->{'1'}) && $playlist->{'parameters'}->{'1'}->{'type'} eq $playlisttype)) {
				debugMsg("Adding playlist: $itemKey\n");
				push @result, $playlist;
			}
		}
	}else {
		if(defined($params->{'group'.$level})) {
			my $group = unescape($params->{'group'.$level});
			debugMsg("Getting group: $group\n");
			my $item = $currentItems->{'dynamicplaylistgroup_'.$group};
			if(defined($item) && !defined($item->{'playlist'})) {
				if(defined($item->{'childs'})) {
					return getPlayListsForContext($client,$params,$item->{'childs'},$level+1);
				}else {
					return \@result;
				}
			}
		}else {
			for my $itemKey (keys %$currentItems) {
				my $item = $currentItems->{$itemKey};
				if(defined($item->{'playlist'})) {
					my $playlist = $item->{'playlist'};
					if(!defined($playlisttype) || (defined($playlist->{'parameters'}) && defined($playlist->{'parameters'}->{'1'}) && $playlist->{'parameters'}->{'1'}->{'type'} eq $playlisttype)) {
						debugMsg("Adding playlist: $itemKey\n");
						push @result, $item->{'playlist'};
					}
				}
			}
		}
	}
	@result = sort { $a->{'name'} cmp $b->{'name'} } @result;
	return \@result;
}

sub getPlayListGroups {
	my $path = shift;
	my $items = shift;
	my $result = shift;
	for my $key (keys %$items) {
		my $item = $items->{$key};
		if(!defined($item->{'playlist'}) && defined($item->{'name'})) {
			my $groupName = undef;
			my $groupId = "";
			for my $pathItem (@$path) {
				if(defined($groupName)) {
					$groupName .= "/";
				}else {
					$groupName = "";
				}
				$groupName .= $pathItem;
				$groupId .= "_".$pathItem;
			}
			if(defined($groupName)) {
				$groupName .= "/";
			}else {
				$groupName = "";
			}
			my %resultItem = (
				'id' => escape($groupId."_".$item->{'name'}),
				'name' => $groupName.$item->{'name'}."/",
				'dynamicplaylistenabled' => $item->{'dynamicplaylistenabled'}
			);
			push @$result,\%resultItem;
			my $childs = $item->{'childs'};
			if(defined($childs)) {
				my @childpath = ();
				for my $childPathItem (@$path) {
					push @childpath,$childPathItem;
				}
				push @childpath,$item->{'name'};
				$result = getPlayListGroups(\@childpath,$childs,$result);
			}
		}
	}
	if($result) {
		my @temp = sort { $a->{'name'} cmp $b->{'name'} } @$result;
		$result = \@temp;
		debugMsg("Got sorted array: $result\n");
	}
	return $result;
}
# Draws the plugin's web page
sub handleWebSaveSelectPlaylists {
	my ($client, $params) = @_;

	initPlayLists($client);
	initPlayListTypes();
	my $first = 1;
	my $sql = '';
	foreach my $playlist (keys %$playLists) {
		my $playlistid = "playlist_".$playLists->{$playlist}{'dynamicplaylistid'};
		if($params->{$playlistid}) {
			Slim::Utils::Prefs::delete('plugin_dynamicplaylist_playlist_'.$playlist.'_enabled');
		}else {
			Slim::Utils::Prefs::set('plugin_dynamicplaylist_playlist_'.$playlist.'_enabled',0);
		}
		my $playlistfavouriteid = "playlistfavourite_".$playLists->{$playlist}{'dynamicplaylistid'};
		if($params->{$playlistfavouriteid}) {
			Slim::Utils::Prefs::set('plugin_dynamicplaylist_playlist_'.$playlist.'_favourite',1);
		}else {
			Slim::Utils::Prefs::delete('plugin_dynamicplaylist_playlist_'.$playlist.'_favourite');
		}
	}
	
	savePlayListGroups($playListItems,$params,"");

	handleWebList($client, $params);
}

sub handleWebSaveSelectFilters {
	my ($client, $params) = @_;

	initFilters();
	my $first = 1;
	my $sql = '';
	foreach my $key (keys %$filters) {
		my $filterid = "filter_".$filters->{$key}{'dynamicplaylistfilterid'};
		if($params->{$filterid}) {
			Slim::Utils::Prefs::set('plugin_dynamicplaylist_filter_'.$key.'_enabled',1);
		}else {
			Slim::Utils::Prefs::set('plugin_dynamicplaylist_filter_'.$key.'_enabled',0);
		}
	}
	
	handleWebList($client, $params);
}

sub savePlayListGroups {
	my $items = shift;
	my $params = shift;
	my $path = shift;
	
	foreach my $itemKey (keys %$items) {
		my $item = $items->{$itemKey};
		if(!defined($item->{'playlist'}) && defined($item->{'name'})) {
			my $groupid = escape($path)."_".escape($item->{'name'});
			my $playlistid = "playlist_".$groupid;
			if($params->{$playlistid}) {
				#debugMsg("Saving: plugin_dynamicplaylist_playlist_".escape($path)."_".escape($itemKey)."_enabled=1\n");
				Slim::Utils::Prefs::set('plugin_dynamicplaylist_playlist_group_'.$groupid.'_enabled',1);
			}else {
				#debugMsg("Saving: plugin_dynamicplaylist_playlist_".escape($path)."_".escape($itemKey)."_enabled=0\n");
				Slim::Utils::Prefs::set('plugin_dynamicplaylist_playlist_group_'.$groupid.'_enabled',0);
			}
			if(defined($item->{'childs'})) {
				savePlayListGroups($item->{'childs'},$params,$path."_".$item->{'name'});
			}
		}
	}
}

sub getFunctions {
	# Functions to allow mapping of mixes to keypresses
	return {
		'up' => sub  {
			my $client = shift;
			$client->bumpUp();
		},
		'down' => sub  {
			my $client = shift;
			$client->bumpDown();
		},
		'left' => sub  {
			my $client = shift;
			Slim::Buttons::Common::popModeRight($client);
		},
		'right' => sub  {
			my $client = shift;
			$client->bumpRight();
		}
	}
}

sub checkDefaults {
	my $prefVal = Slim::Utils::Prefs::get('plugin_dynamicplaylist_number_of_tracks');
	if (! defined $prefVal || $prefVal !~ /^[0-9]+$/) {
		debugMsg("Defaulting plugin_dynamicplaylist_number_of_tracks to 10\n");
		Slim::Utils::Prefs::set('plugin_dynamicplaylist_number_of_tracks', 10);
	}
	
	$prefVal = Slim::Utils::Prefs::get('plugin_dynamicplaylist_skipped_tracks_retries');
	if (! defined $prefVal || $prefVal !~ /^$|^[0-9]+$/) {
		# Default to keeping all tracks
		debugMsg("Defaulting plugin_dynamicplaylist_skipped_tracks_retries to 20\n");
		Slim::Utils::Prefs::set('plugin_dynamicplaylist_skipped_tracks_retries', 20);
	}

	$prefVal = Slim::Utils::Prefs::get('plugin_dynamicplaylist_number_of_old_tracks');
	if (! defined $prefVal || $prefVal !~ /^$|^[0-9]+$/) {
		# Default to keeping all tracks
		debugMsg("Defaulting plugin_dynamicplaylist_number_of_old_tracks to ''\n");
		Slim::Utils::Prefs::set('plugin_dynamicplaylist_number_of_old_tracks', '');
	}

	if (! defined Slim::Utils::Prefs::get('plugin_dynamicplaylist_keep_adding_tracks')) {
		# Default to continous mode
		debugMsg("Defaulting plugin_dynamicplaylist_keep_adding_tracks to 1\n");
		Slim::Utils::Prefs::set('plugin_dynamicplaylist_keep_adding_tracks', 1);
	}

	$prefVal = Slim::Utils::Prefs::get('plugin_dynamicplaylist_showmessages');
	if (! defined $prefVal) {
		# Default to standard playlist directory
		debugMsg("Defaulting plugin_dynamicplaylist_showmessages to 0\n");
		Slim::Utils::Prefs::set('plugin_dynamicplaylist_showmessages', 0);
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_dynamicplaylist_includesavedplaylists');
	if (! defined $prefVal) {
		# Default to standard playlist directory
		debugMsg("Defaulting plugin_dynamicplaylist_includesavedplaylists to 1\n");
		Slim::Utils::Prefs::set('plugin_dynamicplaylist_includesavedplaylists', 1);
	}

	$prefVal = Slim::Utils::Prefs::get('plugin_dynamicplaylist_randomsavedplaylists');
	if (! defined $prefVal) {
		# Default to standard playlist directory
		debugMsg("Defaulting plugin_dynamicplaylist_randomsavedplaylists to 0\n");
		Slim::Utils::Prefs::set('plugin_dynamicplaylist_randomsavedplaylists', 0);
	}

	$prefVal = Slim::Utils::Prefs::get('plugin_dynamicplaylist_fullsavedplaylists');
	if (! defined $prefVal) {
		# Default to standard playlist directory
		debugMsg("Defaulting plugin_dynamicplaylist_fullsavedplaylists to 0\n");
		Slim::Utils::Prefs::set('plugin_dynamicplaylist_fullsavedplaylists', 0);
	}

	$prefVal = Slim::Utils::Prefs::get('plugin_dynamicplaylist_ungrouped');
	if (! defined $prefVal) {
		# Default to show ungrouped playlists on top
		debugMsg("Defaulting plugin_dynamicplaylist_ungrouped to ''\n");
		Slim::Utils::Prefs::set('plugin_dynamicplaylist_ungrouped', '');
	}

	$prefVal = Slim::Utils::Prefs::get('plugin_dynamicplaylist_flatlist');
	if (! defined $prefVal) {
		# Default to strurctured playlists
		debugMsg("Defaulting plugin_dynamicplaylist_flatlist to 0\n");
		Slim::Utils::Prefs::set('plugin_dynamicplaylist_flatlist', 0);
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_dynamicplaylist_structured_savedplaylists');
	if (! defined $prefVal) {
		# Default to structured playlists for saved playlists
		debugMsg("Defaulting plugin_dynamicplaylist_structured_savedplaylists to true\n");
		Slim::Utils::Prefs::set('plugin_dynamicplaylist_structured_savedplaylists', 1);
	}
	
	# enable mixer links by default
	if(!defined(Slim::Utils::Prefs::get("plugin_dynamicplaylist_web_show_mixerlinks"))) {
		# Default to show mixer links
		debugMsg("Defaulting plugin_dynamicplaylist_web_show_mixerlinks to 1\n");
		Slim::Utils::Prefs::set("plugin_dynamicplaylist_web_show_mixerlinks",1);
	}

	# enable mixer function by default
	if(!defined(Slim::Utils::Prefs::get("plugin_dynamicplaylist_enable_mixerfunction"))) {
		# Default to show mixer links
		debugMsg("Defaulting plugin_dynamicplaylist_enable_mixerfunction to 1\n");
		Slim::Utils::Prefs::set("plugin_dynamicplaylist_enable_mixerfunction",1);

	}
	if(!defined(Slim::Utils::Prefs::get("plugin_dynamicplaylist_favouritesname"))) {
		debugMsg("Defaulting plugin_dynamicplaylist_favouritesname to ".string('PLUGIN_DYNAMICPLAYLIST_FAVOURITES')."\n");
		Slim::Utils::Prefs::set("plugin_dynamicplaylist_favouritesname",string('PLUGIN_DYNAMICPLAYLIST_FAVOURITES'));
	}

}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_dynamicplaylist_number_of_tracks','plugin_dynamicplaylist_number_of_old_tracks','plugin_dynamicplaylist_skipped_tracks_retries','plugin_dynamicplaylist_ungrouped','plugin_dynamicplaylist_flatlist','plugin_dynamicplaylist_includesavedplaylists','plugin_dynamicplaylist_web_show_mixerlinks','plugin_dynamicplaylist_enable_mixerfunction','plugin_dynamicplaylist_structured_savedplaylists','plugin_dynamicplaylist_randomsavedplaylists','plugin_dynamicplaylist_fullsavedplaylists','plugin_dynamicplaylist_favouritesname','plugin_dynamicplaylist_showmessages'],
	 GroupHead => string('PLUGIN_DYNAMICPLAYLIST_SETUP_GROUP'),
	 GroupDesc => string('PLUGIN_DYNAMICPLAYLIST_SETUP_GROUP_DESC'),
	 GroupLine => 1,
	 GroupSub  => 1,
	 Suppress_PrefSub  => 1,
	 Suppress_PrefLine => 1
	);
	my %setupPrefs =
	(
	plugin_dynamicplaylist_showmessages => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_DYNAMICPLAYLIST_SHOW_MESSAGES')
			,'changeIntro' => string('PLUGIN_DYNAMICPLAYLIST_SHOW_MESSAGES')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_dynamicplaylist_showmessages"); }
		},		
	plugin_dynamicplaylist_includesavedplaylists => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_DYNAMICPLAYLIST_INCLUDE_SAVED_PLAYLISTS')
			,'changeIntro' => string('PLUGIN_DYNAMICPLAYLIST_INCLUDE_SAVED_PLAYLISTS')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_dynamicplaylist_includesavedplaylists"); }
		},		
	plugin_dynamicplaylist_randomsavedplaylists => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_DYNAMICPLAYLIST_RANDOM_SAVED_PLAYLISTS')
			,'changeIntro' => string('PLUGIN_DYNAMICPLAYLIST_RANDOM_SAVED_PLAYLISTS')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_dynamicplaylist_randomsavedplaylists"); }
		},		
	plugin_dynamicplaylist_fullsavedplaylists => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_DYNAMICPLAYLIST_FULL_SAVED_PLAYLISTS')
			,'changeIntro' => string('PLUGIN_DYNAMICPLAYLIST_FULL_SAVED_PLAYLISTS')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_dynamicplaylist_fullsavedplaylists"); }
		},		
	plugin_dynamicplaylist_number_of_tracks => {
			'validate' => \&validateIntWrapper
			,'PrefChoose' => string('PLUGIN_DYNAMICPLAYLIST_NUMBER_OF_TRACKS')
			,'changeIntro' => string('PLUGIN_DYNAMICPLAYLIST_NUMBER_OF_TRACKS')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_dynamicplaylist_number_of_tracks"); }
		},
	plugin_dynamicplaylist_skipped_tracks_retries => {
			'validate' => \&validateIntWrapper
			,'PrefChoose' => string('PLUGIN_DYNAMICPLAYLIST_NUMBER_OF_SKIPPED_TRACKS_RETRIES')
			,'changeIntro' => string('PLUGIN_DYNAMICPLAYLIST_NUMBER_OF_SKIPPED_TRACKS_RETRIES')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_dynamicplaylist_skipped_tracks_retries"); }
		},
	plugin_dynamicplaylist_number_of_old_tracks => {
			'validate' => \&validateIntOrEmpty
			,'PrefChoose' => string('PLUGIN_DYNAMICPLAYLIST_NUMBER_OF_OLD_TRACKS')
			,'changeIntro' => string('PLUGIN_DYNAMICPLAYLIST_NUMBER_OF_OLD_TRACKS')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_dynamicplaylist_number_of_old_tracks"); }
		},
	plugin_dynamicplaylist_flatlist => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_DYNAMICPLAYLIST_FLATLIST')
			,'changeIntro' => string('PLUGIN_DYNAMICPLAYLIST_FLATLIST')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_dynamicplaylist_flatlist"); }
		},		
	plugin_dynamicplaylist_structured_savedplaylists => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_DYNAMICPLAYLIST_STRUCTURED_SAVEDPLAYLISTS')
			,'changeIntro' => string('PLUGIN_DYNAMICPLAYLIST_STRUCTURED_SAVEDPLAYLISTS')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_dynamicplaylist_structured_savedplaylists"); }
		},	
	plugin_dynamicplaylist_ungrouped => {
			'validate' => \&validateAcceptAllWrapper
			,'PrefChoose' => string('PLUGIN_DYNAMICPLAYLIST_UNGROUPED')
			,'changeIntro' => string('PLUGIN_DYNAMICPLAYLIST_UNGROUPED')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_dynamicplaylist_ungrouped"); }
			,'PrefSize' => 'large'
		},
	plugin_dynamicplaylist_web_show_mixerlinks => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_DYNAMICPLAYLIST_WEB_SHOW_MIXERLINKS')
			,'changeIntro' => string('PLUGIN_DYNAMICPLAYLIST_WEB_SHOW_MIXERLINKS')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_dynamicplaylist_web_show_mixerlinks"); }
		},
	plugin_dynamicplaylist_enable_mixerfunction => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_DYNAMICPLAYLIST_ENABLE_MIXERFUNCTION')
			,'changeIntro' => string('PLUGIN_DYNAMICPLAYLIST_ENABLE_MIXERFUNCTION')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_dynamicplaylist_enable_mixerfunction"); }
		},
	plugin_dynamicplaylist_favouritesname => {
			'validate' => \&validateAcceptAllWrapper
			,'PrefChoose' => string('PLUGIN_DYNAMICPLAYLIST_FAVOURITESNAME')
			,'changeIntro' => string('PLUGIN_DYNAMICPLAYLIST_FAVOURITESNAME')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_dynamicplaylist_favouritesname"); }
			,'PrefSize' => 'large'
		}
	);
	return (\%setupGroup,\%setupPrefs);
}

sub validateIntWrapper {
	my $arg = shift;
	if ($::VERSION ge '6.5') {
		return Slim::Utils::Validate::isInt($arg);
	}else {
		return Slim::Web::Setup::validateInt($arg);
	}
}

sub validateTrueFalseWrapper {
	my $arg = shift;
	if ($::VERSION ge '6.5') {
		return Slim::Utils::Validate::trueFalse($arg);
	}else {
		return Slim::Web::Setup::validateTrueFalse($arg);
	}
}

sub validateAcceptAllWrapper {
	my $arg = shift;
	if ($::VERSION ge '6.5') {
		return Slim::Utils::Validate::acceptAll($arg);
	}else {
		return Slim::Web::Setup::validateAcceptAll($arg);
	}
}

sub getTracksForPlaylist {
	my $client = shift;
	my $playlist = shift;
	my $limit = shift;
	my $offset = shift;
	my @result;
	
	my $id = $playlist->{'dynamicplaylistid'};
	my $plugin = $plugins{$id};
	debugMsg("Calling: $plugin with: $id , $limit , $offset\n");
	my $result;
	no strict 'refs';
	if(UNIVERSAL::can("$plugin","getNextDynamicPlayListTracks")) {
		my %parameterHash;
		if(defined($playlist->{'parameters'})) {
			my $parameters = $playlist->{'parameters'};
			%parameterHash = ();
			foreach my $pk (keys %$parameters) {
				if(defined($parameters->{$pk}->{'value'})) {
					my %parameter = (
						'id' => $parameters->{$pk}->{'id'},
						'value' => $parameters->{$pk}->{'value'}
					);
					$parameterHash{$pk} = \%parameter;
				}
			}
		}
		debugMsg("Calling: $plugin :: getNextDynamicPlayListTracks\n");
		$result =  eval { &{"${plugin}::getNextDynamicPlayListTracks"}($client,$playlist,$limit,$offset,\%parameterHash) };
		if ($@) {
			debugMsg("Error tracks from $plugin: $@\n");
		}
	}
	 
	use strict 'refs';
	return $result;
}

sub cliGetPlaylists {
	debugMsg("Entering cliGetPlaylists\n");
	my $request = shift;
	my $client = $request->client();
	
	if ($request->isNotQuery([['dynamicplaylist'],['playlists']])) {
		debugMsg("Incorrect command\n");
		$request->setStatusBadDispatch();
		debugMsg("Exiting cliGetPlaylists\n");
		return;
	}
	if(!defined $client) {
		debugMsg("Client required\n");
		$request->setStatusNeedsClient();
		debugMsg("Exiting cliGetPlaylists\n");
		return;
	}
	
  	my $all = $request->getParam('_all');
  	initPlayLists($client);
	initPlayListTypes();
  	if(!defined($all) || $all ne 'all') {
  		$all = undef;
  	}
  	my $count = 0;
	foreach my $playlist (sort keys %$playLists) {
		if(!defined($playLists->{$playlist}->{'parameters'}) && ($playLists->{$playlist}->{'dynamicplaylistenabled'} || defined $all)) {
			$count++;
		}
	}
  	$request->addResult('count',$count);
  	$count = 0;
	foreach my $playlist (sort keys %$playLists) {
		if(!defined($playLists->{$playlist}->{'parameters'}) && ($playLists->{$playlist}->{'dynamicplaylistenabled'} || defined $all)) {
			$request->addResultLoop('@playlists', $count,'playlistid', $playlist);
			my $p = $playLists->{$playlist};
			my $name = $p->{'name'};
			$request->addResultLoop('@playlists', $count,'playlistname', $name);
			if(defined $all) {
				$request->addResultLoop('@playlists', $count,'playlistenabled', $playLists->{$playlist}->{'dynamicplaylistenabled'});
			}
			$count++;
		}
	}
	$request->setStatusDone();
	debugMsg("Exiting cliGetPlaylists\n");
}

sub cliGetPlaylists62 {
	debugMsg("Entering cliGetPlaylists62\n");
	my $client = shift;
	my $paramsRef = shift;
	
	if (scalar(@$paramsRef) lt 2) {
		debugMsg("Incorrect number of parameters\n");
		debugMsg("Exiting cliGetPlaylists62\n");
		return;
	}
	
	if (@$paramsRef[1] ne "playlists") {
		debugMsg("Incorrect command\n");
		debugMsg("Exiting cliGetPlaylists62\n");
		return;
	}
	if(!defined $client) {
		debugMsg("Client required\n");
		debugMsg("Exiting cliGetPlaylists62\n");
		return;
	}
	
  	my $all = undef;
  	if (scalar(@$paramsRef) ge 3) {
  		$all = @$paramsRef[2];
  	}
  	
  	initPlayLists($client);
	initPlayListTypes();
  	if(!defined $all && $all ne 'all') {
  		$all = undef;
  	}
  	my $count = 0;
	foreach my $playlist (sort keys %$playLists) {
		if(!defined($playLists->{$playlist}->{'parameters'}) && ($playLists->{$playlist}->{'dynamicplaylistenabled'} || defined $all)) {
			$count++;
		}
	}
	push @$paramsRef,"count:$count";
  	$count = 0;
	foreach my $playlist (sort keys %$playLists) {
		if(!defined($playLists->{$playlist}->{'parameters'}) && ($playLists->{$playlist}->{'dynamicplaylistenabled'} || defined $all)) {
			push @$paramsRef,"playlistid:$playlist";
			my $p = $playLists->{$playlist};
			my $name = $p->{'name'};
			push @$paramsRef,"playlistname:$name";
			if(defined $all) {
				push @$paramsRef,"playlistenabled:".$playLists->{$playlist}->{'dynamicplaylistenabled'};
			}
			$count++;
		}
	}
	debugMsg("Exiting cliGetPlaylists62\n");
}

sub cliPlayPlaylist {
	debugMsg("Entering cliPlayPlaylist\n");
	my $request = shift;
	my $client = $request->client();
	
	if ($request->isNotCommand([['dynamicplaylist'],['playlist'],['play']])) {
		debugMsg("Incorrect command\n");
		$request->setStatusBadDispatch();
		debugMsg("Exiting cliPlayPlaylist\n");
		return;
	}
	if(!defined $client) {
		debugMsg("Client required\n");
		$request->setStatusNeedsClient();
		debugMsg("Exiting cliPlayPlaylist\n");
		return;
	}
	
  	my $playlistId    = $request->getParam('_playlistid');

	playRandom($client, $playlistId, 0, 1);
	
	$request->setStatusDone();
	debugMsg("Exiting cliPlayPlaylist\n");
}

sub cliPlayPlaylist62 {
	debugMsg("Entering cliPlayPlaylist62\n");
	my $client = shift;
	my $paramsRef = shift;
	
	if (scalar(@$paramsRef) lt 4) {
		debugMsg("Incorrect number of parameters\n");
		debugMsg("Exiting cliPlayPlaylists62\n");
		return;
	}
	
	if (@$paramsRef[1] ne "playlist" || @$paramsRef[2] ne "play") {
		debugMsg("Incorrect command\n");
		debugMsg("Exiting cliPlayPlaylist62\n");
		return;
	}
	if(!defined $client) {
		debugMsg("Client required\n");
		debugMsg("Exiting cliPlayPlaylist62\n");
		return;
	}
	
  	my $playlistId    = @$paramsRef[3];

	playRandom($client, $playlistId, 0, 1);
	
	debugMsg("Exiting cliPlayPlaylist62\n");
}

sub cliAddPlaylist {
	debugMsg("Entering cliAddPlaylist\n");
	my $request = shift;
	my $client = $request->client();
	
	if ($request->isNotCommand([['dynamicplaylist'],['playlist'],['add']])) {
		debugMsg("Incorrect command\n");
		$request->setStatusBadDispatch();
		debugMsg("Exiting cliAddPlaylist\n");
		return;
	}
	if(!defined $client) {
		debugMsg("Client required\n");
		$request->setStatusNeedsClient();
		debugMsg("Exiting cliAddPlaylist\n");
		return;
	}
	
  	my $playlistId    = $request->getParam('_playlistid');

	playRandom($client, $playlistId, 1, 1, 1);
	
	$request->setStatusDone();
	debugMsg("Exiting cliAddPlaylist\n");
}

sub cliAddPlaylist62 {
	debugMsg("Entering cliAddPlaylist62\n");
	my $client = shift;
	my $paramsRef = shift;
	
	if (scalar(@$paramsRef) lt 4) {
		debugMsg("Incorrect number of parameters\n");
		debugMsg("Exiting cliPlayPlaylists62\n");
		return;
	}
	
	if (@$paramsRef[1] ne "playlist" || @$paramsRef[2] ne "add") {
		debugMsg("Incorrect command\n");
		debugMsg("Exiting cliAddPlaylist62\n");
		return;
	}
	if(!defined $client) {
		debugMsg("Client required\n");
		debugMsg("Exiting cliAddPlaylist62\n");
		return;
	}
	
  	my $playlistId    = @$paramsRef[3];

	playRandom($client, $playlistId, 1, 1, 1);
	
	debugMsg("Exiting cliAddPlaylist62\n");
}


sub cliStopPlaylist {
	debugMsg("Entering cliStopPlaylist\n");
	my $request = shift;
	my $client = $request->client();
	
	if ($request->isNotCommand([['dynamicplaylist'],['playlist'],['stop']])) {
		debugMsg("Incorrect command\n");
		$request->setStatusBadDispatch();
		debugMsg("Exiting cliStopPlaylist\n");
		return;
	}
	if(!defined $client) {
		debugMsg("Client required\n");
		$request->setStatusNeedsClient();
		debugMsg("Exiting cliStopPlaylist\n");
		return;
	}
	
	playRandom($client, 'disable');
	
	$request->setStatusDone();
	debugMsg("Exiting cliStopPlaylist\n");
}

sub cliStopPlaylist62 {
	debugMsg("Entering cliStopPlaylist62\n");
	my $client = shift;
	my $paramsRef = shift;
	
	if (scalar(@$paramsRef) lt 3) {
		debugMsg("Incorrect number of parameters\n");
		debugMsg("Exiting cliStopPlaylists62\n");
		return;
	}
	
	if (@$paramsRef[1] ne "playlist" || @$paramsRef[2] ne "stop") {
		debugMsg("Incorrect command\n");
		debugMsg("Exiting cliStopPlaylist62\n");
		return;
	}
	if(!defined $client) {
		debugMsg("Client required\n");
		debugMsg("Exiting cliStopPlaylist62\n");
		return;
	}
	
	playRandom($client, 'disable');
	
	debugMsg("Exiting cliStopPlaylist62\n");
}

sub getCustomBrowseMixes {
	my $client = shift;
	return Plugins::DynamicPlayList::Template::Reader::getTemplates($client,'DynamicPlayList','Mixes','xml','mix');
}

sub getDynamicPlayLists {
	my ($client) = @_;

	my $playLists = ();
	my %result = ();
	
	if(Slim::Utils::Prefs::get("plugin_dynamicplaylist_includesavedplaylists")) {
		if ($::VERSION ge '6.5') {
			my @result;
			for my $playlist (Slim::Schema->rs('Playlist')->getPlaylists) {
				push @result, $playlist;
			}
			$playLists = \@result;
		}else {
			$playLists = Slim::DataStores::DBI::DBIStore->getPlaylists();
		}
		debugMsg("Got: ".scalar(@$playLists)." number of playlists\n");
		my $playlistDir = Slim::Utils::Prefs::get('playlistdir');
		if($playlistDir) {
			$playlistDir = Slim::Utils::Misc::fileURLFromPath($playlistDir);
		}
		foreach my $playlist (@$playLists) {
			my $playlistid = "dynamicplaylist_standard_".$playlist->id;
			my $id = $playlist->id;
			my $name = $playlist->title;
			my $playlisturl;
			if ($::VERSION ge '6.5') {
				$playlisturl = "browsedb.html?hierarchy=playlist,playlistTrack&level=1&playlist.id=".$playlist->id;
			}else {
				$playlisturl = "browsedb.html?hierarchy=playlist,playlistTrack&level=1&playlist=".$playlist->id;
			}
			my %currentResult = (
				'id' => $id,
				'name' => $name,
				'url' => $playlisturl
			);
			
			if(Slim::Utils::Prefs::get("plugin_dynamicplaylist_structured_savedplaylists") && $playlistDir) {
				my $url = $playlist->url;
				if($url =~ /^$playlistDir/) {
					$url =~ s/$playlistDir[\/\\]?//;
				}
				$url = unescape($url);
				my @groups = split(/[\/\\]/,$url);
				if(@groups) {
					pop @groups;
				}
				if(@groups) {
					my @mainGroup = [@groups];
					$currentResult{'groups'} = \@mainGroup;
				}
			}
			$result{$playlistid} = \%currentResult;
		}
	}
	
	return \%result;
}

sub getNextDynamicPlayListTracks {
	my ($client,$dynamicplaylist,$limit,$offset) = @_;
	
	my @result = ();

	debugMsg("Getting tracks for standard playlist: ".$dynamicplaylist->{'name'}."\n");
	my $playlist = objectForId('playlist',$dynamicplaylist->{'id'});
	if(Slim::Utils::Prefs::get("plugin_dynamicplaylist_fullsavedplaylists")) {
		$limit = undef;
	}
	my @tracks = ();
	if(!Slim::Utils::Prefs::get("plugin_dynamicplaylist_randomsavedplaylists")) {
		my $iterator = $playlist->tracks;
		@tracks = $iterator->slice(0,$iterator->count);
	}else {
		$offset = 0;
		my $dbh = getCurrentDBH();
		my $rand = "random()";
		if($driver eq 'mysql') {
			$rand = "rand()";
		}
		my $sql = "select playlist_track.track from playlist_track left join dynamicplaylist_history on playlist_track.track=dynamicplaylist_history.id where playlist_track.playlist=".$dynamicplaylist->{'id'}." and dynamicplaylist_history.id is null group by playlist_track.track order by $rand";
		if(defined($limit)) {
			$sql .= " limit $limit";
		}
		eval {
			my $sth = $dbh->prepare($sql);
			$sth->execute() or do {
	            		$sql = undef;
			};
			if(defined($sql)) {
				my $id;
				$sth->bind_columns( undef, \$id);
				my @trackIds = ();
				while( $sth->fetch() ) {
				  	push @trackIds, $id;
			  	}
				if(scalar(@trackIds)>0) {
					if ($::VERSION ge '6.5') {
						@tracks = Slim::Schema->resultset('Track')->search({ 'id' => { 'in' => \@trackIds } });
					}else {
						for my $trackId (@trackIds) {
							my $track = objectForId('track',$trackId);
							if(defined($track)) {
								push @tracks,$track;
							}
						}
					}
					fisher_yates_shuffle(\@tracks);
				}
			}
			$sth->finish();
		};		
		if( $@ ) {
			warn "Database error: $DBI::errstr\n$@\n";
		}
	}
	my $count = 0;
	my $itemCount = 0;
	for my $item (@tracks) {
		if($count >= $offset) {
			$itemCount++;
			push @result, $item;
		}
		$count++;
		if(defined($limit) && $itemCount>=$limit) {
			last;
		}
	}
	debugMsg("Got ".scalar(@result)." tracks\n");
	
	return \@result;
}

sub fisher_yates_shuffle {
    my $myarray = shift;  
    my $i = @$myarray;
    if(scalar(@$myarray)>1) {
	    while (--$i) {
	        my $j = int rand ($i+1);
	        @$myarray[$i,$j] = @$myarray[$j,$i];
	    }
    }
}

sub addToPlayListHistory
{
	my ($client,$track,$skipped) = @_;

	my $ds        = getCurrentDS();

	my $dbh = getCurrentDBH();

	my $sth = $dbh->prepare( "INSERT INTO dynamicplaylist_history (client,id,url,added,skipped) values (?,".$track->id.", ?, ".time().",".$skipped.")" );
	eval {
		$sth->bind_param(1, $client->macaddress() , SQL_VARCHAR);
		$sth->bind_param(2, $track->url , SQL_VARCHAR);
		$sth->execute();
		commit($dbh);
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}
	$sth->finish();
}
sub clearPlayListHistory {
	my $client = shift;
	my $ds        = getCurrentDS();

	my $dbh = getCurrentDBH();

	my $sth = undef;
	if(!defined($client)) {
		my $sql = "DELETE FROM dynamicplaylist_history";
		$sth = $dbh->prepare($sql);
		eval {
			$sth->execute();
			commit($dbh);
		};
	}else {
		my $sql = "DELETE FROM dynamicplaylist_history where client=?";
		$sth = $dbh->prepare($sql);
		eval {
			$sth->bind_param(1, $client->macaddress() , SQL_VARCHAR);
			$sth->execute();
			commit($dbh);
		};
	}
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}
	$sth->finish();
	if($driver eq 'mysql') {
		eval { 
			$dbh->do("ALTER TABLE dynamicplaylist_history AUTO_INCREMENT=1");
			commit($dbh);
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
	}
}

sub validateIntOrEmpty {
	my $arg = shift;
	if(!$arg || $arg eq '' || $arg =~ /^\d+$/) {
		return $arg;
	}
	return undef;
}

sub getCurrentDBH {
	if ($::VERSION ge '6.5') {
		return Slim::Schema->storage->dbh();
	}else {
		return Slim::Music::Info::getCurrentDataStore()->dbh();
	}
}

sub getCurrentDS {
	if ($::VERSION ge '6.5') {
		return 'Slim::Schema';
	}else {
		return Slim::Music::Info::getCurrentDataStore();
	}
}

sub objectForId {
	my $type = shift;
	my $id = shift;
	if ($::VERSION ge '6.5') {
		if($type eq 'artist') {
			$type = 'Contributor';
		}elsif($type eq 'album') {
			$type = 'Album';
		}elsif($type eq 'genre') {
			$type = 'Genre';
		}elsif($type eq 'track') {
			$type = 'Track';
		}elsif($type eq 'playlist') {
			$type = 'Playlist';
		}
		return Slim::Schema->resultset($type)->find($id);
	}else {
		if($type eq 'playlist') {
			$type = 'track';
		}
		return getCurrentDS()->objectForId($type,$id);
	}
}

sub getLinkAttribute {
	my $attr = shift;
	if ($::VERSION ge '6.5') {
		if($attr eq 'artist') {
			$attr = 'contributor';
		}
		return $attr.'.id';
	}
	return $attr;
}

sub executeSQLFile {
        my $file  = shift;

        my $sqlFile;
		if ($::VERSION ge '6.5') {
			for my $plugindir (Slim::Utils::OSDetect::dirsFor('Plugins')) {
				opendir(DIR, catdir($plugindir,"DynamicPlayList")) || next;
        		$sqlFile = catdir($plugindir,"DynamicPlayList", "SQL", $driver, $file);
        		closedir(DIR);
        	}
        }else {
         	$sqlFile = catdir($Bin, "Plugins", "DynamicPlayList", "SQL", $driver, $file);
        }

        debugMsg("Executing SQL file $sqlFile\n");

        open(my $fh, $sqlFile) or do {

                msg("Couldn't open: $sqlFile : $!\n");
                return;
        };

		my $dbh = getCurrentDBH();

        my $statement   = '';
        my $inStatement = 0;

        for my $line (<$fh>) {
                chomp $line;

                # skip and strip comments & empty lines
                $line =~ s/\s*--.*?$//o;
                $line =~ s/^\s*//o;

                next if $line =~ /^--/;
                next if $line =~ /^\s*$/;

                if ($line =~ /^\s*(?:CREATE|SET|INSERT|UPDATE|DELETE|DROP|SELECT|ALTER|DROP)\s+/oi) {
                        $inStatement = 1;
                }

                if ($line =~ /;/ && $inStatement) {

                        $statement .= $line;


                        debugMsg("Executing SQL statement: [$statement]\n");

                        eval { $dbh->do($statement) };

                        if ($@) {
                                msg("Couldn't execute SQL statement: [$statement] : [$@]\n");
                        }

                        $statement   = '';
                        $inStatement = 0;
                        next;
                }

                $statement .= $line if $inStatement;
        }

        commit($dbh);

        close $fh;
}

sub commit {
	my $dbh = shift;
	if (!$dbh->{'AutoCommit'}) {
		$dbh->commit();
	}
}

sub rollback {
	my $dbh = shift;
	if (!$dbh->{'AutoCommit'}) {
		$dbh->rollback();
	}
}

# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

# don't use the external one because it doesn't know about the difference
# between a param and not...
#*unescape = \&URI::Escape::unescape;
sub unescape {
        my $in      = shift;
        my $isParam = shift;

        $in =~ s/\+/ /g if $isParam;
        $in =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

        return $in;
}

# A wrapper to allow us to uniformly turn on & off debug messages
sub debugMsg
{
	my $message = join '','DynamicPlayList: ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_dynamicplaylist_showmessages"));
}

sub strings {
	return <<EOF;
DYNAMICPLAYLIST
	EN	Dynamic Playlists

PLUGIN_DYNAMICPLAYLIST
	EN	Dynamic Playlists

PLUGIN_DYNAMICPLAYLIST_DISABLED
	EN	DynamicPlayList Stopped

PLUGIN_DYNAMICPLAYLIST_CHOOSE_BELOW
	EN	Choose a playlist:

PLUGIN_DYNAMICPLAYLIST_CONTEXT_CHOOSE_BELOW
	EN	Choose a playlist related to: 

PLUGIN_DYNAMICPLAYLIST_BEFORE_NUM_TRACKS
	EN	Now Playing will show

PLUGIN_DYNAMICPLAYLIST_AFTER_NUM_TRACKS
	EN	upcoming songs and

PLUGIN_DYNAMICPLAYLIST_AFTER_NUM_OLD_TRACKS
	EN	recently played songs.

PLUGIN_DYNAMICPLAYLIST_SETUP_GROUP
	EN	Dynamic PlayLists

PLUGIN_DYNAMICPLAYLIST_SETUP_GROUP_DESC
	EN	DynamicPlayList is a plugin which makes it easy to write your own dynamic playlist plugin and it below the same menu as the other playlists

PLUGIN_DYNAMICPLAYLIST_SHOW_MESSAGES
	EN	Show debug messages

PLUGIN_DYNAMICPLAYLIST_FAVOURITESNAME
	EN	Favourites group name

PLUGIN_DYNAMICPLAYLIST_FAVOURITES
	EN	Favourites

PLUGIN_DYNAMICPLAYLIST_INCLUDE_SAVED_PLAYLISTS
	EN	Include saved playlists

PLUGIN_DYNAMICPLAYLIST_RANDOM_SAVED_PLAYLISTS
	EN	Play saved playlist in random

PLUGIN_DYNAMICPLAYLIST_FULL_SAVED_PLAYLISTS
	EN	Add all tracks in saved playlists immediately

PLUGIN_DYNAMICPLAYLIST_NUMBER_OF_TRACKS
	EN	Number of tracks

PLUGIN_DYNAMICPLAYLIST_NUMBER_OF_SKIPPED_TRACKS_RETRIES
	EN	Number of retires when filtering

PLUGIN_DYNAMICPLAYLIST_NUMBER_OF_OLD_TRACKS
	EN	Number of old tracks

PLUGIN_DYNAMICPLAYLIST_UNGROUPED
	EN	Group for playlists without a group

PLUGIN_DYNAMICPLAYLIST_FLATLIST
	EN	Show all playlists on top

PLUGIN_DYNAMICPLAYLIST_WEB_SHOW_MIXERLINKS
	EN	Show DynamicPlayList button in browse pages. May require slimserver restart.

PLUGIN_DYNAMICPLAYLIST_ENABLE_MIXERFUNCTION
	EN	Enable DynamicPlayList play+hold action. May require slimserver restart.

PLUGIN_DYNAMICPLAYLIST_STRUCTURED_SAVEDPLAYLISTS
	EN	Use saved playlist sub directories as groups

SETUP_PLUGIN_DYNAMICPLAYLIST_SHOWMESSAGES
	EN	Debugging

SETUP_PLUGIN_DYNAMICPLAYLIST_INCLUDESAVEDPLAYLISTS
	EN	Saved playlists

SETUP_PLUGIN_DYNAMICPLAYLIST_RANDOMSAVEDPLAYLISTS
	EN	Random saved playlists

SETUP_PLUGIN_DYNAMICPLAYLIST_FULLSAVEDPLAYLISTS
	EN	Whole saved playlists

SETUP_PLUGIN_DYNAMICPLAYLIST_NUMBER_OF_TRACKS
	EN	Number of tracks

PLUGIN_DYNAMICPLAYLIST_NUMBER_OF_SKIPPED_TRACKS_RETRIES
	EN	Number of retries when filtering

SETUP_PLUGIN_DYNAMICPLAYLIST_NUMBER_OF_OLD_TRACKS
	EN	Number of old tracks

SETUP_PLUGIN_DYNAMICPLAYLIST_UNGROUPED
	EN	Playlists without a group

SETUP_PLUGIN_DYNAMICPLAYLIST_WEB_SHOW_MIXERLINKS
	EN	Buttons in browse pages

SETUP_PLUGIN_DYNAMICPLAYLIST_ENABLE_MIXERFUNCTION
	EN	Play+Hold mixer action

SETUP_PLUGIN_DYNAMICPLAYLIST_FLATLIST
	EN	Show all playlists on top

SETUP_PLUGIN_DYNAMICPLAYLIST_STRUCTURED_SAVEDPLAYLISTS
	EN	Use saved playlist sub directories as groups

PLUGIN_DYNAMICPLAYLIST_BEFORE_NUM_TRACKS
	EN	Now Playing will show

PLUGIN_DYNAMICPLAYLIST_AFTER_NUM_TRACKS
	EN	upcoming songs and

PLUGIN_DYNAMICPLAYLIST_AFTER_NUM_OLD_TRACKS
	EN	recently played songs.

PLUGIN_DYNAMICPLAYLIST_CHOOSE_BELOW
	EN	Choose a playlist with music from your library:

PLUGIN_DYNAMICPLAYLIST_PLAYING
	EN	Playing

PLUGIN_DYNAMICPLAYLIST_PRESS_RIGHT
	EN	Press RIGHT to stop adding songs

PLUGIN_DYNAMICPLAYLIST_GENERAL_HELP
	EN	You can add or remove songs from your mix at any time. To stop adding songs, clear your playlist or click to

PLUGIN_DYNAMICPLAYLIST_DISABLE
	EN	Stop adding songs

PLUGIN_DYNAMICPLAYLIST_CONTINUOUS_MODE
	EN	Add new items when old ones finish

PLUGIN_DYNAMICPLAYLIST_NOW_PLAYING_FAILED
	EN	Failed 

PLUGIN_DYNAMICPLAYLIST_SELECT_PLAYLISTS
	EN	Enable/Disable playlists 

PLUGIN_DYNAMICPLAYLIST_SELECT_PLAYLISTS_TITLE
	EN	Select enabled playlists

PLUGIN_DYNAMICPLAYLIST_SELECT_FILTERS
	EN	Enable/Disable filters 

PLUGIN_DYNAMICPLAYLIST_SELECT_FILTERS_TITLE
	EN	Select enabled filters

PLUGIN_DYNAMICPLAYLIST_SELECT_GROUPS_TITLE
	EN	Select enabled playlist groups

PLUGIN_DYNAMICPLAYLIST_SELECT_FAVOURITES_TITLE
	EN	Select favourites

PLUGIN_DYNAMICPLAYLIST_SELECT_PLAYLISTS_NONE
	EN	No Playlists

PLUGIN_DYNAMICPLAYLIST_SELECT_PLAYLISTS_ALL
	EN	All Playlists

PLUGIN_DYNAMICPLAYLIST_SELECT_FILTERS_NONE
	EN	No filters

PLUGIN_DYNAMICPLAYLIST_SELECT_FILTERS_ALL
	EN	All filters

PLUGIN_DYNAMICPLAYLIST_NEXT
	EN	Next

PLUGIN_DYNAMICPLAYLIST_PARAMETERS_TITLE
	EN	Enter additional parameters for playlist

PLUGIN_DYNAMICPLAYLIST_SELECT_FILTERS_CONFIGURE
	EN	Configure filter
EOF

}

1;

__END__
