# MusicInfoSCR.pm by mh jan 2005, parts by kdf Dec 2003, fcm4711 Oct 2005
#
# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# Changelog
# 2.02- prepare plugin for use with slimserver 6.5
# 2.01- fixed some issues with too aggressive caching and added one pixel before the icons
# 2.0 - add icons for shuffle and repeat modes - thanks to Felix Müller
#     - remove 6.1 stuff
# 1.9 - prepare for new %lines hash and prefs methods (>=6.2)
# 1.85- James Craig added a fullscreen progress bar - thanks, James!
# 1.8 - added support for new scrolling code in 6.1
# 1.73- fixed display change after scrolling of second line
# 1.72- fixed PLAYTIME display for streams that display 11329320:33:39...
# 1.71- fixed CURRTIME display (don't cache the current time...)
# 1.7 - removed manual update of line2 (only with >=6.1)
# 1.61- don't translate format strings (eg. X_OF_Y)
# 1.6 - improved PLAYTIME progressbar with different displays
# 1.51- improved online stream handling
# 1.5 - fixes for SlimServer v6.0
#     - added display cache for much lower cpu load
# 1.4 - added "CURRENTTIME", "PLAYLIST"
#     - added option to display playlist name if ALBUM/ARTIST is not available (streams)
# 1.3 - added general "FORMAT (X_OF_Y)"
#     - some cosmetics with PLAYTIME (put a space before progressbar, if reasonable)
# 1.2 - fixed progressbar in PLAYTIME
#     - added "X out of Y" style
#     - added french translation
# 1.1 - handle empty playlists, stopped, paused
#     - added jump back configuration: jump back to where you left or go to playlist
#     - added second value (right) for double line
# 1.0 - initial release

use strict;

package Plugins::MusicInfoSCR;

use Slim::Utils::Strings qw (string);
use vars qw($VERSION);
$VERSION = substr( q$Revision$, 10 );

# Start plugin patch
my %customitems = ();
# End plugin patch

sub getDisplayName() {
	return 'PLUGIN_SCREENSAVER_MUSICINFO';
}

sub setMode {
	my $client = shift;
	$client->lines( \&lines );	
}

