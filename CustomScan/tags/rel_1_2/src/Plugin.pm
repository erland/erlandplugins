# 				CustomScan plugin 
#
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
#
#    The LastFM scanning module uses the webservices from audioscrobbler.
#    Please respect audioscrobbler terms of service, the content of the 
#    feeds are licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License
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

package Plugins::CustomScan::Plugin;

use strict;

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use POSIX qw(ceil);
use File::Spec::Functions qw(:ALL);
use DBI qw(:sql_types);
use FindBin qw($Bin);
use Plugins::CustomScan::Time::Stopwatch;

my $albums = ();
my $artists = ();
my $tracks = ();
my $scanningInProgress = 0;

my $modules = ();
my @pluginDirs = ();

# Indicator if hooked or not
# 0= No
# 1= Yes
my $CUSTOMSCAN_HOOK = 0;


sub getDisplayName {
	return 'PLUGIN_CUSTOMSCAN';
}

sub setMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
}



sub initPlugin {
	my $class = shift;
	initDatabase();
	if ( !$CUSTOMSCAN_HOOK ) {
		refreshTitleFormats();
		installHook();
	}

	checkDefaults();
}

sub shutdownPlugin {
        debugMsg("disabling\n");
        if ($CUSTOMSCAN_HOOK) {
                uninstallHook();
        }
}

# Hook the plugin to the play events.
# Do this as soon as possible during startup.
sub installHook()
{  
	debugMsg("Hook activated.\n");
	Slim::Control::Request::subscribe(\&Plugins::CustomScan::Plugin::commandCallback,[['rescan']]);
	$CUSTOMSCAN_HOOK=1;
}

# Unhook the plugin's play event callback function. 
# Do this as the plugin shuts down, if possible.
sub uninstallHook()
{
	debugMsg("Hook deactivated.\n");
	Slim::Control::Request::unsubscribe(\&Plugins::CustomScan::Plugin::commandCallback);
	$CUSTOMSCAN_HOOK=0;
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

sub commandCallback($) 
{
	debugMsg("Entering commandCallback\n");
	# These are the two passed parameters
	my $request=shift;
	my $client = $request->client();

	######################################
	## Rescan finished
	######################################
	if ( $request->isCommand([['rescan'],['done']]) )
	{
		if(Slim::Utils::Prefs::get("plugin_customscan_auto_rescan")) {
			fullRescan();
		}elsif(Slim::Utils::Prefs::get("plugin_customscan_refresh_rescan")) {
			refreshData();
		}

	}
	debugMsg("Exiting commandCallback\n");
}

sub checkDefaults {

	my $prefVal = Slim::Utils::Prefs::get('plugin_customscan_showmessages');
	if (! defined $prefVal) {
		debugMsg("Defaulting plugin_customscan_showmessages to 0\n");
		Slim::Utils::Prefs::set('plugin_customscan_showmessages', 0);
	}

	if(!defined(Slim::Utils::Prefs::get("plugin_customscan_refresh_startup"))) {
		Slim::Utils::Prefs::set("plugin_customscan_refresh_startup",1);
	}
	if(!defined(Slim::Utils::Prefs::get("plugin_customscan_refresh_rescan"))) {
		Slim::Utils::Prefs::set("plugin_customscan_refresh_rescan",1);
	}
	if(!defined(Slim::Utils::Prefs::get("plugin_customscan_auto_rescan"))) {
		Slim::Utils::Prefs::set("plugin_customscan_auto_rescan",1);
	}
	if (!defined(Slim::Utils::Prefs::get('plugin_customscan_properties'))) {
		debugMsg("Defaulting plugin_scan_properties\n");
		my @properties = ();
		push @properties, 'customtags=OWNER,ORIGIN';
		push @properties, 'singlecustomtags=ORIGIN';
		push @properties, 'lastfmsimilarartistpercent=80';
		push @properties, 'lastfmtagspercent=10';
		Slim::Utils::Prefs::set('plugin_customscan_properties', \@properties);
	}else {
	        my @properties = Slim::Utils::Prefs::getArray('plugin_customscan_properties');
		my $singlecustomtag = undef;
		for my $property (@properties) {
			if($property =~ /^singlecustomtags=/) {
				$singlecustomtag = 1;
			}
		}
		if(!$singlecustomtag) {
			Slim::Utils::Prefs::push('plugin_customscan_properties', 'singlecustomtags=ORIGIN');
		}
	}
	if (!defined(Slim::Utils::Prefs::get('plugin_customscan_titleformats'))) {
		my @titleFormats = ();
		Slim::Utils::Prefs::set('plugin_customscan_titleformats', \@titleFormats);
	}
}

sub getPluginModules {
	my %plugins = ();
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		my $dir = catdir($plugindir,"CustomScan","Modules");
		next unless -d $dir;
		my @dircontents = Slim::Utils::Misc::readDirectory($dir,"pm");
		for my $plugin (@dircontents) {
			if ($plugin =~ s/(.+)\.pm$/$1/i) {
				my $fullname = "Plugins::CustomScan::Modules::$plugin";
				no strict 'refs';
				eval "use $fullname";
				if ($@) {
					msg("CustomScan: Failed to load module $fullname: $@\n");
				}elsif(UNIVERSAL::can("${fullname}","getCustomScanFunctions")) {
					my $data = eval { &{$fullname . "::getCustomScanFunctions"}(); };
					if ($@) {
						msg("CustomScan: Failed to call module $fullname: $@\n");
					}elsif(defined($data) && defined($data->{'id'}) && defined($data->{'name'})) {
						$plugins{$fullname} = $data;
						my $enabled = Slim::Utils::Prefs::get('plugin_customscan_module_'.$data->{'id'}.'_enabled');
						if(!defined($enabled) || $enabled) {
							$plugins{$fullname}->{'enabled'} = 1;
						}else {
							$plugins{$fullname}->{'enabled'} = 0;
						}
					}
				}
				use strict 'refs';
			}
		}
	}
	my @enabledplugins = Slim::Utils::PluginManager::enabledPlugins();
	for my $plugin (@enabledplugins) {
		my $fullname = "Plugins::$plugin";
		no strict 'refs';
		eval "use $fullname";
		if ($@) {
			msg("CustomScan: Failed to load module $fullname: $@\n");
		}elsif(UNIVERSAL::can("${fullname}","getCustomScanFunctions")) {
			my $data = eval { &{$fullname . "::getCustomScanFunctions"}(); };
			if ($@) {
				msg("CustomScan: Failed to load module $fullname: $@\n");
			}elsif(defined($data) && defined($data->{'id'}) && defined($data->{'name'})) {
				$plugins{$fullname} = $data;
				my $enabled = Slim::Utils::Prefs::get('plugin_customscan_module_'.$data->{'id'}.'_enabled');
				if(!defined($enabled) || $enabled) {
					$plugins{$fullname}->{'enabled'} = $enabled;
				}else {
					$plugins{$fullname}->{'enabled'} = 0;
				}
			}
		}
		use strict 'refs';
	}
	return \%plugins;
}

