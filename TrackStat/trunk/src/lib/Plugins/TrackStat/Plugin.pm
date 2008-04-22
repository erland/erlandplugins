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

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;
use Slim::Player::Playlist;
use Slim::Player::Source;
use Slim::Player::Client;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);

use Plugins::TrackStat::Template::Reader;
use Time::HiRes;
use Class::Struct;
use POSIX qw(strftime ceil floor);
use File::Spec::Functions qw(:ALL);
use DBI qw(:sql_types);
use File::Slurp;
use XML::Simple;

use Scalar::Util qw(blessed);

use FindBin qw($Bin);
use Time::Stopwatch;
use File::Basename qw(dirname);
use Plugins::TrackStat::Backup::File;
use Plugins::TrackStat::Storage;
use Plugins::TrackStat::iPeng::Reader;

use Plugins::TrackStat::Settings::Basic;
use Plugins::TrackStat::Settings::Backup;
use Plugins::TrackStat::Settings::EnabledStatistic;
use Plugins::TrackStat::Settings::Favorites;
use Plugins::TrackStat::Settings::Interface;
use Plugins::TrackStat::Settings::Rating;

use Plugins::TrackStat::Statistics::Base;
use Plugins::TrackStat::Statistics::All;
use Plugins::TrackStat::Statistics::FirstPlayed;
use Plugins::TrackStat::Statistics::LastAdded;
use Plugins::TrackStat::Statistics::LastPlayed;
use Plugins::TrackStat::Statistics::LeastPlayed;
use Plugins::TrackStat::Statistics::LeastPlayedRecentAdded;
use Plugins::TrackStat::Statistics::MostPlayed;
use Plugins::TrackStat::Statistics::MostPlayedRecentAdded;
use Plugins::TrackStat::Statistics::MostPlayedRecent;
use Plugins::TrackStat::Statistics::NotCompletelyRated;
use Plugins::TrackStat::Statistics::NotCompletelyRatedRecentAdded;
use Plugins::TrackStat::Statistics::NotCompletelyRatedRecent;
use Plugins::TrackStat::Statistics::NotPlayed;
use Plugins::TrackStat::Statistics::NotRated;
use Plugins::TrackStat::Statistics::NotRatedRecentAdded;
use Plugins::TrackStat::Statistics::NotRatedRecent;
use Plugins::TrackStat::Statistics::PartlyPlayed;
use Plugins::TrackStat::Statistics::SpecificRating;
use Plugins::TrackStat::Statistics::TopRated;
use Plugins::TrackStat::Statistics::TopRatedRecentAdded;
use Plugins::TrackStat::Statistics::TopRatedRecent;

my $prefs = preferences('plugin.trackstat');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.trackstat',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_TRACKSTAT',
});


