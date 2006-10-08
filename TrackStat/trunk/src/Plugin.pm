# 				TrackStat plugin 
#
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
#
#    Portions of code derived from the iTunes plugin included in slimserver
#    Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
#
#    Portions of code derived from the iTunesUpdate 1.5 plugin
#    Copyright (c) 2004-2006 James Craig (james.craig@london.com)
#
#    Portions of code derived from the SlimScrobbler plugin
#    Copyright (c) 2004 Stewart Loving-Gibbard (sloving-gibbard@uswest.net)
#
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

use strict;
use warnings;
                   
package Plugins::TrackStat::Plugin;

use Slim::Player::Playlist;
use Slim::Player::Source;
use Slim::Player::Client;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);

use Time::HiRes;
use Class::Struct;
use POSIX qw(strftime ceil floor);
use File::Spec::Functions qw(:ALL);
use DBI qw(:sql_types);

use Scalar::Util qw(blessed);

use FindBin qw($Bin);
use Plugins::TrackStat::Time::Stopwatch;
use Plugins::TrackStat::iTunes::Import;
use Plugins::TrackStat::iTunes::Export;
use Plugins::TrackStat::MusicMagic::Import;
use Plugins::TrackStat::MusicMagic::Export;
use Plugins::TrackStat::Backup::File;
use Plugins::TrackStat::Storage;

use vars qw($VERSION);
$VERSION = substr(q$Revision$,10);

#################################################
### Global constants - do not change casually ###
#################################################

# Indicator if hooked or not
# 0= No
# 1= Yes
my $TRACKSTAT_HOOK = 0;

my $RATING_CHARACTER = ' *';
my $NO_RATING_CHARACTER = '  ';
	
# Each client's playStatus structure. 
my %playerStatusHash = ();

# Plugins that supports ratings
my %ratingPlugins = ();

# Plugins that supports play count/last played time
my %playCountPlugins = ();

my %statisticPlugins = ();
my %statisticItems = ();
my %statisticTypes = ();
my $statisticPluginsStrings = "";
my $statisticsInitialized = undef;

my $ratingDynamicLastUrl = undef;
my $ratingStaticLastUrl = undef;
my $ratingNumberLastUrl = undef;
my $ratingDynamicCache = undef;
my $ratingStaticCache = undef;
my $ratingNumberCache = undef;

##################################################
### SLIMP3 Plugin API                          ###
##################################################

my %mapping = (
	'0.hold' => 'saveRating_0',
	'1.hold' => 'saveRating_1',
	'2.hold' => 'saveRating_2',
	'3.hold' => 'saveRating_3',
	'4.hold' => 'saveRating_4',
	'5.hold' => 'saveRating_5',
	'0.single' => 'numberScroll_0',
	'1.single' => 'numberScroll_1',
	'2.single' => 'numberScroll_2',
	'3.single' => 'numberScroll_3',
	'4.single' => 'numberScroll_4',
	'5.single' => 'numberScroll_5',
	'0' => 'dead',
	'1' => 'dead',
	'2' => 'dead',
	'3' => 'dead',
	'4' => 'dead',
	'5' => 'dead'
);

my %choiceMapping = (
	'0.hold' => 'saveRating_0',
	'1.hold' => 'saveRating_1',
	'2.hold' => 'saveRating_2',
	'3.hold' => 'saveRating_3',
	'4.hold' => 'saveRating_4',
	'5.hold' => 'saveRating_5',
	'0.single' => 'numberScroll_0',
	'1.single' => 'numberScroll_1',
	'2.single' => 'numberScroll_2',
	'3.single' => 'numberScroll_3',
	'4.single' => 'numberScroll_4',
	'5.single' => 'numberScroll_5',
	'0' => 'dead',
	'1' => 'dead',
	'2' => 'dead',
	'3' => 'dead',
	'4' => 'dead',
	'5' => 'dead',
	'arrow_left' => 'exit_left',
	'arrow_right' => 'exit_right',
	'play' => 'play',
	'add' => 'add',
	'search' => 'passback',
	'stop' => 'passback',
	'pause' => 'passback'
);

sub defaultMap { 
	return \%mapping; 
}

sub getDisplayName()
{
	return $::VERSION =~ m/6\./ ? 'PLUGIN_TRACKSTAT' : string('PLUGIN_TRACKSTAT'); 
}

our %menuSelection;

sub setMode() 
{
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my @listRef = ();
	my $statistics = getStatisticPlugins();

	my $statistictype = $client->param('statistictype');
	my $showFlat = Slim::Utils::Prefs::get('plugin_trackstat_player_flatlist');
	if($showFlat || defined($client->param('flatlist'))) {
		foreach my $flatItem (sort keys %$statistics) {
			my $item = $statistics->{$flatItem};
			if($item->{'trackstat_statistic_enabled'}) {
				my %flatStatisticItem = (
					'item' => $item,
					'trackstat_statistic_enabled' => 1
				);
				if(defined($item->{'namefunction'})) {
					$flatStatisticItem{'name'} = &{$item->{'namefunction'}}();
				}else {
					$flatStatisticItem{'name'} = $item->{'name'};
				}
				$flatStatisticItem{'value'} = $flatStatisticItem{'name'};
				if(!defined($statistictype)) {
					push @listRef, \%flatStatisticItem;
				}else {
					if(defined($item->{'contextfunction'})) {
						my %contextParams = ();
						$contextParams{$statistictype} = $client->param($statistictype);
						my $valid = eval {&{$item->{'contextfunction'}}(\%contextParams)};
						if($valid) {
							push @listRef, \%flatStatisticItem;
						}
					}
				}
			}
		}
	}else {
		foreach my $menuItemKey (sort keys %statisticItems) {
			if($statisticItems{$menuItemKey}->{'trackstat_statistic_enabled'}) {
				if(!defined($statistictype)) {
					push @listRef, $statisticItems{$menuItemKey};
				}else {
					if(defined($statisticItems{$menuItemKey}->{'item'})) {
						my $item = $statisticItems{$menuItemKey}->{'item'};
						if(defined($item->{'contextfunction'})) {
							my %contextParams = ();
							$contextParams{$statistictype} = $client->param($statistictype);
							my $valid = eval {&{$item->{'contextfunction'}}(\%contextParams)};
							if($valid) {
								push @listRef, $statisticItems{$menuItemKey};
							}
						}
					}else {
						push @listRef, $statisticItems{$menuItemKey};
					}
				}
			}
		}
	}

	@listRef = sort { $a->{'name'} cmp $b->{'name'} } @listRef;
	
	# use INPUT.Choice to display the list of feeds
	my %params = (
		header     => '{PLUGIN_TRACKSTAT} {count}',
		listRef    => \@listRef,
		name       => \&getDisplayText,
		overlayRef => \&getOverlay,
		modeName   => 'PLUGIN.TrackStat::Plugin',
		onPlay     => sub {
			my ($client, $item) = @_;
			if(defined($item->{'item'})) {
				my %paramsData = (
					'player' => $client->id,
					'trackstatcmd' => 'play'
				);
				my $function = $item->{'item'}->{'webfunction'};
			    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_player_list_length");
			    if(!defined $listLength || $listLength==0) {
			    	$listLength = 20;
			    }
				debugMsg("Calling webfunction for ".$item->{'item'}->{'id'}."\n");
				eval {
					&{$function}(\%paramsData,$listLength);
				};
				handlePlayAdd($client,\%paramsData);
			}
		},
		onAdd      => sub {
			my ($client, $item) = @_;
			if(defined($item->{'item'})) {
				my %paramsData = (
					'player' => $client->id,
					'trackstatcmd' => 'add'
				);
				my $function = $item->{'item'}->{'webfunction'};
			    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_player_list_length");
			    if(!defined $listLength || $listLength==0) {
			    	$listLength = 20;
			    }
				debugMsg("Calling webfunction for ".$item->{'item'}->{'id'}."\n");
				eval {
					&{$function}(\%paramsData,$listLength);
				};
				handlePlayAdd($client,\%paramsData);
			}
		},
		onRight    => sub {
			my ($client, $item) = @_;
			if(defined($item->{'childs'})) {
				Slim::Buttons::Common::pushModeLeft($client,'INPUT.Choice',getSetModeDataForSubItems($client,$item,$item->{'childs'}));
			}else {
				my %paramsData = ();
				if(defined($client->param('statistictype'))) {
					$paramsData{'statistictype'} = $client->param('statistictype');
					$paramsData{$client->param('statistictype')} = $client->param($client->param('statistictype'));
				}
				my $params = getSetModeDataForStatistics($client,$item->{'item'},\%paramsData);
				if(defined($params)) {
					Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.TrackStat.Choice',$params);
				}else {
					$client->showBriefly(
						$item->{'name'},
						$client->string( 'PLUGIN_TRACKSTAT_NO_TRACK'),
						1);

				}
			}
		},
	);
	if(defined($statistictype)) {
		$params{'statistictype'} = $statistictype;
		$params{$statistictype} = $client->param($statistictype);
	}
	
	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub getDisplayText {
	my ($client, $item) = @_;

	my $name = '';
	if($item) {
		if(defined($item->{'item'})) {
			if(defined($item->{'item'}->{'namefunction'})) {
				$name = eval { &{$item->{'item'}->{'namefunction'}}() };
			}else {
				$name = $item->{'item'}->{'name'};
			}
		}else {
			$name = $item->{'name'};
		}
	}
	return $name;
}

sub getDataDisplayText {
	my ($client, $item) = @_;

	my $name = '';
	if($item) {
		if($item->{'listtype'} eq 'track') {
			$name=Slim::Music::Info::standardTitle($client,$item->{'itemobj'});
		}elsif($item->{'listtype'} eq 'album') {
			$name=$item->{'itemobj'}->{'album'}->title;
			if($item->{'rating'}) {
				$name .= '  '.($RATING_CHARACTER x $item->{'rating'});
			}
			if($item->{'song_count'}) {
				$name .= ' ('.$item->{'song_count'}.')';
			}
		}elsif($item->{'listtype'} eq 'artist') {
			$name=$item->{'itemobj'}->{'artist'}->name;
			if($item->{'rating'}) {
				$name .= '  '.($RATING_CHARACTER x $item->{'rating'});
			}
			if($item->{'song_count'}) {
				$name .= ' ('.$item->{'song_count'}.')';
			}
		}elsif($item->{'listtype'} eq 'genre') {
			$name=$item->{'itemobj'}->{'genre'}->name;
			if($item->{'rating'}) {
				$name .= '  '.($RATING_CHARACTER x $item->{'rating'});
			}
			if($item->{'song_count'}) {
				$name .= ' ('.$item->{'song_count'}.')';
			}
		}elsif($item->{'listtype'} eq 'year') {
			$name=$item->{'itemobj'}->{'year'};
			if($item->{'rating'}) {
				$name .= '  '.($RATING_CHARACTER x $item->{'rating'});
			}
			if($item->{'song_count'}) {
				$name .= ' ('.$item->{'song_count'}.')';
			}
		}elsif($item->{'listtype'} eq 'playlist') {
			$name=$item->{'itemobj'}->{'title'};
			if($item->{'rating'}) {
				$name .= '  '.($RATING_CHARACTER x $item->{'rating'});
			}
			if($item->{'song_count'}) {
				$name .= ' ('.$item->{'song_count'}.')';
			}
		}
	}
	return $name;
}

sub getOverlay {
	my ($client, $item) = @_;
	if(defined($item->{'item'})) {
		return [Slim::Display::Display::symbol('rightarrow'),Slim::Display::Display::symbol('notesymbol')];
	}else {
		return [undef, Slim::Display::Display::symbol('rightarrow')];
	}
}

sub getDataOverlay {
	my ($client, $item) = @_;
	if(defined($item->{'currentstatisticitems'})) {
		return [Slim::Display::Display::symbol('rightarrow'), Slim::Display::Display::symbol('notesymbol')];
	}else {
		return [undef, Slim::Display::Display::symbol('notesymbol')];
	}
}

sub getSetModeDataForSubItems {
	my $client = shift;
	my $currentItem = shift;
	my $items = shift;

	my @listRef = ();
	my $statistictype = $client->param('statistictype');
	foreach my $menuItemKey (sort keys %$items) {
		if($items->{$menuItemKey}->{'trackstat_statistic_enabled'}) {
			if(!defined($statistictype)) {
				push @listRef, $items->{$menuItemKey};
			}else {
				if(defined($items->{$menuItemKey}->{'item'})) {
					my $item = $items->{$menuItemKey}->{'item'};
					if(defined($item->{'contextfunction'})) {
						my %contextParams = ();
						$contextParams{$statistictype} = $client->param($statistictype);
						my $valid = eval {&{$item->{'contextfunction'}}(\%contextParams)};
						if($valid) {
							push @listRef, $statisticItems{$menuItemKey};
						}
					}
				}else {
					push @listRef, $items->{$menuItemKey};
				}
			}
		}
	}
	
	@listRef = sort { $a->{'name'} cmp $b->{'name'} } @listRef;

	my %params = (
		header     => '{PLUGIN_TRACKSTAT} {count}',
		listRef    => \@listRef,
		name       => \&getDisplayText,
		overlayRef => \&getOverlay,
		modeName   => 'PLUGIN.TrackStat::Plugin'.$currentItem->{'value'},
		onPlay     => sub {
			my ($client, $item) = @_;
			if(defined($item->{'item'})) {
				my %paramsData = (
					'player' => $client->id,
					'trackstatcmd' => 'play'
				);
				my $function = $item->{'item'}->{'webfunction'};
			    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_player_list_length");
			    if(!defined $listLength || $listLength==0) {
			    	$listLength = 20;
			    }
				debugMsg("Calling webfunction for ".$item->{'item'}->{'id'}."\n");
				eval {
					&{$function}(\%paramsData,$listLength);
				};
				handlePlayAdd($client,\%paramsData);
			}
		},
		onAdd      => sub {
			my ($client, $item) = @_;
			if(defined($item->{'item'})) {
				my %paramsData = (
					'player' => $client->id,
					'trackstatcmd' => 'add'
				);
				my $function = $item->{'item'}->{'webfunction'};
			    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_player_list_length");
			    if(!defined $listLength || $listLength==0) {
			    	$listLength = 20;
			    }
				debugMsg("Calling webfunction for ".$item->{'item'}->{'id'}."\n");
				eval {
					&{$function}(\%paramsData,$listLength);
				};
				handlePlayAdd($client,\%paramsData);
			}
		},
		onRight    => sub {
			my ($client, $item) = @_;
			if(defined($item->{'childs'})) {
				Slim::Buttons::Common::pushModeLeft($client,'INPUT.Choice',getSetModeDataForSubItems($client,$item,$item->{'childs'}));
			}else {
				my %paramsData = ();
				if(defined($client->param('statistictype'))) {
					$paramsData{'statistictype'} = $client->param('statistictype');
					$paramsData{$client->param('statistictype')} = $client->param($client->param('statistictype'));
				}
				my $params = getSetModeDataForStatistics($client,$item->{'item'},\%paramsData);
				if(defined($params)) {
					Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.TrackStat.Choice',$params);
				}else {
					$client->showBriefly(
						$item->{'name'},
						$client->string( 'PLUGIN_TRACKSTAT_NO_TRACK'),
						1);
				}
			}
		},
	);
	if(defined($statistictype)) {
		$params{'statistictype'} = $statistictype;
		$params{$statistictype} = $client->param($statistictype);
	}
	return \%params;
}

sub getSetModeDataForStatistics {
	my $client = shift;
	my $item = shift;
	my $paramsData = shift;

	if(!defined($paramsData)) {
		my %newParamsData = ();
		$paramsData = \%newParamsData;
	}
	my $function = $item->{'webfunction'};
    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_player_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
	debugMsg("Calling webfunction for ".$item->{'id'}."\n");
	eval {
		&{$function}($paramsData,$listLength);
	};
	my @listRef = ();
	foreach my $it (@{$paramsData->{'browse_items'}}) {
		if(defined($paramsData->{'currentstatisticitems'}) && defined($paramsData->{'currentstatisticitems'}->{$it->{'listtype'}})) {
			$it->{'currentstatisticitems'} = $paramsData->{'currentstatisticitems'}->{$it->{'listtype'}};
		}
		$it->{'value'} = $it->{'attributes'};
		push @listRef, $it;
	}
	
	my $name;
	if(defined($item->{'namefunction'})) {
		$name = eval { &{$item->{'namefunction'}}($paramsData) };
	}else {
		$name = $item->{'name'};
	}
	
	my %params = (
		header     => $name.' {count}',
		listRef    => \@listRef,
		name       => \&getDataDisplayText,
		overlayRef => \&getDataOverlay,
		parentMode => Slim::Buttons::Common::param($client,'parentMode'),
		onPlay     => sub {
			my ($client, $item) = @_;
			my $request;
			if($item->{'listtype'} eq 'track') {
				$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('track'),$item->{'itemobj'}->id)]);
			}elsif($item->{'listtype'} eq 'album') {
				$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('album'),$item->{'itemobj'}->{'album'}->id)]);
			}elsif($item->{'listtype'} eq 'artist') {
				$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('artist'),$item->{'itemobj'}->{'artist'}->id)]);
			}elsif($item->{'listtype'} eq 'genre') {
				$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('genre'),$item->{'itemobj'}->{'genre'}->id)]);
			}elsif($item->{'listtype'} eq 'year') {
				$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('year'),$item->{'itemobj'}->{'year'}->id)]);
			}elsif($item->{'listtype'} eq 'playlist') {
				$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('playlist'),$item->{'itemobj'}->id)]);
			}
			
			if ($::VERSION ge '6.5') {
				# indicate request source
				$request->source('PLUGIN_TRACKSTAT');
			}
		},
		onAdd      => sub {
			my ($client, $item) = @_;
			my $request;
			if($item->{'listtype'} eq 'track') {
				$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('track'),$item->{'itemobj'}->id)]);
			}elsif($item->{'listtype'} eq 'album') {
				$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('album'),$item->{'itemobj'}->{'album'}->id)]);
			}elsif($item->{'listtype'} eq 'artist') {
				$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('artist'),$item->{'itemobj'}->{'artist'}->id)]);
			}elsif($item->{'listtype'} eq 'genre') {
				$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('genre'),$item->{'itemobj'}->{'genre'}->id)]);
			}elsif($item->{'listtype'} eq 'year') {
				$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('year'),$item->{'itemobj'}->{'year'}->id)]);
			}elsif($item->{'listtype'} eq 'playlist') {
				$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('playlist'),$item->{'itemobj'}->id)]);
			}
			
			if ($::VERSION ge '6.5') {
				# indicate request source
				$request->source('PLUGIN_TRACKSTAT');
			}
		},
		onRight    => sub {
			my ($client, $item) = @_;
			my %paramsDataSub = ();
			if(defined($item->{'currentstatisticitems'})) {
				if($item->{'listtype'} eq 'album') {
					$paramsDataSub{'album'} = $item->{'itemobj'}->{'album'}->id;
				}elsif($item->{'listtype'} eq 'artist') {
					$paramsDataSub{'artist'} = $item->{'itemobj'}->{'artist'}->id;
				}elsif($item->{'listtype'} eq 'genre') {
					$paramsDataSub{'genre'} = $item->{'itemobj'}->{'genre'}->id;
				}elsif($item->{'listtype'} eq 'year') {
					$paramsDataSub{'year'} = $item->{'itemobj'}->{'year'};
				}elsif($item->{'listtype'} eq 'playlist') {
					$paramsDataSub{'playlist'} = $item->{'itemobj'}->id;
				}
			    my $statistics = getStatisticPlugins();
				my $subitem = $statistics->{$item->{'currentstatisticitems'}};

				my $params = getSetModeDataForStatistics($client,$subitem,\%paramsDataSub);
				if(defined($params)) {
					Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.TrackStat.Choice',$params);
				}else {
					$client->showBriefly(
						$item->{'name'},
						$client->string( 'PLUGIN_TRACKSTAT_NO_TRACK'),
						1);
				}
			}else {
				if($item->{'listtype'} eq 'track') {
					my $trackHandle = Plugins::TrackStat::Storage::findTrack( $item->{'itemobj'}->url,undef,$item->{'itemobj'});
					my $displayStr;
					my $headerStr;
					if($trackHandle) {
						if($trackHandle->rating) {
							my $rating = $trackHandle->rating;
							if($rating) {
								$rating = floor(($rating+10) / 20);
								$displayStr = $client->string( 'PLUGIN_TRACKSTAT_RATING').($RATING_CHARACTER x $rating);
							}
						}
						if($trackHandle->playCount) {
							my $playCount = $trackHandle->playCount;
							if($displayStr) {
								$displayStr .= '    '.$client->string( 'PLUGIN_TRACKSTAT_PLAY_COUNT').' '.$playCount;
							}else {
								$displayStr = $client->string( 'PLUGIN_TRACKSTAT_PLAY_COUNT').' '.$playCount;
							}
						}
						if($trackHandle->lastPlayed) {
							my $lastPlayed = $trackHandle->lastPlayed;
							$headerStr = $client->string( 'PLUGIN_TRACKSTAT_LAST_PLAYED').' '.Slim::Utils::Misc::shortDateF($lastPlayed).' '.Slim::Utils::Misc::timeF($lastPlayed);
						}
					}
					if(!$displayStr) {
						$displayStr = $client->string( 'PLUGIN_TRACKSTAT_NO_TRACK');
					}
					if(!$headerStr) {
						$headerStr = $client->string( 'PLUGIN_TRACKSTAT');
					}

					$client->showBriefly(
						$headerStr,
						$displayStr,
						1);
				}else {
					Slim::Display::Animation::bumpRight($client);
				}
			}
		}
	);
	if(scalar(@listRef)>0) {
		return \%params;
	}else {
		return undef;
	}
}

