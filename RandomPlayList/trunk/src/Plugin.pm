# 				RandomPlayList plugin 
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

package Plugins::RandomPlayList::Plugin;

use strict;

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use File::Spec::Functions qw(:ALL);
use Class::Struct;

# Information on each clients randomplaylist
my $htmlTemplate = 'plugins/RandomPlayList/randomplaylist_list.html';
my $ds = getCurrentDS();
my $playLists = undef;

my %disable = (
	'id' => 'disable', 
	'name' => ''
);

sub getDisplayName {
	return 'PLUGIN_RANDOMPLAYLIST';
}
sub getCurrentPlayList {
	my $client = shift;
	my $currentPlaying = eval { Plugins::DynamicPlayList::Plugin::getCurrentPlayList($client) };
	if ($@) {
		warn("RandomPlayList: Error getting current playlist from DynamicPlayList plugin: $@\n");
	}
	if($currentPlaying) {
		if(!$playLists) {
			$playLists = getDynamicPlaylists($client);
		}
		if($playLists && $playLists->{$currentPlaying}) {
			$currentPlaying = $playLists->{$currentPlaying}->{'id'};
		}else {
			$currentPlaying = undef;
		}
	}
	return $currentPlaying;
}
# Returns the display text for the currently selected item in the menu
sub getDisplayText {
	my ($client, $item) = @_;

	my $id = undef;
	my $name = '';
	if($item) {
		$id = $item->{'id'};
		$name = $item->{'name'};
	}
	my $currentPlaying = getCurrentPlayList($client);
	# if showing the current mode, show altered string
	if ($currentPlaying && ($id eq $currentPlaying)) {
		return string('PLUGIN_RANDOMPLAYLIST_PLAYING')." ".$name;
	# if a mode is active, handle the temporarily added disable option
	} elsif ($id eq 'disable' && $currentPlaying) {
		return string('PLUGIN_RANDOMPLAYLIST_PRESS_RIGHT');
	} else {
		return $name;
	}
}

# Returns the overlay to be display next to items in the menu
sub getOverlay {
	my ($client, $item) = @_;

	my $currentPlaying = getCurrentPlayList($client);
	# Put the right arrow by genre filter and notesymbol by mixes
	if ($item->{'id'} eq 'disable') {
		return [undef, Slim::Display::Display::symbol('rightarrow')];
	}elsif (!$currentPlaying || $item->{'id'} ne $currentPlaying) {
		return [undef, Slim::Display::Display::symbol('notesymbol')];
	} else {
		return [undef, undef];
	}
}