$prefs->migrate(1, sub {
	$prefs->set('backup_file', Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_backup_file'));
	$prefs->set('backup_dir',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_backup_dir'));
	$prefs->set('backup_time',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_backup_time'));
	$prefs->set('dynamicplaylist',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_dynamicplaylist'));
	$prefs->set('dynamicplaylist_norepeat',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_dynamicplaylist_norepeat'));
	$prefs->set('recent_number_of_days',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_recent_number_of_days'));
	$prefs->set('recentadded_number_of_days',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_recentadded_number_of_days'));
	$prefs->set('web_flatlist',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_web_flatlist'));
	$prefs->set('player_flatlist',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_player_flatlist'));
	$prefs->set('deep_hierarchy',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_deep_hierarchy'));
	$prefs->set('web_list_length',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_web_list_length'));
	$prefs->set('player_list_length',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_player_list_length'));
	$prefs->set('playlist_length',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_playlist_length'));
	$prefs->set('playlist_per_artist_length',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_playlist_per_artist_length'));
	$prefs->set('web_refresh',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_web_refresh'));
	$prefs->set('web_show_mixerlinks',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_web_show_mixerlinks'));
	$prefs->set('web_enable_mixerfunction',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_web_enable_mixerfunction'));
	$prefs->set('enable_mixerfunction',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_enable_mixerfunction'));
	$prefs->set('force_grouprating',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_force_grouprating'));
	$prefs->set('rating_10scale',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_rating_10scale'));
	$prefs->set('ratingchar',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_ratingchar'));
	$prefs->set('rating_auto',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_rating_auto'));
	$prefs->set('rating_auto_nonrated',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_rating_auto_nonrated'));
	$prefs->set('rating_auto_nonrated_value',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_rating_auto_nonrated_value'));
	$prefs->set('rating_auto_smart',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_rating_auto_smart'));
	$prefs->set('rating_decrease_percent',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_rating_decrease_percent'));
	$prefs->set('rating_increase_percent',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_rating_increase_percent'));
	$prefs->set('min_artist_tracks',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_min_artist_tracks'));
	$prefs->set('min_album_tracks',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_min_album_tracks'));
	$prefs->set('min_song_length',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_min_song_length'));
	$prefs->set('song_threshold_length',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_song_threshold_length'));
	$prefs->set('min_song_percent',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_min_song_percent'));
	$prefs->set('refresh_startup',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_refresh_startup'));
	$prefs->set('refresh_rescan',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_refresh_rescan'));
	$prefs->set('history_enabled',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_history_enabled'));
	$prefs->set('disablenumberscroll',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_disablenumberscroll'));
	$prefs->set('long_urls',  Slim::Utils::Prefs::OldPrefs->get('plugin_trackstat_long_urls'));
	1;
});
$prefs->setValidate({'validator' => \&isWritableFile }, 'backup_file'  );
$prefs->setValidate('dir', 'backup_dir'  );
$prefs->setValidate({ 'validator' => \&isTimeOrEmpty }, 'backup_time'  );
$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    1,                 }, 'recent_number_of_days'  );
$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    1,                 }, 'recent_number_of_days'  );
$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    1,                 }, 'web_list_length'  );
$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    1,                 }, 'player_list_length'  );
$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    1,                 }, 'playlist_length'  );
$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    1,                 }, 'playlist_per_artist_length'  );
$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    0, 'high' => 100 }, 'rating_auto_nonrated_value'  );
$prefs->setValidate({ 'validator' => 'numlimit', 'low' =>    0, 'high' => 100 }, 'rating_decrease_percent'  );
$prefs->setValidate({ 'validator' => 'numlimit', 'low' =>    0, 'high' => 100 }, 'rating_increase_percent'  );
$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    0,                 }, 'min_artist_tracks'  );
$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    0,                 }, 'min_album_tracks'  );
$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    0,                 }, 'min_song_length'  );
$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    0,                 }, 'song_threshold_length'  );
$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    0,  'high' => 100 }, 'min_song_percent'  );

my $PLUGINVERSION = undef;

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
	'6.hold' => 'saveRating_6',
	'7.hold' => 'saveRating_7',
	'8.hold' => 'saveRating_8',
	'9.hold' => 'saveRating_9',
	'0.single' => 'numberScroll_0',
	'1.single' => 'numberScroll_1',
	'2.single' => 'numberScroll_2',
	'3.single' => 'numberScroll_3',
	'4.single' => 'numberScroll_4',
	'5.single' => 'numberScroll_5',
	'6.single' => 'numberScroll_6',
	'7.single' => 'numberScroll_7',
	'8.single' => 'numberScroll_8',
	'9.single' => 'numberScroll_9',
	'0' => 'dead',
	'1' => 'dead',
	'2' => 'dead',
	'3' => 'dead',
	'4' => 'dead',
	'5' => 'dead',
	'6' => 'dead',
	'7' => 'dead',
	'8' => 'dead',
	'9' => 'dead'
);

my %choiceMapping = (
	'0.hold' => 'saveRating_0',
	'1.hold' => 'saveRating_1',
	'2.hold' => 'saveRating_2',
	'3.hold' => 'saveRating_3',
	'4.hold' => 'saveRating_4',
	'5.hold' => 'saveRating_5',
	'6.hold' => 'saveRating_6',
	'7.hold' => 'saveRating_7',
	'8.hold' => 'saveRating_8',
	'9.hold' => 'saveRating_9',
	'0.single' => 'numberScroll_0',
	'1.single' => 'numberScroll_1',
	'2.single' => 'numberScroll_2',
	'3.single' => 'numberScroll_3',
	'4.single' => 'numberScroll_4',
	'5.single' => 'numberScroll_5',
	'6.single' => 'numberScroll_6',
	'7.single' => 'numberScroll_7',
	'8.single' => 'numberScroll_8',
	'9.single' => 'numberScroll_9',
	'0' => 'dead',
	'1' => 'dead',
	'2' => 'dead',
	'3' => 'dead',
	'4' => 'dead',
	'5' => 'dead',
	'6' => 'dead',
	'7' => 'dead',
	'8' => 'dead',
	'9' => 'dead',
	'arrow_left' => 'exit_left',
	'arrow_right' => 'exit_right',
	'play' => 'play',
	'add' => 'add',
	'search' => 'passback',
	'stop' => 'passback',
	'pause' => 'passback'
);

sub defaultMap { 
	if($prefs->get("disablenumberscroll")) { 
		for my $key (keys %mapping) {
			if($key =~ /^\d\.single$/) {
				$mapping{$key}='dead';
			}
		}
	}
	return \%mapping; 
}

sub getDisplayName()
{
	return $::VERSION =~ m/6\./ ? 'PLUGIN_TRACKSTAT' : string('PLUGIN_TRACKSTAT'); 
}

our %menuSelection;

sub setMode() 
{
	my $class = shift;
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my @listRef = ();
	my $statistics = getStatisticPlugins();

	my $statistictype = $client->modeParam('statistictype');
	my $showFlat = $prefs->get('player_flatlist');
	if($showFlat || defined($client->modeParam('flatlist'))) {
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
						$contextParams{$statistictype} = $client->modeParam($statistictype);
						my $valid = eval {&{$item->{'contextfunction'}}(\%contextParams)};
						if( $@ ) {
							$log->warn("Error calling contextfunction: $@\n");
						}
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
							$contextParams{$statistictype} = $client->modeParam($statistictype);
							my $valid = eval {&{$item->{'contextfunction'}}(\%contextParams)};
							if( $@ ) {
								$log->warn("Error calling contextfunction: $@\n");
							}
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
		my $statisticgroup = $client->modeParam('selectedgroup');
		if($statisticgroup) {
			for my $item (@listRef) {
				if(!defined($item->{'item'}) && defined($item->{'childs'}) && $item->{'name'} eq $statisticgroup) {
					Slim::Buttons::Common::pushModeLeft($client,'INPUT.Choice',getSetModeDataForSubItems($client,$item,$item->{'childs'}));
					return;
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
		modeName   => 'Plugins::TrackStat::Plugin',
		onPlay     => sub {
			my ($client, $item) = @_;
			if(defined($item->{'item'})) {
				my %paramsData = (
					'player' => $client->id,
					'trackstatcmd' => 'play'
				);
				if(defined($client->modeParam('statistictype'))) {
					$paramsData{'statistictype'} = $client->modeParam('statistictype');
					$paramsData{$client->modeParam('statistictype')} = $client->modeParam($client->modeParam('statistictype'));
				}
				my $function = $item->{'item'}->{'webfunction'};
			    my $listLength = $prefs->get("player_list_length");
			    if(!defined $listLength || $listLength==0) {
			    	$listLength = 20;
			    }
				$log->debug("Calling webfunction for ".$item->{'item'}->{'id'}."\n");
				eval {
					&{$function}(\%paramsData,$listLength);
				};
				if( $@ ) {
					$log->warn("Error calling webfunction: $@\n");
				}
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
				if(defined($client->modeParam('statistictype'))) {
					$paramsData{'statistictype'} = $client->modeParam('statistictype');
					$paramsData{$client->modeParam('statistictype')} = $client->modeParam($client->modeParam('statistictype'));
				}
				my $function = $item->{'item'}->{'webfunction'};
			    my $listLength = $prefs->get("player_list_length");
			    if(!defined $listLength || $listLength==0) {
			    	$listLength = 20;
			    }
				$log->debug("Calling webfunction for ".$item->{'item'}->{'id'}."\n");
				eval {
					&{$function}(\%paramsData,$listLength);
				};
				if( $@ ) {
					$log->warn("Error calling webfunction: $@\n");
				}
				handlePlayAdd($client,\%paramsData);
			}
		},
		onRight    => sub {
			my ($client, $item) = @_;
			if(defined($item->{'childs'})) {
				Slim::Buttons::Common::pushModeLeft($client,'INPUT.Choice',getSetModeDataForSubItems($client,$item,$item->{'childs'}));
			}else {
				my %paramsData = ();
				if(defined($client->modeParam('statistictype'))) {
					$paramsData{'statistictype'} = $client->modeParam('statistictype');
					$paramsData{$client->modeParam('statistictype')} = $client->modeParam($client->modeParam('statistictype'));
				}
				my $params = getSetModeDataForStatistics($client,$item->{'item'},\%paramsData);
				if(defined($params)) {
					Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.TrackStat.Choice',$params);
				}else {
					$client->showBriefly({
						'line' => [$item->{'name'},$client->string( 'PLUGIN_TRACKSTAT_NO_TRACK')]},
						1);

				}
			}
		},
	);
	if(defined($statistictype)) {
		$params{'statistictype'} = $statistictype;
		$params{$statistictype} = $client->modeParam($statistictype);
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
				if( $@ ) {
					$log->warn("Error calling namefunction: $@\n");
				}
			}else {
				$name = $item->{'item'}->{'name'};
			}
		}else {
			$name = $item->{'name'};
		}
	}
	return $name;
}

sub getDetailsDisplayText {
	my ($client, $item) = @_;

	my $trackHandle = Plugins::TrackStat::Storage::findTrack( $item->{'itemobj'}->url,undef,$item->{'itemobj'});
	my $displayStr;
	my $headerStr;
	if($trackHandle) {
		if($trackHandle->rating) {
			my $rating = $trackHandle->rating;
			if($rating) {
				if($prefs->get("rating_10scale")) {
					$rating = floor(($rating+5) / 10);
				}else {
					$rating = floor(($rating+10) / 20);
				}
				$displayStr = $client->string( 'PLUGIN_TRACKSTAT_RATING').($RATING_CHARACTER x $rating);
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
				$headerStr = $client->string( 'PLUGIN_TRACKSTAT_LAST_PLAYED').' '.Slim::Utils::DateTime::shortDateF($lastPlayed).' '.Slim::Utils::DateTime::timeF($lastPlayed);
			}
		}
	}
	if(!$displayStr) {
		$displayStr = $client->string( 'PLUGIN_TRACKSTAT_NO_TRACK');
	}
	if(!$headerStr) {
		$headerStr = $client->string( 'PLUGIN_TRACKSTAT');
	}

	return $displayStr;
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
		return [$client->symbols('rightarrow'),$client->symbols('notesymbol')];
	}else {
		return [undef, $client->symbols('rightarrow')];
	}
}

sub getDetailsOverlay {
	my ($client, $item) = @_;
	if(defined($item->{'itemobj'})) {
		return [undef, $client->symbols('rightarrow')];
	}else {
		return [undef, undef];
	}
}

sub getDataOverlay {
	my ($client, $item) = @_;
	if(defined($item->{'currentstatisticitems'})) {
		return [$client->symbols('rightarrow'), $client->symbols('notesymbol')];
	}else {
		return [undef, $client->symbols('notesymbol')];
	}
}

sub getSetModeDataForSubItems {
	my $client = shift;
	my $currentItem = shift;
	my $items = shift;

	my @listRef = ();
	my $statistictype = $client->modeParam('statistictype');
	foreach my $menuItemKey (sort keys %$items) {
		if($items->{$menuItemKey}->{'trackstat_statistic_enabled'}) {
			if(!defined($statistictype)) {
				push @listRef, $items->{$menuItemKey};
			}else {
				if(defined($items->{$menuItemKey}->{'item'})) {
					my $item = $items->{$menuItemKey}->{'item'};
					if(defined($item->{'contextfunction'})) {
						my %contextParams = ();
						$contextParams{$statistictype} = $client->modeParam($statistictype);
						my $valid = eval {&{$item->{'contextfunction'}}(\%contextParams)};
						if( $@ ) {
							$log->warn("Error calling contextfunction: $@\n");
						}
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
		modeName   => 'Plugins::TrackStat::Plugin'.$currentItem->{'value'},
		onPlay     => sub {
			my ($client, $item) = @_;
			if(defined($item->{'item'})) {
				my %paramsData = (
					'player' => $client->id,
					'trackstatcmd' => 'play'
				);
				my $function = $item->{'item'}->{'webfunction'};
			    my $listLength = $prefs->get("player_list_length");
			    if(!defined $listLength || $listLength==0) {
			    	$listLength = 20;
			    }
				$log->debug("Calling webfunction for ".$item->{'item'}->{'id'}."\n");
				eval {
					&{$function}(\%paramsData,$listLength);
				};
				if( $@ ) {
					$log->warn("Error calling webfunction: $@\n");
				}
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
			    my $listLength = $prefs->get("player_list_length");
			    if(!defined $listLength || $listLength==0) {
			    	$listLength = 20;
			    }
				$log->debug("Calling webfunction for ".$item->{'item'}->{'id'}."\n");
				eval {
					&{$function}(\%paramsData,$listLength);
				};
				if( $@ ) {
					$log->warn("Error calling webfunction: $@\n");
				}
				handlePlayAdd($client,\%paramsData);
			}
		},
		onRight    => sub {
			my ($client, $item) = @_;
			if(defined($item->{'childs'})) {
				Slim::Buttons::Common::pushModeLeft($client,'INPUT.Choice',getSetModeDataForSubItems($client,$item,$item->{'childs'}));
			}else {
				my %paramsData = ();
				if(defined($client->modeParam('statistictype'))) {
					$paramsData{'statistictype'} = $client->modeParam('statistictype');
					$paramsData{$client->modeParam('statistictype')} = $client->modeParam($client->modeParam('statistictype'));
				}
				my $params = getSetModeDataForStatistics($client,$item->{'item'},\%paramsData);
				if(defined($params)) {
					Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.TrackStat.Choice',$params);
				}else {
					$client->showBriefly({
						'line' => [$item->{'name'},$client->string( 'PLUGIN_TRACKSTAT_NO_TRACK')]},
						1);
				}
			}
		},
	);
	if(defined($statistictype)) {
		$params{'statistictype'} = $statistictype;
		$params{$statistictype} = $client->modeParam($statistictype);
	}
	return \%params;
}

sub getDetailItems {
	my $client = shift;
	my $currentItem = shift;
	my $header = shift;

	my @listRef = ();
	push @listRef, $currentItem;

	my %params = (
		header     => $header,
		listRef    => \@listRef,
		name       => \&getDetailsDisplayText,
		overlayRef => \&getDetailsOverlay,
		modeName   => 'Plugins::TrackStat::Plugin::Details',
		parentMode => Slim::Buttons::Common::param($client,'parentMode'),
		onRight    => sub {
			my ($client, $item) = @_;
			my $track = $item->{'itemobj'};
			if(defined($track)) {
				Slim::Buttons::Common::pushModeLeft($client,'trackinfo',{'track' => $track});
			}else {
				$client->bumpRight();
			}
		}
	);
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
	my $listLength = $prefs->get("player_list_length");
	if(!defined $listLength || $listLength==0) {
		$listLength = 20;
	}
	$log->debug("Calling webfunction for ".$item->{'id'}."\n");
	eval {
		&{$function}($paramsData,$listLength);
	};
	if( $@ ) {
		$log->warn("Error calling webfunction: $@\n");
	}
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
		if( $@ ) {
			$log->warn("Error calling namefunction: $@\n");
		}
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
			
			# indicate request source
			$request->source('PLUGIN_TRACKSTAT');
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
			
			# indicate request source
			$request->source('PLUGIN_TRACKSTAT');
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
					$client->showBriefly({
						'line' => [$item->{'name'},$client->string( 'PLUGIN_TRACKSTAT_NO_TRACK')]},
						1);
				}
			}else {
				if($item->{'listtype'} eq 'track') {
					my $trackHandle = Plugins::TrackStat::Storage::findTrack( $item->{'itemobj'}->url,undef,$item->{'itemobj'});
					my $headerStr;
					if($trackHandle) {
						if($trackHandle->lastPlayed) {
							my $lastPlayed = $trackHandle->lastPlayed;
							$headerStr = $client->string( 'PLUGIN_TRACKSTAT_LAST_PLAYED').' '.Slim::Utils::DateTime::shortDateF($lastPlayed).' '.Slim::Utils::DateTime::timeF($lastPlayed);
						}
					}
					if(!$headerStr) {
						$headerStr = $client->string( 'PLUGIN_TRACKSTAT');
					}

					Slim::Buttons::Common::pushModeLeft($client,'INPUT.Choice',getDetailItems($client,$item,$headerStr));
				}else {
					$client->bumpRight();
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
	return 1;
}

my %functions = ();

sub saveRatingsForCurrentlyPlaying {
	my $client = shift;
	my $button = shift;
	my $digit = shift;

	if($prefs->get("rating_10scale")) {
		return unless $digit>='0' && $digit<='9';
		if($digit==0) {
			$digit=10;
		}
	}else{
		return unless $digit>='0' && $digit<='5';
	}

	my $playStatus = getPlayerStatusForClient($client);
	# see if the string is already in the cache
	my $songKey;
	my $listIndex = $client->modeParam('listIndex');
	my $song = Slim::Player::Playlist::song($client,$listIndex);
	$song = $song->url;
	$songKey = $song;
	if (Slim::Music::Info::isRemoteURL($song)) {
		$songKey = Slim::Music::Info::getCurrentTitle($client, $song);
	}
	if($playStatus->currentTrackOriginalFilename() eq $songKey) {
		$playStatus->currentSongRating($digit);
	}
	$log->debug("saveRating: $client, $songKey, $digit\n");
	$client->showBriefly({
		'line' => [$client->string( 'PLUGIN_TRACKSTAT'),$client->string( 'PLUGIN_TRACKSTAT_RATING').($RATING_CHARACTER x $digit)]},
		3);
	my $rating = $digit*20;
	if($prefs->get("rating_10scale")) {
		$rating = $digit*10;
	}
	rateSong($client,$songKey,$rating);
}
sub saveRatingsFromChoice {
		my $client = shift;
		my $button = shift;
		my $digit = shift;

	if($prefs->get("rating_10scale")) {
		return unless $digit>='0' && $digit<='9';
		if($digit==0) {
			$digit=10;
		}
	}else{
		return unless $digit>='0' && $digit<='5';
	}

	my $listRef = Slim::Buttons::Common::param($client,'listRef');
        my $listIndex = Slim::Buttons::Common::param($client,'listIndex');
        my $item = $listRef->[$listIndex];
        if($item->{'listtype'} eq 'track') {
        	$log->debug("saveRating: $client, ".$item->{'itemobj'}->url.", $digit\n");
		my $rating = $digit*20;
		if($prefs->get("rating_10scale")) {
			$rating = $digit*10;
		}
		rateSong($client,$item->{'itemobj'}->url,$rating);
        	my $title = Slim::Music::Info::standardTitle($client,$item->{'itemobj'});
			$client->showBriefly({
				'line' => [$title,$client->string( 'PLUGIN_TRACKSTAT_RATING').($RATING_CHARACTER x $digit)]},
				1);
        	
		}
}	
sub getTrackInfo {
		$log->debug("Entering getTrackInfo\n");
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
					$log->warn("Error retrieving track: ".$playStatus->currentTrackOriginalFilename()."\n");
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
							$playedDate = Slim::Utils::DateTime::shortDateF($trackHandle->lastPlayed).' '.Slim::Utils::DateTime::timeF($trackHandle->lastPlayed);
						}elsif(getLastPlayed($track)) {
							$playedDate = Slim::Utils::DateTime::shortDateF(getLastPlayed($track)).' '.Slim::Utils::DateTime::timeF(getLastPlayed($track));
						}
						if($trackHandle->rating) {
							$rating = $trackHandle->rating;
							if($rating) {
								if($prefs->get("rating_10scale")) {
									$rating = floor(($rating+5) / 10);
								}else {
									$rating = floor(($rating+10) / 20);
								}
							}
						}
				}else {
					if($track) {
						$playedCount = getPlayCount($track);
						if(getLastPlayed($track)) {
							$playedDate = Slim::Utils::DateTime::shortDateF(getLastPlayed($track)).' '.Slim::Utils::DateTime::timeF(getLastPlayed($track));
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
			$log->debug("Exiting getTrackInfo\n");
			return undef;
		}
		$log->debug("Exiting getTrackInfo\n");
		return $playStatus;
}

sub getFunctions() 
{
	return \%functions;
}

sub webPages {
	my %pages = (
		"TrackStat/index\.htm" => \&handleWebIndex,
		"TrackStat/songinfo\.htm" => \&handleWebSongInfo,
	);
	
	my $statistics = getStatisticPlugins();
	for my $item (keys %$statistics) {
		my $id = $statistics->{$item}->{'id'};
		$id = "TrackStat/".$id."\.htm";
		#$log->debug("Adding page: $id\n");
		$pages{$id} = \&handleWebStatistics;
	}

	for my $page (keys %pages) {
		Slim::Web::HTTP::addPageFunction($page, $pages{$page});
	}

	Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_TRACKSTAT' => 'plugins/TrackStat/index.htm' });
	Slim::Web::Pages->addPageLinks("browseiPeng", { 'PLUGIN_TRACKSTAT' => 'plugins/TrackStat/index.htm' });
	Slim::Web::Pages->addPageLinks("icons", {'PLUGIN_TRACKSTAT' => 'plugins/TrackStat/html/images/trackstat.png'});
}

sub baseWebPage {
	my ($client, $params) = @_;
	
	$log->debug("Entering baseWebPage\n");
	if($params->{trackstatcmd} and $params->{trackstatcmd} eq 'listlength') {
		$prefs->set("web_list_length",$params->{listlength});
		$prefs->set("player_list_length",$params->{playerlistlength});
	}elsif($params->{trackstatcmd} and $params->{trackstatcmd} eq 'playlistlength') {
		$prefs->set("playlist_length",$params->{playlistlength});
	}
	my $maxRating = 5;
	if($prefs->get("rating_10scale")) {
		$maxRating = 10;
	}
	$params->{'pluginTrackStatMaxRating'} = $maxRating;
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
				if ($params->{trackstatrating} eq 'up' and $playStatus->currentSongRating() < $maxRating) {
					$playStatus->currentSongRating($playStatus->currentSongRating() + 1);
				} elsif ($params->{trackstatrating} eq 'down' and $playStatus->currentSongRating() > 0) {
					$playStatus->currentSongRating($playStatus->currentSongRating() - 1);
				} elsif ($params->{trackstatrating} >= 0 or $params->{trackstatrating} <= $maxRating) {
					$playStatus->currentSongRating($params->{trackstatrating});
				}
				
				my $rating = $playStatus->currentSongRating()*20;
				if($prefs->get("rating_10scale")) {
					$rating = $playStatus->currentSongRating()*10;
				}
				rateSong($client,$songKey,$rating);
			}elsif($params->{trackstattrackid}) {
				if ($params->{trackstatrating} >= 0 or $params->{trackstatrating} <= $maxRating) {
					my $rating = $params->{trackstatrating}*20;
					if($prefs->get("rating_10scale")) {
						$rating = $params->{trackstatrating}*10;
					}
					rateSong($client,$songKey,$rating);
				}
			}
		}elsif($params->{trackstatcmd} and $params->{trackstatcmd} eq 'albumrating') {
			my $album = $params->{album};
			if ($album) {
				if ($params->{trackstatrating} >= 0 or $params->{trackstatrating} <= $maxRating) {
					my $unratedTracks;
					if($params->{trackstatrating}==0 || $prefs->get("force_grouprating")) {
						$unratedTracks = Plugins::TrackStat::Storage::getTracksOnAlbum($album);
					}else {
						$unratedTracks = Plugins::TrackStat::Storage::getUnratedTracksOnAlbum($album);
					}
					foreach my $url (@$unratedTracks) {
						my $rating = $params->{trackstatrating}*20;
						if($prefs->get("rating_10scale")) {
							$rating = $params->{trackstatrating}*10;
						}
						rateSong($client,$url,$rating);
					}
				}
			}
		}
	}
	if(defined($playStatus)) {
		$params->{playing} = $playStatus->trackAlreadyLoaded();
		if($prefs->get("web_refresh")) {
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
	$params->{'pluginTrackStatListLength'} = $prefs->get("web_list_length");
	$params->{'pluginTrackStatPlayerListLength'} = $prefs->get("player_list_length");
	$params->{'pluginTrackStatPlayListLength'} = $prefs->get("playlist_length");
	$params->{'pluginTrackStatShowMixerLinks'} = $prefs->get("web_show_mixerlinks");
	if($prefs->get("web_refresh")) {
		$params->{refresh} = 60 if (!$params->{refresh} || $params->{refresh} > 60);
	}
	if ($::VERSION ge '7.0') {
		$params->{'pluginTrackStatSlimserver70'} = 1;
	}
	$params->{'pluginTrackStatVersion'} = $PLUGINVERSION;

	$log->debug("Exiting baseWebPage\n");
}
	
sub getStatisticContext {
	my $client = shift;
	my $params = shift;
	my $currentItems = shift;
	my $level = shift;
	my @result = ();
	$log->debug("Get statistic context for level=$level\n");
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
	
	if($prefs->get('web_flatlist') || $params->{'flatlist'}) {
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
	
	if($prefs->get('web_flatlist') || $params->{'flatlist'}) {
		foreach my $itemKey (keys %statisticPlugins) {
			my $item = $statisticPlugins{$itemKey};
			if(defined($item->{'contextfunction'}) && $item->{'trackstat_statistic_enabled'}) {
				my $name;
				if(defined($item->{'namefunction'})) {
					$name = eval { &{$item->{'namefunction'}}() };
					if( $@ ) {
						$log->warn("Error calling namefunction: $@\n");
					}
				}else {
					$name = $item->{'name'};
				}
				my %listItem = (
					'name' => $name,
					'item' => $item
				);
				push @result, \%listItem;
				my $valid = eval {&{$item->{'contextfunction'}}($params)};
				if( $@ ) {
					$log->warn("Error calling contextfunction: $@\n");
				}
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
							if( $@ ) {
								$log->warn("Error calling namefunction: $@\n");
							}
						}else {
							$name = $item->{'name'};
						}
						my %listItem = (
							'name' => $name,
							'item' => $item
						);
						push @result, \%listItem;
						my $valid = eval {&{$item->{'contextfunction'}}($params)};
						if( $@ ) {
							$log->warn("Error calling contextfunction: $@\n");
						}
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
			# indicate request source
			$request->source('PLUGIN_TRACKSTAT');
			return;
		}elsif($params->{trackstatcmd} and $params->{trackstatcmd} eq 'adddynamic') {
			my $request = $client->execute(['dynamicplaylist', 'playlist', 'add', $params->{'dynamicplaylist'}]);
			# indicate request source
			$request->source('PLUGIN_TRACKSTAT');
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
					$log->debug("Loading track = ".$track->title."\n");
					$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('track'),$track->id)]);
				}else {
					$log->debug("Adding track = ".$track->title."\n");
					$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('track'),$track->id)]);
				}
			}elsif($item->{'listtype'} eq 'album') {
				my $album = $item->{'itemobj'}{'album'};
				if($first==1) {
					$log->debug("Loading album = ".$album->title."\n");
					$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('album'),$album->id)]);
				}else {
					$log->debug("Adding album = ".$album->title."\n");
					$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('album'),$album->id)]);
				}
			}elsif($item->{'listtype'} eq 'artist') {
				my $artist = $item->{'itemobj'}{'artist'};
				if($first==1) {
					$log->debug("Loading artist = ".$artist->name."\n");
					$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('artist'),$artist->id)]);
				}else {
					$log->debug("Adding artist = ".$artist->name."\n");
					$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('artist'),$artist->id)]);
				}
			}elsif($item->{'listtype'} eq 'genre') {
				my $genre = $item->{'itemobj'}{'genre'};
				if($first==1) {
					$log->debug("Loading genre = ".$genre->name."\n");
					$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('genre'),$genre->id)]);
				}else {
					$log->debug("Adding genre = ".$genre->name."\n");
					$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('genre'),$genre->id)]);
				}
			}elsif($item->{'listtype'} eq 'year') {
				my $year = $item->{'itemobj'}{'year'};
				if($first==1) {
					$log->debug("Loading year = ".$year."\n");
					$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('year'),$year)]);
				}else {
					$log->debug("Adding year = ".$year."\n");
					$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('year'),$year)]);
				}
			}elsif($item->{'listtype'} eq 'playlist') {
				my $playlist = $item->{'itemobj'}{'playlist'};
				if($first==1) {
					$log->debug("Loading playlist = ".$playlist->title."\n");
					$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('playlist'),$playlist->id)]);
				}else {
					$log->debug("Adding playlist = ".$playlist->title."\n");
					$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('playlist'),$playlist->id)]);
				}
			}
			# indicate request source
			$request->source('PLUGIN_TRACKSTAT');
			$first = 0;
		}
	}
}