sub enabled() 
{
	my $client = shift;
	return 1;
}

my %functions = ();

sub saveRatingsForCurrentlyPlaying {
	my $client = shift;
	my $button = shift;
	my $digit = shift;

	return unless $digit>='0' && $digit<='5';

	my $playStatus = getPlayerStatusForClient($client);
	if ($playStatus->isTiming() eq 'true') {
		# see if the string is already in the cache
		my $songKey;
        my $song = Slim::Player::Playlist::song($client);
    	$song = $song->url;
        $songKey = $song;
        if (Slim::Music::Info::isRemoteURL($song)) {
                $songKey = Slim::Music::Info::getCurrentTitle($client, $song);
        }
        if($playStatus->currentTrackOriginalFilename() eq $songKey) {
			$playStatus->currentSongRating($digit);
		}
    	debugMsg("saveRating: $client, $songKey, $digit\n");
		$client->showBriefly(
			$client->string( 'PLUGIN_TRACKSTAT'),
			$client->string( 'PLUGIN_TRACKSTAT_RATING').($RATING_CHARACTER x $digit),
			3);
		rateSong($client,$songKey,$digit*20);
	}else {
		$client->showBriefly(
			$client->string( 'PLUGIN_TRACKSTAT'),
			$client->string( 'PLUGIN_TRACKSTAT_RATING_NO_SONG'),
			3);
	}
}
sub saveRatingsFromChoice {
		my $client = shift;
		my $button = shift;
		my $digit = shift;

	return unless $digit>='0' && $digit<='5';

		my $listRef = Slim::Buttons::Common::param($client,'listRef');
        my $listIndex = Slim::Buttons::Common::param($client,'listIndex');
        my $item = $listRef->[$listIndex];
        if($item->{'listtype'} eq 'track') {
        	debugMsg("saveRating: $client, ".$item->{'itemobj'}->url.", $digit\n");
			rateSong($client,$item->{'itemobj'}->url,$digit*20);
        	my $title = Slim::Music::Info::standardTitle($client,$item->{'itemobj'});
			$client->showBriefly(
				$title,
				$client->string( 'PLUGIN_TRACKSTAT_RATING').($RATING_CHARACTER x $digit),
				1);
        	
		}
}	
sub getTrackInfo {
		debugMsg("Entering getTrackInfo\n");
		my $client = shift;
		my $playStatus = getPlayerStatusForClient($client);
		if ($playStatus->isTiming() eq 'true') {
			if ($playStatus->trackAlreadyLoaded() eq 'false') {
				my $ds = Plugins::TrackStat::Storage::getCurrentDS();
				my $track;
				# The encapsulation with eval is just to make it more crash safe
				eval {
					$track = Plugins::TrackStat::Storage::objectForUrl($playStatus->currentTrackOriginalFilename());
				};
				if ($@) {
					debugMsg("Error retrieving track: ".$playStatus->currentTrackOriginalFilename()."\n");
				}
				my $trackHandle = Plugins::TrackStat::Storage::findTrack( $playStatus->currentTrackOriginalFilename(),undef,$track);
				my $playedCount = 0;
				my $playedDate = "";
				my $rating = 0;
				if ($trackHandle) {
						if($trackHandle->playCount) {
							$playedCount = $trackHandle->playCount;
						}elsif(getPlayCount($track)){
							$playedCount = getPlayCount($track);
						}
						if($trackHandle->lastPlayed) {
							$playedDate = Slim::Utils::Misc::shortDateF($trackHandle->lastPlayed).' '.Slim::Utils::Misc::timeF($trackHandle->lastPlayed);
						}elsif(getLastPlayed($track)) {
							$playedDate = Slim::Utils::Misc::shortDateF(getLastPlayed($track)).' '.Slim::Utils::Misc::timeF(getLastPlayed($track));
						}
						if($trackHandle->rating) {
							$rating = $trackHandle->rating;
							if($rating) {
								$rating = floor(($rating+10) / 20);
							}
						}
				}else {
					if($track) {
						$playedCount = getPlayCount($track);
						if(getLastPlayed($track)) {
							$playedDate = Slim::Utils::Misc::shortDateF(getLastPlayed($track)).' '.Slim::Utils::Misc::timeF(getLastPlayed($track));
						}
					}
				}
				
				$playStatus->trackAlreadyLoaded('true');
				$playStatus->lastPlayed($playedDate);
				$playStatus->playCount($playedCount);
				#don't overwrite the user's rating
				if ($playStatus->currentSongRating() eq '') {
					$playStatus->currentSongRating($rating);
				}
			}
		} else { 
			debugMsg("Exiting getTrackInfo\n");
			return undef;
		}
		debugMsg("Exiting getTrackInfo\n");
		return $playStatus;
}

sub getFunctions() 
{
	return \%functions;
}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_trackstat_backup_file','plugin_trackstat_backup_dir','plugin_trackstat_backup_time','plugin_trackstat_backup','plugin_trackstat_restore','plugin_trackstat_clear','plugin_trackstat_refresh_tracks','plugin_trackstat_purge_tracks','plugin_trackstat_itunes_import','plugin_trackstat_itunes_export','plugin_trackstat_itunes_enabled','plugin_trackstat_itunes_library_file','plugin_trackstat_itunes_export_dir','plugin_trackstat_itunes_export_library_music_path','plugin_trackstat_itunes_library_music_path','plugin_trackstat_itunes_replace_extension','plugin_trackstat_itunes_export_replace_extension','plugin_trackstat_musicmagic_enabled','plugin_trackstat_musicmagic_host','plugin_trackstat_musicmagic_port','plugin_trackstat_musicmagic_library_music_path','plugin_trackstat_musicmagic_replace_extension','plugin_trackstat_musicmagic_slimserver_replace_extension','plugin_trackstat_musicmagic_import','plugin_trackstat_musicmagic_export','plugin_trackstat_dynamicplaylist','plugin_trackstat_recent_number_of_days','plugin_trackstat_recentadded_number_of_days','plugin_trackstat_web_flatlist','plugin_trackstat_player_flatlist','plugin_trackstat_deep_hierarchy','plugin_trackstat_web_list_length','plugin_trackstat_player_list_length','plugin_trackstat_playlist_length','plugin_trackstat_playlist_per_artist_length','plugin_trackstat_web_refresh','plugin_trackstat_web_show_mixerlinks','plugin_trackstat_web_enable_mixerfunction','plugin_trackstat_enable_mixerfunction','plugin_trackstat_force_grouprating','plugin_trackstat_ratingchar','plugin_trackstat_min_artist_tracks','plugin_trackstat_min_album_tracks','plugin_trackstat_min_song_length','plugin_trackstat_song_threshold_length','plugin_trackstat_min_song_percent','plugin_trackstat_refresh_startup','plugin_trackstat_refresh_rescan','plugin_trackstat_history_enabled','plugin_trackstat_showmessages'],
	 GroupHead => string('PLUGIN_TRACKSTAT_SETUP_GROUP'),
	 GroupDesc => string('PLUGIN_TRACKSTAT_SETUP_GROUP_DESC'),
	 GroupLine => 1,
	 GroupSub  => 1,
	 Suppress_PrefSub  => 1,
	 Suppress_PrefLine => 1
	);
	my %setupPrefs =
	(
	plugin_trackstat_showmessages => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_SHOW_MESSAGES')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_SHOW_MESSAGES')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_showmessages"); }
		},		
	plugin_trackstat_force_grouprating => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_FORCE_GROUPRATING')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_FORCE_GROUPRATING')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_force_grouprating"); }
		},		
	plugin_trackstat_deep_hierarchy => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_DEEP_HIERARCHY')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_DEEP_HIERARCHY')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_deep_hierarchy"); }
		},		
	plugin_trackstat_web_flatlist => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_WEB_FLATLIST')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_WEB_FLATLIST')
			,'options' => {
					 '0' => string('ON')
					,'1' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_web_flatlist"); }
		},		
	plugin_trackstat_player_flatlist => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_PLAYER_FLATLIST')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_PLAYER_FLATLIST')
			,'options' => {
					 '0' => string('ON')
					,'1' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_player_flatlist"); }
		},		
	plugin_trackstat_refresh_startup => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_REFRESH_STARTUP')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_REFRESH_STARTUP')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_refresh_startup"); }
		},		
	plugin_trackstat_history_enabled => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_HISTORY_ENABLED')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_HISTORY_ENABLED')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_history_enabled"); }
		},		
	plugin_trackstat_refresh_rescan => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_REFRESH_RESCAN')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_REFRESH_RESCAN')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_refresh_rescan"); }
		},		
	plugin_trackstat_dynamicplaylist => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_DYNAMICPLAYLIST')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_DYNAMICPLAYLIST')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist"); }
		},		
	plugin_trackstat_web_list_length => {
			'validate'     => \&validateIntWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_WEB_LIST_LENGTH')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_WEB_LIST_LENGTH')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_web_list_length"); }
		},		
	plugin_trackstat_player_list_length => {
			'validate'     => \&validateIntWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_PLAYER_LIST_LENGTH')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_PLAYER_LIST_LENGTH')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_player_list_length"); }
		},		
	plugin_trackstat_playlist_length => {
			'validate'     => \&validateIntWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_PLAYLIST_LENGTH')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_PLAYLIST_LENGTH')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_playlist_length"); }
		},		
	plugin_trackstat_recent_number_of_days => {
			'validate'     => \&validateIntWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_RECENT_NUMBER_OF_DAYS')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_RECENT_NUMBER_OF_DAYS')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_recent_number_of_days"); }
		},		
	plugin_trackstat_recentadded_number_of_days => {
			'validate'     => \&validateIntWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_RECENTADDED_NUMBER_OF_DAYS')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_RECENTADDED_NUMBER_OF_DAYS')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_recentadded_number_of_days"); }
		},		
	plugin_trackstat_song_threshold_length => {
			'validate'     => \&validateIntWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_SONG_THRESHOLD_LENGTH')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_SONG_THRESHOLD_LENGTH')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_song_threshold_length"); }
		},		
	plugin_trackstat_min_artist_tracks => {
			'validate'     => \&validateIntWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_MIN_ARTIST_TRACKS')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MIN_ARTIST_TRACKS')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_min_artist_tracks"); }
		},		
	plugin_trackstat_min_album_tracks => {
			'validate'     => \&validateIntWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_MIN_ALBUM_TRACKS')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MIN_ALBUM_TRACKS')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_min_album_tracks"); }
		},		
	plugin_trackstat_min_song_length => {
			'validate'     => \&validateIntWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_MIN_SONG_LENGTH')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MIN_SONG_LENGTH')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_min_song_length"); }
		},		
	plugin_trackstat_min_song_percent => {
			'validate'     => \&validateIntWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_MIN_SONG_PERCENT')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MIN_SONG_PERCENT')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_min_song_percent"); }
		},		
	plugin_trackstat_playlist_per_artist_length => {
			'validate'     => \&validateIntWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_PLAYLIST_PER_ARTIST_LENGTH')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_PLAYLIST_PER_ARTIST_LENGTH')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_playlist_per_artist_length"); }
		},		
	plugin_trackstat_web_refresh => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_WEB_REFRESH')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_WEB_REFRESH')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_web_refresh"); }
		},		
	plugin_trackstat_web_show_mixerlinks => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_WEB_SHOW_MIXERLINKS')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_WEB_SHOW_MIXERLINKS')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_web_show_mixerlinks"); }
		},		
	plugin_trackstat_web_enable_mixerfunction => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_WEB_ENABLE_MIXERFUNCTION')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_WEB_ENABLE_MIXERFUNCTION')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_web_enable_mixerfunction"); }
		},		
	plugin_trackstat_enable_mixerfunction => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_TRACKSTAT_ENABLE_MIXERFUNCTION')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_ENABLE_MIXERFUNCTION')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_enable_mixerfunction"); }
		},		
	plugin_trackstat_backup_file => {
			'validate' => \&validateAcceptAllWrapper
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_BACKUP_FILE')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_BACKUP_FILE')
			,'rejectMsg' => string('SETUP_BAD_FILE')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_backup_file"); }
		},
	plugin_trackstat_backup_dir => {
			'validate' => \&validateIsDirOrEmpty
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_BACKUP_DIR')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_BACKUP_DIR')
			,'rejectMsg' => string('SETUP_BAD_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_backup_dir"); }
		},
	plugin_trackstat_backup_time => {
			'validate' => \&validateIsTimeOrEmpty
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_BACKUP_TIME')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_BACKUP_TIME')
			,'PrefSize' => 'small'
			,'currentValue' => sub { return Slim::Utils::Prefs::get( "plugin_trackstat_backup_time"); }
		},
	plugin_trackstat_backup => {
			'validate' => \&validateAcceptAllWrapper
			,'onChange' => sub { backupToFile(); }
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MAKING_BACKUP')
			,'ChangeButton' => string('PLUGIN_TRACKSTAT_BACKUP')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
	plugin_trackstat_refresh_tracks => {
			'validate' => \&validateAcceptAllWrapper
			,'onChange' => sub { Plugins::TrackStat::Storage::refreshTracks(); }
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_TRACKSTAT_REFRESHING_TRACKS')
			,'ChangeButton' => string('PLUGIN_TRACKSTAT_REFRESH_TRACKS')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
	plugin_trackstat_purge_tracks => {
			'validate' => \&validateAcceptAllWrapper
			,'onChange' => sub { Plugins::TrackStat::Storage::purgeTracks(); }
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_TRACKSTAT_PURGING_TRACKS')
			,'ChangeButton' => string('PLUGIN_TRACKSTAT_PURGE_TRACKS')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
	plugin_trackstat_restore => {
			'validate' => \&validateAcceptAllWrapper
			,'onChange' => sub { restoreFromFile(); }
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_TRACKSTAT_RESTORING_BACKUP')
			,'ChangeButton' => string('PLUGIN_TRACKSTAT_RESTORE')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
	plugin_trackstat_clear => {
			'validate' => \&validateAcceptAllWrapper
			,'onChange' => sub { Plugins::TrackStat::Storage::deleteAllTracks(); }
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_TRACKSTAT_CLEARING')
			,'ChangeButton' => string('PLUGIN_TRACKSTAT_CLEAR')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
	plugin_trackstat_itunes_library_file => {
			'validate' => \&validateIsFileOrEmpty
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_ITUNES_LIBRARY_FILE')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_ITUNES_LIBRARY_FILE')
			,'rejectMsg' => string('SETUP_BAD_FILE')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_itunes_library_file"); }
		},
	plugin_trackstat_itunes_export_dir => {
			'validate' => \&validateIsDirOrEmpty
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_ITUNES_EXPORT_DIR')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_ITUNES_EXPORT_DIR')
			,'rejectMsg' => string('SETUP_BAD_FILE')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_itunes_export_dir"); }
		},
	plugin_trackstat_itunes_export_library_music_path => {
			'validate' => \&validateAcceptAllWrapper
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_ITUNES_EXPORT_MUSIC_DIRECTORY')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_ITUNES_EXPORT_MUSIC_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_itunes_export_library_music_path"); }
		},
	plugin_trackstat_itunes_library_music_path => {
			'validate' => \&validateIsDirOrEmpty
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_ITUNES_MUSIC_DIRECTORY')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_ITUNES_MUSIC_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_itunes_library_music_path"); }
		},
	plugin_trackstat_itunes_replace_extension => {
			'validate' => \&validateAcceptAllWrapper
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_ITUNES_REPLACE_EXTENSION')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_ITUNES_REPLACE_EXTENSION')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_itunes_replace_extension"); }
		},
	plugin_trackstat_itunes_export_replace_extension => {
			'validate' => \&validateAcceptAllWrapper
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_ITUNES_EXPORT_REPLACE_EXTENSION')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_ITUNES_EXPORT_REPLACE_EXTENSION')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_itunes_export_replace_extension"); }
		},
	plugin_trackstat_itunes_enabled => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_ITUNES_ENABLED')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_ITUNES_ENABLED')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_itunes_enabled"); }
		},		
	plugin_trackstat_musicmagic_enabled => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_ENABLED')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_ENABLED')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_enabled"); }
		},		
	plugin_trackstat_musicmagic_host => {
			'validate' => \&validateAcceptAllWrapper
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_HOST')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_HOST')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_host"); }
		},
	plugin_trackstat_musicmagic_port => {
			'validate' => \&validateIntWrapper
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_PORT')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_PORT')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_port"); }
		},
	plugin_trackstat_musicmagic_library_music_path => {
			'validate' => \&validateAcceptAllWrapper
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_MUSIC_DIRECTORY')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_MUSIC_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_library_music_path"); }
		},
	plugin_trackstat_musicmagic_replace_extension => {
			'validate' => \&validateAcceptAllWrapper
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_REPLACE_EXTENSION')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_REPLACE_EXTENSION')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_replace_extension"); }
		},
	plugin_trackstat_musicmagic_slimserver_replace_extension => {
			'validate' => \&validateAcceptAllWrapper
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_SLIMSERVER_REPLACE_EXTENSION')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_SLIMSERVER_REPLACE_EXTENSION')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_slimserver_replace_extension"); }
		},
	plugin_trackstat_itunes_import => {
			'validate' => \&validateAcceptAllWrapper
			,'onChange' => sub { importFromiTunes(); }
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_TRACKSTAT_ITUNES_IMPORTING')
			,'ChangeButton' => string('PLUGIN_TRACKSTAT_ITUNES_IMPORT_BUTTON')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
	plugin_trackstat_itunes_export => {
			'validate' => \&validateAcceptAllWrapper
			,'onChange' => sub { exportToiTunes(); }
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_TRACKSTAT_ITUNES_EXPORTING')
			,'ChangeButton' => string('PLUGIN_TRACKSTAT_ITUNES_EXPORT_BUTTON')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
	plugin_trackstat_musicmagic_import => {
			'validate' => \&validateAcceptAllWrapper
			,'onChange' => sub { importFromMusicMagic(); }
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_IMPORTING')
			,'ChangeButton' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_IMPORT_BUTTON')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
	plugin_trackstat_musicmagic_export => {
			'validate' => \&validateAcceptAllWrapper
			,'onChange' => sub { exportToMusicMagic(); }
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_EXPORTING')
			,'ChangeButton' => string('PLUGIN_TRACKSTAT_MUSICMAGIC_EXPORT_BUTTON')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
	plugin_trackstat_ratingchar => {
			'validate' => \&validateAcceptAllWrapper
			,'onChange' => sub { initRatingChar(); }
			,'PrefChoose' => string('PLUGIN_TRACKSTAT_RATINGCHAR')
			,'changeIntro' => string('PLUGIN_TRACKSTAT_RATINGCHAR')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_trackstat_ratingchar"); }
		},
	);
	initStatisticPlugins();
	return (\%setupGroup,\%setupPrefs);
}

sub webPages {
	my %pages = (
		"index\.htm" => \&handleWebIndex,
		"selectstatistics\.(?:htm|xml)" => \&handleWebSelectStatistics,
		"saveselectstatistics\.(?:htm|xml)" => \&handleWebSaveSelectStatistics
	);
	
	my $statistics = getStatisticPlugins();
	for my $item (keys %$statistics) {
		my $id = $statistics->{$item}->{'id'};
		$id = $id."\.htm";
		#debugMsg("Adding page: $id\n");
		$pages{$id} = \&handleWebStatistics;
	}

	return (\%pages,"index.html");
}

sub baseWebPage {
	my ($client, $params) = @_;
	
	debugMsg("Entering baseWebPage\n");
	if($params->{trackstatcmd} and $params->{trackstatcmd} eq 'listlength') {
		Slim::Utils::Prefs::set("plugin_trackstat_web_list_length",$params->{listlength});
		Slim::Utils::Prefs::set("plugin_trackstat_player_list_length",$params->{playerlistlength});
	}elsif($params->{trackstatcmd} and $params->{trackstatcmd} eq 'playlistlength') {
		Slim::Utils::Prefs::set("plugin_trackstat_playlist_length",$params->{playlistlength});
	}
	my $playStatus = undef;
	# without a player, don't do anything
	if ($client = Slim::Player::Client::getClient($params->{player})) {
		$playStatus = getTrackInfo($client);
		if ($params->{trackstatcmd} and $params->{trackstatcmd} eq 'rating') {
			my $songKey;
	        if ($params->{trackstattrackid}) {
				my $ds = Plugins::TrackStat::Storage::getCurrentDS();
				my $track     = Plugins::TrackStat::Storage::objectForId('track',$params->{trackstattrackid});
				if(defined($track)) {
					$songKey = $track->url;
				}
	        }elsif ($playStatus) {
		        my $song  = Slim::Player::Playlist::song($client);
	        	$song = $song->url;
		        $songKey = $song;
		        if (Slim::Music::Info::isRemoteURL($song)) {
		                $songKey = Slim::Music::Info::getCurrentTitle($client, $song);
		        }
		    }
	        if(defined($playStatus) && $playStatus->currentTrackOriginalFilename() eq $songKey) {
				if (!$playStatus->currentSongRating()) {
					$playStatus->currentSongRating(0);
				}
				if ($params->{trackstatrating} eq 'up' and $playStatus->currentSongRating() < 5) {
					$playStatus->currentSongRating($playStatus->currentSongRating() + 1);
				} elsif ($params->{trackstatrating} eq 'down' and $playStatus->currentSongRating() > 0) {
					$playStatus->currentSongRating($playStatus->currentSongRating() - 1);
				} elsif ($params->{trackstatrating} >= 0 or $params->{trackstatrating} <= 5) {
					$playStatus->currentSongRating($params->{trackstatrating});
				}
				
				rateSong($client,$songKey,$playStatus->currentSongRating()*20);
			}elsif($params->{trackstattrackid}) {
				if ($params->{trackstatrating} >= 0 or $params->{trackstatrating} <= 5) {
					rateSong($client,$songKey,$params->{trackstatrating}*20);
				}
			}
		}elsif($params->{trackstatcmd} and $params->{trackstatcmd} eq 'albumrating') {
			my $album = $params->{album};
			if ($album) {
				if ($params->{trackstatrating} >= 0 or $params->{trackstatrating} <= 5) {
					my $unratedTracks;
					if(Slim::Utils::Prefs::get("plugin_trackstat_force_grouprating")) {
						$unratedTracks = Plugins::TrackStat::Storage::getTracksOnAlbum($album);
					}else {
						$unratedTracks = Plugins::TrackStat::Storage::getUnratedTracksOnAlbum($album);
					}
					foreach my $url (@$unratedTracks) {
						rateSong($client,$url,$params->{trackstatrating}*20);
					}
				}
			}
		}
	}
	if(defined($playStatus)) {
		$params->{playing} = $playStatus->trackAlreadyLoaded();
		if(Slim::Utils::Prefs::get("plugin_trackstat_web_refresh")) {
			$params->{refresh} = $playStatus->currentTrackLength()-$playStatus->currentSongStopwatch()->getElapsedTime()+30;
			if($params->{refresh}<0){
				$params->{refresh} = 30;
			}
		}
		$params->{track} = $playStatus->currentSongTrack();
		$params->{rating} = $playStatus->currentSongRating();
		$params->{lastPlayed} = $playStatus->lastPlayed();
		$params->{playCount} = $playStatus->playCount();
	} 

	my $statisticItems = getStatisticItemsForContext($client,$params,\%statisticItems,1);
	my $statisticGroups = getStatisticGroupsForContext($client,$params,\%statisticItems,1);
	my $context = getStatisticContext($client,$params,\%statisticItems,1);
	$params->{'pluginTrackStatStatisticGroups'} = $statisticGroups;
	$params->{'pluginTrackStatNoOfStatisticGroupsPerColumn'} = scalar(@$statisticGroups)/3;
	$params->{'pluginTrackStatStatisticItems'} = $statisticItems;
	$params->{'pluginTrackStatNoOfStatisticItemsPerColumn'} = scalar(@$statisticItems)/3;
	$params->{'pluginTrackStatStatisticContext'} = $context;
	if($context && scalar(@$context)>0) {
		$params->{'pluginTrackStatStatisticContextPath'} = $context->[-1]->{'url'};
	}
	if($params->{flatlist}) {
		$params->{'pluginTrackStatFlatlist'}=1;
	}
	$params->{'pluginTrackStatListLength'} = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
	$params->{'pluginTrackStatPlayerListLength'} = Slim::Utils::Prefs::get("plugin_trackstat_player_list_length");
	$params->{'pluginTrackStatPlayListLength'} = Slim::Utils::Prefs::get("plugin_trackstat_playlist_length");
	$params->{'pluginTrackStatShowMixerLinks'} = Slim::Utils::Prefs::get("plugin_trackstat_web_show_mixerlinks");
	if(Slim::Utils::Prefs::get("plugin_trackstat_web_refresh")) {
		$params->{refresh} = 60 if (!$params->{refresh} || $params->{refresh} > 60);
	}
	if ($::VERSION ge '6.5') {
		$params->{'pluginTrackStatSlimserver65'} = 1;
	}
	debugMsg("Exiting baseWebPage\n");
}
	
sub getStatisticContext {
	my $client = shift;
	my $params = shift;
	my $currentItems = shift;
	my $level = shift;
	my @result = ();
	debugMsg("Get statistic context for level=$level\n");
	if(defined($params->{'group'.$level})) {
		my $group = unescape($params->{'group'.$level});
		my $item = $currentItems->{'group_'.$group};
		if(defined($item) && !defined($item->{'item'})) {
			my $currentUrl = "&group".$level."=".escape($group);
			my %resultItem = (
				'url' => $currentUrl,
				'name' => $group,
				'trackstat_statistic_enabled' => $item->{'trackstat_statistic_enabled'}
			);
			push @result, \%resultItem;

			if(defined($item->{'childs'})) {
				my $childResult = getStatisticContext($client,$params,$item->{'childs'},$level+1);
				for my $child (@$childResult) {
					$child->{'url'} = $currentUrl.$child->{'url'};
					push @result,$child;
				}
			}
		}
	}
	return \@result;
}

sub getStatisticGroupsForContext {
	my $client = shift;
	my $params = shift;
	my $currentItems = shift;
	my $level = shift;
	my @result = ();
	
	if(Slim::Utils::Prefs::get('plugin_trackstat_web_flatlist') || $params->{'flatlist'}) {
		return \@result;
	}

	if(defined($params->{'group'.$level})) {
		my $group = unescape($params->{'group'.$level});
		my $item = $currentItems->{'group_'.$group};
		if(defined($item) && !defined($item->{'item'})) {
			if(defined($item->{'childs'})) {
				return getStatisticGroupsForContext($client,$params,$item->{'childs'},$level+1);
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
			if(!defined($item->{'item'}) && defined($item->{'name'}) && $item->{'trackstat_statistic_enabled'}) {
				my $currentUrl = $url."&group".$level."=".escape($item->{'name'});
				my %resultItem = (
					'url' => $currentUrl,
					'name' => $item->{'name'},
					'trackstat_statistic_enabled' => $item->{'trackstat_statistic_enabled'}
				);
				push @result, \%resultItem;
			}
		}
	}
	@result = sort { $a->{'name'} cmp $b->{'name'} } @result;
	return \@result;
}

sub getStatisticItemsForContext {
	my $client = shift;
	my $params = shift;
	my $currentItems = shift;
	my $level = shift;
	my @result = ();
	my @contextResult = ();
	
	if(Slim::Utils::Prefs::get('plugin_trackstat_web_flatlist') || $params->{'flatlist'}) {
		foreach my $itemKey (keys %statisticPlugins) {
			my $item = $statisticPlugins{$itemKey};
			if(defined($item->{'contextfunction'}) && $item->{'trackstat_statistic_enabled'}) {
				my $name;
				if(defined($item->{'namefunction'})) {
					$name = eval { &{$item->{'namefunction'}}() };
				}else {
					$name = $item->{'name'};
				}
				my %listItem = (
					'name' => $name,
					'item' => $item
				);
				push @result, \%listItem;
				my $valid = eval {&{$item->{'contextfunction'}}($params)};
				if($valid) {
					push @contextResult, \%listItem;
				}
			}
		}
	}else {
		if(defined($params->{'group'.$level})) {
			my $group = unescape($params->{'group'.$level});
			my $item = $currentItems->{'group_'.$group};
			if(defined($item) && !defined($item->{'item'})) {
				if(defined($item->{'childs'})) {
					return getStatisticItemsForContext($client,$params,$item->{'childs'},$level+1);
				}else {
					return \@result;
				}
			}
		}else {
			for my $itemKey (keys %$currentItems) {
				my $item = $currentItems->{$itemKey};
				if(defined($item->{'item'}) && $item->{'trackstat_statistic_enabled'}) {
					my $item = $item->{'item'};
					if(defined($item->{'contextfunction'})) {
						my $name;
						if(defined($item->{'namefunction'})) {
							$name = eval { &{$item->{'namefunction'}}() };
						}else {
							$name = $item->{'name'};
						}
						my %listItem = (
							'name' => $name,
							'item' => $item
						);
						push @result, \%listItem;
						my $valid = eval {&{$item->{'contextfunction'}}($params)};
						if($valid) {
							push @contextResult, \%listItem;
						}
					}
				}
			}
		}
	}
	if(scalar(@contextResult)) {
		@result = @contextResult;
	}
	@result = sort { $a->{'name'} cmp $b->{'name'} } @result;
	return \@result;
}

sub handlePlayAdd {
	my ($client, $params) = @_;

	if ($client = Slim::Player::Client::getClient($params->{player})) {
		my $first = 1;
		if($params->{trackstatcmd} and $params->{trackstatcmd} eq 'play') {
			$client->execute(['stop']);
			$client->execute(['power', '1']);
		}elsif($params->{trackstatcmd} and $params->{trackstatcmd} eq 'add') {
			$first = 0;
		}elsif($params->{trackstatcmd} and $params->{trackstatcmd} eq 'playdynamic') {
			my $request = $client->execute(['dynamicplaylist', 'playlist', 'play', $params->{'dynamicplaylist'}]);
			if ($::VERSION ge '6.5') {
				# indicate request source
				$request->source('PLUGIN_TRACKSTAT');
			}
			return;
		}elsif($params->{trackstatcmd} and $params->{trackstatcmd} eq 'adddynamic') {
			my $request = $client->execute(['dynamicplaylist', 'playlist', 'add', $params->{'dynamicplaylist'}]);
			if ($::VERSION ge '6.5') {
				# indicate request source
				$request->source('PLUGIN_TRACKSTAT');
			}
			return;
		}else {
			return;
		}
		my $objs = $params->{'browse_items'};
		
		for my $item (@$objs) {
			my $request;
			if($item->{'listtype'} eq 'track') {
				my $track = $item->{'itemobj'};
				if($first==1) {
					debugMsg("Loading track = ".$track->title."\n");
					$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('track'),$track->id)]);
				}else {
					debugMsg("Adding track = ".$track->title."\n");
					$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('track'),$track->id)]);
				}
			}elsif($item->{'listtype'} eq 'album') {
				my $album = $item->{'itemobj'}{'album'};
				if($first==1) {
					debugMsg("Loading album = ".$album->title."\n");
					$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('album'),$album->id)]);
				}else {
					debugMsg("Adding album = ".$album->title."\n");
					$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('album'),$album->id)]);
				}
			}elsif($item->{'listtype'} eq 'artist') {
				my $artist = $item->{'itemobj'}{'artist'};
				if($first==1) {
					debugMsg("Loading artist = ".$artist->name."\n");
					$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('artist'),$artist->id)]);
				}else {
					debugMsg("Adding artist = ".$artist->name."\n");
					$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('artist'),$artist->id)]);
				}
			}elsif($item->{'listtype'} eq 'genre') {
				my $genre = $item->{'itemobj'}{'genre'};
				if($first==1) {
					debugMsg("Loading genre = ".$genre->name."\n");
					$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('genre'),$genre->id)]);
				}else {
					debugMsg("Adding genre = ".$genre->name."\n");
					$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('genre'),$genre->id)]);
				}
			}elsif($item->{'listtype'} eq 'year') {
				my $year = $item->{'itemobj'}{'year'};
				if($first==1) {
					debugMsg("Loading year = ".$year."\n");
					$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('year'),$year)]);
				}else {
					debugMsg("Adding year = ".$year."\n");
					$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('year'),$year)]);
				}
			}elsif($item->{'listtype'} eq 'playlist') {
				my $playlist = $item->{'itemobj'}{'playlist'};
				if($first==1) {
					debugMsg("Loading playlist = ".$playlist->title."\n");
					$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('playlist'),$playlist->id)]);
				}else {
					debugMsg("Adding playlist = ".$playlist->title."\n");
					$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('playlist'),$playlist->id)]);
				}
			}
			if ($::VERSION ge '6.5') {
				# indicate request source
				$request->source('PLUGIN_TRACKSTAT');
			}
			$first = 0;
		}
	}
}

