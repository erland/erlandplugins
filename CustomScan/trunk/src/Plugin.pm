# 				CustomScan plugin 
#
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
#
#    The LastFM scanning module uses the webservices from audioscrobbler.
#    Please respect audioscrobbler terms of service, the content of the 
#    feeds are licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License
#
#    The Amazon scanning module uses the webservies from amazon.com
#    Please respect amazon.com terms of service, the usage of the 
#    feeds are free but restricted to the Amazon Web Services Licensing Acgreement
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
use Plugins::CustomScan::Template::Reader;

my $albums = ();
my $artists = ();
my $tracks = ();
my $scanningInProgress = 0;
my $scanningAborted = 0;

my $modules = ();
my @pluginDirs = ();
my $PLUGINVERSION = '1.17';

# Indicator if hooked or not
# 0= No
# 1= Yes
my $CUSTOMSCAN_HOOK = 0;


sub getDisplayName {
	return 'PLUGIN_CUSTOMSCAN';
}

sub initPlugin {
	my $class = shift;
	initDatabase();
	if ( !$CUSTOMSCAN_HOOK ) {
		refreshTitleFormats();
		installHook();
	}
	checkDefaults();
	if(!$modules) {
		$modules = getPluginModules();
	}
	for my $key (keys %$modules) {
		my $module = $modules->{$key};
		my $initFunction = $module->{'initModule'};
		if(defined($module->{'initModule'})) {
			no strict 'refs';
			debugMsg("Calling: initModule on $key\n");
			eval { &{$module->{'initModule'}}(); };
			if ($@) {
				msg("CustomScan: Failed to call initModule on module $key: $@\n");
			}
			use strict 'refs';
		}
	}
}