sub handleWebIndex {
	my ($client, $params) = @_;

	baseWebPage($client, $params);

	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub handleWebSongInfo {
	my ($client, $params) = @_;

	my $track = undef;
	my $nowPlayingTrack = undef;
	if(defined($params->{'item'})) {
		$track = Plugins::TrackStat::Storage::objectForId('track',$params->{'item'});
	}
	my $playStatus = undef;
	# without a player, don't do anything
	if ($client = Slim::Player::Client::getClient($params->{player})) {
		$playStatus = getTrackInfo($client);
	}
	if(defined($playStatus)) {
		$nowPlayingTrack = Slim::Player::Playlist::song($client);
	}
	if(!defined($track)) {
		$track=$nowPlayingTrack
	}
	if(defined($nowPlayingTrack)) {
		my %form = ();
		$nowPlayingTrack->displayAsHTML(\%form);
		$params->{'nowplayingtrackitem'} = \%form;
		$params->{'nowplayingtrack'} = $nowPlayingTrack;
		my $trackHandle = Plugins::TrackStat::Storage::findTrack( $nowPlayingTrack->url,undef,$nowPlayingTrack);
		if(defined($trackHandle)) {
			my $rating = $trackHandle->rating || 0;
			if($prefs->get("rating_10scale")) {
				$rating = floor(($rating+5) / 10);
			}else {
				$rating = floor(($rating+10) / 20);
			}
			$params->{nowplayingrating} = $rating;
			$params->{nowplayingplayCount} = $trackHandle->playCount;
			$params->{nowplayinglastPlayed} = Slim::Utils::DateTime::shortDateF($trackHandle->lastPlayed).' '.Slim::Utils::DateTime::timeF($trackHandle->lastPlayed);
		}
		if(defined($nowPlayingTrack->artist)) {
			$params->{'nowplayingartist'} = $nowPlayingTrack->artist;
		}
		if(defined($nowPlayingTrack->album)) {
			$params->{'nowplayingalbum'} = $nowPlayingTrack->album;
		}
	}
	if(defined($track)) {
		my %form = ();
		$track->displayAsHTML(\%form);
		$params->{'trackitem'} = \%form;
		$params->{'track'} = $track;
		my $trackHandle = Plugins::TrackStat::Storage::findTrack( $track->url,undef,$track);
		if(defined($trackHandle)) {
			my $rating = $trackHandle->rating || 0;
			if($prefs->get("rating_10scale")) {
				$rating = floor(($rating+5) / 10);
			}else {
				$rating = floor(($rating+10) / 20);
			}
			$params->{rating} = $rating;
			$params->{playCount} = $trackHandle->playCount;
			$params->{lastPlayed} = Slim::Utils::DateTime::shortDateF($trackHandle->lastPlayed).' '.Slim::Utils::DateTime::timeF($trackHandle->lastPlayed);
		}
		if(defined($track->artist)) {
			$params->{'artist'} = $track->artist;
			my $artiststatistics =  Plugins::TrackStat::Storage::getGroupStatistic('artist',$track->artist->id);
			my $rating;
			my $ratingnumber;
			if($prefs->get("rating_10scale")) {
				$ratingnumber = ($artiststatistics->{'rating'}) / 10;
				$rating = floor(($artiststatistics->{'rating'}+5) / 10);
			}else {
				$ratingnumber = sprintf("%.2f",($artiststatistics->{'rating'}) / 20);
				$rating = floor(($artiststatistics->{'rating'}+10) / 20);
			}
			$params->{'artistrating'} = $rating;
			$params->{'artistratingnumber'} = $ratingnumber;
		}
		if(defined($track->album)) {
			my %form = ();
			$track->album->displayAsHTML(\%form);
			$params->{'item'} = \%form;
			$params->{'album'} = $track->album;
			my $albumstatistics =  Plugins::TrackStat::Storage::getGroupStatistic('album',$track->album->id);
			my $rating;
			my $ratingnumber;
			if($prefs->get("rating_10scale")) {
				$ratingnumber = sprintf("%.2f",($albumstatistics->{'rating'}) / 10);
				$rating = floor(($albumstatistics->{'rating'}+5) / 10);
			}else {
				$ratingnumber = sprintf("%.2f",($albumstatistics->{'rating'}) / 20);
				$rating = floor(($albumstatistics->{'rating'}+10) / 20);
			}
			$params->{'albumrating'} = $rating;
			$params->{'albumratingnumber'} = $ratingnumber;
		}

	}
	my $maxRating = 5;
	if($prefs->get("rating_10scale")) {
		$maxRating = 10;
	}
	$params->{'pluginTrackStatMaxRating'} = $maxRating;
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/songinfo.html', $params);
}

sub getStatisticPlugins {
	if( !defined $statisticsInitialized) {
		initStatisticPlugins();
	}
	return \%statisticPlugins;
}

sub getSQLPlayListTemplates {
	my $client = shift;
	return Plugins::TrackStat::Template::Reader::getTemplates($client,'TrackStat',$PLUGINVERSION,'FileCache/SQLPlayList','PlaylistTemplates','xml');
}
sub getDatabaseQueryTemplates {
	my $client = shift;
	return Plugins::TrackStat::Template::Reader::getTemplates($client,'TrackStat',$PLUGINVERSION,'FileCache/DatabaseQuery','DataQueryTemplates','xml');
}

sub getDatabaseQueryDataQueries {
	my $client = shift;
	return Plugins::TrackStat::Template::Reader::getTemplates($client,'TrackStat',$PLUGINVERSION,,'FileCache/DatabaseQuery','DataQueries','xml','template','dataquery','simple',1);
}

sub getCustomBrowseTemplates {
	my $client = shift;
	return Plugins::TrackStat::Template::Reader::getTemplates($client,'TrackStat',$PLUGINVERSION,'FileCache/CustomBrowse','MenuTemplates','xml');
}

sub getCustomBrowseContextTemplates {
	my $client = shift;
	return Plugins::TrackStat::Template::Reader::getTemplates($client,'TrackStat',$PLUGINVERSION,'FileCache/CustomBrowse','ContextMenuTemplates','xml');
}

sub getCustomBrowseMenus {
	my $client = shift;
	return Plugins::TrackStat::Template::Reader::getTemplates($client,'TrackStat',$PLUGINVERSION,'FileCache/CustomBrowse','Menus','xml','template','menu','simple',1);
}

sub getCustomBrowseContextMenus {
	my $client = shift;
	my $result = Plugins::TrackStat::Template::Reader::getTemplates($client,'TrackStat',$PLUGINVERSION,'FileCache/CustomBrowse','ContextMenus','xml','template','menu','simple',1);
	if($result) {
		for my $item (@$result) {
			my $content = $item->{'menu'};
			$item->{'menu'} = replaceMenuParameters($content);
		}
	}
	return $result;
}

sub replaceMenuParameters {
	my $content = shift;
	if(defined($content)) {
		my $ratingScale = $prefs->get("rating_10scale");
		$content =~ s/\{rating_10scale\}/$ratingScale/g;
	}
	return $content;
}
sub getCustomBrowseMixes {
	my $client = shift;
	return Plugins::TrackStat::Template::Reader::getTemplates($client,'TrackStat',$PLUGINVERSION,'FileCache/CustomBrowse','Mixes','xml','mix');
}

sub getSQLPlayListTemplateData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;
	my $data = Plugins::TrackStat::Template::Reader::readTemplateData('TrackStat','PlaylistTemplates',$templateItem->{'id'});
	return $data;
}