sub handleWebIndex {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub handleWebSelectStatistics {
	my ($client, $params) = @_;

	baseWebPage($client, $params);
	my $statistics = getStatisticPlugins();
	my @statisticItems = ();
	for my $item (keys %$statistics) {
		my %itemData = ();
		$itemData{'id'} = $statistics->{$item}->{'id'};
		if(defined($statistics->{$item}->{'namefunction'})) {
			$itemData{'name'} = eval {&{$statistics->{$item}->{'namefunction'}}()};
		}else {
			$itemData{'name'} = $statistics->{$item}->{'name'};
		}
		$itemData{'enabled'} = $statistics->{$item}->{'trackstat_statistic_enabled'};
		push @statisticItems, \%itemData;
	}
	@statisticItems = sort { $a->{'name'} cmp $b->{'name'} } @statisticItems;
	$params->{'pluginTrackStatStatisticItems'} = \@statisticItems;
	$params->{'pluginTrackStatNoOfStatisticItemsPerColumn'} = scalar(@statisticItems)/2;
	
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/selectstatistics.html', $params);
}

sub handleWebSaveSelectStatistics {
	my ($client, $params) = @_;

	my $statistics = getStatisticPlugins($client);
	my $first = 1;
	foreach my $statistic (keys %$statistics) {
		my $statisticid = "statistic_".$statistics->{$statistic}->{'id'};
		if($params->{$statisticid}) {
			Slim::Utils::Prefs::set('plugin_trackstat_statistics_'.$statistic.'_enabled',1);
			$statistics->{$statistic}->{'trackstat_statistic_enabled'} = 1;
		}else {
			Slim::Utils::Prefs::set('plugin_trackstat_statistics_'.$statistic.'_enabled',0);
			$statistics->{$statistic}->{'trackstat_statistic_enabled'} = 0;
		}
	}
	$params->{'path'} = "plugins/TrackStat/index.html";
	initStatisticPlugins();
	handleWebIndex($client, $params);
}

sub getStatisticPlugins {
	if( !defined $statisticsInitialized) {
		initStatisticPlugins();
	}
	return \%statisticPlugins;
}

sub getStatisticPluginsStrings {
	my @pluginDirs = ();
	if ($::VERSION ge '6.5') {
		@pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
    }else {
     	@pluginDirs = catdir($Bin, "Plugins");
    }
    my %pluginlist = ();
    $statisticPluginsStrings = "";
	for my $plugindir (@pluginDirs) {
		opendir(DIR, catdir($plugindir,"TrackStat","Statistics")) || next;
		for my $plugin (readdir(DIR)) {
			if ($plugin =~ s/(.+)\.pm$/$1/i) {
				my $fullname = "Plugins::TrackStat::Statistics::$plugin";
				no strict 'refs';
				eval {
					eval "use $fullname";
					if ($@) {
	                	msg("TrackStat: Failed to load statistic plugin $plugin: $@\n");
	                }
					if(UNIVERSAL::can("${fullname}","strings")) {
						#debugMsg("Calling: ".$fullname."::strings\n");
						my $str = eval { &{$fullname . "::strings"}(); };
						if ($@) {
		                	msg("TrackStat: Failed call strings on statistic plugin $plugin: $@\n");
		                }
						if(defined $str) {
							$statisticPluginsStrings = "$statisticPluginsStrings$str";
						}
					}
				};
				if ($@) {
                	msg("TrackStat: Failed to load statistic plugin $plugin: $@\n");
                }
				use strict 'refs';
			}
		}
		closedir(DIR);
	}
	$statisticsInitialized = 1;
	return $statisticPluginsStrings;
}

sub initStatisticPlugins {
	%statisticPlugins = ();
	%statisticItems = ();
	%statisticTypes = ();
	my @pluginDirs = ();
	if ($::VERSION ge '6.5') {
		@pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
    }else {
     	@pluginDirs = catdir($Bin, "Plugins");
    }
    my %pluginlist = ();
	for my $plugindir (@pluginDirs) {
		opendir(DIR, catdir($plugindir,"TrackStat","Statistics")) || next;
		for my $plugin (readdir(DIR)) {
			if ($plugin =~ s/(.+)\.pm$/$1/i) {
				my $fullname = "Plugins::TrackStat::Statistics::$plugin";
				no strict 'refs';
				eval {
					eval "use $fullname";
					if ($@) {
	                	msg("TrackStat: Failed to load statistic plugin $plugin: $@\n");
	                }
					if(UNIVERSAL::can("${fullname}","init")) {
						#debugMsg("Calling: ".$fullname."::init\n");
						eval { &{$fullname . "::init"}(); };
						if ($@) {
		                	msg("TrackStat: Failed to call init on statistic plugin $plugin: $@\n");
		                }
					}
					if(UNIVERSAL::can("${fullname}","getStatisticItems")) {
						my $pluginStatistics = eval { &{$fullname . "::getStatisticItems"}() };
						if ($@) {
		                	msg("TrackStat: Failed to call getStatisticItems on statistic plugin $plugin: $@\n");
		                }
						#debugMsg("Calling: ".$fullname."::getStatisticItems\n");
						for my $item (keys %$pluginStatistics) {
							my $enabled = Slim::Utils::Prefs::get('plugin_trackstat_statistics_'.$item.'_enabled');
							#debugMsg("Statistic plugin loaded: $item from $plugin.pm\n");
							my $subitems = $pluginStatistics->{$item};
							my %items = ();
							for my $subitem (keys %$subitems) {
								$items{$subitem} = $subitems->{$subitem};
							}
							if(!defined $enabled || $enabled==1) {
								$items{'trackstat_statistic_enabled'} = 1;
							}else {
								$items{'trackstat_statistic_enabled'} = 0;
							}
							$statisticPlugins{$item} = \%items;
							
							my $groups = $items{'statisticgroups'};
							if(Slim::Utils::Prefs::get("plugin_trackstat_deep_hierarchy") || !defined($groups)) {
								$groups = $items{'groups'};
							}
							if(defined($groups)) {
								for my $currentgroups (@$groups) {
									my $currentLevel = \%statisticItems;
									my $grouppath = '';
									my $enabled = 1;
									for my $group (@$currentgroups) {
										$grouppath .= "_".escape($group);
										my $existingItem = $currentLevel->{'group_'.$group};
										if(defined($existingItem)) {
											if($enabled) {
												$enabled = Slim::Utils::Prefs::get('plugin_trackstat_statistic_group_'.$grouppath.'_enabled');
												if(!defined($enabled)) {
													$enabled = 1;
												}
											}
											if($enabled && $items{'trackstat_statistic_enabled'}) {
												$existingItem->{'trackstat_statistic_enabled'} = 1;
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
												$enabled = Slim::Utils::Prefs::get('plugin_trackstat_statistic_group_'.$grouppath.'_enabled');
												if(!defined($enabled)) {
													$enabled = 1;
												}
											}
											if($enabled && $items{'trackstat_statistic_enabled'}) {
												#debugMsg("Enabled: plugin_dynamicplaylist_playlist_".$grouppath."_enabled=1\n");
												$currentItemGroup{'trackstat_statistic_enabled'} = 1;
											}else {
												#debugMsg("Enabled: plugin_dynamicplaylist_playlist_".$grouppath."_enabled=0\n");
												$currentItemGroup{'trackstat_statistic_enabled'} = 0;
											}

											$currentLevel->{'group_'.$group} = \%currentItemGroup;
											$currentLevel = \%level;
										}
									}
									my %currentGroupItem = (
										'item' => \%items,
										'trackstat_statistic_enabled' => $items{'trackstat_statistic_enabled'}
									);
									if(defined($items{'namefunction'})) {
										$currentGroupItem{'name'} = &{$items{'namefunction'}}();
									}else {
										$currentGroupItem{'name'} = $items{'name'};
									}
									$currentGroupItem{'value'} = $currentGroupItem{'name'};
									$currentLevel->{$item} = \%currentGroupItem;
								}
							}else {
								my %currentItem = (
									'item' => \%items,
									'trackstat_statistic_enabled' => $items{'trackstat_statistic_enabled'}
								);
								if(defined($items{'namefunction'})) {
									$currentItem{'name'} = &{$items{'namefunction'}}();
								}else {
									$currentItem{'name'} = $items{'name'};
								}
								$currentItem{'value'} = $currentItem{'name'};
								$statisticItems{$item} = \%currentItem;
							}

						}
					}
				};
				if ($@) {
                	msg("TrackStat: Failed to load statistic plugin $plugin: $@\n");
                }
				use strict 'refs';
			}
		}
		closedir(DIR);
	}
	
	for my $key (keys %statisticPlugins) {
		my $item = $statisticPlugins{$key};
		if($item->{'trackstat_statistic_enabled'}) {
			if(defined($item->{'contextfunction'})) {
				for my $type (qw{album artist genre year playlist track}) {
					my %params = ();
					$params{$type} = 1;
					my $valid = eval {&{$item->{'contextfunction'}}(\%params)};
					if($valid) {
						$statisticTypes{$type} = 1;
					}
				}
			}
		}
	}
	
	$statisticsInitialized = 1;
}



sub handleWebStatistics {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    
    my $id = $params->{path};
    $id =~ s/^.*\/(.*?)\.htm.?$/$1/; 
    
    my $statistics = getStatisticPlugins();
	my $function = $statistics->{$id}->{'webfunction'};
	debugMsg("Calling webfunction for $id\n");
	eval {
		&{$function}($params,$listLength);
		if(defined($statistics->{$id}->{'namefunction'})) {
			$params->{'songlist'} = &{$statistics->{$id}->{'namefunction'}}($params);
		}else {
			$params->{'songlist'} = $statistics->{$id}->{'name'};
		}
		$params->{'songlistid'} = $statistics->{$id}->{'id'};
		my $statistic = undef;
		my $allowControls = 0;
		if(defined($params->{'statisticparameters'}) && $params->{'statisticparameters'} =~ /\&?album=(\d+)/) {
			$statistic = Plugins::TrackStat::Storage::getGroupStatistic('album',$1);
			$allowControls = 1;
		}elsif(defined($params->{'statisticparameters'}) && $params->{'statisticparameters'} =~ /\&?artist=(\d+)/) {
			$statistic = Plugins::TrackStat::Storage::getGroupStatistic('artist',$1);
		}elsif(defined($params->{'statisticparameters'}) && $params->{'statisticparameters'} =~ /\&?playlist=(\d+)/) {
			$statistic = Plugins::TrackStat::Storage::getGroupStatistic('playlist',$1);
		}elsif(defined($params->{'statisticparameters'}) && $params->{'statisticparameters'} =~ /\&?year=(\d+)/) {
			$statistic = Plugins::TrackStat::Storage::getGroupStatistic('year',$1);
		}elsif(defined($params->{'statisticparameters'}) && $params->{'statisticparameters'} =~ /\&?genre=(\d+)/) {
			$statistic = Plugins::TrackStat::Storage::getGroupStatistic('genre',$1);
		}
		if(defined $statistic) {
			my $rating = $statistic->{'rating'};
			if(!defined($rating)) {
				$rating = 0;
			}
			if(Slim::Utils::Prefs::get("plugin_trackstat_force_grouprating") && $allowControls) {
				$params->{'pluginTrackStatShowGroupRatingWarning'} = "PLUGIN_TRACKSTAT_GROUP_RATING_QUESTION_FORCE";
				$params->{'pluginTrackStatShowGroupRatingControls'} = 1;
			}elsif(!$statistic->{'lowestrating'} && $allowControls) {
				$params->{'pluginTrackStatShowGroupRatingWarning'} = "PLUGIN_TRACKSTAT_GROUP_RATING_QUESTION";
				$params->{'pluginTrackStatShowGroupRatingControls'} = 1;
			}else {
				if($rating) {
					$params->{'pluginTrackStatShowGroupRatingView'} = 1;
				}
			}

		  	$params->{'pluginTrackStatGroupRating'} = ($rating && $rating>0?($rating+10)/20:0);
			$params->{'pluginTrackStatGroupRatingNumber'} = sprintf("%.2f", $rating/20);

		}
		setDynamicPlaylistParams($client,$params);
	};
	
	handlePlayAdd($client,$params);
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub setDynamicPlaylistParams {
	my ($client, $params) = @_;

	my $dynamicPlaylist;
	if ($::VERSION ge '6.5') {
		$dynamicPlaylist = Slim::Utils::PluginManager::enabledPlugin("DynamicPlayList",$client);
	}else {
		$dynamicPlaylist = grep(/DynamicPlayList/,Slim::Buttons::Plugins::enabledPlugins($client));
    }
	if($dynamicPlaylist && Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist")) {
		if(!defined($params->{'artist'}) && !defined($params->{'album'}) && !defined($params->{'genre'}) && !defined($params->{'year'}) && !defined($params->{'playlist'})) {
			$params->{'dynamicplaylist'} = "trackstat_".$params->{'songlistid'};
		}
	}
}
sub getPlayCount {
	my $track = shift;
	if ($::VERSION ge '6.5') {
		return $track->playcount;
	}else {
		return $track->{playCount};
	}
}

sub getLastPlayed {
	my $track = shift;
	if ($::VERSION ge '6.5') {
		return $track->lastplayed;
	}else {
		return $track->{lastPlayed};
	}
}

sub initRatingChar {
	# set rating character
	if (defined(Slim::Utils::Prefs::get("plugin_trackstat_ratingchar"))) {
		my $str = Slim::Utils::Prefs::get("plugin_trackstat_ratingchar");
		if($str ne '') {
			$RATING_CHARACTER = $str;
			$NO_RATING_CHARACTER = ' ' x length($RATING_CHARACTER);
		}
	}else {
		Slim::Utils::Prefs::set("plugin_trackstat_ratingchar",$RATING_CHARACTER);
	}
}

sub initPlugin
{
	my $class = shift;
    debugMsg("initialising\n");
	#if we haven't already started, do so
	if ( !$TRACKSTAT_HOOK ) {
		my %choiceFunctions = %{Slim::Buttons::Input::Choice::getFunctions()};
		$choiceFunctions{'saveRating'} = \&saveRatingsFromChoice;
		Slim::Buttons::Common::addMode('PLUGIN.TrackStat.Choice',\%choiceFunctions,\&Slim::Buttons::Input::Choice::setMode);
		for my $buttonPressMode (qw{repeat hold hold_release single double}) {
			$choiceMapping{'play.' . $buttonPressMode} = 'dead';
			$choiceMapping{'add.' . $buttonPressMode} = 'dead';
			$choiceMapping{'search.' . $buttonPressMode} = 'passback';
			$choiceMapping{'stop.' . $buttonPressMode} = 'passback';
			$choiceMapping{'pause.' . $buttonPressMode} = 'passback';
		}
		Slim::Hardware::IR::addModeDefaultMapping('PLUGIN.TrackStat.Choice',\%choiceMapping);

		# Alter mapping for functions & buttons in Now Playing mode.
		Slim::Hardware::IR::addModeDefaultMapping('playlist',\%mapping);
		my $functref = Slim::Buttons::Playlist::getFunctions();
		$functref->{'saveRating'} = \&saveRatingsForCurrentlyPlaying;

		# this will set messages off by default
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_showmessages"))) { 
			debugMsg("First run - setting showmessages OFF\n");
			Slim::Utils::Prefs::set("plugin_trackstat_showmessages", 0 ); 
		}

		# this will enable DynamicPlaylist integration by default
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist"))) { 
			debugMsg("First run - setting dynamicplaylist ON\n");
			Slim::Utils::Prefs::set("plugin_trackstat_dynamicplaylist", 1 ); 
		}
		# set default web list length to same as items per page
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_web_list_length"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_web_list_length",Slim::Utils::Prefs::get("itemsPerPage"));
		}
		# set default player list length to same as web list length or 20 if not exist
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_player_list_length"))) {
			if(defined(Slim::Utils::Prefs::get("plugin_trackstat_web_list_length"))) {
				Slim::Utils::Prefs::set("plugin_trackstat_player_list_length",Slim::Utils::Prefs::get("plugin_trackstat_web_list_length"));
			}else {
				Slim::Utils::Prefs::set("plugin_trackstat_player_list_length",20);
			}
		}

		# set default playlist length to same as items per page
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_playlist_length"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_playlist_length",Slim::Utils::Prefs::get("itemsPerPage"));
		}
		# set default playlist per artist/album length to 10
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_playlist_per_artist_length"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_playlist_per_artist_length",10);
		}
		# disable music magic integration by default
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_enabled"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_musicmagic_enabled",0);
		}

		# disable iTunes integration by default
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_itunes_enabled"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_itunes_enabled",0);
		}

		# set default music magic port
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_port"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_musicmagic_port",Slim::Utils::Prefs::get('MMSport'));
		}

		# set default music magic host
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_host"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_musicmagic_host",Slim::Utils::Prefs::get('MMSHost'));
		}

		# enable history by default
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_history_enabled"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_history_enabled",1);
		}

		# Set default recent number of days to 30
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_recent_number_of_days"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_recent_number_of_days",30);
		}

		# Set default recent added number of days to 30
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_recentadded_number_of_days"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_recentadded_number_of_days",30);
		}

		# enable refresh at startup by default
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_refresh_startup"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_refresh_startup",1);
		}

		# enable refresh after rescan by default
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_refresh_rescan"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_refresh_rescan",1);
		}

		# set default song threshold to 1800
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_song_threshold_length"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_song_threshold_length",1800);
		}

		# set default min song length to 5
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_min_song_length"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_min_song_length",5);
		}

		# set default min song percent
		if (!defined(Slim::Utils::Prefs::get("plugin_trackstat_min_song_percent"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_min_song_percent",50);
		}
		
		#setup default iTunes history file
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_itunes_export_dir"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_itunes_export_dir",Slim::Utils::Prefs::get('playlistdir'));
		}

		# enable web auto refresh by default
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_web_refresh"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_web_refresh",1);
		}
		# enable mixer links by default
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_web_show_mixerlinks"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_web_show_mixerlinks",1);
		}
		
		# enable mixer functions on web by default
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_web_enable_mixerfunction"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_web_enable_mixerfunction",1);
		}

		# enable mixer functions on player by default
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_enable_mixerfunction"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_enable_mixerfunction",1);
		}

		# Do not force group ratings by default
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_force_grouprating"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_force_grouprating",0);
		}
		
		# Use structured menu on player by default
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_player_flatlist"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_player_flatlist",0);
		}
		# Use structured menu on web by default
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_web_flatlist"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_web_flatlist",0);
		}

		# Use deeper structured menu
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_deep_hierarchy"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_deep_hierarchy",0);
		}

		# Set scheuled backup time
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_backup_time"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_backup_time","03:00");
		}

		# Set scheduled backup dir
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_backup_dir"))) {
			if(defined(Slim::Utils::Prefs::get("plugin_trackstat_backup_file"))) {
				my $dir = Slim::Utils::Prefs::get("plugin_trackstat_backup_file"); 
				while ($dir =~ m/[^\/\\]$/) {
					$dir =~ s/[^\/\\]$//sg;
				}
				if($dir =~ m/[\/\\]$/) {
					$dir =~ s/[\/\\]$//sg;
				}
				Slim::Utils::Prefs::set("plugin_trackstat_backup_dir",$dir);
			}elsif(defined(Slim::Utils::Prefs::get("playlistdir"))) {
				Slim::Utils::Prefs::set("plugin_trackstat_backup_dir",Slim::Utils::Prefs::get("playlistdir"));
			}else {
				Slim::Utils::Prefs::set("plugin_trackstat_backup_dir",'');
			}
				
		}

		# Turn of first scheduled backup to make it possible to configure changes
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_backup_lastday"))) {
			my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
			Slim::Utils::Prefs::set("plugin_trackstat_backup_lastday",$mday);
		}

		# Remove two track artists by default
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_min_artist_tracks"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_min_artist_tracks",3);
		}

		# Remove single track albums by default
		if(!defined(Slim::Utils::Prefs::get("plugin_trackstat_min_album_tracks"))) {
			Slim::Utils::Prefs::set("plugin_trackstat_min_album_tracks",2);
		}

		initRatingChar();
		
		installHook();
		
		Plugins::TrackStat::Storage::init();

		initStatisticPlugins();
		
		no strict 'refs';
		my @enabledplugins;
		if ($::VERSION ge '6.5') {
			@enabledplugins = Slim::Utils::PluginManager::enabledPlugins();
		}else {
			@enabledplugins = Slim::Buttons::Plugins::enabledPlugins();
		}
		for my $plugin (@enabledplugins) {
			if(UNIVERSAL::can("Plugins::$plugin","setTrackStatRating")) {
				debugMsg("Added rating support for $plugin\n");
				$ratingPlugins{$plugin} = "Plugins::${plugin}::setTrackStatRating";
			}
			if(UNIVERSAL::can("Plugins::$plugin","setTrackStatStatistic")) {
				debugMsg("Added play count support for $plugin\n");
				$playCountPlugins{$plugin} = "Plugins::${plugin}::setTrackStatStatistic";
			}
		}
		use strict 'refs';
		
		my %mixerMap = ();
		if(Slim::Utils::Prefs::get("plugin_trackstat_web_enable_mixerfunction")) {
			$mixerMap{'mixerlink'} = \&mixerlink;
		}
		if(Slim::Utils::Prefs::get("plugin_trackstat_enable_mixerfunction")) {
			$mixerMap{'mixer'} = \&mixerFunction;
		}
		if(Slim::Utils::Prefs::get("plugin_trackstat_web_enable_mixerfunction") ||
			Slim::Utils::Prefs::get("plugin_trackstat_enable_mixerfunction")) {
			if ($::VERSION ge '6.5') {
				Slim::Music::Import->addImporter($class, \%mixerMap);
				Slim::Music::Import->useImporter('Plugins::TrackStat::Plugin', 1);
			}else {
				Slim::Music::Import::addImporter('TRACKSTAT', \%mixerMap);
				Slim::Music::Import::useImporter('TRACKSTAT', 1);
			}
		}
		
		checkAndPerformScheduledBackup();
	}
	addTitleFormat('TRACKNUM. ARTIST - TITLE (TRACKSTATRATINGDYNAMIC)');
	addTitleFormat('TRACKNUM. TITLE (TRACKSTATRATINGDYNAMIC)');
	addTitleFormat('PLAYING (X_OF_Y) (TRACKSTATRATINGSTATIC)');
	addTitleFormat('PLAYING (X_OF_Y) TRACKSTATRATINGSTATIC');
	addTitleFormat('TRACKSTATRATINGNUMBER');


	if ($::VERSION ge '6.5') {
		
		Slim::Music::TitleFormatter::addFormat('TRACKSTATRATINGDYNAMIC',\&getRatingDynamicCustomItem);
		Slim::Music::TitleFormatter::addFormat('TRACKSTATRATINGSTATIC',\&getRatingStaticCustomItem);
		Slim::Music::TitleFormatter::addFormat('TRACKSTATRATINGNUMBER',\&getRatingNumberCustomItem);
	}else {
		Slim::Music::Info::addFormat('TRACKSTATRATINGDYNAMIC',\&getRatingDynamicCustomItem);
		Slim::Music::Info::addFormat('TRACKSTATRATINGSTATIC',\&getRatingStaticCustomItem);
		Slim::Music::Info::addFormat('TRACKSTATRATINGNUMBER',\&getRatingNumberCustomItem);
	}
}