sub fullRescan {
	debugMsg("Performing rescan\n");
	$albums = undef;
	$artists = undef;
	$tracks = undef;
	
	if($scanningInProgress) {
		msg("CustomScan: Scanning already in progress, wait until its finished\n");
		return 0;
	}
	refreshData();

	$scanningInProgress = 1;
	$modules = getPluginModules();

	for my $key (keys %$modules) {
		my $module = $modules->{$key};
		if($module->{'enabled'} && defined($module->{'scanInit'})) {
			no strict 'refs';
			debugMsg("Calling: scanInit on $key\n");
			eval { &{$module->{'scanInit'}}(); };
			if ($@) {
				msg("CustomScan: Failed to call scanInit on module $key: $@\n");
			}
			use strict 'refs';
		}
	}
	initArtistScan();
	return 1;
}
sub moduleRescan {
	my $moduleKey = shift;
	
	if($scanningInProgress) {
		msg("CustomScan: Scanning already in progress, wait until its finished\n");
		return 0;
	}
	refreshData();
	debugMsg("Performing module rescan\n");
	if(!$modules) {
		$modules = getPluginModules();
	}
	my $module = $modules->{$moduleKey};
	if(defined($module) && defined($module->{'id'})) {
		$scanningInProgress = 1;
		if(defined($module->{'scanInit'})) {
			no strict 'refs';
			debugMsg("Calling: scanInit on $moduleKey\n");
			eval { &{$module->{'scanInit'}}(); };
			if ($@) {
				msg("CustomScan: Failed to call scanInit on module $moduleKey: $@\n");
			}
			use strict 'refs';
		}
		initArtistScan($moduleKey);
	}
	return 1;
}

sub moduleClear {
	if($scanningInProgress) {
		msg("CustomScan: Scanning already in progress, wait until its finished\n");
		return 0;
	}
	debugMsg("Performing module clear\n");
	my $moduleKey = shift;
	if(!$modules) {
		$modules = getPluginModules();
	}
	my $module = $modules->{$moduleKey};
	if(defined($module) && defined($module->{'id'})) {
		eval {
			my $dbh = getCurrentDBH();
			my $sth = $dbh->prepare("DELETE FROM customscan_contributor_attributes where module=?");
			$sth->bind_param(1,$module->{'id'},SQL_VARCHAR);
			$sth->execute();
			commit($dbh);
			$sth->finish();
	
			$sth = $dbh->prepare("DELETE FROM customscan_album_attributes where module=?");
			$sth->bind_param(1,$module->{'id'},SQL_VARCHAR);
			$sth->execute();
			commit($dbh);
			$sth->finish();
	
			$sth = $dbh->prepare("DELETE FROM customscan_track_attributes where module=?");
			$sth->bind_param(1,$module->{'id'},SQL_VARCHAR);
			$sth->execute();
			commit($dbh);
			$sth->finish();
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n$@\n";
		}
	}
}

sub fullClear {
	if($scanningInProgress) {
		msg("CustomScan: Scanning already in progress, wait until its finished\n");
		return 0;
	}
	debugMsg("Performing full clear\n");
	eval {
		my $dbh = getCurrentDBH();
		my $sth = $dbh->prepare("DELETE FROM customscan_contributor_attributes");
		$sth->execute();
		commit($dbh);
		$sth->finish();

		$sth = $dbh->prepare("ALTER TABLE customscan_contributor_attributes AUTO_INCREMENT=0");
		$sth->execute();
		commit($dbh);
		$sth->finish();

		$sth = $dbh->prepare("DELETE FROM customscan_album_attributes");
		$sth->execute();
		commit($dbh);
		$sth->finish();

		$sth = $dbh->prepare("ALTER TABLE customscan_album_attributes AUTO_INCREMENT=0");
		$sth->execute();
		commit($dbh);
		$sth->finish();

		$sth = $dbh->prepare("DELETE FROM customscan_track_attributes");
		$sth->execute();
		commit($dbh);
		$sth->finish();

		$sth = $dbh->prepare("ALTER TABLE customscan_track_attributes AUTO_INCREMENT=0");
		$sth->execute();
		commit($dbh);
		$sth->finish();
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n$@\n";
	}
}

sub exitScan {
	my $moduleKey = shift;
	my @moduleKeys = ();
	if(defined($moduleKey)) {
		push @moduleKeys,$moduleKey;
	}else {
		for my $key (keys %$modules) {
			if($modules->{$key}->{'enabled'}) {
				push @moduleKeys,$key;
			}
		}
	}
	for my $key (@moduleKeys) {
		my $module = $modules->{$key};
		if(defined($module->{'scanExit'})) {
			no strict 'refs';
			debugMsg("Calling: scanExit on $key\n");
			eval { &{$module->{'scanExit'}}(); };
			if ($@) {
				msg("CustomScan: Failed to call scanExit on module $key: $@\n");
			}
			use strict 'refs';
		}
	}
	$scanningInProgress = 0;
	debugMsg("Rescan finished\n");
}