sub getDatabaseQueryTemplateData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;
	
	my $data = Plugins::TrackStat::Template::Reader::readTemplateData('TrackStat','DataQueryTemplates',$templateItem->{'id'});
	return $data;
}

sub getCustomBrowseTemplateData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;
	
	my $data = Plugins::TrackStat::Template::Reader::readTemplateData('TrackStat','MenuTemplates',$templateItem->{'id'});
	return $data;
}

sub getCustomBrowseContextTemplateData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;
	
	my $data = Plugins::TrackStat::Template::Reader::readTemplateData('TrackStat','ContextMenuTemplates',$templateItem->{'id'});
	return $data;
}

sub getCustomBrowseContextMenuData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;
	my $data = Plugins::TrackStat::Template::Reader::readTemplateData('TrackStat','ContextMenus',$templateItem->{'id'},"xml");
	return replaceMenuParameters($data);
}

sub getCustomBrowseMenuData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;
	my $data = Plugins::TrackStat::Template::Reader::readTemplateData('TrackStat','Menus',$templateItem->{'id'},"xml");
	return replaceMenuParameters($data);
}

sub getDatabaseQueryDataQueryData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;
	my $data = Plugins::TrackStat::Template::Reader::readTemplateData('TrackStat','DataQueries',$templateItem->{'id'},"xml");
	return replaceMenuParameters($data);
}

sub getCustomSkipFilterTypes {
	my @result = ();
	my %rated = (
		'id' => 'trackstat_rated',
		'name' => 'Rated (TrackStat)',
		'description' => 'Skip tracks with a low rating'
	);
	if($prefs->get("rating_10scale")) {
		$rated{'parameters'} = [
			{
				'id' => 'rating',
				'type' => 'singlelist',
				'name' => 'Maximum rating to skip',
				'data' => "14=* (0-14),24=** (0-24),34=*** (0-34),44=**** (0-44),54=***** (0-54),64=****** (0-64),74=******* (0-74),84=******** (0-84),94=********* (0-94),100=********** (0-100)",
				'value' => 44
			}
		];
	}else {
		$rated{'parameters'} = [
			{
				'id' => 'rating',
				'type' => 'singlelist',
				'name' => 'Maximum rating to skip',
				'data' => "29=* (0-29),49=** (0-49),69=*** (0-69),89=**** (0-89),100=***** (0-100)",
				'value' => 49
			}
		];
	}
	
	push @result, \%rated;
	my %notrated = (
		'id' => 'trackstat_notrated',
		'name' => 'Not rated (TrackStat)',
		'description' => 'Skip tracks without a rating'
	);
	push @result, \%notrated;
	my %recentlyplayedtracks = (
		'id' => 'trackstat_recentlyplayedtrack',
		'name' => 'Recently played songs',
		'description' => 'Skip songs that have been recently played',
		'parameters' => [
			{
				'id' => 'time',
				'type' => 'singlelist',
				'name' => 'Time between',
				'data' => '300=5 minutes,600=10 minutes,900=15 minutes,1800=30 minutes,3600=1 hour,7200=2 hours,10800=3 hours,21600=6 hours,43200=12 hours,86400=24 hours,259200=3 days,604800=1 week',
				'value' => 3600 
			}
		]
	);
	push @result, \%recentlyplayedtracks;
	my %recentlyplayedalbums = (
		'id' => 'trackstat_recentlyplayedalbum',
		'name' => 'Recently played albums',
		'description' => 'Skip songs from albums that have been recently played',
		'parameters' => [
			{
				'id' => 'time',
				'type' => 'singlelist',
				'name' => 'Time between',
				'data' => '300=5 minutes,600=10 minutes,900=15 minutes,1800=30 minutes,3600=1 hour,7200=2 hours,10800=3 hours,21600=6 hours,43200=12 hours,86400=24 hours,259200=3 days,604800=1 week',
				'value' => 600 
			}
		]
	);
	push @result, \%recentlyplayedalbums;
	my %recentlyplayedartists = (
		'id' => 'trackstat_recentlyplayedartist',
		'name' => 'Recently played artists',
		'description' => 'Skip songs by artists that have been recently played',
		'parameters' => [
			{
				'id' => 'time',
				'type' => 'singlelist',
				'name' => 'Time between',
				'data' => '300=5 minutes,600=10 minutes,900=15 minutes,1800=30 minutes,3600=1 hour,7200=2 hours,10800=3 hours,21600=6 hours,43200=12 hours,86400=24 hours,259200=3 days,604800=1 week',
				'value' => 600 
			}
		]
	);
	push @result, \%recentlyplayedartists;
	return \@result;
}

sub checkCustomSkipFilterType {
	my $client = shift;
	my $filter = shift;
	my $track = shift;

	my $currentTime = time();
	my $parameters = $filter->{'parameter'};
	if($filter->{'id'} eq 'trackstat_rated') {
		for my $parameter (@$parameters) {
			if($parameter->{'id'} eq 'rating') {
				my $ratings = $parameter->{'value'};
				my $rating = $ratings->[0] if(defined($ratings) && scalar(@$ratings)>0);
				
				my $trackHandle = Plugins::TrackStat::Storage::findTrack( $track->url,undef,$track);
				if(defined($trackHandle) && defined($trackHandle->rating) && $trackHandle->rating<=$rating) {
					return 1;
				}
				last;
			}
		}
	}elsif($filter->{'id'} eq 'trackstat_notrated') {
		my $trackHandle = Plugins::TrackStat::Storage::findTrack( $track->url,undef,$track);
		if(!defined($trackHandle) || !defined($trackHandle->rating) || !$trackHandle->rating) {
			return 1;
		}
	}elsif($filter->{'id'} eq 'trackstat_recentlyplayedtrack') {
		my $matching = 0;
		my $time = undef;
		for my $parameter (@$parameters) {
			if($parameter->{'id'} eq 'time') {
				my $times = $parameter->{'value'};
				my $time = $times->[0] if(defined($times) && scalar(@$times)>0);

				my $trackHandle = Plugins::TrackStat::Storage::findTrack( $track->url,undef,$track);
				if(defined($trackHandle) && $trackHandle->lastPlayed) {
					if($currentTime - $trackHandle->lastPlayed < $time) {
						return 1;
					}
				}
			}
		}
	}elsif($filter->{'id'} eq 'trackstat_recentlyplayedartist') {
		my $matching = 0;
		for my $parameter (@$parameters) {
			if($parameter->{'id'} eq 'time') {
				my $times = $parameter->{'value'};
				my $time = $times->[0] if(defined($times) && scalar(@$times)>0);

				my $artist = $track->artist();
				if(defined($artist)) {
					my $lastPlayed = Plugins::TrackStat::Storage::getLastPlayedArtist($artist->id);
					if(defined($lastPlayed)) {
						if($currentTime - $lastPlayed < $time) {
							return 1;
						}
					}
				}
				last;
			}
		}
	}elsif($filter->{'id'} eq 'trackstat_recentlyplayedalbum') {
		for my $parameter (@$parameters) {
			if($parameter->{'id'} eq 'time') {
				my $times = $parameter->{'value'};
				my $time = $times->[0] if(defined($times) && scalar(@$times)>0);

				my $album = $track->album();
				if(defined($album)) {
					my $lastPlayed = Plugins::TrackStat::Storage::getLastPlayedArtist($album->id);
					if(defined($lastPlayed)) {
						if($currentTime - $lastPlayed < $time) {
							return 1;
						}
					}
				}
				last;
			}
		}
	}
	return 0;
}

sub getCustomScanFunctions {
	my @result = ();
	eval "use Plugins::TrackStat::iTunes::Import";
	eval "use Plugins::TrackStat::iTunes::Export";
	eval "use Plugins::TrackStat::MusicMagic::Import";
	eval "use Plugins::TrackStat::MusicMagic::Export";
	eval "use Plugins::TrackStat::Amarok::Export";
	eval "use Plugins::TrackStat::Amarok::Import";
	push @result,Plugins::TrackStat::Amarok::Export::getCustomScanFunctions();
	push @result,Plugins::TrackStat::Amarok::Import::getCustomScanFunctions();
	push @result,Plugins::TrackStat::MusicMagic::Export::getCustomScanFunctions();
	push @result,Plugins::TrackStat::MusicMagic::Import::getCustomScanFunctions();
	push @result,Plugins::TrackStat::iTunes::Export::getCustomScanFunctions();
	push @result,Plugins::TrackStat::iTunes::Import::getCustomScanFunctions();
	return \@result;
}