sub checkAndPerformScheduledBackup {
	my $timestr = Slim::Utils::Prefs::get("plugin_trackstat_backup_time");
	my $day = Slim::Utils::Prefs::get("plugin_trackstat_backup_lastday");
	my $dir = Slim::Utils::Prefs::get("plugin_trackstat_backup_dir");
	if(!defined($day)) {
		$day = '';
	}
	
	debugMsg("Checking if its time to do a scheduled backup\n");
	if(defined($timestr) && $timestr ne '' && defined($dir) and $dir ne '') {
		my $time = 0;
		$timestr =~ s{
			^(0?[0-9]|1[0-9]|2[0-4]):([0-5][0-9])\s*(P|PM|A|AM)?$
		}{
			if (defined $3) {
				$time = ($1 == 12?0:$1 * 60 * 60) + ($2 * 60) + ($3 =~ /P/?12 * 60 * 60:0);
			} else {
				$time = ($1 * 60 * 60) + ($2 * 60);
			}
		}iegsx;
		my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
	
		my $currenttime = $hour * 60 * 60 + $min * 60;
		
		if(($day ne $mday) && $currenttime>$time) {
			debugMsg("Making backup to: $dir/trackstat_scheduled_backup_".(1900+$year).(($mon+1)<10?'0'.($mon+1):($mon+1)).($mday<10?'0'.$mday:$mday).".xml\n");
			eval {
				backupToFile("$dir/trackstat_scheduled_backup_".(1900+$year).(($mon+1)<10?'0'.($mon+1):($mon+1)).($mday<10?'0'.$mday:$mday).".xml");
			};
			if ($@) {
		    		msg("TrackStat: Scheduled backup failed: $@\n");
		    	}
		    	Slim::Utils::Prefs::set("plugin_trackstat_backup_lastday",$mday);
		}else {
			my $timesleft = $time-$currenttime;
			if($day eq $mday) {
				$timesleft = $timesleft + 60*60*24;
			}
			debugMsg("Its ".($timesleft)." seconds left until next scheduled backup\n");
		}
		
	}else {
		debugMsg("Scheduled backups disabled\n");
	}
	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + 900, \&checkAndPerformScheduledBackup);
}
sub mixable {
        my $class = shift;
        my $item  = shift;
	my $blessed = blessed($item);

	if(!$blessed) {
		return undef;
	}elsif($blessed eq 'Slim::Schema::Track') {
		return 1 if($statisticTypes{'track'});
	}elsif($blessed eq 'Slim::Schema::Year') {
		return 1 if($statisticTypes{'year'} && $item->id);
	}elsif($blessed eq 'Slim::Schema::Album') {
		return 1 if($statisticTypes{'album'});
	}elsif($blessed eq 'Slim::Schema::Age') {
		return 1 if($statisticTypes{'album'});
	}elsif($blessed eq 'Slim::Schema::Contributor') {
		return 1 if($statisticTypes{'artist'});
	}elsif($blessed eq 'Slim::Schema::Genre') {
		return 1 if($statisticTypes{'genre'});
	}elsif($blessed eq 'Slim::Schema::Playlist') {
		return 1 if($statisticTypes{'playlist'});
	}
        return undef;
}