my %functions = (
	'up' => sub {
		my $client = shift;
		$client->bumpUp();
	},
	'down' => sub {
		my $client = shift;
		$client->bumpDown();
	},
	'left' => sub {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub {
		my $client = shift;
		$client->bumpRight();
	},
	'play' => sub {
		my $client = shift;
		if ($client->prefGet('screensaver') ne 'SCREENSAVER.musicinfo' ) {
			$client->prefSet('screensaver', 'SCREENSAVER.musicinfo');
			$client->showBriefly({
				'line1' => string('PLUGIN_SCREENSAVER_MUSICINFO'),
				'line2' => string('PLUGIN_SCREENSAVER_MUSICINFO_ENABLING')
			});
		}
		else {
			$client->prefSet('screensaver', 'screensaver');
			$client->showBriefly({
				'line1' => string('PLUGIN_SCREENSAVER_MUSICINFO'),
				'line2' => string('PLUGIN_SCREENSAVER_MUSICINFO_DISABLING')
			});
		}
	},
);

my %displayCache = ();

my %icons = (
	# Squeezebox2
	'sb2' => {
		'blank' => 	"\x00\x00\x00\x00",

		'space' => 	"\x00\x00\x00\x00" .
					"\x00\x00\x00\x00" .
					"\x00\x00\x00\x00",
					
		'repeat' => {
			'0' =>	"\xff\xe0\x00\x00" .
					"\xff\xe0\x00\x00" .
					"\xaa\xa0\x00\x00" .
					"\xaa\xa0\x00\x00" .
					"\xaa\xa0\x00\x00" .
					"\xaa\xa0\x00\x00" .
					"\xaa\xa0\x00\x00" .
					"\xff\xe0\x00\x00" .
					"\xff\xe0\x00\x00",

			'1' =>	"\xff\xe0\x00\x00" .
					"\x80\x20\x00\x00" .
					"\xbf\xa0\x00\x00" .
					"\xbb\xa0\x00\x00" .
					"\xbb\xa0\x00\x00" .
					"\x8a\x20\x00\x00" .
					"\xfb\xe0\x00\x00" .
					"\xfb\xe0\x00\x00" .
					"\xff\xe0\x00\x00",

			'2' =>	"\xff\xe0\x00\x00" .
					"\x80\x20\x00\x00" .
					"\xbf\xa0\x00\x00" .
					"\xaa\xa0\x00\x00" .
					"\xaa\xa0\x00\x00" .
					"\xaa\xa0\x00\x00" .
					"\xea\xe0\x00\x00" .
					"\xea\xe0\x00\x00" .
					"\xff\xe0\x00\x00"
		},
		
		'shuffle' => {
			'0' =>	"\xff\xe0\x00\x00" .
					"\xf8\x20\x00\x00" .
					"\xff\xe0\x00\x00" .
					"\xf0\x60\x00\x00" .
					"\xff\xe0\x00\x00" .
					"\xc1\xe0\x00\x00" .
					"\xff\xe0\x00\x00" .
					"\x83\xe0\x00\x00" .
					"\xff\xe0\x00\x00",

			'1' =>	"\xff\xe0\x00\x00" .
					"\xf0\x60\x00\x00" .
					"\xff\xe0\x00\x00" .
					"\x83\xe0\x00\x00" .
					"\xff\xe0\x00\x00" .
					"\xf8\x20\x00\x00" .
					"\xff\xe0\x00\x00" .
					"\xc1\xe0\x00\x00" .
					"\xff\xe0\x00\x00",

			'2' =>	"\xff\xe0\x00\x00" .
					"\xf8\x20\x00\x00" .
					"\xff\xe0\x00\x00" .
					"\x83\xe0\x00\x00" .
					"\x83\xe0\x00\x00" .
					"\xff\xe0\x00\x00" .
					"\xe0\xe0\x00\x00" .
					"\xe0\xe0\x00\x00" .
					"\xff\xe0\x00\x00"
		}
	},

	# SqueezeboxG
	'sbg' => {
		'blank' => 	"\x00\x00",

		'space' => 	"\x00\x00" .
					"\x00\x00" .
					"\x00\x00",
					
		'repeat' => {
			'0' =>	"\x00\x00" .
					"\xaa\x00" .
					"\xaa\x00" .
					"\xaa\x00" .
					"\xaa\x00",

			'1' =>	"\xfe\x00" .
					"\x82\x00" .
					"\x92\x00" .
					"\xd6\x00" .
					"\x10\x00",

			'2' =>	"\xfe\x00" .
					"\x82\x00" .
					"\xd6\x00" .
					"\xd6\x00" .
					"\x54\x00"
		},
		
		'shuffle' => {
			'0' =>	"\x0e\x00" .
					"\x00\x00" .
					"\x1c\x00" .
					"\x00\x00" .
					"\x38\x00" .
					"\x00\x00" .
					"\x70\x00" .
					"\x00\x00" .
					"\xe0\x00",

			'1' =>	"\x38\x00" .
					"\x00\x00" .
					"\x0e\x00" .
					"\xe0\x00" .
					"\x00\x00" .
					"\x1c\x00" .
					"\x00\x00" .
					"\x70\x00" .
					"\x00\x00",

			'2' =>	"\x38\x00" .
					"\x38\x00" .
					"\x38\x00" .
					"\x00\x00" .
					"\x0e\x00" .
					"\x0e\x00" .
					"\xe0\x00" .
					"\xe0\x00" .
					"\x00\x00"
		}
	}
);

sub lines {
	my $client = shift;
	my ( $line1, $line2 );
	$line1 = string('PLUGIN_SCREENSAVER_MUSICINFO');
	if ( $client->prefGet('screensaver') ne 'SCREENSAVER.musicinfo' ) {
		$line2 = string('PLUGIN_SCREENSAVER_MUSICINFO_ENABLE');
	}
	else {
		$line2 = string('PLUGIN_SCREENSAVER_MUSICINFO_DISABLE');
	}

	return {
		'line1' => $line1,
		'line2' => $line2
	};
}

sub getFunctions {
	return \%functions;
}

sub setupGroup {
	my (%formatStrings, %formatStrings2);

	foreach my $formatString ( Slim::Utils::Prefs::getArray('titleFormat') ) {
		$formatStrings{"$formatString"} = $formatString;
		$formatStrings{"$formatString (X_OF_Y)"} = "$formatString (X_OF_Y)";
	}

	# add some special formats...
	$formatStrings{''}         = 'NOTHING';
	$formatStrings{'CURRTIME'} = 'CURRTIME';
	$formatStrings{'PLAYTIME'} = 'PLAYTIME';
	$formatStrings{'PLAYLIST'} = 'PLAYLIST';
	$formatStrings{'PLAYLIST (X_OF_Y)'} = 'PLAYLIST (X_OF_Y)';
	$formatStrings{'NOW_PLAYING'} = 'PLAYING';
	$formatStrings{'NOW_PLAYING (X_OF_Y)'} = 'PLAYING (X_OF_Y)';
	$formatStrings{'(X_OF_Y)'} = '(X_OF_Y)';
	$formatStrings{'PROGRESSBAR'} = 'PROGRESSBAR';

	# Start plugin patch
	no strict 'refs';
	my @plugins = Slim::Buttons::Plugins::enabledPlugins();
	for my $plugin (@plugins) {
		if(UNIVERSAL::can("Plugins::$plugin","getMusicInfoSCRCustomItems") && UNIVERSAL::can("Plugins::$plugin","getMusicInfoSCRCustomItem")) {
			$::d_plugins && Slim::Utils::Misc::msg("MusicInfoSCR: Getting items for: $plugin\n");
			my $items = eval { &{"Plugins::${plugin}::getMusicInfoSCRCustomItems"}() };
			for my $item (keys %$items) {
				$customitems{$item} = "Plugins::${plugin}::getMusicInfoSCRCustomItem";
				$formatStrings{$item} = $items->{$item};
			}
		}
	}
	use strict 'refs';
	# End plugin patch

	my %setupGroup = (
		PrefOrder => [
			'plugin_musicinfo_lineA', 'plugin_musicinfo_overlayA',
			'plugin_musicinfo_lineB', 'plugin_musicinfo_overlayB',
			'plugin_musicinfo_line_dbl', 'plugin_musicinfo_overlay_dbl',
			'plugin_musicinfo_show_icons', 'plugin_musicinfo_jump_back', 
			'plugin_musicinfo_stream_fallback'
		],
		PrefsInTable => 0,
		GroupHead => string('PLUGIN_SCREENSAVER_MUSICINFO'),
		GroupDesc => string('SETUP_GROUP_PLUGIN_SCREENSAVER_MUSICINFO_DESC'),
		GroupLine => 1,
		GroupSub  => 1,
		Suppress_PrefSub  => 1,
		Suppress_PrefLine => 1
	);
	my %setupPrefs = (
		'plugin_musicinfo_lineA'       => { 'options' => \%formatStrings, 'optionSort' => 'V' },
		'plugin_musicinfo_lineB'       => { 'options' => \%formatStrings, 'optionSort' => 'V' },
		'plugin_musicinfo_overlayA'    => { 'options' => \%formatStrings, 'optionSort' => 'V' },
		'plugin_musicinfo_overlayB'    => { 'options' => \%formatStrings, 'optionSort' => 'V' },
		'plugin_musicinfo_line_dbl'    => { 'options' => \%formatStrings, 'optionSort' => 'V' },
		'plugin_musicinfo_overlay_dbl' => { 'options' => \%formatStrings, 'optionSort' => 'V' },
		'plugin_musicinfo_show_icons'  => {
			'options' => {
				''         => string('PLUGIN_SCREENSAVER_MUSICINFO_DONT_SHOW'),
				'TOPLEFT'  => string('SETUP_PLUGIN_MUSICINFO_LINEA'),
				'TOPLEFT2' => string('SETUP_PLUGIN_MUSICINFO_LINEA') . ' ' . string('PLUGIN_SCREENSAVER_MUSICINFO_ICON_ALWAYS'),
				'TOPRIGHT' => string('SETUP_PLUGIN_MUSICINFO_OVERLAYA'),
				'TOPRIGHT2'=> string('SETUP_PLUGIN_MUSICINFO_OVERLAYA') . ' ' . string('PLUGIN_SCREENSAVER_MUSICINFO_ICON_ALWAYS')
			},
#			'PrefChoose' => string('SETUP_PLUGIN_MUSICINFO_SHOW_ICONS')
		},
		'plugin_musicinfo_jump_back'   => {
			'validate' => \&Slim::Web::Setup::validateTrueFalse,
			'options'  => {
				'1' => string('ON'),
				'0' => string('OFF')
			},
			'PrefChoose' => string('SETUP_PLUGIN_MUSICINFO_JUMP_BACK')
		},
		'plugin_musicinfo_stream_fallback'   => {
			'validate' => \&Slim::Web::Setup::validateTrueFalse,
			'options'  => {
				'1' => string('ON'),
				'0' => string('OFF')
			},
			'PrefChoose' => string('SETUP_PLUGIN_MUSICINFO_STREAM_FALLBACK')
		}
	);
	return ( \%setupGroup, \%setupPrefs, 1 );
}

sub screenSaver {
	Slim::Buttons::Common::addSaver( 'SCREENSAVER.musicinfo',
		getScreensaverMusicInfo(), \&setScreensaverMusicInfoMode,
		undef, string('PLUGIN_SCREENSAVER_MUSICINFO') );
}

my %screensaverMusicInfoFunctions = (
	'done' => sub {
		my ( $client, $funct, $functarg ) = @_;
		Slim::Buttons::Common::popMode($client);
  		if (not $client->prefGet('plugin_musicinfo_jump_back')) {	
			if (Slim::Buttons::Common::mode($client) ne 'playlist') {
  				Slim::Buttons::Common::pushMode( $client, 'playlist' );
			}
  		}
		$client->update();

		# pass along ir code to new mode if requested
		if ( defined $functarg && $functarg eq 'passback' ) {
			Slim::Hardware::IR::resendButton($client);
		}
	  }
);

sub getScreensaverMusicInfo {
	return \%screensaverMusicInfoFunctions;
}

sub setScreensaverMusicInfoMode() {
	my $client = shift;
	
	# Start plugin patch
	clearCustomItemCache($client);
	# End plugin patch
	
	# initialize settings if they don't exist yet
	if (not ($client->prefGet('plugin_musicinfo_lineA') || $client->prefGet('plugin_musicinfo_overlayA') ||
			$client->prefGet('plugin_musicinfo_lineB') || $client->prefGet('plugin_musicinfo_overlayB') ||
			$client->prefGet('plugin_musicinfo_line_dlbl') || $client->prefGet('plugin_musicinfo_overlay_dbl') ||
			$client->prefGet('plugin_musicinfo_show_icons'))) {
		$client->prefSet('plugin_musicinfo_lineA', 'ALBUM (ARTIST)');
		$client->prefSet('plugin_musicinfo_overlayA', '(X_OF_Y)');
		$client->prefSet('plugin_musicinfo_lineB', 'TITLE');
		$client->prefSet('plugin_musicinfo_overlayB', 'PLAYTIME');
		$client->prefSet('plugin_musicinfo_line_dbl', 'TOPLEFT2');
		$client->prefSet('plugin_musicinfo_show_icons', 'TOPLEFT2');
	}

	# setting this param will call client->update() frequently
	$client->param('modeUpdateInterval', 1);
	$client->lines( \&screensaverMusicInfoLines );
}

sub screensaverMusicInfoLines {
	my $client = shift;
	my ( $line1, $overlay1, $line2, $overlay2, $bits ) = '';

	# if there's nothing playing just display... nothing!
	if (Slim::Player::Playlist::count($client) < 1) {
		$line1 = string('NOW_PLAYING');
		$line2 = string('NOTHING');
	}
	elsif ( $client->linesPerScreen() == 1 ) {
		$line2 = getFormatString($client, $client->prefGet('plugin_musicinfo_line_dbl') || $client->prefGet('plugin_musicinfo_lineB'));
		$overlay2 = getFormatString($client, $client->prefGet('plugin_musicinfo_overlay_dbl'));
	}
	else {
		$line1 = getFormatString($client, $client->prefGet('plugin_musicinfo_lineA'));
		$overlay1 = getFormatString($client, $client->prefGet('plugin_musicinfo_overlayA'));
		
		# if there's no information for the first line, display the playlistname or "now playing..." 
		# (eg. for author information with online streaming etc.)
		if ($client->prefGet('plugin_musicinfo_lineA') and not $line1) {
			$line1 = getFormatString($client, 'PLAYLIST');
			$line1 = string('NOW_PLAYING') if (not $line1);
		}

		$line2 = getFormatString($client, $client->prefGet('plugin_musicinfo_lineB'));
		$overlay2 = getFormatString($client, $client->prefGet('plugin_musicinfo_overlayB'));
	}
	
	# handle special modes... 
	if (Slim::Player::Source::playmode($client) eq 'pause') {
		$line1 = string('PAUSED') . ($line1 ? ' - ' . $line1 : '');
	}
	elsif (Slim::Player::Source::playmode($client) eq 'stop') {
		$line1 = string('STOPPED') . ($line1 ? ' - ' . $line1 : '');
	}
	
	# Repeat/Shuffle icons - right
	if (my $showIcons = $client->prefGet('plugin_musicinfo_show_icons')) {
		if ($showIcons =~ /^TOPRIGHT[2]*$/) {
			($bits, $overlay1) = buttonIcons($client, $showIcons, $overlay1);
		}
	}

	# visualizer, buffer and PLAYTIME stuff...
	$line1 = getPlayTime($client, $line1, $overlay1, 1);
	$line2 = getPlayTime($client, $line2, $overlay2, 2);

	# Repeat/Shuffle icons - left
	if (my $showIcons = $client->prefGet('plugin_musicinfo_show_icons')) {
		if ($showIcons =~ /^TOPLEFT[2]*$/) {
			($bits, $line1) = buttonIcons($client, $showIcons, $line1);
		}
	}
	
	$overlay1 = getPlayTime($client, $overlay1, $line1, 1);
	$overlay2 = getPlayTime($client, $overlay2, $line2, 2);

	return {
		'line1' => $line1,
		'line2' => $line2,
		'overlay1' => $overlay1,
		'overlay2' => $overlay2,
		'bits' => $bits
	};
}

sub getPlayTime {
	my ($client, $part1, $part2, $line) = @_;
	my %parts;
	
	if ($part1 && ($part1 =~ /PLAYTIME/)) {
		my $withoutTag = $part1;
		$withoutTag =~ s/PLAYTIME//;

		if ($line == 2) {
			# pad string if left part is smaller than half the display size
			if ($client->measureText($part2, $line) < ($client->displayWidth()/2)) {
				$part2 = pack('A' . int(($client->displayWidth() / 1.7) / $client->measureText(' ', 1)), ' ');
			}
			else {
				$part2 = pack('A' . int($client->measureText("$part2  X", 2) / $client->measureText(' ', 1)), ' ');
			}
		}
		else {
			$part2 .= ' ';
		}

		$parts{'line1'} = $part2 . $withoutTag;
		$client->nowPlayingModeLines( \%parts );
		# if it's a time like 11938293:23:03 only display mm:ss
		$parts{'overlay1'} =~ /(\d{3,}):(\d\d:\d\d)/ if (defined $parts{'overlay1'});
		if (defined $1 and defined $2) {
			$part1 = s/PLAYTIME/$2/; 
		}
		else {
			$part1 =~ s/PLAYTIME/$parts{'overlay1'}/;
		}
	# use match so we get just the progress bar even if paused/stopped
	} elsif ($part1 and ($part1 =~ /PROGRESSBAR/)) {
		if (Slim::Player::Source::playingSongDuration($client)) {
			# below copied from nowPlayingModeLines, otherwise would have to reset the now playing mode
			my $withoutTag = $part1;
			$withoutTag =~ s/PROGRESSBAR//;
			$part2 .= ' ' . $withoutTag if ($part2);
			my $fractioncomplete = Slim::Player::Source::progress($client);
			my $barlen = $client->displayWidth() - $client->measureText($part2, $line);
			
			# in single line mode (double sized font), half the length - progressBar does not seem to be aware of this
			$barlen /= 2 if (not $client->measureText(' ', 1));
			$part2 = $client->symbols($client->progressBar($barlen, $fractioncomplete));
			$part1 =~ s/PROGRESSBAR/$part2/;
		} else {
			# don't print anything if there's no duration
			$part1 =~ s/PROGRESSBAR//;
		}
	}
	
	# remove trailing/leading blanks
	$part1 =~ s/^\s*(\S*)\s$/$1/;
	return $part1;
}

sub getFormatString {
	my $client = shift;
	my $formatString = shift;
	my $formattedString = $formatString;
	my $isRemote;
	my $songKey;

	my $ref = $displayCache{$client}->{$formatString} ||= {
		'songkey' => '',
		'formattedString' => ''
	};

	# see if the string is already in the cache
	my $song = $songKey = Slim::Player::Playlist::song($client);

	if ($isRemote = Slim::Music::Info::isRemoteURL($song)) {
		$songKey = Slim::Music::Info::getCurrentTitle($client, $song);
	}
	
	if ($songKey ne $ref->{'songkey'}) { 
		$ref = $displayCache{$client}->{$formatString} = {
			'formattedString'  => ''
		};

#		$::d_plugins && Slim::Utils::Misc::msg("MusicInfoSCR: new song? '$songKey'\n");
		my $albumOrArtist = ($formatString =~ /(ALBUM|ARTIST)/i);
		
		# "Now playing..."
		my $string = string('PLAYING');
		$formattedString =~ s/NOW_PLAYING/$string/g;
		
		# Playlistname
		if ($formatString =~ /PLAYLIST/) {
			if ($string = $client->currentPlaylist()) {
				$string = Slim::Music::Info::standardTitle($client, $string);
			}
			else {
				$string = '';
			}
			$formattedString =~ s/PLAYLIST/$string/g;
		}
		
		# Song counter
		if ($formattedString =~ /X_OF_Y/) {
			$string = sprintf("%d %s %d", Slim::Player::Source::playingSongIndex($client) + 1, string('OUT_OF'), Slim::Player::Playlist::count($client));
			$formattedString =~ s/X_OF_Y/$string/g;
		}
	
		# Title: as infoFormat() seems to give us some problems with internet radio stations, we'll handle this manually...
		if (($formatString =~ /TITLE/) && Slim::Music::Info::isRemoteURL($song)) {
			$string = Slim::Music::Info::getCurrentTitle($client, $song);
			$formattedString =~ s/TITLE/$string/g;
		}
		
		if ($formatString !~ /(PLAYLIST|PLAYTIME|NOW_PLAYING)/) {
#			$::d_plugins && Slim::Utils::Misc::msg("MusicInfoSCR: format '$formattedString'\n");
			$formattedString = Slim::Music::TitleFormatter::infoFormat($song, $formattedString);
#			$::d_plugins && Slim::Utils::Misc::msg("MusicInfoSCR: '$formattedString'\n");
		}
		
		# Start plugin patch
		$formattedString = getCustomItem($client,$formattedString);
		# End plugin patch
			
		# if ARTIST/ALBUM etc. is empty, replace them by some "Now playing..."
		if ($albumOrArtist) {
			my $tmpFormattedString = $formattedString;
			my $noArtist = string('NO_ARTIST');
			my $noAlbum = string('NO_ALBUM');
			$tmpFormattedString =~ s/($noAlbum|$noArtist|No Album|No Artist)//ig;
			$tmpFormattedString =~ s/\W//g;
#			$::d_plugins && Slim::Utils::Misc::msg("MusicInfoSCR ($client): empty artist/album? '$tmpFormattedString'\n");
	
			if (! $tmpFormattedString) {
				# Fallback for streams: display playlist name (if available)
				if ($client->currentPlaylist() && $client->prefGet('plugin_musicinfo_stream_fallback') && ($string = Slim::Music::Info::standardTitle($client, $client->currentPlaylist()))) {
#					$::d_plugins && Slim::Utils::Misc::msg("MusicInfoSCR ($client): " . $client->currentPlaylist() . "\n");
#					$::d_plugins && Slim::Utils::Misc::msg("MusicInfoSCR ($client): " . Slim::Music::Info::standardTitle($client, $client->currentPlaylist()) . "\n");
#					$::d_plugins && Slim::Utils::Misc::msg("MusicInfoSCR ($client): let's try to get the playlist name '$string'\n");
					$formattedString = $string;
				}
				else {
					$::d_plugins && Slim::Utils::Misc::msg("MusicInfoSCR ($client): there seems to be nothing left...\n");
					$formattedString = '';
				}
			}
		}

		# store the formatted string in cache
		$ref = $displayCache{$client}->{$formatString} = {
			'songkey' => $songKey,
			'formattedString'  => $formattedString
		};
		
		# force first update
#		$::d_plugins && Slim::Utils::Misc::msg("MusicInfoSCR ($client): do an initial update for the new song\n");
		$client->update();
	}
	# current time has always to be updated
	elsif ($formattedString eq 'CURRTIME') {
		$ref->{'formattedString'} = Slim::Utils::Misc::timeF();
	}
	
	return $ref->{'formattedString'};
}

sub buttonIcons {
	my ($client, $position, $line) = @_;
	
	my $playerType;
	
	if ($client->isa('Slim::Player::Squeezebox2')) {
		$playerType = 'sb2';
	}
	elsif ($client->isa('Slim::Player::SqueezeboxG')) {
		$playerType = 'sbg';
	}
	
	# return empty values if non graphical display
	return if (not $playerType);

	my $shuffleState = $client->getPref('shuffle');
	my $repeatState = $client->getPref('repeat');

	if (($shuffleState ne $displayCache{$client}->{'shuffle'})
	 || ($repeatState ne $displayCache{$client}->{'repeat'})
	 || ($line ne $displayCache{$client}->{'line'})
	 || ($position ne $displayCache{$client}->{'position'})
	 || ($client->displayWidth() != $displayCache{$client}->{'displayWidth'})) {
		my $bits = '';

		if ($shuffleState || ($position =~ /TOP(LEFT|RIGHT)2/)) {
			$bits .= $icons{$playerType}->{'shuffle'}->{$shuffleState};
			$bits .= $icons{$playerType}->{'space'};
		}

		if ($repeatState || ($position =~ /TOP(LEFT|RIGHT)2/)) {
			$bits .= $icons{$playerType}->{'repeat'}->{$repeatState};
			$bits .= $icons{$playerType}->{'space'};
		}

		my $width = (length($bits) / ($client->displayHeight() / 8));
		if ($position =~ /RIGHT/) {
			for (my $i = 0; $i < ($client->displayWidth() - $width + 2); $i++) {
				$bits = $icons{$playerType}->{'blank'} . $bits;
			}
		}
		elsif ($position =~ /LEFT/) {
			for(my $i = 0; $i < ($client->measureText($line, 1) + 4); $i++) {
				$bits = $icons{$playerType}->{'blank'} . $bits;
			}
		}
		$displayCache{$client}->{'repeat'} = $repeatState;
		$displayCache{$client}->{'shuffle'} = $shuffleState;
		$displayCache{$client}->{'position'} = $position;
		$displayCache{$client}->{'line'} = $line;
		$displayCache{$client}->{'icons'} = $bits;
		$displayCache{$client}->{'width'} = ($width / 4);
		$displayCache{$client}->{'displayWidth'} = $client->displayWidth();
	}

	# dirty trick not to have stuff shine through the bitmap: display some empty text...
	return ($displayCache{$client}->{'icons'}, $line . ("\x00" x ($displayCache{$client}->{'width'})));
}

# Start plugin patch
sub getCustomItem()
{
	my $client = shift;
	my $formattedString = shift;

	no strict 'refs';

	for my $item (keys %customitems) {
		my $method = %customitems->{$item};
		if ($formattedString =~ /$item/) {
			$::d_plugins && Slim::Utils::Misc::msg("MusicInfoSCR ($client): Getting custom info for $item from: $method\n");
			$formattedString = eval { &{"${method}"}($client,$formattedString) };
		}
	}
	return $formattedString;
}
sub clearCustomItemCache()
{
	my $client = shift;

	no strict 'refs';

	for my $item (keys %customitems) {
		$displayCache{$client}->{$item} = {
			'songkey' => '',
			'formattedString' => ''
		};
	}
}
# End plugin patch

sub strings { return q^
PLUGIN_SCREENSAVER_MUSICINFO
	DE	Musik-Info Bildschirmschoner
	EN	Music Info Screensaver
	FR	Écran de veille Info Musique
	
PLUGIN_SCREENSAVER_MUSICINFO_ENABLE
	DE	PLAY drücken zum Aktivieren des Bildschirmschoners
	EN	Press PLAY to enable this screensaver
	FR	Appuyer sur PLAY pour activer

PLUGIN_SCREENSAVER_MUSICINFO_DISABLE
	DE	PLAY drücken zum Deaktivieren dieses Bildschirmschoners 
	EN	Press PLAY to disable this screensaver
	FR	Appuyer sur PLAY pour désactiver
	
PLUGIN_SCREENSAVER_MUSICINFO_ENABLING
	DE	Musik-Info Bildschirmschoner aktivieren
	EN	Enabling MusicInfo as current screensaver
	FR	Activation écran de veille Info Musique

PLUGIN_SCREENSAVER_MUSICINFO_DISABLING
	DE	Standard-Bildschirmschoner aktivieren
	EN	Resetting to default screensaver
	FR	Retour à l'écran de veille par défaut

PLUGIN_SCREENSAVER_MUSICINFO_CURRENTTIME
	DE	Aktuelle Uhrzeit
	EN	Current Time
	FR	Heure actuelle

PLUGIN_SCREENSAVER_MUSICINFO_ICON_ALWAYS
	DE	(immer zeigen)
	EN	(show always)

PLUGIN_SCREENSAVER_MUSICINFO_DONT_SHOW
	DE	Nicht anzeigen
	EN	Don't show icons

SETUP_GROUP_PLUGIN_SCREENSAVER_MUSICINFO_DESC
	DE	Wählen Sie hier die Formate, die zur Anzeige der Musikinformationen im Bildschirmschoner verwendet werden sollen. Weitere Formate können unter "Server Einstellungen/Formatierung/Titelformat" definiert werden.
	EN	Please select the title format you want to use for the screensaver. You can add more format definitions under "Server Settings/Formatting/Title Format".
	FR	Vous pouvez spécifier le format d'affichage du titre de l'économiseur d'écran sur votre platine en choisissant parmi les menus ci-dessous. Vous pouvez ajouter des formats d'affichage dans les réglages du serveur.

SETUP_GROUP_PLUGIN_SCREENSAVER_MUSICINFO_DBL_DESC
	DE	Wählen Sie hier die Formate, die zur Anzeige der Musikinformationen im Bildschirmschoner verwendet werden sollen, falls Sie die doppelte Schriftgrösse verwenden und daher nur eine Zeile angezeigt wird.
	EN	Please select the title format you want to use for the screensaver when using huge (double size) fonts only allowing for one single line to display.
	FR	Vous pouvez également spécifier le format d'affichage du titre de l'économiseur d'écran pour utilisation avec une grand police (une ligne seule).

SETUP_PLUGIN_MUSICINFO_LINE_DBL
	DE	Doppelte Höhe (eine Zeile), links
	EN	Huge font (single line), left
	FR	Large police (une seule ligne), gauche

SETUP_PLUGIN_MUSICINFO_OVERLAY_DBL
	DE	Doppelte Höhe (eine Zeile), rechts
	EN	Huge font (single line), right
	FR	Large police (une seule ligne), droite

SETUP_PLUGIN_MUSICINFO_LINEA
	DE	Oben links
	EN	Top left
	FR	Ligne 1, gauche

SETUP_PLUGIN_MUSICINFO_OVERLAYA
	DE	Oben rechts
	EN	Top right
	FR	Ligne 1, droite

SETUP_PLUGIN_MUSICINFO_LINEB
	DE	Unten links
	EN	Bottom left
	FR	Ligne 2, gauche

SETUP_PLUGIN_MUSICINFO_OVERLAYB
	DE	Unten rechts
	EN	Bottom right
	FR	Ligne 1, droite

SETUP_PLUGIN_MUSICINFO_JUMP_BACK
	DE	Beim Aufwachen zurückspringen
	EN	Jump back on wake
	FR	Retour veille

SETUP_PLUGIN_MUSICINFO_JUMP_BACK_DESC
	DE	Legen Sie fest, ob das Display beim Aufwachen dorthin zurückspringen soll, wo Sie sich zuletzt befanden. Falls dies deaktiviert ist, landen Sie automatisch im Playlist-Bereich ("Es läuft gerade...").
	EN	Define whether you want to jump back on wake. If you disable this you will be brought to the "Now playing..." menu.

SETUP_PLUGIN_MUSICINFO_STREAM_FALLBACK
	DE	Bei Online Streams Playlist-Name anzeigen
	EN	Display playlist name for radio stations

SETUP_PLUGIN_MUSICINFO_STREAM_FALLBACK_DESC
	DE	Bei Online Streams stehen Interpreten- und Albumname oft nicht zur Verfügung. Soll in einem solchen Fall an Stelle eines leeren Feldes versucht werden, den Playlist-Namen anzuzeigen?
	EN	Online streams often don't differentiate song-, album- or artistname. This can result in an empty string. Should empty strings be replaced by the playlist name (if available)?

SETUP_PLUGIN_MUSICINFO_SHOW_ICONS
	DE	Symbole für zufällige/wiederholte Wiedergabe anzeigen
	EN	Show icons for Repeat/Shuffle
^;
}

1;