sub initStatisticPlugins {
	%statisticPlugins = ();
	%statisticItems = ();
	%statisticTypes = ();

	Plugins::TrackStat::Statistics::Base::init();
	my %pluginlist = ();
	for my $plugin (qw(All FirstPlayed LastAdded LastPlayed LeastPlayed LeastPlayedRecentAdded MostPlayed MostPlayedRecentAdded MostPlayedRecent NotCompletelyRated NotCompletelyRatedRecentAdded NotCompletelyRatedRecent NotPlayed NotRated NotRatedRecentAdded NotRatedRecent PartlyPlayed SpecificRating TopRated TopRatedRecentAdded TopRatedRecent)) {
		my $fullname = "Plugins::TrackStat::Statistics::$plugin";
		no strict 'refs';
		eval {
			eval "use $fullname";
			if ($@) {
               			$log->warn("Failed to load statistic plugin $plugin: $@\n");
	                }
			if(UNIVERSAL::can("${fullname}","init")) {
				#$log->debug("Calling: ".$fullname."::init\n");
				eval { &{$fullname . "::init"}(); };
				if ($@) {
		                	$log->warn("Failed to call init on statistic plugin $plugin: $@\n");
		                }
			}
			if(UNIVERSAL::can("${fullname}","getStatisticItems")) {
				my $pluginStatistics = eval { &{$fullname . "::getStatisticItems"}() };
				if ($@) {
		                	$log->warn("Failed to call getStatisticItems on statistic plugin $plugin: $@\n");
		                }
				#$log->debug("Calling: ".$fullname."::getStatisticItems\n");
				for my $item (keys %$pluginStatistics) {
					my $enabled = $prefs->get('statistics_'.$item.'_enabled');
					#$log->debug("Statistic plugin loaded: $item from $plugin.pm\n");
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
					if($prefs->get("deep_hierarchy") || !defined($groups)) {
						$groups = $items{'groups'};
					}
					my $favourite = $prefs->get('statistics_'.$item.'_favourite');
					if(defined($favourite) && $favourite) {
						$items{'trackstat_statistic_favourite'} = 1;
					}else {
						$items{'trackstat_statistic_favourite'} = 0;
					}
					if(!defined($groups)) {
						my @emptyArray = ();
						$groups = \@emptyArray;
					}
					if($favourite) {
						my @favouriteGroups = ();
						for my $g (@$groups) {
							push @favouriteGroups,$g;
						}
						my @favouriteGroup = ();
						push @favouriteGroup, string('PLUGIN_TRACKSTAT_FAVOURITES');
						push @favouriteGroups,\@favouriteGroup;
						$groups = \@favouriteGroups;
					}
					if(scalar(@$groups)>0) {
						for my $currentgroups (@$groups) {
							my $currentLevel = \%statisticItems;
							my $grouppath = '';
							my $enabled = 1;
							for my $group (@$currentgroups) {
								$grouppath .= "_".escape($group);
								my $existingItem = $currentLevel->{'group_'.$group};
								if(defined($existingItem)) {
									if($enabled) {
										$enabled = $prefs->get('statistic_group_'.$grouppath.'_enabled');
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
										$enabled = $prefs->get('statistic_group_'.$grouppath.'_enabled');
										if(!defined($enabled)) {
											$enabled = 1;
										}
									}
									if($enabled && $items{'trackstat_statistic_enabled'}) {
										#$log->debug("Enabled: plugin_dynamicplaylist_playlist_".$grouppath."_enabled=1\n");
										$currentItemGroup{'trackstat_statistic_enabled'} = 1;
									}else {
										#$log->debug("Enabled: plugin_dynamicplaylist_playlist_".$grouppath."_enabled=0\n");
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
			$log->warn("Failed to load statistic plugin $plugin: $@\n");
		}
		use strict 'refs';
	}
	
	for my $key (keys %statisticPlugins) {
		my $item = $statisticPlugins{$key};
		if($item->{'trackstat_statistic_enabled'}) {
			if(defined($item->{'contextfunction'})) {
				for my $type (qw{album artist genre year playlist track}) {
					my %params = ();
					$params{$type} = 1;
					my $valid = eval {&{$item->{'contextfunction'}}(\%params)};
					if( $@ ) {
						$log->warn("Error calling contextfunction: $@\n");
					}
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

    my $listLength = $prefs->get("web_list_length");
    if(!defined $listLength || $listLength==0) {
    	$listLength = 20;
    }
    
    my $id = $params->{path};
    $id =~ s/^.*\/(.*?)\.htm.?$/$1/; 
    
    my $statistics = getStatisticPlugins();
	my $function = $statistics->{$id}->{'webfunction'};
	$log->debug("Calling webfunction for $id\n");
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
			if($prefs->get("force_grouprating") && $allowControls) {
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

			if($prefs->get("rating_10scale")) {
			  	$params->{'pluginTrackStatGroupRating'} = ($rating && $rating>0?($rating+5)/10:0);
				$params->{'pluginTrackStatGroupRatingNumber'} = sprintf("%.2f", $rating/10);
			}else {
			  	$params->{'pluginTrackStatGroupRating'} = ($rating && $rating>0?($rating+10)/20:0);
				$params->{'pluginTrackStatGroupRatingNumber'} = sprintf("%.2f", $rating/20);
			}

		}
		setDynamicPlaylistParams($client,$params);
	};
	if( $@ ) {
		$log->warn("Error in handleWebStatistics: $@\n");
	}
	
	handlePlayAdd($client,$params);
	return Slim::Web::HTTP::filltemplatefile('plugins/TrackStat/index.html', $params);
}

sub setDynamicPlaylistParams {
	my ($client, $params) = @_;

	my $dynamicPlaylist;
	$dynamicPlaylist = grep(/DynamicPlayList/, Slim::Utils::PluginManager->enabledPlugins($client));
	if($dynamicPlaylist && $prefs->get("dynamicplaylist")) {
		if(!defined($params->{'artist'}) && !defined($params->{'album'}) && !defined($params->{'genre'}) && !defined($params->{'year'}) && !defined($params->{'playlist'})) {
			$params->{'dynamicplaylist'} = "trackstat_".$params->{'songlistid'};
		}
	}
}
sub getPlayCount {
	my $track = shift;
	return $track->playcount;
}

sub getLastPlayed {
	my $track = shift;
	return $track->lastplayed;
}

sub initRatingChar {
	# set rating character
	if (defined($prefs->get("ratingchar"))) {
		my $str = $prefs->get("ratingchar");
		if($str ne '') {
			$RATING_CHARACTER = $str;
			$NO_RATING_CHARACTER = ' ' x length($RATING_CHARACTER);
		}
	}else {
		$prefs->set("ratingchar",$RATING_CHARACTER);
	}
}

sub initPlugin
{
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	Plugins::TrackStat::Settings::Basic->new($class);
	Plugins::TrackStat::Settings::Backup->new($class);
	Plugins::TrackStat::Settings::EnabledStatistic->new($class);
	Plugins::TrackStat::Settings::Favorites->new($class);
	Plugins::TrackStat::Settings::Interface->new($class);
	Plugins::TrackStat::Settings::Rating->new($class);
    $log->debug("initialising\n");
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
		if($prefs->get("disablenumberscroll")) { 
			for my $key (keys %mapping) {
				if($key =~ /^\d\.single$/) {
					$mapping{$key}='dead';
				}
			}
		}
		Slim::Hardware::IR::addModeDefaultMapping('PLUGIN.TrackStat.Choice',\%choiceMapping);

		# Alter mapping for functions & buttons in Now Playing mode.
		Slim::Hardware::IR::addModeDefaultMapping('playlist',defaultMap()) if(!$prefs->{'itunesupdate'});

		# this will enable DynamicPlaylist integration by default
		if (!defined($prefs->get("dynamicplaylist"))) { 
			$log->debug("First run - setting dynamicplaylist ON\n");
			$prefs->set("dynamicplaylist", 1 ); 
		}

		# this will enable DynamicPlaylist integration to not repeat tracks by default
		if (!defined($prefs->get("dynamicplaylist_norepeat"))) { 
			$log->debug("First run - setting dynamicplaylist no repeat ON\n");
			$prefs->set("dynamicplaylist_norepeat", 1 ); 
		}

		# set default web list length to same as items per page
		if (!defined($prefs->get("web_list_length"))) {
			$prefs->set("web_list_length",$serverPrefs->get("itemsPerPage"));
		}
		# set default player list length to same as web list length or 20 if not exist
		if (!defined($prefs->get("player_list_length"))) {
			if(defined($prefs->get("web_list_length"))) {
				$prefs->set("player_list_length",$prefs->get("web_list_length"));
			}else {
				$prefs->set("player_list_length",20);
			}
		}

		# set default playlist length to same as items per page
		if (!defined($prefs->get("playlist_length"))) {
			$prefs->set("playlist_length",$serverPrefs->get("itemsPerPage"));
		}
		# set default playlist per artist/album length to 10
		if (!defined($prefs->get("playlist_per_artist_length"))) {
			$prefs->set("playlist_per_artist_length",10);
		}

		# enable history by default
		if(!defined($prefs->get("history_enabled"))) {
			$prefs->set("history_enabled",1);
		}

		# Set default recent number of days to 30
		if(!defined($prefs->get("recent_number_of_days"))) {
			$prefs->set("recent_number_of_days",30);
		}

		# Set default recent added number of days to 30
		if(!defined($prefs->get("recentadded_number_of_days"))) {
			$prefs->set("recentadded_number_of_days",30);
		}

		# enable refresh at startup by default
		if(!defined($prefs->get("refresh_startup"))) {
			$prefs->set("refresh_startup",1);
		}

		# enable refresh after rescan by default
		if(!defined($prefs->get("refresh_rescan"))) {
			$prefs->set("refresh_rescan",1);
		}

		# set default song threshold to 1800
		if (!defined($prefs->get("song_threshold_length"))) {
			$prefs->set("song_threshold_length",1800);
		}

		# set default min song length to 5
		if (!defined($prefs->get("min_song_length"))) {
			$prefs->set("min_song_length",5);
		}

		# set default min song percent
		if (!defined($prefs->get("min_song_percent"))) {
			$prefs->set("min_song_percent",50);
		}
		
		# enable web auto refresh by default
		if(!defined($prefs->get("web_refresh"))) {
			$prefs->set("web_refresh",1);
		}
		# enable mixer links by default
		if(!defined($prefs->get("web_show_mixerlinks"))) {
			$prefs->set("web_show_mixerlinks",1);
		}
		
		# enable mixer functions on web by default
		if(!defined($prefs->get("web_enable_mixerfunction"))) {
			$prefs->set("web_enable_mixerfunction",1);
		}

		# enable mixer functions on player by default
		if(!defined($prefs->get("enable_mixerfunction"))) {
			$prefs->set("enable_mixerfunction",1);
		}

		# Do not force group ratings by default
		if(!defined($prefs->get("force_grouprating"))) {
			$prefs->set("force_grouprating",0);
		}
		
		# Use structured menu on player by default
		if(!defined($prefs->get("player_flatlist"))) {
			$prefs->set("player_flatlist",0);
		}
		# Use structured menu on web by default
		if(!defined($prefs->get("web_flatlist"))) {
			$prefs->set("web_flatlist",0);
		}

		# Use deeper structured menu
		if(!defined($prefs->get("deep_hierarchy"))) {
			$prefs->set("deep_hierarchy",0);
		}

		# Set scheuled backup time
		if(!defined($prefs->get("backup_time"))) {
			$prefs->set("backup_time","03:00");
		}

		# Set scheduled backup dir
		if(!defined($prefs->get("backup_dir"))) {
			if(defined($prefs->get("backup_file"))) {
				my $dir = $prefs->get("backup_file"); 
				while ($dir =~ m/[^\/\\]$/) {
					$dir =~ s/[^\/\\]$//sg;
				}
				if($dir =~ m/[\/\\]$/) {
					$dir =~ s/[\/\\]$//sg;
				}
				$prefs->set("backup_dir",$dir);
			}elsif(defined($serverPrefs->get("playlistdir"))) {
				$prefs->set("backup_dir",$serverPrefs->get("playlistdir"));
			}else {
				$prefs->set("backup_dir",'');
			}
				
		}

		# Turn of first scheduled backup to make it possible to configure changes
		if(!defined($prefs->get("backup_lastday"))) {
			my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
			$prefs->set("backup_lastday",$mday);
		}

		# Remove two track artists by default
		if(!defined($prefs->get("min_artist_tracks"))) {
			$prefs->set("min_artist_tracks",3);
		}

		# Remove single track albums by default
		if(!defined($prefs->get("min_album_tracks"))) {
			$prefs->set("min_album_tracks",2);
		}

		# Turn off 10 scale ratings by default
		if(!defined($prefs->get("rating_10scale"))) {
			$prefs->set("rating_10scale",0);
		}
		
		# Turn off automatic ratings by default
		if(!defined($prefs->get("rating_auto"))) {
			$prefs->set("rating_auto",0);
		}

		# Turn on automatic ratings on non rated tracks by default
		if(!defined($prefs->get("rating_auto_nonrated"))) {
			$prefs->set("rating_auto_nonrated",1);
		}

		# Default automatic rating on non rated tracks is 60
		if(!defined($prefs->get("rating_auto_nonrated_value"))) {
			$prefs->set("rating_auto_nonrated_value",60);
		}

		# Default value for automatic increasing ratings
		if(!defined($prefs->get("rating_increase_percent"))) {
			$prefs->set("rating_increase_percent",80);
		}

		# Default value for automatic decreasing ratings
		if(!defined($prefs->get("rating_decrease_percent"))) {
			$prefs->set("rating_decrease_percent",50);
		}

		# Default value for automatic smart ratings
		if(!defined($prefs->get("rating_auto_smart"))) {
			$prefs->set("rating_auto_smart",1);
		}

		# this will enable number scroll by default
		if (!defined($prefs->get("disablenumberscroll"))) { 
			$prefs->set("disablenumberscroll", 0 ); 
		}

		if(!defined($prefs->get("long_urls"))) {
			$prefs->set("long_urls",1);
		}

		if(!defined($prefs->get("itunesupdate"))) {
			$prefs->set("itunesupdate",0);
		}

		initRatingChar();
		
		installHook();
		
		Plugins::TrackStat::Storage::init();

		initStatisticPlugins();
		
		my %mixerMap = ();
		if($prefs->get("web_enable_mixerfunction")) {
			$mixerMap{'mixerlink'} = \&mixerlink;
		}
		if($prefs->get("enable_mixerfunction")) {
			$mixerMap{'mixer'} = \&mixerFunction;
		}
		if($prefs->get("web_enable_mixerfunction") ||
			$prefs->get("enable_mixerfunction")) {
			Slim::Music::Import->addImporter($class, \%mixerMap);
			Slim::Music::Import->useImporter('Plugins::TrackStat::Plugin', 1);
		}
		
		checkAndPerformScheduledBackup();
	}
	addTitleFormat('TRACKNUM. ARTIST - TITLE (TRACKSTATRATINGDYNAMIC)');
	addTitleFormat('TRACKNUM. TITLE (TRACKSTATRATINGDYNAMIC)');
	addTitleFormat('PLAYING (X_OF_Y) (TRACKSTATRATINGSTATIC)');
	addTitleFormat('PLAYING (X_OF_Y) TRACKSTATRATINGSTATIC');
	addTitleFormat('TRACKSTATRATINGNUMBER');
	addTitleFormat('TRACKSTATRATINGSTATIC');
	addTitleFormat('TRACKSTATRATINGDYNAMIC');


	Slim::Music::TitleFormatter::addFormat('TRACKSTATRATINGDYNAMIC',\&getRatingDynamicCustomItem);
	Slim::Music::TitleFormatter::addFormat('TRACKSTATRATINGSTATIC',\&getRatingStaticCustomItem);
	Slim::Music::TitleFormatter::addFormat('TRACKSTATRATINGNUMBER',\&getRatingNumberCustomItem);

	Plugins::TrackStat::iPeng::Reader::read("TrackStat","iPengConfiguration");
}

sub postinitPlugin {
	if(isPluginsInstalled(undef,"CustomScan::Plugin")) {
		eval "use Plugins::TrackStat::iTunes::Import";
		eval "use Plugins::TrackStat::iTunes::Export";
		eval "use Plugins::TrackStat::MusicMagic::Import";
		eval "use Plugins::TrackStat::MusicMagic::Export";
		eval "use Plugins::TrackStat::Amarok::Export";
		eval "use Plugins::TrackStat::Amarok::Import";
	}
	# Alter mapping for functions & buttons in Now Playing mode. (We need to do this in postinit to overwrite any iTunesUpdate changes)
	my $functref = Slim::Buttons::Playlist::getFunctions();
	$functref->{'saveRating'} = \&saveRatingsForCurrentlyPlaying if(!$prefs->get("itunesupdate") || !exists $functref->{'saveRating'});

	no strict 'refs';
	my @enabledplugins;
	@enabledplugins = Slim::Utils::PluginManager->enabledPlugins();
	for my $plugin (@enabledplugins) {
		if(UNIVERSAL::can("$plugin","setTrackStatRating")) {
			$log->debug("Added rating support for $plugin\n");
			$ratingPlugins{$plugin} = "${plugin}::setTrackStatRating";
		}
		if(UNIVERSAL::can("$plugin","setTrackStatStatistic")) {
			$log->debug("Added play count support for $plugin\n");
			$playCountPlugins{$plugin} = "${plugin}::setTrackStatStatistic";
		}
	}
	use strict 'refs';
}

sub checkAndPerformScheduledBackup {
	my $timestr = $prefs->get("backup_time");
	my $day = $prefs->get("backup_lastday");
	my $dir = $prefs->get("backup_dir");
	if(!defined($day)) {
		$day = '';
	}
	
	$log->debug("Checking if its time to do a scheduled backup\n");
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
			$log->info("Making backup to: $dir/trackstat_scheduled_backup_".(1900+$year).(($mon+1)<10?'0'.($mon+1):($mon+1)).($mday<10?'0'.$mday:$mday).".xml\n");
			eval {
				backupToFile("$dir/trackstat_scheduled_backup_".(1900+$year).(($mon+1)<10?'0'.($mon+1):($mon+1)).($mday<10?'0'.$mday:$mday).".xml");
			};
			if ($@) {
		    		$log->error("Scheduled backup failed: $@\n");
		    	}
		    	$prefs->set("backup_lastday",$mday);
		}else {
			my $timesleft = $time-$currenttime;
			if($day eq $mday) {
				$timesleft = $timesleft + 60*60*24;
			}
			$log->debug("Its ".($timesleft)." seconds left until next scheduled backup\n");
		}
		
	}else {
		$log->debug("Scheduled backups disabled\n");
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
	}elsif($blessed eq 'Slim::Schema::Contributor' &&  Slim::Schema->variousArtistsObject->id ne $item->id) {
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
	my $paramref = defined $client->modeParam('parentParams') ? $client->modeParam('parentParams') : $client->modeParameterStack(-1);
	if(defined($paramref)) {
		my $listIndex = $paramref->{'listIndex'};
		my $items     = $paramref->{'listRef'};
		my $currentItem = $items->[$listIndex];
		my $hierarchy = $paramref->{'hierarchy'};
		my @levels    = split(",", $hierarchy);
		my $level     = $paramref->{'level'} || 0;
		my $mixerType = $levels[$level];
		if($mixerType eq 'contributor' &&  Slim::Schema->variousArtistsObject->id ne $currentItem->id) {
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
				$log->debug("Calling album statistics with ".$params{'album'}."\n");
				Slim::Buttons::Common::pushModeLeft($client,'Plugins::TrackStat::Plugin',\%params);
				$client->update();
			}elsif($mixerType eq 'year') {
				my $year = $currentItem;
				$year = $currentItem->id;
				my %params = (
					'year' => $year,
					'statistictype' => 'year',
					'flatlist' => 1
				);
				$log->debug("Calling album statistics with ".$params{'year'}."\n");
				Slim::Buttons::Common::pushModeLeft($client,'Plugins::TrackStat::Plugin',\%params);
				$client->update();
			}elsif($mixerType eq 'artist') {
				my %params = (
					'artist' => $currentItem->id,
					'statistictype' => 'artist',
					'flatlist' => 1
				);
				$log->debug("Calling artist statistics with ".$params{'artist'}."\n");
				Slim::Buttons::Common::pushModeLeft($client,'Plugins::TrackStat::Plugin',\%params);
				$client->update();
			}elsif($mixerType eq 'genre') {
				my %params = (
					'genre' => $currentItem->id,
					'statistictype' => 'genre',
					'flatlist' => 1
				);
				$log->debug("Calling genre statistics with ".$params{'genre'}."\n");
				Slim::Buttons::Common::pushModeLeft($client,'Plugins::TrackStat::Plugin',\%params);
				$client->update();
			}elsif($mixerType eq 'playlist') {
				my %params = (
					'playlist' => $currentItem->id,
					'statistictype' => 'playlist',
					'flatlist' => 1
				);
				$log->debug("Calling playlist statistics with ".$params{'playlist'}."\n");
				Slim::Buttons::Common::pushModeLeft($client,'Plugins::TrackStat::Plugin',\%params);
				$client->update();
			}else {
				$log->warn("Unknown statistictype = ".$mixerType."\n");
			}
		}else {
			$log->warn("No statistics found for ".$mixerType."\n");
		}
	}else {
		$log->warn("No parent parameter found\n");
	}

}
sub title {
	return 'TRACKSTAT';
}

sub mixerlink {
        my $item = shift;
        my $form = shift;
        my $descend = shift;
#		$log->debug("***********************************\n");
#		for my $it (keys %$form) {
#			$log->debug("form{$it}=".$form->{$it}."\n");
#		}
#		$log->debug("***********************************\n");
		
	my $levelName = $form->{'levelName'};
	if($form->{'noTrackStatButton'}) {
	}elsif(defined($levelName) && ($levelName eq 'artist' || $levelName eq 'contributor' || $levelName eq 'album' || $levelName eq 'genre' || $levelName eq 'playlist')) {
		if(($levelName eq 'artist' || $levelName eq 'contributor') &&  Slim::Schema->variousArtistsObject->id eq $item->id) {
        	}else {
			$form->{'mixerlinks'}{'TRACKSTAT'} = "plugins/TrackStat/mixerlink65.html";
		}
        }elsif(defined($levelName) && $levelName eq 'year') {
        	$form->{'yearid'} = $item->id;
        	if(defined($form->{'yearid'})) {
       			$form->{'mixerlinks'}{'TRACKSTAT'} = "plugins/TrackStat/mixerlink65.html";
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
       			$form->{'mixerlinks'}{'TRACKSTAT'} = "plugins/TrackStat/mixerlink65.html";
        	}
        }
        return $form;
}
	
sub addTitleFormat
{
	my $titleformat = shift;
	my $titleFormats = $serverPrefs->get('titleFormat');
	foreach my $format ( @$titleFormats ) {
		if($titleformat eq $format) {
			return;
		}
	}
	$log->debug("Adding: $titleformat");
	push @$titleFormats,$titleformat;
	$serverPrefs->set('titleFormat',$titleFormats);
}

sub shutdownPlugin {
        $log->debug("disabling\n");
        if ($TRACKSTAT_HOOK) {
                uninstallHook();
		if($prefs->get("web_enable_mixerfunction") ||
			$prefs->get("enable_mixerfunction")) {
			Slim::Music::Import->useImporter('Plugins::TrackStat::Plugin',0);
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

	#$log->debug("Asking about client $clientName ($clientID)\n");
	my $key = $client;
	if(defined($client->syncgroupid)) {
		$key = "SyncGroup".$client->syncgroupid;
	}
	# If we haven't seen this client before, create a new per-client 
	# playState structure.
	if (!defined($playerStatusHash{$key}))
	{
		$log->debug("Creating new PlayerStatus for $clientName ($clientID)\n");

		# Create new playState structure
		$playerStatusHash{$key} = TrackStatus->new();

		# Set appropriate defaults
		setPlayerStatusDefaults($client, $playerStatusHash{$key});
	}

	# If it didn't exist, it does now - 
	# return the playerStatus structure for the client.
	return $playerStatusHash{$key};
}

################################################
### main routines                            ###
################################################


# Hook the plugin to the play events.
# Do this as soon as possible during startup.
sub installHook()
{  
	$log->debug("Hook activated.\n");
	Slim::Control::Request::subscribe(\&Plugins::TrackStat::Plugin::commandCallback65,[['mode', 'play', 'stop', 'pause', 'playlist','rescan']]);
	Slim::Control::Request::addDispatch(['trackstat','getrating', '_trackid'], [0, 1, 0, \&getCLIRating]);
	Slim::Control::Request::addDispatch(['trackstat','setrating', '_trackid', '_rating'], [1, 0, 0, \&setCLIRating]);
	Slim::Control::Request::addDispatch(['trackstat','setstatistic', '_trackid','_playcount','_lastplayed'], [1, 0, 0, \&setCLIStatistic]);
	Slim::Control::Request::addDispatch(['trackstat', 'changedrating', '_url', '_trackid', '_rating', '_ratingpercent'],[0, 0, 0, undef]);
	Slim::Control::Request::addDispatch(['trackstat', 'changedstatistic', '_url', '_trackid', '_playcount','_lastplayed'],[0, 0, 0, undef]);
	$TRACKSTAT_HOOK=1;
}

# Unhook the plugin's play event callback function. 
# Do this as the plugin shuts down, if possible.
sub uninstallHook()
{
	$log->debug("Hook deactivated.\n");
	Slim::Control::Request::unsubscribe(\&Plugins::TrackStat::Plugin::commandCallback65);
	$TRACKSTAT_HOOK=0;
}

# These xxxCommand() routines handle commands coming to us
# through the command callback we have hooked into.
sub openCommand($$$)
{
	######################################
	### Open command
	######################################

	# This is the chief way we detect a new song being played, NOT the play command.
	# Parameter - TrackStatus for current client
	my $client = shift;
	my $playStatus = shift;

	# Stop old song, if needed
	# do this before updating the filename as we need to use it in the stop function
	if ($playStatus->isTiming() eq "true")
	{
		stopTimingSong($client,$playStatus);
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
		$log->debug("Resuming with play from pause\n");
		resumeTimingSong($playStatus);
	} elsif ( ($playStatus->isTiming() eq "true") &&($playStatus->isPaused() eq "false") )
	{
		$log->debug("Ignoring play command, assumed redundant...\n");		      
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
			$log->debug("Pausing (vanilla pause)\n");
			pauseTimingSong($playStatus);   
		} elsif ($playStatus->isPaused() eq "true") {
			$log->debug("Unpausing (vanilla unpause)\n");
			resumeTimingSong($playStatus);      
		}
	}

	# "pause 1" means "pause true", so pause and stop timing, if not already paused.
	elsif ( ($secondParm eq 1) && ($playStatus->isPaused() eq "false") ) {
		$log->debug("Pausing (1 case)\n");
		pauseTimingSong($playStatus);      
	}

	# "pause 0" means "pause false", so unpause and resume timing, if not already timing.
	elsif ( ($secondParm eq 0) && ($playStatus->isPaused() eq "true") ) {
		$log->debug("Pausing (0 case)\n");
		resumeTimingSong($playStatus);      
	} else {      
		$log->debug("Pause command ignored, assumed redundant.\n");
	}
}

sub stopCommand($$)
{
	######################################
	### Stop command
	######################################

	# Parameter - TrackStatus for current client
	my $client = shift;
	my $playStatus = shift;

	if ($playStatus->isTiming() eq "true")
	{
		stopTimingSong($client,$playStatus);      
	}
}


# This gets called during playback events.
# We look for events we are interested in, and start and stop our various
# timers accordingly.
sub commandCallback65($) 
{
	$log->debug("Entering commandCallback65\n");
	# These are the two passed parameters
	my $request=shift;
	my $client = $request->client();

	######################################
	## Rescan finished
	######################################
	if ( $request->isCommand([['rescan'],['done']]) )
	{
		if($prefs->get("refresh_rescan")) {
			Plugins::TrackStat::Storage::refreshTracks();
		}
	}

	if(!defined $client) {
		$log->debug("Exiting commandCallback65\n");
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
		openCommand($client,$playStatus,$request->getParam('_path'));
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
		stopCommand($client,$playStatus);
	}

	######################################
	### Stop command
	######################################

	if ( $request->isCommand([['playlist'],['sync']]) or $request->isCommand([['playlist'],['clear']]) )
	{
		# If this player syncs with another, we treat it as a stop,
		# since whatever it is presently playing (if anything) will end.
		stopCommand($client,$playStatus);
	}

	######################################
	## Power command
	######################################
	if ( $request->isCommand([['power']]))
	{
		stopCommand($client,$playStatus);
	}
	$log->debug("Exiting commandCallback65\n");
}

# A new song has begun playing. Reset the current song
# timer and set new Artist and Track.
sub startTimingNewSong($$$$)
{
	# Parameter - TrackStatus for current client
	my $playStatus = shift;
	return unless $playStatus->currentTrackOriginalFilename;
	$log->debug("Starting a new song\n");
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
			$log->warn("Programmer error in startTimingNewSong() - already timing!\n");	 
		}

		# Clear the stopwatch and start it again
		($playStatus->currentSongStopwatch())->clear();
		($playStatus->currentSongStopwatch())->start();

		# Not paused - we are playing a song
		$playStatus->isPaused("false");

		# We are now timing a song
		$playStatus->isTiming("true");

		$playStatus->trackAlreadyLoaded("false");

		$log->debug("Starting to time ",$playStatus->currentTrackOriginalFilename,"\n");
	} else {
		$log->debug("Not timing ",$playStatus->currentTrackOriginalFilename," - not a file\n");
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
		$log->warn("Programmer error or other problem in pauseTimingSong! Confused about pause status.\n");      
	}

	# Stop the stopwatch 
	$playStatus->currentSongStopwatch()->stop();

	# Go into pause mode
	$playStatus->isPaused("true");

	$log->debug("Pausing ",$playStatus->currentTrackOriginalFilename,"\n");
	$log->debug("Elapsed seconds: ",$playStatus->currentSongStopwatch()->getElapsedTime(),"\n");
	#showCurrentVariables($playStatus);
}

# Resume the current song timer - playing again
sub resumeTimingSong($)
{
	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	if ($playStatus->isPaused() eq "false")
	{
		$log->warn("Programmer error or other problem in resumeTimingSong! Confused about pause status.\n");      
	}

	# Re-start the stopwatch 
	$playStatus->currentSongStopwatch()->start();

	# Exit pause mode
	$playStatus->isPaused("false");

	$log->debug("Resuming ",$playStatus->currentTrackOriginalFilename,"\n");
	#showCurrentVariables($playStatus);
}

# Stop timing the current song
# (Either stop was hit or we are about to play another one)
sub stopTimingSong($$)
{
	# Parameter - TrackStatus for current client
	my $client = shift;
	my $playStatus = shift;

	if ($playStatus->isTiming() eq "false")
	{
		$log->warn("Programmer error - not already timing!\n");   
	}

	if (Slim::Music::Info::isFile($playStatus->currentTrackOriginalFilename)) {

		my $totalElapsedTimeDuringPlay = $playStatus->currentSongStopwatch()->getElapsedTime();
		$log->debug("Stopping timing ",$playStatus->currentTrackOriginalFilename,"\n");
		$log->debug("Total elapsed time in seconds: $totalElapsedTimeDuringPlay \n");
		# We wan't to stop timing here since there is a risk that we will get a recursion loop else
		$playStatus->isTiming("false");

		# If the track was played long enough to count as a listen..
		if (trackWasPlayedEnoughToCountAsAListen($playStatus, $totalElapsedTimeDuringPlay) )
		{
			#$log->debug("Track was played long enough to count as listen\n");
			markedAsPlayed($client,$playStatus->currentTrackOriginalFilename);
			# We could also log to history at this point as well...
		}
		# If automatic rating is enabled
		if($prefs->get("rating_auto")) {
			my $minPlayedTime = $prefs->get("min_song_length");
			if($totalElapsedTimeDuringPlay>=$minPlayedTime) {
				my $trackHandle = Plugins::TrackStat::Storage::findTrack( $playStatus->currentTrackOriginalFilename);
				my $rating = undef;
				if(defined($trackHandle)) {
					$rating = $trackHandle->rating;
				}
				if($prefs->get("rating_auto_nonrated")) {
					if(!$rating) {
						$log->debug("Setting default rating 3 on unrated track\n");
						$rating = $prefs->get("rating_auto_nonrated_value");
					}
				}
	
				if($rating) {
					my $increase = $prefs->get("rating_increase_percent");
					$increase = $increase*$playStatus->currentTrackLength() / 100;
					my $decrease = $prefs->get("rating_decrease_percent");
					$decrease = $decrease*$playStatus->currentTrackLength() / 100;
	
					# RT - 3.Aug.2007: accelerated algorithm inspired by quodlibet plugin
					my $delta = $rating;
					if ($rating > 50) { 
						$delta = 100 - $rating; 
					}

					if($totalElapsedTimeDuringPlay>=$increase && $rating<100) {
						$delta = floor( $delta / 8 );
						if (!$prefs->get("rating_auto_smart") || $delta < 1) { 
							$delta = 1; 
						}

						$log->debug("Increasing rating by $delta/100, played $totalElapsedTimeDuringPlay of required $increase seconds\n");
						$rating = $rating + $delta;
						if($rating>100) {
							$rating = 100;
						}
						rateSong($client,$playStatus->currentTrackOriginalFilename,$rating);
					}elsif($totalElapsedTimeDuringPlay<$decrease && $rating>0) {
						$delta = floor( $delta / 4 );
						if (!$prefs->get("rating_auto_smart") || $delta < 1) { 
							$delta = 1; 
						}
						$log->debug("Decreasing rating by $delta/100, played $totalElapsedTimeDuringPlay of required $decrease seconds\n");
						$rating = $rating - $delta;
						if($rating<1) {
							$rating = 1;
						}
						rateSong($client,$playStatus->currentTrackOriginalFilename,$rating);
					}else {
						$log->debug("Do not adjust rating, only played $totalElapsedTimeDuringPlay of required $increase seconds\n");
					}
				}else {
					$log->debug("Do not adjust rating on non rated tracks\n");
				}
			}else {
				$log->debug("Do not adjust rating, tracks played shorter than $minPlayedTime seconds will not be automatic rated\n");
			}
		}
	} else {
		$log->debug("That wasn't a file - ignoring\n");
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
	$log->debug("Entering markedAsPlayed\n");
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
	}else {
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
		$log->debug("Calling $item\n");
		eval { &{$playCountPlugins{$item}}($client,$url,\%statistic) };
		if( $@ ) {
			$log->warn("Error calling changedstatistic plugin: $@\n");
		}
	}
	use strict 'refs';
	Slim::Control::Request::notifyFromArray($client, ['trackstat', 'changedstatistic', $url, $track->id, $playCount, $lastPlayed]);
	$log->debug("Exiting markedAsPlayed\n");
}

# Debugging routine - shows current variable values for the given playStatus
sub showCurrentVariables($)
{
	# Parameter - TrackStatus for current client
	my $playStatus = shift;

	$log->debug("======= showCurrentVariables() ========\n");
	$log->debug("Artist:",playStatus->currentSongArtist(),"\n");
	$log->debug("Track: ",$playStatus->currentSongTrack(),"\n");
	$log->debug("Album: ",$playStatus->currentSongAlbum(),"\n");
	$log->debug("Original Filename: ",$playStatus->currentTrackOriginalFilename(),"\n");
	$log->debug("Duration in seconds: ",$playStatus->currentTrackLength(),"\n"); 
	$log->debug("Time showing on stopwatch: ",$playStatus->currentSongStopwatch()->getElapsedTime(),"\n");
	$log->debug("Is song playback paused? : ",$playStatus->isPaused(),"\n");
	$log->debug("Are we currently timing? : ",$playStatus->isTiming(),"\n");
	$log->debug("=======================================\n");
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

	my $minPlayedTime = $prefs->get("min_song_length");
	if(!defined $minPlayedTime) {
		$minPlayedTime = 5;
	}

	my $thresholdTime = $prefs->get("song_threshold_length");
	if(!defined $thresholdTime) {
		$thresholdTime = 1800;
	}

	my $minPlayedPercent = $prefs->get("min_song_percent");
	if(!defined $minPlayedPercent) {
		$minPlayedPercent = 50;
	}

	# The minimum play time the % minimum requires
	my $minimumPlayLengthFromPercentPlayThreshold = $minPlayedPercent * $currentTrackLength / 100;

	my $printableDisplayThreshold = $minPlayedPercent;
	$log->debug("Time actually played in track: $totalTimeElapsedDuringPlay\n");
	#$log->debug("Current play threshold is $printableDisplayThreshold%.\n");
	#$log->debug("Minimum play time is $minPlayedTime seconds.\n");
	#$log->debug("Time play threshold is $thresholdTime seconds.\n");
	#$log->debug("Percentage play threshold calculation:\n");
	#$log->debug("$minPlayedPercent * $currentTrackLength / 100 = $minimumPlayLengthFromPercentPlayThreshold\n");	

	# Did it play at least the absolute minimum amount?
	if ($totalTimeElapsedDuringPlay < $minPlayedTime ) 
	{
		# No. This condition overrides the others.
		$log->debug("\"$tmpCurrentSongTrack\" NOT played long enough: Played $totalTimeElapsedDuringPlay; needed to play $minPlayedTime seconds.\n");
		$wasLongEnough = 0;   
	}
	# Did it play past the percent-of-track played threshold?
	elsif ($totalTimeElapsedDuringPlay >= $minimumPlayLengthFromPercentPlayThreshold)
	{
		# Yes. We have a play.
		$log->debug("\"$tmpCurrentSongTrack\" was played long enough to count as played.\n");
		$log->debug("Played past percentage threshold of $minimumPlayLengthFromPercentPlayThreshold seconds.\n");
		$wasLongEnough = 1;
	}
	# Did it play past the number-of-seconds played threshold?
	elsif ($totalTimeElapsedDuringPlay >= $thresholdTime)
	{
		# Yes. We have a play.
		$log->debug("\"$tmpCurrentSongTrack\" was played long enough to count as played.\n");
		$log->debug("Played past time threshold of $thresholdTime seconds.\n");
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
		$log->debug("\"$tmpCurrentSongTrack\" NOT played long enough: Played $totalTimeElapsedDuringPlay; needed to play $minimumPlayTimeNeeded seconds.\n");
		$wasLongEnough = 0;   
	}
	return $wasLongEnough;
}




sub rateSong($$$) {
	my ($client,$url,$rating)=@_;

	$log->debug("Changing song rating to: $rating\n");
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	my $track = Plugins::TrackStat::Storage::objectForUrl($url);
	if(!defined $track) {
		$log->warn("Failure setting rating, track does not exist: $url\n");
		return;
	}
	Plugins::TrackStat::Storage::saveRating($url,undef,$track,$rating);
	no strict 'refs';
	for my $item (keys %ratingPlugins) {
		$log->debug("Calling $item\n");
		eval { &{$ratingPlugins{$item}}($client,$url,$rating) };
		if( $@ ) {
			$log->warn("Error calling changedrating plugin: $@\n");
		}
	}
	my $digit = floor(($rating+10)/20);
	use strict 'refs';
	Slim::Control::Request::notifyFromArray($client, ['trackstat', 'changedrating', $url, $track->id, $digit, $rating]);
	Slim::Music::Info::clearFormatDisplayCache();
	$ratingStaticLastUrl = undef;
	$ratingDynamicLastUrl = undef;
	$ratingNumberLastUrl = undef;
}

sub setTrackStatRating {
	$log->debug("Entering setTrackStatRating\n");
	my ($client,$url,$rating)=@_;
	my $track = undef;
	my $ds = Plugins::TrackStat::Storage::getCurrentDS();
	eval {
		$track = Plugins::TrackStat::Storage::objectForUrl($url);
	};
	if ($@) {
		$log->warn("Error retrieving track: $url\n");
	}
	if($track) {
		# Run this within eval for now so it hides all errors until this is standard
		eval {
			$track->set('rating' => $rating);
			$track->update();
			$ds->forceCommit();
		};
	}
	if(isPluginsInstalled($client,"CustomScan::Plugin")) {
		Plugins::TrackStat::MusicMagic::Export::exportRating($url,$rating,$track);
		Plugins::TrackStat::iTunes::Export::exportRating($url,$rating,$track);
		Plugins::TrackStat::Amarok::Export::exportRating($url,$rating,$track);
	}
	$log->debug("Exiting setTrackStatRating\n");
}

sub getCLIRating {
	$log->debug("Entering getCLIRating\n");
	my $request = shift;
	
	if ($request->isNotQuery([['trackstat'],['getrating']])) {
		$log->warn("Incorrect command\n");
		$request->setStatusBadDispatch();
		$log->debug("Exiting getCLIRating\n");
		return;
	}
	# get our parameters
  	my $trackId    = $request->getParam('_trackid');
  	if(!defined $trackId || $trackId eq '') {
		$log->warn("_trackid not defined\n");
		$request->setStatusBadParams();
		$log->debug("Exiting getCLIRating\n");
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
			$log->warn("Error retrieving track: $trackId\n");
		}
	}else {
		# The encapsulation with eval is just to make it more crash safe
		eval {
			$track = Plugins::TrackStat::Storage::objectForId('track',$trackId);
		};
		if ($@) {
			$log->warn("Error retrieving track: $trackId\n");
		}
	}
	
	if(!defined $track || !defined $track->audio) {
		$log->warn("Track $trackId not found\n");
		$request->setStatusBadParams();
		$log->debug("Exiting getCLIRating\n");
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
	$log->debug("Exiting getCLIRating\n");
}

sub setCLIRating {
	$log->debug("Entering setCLIRating\n");
	my $request = shift;
	my $client = $request->client();
	
	if ($request->isNotCommand([['trackstat'],['setrating']])) {
		$log->warn("Incorrect command\n");
		$request->setStatusBadDispatch();
		$log->debug("Exiting setCLIRating\n");
		return;
	}
	if(!defined $client) {
		$log->warn("Client required\n");
		$request->setStatusNeedsClient();
		$log->debug("Exiting setCLIRating\n");
		return;
	}

	# get our parameters
  	my $trackId    = $request->getParam('_trackid');
  	my $rating    = $request->getParam('_rating');
  	if(!defined $trackId || $trackId eq '' || !defined $rating || $rating eq '') {
		$log->warn("_trackid and _rating not defined\n");
		$request->setStatusBadParams();
		$log->debug("Exiting setCLIRating\n");
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
			$log->warn("Error retrieving track: $trackId\n");
		}
	}else {
		# The encapsulation with eval is just to make it more crash safe
		eval {
			$track = Plugins::TrackStat::Storage::objectForId('track',$trackId);
		};
		if ($@) {
			$log->warn("Error retrieving track: $trackId\n");
		}
	}
	
	if(!defined $track || !defined $track->audio) {
		$log->warn("Track $trackId not found\n");
		$request->setStatusBadParams();
		$log->debug("Exiting setCLIRating\n");
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
	$log->debug("Exiting setCLIRating\n");
}

sub setCLIStatistic {
	$log->debug("Entering setCLIStatistic\n");
	my $request = shift;
	my $client = $request->client();
	
	if ($request->isNotCommand([['trackstat'],['setstatistic']])) {
		$log->warn("Incorrect command\n");
		$request->setStatusBadDispatch();
		$log->debug("Exiting setCLIStatistic\n");
		return;
	}
	if(!defined $client) {
		$log->warn("Client required\n");
		$request->setStatusNeedsClient();
		$log->debug("Exiting setCLIStatistic\n");
		return;
	}

	# get our parameters
  	my $trackId    = $request->getParam('_trackid');
  	my $lastplayed    = $request->getParam('_lastplayed');
  	my $playcount    = $request->getParam('_playcount');
  	if(!defined $trackId || $trackId eq '' || !defined $lastplayed || $lastplayed eq '') {
		$log->warn("_trackid and _lastplayed not defined\n");
		$request->setStatusBadParams();
		$log->debug("Exiting setCLIStatistic\n");
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
			$log->warn("Error retrieving track: $trackId\n");
		}
	}else {
		# The encapsulation with eval is just to make it more crash safe
		eval {
			$track = Plugins::TrackStat::Storage::objectForId('track',$trackId);
		};
		if ($@) {
			$log->warn("Error retrieving track: $trackId\n");
		}
	}
	
	if(!defined $track || !defined $track->audio) {
		$log->warn("Track $trackId not found\n");
		$request->setStatusBadParams();
		$log->debug("Exiting setCLIStatistic\n");
		return;
	}

	my $trackHandle = Plugins::TrackStat::Storage::findTrack( $track->url,undef,$track);

	if($trackHandle && $trackHandle->playCount && (!defined($playcount) || $trackHandle->playCount>$playcount)) {
		$playcount = $trackHandle->playCount;
	}

	if($trackHandle && $trackHandle->lastPlayed && (!defined($lastplayed) || $trackHandle->lastPlayed>$lastplayed)) {
		$lastplayed = $trackHandle->lastPlayed;
	}

	Plugins::TrackStat::Storage::savePlayCountAndLastPlayed($track->url,undef,$playcount,$lastplayed,$track);

	$request->setStatusDone();
	$log->debug("Exiting setCLIStatistic\n");
}


sub setTrackStatStatistic {
	$log->debug("Entering setTrackStatStatistic\n");
	my ($client,$url,$statistic)=@_;
	
	my $playCount = $statistic->{'playCount'};
	my $lastPlayed = $statistic->{'lastPlayed'};	
	my $rating = $statistic->{'rating'};
	if(isPluginsInstalled($client,"CustomScan::Plugin")) {
		Plugins::TrackStat::MusicMagic::Export::exportStatistic($url,$rating,$playCount,$lastPlayed);
		Plugins::TrackStat::iTunes::Export::exportStatistic($url,$rating,$playCount,$lastPlayed);
		Plugins::TrackStat::Amarok::Export::exportStatistic($url,$rating,$playCount,$lastPlayed);
	}
	$log->debug("Exiting setTrackStatStatistic\n");
}

sub ratingStringFormat {
        my $self = shift;
        my $client = shift;
        my $item = shift;
	my $parameters = shift;
	my $rating = $item->{'itemname'};
	if(defined($rating)) {
		my $lowrating = undef;
		if($prefs->get("rating_10scale")) {
			$lowrating = floor(($rating+5) / 10);
		}else {
			$lowrating = floor(($rating+10) / 20);
			$rating = floor($rating/2);
		}
		my $result = ($lowrating?$RATING_CHARACTER x $lowrating:'');
		if($parameters->{'shownumerical'} && $result ne '') {
			$result .= sprintf(" (%.2f)", $rating/10);
		}
		return $result;
	}else {
		return $rating;
	}
}
sub getRatingDynamicCustomItem
{
	my $track = shift;
	my $string = '';
	if(defined($ratingDynamicLastUrl) && $track->url eq $ratingDynamicLastUrl) {
		$string = $ratingDynamicCache;
	}else {
		$log->debug("Entering getRatingDynamicCustomItem\n");
		my $trackHandle = Plugins::TrackStat::Storage::findTrack( $track->url,undef,$track);
		if($trackHandle && $trackHandle->rating) {
			my $rating;
			if($prefs->get("rating_10scale")) {
				$rating = floor(($trackHandle->rating+5) / 10);
			}else {
				$rating = floor(($trackHandle->rating+10) / 20);
			}
			$string = ($rating?$RATING_CHARACTER x $rating:'');
		}
		$ratingDynamicLastUrl = $track->url;
		$ratingDynamicCache = $string;
		$log->debug("Exiting getRatingDynamicCustomItem\n");
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
		$log->debug("Entering getRatingStaticCustomItem\n");
		my $trackHandle = Plugins::TrackStat::Storage::findTrack( $track->url,undef,$track);
		if($trackHandle && $trackHandle->rating) {
			my $rating;
			if($prefs->get("rating_10scale")) {
				 $rating = floor(($trackHandle->rating+5) / 10);
			}else {
				 $rating = floor(($trackHandle->rating+10) / 20);
			}
			$log->debug("rating = $rating\n");
			if($rating) {
				$string = ($rating?$RATING_CHARACTER x $rating:'');
				my $left = 5 - $rating;
				$string = $string . ($NO_RATING_CHARACTER x $left);
			}
		}
		$ratingStaticLastUrl = $track->url;
		$ratingStaticCache = $string;
		$log->debug("Exiting getRatingStaticCustomItem\n");
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
		$log->debug("Entering getRatingNumberCustomItem\n");
		my $trackHandle = Plugins::TrackStat::Storage::findTrack( $track->url,undef,$track);
		if($trackHandle && $trackHandle->rating) {
			my $rating;
			if($prefs->get("rating_10scale")) {
				$rating = floor(($trackHandle->rating+5) / 10);
			}else {
				$rating = floor(($trackHandle->rating+10) / 20);
			}
			$string = ($rating?$rating:'');
		}
		$ratingNumberLastUrl = $track->url;
		$ratingNumberCache = $string;
		$log->debug("Exiting getRatingNumberCustomItem\n");
	}
	return $string;
}

sub backupToFile() 
{
	my $backupfile = shift;
	if(!defined($backupfile)) {
		$backupfile = $prefs->get("backup_file");
	}
	if($backupfile) {
		Plugins::TrackStat::Backup::File::backupToFile($backupfile);
	}else {
		$log->error("No backup file specified\n");
	}
}

sub restoreFromFile()
{
	my $backupfile = $prefs->get("backup_file");
	if($backupfile) {
		Plugins::TrackStat::Backup::File::restoreFromFile($backupfile);
	}else {
		$log->error("No backup file specified\n");
	}
}

sub getDynamicPlayLists {
	my ($client) = @_;
	my %result = ();

	return \%result unless $prefs->get("dynamicplaylist");
	
	my $statistics = getStatisticPlugins();
	for my $item (keys %$statistics) {
		my $id = $statistics->{$item}->{'id'};
		my $playlistid = "trackstat_".$id;
		my %playlistItem = (
			'id' => $id
		);
		if(defined($statistics->{$item}->{'namefunction'})) {
			$playlistItem{'name'} = eval { &{$statistics->{$item}->{'namefunction'}}() };
			if( $@ ) {
				$log->warn("TrackStat: Error calling namefunction: $@\n");
			}
		}else {
			$playlistItem{'name'} = $statistics->{$item}->{'name'};
		}
		$playlistItem{'url'}="plugins/TrackStat/".$id.".html?";
		$playlistItem{'urlcontext'}="#songlist";
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

	my $listLength = $prefs->get("playlist_length");
	if(!defined $listLength || $listLength==0) {
		$listLength = 20;
	}
	$log->debug("Got: ".$dynamicplaylist->{'id'}.", $limit\n");
	my $statistics = getStatisticPlugins();
	for my $item (keys %$statistics) {
		my $id = $statistics->{$item}->{'id'};
		if($dynamicplaylist->{'id'} eq $id) {
			$log->debug("Calling playlistfunction for ".$dynamicplaylist->{'id'}."\n");
			eval {
				$result = &{$statistics->{$item}->{'playlistfunction'}}($listLength,$limit);
			};
			if ($@) {
			    	$log->warn("Failure calling playlistfunction for ".$dynamicplaylist->{'id'}.": $@\n");
			}
		}
	}
	my @resultArray = ();
	for my $track (@$result) {
		push @resultArray,$track;
	}
	$log->debug("Got ".scalar(@resultArray)." tracks\n");
	return \@resultArray;
}

sub isPluginsInstalled {
	my $client = shift;
	my $pluginList = shift;
	my $enabledPlugin = 1;
	foreach my $plugin (split /,/, $pluginList) {
		if($enabledPlugin) {
			$enabledPlugin = grep(/$plugin/, Slim::Utils::PluginManager->enabledPlugins($client));
		}
	}
	return $enabledPlugin;
}

sub getLinkAttribute {
	my $attr = shift;
	if($attr eq 'artist') {
		$attr = 'contributor';
	}
	return $attr.'.id';
}

sub isTimeOrEmpty {
        my $name = shift;
        my $arg = shift;
        if(!$arg || $arg eq '') {
                return $arg;
        }elsif ($arg =~ m/^([0\s]?[0-9]|1[0-9]|2[0-4]):([0-5][0-9])\s*(P|PM|A|AM)?$/isg) {
                return $arg;

        }
	return undef;
}

sub isWritableFile {
        my $name = shift;
        my $arg = shift;
        if(!$arg || $arg eq '') {
                return $arg;
        }elsif (-e dirname($arg) && !-d $arg) {
                return $arg;

        }
	return undef;
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


1;

__END__