sub mixerFunction {
	my ($client, $noSettings) = @_;
	# look for parentParams (needed when multiple mixers have been used)
	my $paramref = defined $client->param('parentParams') ? $client->param('parentParams') : $client->modeParameterStack(-1);
	if(defined($paramref)) {
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
		if($statisticTypes{$mixerType}) { 
			if($mixerType eq 'album') {
				my %params = (
					'album' => $currentItem->id,
					'statistictype' => 'album',
					'flatlist' => 1
				);
				debugMsg("Calling album statistics with ".$params{'album'}."\n");
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.TrackStat::Plugin',\%params);
				$client->update();
			}elsif($mixerType eq 'year') {
				my $year = $currentItem;
				if ($::VERSION ge '6.5') {
					$year = $currentItem->id;
				}
				my %params = (
					'year' => $year,
					'statistictype' => 'year',
					'flatlist' => 1
				);
				debugMsg("Calling album statistics with ".$params{'year'}."\n");
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.TrackStat::Plugin',\%params);
				$client->update();
			}elsif($mixerType eq 'artist') {
				my %params = (
					'artist' => $currentItem->id,
					'statistictype' => 'artist',
					'flatlist' => 1
				);
				debugMsg("Calling artist statistics with ".$params{'artist'}."\n");
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.TrackStat::Plugin',\%params);
				$client->update();
			}elsif($mixerType eq 'genre') {
				my %params = (
					'genre' => $currentItem->id,
					'statistictype' => 'genre',
					'flatlist' => 1
				);
				debugMsg("Calling genre statistics with ".$params{'genre'}."\n");
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.TrackStat::Plugin',\%params);
				$client->update();
			}elsif($mixerType eq 'playlist') {
				my %params = (
					'playlist' => $currentItem->id,
					'statistictype' => 'playlist',
					'flatlist' => 1
				);
				debugMsg("Calling playlist statistics with ".$params{'playlist'}."\n");
				Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.TrackStat::Plugin',\%params);
				$client->update();
			}else {
				debugMsg("Unknown statistictype = ".$mixerType."\n");
			}
		}else {
			debugMsg("No statistics found for ".$mixerType."\n");
		}
	}else {
		debugMsg("No parent parameter found\n");
	}

}
sub title {
	return 'TRACKSTAT';
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
	if($form->{'noTrackStatButton'}) {
		if ($::VERSION lt '6.5') {
        		Slim::Web::Pages::addLinks("mixer", {'TRACKSTAT' => undef});
        	}
	}elsif(defined($levelName) && ($levelName eq 'artist' || $levelName eq 'contributor' || $levelName eq 'album' || $levelName eq 'genre' || $levelName eq 'playlist')) {
		if ($::VERSION ge '6.5') {
	        	$form->{'mixerlinks'}{'TRACKSTAT'} = "plugins/TrackStat/mixerlink65.html";
	        }else {
        		Slim::Web::Pages::addLinks("mixer", {'TRACKSTAT' => "plugins/TrackStat/mixerlink.html"}, 1);
	        }
        }elsif(defined($levelName) && $levelName eq 'year') {
        	$form->{'yearid'} = $item->year;
        	if(defined($form->{'yearid'})) {
				if ($::VERSION ge '6.5') {
        			$form->{'mixerlinks'}{'TRACKSTAT'} = "plugins/TrackStat/mixerlink65.html";
        		}else {
        			Slim::Web::Pages::addLinks("mixer", {'TRACKSTAT' => "plugins/TrackStat/mixerlink.html"}, 1);
        		}
        	}
        }else {
        	my $attributes = $form->{'attributes'};
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
	    			$album = $item;
	    		}elsif(ref($item) eq 'Slim::Schema::Album' || ref($item) eq 'Slim::DataStores::DBI::Album') {
	    			$album = $item;
			}else {
	    			$album = $item->album;
	    		}
	    		if(defined($album)) {
    				$form->{'albumid'} = $album->id;
	    		}
	    	}
	    	$form->{'currenttrackstatitem'} = $item->id;
	    	
        	if(defined($form->{'albumid'}) || defined($form->{'playlist'})) {
			if ($::VERSION ge '6.5') {
        			$form->{'mixerlinks'}{'TRACKSTAT'} = "plugins/TrackStat/mixerlink65.html";
        		}else {
        			Slim::Web::Pages::addLinks("mixer", {'TRACKSTAT' => "plugins/TrackStat/mixerlink.html"}, 1);
        		}
        	}
        }
        return $form;
}
	
sub addTitleFormat
{
	my $titleformat = shift;
	foreach my $format ( Slim::Utils::Prefs::getArray('titleFormat') ) {
		if($titleformat eq $format) {
			return;
		}
	}
	my $arrayMax = Slim::Utils::Prefs::getArrayMax('titleFormat');
	debugMsg("Adding at $arrayMax: $titleformat");
	Slim::Utils::Prefs::set('titleFormat',$titleformat,$arrayMax+1);
}

sub shutdownPlugin {
        debugMsg("disabling\n");
        if ($TRACKSTAT_HOOK) {
                uninstallHook();
		if(Slim::Utils::Prefs::get("plugin_trackstat_web_enable_mixerfunction") ||
			Slim::Utils::Prefs::get("plugin_trackstat_enable_mixerfunction")) {
			if ($::VERSION ge '6.5') {
				Slim::Music::Import->useImporter('Plugins::TrackStat::Plugin',0);
			}else {
				Slim::Music::Import::useImporter('TRACKSTAT', 0);
			}
		}
        }
}


##################################################
### per-client Data                            ###
##################################################

struct TrackStatus => {

	# Artist's name for current song
	client => '$',

	# Artist's name for current song
	currentSongArtist => '$',

	# Track title for current song
	currentSongTrack => '$',

	# Album title for current song.
	# (If not known, blank.)
	currentSongAlbum => '$',

	# Stopwatch to time the playing of the current track
	currentSongStopwatch => 'Time::Stopwatch',

	# Filename of the current track being played
	currentTrackOriginalFilename => '$',

	# Total length of the track being played
	currentTrackLength => '$',

	# Are we currently paused during a song's playback?
	isPaused => '$',

	# Are we currently timing a song's playback?
	isTiming => '$',

	# have we looked up the track in the storage yet
	trackAlreadyLoaded => '$',

	# Rating for current song
	currentSongRating => '$',

	# last played time
	lastPlayed => '$',

	# play count
	playCount => '$',

	# menu list item
	listitem => '$',

};

# Set the appropriate default values for this playerStatus struct
sub setPlayerStatusDefaults($$)
{
	# Parameter - client
	my $client = shift;

	# Parameter - Player status structure.
	# Uses pass-by-reference
	my $playerStatusToSetRef = shift;

	# Client reference
	$playerStatusToSetRef->client($client);
	# Artist's name for current song
	$playerStatusToSetRef->currentSongArtist("");

	# Track title for current song
	$playerStatusToSetRef->currentSongTrack("");

	# Album title for current song.
	# (If not known, blank.)
	$playerStatusToSetRef->currentSongAlbum("");

	# Rating for current song
	$playerStatusToSetRef->currentSongRating("");

	# Filename of the current track being played
	$playerStatusToSetRef->currentTrackOriginalFilename("");

	# Total length of the track being played
	$playerStatusToSetRef->currentTrackLength(0);

	# Are we currently paused during a song's playback?
	$playerStatusToSetRef->isPaused('false');

	# Are we currently timing a song's playback?
	$playerStatusToSetRef->isTiming('false');

	# Stopwatch to time the playing of the current track
	$playerStatusToSetRef->currentSongStopwatch(Time::Stopwatch->new());

	$playerStatusToSetRef->trackAlreadyLoaded('false');
	$playerStatusToSetRef->listitem(0);

}

# Get the player state for the given client.
# Will create one for new clients.
sub getPlayerStatusForClient($)
{
	# Parameter - Client structure
	my $client = shift;

	# Get the friendly name for this client
	my $clientName = Slim::Player::Client::name($client);
	# Get the ID (IP) for this client
	my $clientID = Slim::Player::Client::id($client);

	#debugMsg("Asking about client $clientName ($clientID)\n");

	# If we haven't seen this client before, create a new per-client 
	# playState structure.
	if (!defined($playerStatusHash{$client}))
	{
		debugMsg("Creating new PlayerStatus for $clientName ($clientID)\n");

		# Create new playState structure
		$playerStatusHash{$client} = TrackStatus->new();

		# Set appropriate defaults
		setPlayerStatusDefaults($client, $playerStatusHash{$client});
	}

	# If it didn't exist, it does now - 
	# return the playerStatus structure for the client.
	return $playerStatusHash{$client};
}

################################################
### main routines                            ###
################################################

# A wrapper to allow us to uniformly turn on & off debug messages
sub debugMsg
{
	my $message = join '','TrackStat: ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_trackstat_showmessages"));
}


# Hook the plugin to the play events.
# Do this as soon as possible during startup.
sub installHook()
{  
	debugMsg("Hook activated.\n");
	if ($::VERSION ge '6.5') {
		Slim::Control::Request::subscribe(\&Plugins::TrackStat::Plugin::commandCallback65,[['mode', 'play', 'stop', 'pause', 'playlist','rescan']]);
		Slim::Control::Request::addDispatch(['trackstat','getrating', '_trackid'], [0, 1, 0, \&getCLIRating]);
		Slim::Control::Request::addDispatch(['trackstat','setrating', '_trackid', '_rating'], [1, 0, 0, \&setCLIRating]);
	} else {
		Slim::Control::Command::setExecuteCallback(\&commandCallback62);
	}
	$TRACKSTAT_HOOK=1;
}

# Unhook the plugin's play event callback function. 
# Do this as the plugin shuts down, if possible.
sub uninstallHook()
{
	debugMsg("Hook deactivated.\n");
	if ($::VERSION ge '6.5') {
		Slim::Control::Request::unsubscribe(\&Plugins::TrackStat::Plugin::commandCallback65);
	} else {
		Slim::Control::Command::clearExecuteCallback(\&commandCallback62);
	}
	$TRACKSTAT_HOOK=0;
}

# These xxxCommand() routines handle commands coming to us
# through the command callback we have hooked into.
sub openCommand($$)
{
	######################################
	### Open command
	######################################

	# This is the chief way we detect a new song being played, NOT the play command.
	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	# Stop old song, if needed
	# do this before updating the filename as we need to use it in the stop function
	if ($playStatus->isTiming() eq "true")
	{
		stopTimingSong($playStatus);
	}
	# Parameter - filename of track being played
	$playStatus->currentTrackOriginalFilename(shift);

	# Start timing new song
	startTimingNewSong($playStatus);#, $artistName,$trackTitle,$albumName);
}

sub playCommand($)
{
	######################################
	### Play command
	######################################

	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	if ( ($playStatus->isTiming() eq "true") &&($playStatus->isPaused() eq "true") )
	{
		debugMsg("Resuming with play from pause\n");
		resumeTimingSong($playStatus);
	} elsif ( ($playStatus->isTiming() eq "true") &&($playStatus->isPaused() eq "false") )
	{
		debugMsg("Ignoring play command, assumed redundant...\n");		      
	} else {
		# this seems to happen when you switch on and press play    
		# Start timing new song
		startTimingNewSong($playStatus);
	}
}

sub pauseCommand($$)
{
	######################################
	### Pause command
	######################################

	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	# Parameter - Optional second parameter in command
	# (This is for the case <pause 0 | 1> ). 
	# If user said "pause 0" or "pause 1", this will be 0 or 1. Otherwise, undef.
	my $secondParm = shift;

	# Just a plain "pause"
	if (!defined($secondParm))
	{
		# What we do depends on if we are already paused or not
		if ($playStatus->isPaused() eq "false") {
			debugMsg("Pausing (vanilla pause)\n");
			pauseTimingSong($playStatus);   
		} elsif ($playStatus->isPaused() eq "true") {
			debugMsg("Unpausing (vanilla unpause)\n");
			resumeTimingSong($playStatus);      
		}
	}

	# "pause 1" means "pause true", so pause and stop timing, if not already paused.
	elsif ( ($secondParm eq 1) && ($playStatus->isPaused() eq "false") ) {
		debugMsg("Pausing (1 case)\n");
		pauseTimingSong($playStatus);      
	}

	# "pause 0" means "pause false", so unpause and resume timing, if not already timing.
	elsif ( ($secondParm eq 0) && ($playStatus->isPaused() eq "true") ) {
		debugMsg("Pausing (0 case)\n");
		resumeTimingSong($playStatus);      
	} else {      
		debugMsg("Pause command ignored, assumed redundant.\n");
	}
}

sub stopCommand($)
{
	######################################
	### Stop command
	######################################

	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	if ($playStatus->isTiming() eq "true")
	{
		stopTimingSong($playStatus);      
	}
}


# This gets called during playback events.
# We look for events we are interested in, and start and stop our various
# timers accordingly.
sub commandCallback62($) 
{
	# These are the two passed parameters
	my $client = shift;
	my $paramsRef = shift;

	return unless $client;

	# Get the PlayerStatus
	my $playStatus = getPlayerStatusForClient($client);

	### START DEBUG
	#debugMsg("====New commands:\n");
	#foreach my $param (@$paramsRef)
	#{
	#   debugMsg("  command: $param\n");
	#}
	#showCurrentVariables($playStatus);
	### END DEBUG

	my $slimCommand = @$paramsRef[0];
	my $paramOne = @$paramsRef[1];

	return unless $slimCommand;

	######################################
	### Open command
	######################################

	# This is the chief way we detect a new song being played, NOT play.

	if ($slimCommand eq "open") 
	{
		my $trackOriginalFilename = $paramOne;
		openCommand($playStatus, $trackOriginalFilename);
	}

	######################################
	### Play command
	######################################

	if( ($slimCommand eq "play") || (($slimCommand eq "mode") && ($paramOne eq "play")) )
	{
		playCommand($playStatus);
	}

	######################################
	### Pause command
	######################################

	if ($slimCommand eq "pause")
	{
		# This second parameter may not exist,
		# and so this may be undef. Routine expects this possibility,
		# so all should be well.
		pauseCommand($playStatus, $paramOne);
	}

	if (($slimCommand eq "mode") && ($paramOne eq "pause"))
	{  
		# "mode pause" will always put us into pause mode, so fake a "pause 1".
		pauseCommand($playStatus, 1);
	}

	######################################
	### Sleep command
	######################################

	if ($slimCommand eq "sleep")
	{
		# Sleep has no effect on streamed players; is this correct for slimp3s?
		# I can't test it.
		#debugMsg("===> Sleep activated! Be sure this works!\n");
		#pauseCommand($playStatus, undef());
	}

	######################################
	### Stop command
	######################################

	if ( ($slimCommand eq "stop") ||	(($slimCommand eq "mode") && ($paramOne eq "stop")) )
	{
		stopCommand($playStatus);
	}

	######################################
	### Stop command
	######################################

	if ( ($slimCommand eq "playlist") && (($paramOne eq "sync") || ($paramOne eq "clear")) )
	{
		# If this player syncs with another, we treat it as a stop,
		# since whatever it is presently playing (if anything) will end.
		stopCommand($playStatus);
	}

	######################################
	## Power command
	######################################
	# softsqueeze doesn't seem to send a 2nd param on power on/off
	# might as well stop timing regardless of type
	if ( ($slimCommand eq "power") || (($slimCommand eq "mode") && ($paramOne eq "off")) )
	{
		stopCommand($playStatus);
	}
	
	######################################
	## CLI commands
	######################################
	if ( ($slimCommand eq "trackstat") ) 
	{
		if($paramOne eq "getrating") {
			getCLIRating62($client,\@$paramsRef);
		}elsif($paramOne eq "setrating") {
			setCLIRating62($client,\@$paramsRef);
		}
	}
}


# This gets called during playback events.
# We look for events we are interested in, and start and stop our various
# timers accordingly.
sub commandCallback65($) 
{
	debugMsg("Entering commandCallback65\n");
	# These are the two passed parameters
	my $request=shift;
	my $client = $request->client();

	######################################
	## Rescan finished
	######################################
	if ( $request->isCommand([['rescan'],['done']]) )
	{
		if(Slim::Utils::Prefs::get("plugin_trackstat_refresh_rescan")) {
			Plugins::TrackStat::Storage::refreshTracks();
		}
	}

	if(!defined $client) {
		debugMsg("Exiting commandCallback65\n");
		return;
	}

	# Get the PlayerStatus
	my $playStatus = getPlayerStatusForClient($client);

	######################################
	### Open command
	######################################

	# This is the chief way we detect a new song being played, NOT play.
	# should be using playlist,newsong now...
	if ($request->isCommand([['playlist'],['open']]) )
	{
		openCommand($playStatus,$request->getParam('_path'));
	}

	######################################
	### Play command
	######################################

	if( ($request->isCommand([['playlist'],['play']])) or ($request->isCommand([['mode','play']])) )
	{
		playCommand($playStatus);
	}

	######################################
	### Pause command
	######################################

	if ($request->isCommand([['pause']]))
	{
		pauseCommand($playStatus,$request->getParam('_newValue'));
	}

	if ($request->isCommand([['mode'],['pause']]))
	{  
		# "mode pause" will always put us into pause mode, so fake a "pause 1".
		pauseCommand($playStatus, 1);
	}

	######################################
	### Stop command
	######################################

	if ( ($request->isCommand([["stop"]])) or ($request->isCommand([['mode'],['stop']])) )
	{
		stopCommand($playStatus);
	}

	######################################
	### Stop command
	######################################

	if ( $request->isCommand([['playlist'],['sync']]) or $request->isCommand([['playlist'],['clear']]) )
	{
		# If this player syncs with another, we treat it as a stop,
		# since whatever it is presently playing (if anything) will end.
		stopCommand($playStatus);
	}

	######################################
	## Power command
	######################################
	if ( $request->isCommand([['power']]))
	{
		stopCommand($playStatus);
	}
	debugMsg("Exiting commandCallback65\n");
}

# A new song has begun playing. Reset the current song
# timer and set new Artist and Track.
sub startTimingNewSong($$$$)
{
	# Parameter - TrackStatus for current client
	my $playStatus = shift;
	return unless $playStatus->currentTrackOriginalFilename;
	debugMsg("Starting a new song\n");
	my $ds        = Plugins::TrackStat::Storage::getCurrentDS();
	my $track     = Plugins::TrackStat::Storage::objectForUrl($playStatus->currentTrackOriginalFilename);

	if (Slim::Music::Info::isFile($playStatus->currentTrackOriginalFilename)) {
		# Get new song data
		$playStatus->currentTrackLength($track->durationSeconds);

		my $artistName = $track->artist();
		#put this in because I'm getting crashes on missing artists
		$artistName = $artistName->name() if (defined $artistName);
		$artistName = "" if (!defined $artistName or $artistName eq string('NO_ARTIST'));

		my $albumName  = $track->album->title();
		$albumName = "" if (!defined $albumName or $albumName eq string('NO_ALBUM'));

		my $trackTitle = $track->title;
		$trackTitle = "" if $trackTitle eq string('NO_TITLE');

		# Set the Name & artist & album
		$playStatus->currentSongArtist($artistName);
		$playStatus->currentSongTrack($trackTitle);
		$playStatus->currentSongAlbum($albumName);
		

		if ($playStatus->isTiming() eq "true")
		{
			debugMsg("Programmer error in startTimingNewSong() - already timing!\n");	 
		}

		# Clear the stopwatch and start it again
		($playStatus->currentSongStopwatch())->clear();
		($playStatus->currentSongStopwatch())->start();

		# Not paused - we are playing a song
		$playStatus->isPaused("false");

		# We are now timing a song
		$playStatus->isTiming("true");

		$playStatus->trackAlreadyLoaded("false");

		debugMsg("Starting to time ",$playStatus->currentTrackOriginalFilename,"\n");
	} else {
		debugMsg("Not timing ",$playStatus->currentTrackOriginalFilename," - not a file\n");
	}
	#showCurrentVariables($playStatus);
}

# Pause the current song timer
sub pauseTimingSong($)
{
	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	if ($playStatus->isPaused() eq "true")
	{
		debugMsg("Programmer error or other problem in pauseTimingSong! Confused about pause status.\n");      
	}

	# Stop the stopwatch 
	$playStatus->currentSongStopwatch()->stop();

	# Go into pause mode
	$playStatus->isPaused("true");

	debugMsg("Pausing ",$playStatus->currentTrackOriginalFilename,"\n");
	debugMsg("Elapsed seconds: ",$playStatus->currentSongStopwatch()->getElapsedTime(),"\n");
	#showCurrentVariables($playStatus);
}

# Resume the current song timer - playing again
sub resumeTimingSong($)
{
	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	if ($playStatus->isPaused() eq "false")
	{
		debugMsg("Programmer error or other problem in resumeTimingSong! Confused about pause status.\n");      
	}

	# Re-start the stopwatch 
	$playStatus->currentSongStopwatch()->start();

	# Exit pause mode
	$playStatus->isPaused("false");

	debugMsg("Resuming ",$playStatus->currentTrackOriginalFilename,"\n");
	#showCurrentVariables($playStatus);
}