# Do what's necessary when play or add button is pressed
sub handlePlayOrAdd {
	my ($client, $item, $add) = @_;
	debugMsg("".($add ? 'Add' : 'Play')."$item\n");
		
	my $currentPlaying = getCurrentPlayList($client);

	# reconstruct the list of options, adding and removing the 'disable' option where applicable
	my $listRef = Slim::Buttons::Common::param($client, 'listRef');
		
	if ($item eq 'disable') {
		pop @$listRef;
		
	# only add disable option if starting a mode from idle state
	} elsif (! $currentPlaying) {
		push @$listRef, \%disable;
	}
	Slim::Buttons::Common::param($client, 'listRef', $listRef);

	my $request;
	if($item eq 'disable') {
		$request = $client->execute(['dynamicplaylist', 'playlist', 'stop']);
	}else {
		$request = $client->execute(['dynamicplaylist', 'playlist', ($add?'add':'play'), $item]);
	}
	if ($::VERSION ge '6.5') {
		# indicate request source
		$request->source('PLUGIN_RANDOMPLAYLIST');
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
	if(!$playLists) {
		$playLists = getDynamicPlayLists($client);
	}
	foreach my $playlist (sort keys %$playLists) {
		push @listRef, $playLists->{$playlist};
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header     => '{PLUGIN_RANDOMPLAYLIST} {count}',
		listRef    => \@listRef,
		name       => \&getDisplayText,
		overlayRef => \&getOverlay,
		modeName   => 'RandomPlayList',
		onPlay     => sub {
			my ($client, $item) = @_;
			handlePlayOrAdd($client, 'randomplaylist_'.$item->{'id'}, 0);		
		},
		onAdd      => sub {
			my ($client, $item) = @_;
			handlePlayOrAdd($client, 'randomplaylist_'.$item->{'id'}, 1);
		},
		onRight    => sub {
			my ($client, $item) = @_;
			if($item->{'id'} eq 'disable') {
				handlePlayOrAdd($client, 'disable');
			}else {
				$client->bumpRight();
			}
		},
,
	);

	my $currentPlaying = getCurrentPlayList($client);

	# if we have an active mode, temporarily add the disable option to the list.
	if ($currentPlaying) {
		push @{$params{listRef}},\%disable;
	}

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}


sub initPlugin {
	checkDefaults();
}

sub webPages {

	my %pages = (
		"randomplaylist_list\.(?:htm|xml)"     => \&handleWebList,
		"randomplaylist_mix\.(?:htm|xml)"      => \&handleWebMix,
		"randomplaylist_settings\.(?:htm|xml)"      => \&handleWebSettings,
	);

	my $value = $htmlTemplate;

	if (grep { /^RandomPlayList::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

		$value = undef;
	} 

	#Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_RANDOMPLAYLIST' => $value });

	return (\%pages,$value);
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	# Pass on the current pref values and now playing info
	if(!$playLists) {
		$playLists = getDynamicPlayLists($client);
	}
	my $currentPlayingId = getCurrentPlayList($client);
	my $name = undef;
	if(defined($currentPlayingId)) {
		my $currentPlaying = eval { Plugins::DynamicPlayList::Plugin::getCurrentPlayList($client) };
		if ($@) {
			warn("RandomPlayList: Error getting current playlist from DynamicPlayList plugin: $@\n");
		}
		
		$name = $playLists->{$currentPlaying}->{'name'};
	}
	$params->{'pluginRandomPlayListGenreList'} = getFilteredGenres($client,1);
	$params->{'pluginRandomPlayListPlayLists'} = $playLists;
	$params->{'pluginRandomPlayListNowPlaying'} = $name;
	if ($::VERSION ge '6.5') {
		$params->{'pluginRandomPlayListSlimserver65'} = 1;
	}
    if(!UNIVERSAL::can("Plugins::DynamicPlayList::Plugin","getCurrentPlayList")) {
		$params->{'pluginRandomPlayListError'} = "ERROR!!! Cannot find DynamicPlayList plugin, please make sure you have installed and enabled at least DynamicPlayList 1.3"
	}
	
	return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
}

# Handles play requests from plugin's web page
sub handleWebMix {
	my ($client, $params) = @_;
	if (defined $client && $params->{'type'}) {
		handlePlayOrAdd($client, $params->{'type'}, $params->{'addOnly'});
	}
	handleWebList($client, $params);
}

# Handles settings requests from plugin's web page
sub handleWebSettings {
	my ($client, $params) = @_;

	my $genres = getFilteredGenres($client,1);
	my @lookup = ();
	
	foreach my $genre (keys %$genres) {
            @lookup[$genres->{$genre}->{'id'}] = $genre;
    }

    # %$params will contain a key called genre_<genre id> for each ticked checkbox on the page
    foreach my $genre (keys(%$params)) {
            if ($genre =~ s/^genre_//) {
                    delete($genres->{$lookup[$genre]});
            }
    }
    
    my @excludedGenres = ();
    foreach my $genre (keys %$genres) {
    	push @excludedGenres, $genre;
    }
    Slim::Utils::Prefs::set('plugin_randomplaylist_exclude_genres', \@excludedGenres);
    debugMsg("Setting genres to : ".@excludedGenres."\n");
    return handleWebList($client, $params);
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
	my $prefVal = Slim::Utils::Prefs::get('plugin_randomplaylist_showmessages');
	if (! defined $prefVal) {
		# Default to standard playlist directory
		debugMsg("Defaulting plugin_randomplaylist_showmessages to 0\n");
		Slim::Utils::Prefs::set('plugin_randomplaylist_showmessages', 0);
	}
	my @genres = Slim::Utils::Prefs::getArray('plugin_randomplaylist_exclude_genres');
	if(! @genres) {
		my @default = Slim::Utils::Prefs::getArray('plugin_random_exclude_genres');
		if(@default) {
			Slim::Utils::Prefs::set('plugin_randomplaylist_exclude_genres', @default);
		}else {
			Slim::Utils::Prefs::set('plugin_randomplaylist_exclude_genres', []);
		}
	}
}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_randomplaylist_showmessages'],
	 GroupHead => string('PLUGIN_RANDOMPLAYLIST_SETUP_GROUP'),
	 GroupDesc => string('PLUGIN_RANDOMPLAYLIST_SETUP_GROUP_DESC'),
	 GroupLine => 1,
	 GroupSub  => 1,
	 Suppress_PrefSub  => 1,
	 Suppress_PrefLine => 1
	);
	my %setupPrefs =
	(
	plugin_randomplaylist_showmessages => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_RANDOMPLAYLIST_SHOW_MESSAGES')
			,'changeIntro' => string('PLUGIN_RANDOMPLAYLIST_SHOW_MESSAGES')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_randomplaylist_showmessages"); }
		}
	);
	return (\%setupGroup,\%setupPrefs);
}