sub initArtistScan {
	my $moduleKey = shift;
	$artists = Slim::Schema->resultset('Contributor');
	debugMsg("Got ".$artists->count." artists\n");
	my $dbh = getCurrentDBH();
	my @moduleKeys = ();
	if(defined($moduleKey)) {
		push @moduleKeys,$moduleKey;
	}else {
		for my $key (keys %$modules) {
			if($modules->{$key}->{'enabled'}) {
				push @moduleKeys,$key;
			}
		}
	}
	for my $key (@moduleKeys) {
		my $module = $modules->{$key};
		my $moduleId = $key;
		my $moduleId = $module->{'id'};
		if(defined($module->{'scanArtist'}) && defined($module->{'alwaysRescanArtist'}) && $module->{'alwaysRescanArtist'}) {
			debugMsg("Clearing artist data for ".$moduleId."\n");
			eval {
				my $sth = $dbh->prepare("DELETE FROM customscan_contributor_attributes where module=".$dbh->quote($moduleId));
				$sth->execute();
				commit($dbh);
				$sth->finish();
			};
			if( $@ ) {
			    warn "Database error: $DBI::errstr\n$@\n";
			    eval {
			    	rollback($dbh); #just die if rollback is failing
			    };
		   	}
		}
	}
	Slim::Utils::Scheduler::add_task(\&scanArtist,$moduleKey);
}

sub initAlbumScan {
	my $moduleKey = shift;
	$albums = Slim::Schema->resultset('Album');
	debugMsg("Got ".$albums->count." albums\n");
	my $dbh = getCurrentDBH();
	my @moduleKeys = ();
	if(defined($moduleKey)) {
		push @moduleKeys,$moduleKey;
	}else {
		for my $key (keys %$modules) {
			if($modules->{$key}->{'enabled'}) {
				push @moduleKeys,$key;
			}
		}
	}
	for my $key (@moduleKeys) {
		my $module = $modules->{$key};
		my $moduleId = $module->{'id'};
		if(defined($module->{'scanAlbum'}) && defined($module->{'alwaysRescanAlbum'}) && $module->{'alwaysRescanAlbum'}) {
			debugMsg("Clearing album data for ".$moduleId."\n");
			eval {
				my $sth = $dbh->prepare("DELETE FROM customscan_album_attributes where module=".$dbh->quote($moduleId));
				$sth->execute();
				commit($dbh);
				$sth->finish();
			};
			if( $@ ) {
			    warn "Database error: $DBI::errstr\n";
			    eval {
			    	rollback($dbh); #just die if rollback is failing
			    };
		   	}
		}
	}
	Slim::Utils::Scheduler::add_task(\&scanAlbum,$moduleKey);
}

sub initTrackScan {
	my $moduleKey = shift;
	$tracks = Slim::Schema->resultset('Track');
	debugMsg("Got ".$tracks->count." tracks\n");
	my $dbh = getCurrentDBH();
	my @moduleKeys = ();
	if(defined($moduleKey)) {
		push @moduleKeys,$moduleKey;
	}else {
		for my $key (keys %$modules) {
			if($modules->{$key}->{'enabled'}) {
				push @moduleKeys,$key;
			}
		}
	}
	for my $key (@moduleKeys) {
		my $module = $modules->{$key};
		my $moduleId = $module->{'id'};
		if(defined($module->{'scanTrack'}) && defined($module->{'alwaysRescanTrack'}) && $module->{'alwaysRescanTrack'}) {
			debugMsg("Clearing track data for ".$moduleId."\n");
			eval {
				my $sth = $dbh->prepare("DELETE FROM customscan_track_attributes where module=".$dbh->quote($moduleId));
				$sth->execute();
				commit($dbh);
				$sth->finish();
			};
			if( $@ ) {
			    warn "Database error: $DBI::errstr\n";
			    eval {
			    	rollback($dbh); #just die if rollback is failing
			    };
		   	}
		}
	}
	Slim::Utils::Scheduler::add_task(\&scanTrack,$moduleKey);
}