# Stop timing the current song
# (Either stop was hit or we are about to play another one)
sub stopTimingSong($)
{
	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	if ($playStatus->isTiming() eq "false")
	{
		debugMsg("Programmer error - not already timing!\n");   
	}

	if (Slim::Music::Info::isFile($playStatus->currentTrackOriginalFilename)) {

		my $totalElapsedTimeDuringPlay = $playStatus->currentSongStopwatch()->getElapsedTime();
		debugMsg("Stopping timing ",$playStatus->currentTrackOriginalFilename,"\n");
		debugMsg("Total elapsed time in seconds: $totalElapsedTimeDuringPlay \n");
		# We wan't to stop timing here since there is a risk that we will get a recursion loop else
		$playStatus->isTiming("false");

		# If the track was played long enough to count as a listen..
		if (trackWasPlayedEnoughToCountAsAListen($playStatus, $totalElapsedTimeDuringPlay) )
		{
			#debugMsg("Track was played long enough to count as listen\n");
			markedAsPlayed($playStatus->client,$playStatus->currentTrackOriginalFilename);
			# We could also log to history at this point as well...
		}
	} else {
		debugMsg("That wasn't a file - ignoring\n");
	}
	$playStatus->currentSongArtist("");
	$playStatus->currentSongTrack("");
	$playStatus->currentSongRating("");

	# Clear the stopwatch
	$playStatus->currentSongStopwatch()->clear();

	$playStatus->isPaused("false");
	$playStatus->isTiming("false");
}

sub markedAsPlayed {
	debugMsg("Entering markedAsPlayed\n");
	my $client = shift;
	my $url = shift;
	my $ds        = Plugins::TrackStat::Storage::getCurrentDS();
	my $track     = Plugins::TrackStat::Storage::objectForUrl($url);
	my $trackHandle = Plugins::TrackStat::Storage::findTrack( $url,undef,$track);

	my $playCount;
	if($trackHandle && $trackHandle->playCount) {
		$playCount = $trackHandle->playCount + 1;
	}elsif(getPlayCount($track)){
		$playCount = getPlayCount($track);
	}else {
		$playCount = 1;
	}

	my $lastPlayed = getLastPlayed($track);
	if(!$lastPlayed) {
		$lastPlayed = time();
	}
	my $mbId = undef;
	my $rating = undef;
	if ($trackHandle) {
		$mbId = $trackHandle->mbId;
		$rating = $trackHandle->rating;
	}elsif ($::VERSION ge '6.5') {
		$rating = $track->{rating};
	}
	 
	Plugins::TrackStat::Storage::savePlayCountAndLastPlayed($url,$mbId,$playCount,$lastPlayed);
	Plugins::TrackStat::Storage::addToHistory($url,$mbId,$lastPlayed,$rating);
	
	my %statistic = (
		'url' => $url,
		'playCount' => $playCount,
		'lastPlayed' => $lastPlayed,
		'rating' => $rating,
		'mbId' => $mbId,
	);
	no strict 'refs';
	for my $item (keys %playCountPlugins) {
		debugMsg("Calling $item\n");
		eval { &{$playCountPlugins{$item}}($client,$url,\%statistic) };
	}
	use strict 'refs';
	if ($::VERSION ge '6.5') {
		Slim::Control::Request::notifyFromArray($client, ['trackstat', 'changedstatistic', $url, $track->id, $playCount, $lastPlayed]);
	}else {
		$client->execute(['trackstat', 'changedstatistic', $url, $track->id, $playCount, $lastPlayed]);
	}
	debugMsg("Exiting markedAsPlayed\n");
}

# Debugging routine - shows current variable values for the given playStatus
sub showCurrentVariables($)
{
	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	debugMsg("======= showCurrentVariables() ========\n");
	debugMsg("Artist:",playStatus->currentSongArtist(),"\n");
	debugMsg("Track: ",$playStatus->currentSongTrack(),"\n");
	debugMsg("Album: ",$playStatus->currentSongAlbum(),"\n");
	debugMsg("Original Filename: ",$playStatus->currentTrackOriginalFilename(),"\n");
	debugMsg("Duration in seconds: ",$playStatus->currentTrackLength(),"\n"); 
	debugMsg("Time showing on stopwatch: ",$playStatus->currentSongStopwatch()->getElapsedTime(),"\n");
	debugMsg("Is song playback paused? : ",$playStatus->isPaused(),"\n");
	debugMsg("Are we currently timing? : ",$playStatus->isTiming(),"\n");
	debugMsg("=======================================\n");
}

sub trackWasPlayedEnoughToCountAsAListen($$)
{
	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	# Total time elapsed during play
	my $totalTimeElapsedDuringPlay = shift;

	my $wasLongEnough = 0;
	my $currentTrackLength = $playStatus->currentTrackLength();
	my $tmpCurrentSongTrack = $playStatus->currentSongTrack();

	my $minPlayedTime = Slim::Utils::Prefs::get("plugin_trackstat_min_song_length");
	if(!defined $minPlayedTime) {
		$minPlayedTime = 5;
	}

	my $thresholdTime = Slim::Utils::Prefs::get("plugin_trackstat_song_threshold_length");
	if(!defined $thresholdTime) {
		$thresholdTime = 1800;
	}

	my $minPlayedPercent = Slim::Utils::Prefs::get("plugin_trackstat_min_song_percent");
	if(!defined $minPlayedPercent) {
		$minPlayedPercent = 50;
	}

	# The minimum play time the % minimum requires
	my $minimumPlayLengthFromPercentPlayThreshold = $minPlayedPercent * $currentTrackLength / 100;

	my $printableDisplayThreshold = $minPlayedPercent;
	debugMsg("Time actually played in track: $totalTimeElapsedDuringPlay\n");
	#debugMsg("Current play threshold is $printableDisplayThreshold%.\n");
	#debugMsg("Minimum play time is $minPlayedTime seconds.\n");
	#debugMsg("Time play threshold is $thresholdTime seconds.\n");
	#debugMsg("Percentage play threshold calculation:\n");
	#debugMsg("$minPlayedPercent * $currentTrackLength / 100 = $minimumPlayLengthFromPercentPlayThreshold\n");	

	# Did it play at least the absolute minimum amount?
	if ($totalTimeElapsedDuringPlay < $minPlayedTime ) 
	{
		# No. This condition overrides the others.
		debugMsg("\"$tmpCurrentSongTrack\" NOT played long enough: Played $totalTimeElapsedDuringPlay; needed to play $minPlayedTime seconds.\n");
		$wasLongEnough = 0;   
	}
	# Did it play past the percent-of-track played threshold?
	elsif ($totalTimeElapsedDuringPlay >= $minimumPlayLengthFromPercentPlayThreshold)
	{
		# Yes. We have a play.
		debugMsg("\"$tmpCurrentSongTrack\" was played long enough to count as played.\n");
		debugMsg("Played past percentage threshold of $minimumPlayLengthFromPercentPlayThreshold seconds.\n");
		$wasLongEnough = 1;
	}
	# Did it play past the number-of-seconds played threshold?
	elsif ($totalTimeElapsedDuringPlay >= $thresholdTime)
	{
		# Yes. We have a play.
		debugMsg("\"$tmpCurrentSongTrack\" was played long enough to count as played.\n");
		debugMsg("Played past time threshold of $thresholdTime seconds.\n");
		$wasLongEnough = 1;
	} else {
		# We *could* do this calculation above, but I wanted to make it clearer
		# exactly why a play was too short, if it was too short, with explicit
		# debug messages.
		my $minimumPlayTimeNeeded;
		if ($minimumPlayLengthFromPercentPlayThreshold < $thresholdTime) {
			$minimumPlayTimeNeeded = $minimumPlayLengthFromPercentPlayThreshold;
		} else {
			$minimumPlayTimeNeeded = $thresholdTime;
		}
		# Otherwise, it played above the minimum 
		#, but below the thresholds, so, no play.
		debugMsg("\"$tmpCurrentSongTrack\" NOT played long enough: Played $totalTimeElapsedDuringPlay; needed to play $minimumPlayTimeNeeded seconds.\n");
		$wasLongEnough = 0;   
	}
	return $wasLongEnough;
}




sub rateSong($$$) {
	my ($client,$url,$rating)=@_;

	debugMsg("Changing song rating to: $rating\n");
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $track = Plugins::TrackStat::Storage::objectForUrl($url);
	if(!defined $track) {
		debugMsg("Failure setting rating, track does not exist: $url\n");
		return;
	}
	Plugins::TrackStat::Storage::saveRating($url,undef,$track,$rating);
	no strict 'refs';
	for my $item (keys %ratingPlugins) {
		debugMsg("Calling $item\n");
		eval { &{$ratingPlugins{$item}}($client,$url,$rating) };
	}
	my $digit = floor(($rating+10)/20);
	use strict 'refs';
	if ($::VERSION ge '6.5') {
		Slim::Control::Request::notifyFromArray($client, ['trackstat', 'changedrating', $url, $track->id, $digit, $rating]);
	}else {
		$client->execute(['trackstat', 'changedrating', $url, $track->id, $digit, $rating]);
	}
	Slim::Music::Info::clearFormatDisplayCache();
	$ratingStaticLastUrl = undef;
	$ratingDynamicLastUrl = undef;
	$ratingNumberLastUrl = undef;
}

sub setTrackStatRating {
	debugMsg("Entering setTrackStatRating\n");
	my ($client,$url,$rating)=@_;
	my $lowrating = floor(($rating+10) / 20);
	my $track = undef;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	if ($::VERSION ge '6.5') {
		eval {
			$track = Plugins::TrackStat::Storage::objectForUrl($url);
		};
		if ($@) {
			debugMsg("Error retrieving track: $url\n");
		}
		if($track) {
			# Run this within eval for now so it hides all errors until this is standard
			eval {
				$track->set('rating' => $rating);
				$track->update();
				$ds->forceCommit();
			};
		}
	}
	if(Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_enabled")) {
		my $mmurl = getMusicMagicURL($url);
		
		my $hostname = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_host");
		my $port = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_port");
		my $musicmagicurl = "http://$hostname:$port/api/setRating?song=$mmurl&rating=$lowrating";
		debugMsg("Calling: $musicmagicurl\n");
		my $http = Slim::Player::Protocols::HTTP->new({
	        'url'    => "$musicmagicurl",
	        'create' => 0,
	    });
	    if(defined($http)) {
	    	my $result = $http->content;
	    	chomp $result;
	    	if($result eq "1") {
				debugMsg("Success setting Music Magic rating\n");
			}else {
				debugMsg("Error setting Music Magic rating, error code = $result\n");
			}
	    	$http->close();
	    }else {
			debugMsg("Failure setting Music Magic rating\n");
	    }
	}
	if(Slim::Utils::Prefs::get("plugin_trackstat_itunes_enabled")) {
		my $itunesurl = getiTunesURL($url);
		my $dir = Slim::Utils::Prefs::get('plugin_trackstat_itunes_export_dir');
		my $filename = catfile($dir,"TrackStat_iTunes_Hist.txt");
		my $output = FileHandle->new($filename, ">>") or do {
			warn "Could not open $filename for writing.";
			return;
		};
		if(!defined($track)) {
			$track = Plugins::TrackStat::Storage::objectForUrl($url);
		}
		
		print $output "".$track->title."|||$itunesurl|rated||$rating\n";
		close $output;
	}
	debugMsg("Exiting setTrackStatRating\n");
}

sub getCLIRating {
	debugMsg("Entering getCLIRating\n");
	my $request = shift;
	
	if ($request->isNotQuery([['trackstat'],['getrating']])) {
		debugMsg("Incorrect command\n");
		$request->setStatusBadDispatch();
		debugMsg("Exiting getCLIRating\n");
		return;
	}
	# get our parameters
  	my $trackId    = $request->getParam('_trackid');
  	if(!defined $trackId || $trackId eq '') {
		debugMsg("_trackid not defined\n");
		$request->setStatusBadParams();
		debugMsg("Exiting getCLIRating\n");
		return;
  	}
  	
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $track;
	if($trackId !~ /^-?\d+$/) {
		if($trackId =~ /^\/.+$/) {
			$trackId = Slim::Utils::Misc::fileURLFromPath($trackId);
		}
		# The encapsulation with eval is just to make it more crash safe
		eval {
			$track = Plugins::TrackStat::Storage::objectForUrl($trackId);
		};
		if ($@) {
			debugMsg("Error retrieving track: $trackId\n");
		}
	}else {
		# The encapsulation with eval is just to make it more crash safe
		eval {
			$track = Plugins::TrackStat::Storage::objectForId('track',$trackId);
		};
		if ($@) {
			debugMsg("Error retrieving track: $trackId\n");
		}
	}
	
	if(!defined $track || !defined $track->audio) {
		debugMsg("Track $trackId not found\n");
		$request->setStatusBadParams();
		debugMsg("Exiting getCLIRating\n");
		return;
	}
	my $trackHandle = Plugins::TrackStat::Storage::findTrack( $track->url,undef,$track);
	my $resultRating = 0;
	my $resultDigit = 0;
	if($trackHandle && $trackHandle->rating) {
		$resultRating = $trackHandle->rating;
		$resultDigit = floor(($trackHandle->rating+10)/20);
	}
	$request->addResult('rating', $resultDigit);
	$request->addResult('ratingpercentage', $resultRating);
	$request->setStatusDone();
	debugMsg("Exiting getCLIRating\n");
}

sub getCLIRating62 {
	debugMsg("Entering getCLIRating62\n");
	my $client = shift;
	my $paramsRef = shift;
	
	if (scalar(@$paramsRef) lt 3) {
		debugMsg("Incorrect number of parameters\n");
		debugMsg("Exiting getCLIRating62\n");
		return;
	}
	if (@$paramsRef[1] ne "getrating") {
		debugMsg("Incorrect command\n");
		debugMsg("Exiting getCLIRating62\n");
		return;
	}
	# get our parameters
  	my $trackId    = @$paramsRef[2];
  	if(!defined $trackId || $trackId eq '') {
		debugMsg("_trackid not defined\n");
		debugMsg("Exiting getCLIRating62\n");
		return;
  	}
  	
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $track;
	if($trackId !~ /^-?\d+$/) {
		if($trackId =~ /^\/.+$/) {
			$trackId = Slim::Utils::Misc::fileURLFromPath($trackId);
		}
		# The encapsulation with eval is just to make it more crash safe
		eval {
			$track = Plugins::TrackStat::Storage::objectForUrl($trackId);
		};
		if ($@) {
			debugMsg("Error retrieving track: $trackId\n");
		}
	}else {
		# The encapsulation with eval is just to make it more crash safe
		eval {
			$track = Plugins::TrackStat::Storage::objectForId('track',$trackId);
		};
		if ($@) {
			debugMsg("Error retrieving track: $trackId\n");
		}
	}
	
	if(!defined $track || !defined $track->audio) {
		debugMsg("Track $trackId not found\n");
		debugMsg("Exiting getCLIRating62\n");
		return;
	}
	my $trackHandle = Plugins::TrackStat::Storage::findTrack( $track->url,undef,$track);
	my $resultRating = 0;
	my $resultDigit = 0;
	if($trackHandle && $trackHandle->rating) {
		$resultRating = $trackHandle->rating;
		$resultDigit = floor(($trackHandle->rating+10)/20);
	}
	push @$paramsRef,"rating:$resultDigit";
	push @$paramsRef,"ratingpercentage:$resultRating";
	debugMsg("Exiting getCLIRating62\n");
}

sub setCLIRating {
	debugMsg("Entering setCLIRating\n");
	my $request = shift;
	my $client = $request->client();
	
	if ($request->isNotCommand([['trackstat'],['setrating']])) {
		debugMsg("Incorrect command\n");
		$request->setStatusBadDispatch();
		debugMsg("Exiting setCLIRating\n");
		return;
	}
	if(!defined $client) {
		debugMsg("Client required\n");
		$request->setStatusNeedsClient();
		debugMsg("Exiting setCLIRating\n");
		return;
	}

	# get our parameters
  	my $trackId    = $request->getParam('_trackid');
  	my $rating    = $request->getParam('_rating');
  	if(!defined $trackId || $trackId eq '' || !defined $rating || $rating eq '') {
		debugMsg("_trackid and _rating not defined\n");
		$request->setStatusBadParams();
		debugMsg("Exiting setCLIRating\n");
		return;
  	}
  	
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $track;
	if($trackId !~ /^-?\d+$/) {
		if($trackId =~ /^\/.+$/) {
			$trackId = Slim::Utils::Misc::fileURLFromPath($trackId);
		}
		# The encapsulation with eval is just to make it more crash safe
		eval {
			$track = Plugins::TrackStat::Storage::objectForUrl($trackId);
		};
		if ($@) {
			debugMsg("Error retrieving track: $trackId\n");
		}
	}else {
		# The encapsulation with eval is just to make it more crash safe
		eval {
			$track = Plugins::TrackStat::Storage::objectForId('track',$trackId);
		};
		if ($@) {
			debugMsg("Error retrieving track: $trackId\n");
		}
	}
	
	if(!defined $track || !defined $track->audio) {
		debugMsg("Track $trackId not found\n");
		$request->setStatusBadParams();
		debugMsg("Exiting setCLIRating\n");
		return;
	}
	if($rating =~ /.*%$/) {
		$rating =~ s/%$//;
	}else {
		$rating = $rating*20;
	}
	rateSong($client,$track->url,$rating);
	
	my $digit = floor(($rating+10)/20);
	$request->addResult('rating', $digit);
	$request->addResult('ratingpercentage', $rating);
	$request->setStatusDone();
	debugMsg("Exiting setCLIRating\n");
}

sub setCLIRating62 {
	debugMsg("Entering setCLIRating62\n");
	my $client = shift;
	my $paramsRef = shift;
	
	if (scalar(@$paramsRef) lt 4) {
		debugMsg("Incorrect number of parameters\n");
		debugMsg("Exiting setCLIRating62\n");
		return;
	}
	if (@$paramsRef[1] ne "setrating") {
		debugMsg("Incorrect command\n");
		debugMsg("Exiting setCLIRating62\n");
		return;
	}
	if(!defined $client) {
		debugMsg("Client required\n");
		debugMsg("Exiting setCLIRating62\n");
		return;
	}

	# get our parameters
  	my $trackId    = @$paramsRef[2];
  	my $rating    = @$paramsRef[3];
  	if(!defined $trackId || $trackId eq '' || !defined $rating || $rating eq '') {
		debugMsg("_trackid and _rating not defined\n");
		debugMsg("Exiting setCLIRating62\n");
		return;
  	}
  	
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $track;
	if($trackId !~ /^-?\d+$/) {
		if($trackId =~ /^\/.+$/) {
			$trackId = Slim::Utils::Misc::fileURLFromPath($trackId);
		}
		# The encapsulation with eval is just to make it more crash safe
		eval {
			$track = Plugins::TrackStat::Storage::objectForUrl($trackId);
		};
		if ($@) {
			debugMsg("Error retrieving track: $trackId\n");
		}
	}else {
		# The encapsulation with eval is just to make it more crash safe
		eval {
			$track = Plugins::TrackStat::Storage::objectForId('track',$trackId);
		};
		if ($@) {
			debugMsg("Error retrieving track: $trackId\n");
		}
	}
	
	if(!defined $track || !defined $track->audio) {
		debugMsg("Track $trackId not found\n");
		debugMsg("Exiting setCLIRating62\n");
		return;
	}
	
	if($rating =~ /.*%$/) {
		$rating =~ s/%$//;
	}else {
		$rating = $rating*20;
	}
	rateSong($client,$track->url,$rating);
	
	my $digit = floor(($rating+10)/20);
	push @$paramsRef,"rating:$digit";
	push @$paramsRef,"ratingpercentage:$rating";
	debugMsg("Exiting setCLIRating62\n");
}

sub gotViaHTTP {
	my $http  = shift;
	my $params = $http->params;
	my $result = $http->content;
	chomp $result;
	if($result eq "1") {
		debugMsg("Success setting Music Magic ".$params->{'command'}."\n");
	}else {
		debugMsg("Error setting Music Magic ".$params->{'command'}.", error code = $result\n");
	}
	$http->close();
}

sub gotErrorViaHTTP {
	my $http  = shift;
	my $params = $http->params;
	debugMsg("Failure setting Music Magic ".$params->{'command'}."\n");
}