sub validateTrueFalseWrapper {
	my $arg = shift;
	if ($::VERSION ge '6.5') {
		return Slim::Utils::Validate::trueFalse($arg);
	}else {
		return Slim::Web::Setup::validateTrueFalse($arg);
	}
}

sub getDynamicPlayLists {
	my ($client) = @_;
	debugMsg("getDynamicPlayLists entering\n");
	my %result = ();
	if(!defined($client)) {
		debugMsg("getDynamicPlayLists exiting\n");
		return undef;
	}
	my %currentResultTrack = (
		'id' => 'track',
		'name' => $client->string('PLUGIN_RANDOMPLAYLIST_RANDOM_TRACK')
	);
	my $id = "randomplaylist_track";
	$result{$id} = \%currentResultTrack;
	
	my %currentResultAlbum = (
		'id' => 'album',
		'name' => $client->string('PLUGIN_RANDOMPLAYLIST_RANDOM_ALBUM')
	);
	$id = "randomplaylist_album";
	$result{$id} = \%currentResultAlbum;
	
	my %currentResultYear = (
		'id' => 'year',
		'name' => $client->string('PLUGIN_RANDOMPLAYLIST_RANDOM_YEAR')
	);
	$id = "randomplaylist_year";
	$result{$id} = \%currentResultYear;

	my %currentResultArtist = (
		'id' => 'artist',
		'name' => $client->string('PLUGIN_RANDOMPLAYLIST_RANDOM_ARTIST')
	);
	$id = "randomplaylist_artist";
	$result{$id} = \%currentResultArtist;

	debugMsg("getDynamicPlayLists exiting\n");
	return \%result;
}

sub getRandomYear {
	my $filteredGenres = shift;
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
		 my @joins = qw(genreTracks);
		 push @joins, 'genreTracks';
		 my $rs = Slim::Schema->rs('Track')->search(
                { 'genreTracks.genre' => $filteredGenres },
                { 'order_by' => \'RAND()', 'join' => \@joins }
        	)->slice(0,1);
        my $year = $rs->next;
        if($year) {
        	$year = $year->year;
        }else {
        	$year = undef;
        }
        if(!$year) {
        	$year = $rs->next;
	        if($year) {
	        	$year = $year->year;
	        }else {
	        	$year = undef;
	        }
        }
        return $year;
	}else {
	   	my $items = $ds->find({
			'field'  => 'year',
			'find'   => {
				'genre.name' => $filteredGenres,
			},
			'sortBy' => 'random',
			'limit'  => 2,
			'cache'  => 0,
		});
		my $year = shift @$items;
		if(!defined($year)) {
			$year = shift @$items;
		}
		return $year;
	}
}

sub getFilteredGenres {
	my $client = shift;
	my $returnAll = shift;
    my @filteredGenres = ();
    my %allGenres;
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
	    # Should use genre.name in following find, but a bug in find() doesn't allow this
	    # XXXX - how does the above comment translate into DBIx::Class world?
	    my $rs = Slim::Schema->search('Genre');

	    # Extract each genre name into a hash
	    my @exclude      = Slim::Utils::Prefs::getArray('plugin_randomplaylist_exclude_genres');

	    for my $genre ($rs->all) {

	            # Put the name here as well so the hash can be passed to
	            # INPUT.Choice as part of listRef later on
	            my $name = $genre->name;
	            my $id   = $genre->id;
	            my $ena  = 1;

	            if (grep { $_ eq $name } @exclude) {
	                    $ena = 0;
	            }
	            
				$allGenres{$name} = {
                     name    => $name,
                     id      => $id,
                     enabled => $ena
				};
	            if($ena) {
	            	push @filteredGenres, $id;
	            }
	    }
	}else {
        # Should use genre.name in following find, but a bug in find() doesn't allow this
        my $items = $ds->find({
                'field'  => 'genre',
                'cache'  => 0,
        });

        # Extract each genre name into a hash
        my @exclude = Slim::Utils::Prefs::getArray('plugin_randomplaylist_exclude_genres');
        foreach my $genre (@$items) {
	            # Put the name here as well so the hash can be passed to
	            # INPUT.Choice as part of listRef later on
	            my $name = $genre->name;
	            my $id   = $genre->id;
	            my $ena  = 1;

	            if (grep { $_ eq $name } @exclude) {
	                    $ena = 0;
	            }
				$allGenres{$name} = {
                     name    => $name,
                     id      => $id,
                     enabled => $ena
				};
	            if($ena) {
	            	push @filteredGenres, $name;
	            }
        }
	}
    if($returnAll) {
    	return \%allGenres;
    }else {
    	return \@filteredGenres;
    }
}