sub scanArtist {
	my $moduleKey = shift;
	my $artist = undef;
	if($artists) {
		$artist = $artists->next;
		if(defined($artist) && $artist->id eq Slim::Schema->variousArtistsObject->id) {
			msg("CustomScan: Skipping artist ".$artist->name."\n");
			$artist = $artists->next;
		}
	}
	if(defined($artist)) {
		my $dbh = getCurrentDBH();
		#debugMsg("Scanning artist: ".$artist->name."\n");
		my @moduleKeys = ();
		if(defined($moduleKey)) {
			push @moduleKeys,$moduleKey;
		}else {
			for my $key (keys %$modules) {
				if($modules->{$key}->{'enabled'}) {
					push @moduleKeys,$key;
				}
			}
		}
		for my $key (@moduleKeys) {
			my $module = $modules->{$key};
			my $moduleId = $module->{'id'};
			if(defined($module->{'scanArtist'})) {
				my $scan = 1;
				if(!defined($module->{'alwaysRescanArtist'}) || !$module->{'alwaysRescanArtist'}) {
					my $sth = $dbh->prepare("SELECT id from customscan_contributor_attributes where module=? and contributor=?");
					$sth->bind_param(1,$moduleId,SQL_VARCHAR);
					$sth->bind_param(2, $artist->id , SQL_INTEGER);
					$sth->execute();
					if($sth->fetch()) {
						$scan = 0;
					}
					$sth->finish();
				}
				if($scan) {
					no strict 'refs';
					#debugMsg("Calling: ".$plugin."::scanArtist\n");
					my $attributes = eval { &{$module->{'scanArtist'}}($artist); };
					if ($@) {
						msg("CustomScan: Failed to call scanArtist on module $key: $@\n");
					}
					use strict 'refs';
					if($attributes && scalar(@$attributes)>0) {
						for my $attribute (@$attributes) {
							my $sql = undef;
							$sql = "INSERT INTO customscan_contributor_attributes (contributor,name,musicbrainz_id,module,attr,value) values (?,?,?,?,?,?)";

							my $sth = $dbh->prepare( $sql );
							eval {
								$sth->bind_param(1, $artist->id , SQL_INTEGER);
								$sth->bind_param(2, $artist->name , SQL_VARCHAR);
								if($artist->musicbrainz_id =~ /.+-.+/) {
									$sth->bind_param(3,  $artist->musicbrainz_id, SQL_VARCHAR);
								}else {
									$sth->bind_param(3,  undef, SQL_VARCHAR);
								}
								$sth->bind_param(4, $moduleId, SQL_VARCHAR);
								$sth->bind_param(5, $attribute->{'name'}, SQL_VARCHAR);
								$sth->bind_param(6, $attribute->{'value'} , SQL_VARCHAR);
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
					}
				}
			}
		}
		return 1;
	}
	initAlbumScan($moduleKey);
	return 0;
}

sub scanAlbum {
	my $moduleKey = shift;
	my $album = undef;
	if($albums) {
		$album = $albums->next;
		while(defined($album) && (!$album->title || $album->title eq string('NO_ALBUM'))) {
			if($album->title) {
				msg("CustomScan: Skipping album ".$album->title."\n");
			}else {
				msg("CustomScan: Skipping album with no title\n");
			}
			$album = $albums->next;
		}
	}
	if(defined($album)) {
		my $dbh = getCurrentDBH();
		#debugMsg("Scanning album: ".$album->title."\n");
		my @moduleKeys = ();
		if(defined($moduleKey)) {
			push @moduleKeys,$moduleKey;
		}else {
			for my $key (keys %$modules) {
				if($modules->{$key}->{'enabled'}) {
					push @moduleKeys,$key;
				}
			}
		}
		for my $key (@moduleKeys) {
			my $module = $modules->{$key};
			my $moduleId = $module->{'id'};
			if(defined($module->{'scanAlbum'})) {
				my $scan = 1;
				if(!defined($module->{'alwaysRescanAlbum'}) || !$module->{'alwaysRescanAlbum'}) {
					my $sth = $dbh->prepare("SELECT id from customscan_album_attributes where module=? and album=?");
					$sth->bind_param(1,$moduleId,SQL_VARCHAR);
					$sth->bind_param(2, $album->id , SQL_INTEGER);
					$sth->execute();
					if($sth->fetch()) {
						$scan = 0;
					}
					$sth->finish();
				}
				if($scan) {
					no strict 'refs';
					#debugMsg("Calling: ".$plugin."::scanAlbum\n");
					my $attributes = eval { &{$module->{'scanAlbum'}}($album); };
					if ($@) {
						msg("CustomScan: Failed to call scanAlbum on module $key: $@\n");
					}
					use strict 'refs';
					if($attributes && scalar(@$attributes)>0) {
						for my $attribute (@$attributes) {
							my $sql = undef;
							$sql = "INSERT INTO customscan_album_attributes (album,title,musicbrainz_id,module,attr,value) values (?,?,?,?,?,?)";
							my $sth = $dbh->prepare( $sql );
							eval {
								$sth->bind_param(1, $album->id , SQL_INTEGER);
								$sth->bind_param(2, $album->title , SQL_VARCHAR);
								if($album->musicbrainz_id =~ /.+-.+/) {
									$sth->bind_param(3,  $album->musicbrainz_id, SQL_VARCHAR);
								}else {
									$sth->bind_param(3,  undef, SQL_VARCHAR);
								}
								$sth->bind_param(4, $moduleId, SQL_VARCHAR);
								$sth->bind_param(5, $attribute->{'name'}, SQL_VARCHAR);
								$sth->bind_param(6, $attribute->{'value'} , SQL_VARCHAR);
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
					}
				}
			}
		}
		return 1;
	}
	initTrackScan($moduleKey);
	return 0;
}

sub scanTrack {
	my $moduleKey = shift;
	my $track = undef;
	if($tracks) {
		$track = $tracks->next;
		while(defined($track) && !$track->audio) {
			msg("CustomScan: Skipping track ".$track->title."\n");
			$track = $tracks->next;
		}
	}
	if(defined($track)) {
		my $dbh = getCurrentDBH();
		#debugMsg("Scanning track: ".$track->title."\n");
		my @moduleKeys = ();
		if(defined($moduleKey)) {
			push @moduleKeys,$moduleKey;
		}else {
			for my $key (keys %$modules) {
				if($modules->{$key}->{'enabled'}) {
					push @moduleKeys,$key;
				}
			}
		}
		for my $key (@moduleKeys) {
			my $module = $modules->{$key};
			my $moduleId = $module->{'id'};
			if(defined($module->{'scanTrack'})) {
				my $scan = 1;
				if(!defined($module->{'alwaysRescanTrack'}) || !$module->{'alwaysRescanTrack'}) {
					my $sth = $dbh->prepare("SELECT id from customscan_track_attributes where module=? and track=?");
					$sth->bind_param(1,$moduleId,SQL_VARCHAR);
					$sth->bind_param(2, $track->id , SQL_INTEGER);
					$sth->execute();
					if($sth->fetch()) {
						$scan = 0;
					}
					$sth->finish();
				}
				if($scan) {
					no strict 'refs';
					#debugMsg("Calling: ".$plugin."::scanTrack\n");
					my $attributes = eval { &{$module->{'scanTrack'}}($track); };
					if ($@) {
						msg("CustomScan: Failed to call scanTrack on module $key: $@\n");
					}
					use strict 'refs';
					if($attributes && scalar(@$attributes)>0) {
						for my $attribute (@$attributes) {
							my $sql = undef;
							$sql = "INSERT INTO customscan_track_attributes (track,url,musicbrainz_id,module,attr,value) values (?,?,?,?,?,?)";
							my $sth = $dbh->prepare( $sql );
							eval {
								$sth->bind_param(1, $track->id , SQL_INTEGER);
								$sth->bind_param(2, $track->url , SQL_VARCHAR);
								if($track->musicbrainz_id =~ /.+-.+/) {
									$sth->bind_param(3,  $track->musicbrainz_id, SQL_VARCHAR);
								}else {
									$sth->bind_param(3,  undef, SQL_VARCHAR);
								}
								$sth->bind_param(4, $moduleId, SQL_VARCHAR);
								$sth->bind_param(5, $attribute->{'name'}, SQL_VARCHAR);
								$sth->bind_param(6, $attribute->{'value'} , SQL_VARCHAR);
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
					}
				}
			}
		}
		return 1;
	}
	exitScan($moduleKey);
	return 0;
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

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_customscan_refresh_startup','plugin_customscan_refresh_rescan','plugin_customscan_auto_rescan','plugin_customscan_properties','plugin_customscan_titleformats','plugin_customscan_showmessages'],
	 GroupHead => string('PLUGIN_CUSTOMSCAN_SETUP_GROUP'),
	 GroupDesc => string('PLUGIN_CUSTOMSCAN_SETUP_GROUP_DESC'),
	 GroupLine => 1,
	 GroupSub  => 1,
	 Suppress_PrefSub  => 1,
	 Suppress_PrefLine => 1
	);
	my %setupPrefs =
	(
	plugin_customscan_refresh_startup => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_CUSTOMSCAN_REFRESH_STARTUP')
			,'changeIntro' => string('PLUGIN_CUSTOMSCAN_REFRESH_STARTUP')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_customscan_refresh_startup"); }
		},		
	plugin_customscan_refresh_rescan => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_CUSTOMSCAN_REFRESH_RESCAN')
			,'changeIntro' => string('PLUGIN_CUSTOMSCAN_REFRESH_RESCAN')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_customscan_refresh_rescan"); }
		},		
	plugin_customscan_auto_rescan => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_CUSTOMSCAN_AUTO_RESCAN')
			,'changeIntro' => string('PLUGIN_CUSTOMSCAN_AUTO_RESCAN')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_customscan_auto_rescan"); }
		},		
	plugin_customscan_properties => {
			'validate' => \&validateProperty
			,'isArray' => 1
			,'arrayAddExtra' => 1
			,'arrayDeleteNull' => 1
			,'arrayDeleteValue' => ''
			,'arrayBasicValue' => ''
			,'inputTemplate' => 'setup_input_array_txt.html'
			,'changeAddlText' => string('PLUGIN_CUSTOMSCAN_PROPERTIES')
			,'PrefSize' => 'large'
		},
	plugin_customscan_titleformats => {
			'validate' => \&validateAcceptAllWrapper
			,'isArray' => 1
			,'arrayAddExtra' => 1
			,'arrayDeleteNull' => 1
			,'arrayDeleteValue' => -1
			,'arrayBasicValue' => ''
			,'inputTemplate' => 'setup_input_array_sel.html'
			,'changeAddlText' => string('PLUGIN_CUSTOMSCAN_TITLEFORMATS')
			,'PrefSize' => 'large'
			,'options' => sub {return getAvailableTitleFormats();}
		},
	plugin_customscan_showmessages => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_CUSTOMSCAN_SHOW_MESSAGES')
			,'changeIntro' => string('PLUGIN_CUSTOMSCAN_SHOW_MESSAGES')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_customscan_showmessages"); }
		}
	);

	refreshTitleFormats();
	return (\%setupGroup,\%setupPrefs);
}

sub refreshTitleFormats() {
        my @titleformats = Slim::Utils::Prefs::getArray('plugin_customscan_titleformats');
	for my $format (@titleformats) {
		if($format) {
			Slim::Music::TitleFormatter::addFormat("CUSTOMSCAN_$format",
				sub {
					debugMsg("Retreiving title format: $format\n");
					my $track = shift;
					my $result = '';
					if($format =~ /^([^_]+)_(.+)$/) {
						my $module = $1;
						my $attr = $2;
						eval {
							my $dbh = getCurrentDBH();
							my $sth = $dbh->prepare("SELECT value from customscan_track_attributes where module=? and attr=? and track=? group by value");
							$sth->bind_param(1,$module,SQL_VARCHAR);
							$sth->bind_param(2,$attr,SQL_VARCHAR);
							$sth->bind_param(3,$track->id,SQL_INTEGER);
							$sth->execute();
							my $value;
							$sth->bind_col(1, \$value);
							while($sth->fetch()) {
								if($result) {
									$result .= ', ';
								}
								$result .= $value;
							}
							$sth->finish();
						};
						if( $@ ) {
		    					warn "Database error: $DBI::errstr\n$@\n";
						}
					}
					debugMsg("Finished retreiving title format: $format=$result\n");
					return $result;
				});
		}
	}
}

sub webPages {
	my %pages = (
                "customscan_list\.(?:htm|xml)"     => \&handleWebList,
                "customscan_scan\.(?:htm|xml)"     => \&handleWebScan,
		"customscan_selectmodules\.(?:htm|xml)" => \&handleWebSelectModules,
		"customscan_saveselectmodules\.(?:htm|xml)" => \&handleWebSaveSelectModules,
        );

        my $value = 'customscan_list.html';

        if (grep { /^CustomScan::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

                $value = undef;
        }

        return (\%pages,$value);
}


sub handleWebList {
	my ($client, $params) = @_;

	$params->{'pluginCustomScanModules'} = getPluginModules();
	$params->{'pluginCustomScanScanning'} = $scanningInProgress;
	if ($::VERSION ge '6.5') {
		$params->{'pluginCustomScanSlimserver70'} = 1;
	}
	
	return Slim::Web::HTTP::filltemplatefile('plugins/CustomScan/customscan_list.html', $params);
}

sub handleWebScan {
	my ($client, $params) = @_;
	if($params->{'module'} eq 'allmodules') {
		if($params->{'type'} eq 'scan') {
			fullRescan();
		}elsif($params->{'type'} eq 'clear') {
			fullClear();
		}
	}else {
		if($params->{'type'} eq 'scan') {
			moduleRescan($params->{'module'});
		}elsif($params->{'type'} eq 'clear') {
			moduleClear($params->{'module'});
		}
	}
	return handleWebList($client, $params);
}

sub handleWebSelectModules {
	my ($client, $params) = @_;

	# Pass on the current pref values and now playing info
	$params->{'pluginCustomScanModules'} = getPluginModules();
	if ($::VERSION ge '7.0') {
		$params->{'pluginCustomScanSlimserver70'} = 1;
	}
	
	return Slim::Web::HTTP::filltemplatefile('plugins/CustomScan/customscan_selectmodules.html', $params);
}

sub handleWebSaveSelectModules {
	my ($client, $params) = @_;

	my $modules = getPluginModules();
	my $first = 1;
	my $sql = '';
	foreach my $module (keys %$modules) {
		my $moduleid = "module_".$modules->{$module}->{'id'};
		if($params->{$moduleid}) {
			Slim::Utils::Prefs::set('plugin_customscan_module_'.$modules->{$module}->{'id'}.'_enabled',1);
		}else {
			Slim::Utils::Prefs::set('plugin_customscan_module_'.$modules->{$module}->{'id'}.'_enabled',0);
		}
	}
	
	handleWebList($client, $params);
}

sub initDatabase {
	my $driver = Slim::Utils::Prefs::get('dbsource');
	$driver =~ s/dbi:(.*?):(.*)$/$1/;
    
	#Check if tables exists and create them if not
	debugMsg("Checking if customscan_track_attributes database table exists\n");
	my $dbh = getCurrentDBH();
	my $st = $dbh->table_info();
	my $tblexists;
	while (my ( $qual, $owner, $table, $type ) = $st->fetchrow_array()) {
		if($table eq "customscan_track_attributes") {
			$tblexists=1;
		}
	}
	unless ($tblexists) {
		debugMsg("Create database table\n");
		executeSQLFile("dbcreate.sql");
	}

	my $sth = $dbh->prepare("show create table tracks");
	my $charset;
	eval {
		debugMsg("Checking charsets on tables\n");
		$sth->execute();
		my $line = undef;
		$sth->bind_col( 2, \$line);
		if( $sth->fetch() ) {
			if(defined($line) && ($line =~ /.*CHARSET\s*=\s*([^\s\r\n]+).*/)) {
				$charset = $1;
				my $collate = '';
				if($line =~ /.*COLLATE\s*=\s*([^\s\r\n]+).*/) {
					$collate = $1;
				}
				debugMsg("Got tracks charset = $charset and collate = $collate\n");
				
				if(defined($charset)) {
					
					$sth->finish();
					updateCharSet("customscan_contributor_attributes",$charset,$collate);
					updateCharSet("customscan_album_attributes",$charset,$collate);
					updateCharSet("customscan_track_attributes",$charset,$collate);
				}
			}
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
	if(Slim::Utils::Prefs::get("plugin_customscan_refresh_startup")) {
		refreshData();
	}
}
sub updateCharSet {
	my $table = shift;
	my $charset = shift;
	my $collate = shift;

	my $dbh = getCurrentDBH();
	my $sth = $dbh->prepare("show create table $table");
	$sth->execute();
	my $line = undef;
	$sth->bind_col( 2, \$line);
	if( $sth->fetch() ) {
		if(defined($line) && ($line =~ /.*CHARSET\s*=\s*([^\s\r\n]+).*/)) {
			my $table_charset = $1;
			my $table_collate = '';
			if($line =~ /.*COLLATE\s*=\s*([^\s\r\n]+).*/) {
				$table_collate = $1;
			}
			debugMsg("Got $table charset = $table_charset and collate = $table_collate\n");
			if($charset ne $table_charset || ($collate && (!$table_collate || $collate ne $table_collate))) {
				debugMsg("Converting $table to correct charset=$charset collate=$collate\n");
				if(!$collate) {
					eval { $dbh->do("alter table $table convert to character set $charset") };
				}else {
					eval { $dbh->do("alter table $table convert to character set $charset collate $collate") };
				}
				if ($@) {
					debugMsg("Couldn't convert charsets: $@\n");
				}
			}
		}
	}
	$sth->finish();
}

sub refreshData 
{
	my $ds = getCurrentDS();
	my $dbh = getCurrentDBH();
	my $sth;
	my $sthupdate;
	my $sql;
	my $sqlupdate;
	my $count;
	my $timeMeasure = Time::Stopwatch->new();
	$timeMeasure->clear();

	$timeMeasure->start();
	debugMsg("Starting to update musicbrainz id's in custom scan artist data based on names\n");
	# Now lets set all musicbrainz id's not already set
	$sql = "UPDATE contributors,customscan_contributor_attributes SET customscan_contributor_attributes.musicbrainz_id=contributors.musicbrainz_id where contributors.name=customscan_contributor_attributes.name and contributors.musicbrainz_id like '%-%' and customscan_contributor_attributes.musicbrainz_id is null";
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}

	$sth->finish();
	debugMsg("Finished updating musicbrainz id's in custom scan artist data based on names, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();
	$timeMeasure->clear();

	$timeMeasure->start();
	debugMsg("Starting to update custom scan artist data based on musicbrainz ids\n");
	# First lets refresh all urls with musicbrainz id's
	$sql = "UPDATE contributors,customscan_contributor_attributes SET customscan_contributor_attributes.name=contributors.name, customscan_contributor_attributes.contributor=contributors.id where contributors.musicbrainz_id is not null and contributors.musicbrainz_id=customscan_contributor_attributes.musicbrainz_id and (customscan_contributor_attributes.name!=contributors.name or customscan_contributor_attributes.contributor!=contributors.id)";
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}
	$sth->finish();
	debugMsg("Finished updating custom scan artist data based on musicbrainz ids, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();

	$timeMeasure->clear();

	$timeMeasure->start();
	debugMsg("Starting to update custom scan artist data based on names\n");
	# First lets refresh all urls with musicbrainz id's
	$sql = "UPDATE contributors,customscan_contributor_attributes SET customscan_contributor_attributes.contributor=contributors.id where customscan_contributor_attributes.musicbrainz_id is null and contributors.name=customscan_contributor_attributes.name and customscan_contributor_attributes.contributor!=contributors.id";
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}
	$sth->finish();
	debugMsg("Finished updating custom scan artist data based on names, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();

	$timeMeasure->clear();

	$timeMeasure->start();
	debugMsg("Starting to update musicbrainz id's in custom scan album data based on titles\n");
	# Now lets set all musicbrainz id's not already set
	$sql = "UPDATE albums,customscan_album_attributes SET customscan_album_attributes.musicbrainz_id=albums.musicbrainz_id where albums.title=customscan_album_attributes.title and albums.musicbrainz_id like '%-%' and customscan_album_attributes.musicbrainz_id is null";
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}

	$sth->finish();
	debugMsg("Finished updating musicbrainz id's in custom scan album data based on titles, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();
	$timeMeasure->clear();

	$timeMeasure->start();
	debugMsg("Starting to update custom scan album data based on musicbrainz ids\n");
	# First lets refresh all urls with musicbrainz id's
	$sql = "UPDATE albums,customscan_album_attributes SET customscan_album_attributes.title=albums.title, customscan_album_attributes.album=albums.id where albums.musicbrainz_id is not null and albums.musicbrainz_id=customscan_album_attributes.musicbrainz_id and (customscan_album_attributes.title!=albums.title or customscan_album_attributes.album!=albums.id)";
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}
	$sth->finish();
	debugMsg("Finished updating custom scan album data based on musicbrainz ids, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();
	$timeMeasure->clear();

	$timeMeasure->start();
	debugMsg("Starting to update custom scan album data based on titles\n");
	# First lets refresh all urls with musicbrainz id's
	$sql = "UPDATE albums,customscan_album_attributes SET customscan_album_attributes.album=albums.id where customscan_album_attributes.musicbrainz_id is null and albums.title=customscan_album_attributes.title and customscan_album_attributes.album!=albums.id";
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}
	$sth->finish();
	debugMsg("Finished updating custom scan album data based on titles, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();
	$timeMeasure->clear();

	$timeMeasure->start();
	debugMsg("Starting to update musicbrainz id's in custom scan track data based on urls\n");
	# Now lets set all musicbrainz id's not already set
	$sql = "UPDATE tracks,customscan_track_attributes SET customscan_track_attributes.musicbrainz_id=tracks.musicbrainz_id where tracks.url=customscan_track_attributes.url and tracks.musicbrainz_id like '%-%' and customscan_track_attributes.musicbrainz_id is null";
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}

	$sth->finish();
	debugMsg("Finished updating musicbrainz id's in custom scan track data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();
	$timeMeasure->clear();

	$timeMeasure->start();
	debugMsg("Starting to update custom scan track data based on musicbrainz ids\n");
	# First lets refresh all urls with musicbrainz id's
	$sql = "UPDATE tracks,customscan_track_attributes SET customscan_track_attributes.url=tracks.url, customscan_track_attributes.track=tracks.id where tracks.musicbrainz_id is not null and tracks.musicbrainz_id=customscan_track_attributes.musicbrainz_id and (customscan_track_attributes.url!=tracks.url or customscan_track_attributes.track!=tracks.id)";
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}
	$sth->finish();
	debugMsg("Finished updating custom scan track data based on musicbrainz ids, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();
	$timeMeasure->clear();

	$timeMeasure->start();
	debugMsg("Starting to update custom scan track data based on urls\n");
	# First lets refresh all urls with musicbrainz id's
	$sql = "UPDATE tracks,customscan_track_attributes SET customscan_track_attributes.track=tracks.id where customscan_track_attributes.musicbrainz_id is null and tracks.url=customscan_track_attributes.url and customscan_track_attributes.track!=tracks.id";
	$sth = $dbh->prepare( $sql );
	$count = 0;
	eval {
		$count = $sth->execute();
		if($count eq '0E0') {
			$count = 0;
		}
		commit($dbh);
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}
	$sth->finish();
	debugMsg("Finished updating custom scan track data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	$timeMeasure->stop();
	$timeMeasure->clear();
}


sub executeSQLFile {
        my $file  = shift;
	my $driver = Slim::Utils::Prefs::get('dbsource');
	$driver =~ s/dbi:(.*?):(.*)$/$1/;

        my $sqlFile;
	for my $plugindir (Slim::Utils::OSDetect::dirsFor('Plugins')) {
		opendir(DIR, catdir($plugindir,"CustomScan")) || next;
       		$sqlFile = catdir($plugindir,"CustomScan", "SQL", $driver, $file);
       		closedir(DIR);
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
sub getAvailableTitleFormats {
	my $dbh = getCurrentDBH();
	my %result = ();
	$result{'-1'} = ' ';
        my @titleformats = Slim::Utils::Prefs::getArray('plugin_customscan_titleformats');
	for my $format (@titleformats) {
		if($format) {
			$result{$format} = "CUSTOMSCAN_$format";
		}
	}

	my $sth = $dbh->prepare("SELECT module,attr from customscan_track_attributes group by module,attr");
	my $module;
	my $attr;
	$sth->execute();
	$sth->bind_col(1,\$module);
	$sth->bind_col(2, \$attr);
	if($sth->fetch()) {
		$result{uc($module)."_".uc($attr)} = "CUSTOMSCAN_TRACK_".uc($module)."_".uc($attr);
	}
	$sth->finish();

	return \%result;
}

sub getCustomScanProperty {
	my $name = shift;
	my $properties = getCustomScanProperties();
	return $properties->{$name};
}

sub getCustomScanProperties {
	my $array = Slim::Utils::Prefs::get('plugin_customscan_properties');
	my %result = ();
	foreach my $item (@$array) {
		if($item =~ m/^([a-zA-Z0-9]+?)\s*=\s*(.+)\s*$/) {
			my $name = $1;
			my $value = $2;
			$result{$name}=$value;
		}
	}
	return \%result;
}

sub validateProperty {
	my $arg = shift;
	if($arg eq '' || $arg =~ /^[a-zA-Z0-9_]+\s*=\s*.+$/) {
		return $arg;
	}else {
		return undef;
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

sub validateProperty {
	my $arg = shift;
	if($arg eq '' || $arg =~ /^[a-zA-Z0-9]+\s*=\s*.+$/) {
		return $arg;
	}else {
		return undef;
	}
}
sub validateIsDirWrapper {
	my $arg = shift;
	if ($::VERSION ge '6.5') {
		return Slim::Utils::Validate::isDir($arg);
	}else {
		return Slim::Web::Setup::validateIsDir($arg);
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
		}elsif($type eq 'year') {
			$type = 'Year';
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
	my $message = join '','CustomScan: ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_customscan_showmessages"));
}

sub strings {
	return <<EOF;
PLUGIN_CUSTOMSCAN
	EN	Custom Scan

PLUGIN_CUSTOMSCAN_SETUP_GROUP
	EN	Custom Scan

PLUGIN_CUSTOMSCAN_SETUP_GROUP_DESC
	EN	Custom Scan is a plugin which makes it possible to retreive additional information about albums, artists and tracks

PLUGIN_CUSTOMSCAN_SHOW_MESSAGES
	EN	Show debug messages

SETUP_PLUGIN_CUSTOMSCAN_SHOWMESSAGES
	EN	Debugging

PLUGIN_CUSTOMSCAN_REFRESH_STARTUP
	EN	Refresh custom scan data at startup

SETUP_PLUGIN_CUSTOMSCAN_REFRESH_STARTUP
	EN	Startup refresh

SETUP_PLUGIN_CUSTOMSCAN_REFRESH_STARTUP_DESC
	EN	This will activate/deactivate the refresh data operation at slimserver startup, the only reason to turn this if is if you get performance issues with refresh data

PLUGIN_CUSTOMSCAN_REFRESH_RESCAN
	EN	Refresh custom scan data after rescan

SETUP_PLUGIN_CUSTOMSCAN_REFRESH_RESCAN
	EN	Rescan refresh

SETUP_PLUGIN_CUSTOMSCAN_REFRESH_RESCAN_DESC
	EN	This will activate/deactivate the refresh data operation after a slimserver rescan, the only reason to turn this if is if you get performance issues with refresh data. This option does not have any effect if automatic rescan is turned on.

PLUGIN_CUSTOMSCAN_AUTO_RESCAN
	EN	Automatic rescan

SETUP_PLUGIN_CUSTOMSCAN_AUTO_RESCAN
	EN	Automatic rescan

SETUP_PLUGIN_CUSTOMSCAN_AUTO_RESCAN_DESC
	EN	This will activate/deactivate the automatic rescan after a slimserver rescan has been performed

PLUGIN_CUSTOMSCAN_SELECT_MODULES
	EN	Enable/Disable scanning modules 

PLUGIN_CUSTOMSCAN_SELECT_MODULES_TITLE
	EN	Select enabled modules

PLUGIN_CUSTOMSCAN_SELECT_MODULES_NONE
	EN	No modules

PLUGIN_CUSTOMSCAN_SELECT_MODULES_ALL
	EN	All modules

PLUGIN_CUSTOMSCAN_SCAN_CLEAR
	EN	Clear

PLUGIN_CUSTOMSCAN_SCAN_RESCAN
	EN	Scan

PLUGIN_CUSTOMSCAN_SCAN_CLEAR_QUESTION
	EN	Are you sure you want to completely remove the data for this module ?

PLUGIN_CUSTOMSCAN_SCAN_CLEAR_ALL
	EN	Clear All

PLUGIN_CUSTOMSCAN_SCAN_RESCAN_ALL
	EN	Scan All

PLUGIN_CUSTOMSCAN_SCAN_CLEAR_ALL_QUESTION
	EN	Are you sure you want to completely remove all data for all modules ?

PLUGIN_CUSTOMSCAN_PROPERTIES
	EN	Properties to use in scanning modules

SETUP_PLUGIN_CUSTOMSCAN_PROPERTIES
	EN	Properties to use in scanning modules

PLUGIN_CUSTOMSCAN_TITLEFORMATS
	EN	Attributes to make available as title formats

SETUP_PLUGIN_CUSTOMSCAN_TITLEFORMATS
	EN	Title formats

PLUGIN_CUSTOMSCAN_SCANNING
	EN	Scanning in progress...

PLUGIN_CUSTOMSCAN_REFRESH
	EN	Refresh scanning status
EOF

}

1;

__END__