sub setTrackStatStatistic {
	debugMsg("Entering setTrackStatStatistic\n");
	my ($client,$url,$statistic)=@_;
	
	my $playCount = $statistic->{'playCount'};
	my $lastPlayed = $statistic->{'lastPlayed'};	
	my $rating = $statistic->{'rating'};
	if(Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_enabled")) {
		my $mmurl = getMusicMagicURL($url);
		
		my $hostname = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_host");
		my $port = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_port");
		my $musicmagicurl = "http://$hostname:$port/api/setPlayCount?song=$mmurl&count=$playCount";
		debugMsg("Calling: $musicmagicurl\n");
		my $http = Slim::Networking::SimpleAsyncHTTP->new(\&gotViaHTTP, \&gotErrorViaHTTP, {'command' => 'playCount' });
		$http->get($musicmagicurl);
		$musicmagicurl = "http://$hostname:$port/api/setLastPlayed?song=$mmurl&time=$lastPlayed";
		debugMsg("Calling: $musicmagicurl\n");
		$http = Slim::Networking::SimpleAsyncHTTP->new(\&gotViaHTTP, \&gotErrorViaHTTP, {'command' => 'lastPlayed' });
		$http->get($musicmagicurl);
	}
	if(Slim::Utils::Prefs::get("plugin_trackstat_itunes_enabled")) {
		my $itunesurl = getiTunesURL($url);
		my $dir = Slim::Utils::Prefs::get('plugin_trackstat_itunes_export_dir');
		my $filename = catfile($dir,"TrackStat_iTunes_Hist.txt");
		my $output = FileHandle->new($filename, ">>") or do {
			warn "Could not open $filename for writing.";
			return;
		};
		my $ds = Plugins::TrackStat::Storage::getCurrentDS();
		my $track = Plugins::TrackStat::Storage::objectForUrl($url);
		if(!defined $rating) {
			$rating = '';
		}
		if(defined $lastPlayed) {
			my $timestr = strftime ("%Y%m%d%H%M%S", localtime $lastPlayed);
			print $output "".$track->title."|||$itunesurl|played|$timestr|$rating\n";
		}
		close $output;
	}
	debugMsg("Exiting setTrackStatStatistic\n");
}
	
sub getMusicMagicURL {
	my $url = shift;
	my $replacePath = Slim::Utils::Prefs::get("plugin_trackstat_musicmagic_library_music_path");
	if(defined $replacePath && $replacePath ne '') {
		$replacePath = escape($replacePath);
		my $nativeRoot = Slim::Utils::Prefs::get('audiodir');
		my $nativeUrl = Slim::Utils::Misc::fileURLFromPath($nativeRoot);
		if($url =~ /$nativeUrl/) {
			$url =~ s/$nativeUrl/$replacePath/isg;
		}else {
			$url = Slim::Utils::Misc::pathFromFileURL($url);
		}
	}else {
		$url = Slim::Utils::Misc::pathFromFileURL($url);
	}

	my $replaceExtension = Slim::Utils::Prefs::get('plugin_trackstat_musicmagic_replace_extension');;
	if($replaceExtension) {
		$url =~ s/\.[^.]*$/$replaceExtension/isg;
	}
	$url =~ s/\\/\//isg;
	$url = unescape($url);
	$url = URI::Escape::uri_escape($url);
	return $url;
}	

sub getiTunesURL {
	my $url = shift;
	my $replaceExtension = Slim::Utils::Prefs::get('plugin_trackstat_itunes_export_replace_extension');
	my $replacePath = Slim::Utils::Prefs::get('plugin_trackstat_itunes_export_library_music_path');
	my $nativeRoot = Slim::Utils::Prefs::get('audiodir');
	$nativeRoot =~ s/\\/\//isg;
	if(defined($replacePath) && $replacePath ne '') {
		$replacePath =~ s/\\/\//isg;
	}

	my $path = Slim::Utils::Misc::pathFromFileURL($url);
	if($replaceExtension) {
		$path =~ s/\.[^.]*$/$replaceExtension/isg;
	}

	if(defined($replacePath) && $replacePath ne '') {
		$path =~ s/\\/\//isg;
		$path =~ s/$nativeRoot/$replacePath/isg;
	}

	return $path;
}	

my %musicInfoSCRItems = (
	'TRACKSTAT_RATING_DYNAMIC' => 'TRACKSTAT_RATING_DYNAMIC',
	'PLAYING (X_OF_Y) TRACKSTAT_RATING_DYNAMIC' => 'PLAYING (X_OF_Y) TRACKSTAT_RATING_DYNAMIC',
	'TRACKSTAT_RATING_STATIC' => 'TRACKSTAT_RATING_STATIC',
	'PLAYING (X_OF_Y) TRACKSTAT_RATING_STATIC' => 'PLAYING (X_OF_Y) TRACKSTAT_RATING_STATIC',
	'TRACKSTAT_RATING_NUMBER' => 'TRACKSTAT_RATING_NUMBER',
);

sub getMusicInfoSCRCustomItems() 
{
	return \%musicInfoSCRItems;
}

sub getMusicInfoSCRCustomItem()
{
	debugMsg("Entering getMusicInfoSCRCustomItem\n");
	my $client = shift;
    my $formattedString  = shift;
	if ($formattedString =~ /TRACKSTAT_RATING_STATIC/) {
		my $playStatus = getTrackInfo($client);
		my $string = $NO_RATING_CHARACTER x 5;
		if($playStatus->currentSongRating()) {
			$string = ($playStatus->currentSongRating()?$RATING_CHARACTER x $playStatus->currentSongRating():'');
			my $left = 5 - $playStatus->currentSongRating();
			$string = $string . ($NO_RATING_CHARACTER x $left);
		}
		$formattedString =~ s/TRACKSTAT_RATING_STATIC/$string/g;
	}
	if ($formattedString =~ /TRACKSTAT_RATING_DYNAMIC/) {
		my $playStatus = getTrackInfo($client);
		my $string = ($playStatus->currentSongRating()?$RATING_CHARACTER x $playStatus->currentSongRating():'');
		$formattedString =~ s/TRACKSTAT_RATING_DYNAMIC/$string/g;
	}
	if ($formattedString =~ /TRACKSTAT_RATING_NUMBER/) {
		my $playStatus = getTrackInfo($client);
		my $string = ($playStatus->currentSongRating()?$playStatus->currentSongRating():'');
		$formattedString =~ s/TRACKSTAT_RATING_NUMBER/$string/g;
	}
	debugMsg("Exiting getMusicInfoSCRCustomItem\n");
	return $formattedString;
}


sub getRatingDynamicCustomItem
{
	my $track = shift;
	my $string = '';
	if(defined($ratingDynamicLastUrl) && $track->url eq $ratingDynamicLastUrl) {
		$string = $ratingDynamicCache;
	}else {
		debugMsg("Entering getRatingDynamicCustomItem\n");
		my $trackHandle = Plugins::TrackStat::Storage::findTrack( $track->url,undef,$track);
		if($trackHandle && $trackHandle->rating) {
			my $rating = floor(($trackHandle->rating+10) / 20);
			$string = ($rating?$RATING_CHARACTER x $rating:'');
		}
		$ratingDynamicLastUrl = $track->url;
		$ratingDynamicCache = $string;
		debugMsg("Exiting getRatingDynamicCustomItem\n");
	}
	return $string;
}

sub getRatingStaticCustomItem
{
	my $track = shift;
	my $string = $NO_RATING_CHARACTER x 5;
	if(defined($ratingStaticLastUrl) && $track->url eq $ratingStaticLastUrl) {
		$string = $ratingStaticCache;
	}else {
		debugMsg("Entering getRatingStaticCustomItem\n");
		my $trackHandle = Plugins::TrackStat::Storage::findTrack( $track->url,undef,$track);
		if($trackHandle && $trackHandle->rating) {
			my $rating = floor(($trackHandle->rating+10) / 20);
			debugMsg("rating = $rating\n");
			if($rating) {
				$string = ($rating?$RATING_CHARACTER x $rating:'');
				my $left = 5 - $rating;
				$string = $string . ($NO_RATING_CHARACTER x $left);
			}
		}
		$ratingStaticLastUrl = $track->url;
		$ratingStaticCache = $string;
		debugMsg("Exiting getRatingStaticCustomItem\n");
	}
	return $string;
}

sub getRatingNumberCustomItem
{
	my $track = shift;
	my $string = '';
	if(defined($ratingNumberLastUrl) && $track->url eq $ratingNumberLastUrl) {
		$string = $ratingNumberCache;
	}else {
		debugMsg("Entering getRatingNumberCustomItem\n");
		my $trackHandle = Plugins::TrackStat::Storage::findTrack( $track->url,undef,$track);
		if($trackHandle && $trackHandle->rating) {
			my $rating = floor(($trackHandle->rating+10) / 20);
			$string = ($rating?$rating:'');
		}
		$ratingNumberLastUrl = $track->url;
		$ratingNumberCache = $string;
		debugMsg("Exiting getRatingNumberCustomItem\n");
	}
	return $string;
}

sub importFromiTunes()
{
	Plugins::TrackStat::iTunes::Import::startImport();
}

sub exportToiTunes()
{
	Plugins::TrackStat::iTunes::Export::startExport();
}

sub importFromMusicMagic()
{
	Plugins::TrackStat::MusicMagic::Import::startImport();
}

sub exportToMusicMagic()
{
	Plugins::TrackStat::MusicMagic::Export::startExport();
}

sub backupToFile() 
{
	my $backupfile = shift;
	if(!defined($backupfile)) {
		$backupfile = Slim::Utils::Prefs::get("plugin_trackstat_backup_file");
	}
	if($backupfile) {
		Plugins::TrackStat::Backup::File::backupToFile($backupfile);
	}
}

sub restoreFromFile()
{
	my $backupfile = Slim::Utils::Prefs::get("plugin_trackstat_backup_file");
	if($backupfile) {
		Plugins::TrackStat::Backup::File::restoreFromFile($backupfile);
	}
}

sub getDynamicPlayLists {
	my ($client) = @_;
	my %result = ();

	return \%result unless Slim::Utils::Prefs::get("plugin_trackstat_dynamicplaylist");
	
	my $statistics = getStatisticPlugins();
	for my $item (keys %$statistics) {
		my $id = $statistics->{$item}->{'id'};
		my $playlistid = "trackstat_".$id;
		my %playlistItem = (
			'id' => $id
		);
		if(defined($statistics->{$item}->{'namefunction'})) {
			$playlistItem{'name'} = eval { &{$statistics->{$item}->{'namefunction'}}() };
		}else {
			$playlistItem{'name'} = $statistics->{$item}->{'name'};
		}
		$playlistItem{'url'}="plugins/TrackStat/".$id.".html?";
		if(defined($statistics->{$item}->{'groups'})) {
			$playlistItem{'groups'} = $statistics->{$item}->{'groups'};
		}

		$result{$playlistid} = \%playlistItem;
	}

	return \%result;
}