sub getNextDynamicPlayListTracks {
	my ($client,$dynamicplaylist,$limit,$offset) = @_;
	
	my @result = ();

	my $type = $dynamicplaylist->{'id'};
	my $filteredGenres = getFilteredGenres($client);
	debugMsg("Got ".scalar(@$filteredGenres)." filtered genres\n");
	my $find;
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
		$find = {'genreTracks.genre' =>  { 'in' => $filteredGenres }};
	}else {
		$find = {'genre.name' => $filteredGenres};
	}
	if ($type eq 'track' || $type eq 'year') {
		# Find only tracks, not albums etc
		$find->{'audio'} = 1;
	}
	my $items;


	if($type eq 'track') {
		if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
			 my @joins  = ();
			 push @joins, 'genreTracks';
			 my $rs = Slim::Schema->rs('Track')->search($find, {
                'order_by' => \'RAND()',
	            'join'     => \@joins,
	            });
			for my $track ($rs->slice(0, ($limit-1))) {
				push @result, $track;
			}
		}else {
			$items = $ds->find({
				'field'  => 'track',
				'find'   => $find,
				'sortBy' => 'random',
				'limit'  => $limit,
				'cache'  => 0,
			});
			for my $track (@$items) {
				push @result, $track;
			}
		}
		debugMsg("Got ".scalar(@result)." tracks\n");


	}elsif($type eq 'year') {
		# We want to do this twice to make sure the playlist will continue if only one track exists for the selected year
		for (my $i = 0; $i < 2 && scalar(@result)<2; $i++) {
			my $year = getRandomYear($filteredGenres);
			$find->{'year'} = $year;
			debugMsg("Finding tracks for year $year\n");
			if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
				 my @joins  = ();
				 push @joins, 'genreTracks';
				 my $rs = Slim::Schema->rs('Track')->search($find, {
	                'order_by' => \'RAND()',
    	            'join'     => \@joins,
    	            });
					for my $track ($rs->all) {
						push @result, $track;
					}
			}else {
				$items = $ds->find({
					'field'  => 'track',
					'find'   => $find,
					'sortBy' => 'random',
					'limit'  => undef,
					'cache'  => 0,
				});
				for my $track (@$items) {
					push @result, $track;
				}
			}
		}
		debugMsg("Got ".scalar(@result)." tracks\n");


	}elsif($type eq 'album') {
		my $album;
		if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
			my @joins  = ();
			push @joins, { 'tracks' => 'genreTracks' };
			my $rs = Slim::Schema->rs('Album')->search($find, {
				'order_by' => \'RAND()',
				'join'     => \@joins,
				})->slice(0,0);
			
			$album = $rs->next;
		}else {
			my $items = $ds->find({
				'field'  => 'album',
				'find'   => $find,
				'sortBy' => 'random',
				'limit'  => 1,
				'cache'  => 0,
			});
			$album = shift @{$items};
		}

		if ($album && ref($album)) {
			debugMsg("Getting tracks for album: ".$album->title."\n");
			my $iterator = $album->tracks;
			for my $item ($iterator->slice(0,$iterator->count)) {
				push @result, $item;
			}
			debugMsg("Got ".scalar(@result)." tracks\n");
		}


	}elsif($type eq 'artist') {
		# We want to do this twice to make sure the playlist will continue if only one track exists for the selected artist
		my @artists = ();
		if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
			my @joins  = ();
			push @joins, { 'contributorTracks' => { 'track' => 'genreTracks' } };
			my $rs = Slim::Schema->rs('Contributor')->search($find, {
				'order_by' => \'RAND()',
				'join'     => \@joins,
				});
			for my $artist ($rs->slice(0,1)) {
				push @artists,$artist;
			}
		}else {
			my $items = $ds->find({
				'field'  => 'artist',
				'find'   => $find,
				'sortBy' => 'random',
				'limit'  => 2,
				'cache'  => 0,
			});
			for my $artist (@$items) {
				push @artists,$artist;
			}
		}

		for (my $i = 0; $i < 2 && scalar(@result)<2; $i++) {
			my $artist = shift @artists;
			if ($artist && ref($artist)) {
				debugMsg("Getting tracks for artist: ".$artist->name."\n");
				my $items;
				if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
					my $artistFind = {'contributor' => $artist->id };
					 my @joins  = ();
					 push @joins, { 'contributorTracks' => { 'track' => 'genreTracks' } };
					 my $rs = Slim::Schema->rs('Track')->search($artistFind, {
		                'order_by' => \'RAND()',
	    	            'join'     => \@joins,
	    	            });
					for my $item ($rs->distinct) {
						debugMsg("Adding: ".$item->title."\n");
						push @result, $item;
					}
				}else {
					my $artistFind = {'artist' => $artist->id };
					$items = $ds->find({
						'field'  => 'track',
						'find'   => $artistFind,
						'sortBy' => 'random',
						'limit'  => undef,
						'cache'  => 0,
					});
					for my $item (@$items) {
						push @result, $item;
					}
				}
			}
		}
		debugMsg("Got ".scalar(@result)." tracks\n");
	}
	
	return \@result;
}