sub shutdownPlugin {
        debugMsg("disabling\n");
        if ($CUSTOMSCAN_HOOK) {
                uninstallHook();
        }
	if(!$modules) {
		for my $key (keys %$modules) {
			my $module = $modules->{$key};
			my $initFunction = $module->{'exitModule'};
			if(defined($module->{'exitModule'})) {
				no strict 'refs';
				debugMsg("Calling: exitModule on $key\n");
				eval { &{$module->{'exitModule'}}(); };
				if ($@) {
					msg("CustomScan: Failed to call exitModule on module $key: $@\n");
				}
				use strict 'refs';
			}
		}
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

	$modules = getPluginModules();
	for my $key (keys %$modules) {
		my $module = $modules->{$key};
		my $properties = $module->{'properties'};
		for my $property (@$properties) {
			my $value = getCustomScanProperty($property->{'id'});
			if(!defined($value)) {
				setCustomScanProperty($property->{'id'},$property->{'value'});
			}
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
						if((!defined($enabled) && $data->{'defaultenabled'})|| $enabled) {
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

sub getSQLPlayListTemplates {
	my $client = shift;
	return Plugins::CustomScan::Template::Reader::getTemplates($client,'CustomScan','PlaylistTemplates','xml');
}
sub getCustomBrowseTemplates {
	my $client = shift;
	return Plugins::CustomScan::Template::Reader::getTemplates($client,'CustomScan','MenuTemplates','xml');
}
sub getCustomBrowseContextTemplates {
	my $client = shift;
	return Plugins::CustomScan::Template::Reader::getTemplates($client,'CustomScan','ContextMenuTemplates','xml');
}

sub getCustomBrowseContextMenus {
	my $client = shift;
	my $result = Plugins::CustomScan::Template::Reader::getTemplates($client,'CustomScan','ContextMenus','xml','template','menu','simple',1);
	return $result;
}
sub getCustomBrowseMixes {
	my $client = shift;
	return Plugins::CustomScan::Template::Reader::getTemplates($client,'CustomScan','Mixes','xml','mix');
}
sub getSQLPlayListTemplateData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;
	
	my $data = Plugins::CustomScan::Template::Reader::readTemplateData('CustomScan','PlaylistTemplates',$templateItem->{'id'});
	return $data;
}


sub getCustomBrowseTemplateData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;
	
	my $data = Plugins::CustomScan::Template::Reader::readTemplateData('CustomScan','MenuTemplates',$templateItem->{'id'});
	return $data;
}
sub getCustomBrowseContextTemplateData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;
	
	my $data = Plugins::CustomScan::Template::Reader::readTemplateData('CustomScan','ContextMenuTemplates',$templateItem->{'id'});
	return $data;
}
sub getCustomBrowseContextMenuData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;
	my $data = Plugins::CustomScan::Template::Reader::readTemplateData('CustomScan','ContextMenus',$templateItem->{'id'},"xml");
	return $data;
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
	$scanningAborted = 0;
	refreshData();

	$scanningInProgress = 1;
	$modules = getPluginModules();

	my @moduleKeys = ();
	my $array = getSortedModuleKeys();
	push @moduleKeys,@$array;
	for my $key (@moduleKeys) {
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

sub fullAbort {
	if($scanningInProgress) {
		$scanningAborted = 1;
		msg("CustomScan: Aborting scanning...\n");
		return 0;
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
		my $array = getSortedModuleKeys();
		push @moduleKeys,@$array;
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
	$scanningAborted = 0;
	$scanningInProgress = 0;
	debugMsg("Rescan finished\n");
}

sub initArtistScan {
	my $moduleKey = shift;
	my @joins = ();
	push @joins, 'contributorTracks';
	$artists = Slim::Schema->resultset('Contributor')->search(
		{'contributorTracks.role' => {'in' => [1,5]}},
		{
			'group_by' => 'me.id',
			'join' => \@joins
		}
	);
	debugMsg("Got ".$artists->count." artists\n");
	my $dbh = getCurrentDBH();
	my @moduleKeys = ();
	if(defined($moduleKey)) {
		push @moduleKeys,$moduleKey;
	}else {
		my $array = getSortedModuleKeys();
		push @moduleKeys,@$array;
	}
	for my $key (@moduleKeys) {
		my $module = $modules->{$key};
		my $moduleId = $key;
		my $moduleId = $module->{'id'};
		if((defined($module->{'scanArtist'}) || defined($module->{'initScanArtist'})) && defined($module->{'alwaysRescanArtist'}) && $module->{'alwaysRescanArtist'}) {
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
		if(defined($module->{'initScanArtist'})) {
			no strict 'refs';
			#debugMsg("Calling: ".$plugin."::initScanArtist\n");
			eval { &{$module->{'initScanArtist'}}(); };
			if ($@) {
				msg("CustomScan: Failed to call initScanArtist on module $key: $@\n");
			}
			use strict 'refs';
		}
	}
	Slim::Utils::Scheduler::add_task(\&scanArtist,$moduleKey);
}

sub getSortedModuleKeys {
	my @moduleArray = ();
	for my $key (keys %$modules) {
		if($modules->{$key}->{'enabled'}) {
			my %tmp = (
				'key' => $key,
				'module' => $modules
			);
			push @moduleArray,\%tmp;
		}
	}
	@moduleArray = sort { 
		if(defined($a->{'module'}->{'order'}) && defined($b->{'module'}->{'order'})) {
			if($a->{'module'}->{'order'}!=$b->{'module'}->{'order'}) {
				return $a->{'module'}->{'order'} <=> $b->{'module'}->{'order'};
			}
		}
		if(defined($a->{'module'}->{'order'}) && !defined($b->{'module'}->{'order'})) {
			if($a->{'module'}->{'order'}!=50) {
				return $a->{'order'} <=> 50;
			}
		}
		if(!defined($a->{'module'}->{'order'}) && defined($b->{'module'}->{'order'})) {
			if($b->{'module'}->{'order'}!=50) {
				return 50 <=> $b->{'module'}->{'order'};
			}
		}
		if(!defined($a->{'module'}->{'order'}) && !defined($b->{'module'}->{'order'})) {
			return 0;
		}
		return $a->{'module'}->{'order'} cmp $b->{'module'}->{'order'} 
	} @moduleArray;
	
	my @moduleKeys = ();		
	for my $module (@moduleArray) {
		push @moduleKeys,$module->{'key'};
	}
	return \@moduleKeys;
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
		my $array = getSortedModuleKeys();
		push @moduleKeys,@$array;
	}
	for my $key (@moduleKeys) {
		my $module = $modules->{$key};
		my $moduleId = $module->{'id'};
		if((defined($module->{'scanAlbum'}) || defined($module->{'initScanAlbum'})) && defined($module->{'alwaysRescanAlbum'}) && $module->{'alwaysRescanAlbum'}) {
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
		if(defined($module->{'initScanAlbum'})) {
			no strict 'refs';
			#debugMsg("Calling: ".$plugin."::initScanAlbum\n");
			eval { &{$module->{'initScanAlbum'}}(); };
			if ($@) {
				msg("CustomScan: Failed to call initScanAlbum on module $key: $@\n");
			}
			use strict 'refs';
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
		my $array = getSortedModuleKeys();
		push @moduleKeys,@$array;
	}
	for my $key (@moduleKeys) {
		my $module = $modules->{$key};
		my $moduleId = $module->{'id'};
		if((defined($module->{'scanTrack'}) || defined($module->{'initScanTrack'})) && defined($module->{'alwaysRescanTrack'}) && $module->{'alwaysRescanTrack'}) {
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
		if(defined($module->{'initScanTrack'})) {
			no strict 'refs';
			#debugMsg("Calling: ".$plugin."::initScanTrack\n");
			eval { &{$module->{'initScanTrack'}}(); };
			if ($@) {
				msg("CustomScan: Failed to call initScanTrack on module $key: $@\n");
			}
			use strict 'refs';
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
	my @moduleKeys = ();
	if(defined($moduleKey)) {
		push @moduleKeys,$moduleKey;
	}else {
		my $array = getSortedModuleKeys();
		push @moduleKeys,@$array;
	}
	if(defined($artist)) {
		my $dbh = getCurrentDBH();
		#debugMsg("Scanning artist: ".$artist->name."\n");
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
							$sql = "INSERT INTO customscan_contributor_attributes (contributor,name,musicbrainz_id,module,attr,value,valuesort,extravalue,valuetype) values (?,?,?,?,?,?,?,?,?)";
							my $sth = $dbh->prepare( $sql );
							eval {
								$sth->bind_param(1, $artist->id , SQL_INTEGER);
								$sth->bind_param(2, $artist->name , SQL_VARCHAR);
								if(defined($artist->musicbrainz_id) && $artist->musicbrainz_id =~ /.+-.+/) {
									$sth->bind_param(3,  $artist->musicbrainz_id, SQL_VARCHAR);
								}else {
									$sth->bind_param(3,  undef, SQL_VARCHAR);
								}
								$sth->bind_param(4, $moduleId, SQL_VARCHAR);
								$sth->bind_param(5, $attribute->{'name'}, SQL_VARCHAR);
								$sth->bind_param(6, $attribute->{'value'} , SQL_VARCHAR);
								$sth->bind_param(7, $attribute->{'valuesort'} , SQL_VARCHAR);
								$sth->bind_param(8, $attribute->{'extravalue'} , SQL_VARCHAR);
								$sth->bind_param(9, $attribute->{'valuetype'} , SQL_VARCHAR);
								$sth->execute();
								commit($dbh);
							};
							if( $@ ) {
							    warn "Database error: $DBI::errstr\n";
							    eval {
							    	rollback($dbh); #just die if rollback is failing
							    };
							    debugMsg("Error values: ".$artist->id.", ".$artist->name.", ".$artist->musicbrainz_id.", ".$moduleId.", ".$attribute->{'name'}.", ".$attribute->{'value'}.", ".$attribute->{'valuesort'}.", ".$attribute->{'extravalue'}.", ".$attribute->{'valuetype'}."\n");
						   	}
							$sth->finish();
						}
					}
				}
			}
		}
		if(!$scanningAborted) {
			return 1;
		}
	}
	for my $key (@moduleKeys) {
		my $module = $modules->{$key};
		if(defined($module->{'exitScanArtist'})) {
			no strict 'refs';
			#debugMsg("Calling: ".$plugin."::exitScanArtist\n");
			eval { &{$module->{'exitScanArtist'}}(); };
			if ($@) {
				msg("CustomScan: Failed to call exitScanArtist on module $key: $@\n");
			}
			use strict 'refs';
		}
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
	my @moduleKeys = ();
	if(defined($moduleKey)) {
		push @moduleKeys,$moduleKey;
	}else {
		my $array = getSortedModuleKeys();
		push @moduleKeys,@$array;
	}
	if(defined($album)) {
		my $dbh = getCurrentDBH();
		#debugMsg("Scanning album: ".$album->title."\n");
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
							$sql = "INSERT INTO customscan_album_attributes (album,title,musicbrainz_id,module,attr,value,valuesort,extravalue,valuetype) values (?,?,?,?,?,?,?,?,?)";
							my $sth = $dbh->prepare( $sql );
							eval {
								$sth->bind_param(1, $album->id , SQL_INTEGER);
								$sth->bind_param(2, $album->title , SQL_VARCHAR);
								if(defined($album->musicbrainz_id) && $album->musicbrainz_id =~ /.+-.+/) {
									$sth->bind_param(3,  $album->musicbrainz_id, SQL_VARCHAR);
								}else {
									$sth->bind_param(3,  undef, SQL_VARCHAR);
								}
								$sth->bind_param(4, $moduleId, SQL_VARCHAR);
								$sth->bind_param(5, $attribute->{'name'}, SQL_VARCHAR);
								$sth->bind_param(6, $attribute->{'value'} , SQL_VARCHAR);
								$sth->bind_param(7, $attribute->{'valuesort'} , SQL_VARCHAR);
								$sth->bind_param(8, $attribute->{'extravalue'} , SQL_VARCHAR);
								$sth->bind_param(9, $attribute->{'valuetype'} , SQL_VARCHAR);
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
		if(!$scanningAborted) {
			return 1;
		}
	}
	for my $key (@moduleKeys) {
		my $module = $modules->{$key};
		if(defined($module->{'exitScanAlbum'})) {
			no strict 'refs';
			#debugMsg("Calling: ".$plugin."::exitScanAlbum\n");
			eval { &{$module->{'exitScanAlbum'}}(); };
			if ($@) {
				msg("CustomScan: Failed to call exitScanAlbum on module $key: $@\n");
			}
			use strict 'refs';
		}
	}
	initTrackScan($moduleKey);
	return 0;
}

sub scanTrack {
	my $moduleKey = shift;
	my $track = undef;
	if($tracks) {
		$track = $tracks->next;
		# Skip non audio tracks and tracks with url longer than 255 characters
		while(defined($track) && !$track->audio && length($track->url)<=255) {
			$track = $tracks->next;
		}
	}
	my @moduleKeys = ();
	if(defined($moduleKey)) {
		push @moduleKeys,$moduleKey;
	}else {
		my $array = getSortedModuleKeys();
		push @moduleKeys,@$array;
	}
	if(defined($track)) {
		my $dbh = getCurrentDBH();
		#debugMsg("Scanning track: ".$track->title."\n");
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
							$sql = "INSERT INTO customscan_track_attributes (track,url,musicbrainz_id,module,attr,value,valuesort,extravalue,valuetype) values (?,?,?,?,?,?,?,?,?)";
							my $sth = $dbh->prepare( $sql );
							eval {
								$sth->bind_param(1, $track->id , SQL_INTEGER);
								$sth->bind_param(2, $track->url , SQL_VARCHAR);
								if(defined($track->musicbrainz_id) && $track->musicbrainz_id =~ /.+-.+/) {
									$sth->bind_param(3,  $track->musicbrainz_id, SQL_VARCHAR);
								}else {
									$sth->bind_param(3,  undef, SQL_VARCHAR);
								}
								$sth->bind_param(4, $moduleId, SQL_VARCHAR);
								$sth->bind_param(5, $attribute->{'name'}, SQL_VARCHAR);
								$sth->bind_param(6, $attribute->{'value'} , SQL_VARCHAR);
								$sth->bind_param(7, $attribute->{'valuesort'} , SQL_VARCHAR);
								$sth->bind_param(8, $attribute->{'extravalue'} , SQL_VARCHAR);
								$sth->bind_param(9, $attribute->{'valuetype'} , SQL_VARCHAR);
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
		if(!$scanningAborted) {
			return 1;
		}
	}
	for my $key (@moduleKeys) {
		my $module = $modules->{$key};
		if(defined($module->{'exitScanTrack'})) {
			no strict 'refs';
			#debugMsg("Calling: ".$plugin."::exitScanTrack\n");
			eval { &{$module->{'exitScanTrack'}}(); };
			if ($@) {
				msg("CustomScan: Failed to call exitScanTrack on module $key: $@\n");
			}
			use strict 'refs';
		}
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
	debugMsg("Adding at $arrayMax: $titleformat\n");
	Slim::Utils::Prefs::set('titleFormat',$titleformat,$arrayMax+1);
}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_customscan_refresh_startup','plugin_customscan_refresh_rescan','plugin_customscan_auto_rescan','plugin_customscan_titleformats','plugin_customscan_showmessages'],
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
								$value = Slim::Utils::Unicode::utf8on($value);
								$value = Slim::Utils::Unicode::utf8encode_locale($value);
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
			addTitleFormat("DISC-TRACKNUM. TITLE - CUSTOMSCAN_$format");
		}
	}
}

sub webPages {
	my %pages = (
                "customscan_list\.(?:htm|xml)"     => \&handleWebList,
                "customscan_scan\.(?:htm|xml)"     => \&handleWebScan,
		"customscan_settings\.(?:htm|xml)" => \&handleWebSettings,
		"customscan_savesettings\.(?:htm|xml)" => \&handleWebSaveSettings,
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
	$params->{'pluginCustomScanVersion'} = $PLUGINVERSION;
	
	return Slim::Web::HTTP::filltemplatefile('plugins/CustomScan/customscan_list.html', $params);
}

sub handleWebSettings {
	my ($client, $params) = @_;

	if(!$modules) {
		$modules = getPluginModules();
	}
	my $module = $modules->{$params->{'module'}};


	$params->{'pluginCustomScanModuleId'} = $params->{'module'};
	$params->{'pluginCustomScanModuleEnabled'} = $module->{'enabled'};
	$params->{'pluginCustomScanModuleName'} = $module->{'name'};
	$params->{'pluginCustomScanModuleDescription'} = $module->{'description'};
	my @properties = ();
	my $moduleProperties = $module->{'properties'};
	for my $property (@$moduleProperties) {
		my %p = (
			'id' => $property->{'id'},
			'name' => $property->{'name'},
			'description' => $property->{'description'},
			'type' => $property->{'type'}
		);
		my $value = getCustomScanProperty($property->{'id'});
		if(!defined($value)) {
			$value = $property->{'value'};
		}
		$p{'value'} = $value;
		push @properties,\%p;
	}	
	$params->{'pluginCustomScanModuleProperties'} = \@properties;

	if ($::VERSION ge '6.5') {
		$params->{'pluginCustomScanSlimserver70'} = 1;
	}
	
	return Slim::Web::HTTP::filltemplatefile('plugins/CustomScan/customscan_settings.html', $params);
}

sub handleWebSaveSettings {
	my ($client, $params) = @_;

	if(!$modules) {
		$modules = getPluginModules();
	}
	my $module = $modules->{$params->{'module'}};
	
	my $moduleProperties = $module->{'properties'};

	foreach my $property (@$moduleProperties) {
		my $propertyid = "property_".$property->{'id'};
		if($params->{$propertyid}) {
			setCustomScanProperty($property->{'id'},$params->{$propertyid});
		}else {
			if($property->{'type'} eq 'checkbox') {
				setCustomScanProperty($property->{'id'},0);
			}else {
				setCustomScanProperty($property->{'id'},'');
			}
		}
	}
	if($params->{'moduleenabled'}) {
		$module->{'enabled'} = 1;
		Slim::Utils::Prefs::set('plugin_customscan_module_'.$module->{'id'}.'_enabled',1);
	}else {
		$module->{'enabled'} = 0;
		Slim::Utils::Prefs::set('plugin_customscan_module_'.$module->{'id'}.'_enabled',0);
	}
	handleWebList($client, $params);
}

sub setCustomScanProperty {
	my $name = shift;
	my $value = shift;

        my @properties = Slim::Utils::Prefs::getArray('plugin_customscan_properties');
	my $propertyexists = undef;
	my $index = 0;
	for my $property (@properties) {
		if($property =~ /^$name=/) {
			$propertyexists = 1;
			Slim::Utils::Prefs::set('plugin_customscan_properties',"$name=$value",$index);
		}
		$index = $index+1;
	}
	if(!$propertyexists) {
		Slim::Utils::Prefs::push('plugin_customscan_properties', "$name=$value");
	}
}

sub handleWebScan {
	my ($client, $params) = @_;
	if($params->{'module'} eq 'allmodules') {
		if($params->{'type'} eq 'scan') {
			fullRescan();
		}elsif($params->{'type'} eq 'clear') {
			fullClear();
		}elsif($params->{'type'} eq 'abort') {
			fullAbort();
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
		msg("CustomScan: Creating database tables\n");
		executeSQLFile("dbcreate.sql");
	}

	eval { $dbh->do("select valuesort from customscan_track_attributes limit 1;") };
	if ($@) {
		msg("CustomScan: Upgrading database adding table column valuesort, please wait...\n");
		executeSQLFile("dbupgrade_valuesort.sql");
	}

	eval { $dbh->do("select extravalue from customscan_track_attributes limit 1;") };
	if ($@) {
		msg("CustomScan: Upgrading database adding table column extravalue, please wait...\n");
		executeSQLFile("dbupgrade_extravalue.sql");
	}

	eval { $dbh->do("select valuetype from customscan_track_attributes limit 1;") };
	if ($@) {
		msg("CustomScan: Upgrading database adding table column valuetype, please wait...\n");
		executeSQLFile("dbupgrade_valuetype.sql");
	}

	my $sth = $dbh->prepare("show create table customscan_track_attributes");
	eval {
		debugMsg("Checking datatype on customscan_track_attributes\n");
		$sth->execute();
		my $line = undef;
		$sth->bind_col( 2, \$line);
		if( $sth->fetch() ) {
			if(defined($line) && (lc($line) =~ /url.*(text|mediumtext)/m)) {
				msg("CustomScan: Upgrading database changing type of url column, please wait...\n");
				executeSQLFile("dbupgrade_url_type.sql");
			}
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n$@\n";
	}
	$sth->finish();
	$sth = $dbh->prepare("show create table tracks");
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
	$sth = $dbh->prepare("show index from customscan_album_attributes;");
	eval {
		debugMsg("Checking if indexes is needed for customscan_album_attributes\n");
		$sth->execute();
		my $keyname;
		$sth->bind_col( 3, \$keyname );
		my $foundMB = 0;
		my $foundValue = 0;
		while( $sth->fetch() ) {
			if($keyname eq "musicbrainzIndex") {
				$foundMB = 1;
			}
			if($keyname eq "module_attr_value_idx") {
				$foundValue = 1;
			}
		}
		if(!$foundMB) {
			msg("CustomScan: No musicbrainzIndex index found in customscan_album_attributes, creating index...\n");
			eval { $dbh->do("create index musicbrainzIndex on customscan_album_attributes (musicbrainz_id);") };
			if ($@) {
				debugMsg("Couldn't add index: $@\n");
			}
		}
		if(!$foundValue) {
			msg("CustomScan: No module_attr_value_idx index found in customscan_album_attributes, creating index...\n");
			eval { $dbh->do("create index module_attr_value_idx on customscan_album_attributes (module,attr,value);") };
			if ($@) {
				debugMsg("Couldn't add index: $@\n");
			}
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n$@\n";
	}
	$sth->finish();
	$sth = $dbh->prepare("show index from customscan_contributor_attributes;");
	eval {
		debugMsg("Checking if indexes is needed for customscan_contributor_attributes\n");
		$sth->execute();
		my $keyname;
		$sth->bind_col( 3, \$keyname );
		my $foundMB = 0;
		my $foundValue = 0;
		while( $sth->fetch() ) {
			if($keyname eq "musicbrainzIndex") {
				$foundMB = 1;
			}elsif($keyname eq "module_attr_value_idx") {
				$foundValue = 1;
			}
		}
		if(!$foundMB) {
			msg("CustomScan: No musicbrainzIndex index found in customscan_contributor_attributes, creating index...\n");
			eval { $dbh->do("create index musicbrainzIndex on customscan_contributor_attributes (musicbrainz_id);") };
			if ($@) {
				debugMsg("Couldn't add index: $@\n");
			}
		}
		if(!$foundValue) {
			msg("CustomScan: No module_attr_value_idx index found in customscan_contributor_attributes, creating index...\n");
			eval { $dbh->do("create index module_attr_value_idx on customscan_contributor_attributes (module,attr,value);") };
			if ($@) {
				debugMsg("Couldn't add index: $@\n");
			}
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n$@\n";
	}
	$sth->finish();
	$sth = $dbh->prepare("show index from customscan_track_attributes;");
	eval {
		debugMsg("Checking if indexes is needed for customscan_track_attributes\n");
		$sth->execute();
		my $keyname;
		$sth->bind_col( 3, \$keyname );
		my $foundMB = 0;
		my $foundUrl = 0;
		my $foundValue = 0;
		while( $sth->fetch() ) {
			if($keyname eq "musicbrainzIndex") {
				$foundMB = 1;
			}elsif($keyname eq "urlIndex") {
				$foundUrl = 1;
			}elsif($keyname eq "module_attr_value_idx") {
				$foundValue = 1;
			}
		}
		if(!$foundMB) {
			msg("CustomScan: No musicbrainzIndex index found in customscan_track_attributes, creating index...\n");
			eval { $dbh->do("create index musicbrainzIndex on customscan_track_attributes (musicbrainz_id);") };
			if ($@) {
				debugMsg("Couldn't add index: $@\n");
			}
		}
		if(!$foundUrl) {
			msg("CustomScan: No urlIndex index found in customscan_track_attributes, creating index...\n");
			eval { $dbh->do("create index urlIndex on customscan_track_attributes (url(255));") };
			if ($@) {
				debugMsg("Couldn't add index: $@\n");
			}
		}
		if(!$foundValue) {
			msg("CustomScan: No module_attr_value_idx index found in customscan_track_attributes, creating index...\n");
			eval { $dbh->do("create index module_attr_value_idx on customscan_track_attributes (module,attr,value);") };
			if ($@) {
				debugMsg("Couldn't add index: $@\n");
			}
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n$@\n";
	}
	$sth->finish();

	if(Slim::Utils::Prefs::get("plugin_customscan_refresh_startup")) {
		msg("CustomScan: Synchronizing Custom Scan data, please wait...\n");
		refreshData();
		msg("CustomScan: Synchronization finished\n");
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
	$sql = "UPDATE tracks,customscan_track_attributes SET customscan_track_attributes.url=tracks.url, customscan_track_attributes.track=tracks.id where tracks.musicbrainz_id is not null and tracks.musicbrainz_id=customscan_track_attributes.musicbrainz_id and (customscan_track_attributes.url!=tracks.url or customscan_track_attributes.track!=tracks.id) and length(tracks.url)<256";
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
	while($sth->fetch()) {
		$result{uc($module)."_".uc($attr)} = "CUSTOMSCAN_".uc($module)."_".uc($attr);
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

PLUGIN_CUSTOMSCAN_SETTINGS_TITLE
	EN	Settings

PLUGIN_CUSTOMSCAN_PROPERTIES_TITLE
	EN	Configurable properties

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

PLUGIN_CUSTOMSCAN_SCAN_ABORT
	EN	Abort

PLUGIN_CUSTOMSCAN_SCAN_ABORT_QUESTION
	EN	Are you sure you want to abort the scanning process ?

PLUGIN_CUSTOMSCAN_TITLEFORMATS
	EN	Attributes to make available as title formats

SETUP_PLUGIN_CUSTOMSCAN_TITLEFORMATS
	EN	Title formats

PLUGIN_CUSTOMSCAN_SCANNING
	EN	Scanning in progress...

PLUGIN_CUSTOMSCAN_REFRESH
	EN	Refresh scanning status

PLUGIN_CUSTOMSCAN_SETTINGS_MODULE_ENABLED
	EN	Enable in automatic and full scans

PLUGIN_CUSTOMSCAN_MATCHING_ALBUMS
	EN	Matching Albums

PLUGIN_CUSTOMSCAN_MATCHING_SONGS
	EN	Matching Songs
EOF

}

1;

__END__