sub getNextDynamicPlayListTracks {
	my ($client,$dynamicplaylist,$limit,$offset) = @_;

	my $result;

    my $listLength = Slim::Utils::Prefs::get("plugin_trackstat_playlist_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
	debugMsg("Got: ".$dynamicplaylist->{'id'}.", $limit\n");
	my $statistics = getStatisticPlugins();
	for my $item (keys %$statistics) {
		my $id = $statistics->{$item}->{'id'};
		if($dynamicplaylist->{'id'} eq $id) {
			debugMsg("Calling playlistfunction for ".$dynamicplaylist->{'id'}."\n");
			eval {
				$result = &{$statistics->{$item}->{'playlistfunction'}}($listLength,$limit);
			};
			if ($@) {
		    	debugMsg("Failure calling playlistfunction for ".$dynamicplaylist->{'id'}.": $@\n");
		    }
		}
	}
	my @resultArray = ();
	for my $track (@$result) {
		push @resultArray,$track;
	}
	debugMsg("Got ".scalar(@resultArray)." tracks\n");
	return \@resultArray;
}

sub validateIsDirOrEmpty {
	my $arg = shift;
	if(!$arg || $arg eq '') {
		return $arg;
	}else {
		if ($::VERSION ge '6.5') {
			return Slim::Utils::Validate::isDir($arg);
		}else {
			return Slim::Web::Setup::validateIsDir($arg);
		}
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

sub validateIsFileOrEmpty {
	my $arg = shift;
	if(!$arg || $arg eq '') {
		return $arg;
	}else {
		if ($::VERSION ge '6.5') {
			return Slim::Utils::Validate::isFile($arg);
		}else {
			return Slim::Web::Setup::validateIsFile($arg);
		}
	}
}

sub validateIsTimeOrEmpty {
	my $arg = shift;
	if(!$arg || $arg eq '') {
		return $arg;
	}else {
		if ($::VERSION ge '6.5') {
			return Slim::Utils::Validate::isTime($arg);
		}else {
			return Slim::Web::Setup::validateTime($arg);
		}
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

sub strings() { 
	my $pluginStrings = getStatisticPluginsStrings();
	my $str = "
TRACKSTAT
	EN	TrackStat

PLUGIN_TRACKSTAT
	EN	TrackStat

PLUGIN_TRACKSTAT_ACTIVATED
	EN	TrackStat Activated...

PLUGIN_TRACKSTAT_NOTACTIVATED
	EN	TrackStat Not Activated...

PLUGIN_TRACKSTAT_TRACK
	EN	Track:
	
PLUGIN_TRACKSTAT_RATING
	EN	Rating:
	
PLUGIN_TRACKSTAT_LAST_PLAYED
	EN	Played:
	
PLUGIN_TRACKSTAT_PLAY_COUNT
	EN	Play Count:
	
PLUGIN_TRACKSTAT_SETUP_GROUP
	EN	TrackStat settings

PLUGIN_TRACKSTAT_SETUP_GROUP_DESC
	EN	The TrackStat plugin provides a possiblilty to keep the statistic information in a safe place which survives rescans of the music library. It also makes it possible to give each track a rating.<br>Statistic information about rating, play counts and last played time can also be imported from iTunes.

PLUGIN_TRACKSTAT_SHOW_MESSAGES
	EN	Write messages to log

SETUP_PLUGIN_TRACKSTAT_SHOWMESSAGES
	EN	Debug logging

SETUP_PLUGIN_TRACKSTAT_SHOWMESSAGES_DESC
	EN	This will turn on/off debug logging of the TrackStat plugin

PLUGIN_TRACKSTAT_DEEP_HIERARCHY
	EN	Group statistics into deep group hierarchy

SETUP_PLUGIN_TRACKSTAT_DEEP_HIERARCHY
	EN	Group statistics into deep group hierarchy

SETUP_PLUGIN_TRACKSTAT_DEEP_HIERARCHY_DESC
	EN	This will create a deeper group hierarchy making the groups a little smaller

PLUGIN_TRACKSTAT_WEB_FLATLIST
	EN	Group statistics into groups

SETUP_PLUGIN_TRACKSTAT_WEB_FLATLIST
	EN	Web interface structure

SETUP_PLUGIN_TRACKSTAT_WEB_FLATLIST_DESC
	EN	This will group the statistics in the web interface into different groups to simplify browsing the statistics.

PLUGIN_TRACKSTAT_PLAYER_FLATLIST
	EN	Group statistics into groups

SETUP_PLUGIN_TRACKSTAT_PLAYER_FLATLIST
	EN	Player interface structure

SETUP_PLUGIN_TRACKSTAT_PLAYER_FLATLIST_DESC
	EN	This will group the statistics in the player interface into different groups to simplify browsing the statistics.

PLUGIN_TRACKSTAT_FORCE_GROUPRATING
	EN	Force album ratings on rated tracks

SETUP_PLUGIN_TRACKSTAT_FORCE_GROUPRATING
	EN	Group ratings

SETUP_PLUGIN_TRACKSTAT_FORCE_GROUPRATING_DESC
	EN	If enabled already rated tracks will change rating when changing ratings on an album, if disabled rating an album only means that unrated tracks on that album will get a rating

PLUGIN_TRACKSTAT_REFRESH_STARTUP
	EN	Refresh statistics at startup

SETUP_PLUGIN_TRACKSTAT_REFRESH_STARTUP
	EN	Startup refresh

SETUP_PLUGIN_TRACKSTAT_REFRESH_STARTUP_DESC
	EN	This will activate/deactivate the refresh statistic operation at slimserver startup, the only reason to turn this if is if you get performance issues with refresh statistics

PLUGIN_TRACKSTAT_REFRESH_RESCAN
	EN	Rescan refresh

SETUP_PLUGIN_TRACKSTAT_REFRESH_RESCAN
	EN	Rescan refresh (slimserver 6.5 only)

SETUP_PLUGIN_TRACKSTAT_REFRESH_RESCAN_DESC
	EN	This will activate/deactivate the automatic refresh statistic operation after a rescan has been performed in slimserver, the only reason to turn this if is if you get performance issues with refresh statistics.<br>Note! This parameter does only have effect if you run slimserver 6.5

PLUGIN_TRACKSTAT_HISTORY_ENABLED
	EN	Enable/disable History

SETUP_PLUGIN_TRACKSTAT_HISTORY_ENABLED
	EN	History

SETUP_PLUGIN_TRACKSTAT_HISTORY_ENABLED_DESC
	EN	This will activate/deactivate history logging in TrackStat. With history logging enabled TrackStat will store the exact time each time a track is played and can with this information calculate statistics such as \"Most played tracks in last month\". With history disabled TrackStat will only have information about the last time a specific track was played. You might want to try to disable history logging if you get performance problems with TrackStat.

PLUGIN_TRACKSTAT_DYNAMICPLAYLIST
	EN	Enable Dynamic Playlists

SETUP_PLUGIN_TRACKSTAT_DYNAMICPLAYLIST
	EN	Dynamic Playlists integration 

SETUP_PLUGIN_TRACKSTAT_DYNAMICPLAYLIST_DESC
	EN	This will turn on/off integration with Dynamic Playlists plugin making the statistics available as playlists

PLUGIN_TRACKSTAT_ITUNES_IMPORTING
	EN	Importing from iTunes...

PLUGIN_TRACKSTAT_ITUNES_EXPORTING
	EN	Exporting to iTunes...

PLUGIN_TRACKSTAT_ITUNES_IMPORT_BUTTON
	EN	Import from iTunes

SETUP_PLUGIN_TRACKSTAT_ITUNES_IMPORT
	EN	Import from iTunes

SETUP_PLUGIN_TRACKSTAT_ITUNES_IMPORT_DESC
	EN	Import information from the specified iTunes Music Library.xml file. This means that any existing rating, play counts or last played information in iTunes will overwrite any existing information.

PLUGIN_TRACKSTAT_ITUNES_EXPORT_BUTTON
	EN	Export to iTunes

SETUP_PLUGIN_TRACKSTAT_ITUNES_EXPORT
	EN	Export to iTunes

SETUP_PLUGIN_TRACKSTAT_ITUNES_EXPORT_DESC
	EN	Export information from TrackStat to the iTunes history file(TrackStat_iTunes_Complete.txt). Note that the generated iTunes history file must be run with the TrackStatiTunesUpdateWin.pl script to actually export the data to iTunes.

PLUGIN_TRACKSTAT_ITUNES_LIBRARY_FILE
	EN	Path to iTunes Music Library.xml

SETUP_PLUGIN_TRACKSTAT_ITUNES_LIBRARY_FILE
	EN	iTunes Music Library file

SETUP_PLUGIN_TRACKSTAT_ITUNES_LIBRARY_FILE_DESC
	EN	This parameter shall be the full path to the iTunes Music Library.xml file that should be used when importing information from iTunes.

PLUGIN_TRACKSTAT_ITUNES_EXPORT_DIR
	EN	iTunes history file directory

SETUP_PLUGIN_TRACKSTAT_ITUNES_EXPORT_DIR
	EN	iTunes history file directory

SETUP_PLUGIN_TRACKSTAT_ITUNES_EXPORT_DIR_DESC
	EN	This parameter shall be the full path to the directory where the iTunes history file should be written when exporting to iTunes. Note that the generated iTunes history file must be run with the TrackStatiTunesUpdate.pl script to actually export the data to iTunes.<br>A complete export will generate a TrackStat_iTunes_Complete.txt file, continously export when playing will generate a TrackStat_iTunes_Hist.txt file<br>Note! the TrackStatiTunesUpdateWin.pl script is only supported for iTunes on Windows.

PLUGIN_TRACKSTAT_ITUNES_MUSIC_DIRECTORY
	EN	Path to iTunes Music (import)

SETUP_PLUGIN_TRACKSTAT_ITUNES_LIBRARY_MUSIC_PATH
	EN	Music directory (iTunes import)

SETUP_PLUGIN_TRACKSTAT_ITUNES_LIBRARY_MUSIC_PATH_DESC
	EN	The begining of the paths of the music imported from iTunes will be replaced with this path. This makes it possible to have the music in a different directory in iTunes compared to the directory where the music is accessible on the slimserver computer.

PLUGIN_TRACKSTAT_ITUNES_EXPORT_MUSIC_DIRECTORY
	EN	Path to iTunes Music (export)

SETUP_PLUGIN_TRACKSTAT_ITUNES_EXPORT_LIBRARY_MUSIC_PATH
	EN	Music directory (iTunes export)

SETUP_PLUGIN_TRACKSTAT_ITUNES_EXPORT_LIBRARY_MUSIC_PATH_DESC
	EN	The begining of the paths of the music exported to iTunes will be replaced with this path. This makes it possible to have the music in a different directory in iTunes compared to the directory where the music is accessible on the slimserver computer.

PLUGIN_TRACKSTAT_ITUNES_REPLACE_EXTENSION
	EN	File extension to use in files imported from iTunes
	
SETUP_PLUGIN_TRACKSTAT_ITUNES_REPLACE_EXTENSION
	EN	iTunes import extension
	
SETUP_PLUGIN_TRACKSTAT_ITUNES_REPLACE_EXTENSION_DESC
	EN	The file extensions of the music files imported from iTunes can be replaced with this extension. This makes it possible to have .mp3 files in iTunes and have .flac files in slimserver with the same name besides the extension. This is usefull if flac2mp3 is used to convert flac files to mp3 for usage with iTunes.
	
PLUGIN_TRACKSTAT_ITUNES_EXPORT_REPLACE_EXTENSION
	EN	File extension to use in files exported to iTunes
	
SETUP_PLUGIN_TRACKSTAT_ITUNES_EXPORT_REPLACE_EXTENSION
	EN	iTunes export extension
	
SETUP_PLUGIN_TRACKSTAT_ITUNES_EXPORT_REPLACE_EXTENSION_DESC
	EN	The file extensions of the music files exported to iTunes can be replaced with this extension. This makes it possible to have .mp3 files in iTunes and have .flac files in slimserver with the same name besides the extension. This is usefull if flac2mp3 is used to convert flac files to mp3 for usage with iTunes.
	
PLUGIN_TRACKSTAT_MUSICMAGIC_ENABLED
	EN	Enable dynamic MusicIP Mixer integration

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_ENABLED
	EN	MusicIP Mixer Dynamic Integration

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_ENABLED_DESC
	EN	Enable ratings, play counts and last played time to be sent continously to MusicIP Mixer as songs are played and rated

PLUGIN_TRACKSTAT_ITUNES_ENABLED
	EN	Enable dynamic iTunes integration

SETUP_PLUGIN_TRACKSTAT_ITUNES_ENABLED
	EN	iTunes Dynamic Integration

SETUP_PLUGIN_TRACKSTAT_ITUNES_ENABLED_DESC
	EN	Enable ratings, play counts and last played time to be sent to a iTunes history file as songs are played and rated. The iTunes history file will be called TrackStat_iTunes_Hist.txt and has to be run with the TrackStatiTunesUpdateWin.pl script to actually write the information to iTunes.

PLUGIN_TRACKSTAT_MUSICMAGIC_HOST
	EN	Hostname

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_HOST
	EN	MusicIP Mixer server hostname

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_HOST_DESC
	EN	Hostname of MusicIP Mixer server, default is localhost

PLUGIN_TRACKSTAT_MUSICMAGIC_PORT
	EN	Port

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_PORT
	EN	MusicIP Mixer server port

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_PORT_DESC
	EN	Port on MusicIP Mixer server, default is 10002

PLUGIN_TRACKSTAT_MUSICMAGIC_MUSIC_DIRECTORY
	EN	Music directory

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_LIBRARY_MUSIC_PATH
	EN	MusicIP Mixer music path

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_LIBRARY_MUSIC_PATH_DESC
	EN	The begining of the paths of the music will be replaced with this path when calling MusicIP Mixer for setting ratings and play counts. This makes it possible to have the music in a different directory in MusicIP Mixer compared to the directory where the music is accessible on the slimserver computer. During import/export this path will also be used to convert slimserver paths to MusicIP Mixer paths.

PLUGIN_TRACKSTAT_MUSICMAGIC_REPLACE_EXTENSION
	EN	File extension to use when calling MusicIP Mixer

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_REPLACE_EXTENSION
	EN	MusicIP Mixer export extension

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_REPLACE_EXTENSION_DESC
	EN	The file extensions of to use when sending ratings and play counts to MusicIP Mixer, this is the extension used for files in MusicIP Mixer. This makes it possible to have .mp3 files in MusicIP Mixer and have .flac files in slimserver with the same name besides the extension. This is usefull if flac2mp3 is used to convert flac files to mp3 for usage with MusicIP Mixer.

PLUGIN_TRACKSTAT_MUSICMAGIC_SLIMSERVER_REPLACE_EXTENSION
	EN	File extension to use when importing from MusicIP Mixer

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_SLIMSERVER_REPLACE_EXTENSION
	EN	MusicIP Mixer import extension

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_SLIMSERVER_REPLACE_EXTENSION_DESC
	EN	The file extensions of to use when importing tracks from MusicIP Mixer, this is the extension used for files in slimserver. This makes it possible to have .mp3 files in MusicIP Mixer and have .flac files in slimserver with the same name besides the extension. This is usefull if flac2mp3 is used to convert flac files to mp3 for usage with MusicIP Mixer.

PLUGIN_TRACKSTAT_MUSICMAGIC_IMPORTING
	EN	Importing from MusicIP Mixer...

PLUGIN_TRACKSTAT_MUSICMAGIC_IMPORT_BUTTON
	EN	Import from MusicIP Mixer

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_IMPORT
	EN	MusicIP Mixer import

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_IMPORT_DESC
	EN	Import information from the specified MusicIP Mixer server. This means that any existing rating, play counts or last played information in MusicIP Mixer will overwrite any existing information. 

PLUGIN_TRACKSTAT_MUSICMAGIC_EXPORTING
	EN	Exporting to MusicIP Mixer...

PLUGIN_TRACKSTAT_MUSICMAGIC_EXPORT_BUTTON
	EN	Export to MusicIP Mixer

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_EXPORT
	EN	MusicIP Mixer export

SETUP_PLUGIN_TRACKSTAT_MUSICMAGIC_EXPORT_DESC
	EN	Export information from TrackStat to the specified MusicIP Mixer server. This means that any existing rating, play counts or last played information in TrackStat will overwrite any existing information in MusicIP Mixer. Note that an export to MusicIP Mixer might take some time.

PLUGIN_TRACKSTAT_RATINGCHAR
	EN	Character

SETUP_PLUGIN_TRACKSTAT_RATINGCHAR
	EN	Rating display character

SETUP_PLUGIN_TRACKSTAT_RATINGCHAR_DESC
	EN	The character used to display ratings

PLUGIN_TRACKSTAT_BACKUP_FILE
	EN	Backup file

SETUP_PLUGIN_TRACKSTAT_BACKUP_FILE
	EN	Backup file

SETUP_PLUGIN_TRACKSTAT_BACKUP_FILE_DESC
	EN	File used for TrackStat information backup. This file must be in a place where the user which is running slimserver has read/write access.

PLUGIN_TRACKSTAT_BACKUP_DIR
	EN	Backup dir

SETUP_PLUGIN_TRACKSTAT_BACKUP_DIR
	EN	Backup dir

SETUP_PLUGIN_TRACKSTAT_BACKUP_DIR_DESC
	EN	Directory used for scheduled backups of TrackStat information. This directory must be in a place where the user which is running slimserver has read/write access.

PLUGIN_TRACKSTAT_BACKUP_TIME
	EN	Backup time

SETUP_PLUGIN_TRACKSTAT_BACKUP_TIME
	EN	Backup time

SETUP_PLUGIN_TRACKSTAT_BACKUP_TIME_DESC
	EN	Time each day when a scheduled backup or TrackStat information should take place, if this field is empty no scheduled backups will occur

PLUGIN_TRACKSTAT_BACKUP
	EN	Backup to file

SETUP_PLUGIN_TRACKSTAT_BACKUP
	EN	Backup to file

SETUP_PLUGIN_TRACKSTAT_BACKUP_DESC
	EN	Do backup of all TrackStat information to the file specified as backup file

PLUGIN_TRACKSTAT_MAKING_BACKUP
	EN	Making TrackStat backup to file...

SETUP_PLUGIN_TRACKSTAT_RECENT_NUMBER_OF_DAYS
	EN	Number of days to use for recently played

SETUP_PLUGIN_TRACKSTAT_RECENT_NUMBER_OF_DAYS_DESC
	EN	Number of days to use for recently played in statistics, this option only has effect if history is enabled. Its used when calculating statistics that ignores recently played or only uses recently played tracks.

PLUGIN_TRACKSTAT_RECENT_NUMBER_OF_DAYS
	EN	Number of days to use for recently played in statistics

SETUP_PLUGIN_TRACKSTAT_RECENTADDED_NUMBER_OF_DAYS
	EN	Number of days to use for recently added

SETUP_PLUGIN_TRACKSTAT_RECENTADDED_NUMBER_OF_DAYS_DESC
	EN	Number of days to use for recently added in statistics. Its used when calculating statistics that ignores recently added or only uses recently added tracks.

PLUGIN_TRACKSTAT_RECENTADDED_NUMBER_OF_DAYS
	EN	Number of days to use for recently added in statistics

SETUP_PLUGIN_TRACKSTAT_WEB_LIST_LENGTH
	EN	Number of songs/albums/artists on web

SETUP_PLUGIN_TRACKSTAT_WEB_LIST_LENGTH_DESC
	EN	Number songs/albums/artists that should be shown in the web interface for TrackStat when choosing to view statistic information

PLUGIN_TRACKSTAT_WEB_LIST_LENGTH
	EN	Number of songs/albums/artists on web

SETUP_PLUGIN_TRACKSTAT_PLAYER_LIST_LENGTH
	EN	Number of songs/albums/artists on player

SETUP_PLUGIN_TRACKSTAT_PLAYER_LIST_LENGTH_DESC
	EN	Number songs/albums/artists that should be shown in the player interface for TrackStat when browsing statistic information with remote

PLUGIN_TRACKSTAT_PLAYER_LIST_LENGTH
	EN	Number of songs/albums/artists on player

PLUGIN_TRACKSTAT_PLAYER_LIST_LENGTH_SHORT
	EN	and on player

SETUP_PLUGIN_TRACKSTAT_PLAYLIST_LENGTH
	EN	Number of songs/albums/artists to use in dynamic playlists

SETUP_PLUGIN_TRACKSTAT_PLAYLIST_LENGTH_DESC
	EN	Number songs/albums/artists that should be used when selecting tracks in DynamicPlaylist plugin

PLUGIN_TRACKSTAT_PLAYLIST_LENGTH
	EN	Number of songs/albums/artists to use in dynamic playlists

SETUP_PLUGIN_TRACKSTAT_MIN_ARTIST_TRACKS
	EN	Minimum songs per artist

SETUP_PLUGIN_TRACKSTAT_MIN_ARTIST_TRACKS_DESC
	EN	A minimum number of songs an artist must have to be shown in the artist statistics

PLUGIN_TRACKSTAT_MIN_ARTIST_TRACKS
	EN	Minimum songs per artist

SETUP_PLUGIN_TRACKSTAT_MIN_ALBUM_TRACKS
	EN	Minimum songs per album

SETUP_PLUGIN_TRACKSTAT_MIN_ALBUM_TRACKS_DESC
	EN	A minimum number of songs an album must have to be shown in the album statistics

PLUGIN_TRACKSTAT_MIN_ALBUM_TRACKS
	EN	Minimum songs per album

SETUP_PLUGIN_TRACKSTAT_PLAYLIST_PER_ARTIST_LENGTH
	EN	Number of songs per artist in playlists

SETUP_PLUGIN_TRACKSTAT_PLAYLIST_PER_ARTIST_LENGTH_DESC
	EN	Number songs for each artists used when selecting artist playlists in DynamicPlaylist plugin. This means that selecting \"Top rated artist\" will play this number of tracks for an artist before changing to next artist.

PLUGIN_TRACKSTAT_PLAYLIST_PER_ARTIST_LENGTH
	EN	Number of songs for each artist in playlists

SETUP_PLUGIN_TRACKSTAT_MIN_SONG_LENGTH
	EN	Minimum song length to count

SETUP_PLUGIN_TRACKSTAT_MIN_SONG_LENGTH_DESC
	EN	A minimum number of seconds a track must be played to be considered a play. Note that if set too high it can prevent a track from ever being noted as played - it is effectively a minimum track length. Tracks shorter than this time will never be considered played even if they fullfill the percent and threshold limits.

PLUGIN_TRACKSTAT_MIN_SONG_LENGTH
	EN	Minumum song length to count

SETUP_PLUGIN_TRACKSTAT_SONG_THRESHOLD_LENGTH
	EN	Played length to always count

SETUP_PLUGIN_TRACKSTAT_SONG_THRESHOLD_LENGTH_DESC
	EN	A time played threshold. After this number of seconds playing, the track will be considered played. This is useful for long recordings which are several hours and you want them to be considered as played every time you have played them for at least 30 minutes.

PLUGIN_TRACKSTAT_SONG_THRESHOLD_LENGTH
	EN	Played length to always count

SETUP_PLUGIN_TRACKSTAT_MIN_SONG_PERCENT
	EN	Minumum played percent

SETUP_PLUGIN_TRACKSTAT_MIN_SONG_PERCENT_DESC
	EN	A percentage play threshold. For example, if 50% of a track is played, it will be considered played else it will never be added to the statistics as played.

PLUGIN_TRACKSTAT_MIN_SONG_PERCENT
	EN	Minimum played percent

SETUP_PLUGIN_TRACKSTAT_WEB_REFRESH
	EN	Automatic refresh of web page

SETUP_PLUGIN_TRACKSTAT_WEB_REFRESH_DESC
	EN	Automatic refresh of web page every 60'th second and at each track change

PLUGIN_TRACKSTAT_WEB_REFRESH
	EN	Automatic refresh of web page

SETUP_PLUGIN_TRACKSTAT_WEB_SHOW_MIXERLINKS
	EN	Show MusicIP mixer links

SETUP_PLUGIN_TRACKSTAT_WEB_SHOW_MIXERLINKS_DESC
	EN	Show MusicIP mixer links in TrackStat pages, requires that MusicMagic plugin is enabled and configured to be used in SlimServer

PLUGIN_TRACKSTAT_WEB_SHOW_MIXERLINKS
	EN	Show MusicIP mixer links

SETUP_PLUGIN_TRACKSTAT_WEB_ENABLE_MIXERFUNCTION
	EN	Show TrackStat buttons on web

SETUP_PLUGIN_TRACKSTAT_WEB_ENABLE_MIXERFUNCTION_DESC
	EN	Show TrackStat buttons in browse pages in web interface.<br>Note! Slimserver may have to be restarted for this to take effect

PLUGIN_TRACKSTAT_WEB_ENABLE_MIXERFUNCTION
	EN	Show TrackStat buttons on web

SETUP_PLUGIN_TRACKSTAT_ENABLE_MIXERFUNCTION
	EN	Enable TrackStat play+hold

SETUP_PLUGIN_TRACKSTAT_ENABLE_MIXERFUNCTION_DESC
	EN	Enable TrackStat play+hold action with remote when browsing music on SqueezeBox.<br>Note! Slimserver may have to be restarted for this to take effect

PLUGIN_TRACKSTAT_ENABLE_MIXERFUNCTION
	EN	Enable TrackStat play+hold

PLUGIN_TRACKSTAT_RESTORE
	EN	Restore from file

SETUP_PLUGIN_TRACKSTAT_RESTORE
	EN	Restore from file

SETUP_PLUGIN_TRACKSTAT_RESTORE_DESC
	EN	Restore TrackStat information from the file specified as backup file.<br><b>WARNING!</b><br>This will overwrite any TrackStat information that exist with the information in the file

PLUGIN_TRACKSTAT_RESTORING_BACKUP
	EN	Restoring TrackStat backup from file...

PLUGIN_TRACKSTAT_CLEAR
	EN	Remove all data

SETUP_PLUGIN_TRACKSTAT_CLEAR
	EN	Remove all data

SETUP_PLUGIN_TRACKSTAT_CLEAR_DESC
	EN	This will remove all existing TrackStat data.<br><b>WARNING!</b><br>If you have not made an backup of the information it will be lost forever.

PLUGIN_TRACKSTAT_NO_TRACK
	EN	No statistics found

PLUGIN_TRACKSTAT_NOT_FOUND
	EN	Can't find current track

PLUGIN_TRACKSTAT_CLEARING
	EN	Removing all TrackStat data

PLUGIN_TRACKSTAT_RATING_NO_SONG
	EN	No song playing

PLUGIN_TRACKSTAT_SONGLIST_MENUHEADER
	EN	Choose statistics to view

PLUGIN_TRACKSTAT_PURGING_TRACKS
	EN	Delete unused statistic

PLUGIN_TRACKSTAT_PURGE_TRACKS
	EN	Delete unused statistic

SETUP_PLUGIN_TRACKSTAT_PURGE_TRACKS
	EN	Delete unused statistic after rescan

SETUP_PLUGIN_TRACKSTAT_PURGE_TRACKS_DESC
	EN	This deletes statistic data for all tracks that no longer exists in a database after a rescan, note that if you have changed filename of a track and performed a rescan it till be detected as a completely new track if it does not contain MusicBrainz Id's. Due to this the old file in statistic data will be deleted if you perform this operation. <br><b>WARNING!</b><br>Deleted statistic data will not be possible to get back, so perform a backup of statistic data before you perform this operation.

PLUGIN_TRACKSTAT_REFRESHING_TRACKS
	EN	Refresh statistic data

PLUGIN_TRACKSTAT_REFRESH_TRACKS
	EN	Refresh statistic

SETUP_PLUGIN_TRACKSTAT_REFRESH_TRACKS
	EN	Refresh statistic after rescan

SETUP_PLUGIN_TRACKSTAT_REFRESH_TRACKS_DESC
	EN	Refresh TrackStat information after a complete rescan, this is only neccesary if you have changed some filenames or directory names. As long as you only have added new files you don't need to perform a refresh. The refresh operation will not destroy or remove any data, it will just make sure the TrackStat information is synchronized with the standard slimserver database.<br>In slimserver 6.5 this operation is performed automatically after each slimserver rescan.

PLUGIN_TRACKSTAT_DYNAMICPLAYLIST_LINK
	EN	Play as dynamic playlist

PLUGIN_TRACKSTAT_SELECT_STATISTICS
	EN	Hide/Show

PLUGIN_TRACKSTAT_SELECT_STATISTICS_TITLE
	EN	Select which statistics to view

PLUGIN_TRACKSTAT_SELECT_STATISTICS_ALL
	EN	Select all

PLUGIN_TRACKSTAT_SELECT_STATISTICS_NONE
	EN	Select none

PLUGIN_TRACKSTAT_SHOW_ALL_STATISTICS
	EN	Show all

PLUGIN_TRACKSTAT_GROUP_RATING_QUESTION
	EN	This will change all ratings not already set on this album, is this what you want to do ?

PLUGIN_TRACKSTAT_GROUP_RATING_QUESTION_FORCE
	EN	This will change all ratings on this album old ratings will be lost, is this what you want to do ?

PLUGIN_TRACKSTAT_SONGLIST_TRACK_GROUP
	EN	Songs

PLUGIN_TRACKSTAT_SONGLIST_ALBUM_GROUP
	EN	Albums

PLUGIN_TRACKSTAT_SONGLIST_ARTIST_GROUP
	EN	Artists

PLUGIN_TRACKSTAT_SONGLIST_YEAR_GROUP
	EN	Years

PLUGIN_TRACKSTAT_SONGLIST_GENRE_GROUP
	EN	Genres

PLUGIN_TRACKSTAT_SONGLIST_PLAYLIST_GROUP
	EN	Playlists

PLUGIN_TRACKSTAT_SONGLIST_RECENT_GROUP
	EN	Recently played

PLUGIN_TRACKSTAT_SONGLIST_NOTRECENT_GROUP
	EN	Not recently played

PLUGIN_TRACKSTAT_SONGLIST_RECENTADDED_GROUP
	EN	Recently added

PLUGIN_TRACKSTAT_SONGLIST_NOTRECENTADDED_GROUP
	EN	Not recently added
$pluginStrings";
return $str;
}

1;

__END__