sub getCurrentDBH {
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
		return Slim::Schema->storage->dbh();
	}else {
		return Slim::Music::Info::getCurrentDataStore()->dbh();
	}
}

sub getCurrentDS {
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
		return 'Slim::Schema';
	}else {
		return Slim::Music::Info::getCurrentDataStore();
	}
}

sub objectForId {
	my $type = shift;
	my $id = shift;
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
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
	my $message = join '','RandomPlayList: ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_randomplaylist_showmessages"));
}

sub strings {
	return <<EOF;
PLUGIN_RANDOMPLAYLIST
	EN	Random Playlists

PLUGIN_RANDOMPLAYLIST_DISABLED
	EN	Random PlayList Stopped

PLUGIN_RANDOMPLAYLIST_CHOOSE_BELOW
	EN	Choose a playlist:

PLUGIN_RANDOMPLAYLIST_SETUP_GROUP
	EN	Random PlayLists

PLUGIN_RANDOMPLAYLIST_SETUP_GROUP_DESC
	EN	RandomPlayList is a plugin which makes possible to play random songs in your music library

PLUGIN_RANDOMPLAYLIST_SHOW_MESSAGES
	EN	Show debug messages

SETUP_PLUGIN_RANDOMPLAYLIST_SHOWMESSAGES
	EN	Debugging

PLUGIN_RANDOMPLAYLIST_CHOOSE_BELOW
	EN	Choose a playlist with music from your library:

PLUGIN_RANDOMPLAYLIST_PLAYING
	EN	Playing

PLUGIN_RANDOMPLAYLIST_RANDOM_TRACK
	EN	Random Song

PLUGIN_RANDOMPLAYLIST_RANDOM_ARTIST
	EN	Random Artist

PLUGIN_RANDOMPLAYLIST_RANDOM_ALBUM
	EN	Random Album

PLUGIN_RANDOMPLAYLIST_RANDOM_YEAR
	EN	Random Year

PLUGIN_RANDOMPLAYLIST_GENERAL_HELP
	EN	You can add or remove songs from your mix at any time. To stop adding songs, clear your playlist or click to

PLUGIN_RANDOMPLAYLIST_DISABLE
	EN	Stop adding songs

PLUGIN_RANDOMPLAYLIST_NOW_PLAYING_FAILED
	EN	Failed 

PLUGIN_RANDOMPLAYLIST_GENRES_SELECT_ALL
	EN	Select All

PLUGIN_RANDOMPLAYLIST_GENRES_SELECT_NONE
	EN	Select None

PLUGIN_RANDOMPLAYLIST_GENRES_TITLE
	EN	Genres to include in the playlist:

PLUGIN_RANDOMPLAYLIST_PRESS_RIGHT
	EN	Press RIGHT to stop adding songs

EOF

}

1;

__END__
