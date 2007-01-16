# 				MultiLibrary plugin 
#
#    Copyright (c) 2007 Erland Isaksson (erland_i@hotmail.com)
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

package Plugins::MultiLibrary::Plugin;

use strict;

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use File::Spec::Functions qw(:ALL);
use File::Slurp;
use XML::Simple;
use Data::Dumper;
use HTML::Entities;
use FindBin qw($Bin);
use DBI qw(:sql_types);

if ($::VERSION ge '6.5') {
	eval "use Slim::Schema";
}

# Information on each clients multilibrary
my $htmlTemplate = 'plugins/MultiLibrary/multilibrary_list.html';
my $ds = getCurrentDS();
my $template;
my $libraries = undef;
my $sqlerrors = '';
my %currentLibrary = ();
my $PLUGINVERSION = '1.0';

# Indicator if hooked or not
# 0= No
# 1= Yes
my $MULTILIBRARY_HOOK = 0;

sub getDisplayName {
	return 'PLUGIN_MULTILIBRARY';
}

sub getLibrary {
	my $client = shift;
	my $type = shift;
	
	return undef unless $type;

	debugMsg("Get library: $type\n");
	if(!$libraries) {
		initLibraries($client);
	}
	return undef unless $libraries;
	
	return $libraries->{$type};
}

sub getDisplayText {
	my ($client, $item) = @_;

	my $name = '';
	if($item) {
		$name = $item->{'libraryname'};
		my $library = getCurrentLibrary($client);
		if(defined($library) && $library->{'id'} eq $item->{'id'}) {
			$name .= " (active)";
		}

	}
	return $name;
}


# Returns the overlay to be display next to items in the menu
sub getOverlay {
	my ($client, $item) = @_;
	my $library = getCurrentLibrary($client);
	my $itemId = $item->{'id'};
	if(defined($itemId) && defined($library) && $itemId eq $library->{'id'}) {
		return [undef, undef];
	}else {
		return [undef, Slim::Display::Display::symbol('notesymbol')];
	}
}

sub isLibraryEnabledForClient {
	my $client = shift;
	my $library = shift;
	
	if(defined($library->{'includedclients'})) {
		if(defined($client)) {
			my @clients = split(/,/,$library->{'includedclients'});
			for my $clientName (@clients) {
				if($client->name eq $clientName) {
					return 1;
				}
			}
		}
		return 0;
	}elsif(defined($library->{'excludedclients'})) {
		if(defined($client)) {
			my @clients = split(/,/,$library->{'excludedclients'});
			for my $clientName (@clients) {
				if($client->name eq $clientName) {
					return 0;
				}
			}
		}
		return 1;
	}else {
		return 1;
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
	initLibraries();
	for my $library (keys %$libraries) {
		if(isLibraryEnabledForClient($client,$libraries->{$library})) {
			my %item = (
				'id' => $library,
				'value' => $library,
				'libraryname' => $libraries->{$library}->{'name'}
			);
			push @listRef, \%item;
		}
	}
	@listRef = sort { $a->{'libraryname'} cmp $b->{'libraryname'} } @listRef;

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header     => '{PLUGIN_MULTILIBRARY} {count}',
		listRef    => \@listRef,
		name       => \&getDisplayText,
		overlayRef => \&getOverlay,
		modeName   => 'PLUGIN.MultiLibrary',
		parentMode => 'PLUGIN.MultiLibrary',
		onPlay     => sub {
			my ($client, $item) = @_;
			selectLibrary($client,$item->{'id'},1);
		},
		onAdd      => sub {
			my ($client, $item) = @_;
			debugMsg("Do nothing on add\n");
		},
		onRight    => sub {
			my ($client, $item) = @_;
			selectLibrary($client,$item->{'id'},1);
		},
	);
	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub selectLibrary {
	my $client = shift;
	my $libraryId = shift;
	my $showUser = shift;

	my $key = undef;
	if(defined($client)) {
		$key = $client;
		if(defined($client->syncgroupid)) {
			$key = "SyncGroup".$client->syncgroupid;
		}
	}
	if(defined($key) && defined($libraryId) && defined($libraries->{$libraryId})) {
		$currentLibrary{$key} = $libraryId;
		$client->prefSet('plugin_multilibrary_activelibrary',$libraryId);
		$client->prefSet('plugin_multilibrary_activelibraryno',$libraries->{$libraryId}->{'libraryno'});
		if($showUser) {
			$client->showBriefly(
				$client->string( 'PLUGIN_MULTILIBRARY'),
				$client->string( 'PLUGIN_MULTILIBRARY_ACTIVATING_LIBRARY').": ".$libraries->{$libraryId}->{'name'},
				1);
		}
		
	}
}
sub initLibraries {
	my $client = shift;
	my @pluginDirs = ();
	if ($::VERSION ge '6.5') {
		@pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	}else {
		@pluginDirs = catdir($Bin, "Plugins");
	}
	my %localLibraries = ();
	my $templates = readTemplateConfiguration();
	
	my $libraryDir = Slim::Utils::Prefs::get("plugin_multilibrary_library_directory");
	debugMsg("Searching for library definitions in: $libraryDir\n");
	
	if (defined $libraryDir && -d $libraryDir) {
		readLibrariesFromDir($client,0,$libraryDir,\%localLibraries);
		readTemplateLibrariesFromDir($client,0,$libraryDir,\%localLibraries,$templates);
	}else {
		debugMsg("Skipping library folder scan - library dir is undefined.\n");
	}

	my $dbh = getCurrentDBH();

	for my $libraryid (keys %localLibraries) {
		my $library = $localLibraries{$libraryid};
		my $sth = $dbh->prepare("select id from multilibrary_libraries where libraryid=?");
		$sth->bind_param(1,$libraryid,SQL_VARCHAR);
		$sth->execute();
			
		my $id;
		$sth->bind_col(1, \$id);
		if($sth->fetch()) {
			$sth->finish();
			$sth = $dbh->prepare("UPDATE multilibrary_libraries set name=? where id=?");
			$sth->bind_param(1,$library->{'name'},SQL_VARCHAR);
			$sth->bind_param(2,$id,SQL_INTEGER);
			$sth->execute();
		}else {
			$sth->finish();
			$sth = $dbh->prepare("INSERT into multilibrary_libraries (libraryid,name) values (?,?)");
			$sth->bind_param(1,$libraryid,SQL_VARCHAR);
			$sth->bind_param(2,$library->{'name'},SQL_VARCHAR);
			$sth->execute();
			$sth->finish();
			$sth = $dbh->prepare("select id from multilibrary_libraries where libraryid=?");
			$sth->bind_param(1,$libraryid,SQL_VARCHAR);
			$sth->execute();
			$sth->bind_col(1, \$id);
			$sth->fetch();
		}
		$localLibraries{$libraryid}->{'libraryno'} = $id;
	}

	$libraries = \%localLibraries;

}

sub getCustomSkipFilterTypes {
	my @result = ();
	my %notactive = (
		'id' => 'multilibrary_notactive',
		'name' => 'Not Active Library',
		'description' => 'Skip tracks which dont exist in currently active library'
	);
	push @result, \%notactive;
	return \@result;
}

sub checkCustomSkipFilterType	 {
	my $client = shift;
	my $filter = shift;
	my $track = shift;

	if($filter->{'id'} eq 'multilibrary_notactive') {
		my $dbh = getCurrentDBH();
		my $library = getCurrentLibrary($client);
		if(defined($library)) {
			my $sth = $dbh->prepare("select track from multilibrary_track where library=? and track=?");
			$sth->bind_param(1,$library->{'libraryno'},SQL_INTEGER);
			$sth->bind_param(2,$track->id,SQL_INTEGER);
			$sth->execute();
			my $id = undef;
			$sth->bind_col(1, \$id);
			if(!$sth->fetch()) {
				return 1;
			}
		}

	}
	return 0;
}

sub getCustomBrowseMenus {
	my $client = shift;
	my @result = ();

	for my $libraryid (keys %$libraries) {
		my $library = $libraries->{$libraryid};
		my @pluginDirs = ();
		if ($::VERSION ge '6.5') {
			@pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
		}else {
			@pluginDirs = catdir($Bin, "Plugins");
		}
		for my $plugindir (@pluginDirs) {
			my $templateDir = catdir($plugindir,'MultiLibrary','Menus');
			next unless -d $templateDir;
			my @dircontents = Slim::Utils::Misc::readDirectory($templateDir,'xml');
			for my $item (@dircontents) {
				next if -d catdir($templateDir,$item);
				my $templateId = $item;
				$templateId =~ s/\.xml$//;
				my $path = catfile($templateDir,$item);
				my $content = eval { read_file($path) };
				if(defined($content)) {
					my %parameters = (
						'libraryid' => $libraryid,
						'libraryno' => $library->{'libraryno'},
						'libraryname' => $library->{'name'}
					);
					if(defined($library->{'includedclients'})) {
						$parameters{'includedclients'} = '<value>'.$library->{'includedclients'}.'</value>';
					}else {
						$parameters{'includedclients'} = '';
					}
					if(defined($library->{'excludedclients'})) {
						$parameters{'excludedclients'} = '<value>'.$library->{'excludedclients'}.'</value>';
					}else {
						$parameters{'excludedclients'} = '';
					}
					$content = replaceParameters($content,\%parameters);
					my %templateItem = (
						'id' => $libraryid.'_'.$templateId,
						'libraryid' => $libraryid,
						'libraryno' => $library->{'libraryno'},
						'libraryname' => $library->{'name'},
						'librarytype' => $item,
						'type' => 'simple',
						'menu' => $content
					);
					push @result,\%templateItem;
				}
			}
		}
	}
	return \@result;
}

sub getCustomBrowseMenuData {
	my $client = shift;
	my $menu = shift;

	if(defined($menu->{'libraryid'}) && defined($libraries->{$menu->{'libraryid'}})) {
		my $library = $libraries->{$menu->{'libraryid'}};
		my @pluginDirs = ();
		if ($::VERSION ge '6.5') {
			@pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
		}else {
			@pluginDirs = catdir($Bin, "Plugins");
		}
		for my $plugindir (@pluginDirs) {
			my $templateDir = catdir($plugindir,'MultiLibrary','Menus');
			next unless -d $templateDir;
			next if -d catdir($templateDir,$menu->{'librarytype'});
			my $templateId = $menu->{'libraryid'};
			my $path = catfile($templateDir,$menu->{'librarytype'});
			my $content = eval { read_file($path) };
			if(defined($content)) {
				my %parameters = (
					'libraryid' => $menu->{'libraryid'},
					'libraryno' => $library->{'libraryno'},
					'libraryname' => $library->{'name'}
				);
				$content = replaceParameters($content,\%parameters);
				return $content;
			}
		}
	}
	return undef;
}

sub parseLibraryContent {
	my $client = shift;
	my $item = shift;
	my $content = shift;
	my $libraries = shift;
	my $defaultLibrary = shift;

	my $libraryId = $item;
	$libraryId =~ s/\.ml\.xml//;
	my $errorMsg = undef;
        if ( $content ) {
	    $content = Slim::Utils::Unicode::utf8decode($content,'utf8');
            my $xml = eval { 	XMLin($content, forcearray => ["item"], keyattr => []) };
            #debugMsg(Dumper($xml));
            if ($@) {
		    $errorMsg = "$@";
                    errorMsg("MultiLibrary: Failed to parse library configuration because:\n$@\n");
            }else {
		my $include = isLibraryEnabled($client,$xml);

		my $disabled = 0;
		if(defined($xml->{'library'})) {
			$xml->{'library'}->{'id'} = escape($libraryId);
		}
		if(defined($xml->{'library'}) && defined($xml->{'library'}->{'id'})) {
			my $enabled = Slim::Utils::Prefs::get('plugin_multilibrary_library_'.escape($xml->{'library'}->{'id'}).'_enabled');
			if(defined($enabled) && !$enabled) {
				$disabled = 1;
			}elsif(!defined($enabled)) {
				if(defined($xml->{'defaultdisabled'}) && $xml->{'defaultdisabled'}) {
					$disabled = 1;
				}
			}
		}
		
		if($include && !$disabled) {
			$xml->{'library'}->{'enabled'}=1;
			if($defaultLibrary) {
				$xml->{'library'}->{'defaultlibrary'} = 1;
			}else {
				$xml->{'library'}->{'customlibrary'} = 1;
			}
	                $libraries->{$libraryId} = $xml->{'library'};
		}elsif($include && $disabled) {
			$xml->{'library'}->{'enabled'}=0;
			if($defaultLibrary) {
				$xml->{'library'}->{'defaultlibrary'} = 1;
			}else {
				$xml->{'library'}->{'customlibrary'} = 1;
			}
	                $libraries->{$libraryId} = $xml->{'library'};
		}
            }
    
            # Release content
            undef $content;
        }else {
            if ($@) {
                    $errorMsg = "Incorrect information in library data: $@";
                    errorMsg("MultiLibrary: Unable to read library configuration:\n$@\n");
            }else {
		$errorMsg = "Incorrect information in library data";
                errorMsg("MultiLibrary: Unable to to read library configuration\n");
            }
        }
	return $errorMsg;
}

sub parseLibraryTemplateContent {
	my $client = shift;
	my $item = shift;
	my $content = shift;
	my $libraries = shift;
	my $defaultLibrary = shift;
	my $templates = shift;
	my $dbh = getCurrentDBH();

	my $libraryId = $item;
	$libraryId =~ s/\.ml\.values\.xml//;
	my $errorMsg = undef;
        if ( $content ) {
		$content = Slim::Utils::Unicode::utf8decode($content,'utf8');
		my $valuesXml = eval { XMLin($content, forcearray => ["parameter","value"], keyattr => []) };
		#debugMsg(Dumper($valuesXml));
		if ($@) {
			$errorMsg = "$@";
			errorMsg("MultiLibrary: Failed to parse library configuration because:\n$@\n");
		}else {
			my $templateId = $valuesXml->{'template'}->{'id'};
			my $template = $templates->{$templateId};
			$templateId =~s/\.xml//;
			my $include = undef;
			if($template) {
				$include = 1;
			}
			my $templateFile = $templateId.".template";
			my %templateParameters = ();
			my $parameters = $valuesXml->{'template'}->{'parameter'};
			for my $p (@$parameters) {
				my $values = $p->{'value'};
				my $value = '';
				for my $v (@$values) {
					if($value ne '') {
						$value .= ',';
					}
					if($p->{'quotevalue'}) {
						$value .= $dbh->quote(encode_entities($v));
					}else {
						$value .= encode_entities($v);
					}
				}
				#debugMsg("Setting: ".$p->{'id'}."=".$value."\n");
				$templateParameters{$p->{'id'}}=$value;
			}
			if(defined($template->{'parameter'})) {
				my $parameters = $template->{'parameter'};
				for my $p (@$parameters) {
					if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
						if(!defined($templateParameters{$p->{'id'}})) {
							my $value = $p->{'value'};
							if(!defined($value)) {
								$value='';
							}
							debugMsg("Setting default value ".$p->{'id'}."=".$value."\n");
							$templateParameters{$p->{'id'}} = $value;
						}
					}
				}
			}
			my $templateFileData = undef;
			my $doParsing = 1;
			if(defined($template->{'multilibrary_plugin_template'})) {
				my $pluginTemplate = $template->{'multilibrary_plugin_template'};
				if(defined($pluginTemplate->{'type'}) && $pluginTemplate->{'type'} eq 'final') {
					$doParsing = 0;
				}
				$templateFileData = getPluginTemplateData($client,$template,\%templateParameters);
			}else {
				$templateFileData = $templateFile;
			}
			my $libraryData = undef;
			if($doParsing) {
				$libraryData = fillTemplate($templateFileData,\%templateParameters);
			}else {
				$libraryData = $templateFileData;
			}
			$libraryData = Slim::Utils::Unicode::utf8on($libraryData);
			$libraryData = Slim::Utils::Unicode::utf8encode_locale($libraryData);
			#$libraryData = encode_entities($libraryData);
			
			my $xml = eval { 	XMLin($libraryData, forcearray => ["item"], keyattr => []) };
			#debugMsg(Dumper($xml));
			if ($@) {
				$errorMsg = "$@";
				errorMsg("MultiLibrary: Failed to parse library configuration because:\n$@\n");
			}else {
				my $disabled = 0;
				if(defined($xml->{'library'})) {
					$xml->{'library'}->{'id'} = escape($libraryId);
				}
	
				if(defined($xml->{'library'}) && defined($xml->{'library'}->{'id'})) {
					my $enabled = Slim::Utils::Prefs::get('plugin_multilibrary_library_'.escape($xml->{'library'}->{'id'}).'_enabled');
					if(defined($enabled) && !$enabled) {
						$disabled = 1;
					}elsif(!defined($enabled)) {
						if(defined($xml->{'defaultdisabled'}) && $xml->{'defaultdisabled'}) {
							$disabled = 1;
						}
					}
				}
			
				$xml->{'library'}->{'simple'} = 1;
				if($include && !$disabled) {
					$xml->{'library'}->{'enabled'}=1;
					if($defaultLibrary) {
						$xml->{'library'}->{'defaultlibrary'} = 1;
					}elsif(defined($template->{'customtemplate'})) {
						$xml->{'library'}->{'customlibrary'} = 1;
					}
			                $libraries->{$libraryId} = $xml->{'library'};
				}elsif($include && $disabled) {
					$xml->{'library'}->{'enabled'}=0;
					if($defaultLibrary) {
						$xml->{'library'}->{'defaultlibrary'} = 1;
					}elsif(defined($template->{'customtemplate'})) {
						$xml->{'library'}->{'customlibrary'} = 1;
					}
			                $libraries->{$libraryId} = $xml->{'library'};
				}
			}
	    
			# Release content
			undef $libraryData;
			undef $content;
		}
	}else {
		$errorMsg = "Incorrect information in library data";
		errorMsg("MultiLibrary: Unable to to read library configuration\n");
	}
	return $errorMsg;
}

sub isLibraryEnabled {
	my $client = shift;
	my $xml = shift;

	my $include = 1;
	if(defined($xml->{'minslimserverversion'})) {
		if($::VERSION lt $xml->{'minslimserverversion'}) {
			$include = 0;
		}
	}
	if(defined($xml->{'maxslimserverversion'})) {
		if($::VERSION gt $xml->{'maxslimserverversion'}) {
			$include = 0;
		}
	}
	if(defined($xml->{'requireplugins'}) && $include) {
		$include = 0;
		my $requiredPlugins = $xml->{'requireplugins'};
		my $enabledPlugin = 1;
		foreach my $plugin (split /,/, $requiredPlugins) {
			if($enabledPlugin) {
				if ($::VERSION ge '6.5') {
					$enabledPlugin = Slim::Utils::PluginManager::enabledPlugin($plugin,$client);
				}else {
					$enabledPlugin = grep(/$plugin/,Slim::Buttons::Plugins::enabledPlugins($client));
				}
			}
		}
		if($enabledPlugin) {
			$include = 1;
		}
	}
	if($include && defined($xml->{'minpluginversion'}) && $xml->{'minpluginversion'} =~ /(\d+)\.(\d+).*/) {
		my $downloadMajor = $1;
		my $downloadMinor = $2;
		if($PLUGINVERSION =~ /(\d+)\.(\d+).*/) {
			my $pluginMajor = $1;
			my $pluginMinor = $2;
			if($pluginMajor>=$downloadMajor && $pluginMinor>=$downloadMinor) {
				$include = 1;
			}else {
				$include = 0;
			}
		}
	}	
	if(defined($xml->{'database'}) && $include) {
		$include = 0;
		my $driver = Slim::Utils::Prefs::get('dbsource');
		$driver =~ s/dbi:(.*?):(.*)$/$1/;
		if($driver eq $xml->{'database'}) {
			$include = 1;
		}
	}
	return $include;
}

sub initPlugin {
	checkDefaults();
	initDatabase();
	initLibraries();
	if(Slim::Utils::Prefs::get("plugin_multilibrary_refresh_startup")) {
		refreshLibraries();
	}
	if ( !$MULTILIBRARY_HOOK ) {
		installHook();
	}
}

sub shutdownPlugin {
        if ($MULTILIBRARY_HOOK) {
                uninstallHook();
        }
}

# Hook the plugin to the play events.
# Do this as soon as possible during startup.
sub installHook()
{  
	debugMsg("Hook activated.\n");
	Slim::Control::Request::subscribe(\&Plugins::MultiLibrary::Plugin::rescanCallback,[['rescan']]);
	$MULTILIBRARY_HOOK=1;
}

# Unhook the plugin's play event callback function. 
# Do this as the plugin shuts down, if possible.
sub uninstallHook()
{
	debugMsg("Hook deactivated.\n");
	Slim::Control::Request::unsubscribe(\&Plugins::MultiLibrary::Plugin::rescanCallback);
	$MULTILIBRARY_HOOK=0;
}

sub rescanCallback($) 
{
	debugMsg("Entering rescanCallback\n");
	# These are the two passed parameters
	my $request=shift;
	my $client = $request->client();

	######################################
	## Rescan finished
	######################################
	if ( $request->isCommand([['rescan'],['done']]) )
	{
		if(Slim::Utils::Prefs::get("plugin_multilibrary_refresh_rescan")) {
			refreshLibraries();
		}

	}
	debugMsg("Exiting rescanCallback\n");
}

sub refreshLibraries {
	msg("MultiLibrary: Synchronizing libraries data, please wait...\n");
	eval {
		my $dbh = getCurrentDBH();
		my $libraryIds = '';
		for my $key (keys %$libraries) {
			if($libraryIds ne '') {
				$libraryIds .= ',';
			}
			$libraryIds .= $dbh->quote($key);
		}
	
		# remove non existent libraries
		debugMsg("Deleting removed libraries\n");
		my $sth = undef;
		if($libraryIds ne '') {
			$sth = $dbh->prepare("DELETE from multilibrary_libraries where libraryid not in ($libraryIds)");
		}else {
			$sth = $dbh->prepare("DELETE from multilibrary_libraries");
		}
		$sth->execute();
		$sth->finish();

		$sth = $dbh->prepare("DELETE from multilibrary_track where library not in (select id from multilibrary_libraries)");
		$sth->execute();
		$sth->finish();
	
		$sth = $dbh->prepare("DELETE from multilibrary_album where library not in (select id from multilibrary_libraries)");
		$sth->execute();
		$sth->finish();

		$sth = $dbh->prepare("DELETE from multilibrary_contributor where library not in (select id from multilibrary_libraries)");
		$sth->execute();
		$sth->finish();

		$sth = $dbh->prepare("DELETE from multilibrary_year where library not in (select id from multilibrary_libraries)");
		$sth->execute();
		$sth->finish();

		$sth = $dbh->prepare("DELETE from multilibrary_genre where library not in (select id from multilibrary_libraries)");
		$sth->execute();
		$sth->finish();

		# Synchronize existing libraries
		for my $key (keys %$libraries) {
			eval {
				debugMsg("Checking library $key\n");
				my $library = $libraries->{$key};
				$sth = $dbh->prepare("select id from multilibrary_libraries where libraryid=?");
				$sth->bind_param(1,$key,SQL_VARCHAR);
				$sth->execute();
					
				my $id;
				$sth->bind_col(1, \$id);
				if($sth->fetch()) {
					$sth->finish();
					$sth = $dbh->prepare("UPDATE multilibrary_libraries set name=? where id=?");
					$sth->bind_param(1,$library->{'name'},SQL_VARCHAR);
					$sth->bind_param(2,$id,SQL_INTEGER);
					$sth->execute();
				}else {
					$sth->finish();
					$sth = $dbh->prepare("INSERT into multilibrary_libraries (libraryid,name) values (?,?)");
					$sth->bind_param(1,$key,SQL_VARCHAR);
					$sth->bind_param(2,$library->{'name'},SQL_VARCHAR);
					$sth->execute();
					$sth->finish();
					$sth = $dbh->prepare("select id from multilibrary_libraries where libraryid=?");
					$sth->bind_param(1,$key,SQL_VARCHAR);
					$sth->execute();
					$sth->bind_col(1, \$id);
					$sth->fetch();
				}
				if(defined($id)) {
					debugMsg("Deleting data for library $key\n");
					$sth = $dbh->prepare("DELETE from multilibrary_track where library=?");
					$sth->bind_param(1,$id,SQL_INTEGER);
					$sth->execute();
					$sth->finish();
					$sth = $dbh->prepare("DELETE from multilibrary_album where library=?");
					$sth->bind_param(1,$id,SQL_INTEGER);
					$sth->execute();
					$sth->finish();
					$sth = $dbh->prepare("DELETE from multilibrary_contributor where library=?");
					$sth->bind_param(1,$id,SQL_INTEGER);
					$sth->execute();
					$sth->finish();
					$sth = $dbh->prepare("DELETE from multilibrary_genre where library=?");
					$sth->bind_param(1,$id,SQL_INTEGER);
					$sth->execute();
					$sth->finish();
					$sth = $dbh->prepare("DELETE from multilibrary_year where library=?");
					$sth->bind_param(1,$id,SQL_INTEGER);
					$sth->execute();
					$sth->finish();
					if(defined($library->{'track'})) {
						my $sql = $library->{'track'}->{'data'};
						if(defined($sql)) {
							debugMsg("Adding new data for library $key\n");
							my %keywords = (
								'library' => $id
							);
							$sql = replaceParameters($sql,\%keywords);
							$sth = $dbh->prepare('INSERT INTO multilibrary_track (library,track) '.$sql);
							$sth->execute();
							$sth->finish();
							
							$sth = $dbh->prepare('INSERT INTO multilibrary_album (library,album) SELECT ?,tracks.album FROM tracks,multilibrary_track where tracks.id=multilibrary_track.track group by tracks.album');
							$sth->bind_param(1,$id,SQL_INTEGER);
							$sth->execute();
							$sth->finish();
		
							$sth = $dbh->prepare('INSERT INTO multilibrary_contributor (library,contributor) SELECT ?,contributor_track.contributor FROM tracks,contributor_track,multilibrary_track where tracks.id=multilibrary_track.track and tracks.id=contributor_track.track group by contributor_track.contributor');
							$sth->bind_param(1,$id,SQL_INTEGER);
							$sth->execute();
							$sth->finish();

							$sth = $dbh->prepare('INSERT INTO multilibrary_year (library,year) SELECT ?,tracks.year FROM tracks,multilibrary_track where tracks.id=multilibrary_track.track group by tracks.year');
							$sth->bind_param(1,$id,SQL_INTEGER);
							$sth->execute();
							$sth->finish();

							$sth = $dbh->prepare('INSERT INTO multilibrary_genre (library,genre) SELECT ?,genre_track.genre FROM tracks,genre_track,multilibrary_track where tracks.id=multilibrary_track.track and tracks.id=genre_track.track group by genre_track.genre');
							$sth->bind_param(1,$id,SQL_INTEGER);
							$sth->execute();
							$sth->finish();
						}
					}
				}
			};
			if( $@ ) {
			    	warn "Database error: $DBI::errstr\n$@\n";
			}		
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n$@\n";
	}		
	msg("MultiLibrary: Synchronization finished\n");
}


sub replaceParameters {
    my $originalValue = shift;
    my $parameters = shift;
    my $dbh = getCurrentDBH();

    if(defined($parameters)) {
        for my $param (keys %$parameters) {
            my $value = $dbh->quote($parameters->{$param});
	    $value = substr($value, 1, -1);
	    $value = Slim::Utils::Unicode::utf8on($value);
	    $value = Slim::Utils::Unicode::utf8encode_locale($value);
            $originalValue =~ s/\{$param\}/$value/g;
        }
    }
    while($originalValue =~ m/\{property\.(.*?)\}/) {
	my $propertyValue = Slim::Utils::Prefs::get($1);
	if(defined($propertyValue)) {
		$propertyValue = $dbh->quote($propertyValue);
	    	$propertyValue = substr($propertyValue, 1, -1);
		$originalValue =~ s/\{property\.$1\}/$propertyValue/g;
	}else {
		$originalValue =~ s/\{property\..*?\}//g;
	}
    }

    return $originalValue;
}

sub initDatabase {
	my $driver = Slim::Utils::Prefs::get('dbsource');
	$driver =~ s/dbi:(.*?):(.*)$/$1/;
    
	#Check if tables exists and create them if not
	debugMsg("Checking if multilibrary_track database table exists\n");
	my $dbh = getCurrentDBH();
	my $st = $dbh->table_info();
	my $tblexists;
	while (my ( $qual, $owner, $table, $type ) = $st->fetchrow_array()) {
		if($table eq "multilibrary_track") {
			$tblexists=1;
		}
	}
	unless ($tblexists) {
		msg("MultiLibrary: Creating database tables\n");
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
					updateCharSet("multilibrary_track",$charset,$collate);
					updateCharSet("multilibrary_album",$charset,$collate);
					updateCharSet("multilibrary_contributor",$charset,$collate);
					updateCharSet("multilibrary_libraries",$charset,$collate);
				}
			}
		}
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n";
	}
	$sth->finish();
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

sub executeSQLFile {
        my $file  = shift;
	my $driver = Slim::Utils::Prefs::get('dbsource');
	$driver =~ s/dbi:(.*?):(.*)$/$1/;

        my $sqlFile;
	for my $plugindir (Slim::Utils::OSDetect::dirsFor('Plugins')) {
		opendir(DIR, catdir($plugindir,"MultiLibrary")) || next;
       		$sqlFile = catdir($plugindir,"MultiLibrary", "SQL", $driver, $file);
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

sub webPages {

	my %pages = (
		"multilibrary_list\.(?:htm|xml)"     => \&handleWebList,
		"multilibrary_refreshlibraries\.(?:htm|xml)"     => \&handleWebRefreshLibraries,
		"multilibrary_editlibrary\.(?:htm|xml)"      => \&handleWebEditLibrary,
		"multilibrary_newlibrarytypes\.(?:htm|xml)"      => \&handleWebNewLibraryTypes,
                "multilibrary_newlibraryparameters\.(?:htm|xml)"     => \&handleWebNewLibraryParameters,
		"multilibrary_newlibrary\.(?:htm|xml)"      => \&handleWebNewLibrary,
                "multilibrary_savenewsimplelibrary\.(?:htm|xml)"     => \&handleWebSaveNewSimpleLibrary,
                "multilibrary_savesimplelibrary\.(?:htm|xml)"     => \&handleWebSaveSimpleLibrary,
		"multilibrary_savelibrary\.(?:htm|xml)"      => \&handleWebSaveLibrary,
		"multilibrary_savenewlibrary\.(?:htm|xml)"      => \&handleWebSaveNewLibrary,
		"multilibrary_removelibrary\.(?:htm|xml)"      => \&handleWebRemoveLibrary,
		"multilibrary_selectlibrary\.(?:htm|xml)"      => \&handleWebSelectLibrary,
	);

	my $value = $htmlTemplate;

	if (grep { /^MultiLibrary::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

		$value = undef;
	} 

	#Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_MULTILIBRARY' => $value });

	return (\%pages,$value);
}

sub getCurrentLibrary {
	my $client = shift;
	if(defined($client)) {
		if(!$libraries) {
			initLibraries();
		}
		my $key = $client;
		if(defined($client->syncgroupid)) {
			$key = "SyncGroup".$client->syncgroupid;
		}
		if(defined($currentLibrary{$key}) && defined($libraries->{$currentLibrary{$key}}) && isLibraryEnabledForClient($client,$libraries->{$currentLibrary{$key}})) {
			return $libraries->{$currentLibrary{$key}};
		}else {
			my $library = $client->prefGet('plugin_multilibrary_activelibrary');
			if(defined($library) && defined($libraries->{$library}) && isLibraryEnabledForClient($client,$libraries->{$library})) {
				$currentLibrary{$key} = $library;
				return $libraries->{$library};
			}else {
				if(scalar(keys %$libraries)==1) {
					for my $key (keys %$libraries) {
						if(isLibraryEnabledForClient($client,$libraries->{$key})) {
							$currentLibrary{$key} = $key;
							$client->prefSet('plugin_multilibrary_activelibrary',$key);
							$client->prefSet('plugin_multilibrary_activelibraryno',$libraries->{$key}->{'libraryno'});
							return $libraries->{$key};
						}
					}
				}
			}
		}	
	}
	$client->prefDelete('plugin_multilibrary_activelibrary');
	return undef;
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	# Pass on the current pref values and now playing info
	if(!defined($params->{'donotrefresh'})) {
		initLibraries($client);
	}
	my $library = getCurrentLibrary($client);
	my $name = undef;
	my @weblibraries = ();
	for my $key (keys %$libraries) {
		my %weblibrary = ();
		my $lib = $libraries->{$key};
		for my $attr (keys %$lib) {
			$weblibrary{$attr} = $lib->{$attr};
		}
		if(!isLibraryEnabledForClient($client,\%weblibrary)) {
			$weblibrary{'enabled'} = 0;
		}
		push @weblibraries,\%weblibrary;
	}
	@weblibraries = sort { $a->{'name'} cmp $b->{'name'} } @weblibraries;

	$params->{'pluginMultiLibraryLibraries'} = \@weblibraries;
	$params->{'pluginMultiLibraryActiveLibrary'} = $library;
	if ($::VERSION ge '6.5') {
		$params->{'pluginMultiLibrarySlimserver65'} = 1;
	}
	$params->{'pluginMultiLibraryVersion'} = $PLUGINVERSION;
	if(defined($params->{'redirect'})) {
		return Slim::Web::HTTP::filltemplatefile('plugins/MultiLibrary/multilibrary_redirect.html', $params);
	}else {
		return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
	}
}

sub handleWebRefreshLibraries {
	my ($client, $params) = @_;

	refreshLibraries($client);
	return handleWebList($client,$params);
}

sub handleWebSelectLibrary {
	my ($client, $params) = @_;
	initLibraries($client);

	selectLibrary($client,$params->{'type'});
	return handleWebList($client,$params);
}

# Draws the plugin's edit library web page
sub handleWebEditLibrary {
	my ($client, $params) = @_;

	$params->{'pluginMultiLibraryError'} = undef;
	if ($::VERSION ge '6.5') {
		$params->{'pluginMultiLibrarySlimserver65'} = 1;
	}
	if(defined($params->{'redirect'})) {
		$params->{'pluginMultiLibraryRedirect'} = 1;
	}

	if ($params->{'type'}) {
		my $library = getLibrary($client,$params->{'type'});
		if($library) {
			if(defined($library->{'simple'})) {
				my $templateData = loadTemplateValues($params->{'type'}.".ml.values.xml");
	
				if(defined($templateData)) {
					my $templates = readTemplateConfiguration($client);
					my $template = $templates->{$templateData->{'id'}};
					if(defined($template)) {
						my %currentParameterValues = ();
						my $templateDataParameters = $templateData->{'parameter'};
						for my $p (@$templateDataParameters) {
							my $values = $p->{'value'};
							if(!defined($values)) {
								push @$values,'';
							}
							my %valuesHash = ();
							for my $v (@$values) {
								$valuesHash{$v} = $v;
							}
							if(%valuesHash) {
								$currentParameterValues{$p->{'id'}} = \%valuesHash;
							}
						}
						if(defined($template->{'parameter'})) {
							my $parameters = $template->{'parameter'};
							my @parametersToSelect = ();
							for my $p (@$parameters) {
								if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
									addValuesToTemplateParameter($p,$currentParameterValues{$p->{'id'}});
									push @parametersToSelect,$p;
								}
							}
							$params->{'pluginMultiLibraryEditLibraryParameters'} = \@parametersToSelect;
						}
						$params->{'pluginMultiLibraryEditLibraryFile'} = $params->{'type'}.".ml.values.xml";
						$params->{'pluginMultiLibraryEditLibraryTemplate'} = $templateData->{'id'};
						$params->{'pluginMultiLibraryEditLibraryFileUnescaped'} = unescape($params->{'pluginMultiLibraryEditLibraryFile'});
						return Slim::Web::HTTP::filltemplatefile('plugins/MultiLibrary/multilibrary_editsimplelibrary.html', $params);
					}
				}
			}else {
				my $data = loadLibraryDataFromAnyDir($params->{'type'}.".ml.xml");

				if($data) {
					$data = encode_entities($data);
				}

				$params->{'pluginMultiLibraryEditLibraryFile'} = escape($params->{'type'}.".ml.xml");
				$params->{'pluginMultiLibraryEditLibraryName'} = $library->{'name'};
				$params->{'pluginMultiLibraryEditLibraryData'} = $data;
				$params->{'pluginMultiLibraryEditLibraryFileUnescaped'} = unescape($params->{'pluginMultiLibraryEditLibraryFile'});
				return Slim::Web::HTTP::filltemplatefile('plugins/MultiLibrary/multilibrary_editlibrary.html', $params);
			}
		}else {
			warn "Cannot find: ".$params->{'type'};
		}
	}
	return handleWebList($client,$params);
}

sub loadLibraryDataFromAnyDir {
	my $file = shift;
	my $data = undef;

	my $browseDir = Slim::Utils::Prefs::get("plugin_multilibrary_library_directory");
	if (!defined $browseDir || !-d $browseDir) {
		debugMsg("Skipping library configuration - directory is undefined\n");
	}else {
		$data = loadLibraryData($browseDir,$file);
	}
	return $data;
}

sub loadLibraryData {
    my $browseDir = shift;
    my $file = shift;

    debugMsg("Loading library data from: $browseDir/$file\n");

    my $path = catfile($browseDir, $file);
    
    return unless -f $path;

    my $content = eval { read_file($path) };
    if ($@) {
    	debugMsg("Failed to load library data because:\n$@\n");
    }
    if(defined($content)) {
	debugMsg("Loading of library data succeeded\n");
    }
    return $content;
}




sub addParameterValues {
	my $client = shift;
	my $listRef = shift;
	my $parameter = shift;
	
	debugMsg("Getting values for ".$parameter->{'name'}." of type ".$parameter->{'type'}."\n");
	my $sql = undef;
	if(lc($parameter->{'type'}) eq 'album') {
		$sql = "select id,title from albums order by titlesort";
	}elsif(lc($parameter->{'type'}) eq 'artist') {
		$sql = "select id,name from contributors where namesort is not null order by namesort";
	}elsif(lc($parameter->{'type'}) eq 'genre') {
		$sql = "select id,name from genres order by namesort";
	}elsif(lc($parameter->{'type'}) eq 'year') {
		$sql = "select year,year from tracks where year is not null group by year order by year";
	}elsif(lc($parameter->{'type'}) eq 'playlist') {
		$sql = "select playlist_track.playlist,tracks.title from tracks, playlist_track where tracks.id=playlist_track.playlist group by playlist_track.playlist order by titlesort";
	}elsif(lc($parameter->{'type'}) eq 'list') {
		my $value = $parameter->{'definition'};
		if(defined($value) && $value ne "" ) {
			my @values = split(/,/,$value);
			if(@values) {
				for my $valueItem (@values) {
					my @valueItemArray = split(/:/,$valueItem);
					my $id = shift @valueItemArray;
					my $name = shift @valueItemArray;
					
					if(defined($id)) {
						my %listitem = (
							'id' => $id
						);
						if(defined($name)) {
							$listitem{'name'}=$name;
						}else {
							$listitem{'name'}=$id;
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
				my $parameter = $client->param('multilibrary_parameter_'.$i);
				my $value = $parameter->{'id'};
				my $parameterid = "\'LibraryParameter".$i."\'";
				debugMsg("Replacing ".$parameterid." with ".$value."\n");
				$sql =~ s/$parameterid/$value/g;
			}
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
				$sth->bind_columns( undef, \$id,\$name);
				while( $sth->fetch() ) {
					my %listitem = (
						'id' => $id,
						'name' => Slim::Utils::Unicode::utf8decode($name,'utf8')
					);
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

sub handleWebNewLibraryTypes {
	my ($client, $params) = @_;
        if ($::VERSION ge '6.5') {
                $params->{'pluginMultiLibrarySlimserver65'} = 1;
        }
	if(defined($params->{'redirect'})) {
		$params->{'pluginMultiLibraryRedirect'} = 1;
	}
	my $templatesHash = readTemplateConfiguration($client);

	$params->{'pluginMultiLibraryTemplates'} = $templatesHash;
	$params->{'pluginMultiLibraryPostUrl'} = "multilibrary_newlibraryparameters.html";
	
        return Slim::Web::HTTP::filltemplatefile('plugins/MultiLibrary/multilibrary_newlibrarytypes.html', $params);
}

sub handleWebNewLibraryParameters {
	my ($client, $params) = @_;
        if ($::VERSION ge '6.5') {
                $params->{'pluginMultiLibrarySlimserver65'} = 1;
        }
	if(defined($params->{'redirect'})) {
		$params->{'pluginMultiLibraryRedirect'} = 1;
	}
	$params->{'pluginMultiLibraryNewLibraryTemplate'} = $params->{'librarytemplate'};
	my $templates = readTemplateConfiguration($client);
	my $template = $templates->{$params->{'librarytemplate'}};
	my @parametersToSelect = ();
	if(defined($template->{'parameter'})) {
		my $parameters = $template->{'parameter'};
		for my $p (@$parameters) {
			if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
				addValuesToTemplateParameter($p);
				push @parametersToSelect,$p;
			}
		}
	}
	$params->{'pluginMultiLibraryNewLibraryParameters'} = \@parametersToSelect;
        return Slim::Web::HTTP::filltemplatefile('plugins/MultiLibrary/multilibrary_newlibraryparameters.html', $params);
}

sub handleWebNewLibrary {
	my ($client, $params) = @_;
        if ($::VERSION ge '6.5') {
                $params->{'pluginMultiLibrarySlimserver65'} = 1;
        }
	if(defined($params->{'redirect'})) {
		$params->{'pluginMultiLibraryRedirect'} = 1;
	}
	my $templateFile = $params->{'librarytemplate'};
	my $libraryFile = $templateFile;
	$templateFile =~ s/\.xml$/.template/;
	$libraryFile =~ s/\.xml$//;
	my $templates = readTemplateConfiguration($client);
	my $template = $templates->{$params->{'librarytemplate'}};
	my $menytype = $params->{'librarytype'};

	if($menytype eq 'advanced') {
		$libraryFile .= ".ml.xml";
		my %templateParameters = ();
		if(defined($template->{'parameter'})) {
			my $parameters = $template->{'parameter'};
			my @parametersToSelect = ();
			for my $p (@$parameters) {
				if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
					addValuesToTemplateParameter($p);
					my $value = getValueOfTemplateParameter($params,$p);
					$templateParameters{$p->{'id'}} = $value;
				}
			}
		}
		my $templateFileData = undef;
		my $doParsing = 1;
		if(defined($template->{'multilibrary_plugin_template'})) {
			my $pluginTemplate = $template->{'multilibrary_plugin_template'};
			if(defined($pluginTemplate->{'type'}) && $pluginTemplate->{'type'} eq 'final') {
				$doParsing = 0;
			}
			$templateFileData = getPluginTemplateData($client,$template,\%templateParameters);
		}else {
			if(defined($template->{'templatefile'})) {
				$templateFile = $template->{'templatefile'};
			}
			$templateFileData = $templateFile;
		}
		my $libraryData = undef;
		if($doParsing) {
			$libraryData = fillTemplate($templateFileData,\%templateParameters);
		}else {
			$libraryData = $$templateFileData;
		}
		$libraryData = Slim::Utils::Unicode::utf8on($libraryData);
		$libraryData = Slim::Utils::Unicode::utf8encode_locale($libraryData);
		$libraryData = encode_entities($libraryData,"&<>\'\"");
		if(length($libraryData)>10000) {
			debugMsg("Warning! Large library configuration, ".length($libraryData)." characters\n");
		        $params->{'pluginMultiLibraryEditLibrarySizeWarning'} = "This library configuration is very large, due to size limitations it might fail when you try to save it<br>Temporary solution: If save fails, click back in web browser and copy the information in the Library configuration field to a text file and save it to the ".Slim::Utils::Prefs::get("plugin_multilibrary_library_directory")." directory with a filename with extension .ml.xml";
		}
        	$params->{'pluginMultiLibraryEditLibraryData'} = $libraryData;
		$params->{'pluginMultiLibraryEditLibraryFile'} = $libraryFile;
		$params->{'pluginMultiLibraryEditLibraryFileUnescaped'} = unescape($libraryFile);
	        return Slim::Web::HTTP::filltemplatefile('plugins/MultiLibrary/multilibrary_newlibrary.html', $params);
	}else {
		my $templateParameters = getParameterArray($params,"libraryparameter_");
		$libraryFile .= ".ml.values.xml";
		$params->{'pluginMultiLibraryEditLibraryParameters'} = $templateParameters;
		$params->{'pluginMultiLibraryNewLibraryTemplate'} = $params->{'librarytemplate'};
		$params->{'pluginMultiLibraryEditLibraryFile'} = $libraryFile;
		$params->{'pluginMultiLibraryEditLibraryFileUnescaped'} = unescape($libraryFile);
	        return Slim::Web::HTTP::filltemplatefile('plugins/MultiLibrary/multilibrary_newsimplelibrary.html', $params);
	}
}

sub handleWebSaveNewSimpleLibrary {
	my ($client, $params) = @_;
	$params->{'pluginMultiLibraryError'} = undef;
	if(defined($params->{'redirect'})) {
		$params->{'pluginMultiLibraryRedirect'} = 1;
	}

	if (!$params->{'file'} && !$params->{'librarytemplate'}) {
		$params->{'pluginMultiLibraryError'} = 'All fields are mandatory';
	}

	my $browseDir = Slim::Utils::Prefs::get("plugin_multilibrary_library_directory");
	
	if (!defined $browseDir || !-d $browseDir) {
		$params->{'pluginMultiLibraryError'} = 'No library directory configured';
	}
	my $file = unescape($params->{'file'});
	my $url = catfile($browseDir, $file);
	
	if(!defined($params->{'pluginMultiLibraryError'}) && -e $url && !$params->{'overwrite'}) {
		$params->{'pluginMultiLibraryError'} = 'Invalid filename, file already exist';
	}

	if(!saveSimpleLibrary($client,$params,$url)) {
		my $templateParameters = getParameterArray($params,"libraryparameter_");
		$params->{'pluginMultiLibraryEditLibraryParameters'} = $templateParameters;
		$params->{'pluginMultiLibraryNewLibraryTemplate'}=$params->{'librarytemplate'};
		return Slim::Web::HTTP::filltemplatefile('plugins/MultiLibrary/multilibrary_newsimplelibrary.html', $params);
	}else {
		$params->{'donotrefresh'} = 1;
		initLibraries($client);
		if(Slim::Utils::Prefs::get("plugin_multilibrary_refresh_save")) {
			refreshLibraries();
		}
		return handleWebList($client,$params)
	}
}

sub handleWebSaveSimpleLibrary {
	my ($client, $params) = @_;
        if ($::VERSION ge '6.5') {
                $params->{'pluginMultiLibrarySlimserver65'} = 1;
        }
	if(defined($params->{'redirect'})) {
		$params->{'pluginMultiLibraryRedirect'} = 1;
	}
	my $templateFile = $params->{'librarytemplate'};
	my $libraryFile = $templateFile;
	$templateFile =~ s/\.xml$/.template/;
	$libraryFile =~ s/\.xml$//;
	my $templates = readTemplateConfiguration($client);
	my $template = $templates->{$params->{'librarytemplate'}};
	my $menytype = $params->{'librarytype'};

	if($menytype eq 'advanced') {
		$libraryFile .= ".ml.xml";
		my %templateParameters = ();
		if(defined($template->{'parameter'})) {
			my $parameters = $template->{'parameter'};
			my @parametersToSelect = ();
			for my $p (@$parameters) {
				if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
					addValuesToTemplateParameter($p);
					my $value = getValueOfTemplateParameter($params,$p);
					$templateParameters{$p->{'id'}} = $value;
				}
			}
		}
		my $templateFileData = undef;
		my $doParsing = 1;
		if(defined($template->{'multilibrary_plugin_template'})) {
			my $pluginTemplate = $template->{'multilibrary_plugin_template'};
			if(defined($pluginTemplate->{'type'}) && $pluginTemplate->{'type'} eq 'final') {
				$doParsing = 0;
			}
			$templateFileData = getPluginTemplateData($client,$template,\%templateParameters);
		}else {
			if(defined($template->{'templatefile'})) {
				$templateFile = $template->{'templatefile'};
			}
			$templateFileData = $templateFile;
		}
		my $libraryData = undef;
		if($doParsing) {
			$libraryData = fillTemplate($templateFileData,\%templateParameters);
		}else {
			$libraryData = $$templateFileData;
		}
		$libraryData = Slim::Utils::Unicode::utf8on($libraryData);
		$libraryData = Slim::Utils::Unicode::utf8encode_locale($libraryData);
		$libraryData = encode_entities($libraryData,"&<>\'\"");
		if(length($libraryData)>10000) {
			debugMsg("Warning! Large library configuration, ".length($libraryData)." characters\n");
		        $params->{'pluginMultiLibraryEditLibrarySizeWarning'} = "This library configuration is very large, due to size limitations it might fail when you try to save it<br>Temporary solution: If save fails, click back in web browser and copy the information in the Library configuration field to a text file and save it to the ".Slim::Utils::Prefs::get("plugin_multilibrary_library_directory")." directory with a filename with extension .ml.xml";
		}
        	$params->{'pluginMultiLibraryEditLibraryData'} = $libraryData;
		$params->{'pluginMultiLibraryEditLibraryDeleteSimple'} = $params->{'file'};
		$params->{'pluginMultiLibraryEditLibraryFile'} = $libraryFile;
		$params->{'pluginMultiLibraryEditLibraryFileUnescaped'} = unescape($libraryFile);
	        return Slim::Web::HTTP::filltemplatefile('plugins/MultiLibrary/multilibrary_editlibrary.html', $params);
	}else {
		$params->{'pluginMultiLibraryError'} = undef;
	
		if (!$params->{'file'}) {
			$params->{'pluginMultiLibraryError'} = 'Filename is mandatory';
		}
	
		my $browseDir = Slim::Utils::Prefs::get("plugin_multilibrary_library_directory");
		
		if (!defined $browseDir || !-d $browseDir) {
			$params->{'pluginMultiLibraryError'} = 'No library directory configured';
		}
		my $file = unescape($params->{'file'});
		my $url = catfile($browseDir, $file);
		
		if(!saveSimpleLibrary($client,$params,$url)) {
			return Slim::Web::HTTP::filltemplatefile('plugins/MultiLibrary/multilibrary_editsimplelibrary.html', $params);
		}else {
			$params->{'donotrefresh'} = 1;
			initLibraries($client);
			if(Slim::Utils::Prefs::get("plugin_multilibrary_refresh_save")) {
				refreshLibraries();
			}
			return handleWebList($client,$params)
		}
	}
}

sub getTemplate {
	if(!defined($template)) {
		my @pluginDirs = ();
		if ($::VERSION ge '6.5') {
			@pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
		}else {
			@pluginDirs = catdir($Bin, "Plugins");
		}
		my @include_path = ();

		for my $plugindir (@pluginDirs) {
			next unless -d catdir($plugindir,'MultiLibrary/Templates');
			my $templateDir = catdir($plugindir,'MultiLibrary/Templates');
			push @include_path,$templateDir;
		}
	
	
		$template = Template->new({
	
	                INCLUDE_PATH => \@include_path,
	                COMPILE_DIR => catdir( Slim::Utils::Prefs::get('cachedir'), 'templates' ),
	                FILTERS => {
	                        'string'        => \&Slim::Utils::Strings::string,
	                        'getstring'     => \&Slim::Utils::Strings::getString,
	                        'resolvestring' => \&Slim::Utils::Strings::resolveString,
	                        'nbsp'          => \&nonBreaking,
	                        'uri'           => \&URI::Escape::uri_escape_utf8,
	                        'unuri'         => \&URI::Escape::uri_unescape,
	                        'utf8decode'    => \&Slim::Utils::Unicode::utf8decode,
	                        'utf8encode'    => \&Slim::Utils::Unicode::utf8encode,
	                        'utf8on'        => \&Slim::Utils::Unicode::utf8on,
	                        'utf8off'       => \&Slim::Utils::Unicode::utf8off,
	                        'fileurl'       => \&templateFileURLFromPath,
	                },
	
	                EVAL_PERL => 1,
	        });
	}
	return $template;
}

sub templateFileURLFromPath {
	my $path = shift;
	$path = Slim::Utils::Misc::fileURLFromPath($path);
	$path =~ s/%/%%/g;
	return $path;
}

sub fillTemplate {
	my $filename = shift;
	my $params = shift;

	
	my $output = '';
	$params->{'LOCALE'} = 'utf-8';
	my $template = getTemplate();
	if(!$template->process($filename,$params,\$output)) {
		msg("MultiLibrary: ERROR parsing template: ".$template->error()."\n");
	}
	return $output;
}

sub addValuesToTemplateParameter {
	my $p = shift;
	my $currentValues = shift;

	if($p->{'type'} =~ '^sql.*') {
		my $listValues = getSQLTemplateData($p->{'data'});
		if(defined($currentValues)) {
			for my $v (@$listValues) {
				if($currentValues->{$v->{'value'}}) {
					$v->{'selected'} = 1;
				}
			}
		}
		$p->{'values'} = $listValues;
	}elsif($p->{'type'} =~ '.*list$' || $p->{'type'} =~ '.*checkboxes$') {
		my @listValues = ();
		my @values = split(/,/,$p->{'data'});
		for my $value (@values){
			my @idName = split(/=/,$value);
			my %listValue = (
				'id' => @idName->[0],
				'name' => @idName->[1]
			);
			if(scalar(@idName)>2) {
				$listValue{'value'} = @idName->[2];
			}else {
				$listValue{'value'} = @idName->[0];
			}
			push @listValues, \%listValue;
		}
		if(defined($currentValues)) {
			for my $v (@listValues) {
				if($currentValues->{$v->{'value'}}) {
					$v->{'selected'} = 1;
				}
			}
		}
		$p->{'values'} = \@listValues;
	}elsif(defined($currentValues)) {
		for my $v (keys %$currentValues) {
			$p->{'value'} = $v;
		}
	}
}

sub getValueOfTemplateParameter {
	my $params = shift;
	my $parameter = shift;

	my $dbh = getCurrentDBH();
	my $result = undef;
	if($parameter->{'type'} =~ /.*multiplelist$/ || $parameter->{'type'} =~ /.*checkboxes$/) {
		my $selectedValues = undef;
		if($parameter->{'type'} =~ /.*multiplelist$/) {
			$selectedValues = getMultipleListQueryParameter($params,'libraryparameter_'.$parameter->{'id'});
		}else {
			$selectedValues = getCheckBoxesQueryParameter($params,'libraryparameter_'.$parameter->{'id'});
		}
		my $values = $parameter->{'values'};
		for my $item (@$values) {
			if(defined($selectedValues->{$item->{'id'}})) {
				if(defined($result)) {
					$result = $result.',';
				}
				if($parameter->{'quotevalue'}) {
					$result = $result.$dbh->quote(encode_entities($item->{'value'},"&<>\'\""));
				}else {
					$result = $result.encode_entities($item->{'value'},"&<>\'\"");
				}
			}
		}
		if(!defined($result)) {
			$result = '';
		}
	}elsif($parameter->{'type'} =~ /.*singlelist$/) {
		my $values = $parameter->{'values'};
		my $selectedValue = $params->{'libraryparameter_'.$parameter->{'id'}};
		for my $item (@$values) {
			if($selectedValue eq $item->{'id'}) {
				if($parameter->{'quotevalue'}) {
					$result = $dbh->quote(encode_entities($item->{'value'},"&<>\'\""));
				}else {
					$result = encode_entities($item->{'value'},"&<>\'\"");
				}
				last;
			}
		}
		if(!defined($result)) {
			$result = '';
		}
	}else{
		if($params->{'libraryparameter_'.$parameter->{'id'}}) {
			if($parameter->{'quotevalue'}) {
				$result = $dbh->quote(encode_entities($params->{'libraryparameter_'.$parameter->{'id'}},"&<>\'\""));
			}else {
				$result = encode_entities($params->{'libraryparameter_'.$parameter->{'id'}},"&<>\'\"");
			}
		}else {
			$result = '';
		}
	}
	if(defined($result)) {
		$result = Slim::Utils::Unicode::utf8on($result);
		$result = Slim::Utils::Unicode::utf8encode_locale($result);
	}
	return $result;
}

sub getXMLValueOfTemplateParameter {
	my $params = shift;
	my $parameter = shift;

	my $dbh = getCurrentDBH();
	my $result = undef;
	if($parameter->{'type'} =~ /.*multiplelist$/ || $parameter->{'type'} =~ /.*checkboxes$/) {
		my $selectedValues = undef;
		if($parameter->{'type'} =~ /.*multiplelist$/) {
			$selectedValues = getMultipleListQueryParameter($params,'libraryparameter_'.$parameter->{'id'});
		}else {
			$selectedValues = getCheckBoxesQueryParameter($params,'libraryparameter_'.$parameter->{'id'});
		}
		my $values = $parameter->{'values'};
		for my $item (@$values) {
			if(defined($selectedValues->{$item->{'id'}})) {
				$result = $result.'<value>';
				if($parameter->{'quotevalue'}) {
					$result = $result.encode_entities($item->{'value'},"&<>\'\"");
				}else {
					$result = $result.encode_entities($item->{'value'},"&<>\'\"");
				}
				$result = $result.'</value>';
			}
		}
		if(!defined($result)) {
			$result = '';
		}
	}elsif($parameter->{'type'} =~ /.*singlelist$/) {
		my $values = $parameter->{'values'};
		my $selectedValue = $params->{'libraryparameter_'.$parameter->{'id'}};
		for my $item (@$values) {
			if($selectedValue eq $item->{'id'}) {
				$result = '<value>';
				if($parameter->{'quotevalue'}) {
					$result .= encode_entities($item->{'value'},"&<>\'\"");
				}else {
					$result .= encode_entities($item->{'value'},"&<>\'\"");
				}
				$result .= '</value>';
				last;
			}
		}
		if(!defined($result)) {
			$result = '';
		}
	}else{
		if(defined($params->{'libraryparameter_'.$parameter->{'id'}}) && $params->{'libraryparameter_'.$parameter->{'id'}} ne '') {
			if($parameter->{'quotevalue'}) {
				$result = '<value>'.encode_entities($params->{'libraryparameter_'.$parameter->{'id'}},"&<>\'\"").'</value>';
			}else {
				$result = '<value>'.encode_entities($params->{'libraryparameter_'.$parameter->{'id'}},"&<>\'\"").'</value>';
			}
		}else {
			$result = '';
		}
	}
	if(defined($result)) {
		$result = Slim::Utils::Unicode::utf8on($result);
		$result = Slim::Utils::Unicode::utf8encode_locale($result);
	}
	return $result;
}


sub getMultipleListQueryParameter {
	my $params = shift;
	my $parameter = shift;

	my $query = $params->{url_query};
	my %result = ();
	if($query) {
		foreach my $param (split /\&/, $query) {
			if ($param =~ /([^=]+)=(.*)/) {
				my $name  = unescape($1,1);
				my $value = unescape($2,1);
				if($name eq $parameter) {
					# We need to turn perl's internal
					# representation of the unescaped
					# UTF-8 string into a "real" UTF-8
					# string with the appropriate magic set.
					if ($value ne '*' && $value ne '') {
						$value = Slim::Utils::Unicode::utf8on($value);
						$value = Slim::Utils::Unicode::utf8encode_locale($value);
					}
					$result{$value} = 1;
				}
			}
		}
	}
	return \%result;
}

sub getParameterArray {
	my $params = shift;
	my $prefix = shift;

	my $query = $params->{url_query};
	my @result = ();
	if($query) {
		foreach my $param (split /\&/, $query) {
			if ($param =~ /([^=]+)=(.*)/) {
				my $name  = unescape($1,1);
				my $value = unescape($2,1);
				if($name =~ /^$prefix/) {
					# We need to turn perl's internal
					# representation of the unescaped
					# UTF-8 string into a "real" UTF-8
					# string with the appropriate magic set.
					if ($value ne '*' && $value ne '') {
						$value = Slim::Utils::Unicode::utf8on($value);
						$value = Slim::Utils::Unicode::utf8encode_locale($value);
					}
					my %parameter = (
						'id' => $name,
						'value' => $value
					);
					push @result,\%parameter;
				}
			}
		}
	}
	return \@result;
}

sub getCheckBoxesQueryParameter {
	my $params = shift;
	my $parameter = shift;

	my %result = ();
	foreach my $key (keys %$params) {
		my $pattern = '^'.$parameter.'_(.*)';
		if ($key =~ /$pattern/) {
			my $id  = unescape($1);
			$result{$id} = 1;
		}
	}
	return \%result;
}

sub getSQLTemplateData {
	my $sqlstatements = shift;
	my @result =();
	my $ds = getCurrentDS();
	my $dbh = getCurrentDBH();
	my $trackno = 0;
	my $sqlerrors = "";
    	for my $sql (split(/[;]/,$sqlstatements)) {
    	eval {
			$sql =~ s/^\s+//g;
			$sql =~ s/\s+$//g;
			my $sth = $dbh->prepare( $sql );
			debugMsg("Executing: $sql\n");
			$sth->execute() or do {
	            debugMsg("Error executing: $sql\n");
	            $sql = undef;
			};

	        if ($sql =~ /^SELECT+/oi) {
				debugMsg("Executing and collecting: $sql\n");
				my $id;
                                my $name;
                                my $value;
				$sth->bind_col( 1, \$id);
                                $sth->bind_col( 2, \$name);
                                $sth->bind_col( 3, \$value);
				while( $sth->fetch() ) {
                                    my %item = (
                                        'id' => $id,
                                        'name' => Slim::Utils::Unicode::utf8decode($name,'utf8'),
					'value' => Slim::Utils::Unicode::utf8decode($value,'utf8')
                                    );
                                    push @result, \%item;
				}
			}
			$sth->finish();
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		}		
	}
	return \@result;
}

sub readLibrariesFromDir {
    my $client = shift;
    my $defaultLibrary = shift;
    my $browseDir = shift;
    my $localBrowseLibraries = shift;
    debugMsg("Loading library configuration from: $browseDir\n");

    my @dircontents = Slim::Utils::Misc::readDirectory($browseDir,"ml.xml");
    for my $item (@dircontents) {

	next if -d catdir($browseDir, $item);

        my $path = catfile($browseDir, $item);

        # read_file from File::Slurp
        my $content = eval { read_file($path) };
        if ( $content ) {
		my $errorMsg = parseLibraryContent($client,$item,$content,$localBrowseLibraries,$defaultLibrary);
		if($errorMsg) {
	                errorMsg("MultiLibrary: Unable to open library configuration file: $path\n$errorMsg\n");
		}
        }else {
            if ($@) {
                    errorMsg("MultiLibrary: Unable to open library configuration file: $path\nBecause of:\n$@\n");
            }else {
                errorMsg("MultiLibrary: Unable to open library configuration file: $path\n");
            }
        }
    }
}

sub readTemplateLibrariesFromDir {
    my $client = shift;
    my $defaultLibrary = shift;
    my $libraryDir = shift;
    my $localLibraries = shift;
    my $templates = shift;
    debugMsg("Loading template libraries from: $libraryDir\n");

    my @dircontents = Slim::Utils::Misc::readDirectory($libraryDir,"ml.values.xml");
    for my $item (@dircontents) {

	next if -d catdir($libraryDir, $item);

        my $path = catfile($libraryDir, $item);

        # read_file from File::Slurp
        my $content = eval { read_file($path) };
        if ( $content ) {
		my $errorMsg = parseTemplateLibraryContent($client,$item,$content,$localLibraries,$defaultLibrary, $templates);
		if($errorMsg) {
	                errorMsg("MultiLibrary: Unable to open template library: $path\n$errorMsg\n");
		}
        }else {
            if ($@) {
                    errorMsg("MultiLibrary: Unable to open template library: $path\nBecause of:\n$@\n");
            }else {
                errorMsg("MultiLibrary: Unable to open template library: $path\n");
            }
        }
    }
}

sub readTemplateConfiguration {
	my $client = shift;
	my @pluginDirs = ();
	if ($::VERSION ge '6.5') {
		@pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	}else {
		@pluginDirs = catdir($Bin, "Plugins");
	}
	my %templates = ();
	for my $plugindir (@pluginDirs) {
		next unless -d catdir($plugindir,"MultiLibrary","Templates");
		readTemplateConfigurationFromDir($client,0,catdir($plugindir,"MultiLibrary","Templates"),\%templates);
	}

	no strict 'refs';
	my @enabledplugins;
	if ($::VERSION ge '6.5') {
		@enabledplugins = Slim::Utils::PluginManager::enabledPlugins();
	}else {
		@enabledplugins = Slim::Buttons::Plugins::enabledPlugins();
	}

	for my $plugin (@enabledplugins) {
		if(UNIVERSAL::can("Plugins::$plugin","getMultiLibraryTemplates") && UNIVERSAL::can("Plugins::$plugin","getMultiLibraryTemplateData")) {
			debugMsg("Getting library templates for: $plugin\n");
			my $items = eval { &{"Plugins::${plugin}::getMultiLibraryTemplates"}($client) };
			if ($@) {
				debugMsg("Error getting library templates from $plugin: $@\n");
			}
			for my $item (@$items) {
				my $template = $item->{'template'};
				$template->{'multilibrary_plugin_template'}=$item;
				$template->{'multilibrary_plugin'} = "Plugins::${plugin}";
				my $templateId = $item->{'id'};
				if($plugin =~ /^([^:]+)::.*$/) {
					$templateId = lc($1)."_".$item->{'id'};
				}
				$template->{'id'} = $templateId;
				debugMsg("Adding template: $templateId\n");
				#debugMsg(Dumper($template));
				$templates{$templateId} = $template;
			}
		}
	}
	use strict 'refs';

	return \%templates;
}

sub readTemplateConfigurationFromDir {
    my $client = shift;
    my $customlibrary = shift;
    my $templateDir = shift;
    my $templates = shift;
    debugMsg("Loading template configuration from: $templateDir\n");

    my @dircontents = Slim::Utils::Misc::readDirectory($templateDir,"xml");
    for my $item (@dircontents) {

	next if -d catdir($templateDir, $item);

        my $path = catfile($templateDir, $item);

        # read_file from File::Slurp
        my $content = eval { read_file($path) };
	my $error = parseTemplateContent($client,$customlibrary, $item,$content,$templates);
	if($error) {
		errorMsg("Unable to read: $path\n");
	}
    }
}

sub parseTemplateContent {
	my $client = shift;
	my $customlibrary = shift;
	my $key = shift;
	my $content = shift;
	my $templates = shift;

	my $errorMsg = undef;
        if ( $content ) {
	    $content = Slim::Utils::Unicode::utf8decode($content,'utf8');
            my $xml = eval { 	XMLin($content, forcearray => ["parameter"], keyattr => []) };
            #debugMsg(Dumper($xml));
            if ($@) {
		    $errorMsg = "$@";
                    errorMsg("MultiLibrary: Failed to parse library template configuration because:\n$@\n");
            }else {
		my $include = isTemplateEnabled($client,$xml);
		if(defined($xml->{'template'})) {
			$xml->{'template'}->{'id'} = $key;
			if($customlibrary) {
				$xml->{'template'}->{'customlibrary'} = 1;
			}
		}
		if($include && defined($xml->{'template'})) {
	                $templates->{$key} = $xml->{'template'};
		}
            }
    
            # Release content
            undef $content;
        }else {
            if ($@) {
                    $errorMsg = "Incorrect information in template data: $@";
                    errorMsg("MultiLibrary: Unable to read template configuration:\n$@\n");
            }else {
		$errorMsg = "Incorrect information in template data";
                errorMsg("MultiLibrary: Unable to to read template configuration\n");
            }
        }
	return $errorMsg;
}

sub parseTemplateLibraryContent {
	my $client = shift;
	my $item = shift;
	my $content = shift;
	my $libraries = shift;
	my $defaultLibrary = shift;
	my $templates = shift;
	my $dbh = getCurrentDBH();

	my $libraryId = $item;
	$libraryId =~ s/\.ml\.values\.xml$//;
	my $errorMsg = undef;
        if ( $content ) {
		$content = Slim::Utils::Unicode::utf8decode($content,'utf8');
		my $valuesXml = eval { XMLin($content, forcearray => ["parameter","value"], keyattr => []) };
		#debugMsg(Dumper($valuesXml));
		if ($@) {
			$errorMsg = "$@";
			errorMsg("MultiLibrary: Failed to parse library template because:\n$@\n");
		}else {
			my $templateId = $valuesXml->{'template'}->{'id'};
			my $template = $templates->{$templateId};
			$templateId =~s/\.xml$//;
			my $include = undef;
			if($template) {
				$include = 1;
				my %templateParameters = ();
				my $parameters = $valuesXml->{'template'}->{'parameter'};
				for my $p (@$parameters) {
					my $values = $p->{'value'};
					my $value = '';
					for my $v (@$values) {
						if($value ne '') {
							$value .= ',';
						}
						if($p->{'quotevalue'}) {
							$value .= $dbh->quote(encode_entities($v,"&<>\'\""));
						}else {
							$value .= encode_entities($v,"&<>\'\"");
						}
					}
					$templateParameters{$p->{'id'}}=$value;
				}

				my $templateFileData = undef;
				my $doParsing = 1;
				if(defined($template->{'multilibrary_plugin_template'})) {
					my $pluginTemplate = $template->{'multilibrary_plugin_template'};
					if(defined($pluginTemplate->{'type'}) && $pluginTemplate->{'type'} eq 'final') {
						$doParsing = 0;
					}
					$templateFileData = getPluginTemplateData($client,$template,\%templateParameters);
				}else {
					if(defined($template->{'templatefile'})) {
						$templateFileData = $template->{'templatefile'};
					}else {
						$templateFileData = $templateId.".template";
					}
				}
				my $libraryData = undef;
				if($doParsing) {
					$libraryData = fillTemplate($templateFileData,\%templateParameters);
				}else {
					$libraryData = $$templateFileData;
				}
				$libraryData = Slim::Utils::Unicode::utf8on($libraryData);
				$libraryData = Slim::Utils::Unicode::utf8encode_locale($libraryData);
			
				my $xml = eval { XMLin($libraryData, forcearray => ["item"], keyattr => []) };
				#debugMsg(Dumper($xml));
				if ($@) {
					$errorMsg = "$@";
					errorMsg("MultiLibrary: Failed to parse library configuration because:\n$@\n");
				}else {
					my $disabled = 0;
					if(defined($xml->{'library'})) {
						$xml->{'library'}->{'id'} = escape($libraryId);
					}
	
					if(defined($xml->{'library'}) && defined($xml->{'library'}->{'id'})) {
						my $enabled = Slim::Utils::Prefs::get('plugin_multilibrary_library_'.escape($xml->{'library'}->{'id'}).'_enabled');
						if(defined($enabled) && !$enabled) {
							$disabled = 1;
						}elsif(!defined($enabled)) {
							if(defined($xml->{'defaultdisabled'}) && $xml->{'defaultdisabled'}) {
								$disabled = 1;
							}
						}
					}
			
					$xml->{'library'}->{'simple'} = 1;
					if($include && !$disabled) {
						$xml->{'library'}->{'enabled'}=1;
						if($defaultLibrary) {
							$xml->{'library'}->{'defaultlibrary'} = 1;
						}elsif(defined($template->{'customtemplate'})) {
							$xml->{'library'}->{'customlibrary'} = 1;
						}
				                $libraries->{$libraryId} = $xml->{'library'};
					}elsif($include && $disabled) {
						$xml->{'library'}->{'enabled'}=0;
						if($defaultLibrary) {
							$xml->{'library'}->{'defaultlibrary'} = 1;
						}elsif(defined($template->{'customtemplate'})) {
							$xml->{'library'}->{'customlibrary'} = 1;
						}
				                $libraries->{$libraryId} = $xml->{'library'};
					}
				}
			}
		}
		    
		# Release content
		undef $content;
	}else {
		$errorMsg = "Incorrect information in library data";
		errorMsg("MultiLibrary: Unable to to read library data\n");
	}
	return $errorMsg;
}

sub getPluginTemplateData {
	my $client = shift;
	my $template = shift;
	my $parameters = shift;
	debugMsg("Get template data from plugin\n");
	my $plugin = $template->{'multilibrary_plugin'};
	my $pluginTemplate = $template->{'multilibrary_plugin_template'};
	my $templateFileData = undef;
	no strict 'refs';
	if(UNIVERSAL::can("$plugin","getMultiLibraryTemplateData")) {
		debugMsg("Calling: $plugin :: getMultiLibraryTemplateData\n");
		$templateFileData =  eval { &{"${plugin}::getMultiLibraryTemplateData"}($client,$pluginTemplate,$parameters) };
		if ($@) {
			debugMsg("Error retreiving library template data from $plugin: $@\n");
		}
	}
	use strict 'refs';
	return \$templateFileData;
}

sub loadTemplateValues {
	my $file = shift;
	my $templateData = undef;
	my $browseDir = Slim::Utils::Prefs::get("plugin_multilibrary_library_directory");
	if (!defined $browseDir || !-d $browseDir) {
		debugMsg("Skipping library configuration - directory is undefined\n");
	}else {
		$templateData = loadTemplateData($browseDir,$file);
	}
	return $templateData;
}

sub loadTemplateData {
	my $browseDir = shift;
	my $file = shift;
	
	my $path = catfile($browseDir, $file);
	if( -f $path ) {
		my $content = eval { read_file($path) };
	        if ( $content ) {
			$content = Slim::Utils::Unicode::utf8decode($content,'utf8');
			my $xml = eval { XMLin($content, forcearray => ["parameter","value"], keyattr => []) };
			#debugMsg(Dumper($valuesXml));
			if ($@) {
				errorMsg("MultiLibrary: Failed to parse template data because:\n$@\n");
			}else {
				return $xml->{'template'}
			}
		}else {
			debugMsg("Failed to load template data because:\n$@\n");
		}
		if ($@) {
			debugMsg("Failed to load template data because:\n$@\n");
		}
	}
	return undef;
}


sub isTemplateEnabled {
	my $client = shift;
	my $xml = shift;

	my $include = 1;
	if(defined($xml->{'minslimserverversion'})) {
		if($::VERSION lt $xml->{'minslimserverversion'}) {
			$include = 0;
		}
	}
	if(defined($xml->{'maxslimserverversion'})) {
		if($::VERSION gt $xml->{'maxslimserverversion'}) {
			$include = 0;
		}
	}
	if(defined($xml->{'requireplugins'}) && $include) {
		$include = 0;
		my $requiredPlugins = $xml->{'requireplugins'};
		my $enabledPlugin = 1;
		foreach my $plugin (split /,/, $requiredPlugins) {
			if($enabledPlugin) {
				if ($::VERSION ge '6.5') {
					$enabledPlugin = Slim::Utils::PluginManager::enabledPlugin($plugin,$client);
				}else {
					$enabledPlugin = grep(/$plugin/,Slim::Buttons::Plugins::enabledPlugins($client));
				}
			}
		}
		if($enabledPlugin) {
			$include = 1;
		}
	}
	if(defined($xml->{'database'}) && $include) {
		$include = 0;
		my $driver = Slim::Utils::Prefs::get('dbsource');
		$driver =~ s/dbi:(.*?):(.*)$/$1/;
		if($driver eq $xml->{'database'}) {
			$include = 1;
		}
	}
	return $include;
}


# Draws the plugin's edit library web page
sub handleWebSaveLibrary {
	my ($client, $params) = @_;

	$params->{'pluginMultiLibraryError'} = undef;
	if(defined($params->{'redirect'})) {
		$params->{'pluginMultiLibraryRedirect'} = 1;
	}

	if (!$params->{'text'} || !$params->{'file'}) {
		$params->{'pluginMultiLibraryError'} = 'All fields are mandatory';
	}

	my $libraryDir = Slim::Utils::Prefs::get("plugin_multilibrary_library_directory");
	
	if (!defined $libraryDir || !-d $libraryDir) {
		$params->{'pluginMultiLibraryError'} = 'No library dir defined';
	}
	my $url = catfile($libraryDir, unescape($params->{'file'}));
	if (!-e $url && !defined($params->{'deletesimple'})) {
		$params->{'pluginMultiLibraryError'} = 'File doesnt exist';
	}
	
	my $library = getLibrary($client,escape($params->{'name'},"^A-Za-z0-9\-_"));
	if($library && $library->{'file'} ne unescape($params->{'file'}) && !defined($library->{'defaultlibrary'}) && !defined($library->{'simple'})) {
		$params->{'pluginMultiLibraryError'} = 'Library with that name already exists';
	}
	if(!saveLibrary($client,$params,$url)) {
		if(defined($params->{'deletesimple'})) {
			$params->{'pluginMultiLibraryEditLibraryDeleteSimple'} = $params->{'deletesimple'};
		}
		return Slim::Web::HTTP::filltemplatefile('plugins/MultiLibrary/multilibrary_editlibrary.html', $params);
	}else {
		if(defined($params->{'deletesimple'})) {
			my $file = unescape($params->{'deletesimple'});
			my $url = catfile($libraryDir, $file);
			if(-e $url) {
				unlink($url) or do {
					warn "Unable to delete file: ".$url.": $! \n";
				}
			}
		}
		$params->{'donotrefresh'} = 1;
		initLibraries($client);
		if(Slim::Utils::Prefs::get("plugin_multilibrary_refresh_save")) {
			refreshLibraries();
		}
		return handleWebList($client,$params)
	}

}

# Draws the plugin's edit library web page
sub handleWebSaveNewLibrary {
	my ($client, $params) = @_;

	if(defined($params->{'redirect'})) {
		$params->{'pluginMultiLibraryRedirect'} = 1;
	}

	$params->{'pluginMultiLibraryError'} = undef;
	
	if (!$params->{'text'} || !$params->{'file'}) {
		$params->{'pluginMultiLibraryError'} = 'All fields are mandatory';
	}

	my $libraryDir = Slim::Utils::Prefs::get("plugin_multilibrary_library_directory");
	
	if (!defined $libraryDir || !-d $libraryDir) {
		$params->{'pluginMultiLibraryError'} = 'No library dir defined';
	}
	debugMsg("Got file: ".$params->{'file'}."\n");
	if($params->{'file'} !~ /.*\.ml\.xml$/) {
		$params->{'pluginMultiLibraryError'} = 'File name must end with .ml.xml';
	}
	
	if($params->{'file'} !~ /^[0-9A-Za-z\._\- ]*$/) {
		$params->{'pluginMultiLibraryError'} = 'File name is only allowed to contain characters a-z , A-Z , 0-9 , - , _ , . , and space';
	}

	my $url = catfile($libraryDir, unescape($params->{'file'}));
	if (-e $url) {
		$params->{'pluginMultiLibraryError'} = 'File already exist';
	}

	if(!saveLibrary($client,$params,$url)) {
		return Slim::Web::HTTP::filltemplatefile('plugins/MultiLibrary/multilibrary_newlibrary.html', $params);
	}else {
		$params->{'donotrefresh'} = 1;
		initLibraries($client);
		if(Slim::Utils::Prefs::get("plugin_multilibrary_refresh_save")) {
			refreshLibraries();
		}
		return handleWebList($client,$params)
	}

}

sub handleWebRemoveLibrary {
	my ($client, $params) = @_;

	if(defined($params->{'redirect'})) {
		$params->{'pluginMultiLibraryRedirect'} = 1;
	}

	if ($params->{'type'}) {
		my $library = getLibrary($client,$params->{'type'});
		if($library) {
			my $libraryDir = Slim::Utils::Prefs::get("plugin_multilibrary_library_directory");
			
			if (!defined $libraryDir || !-d $libraryDir) {
				warn "No library dir defined\n"
			}else {
				my $file = $params->{'type'};
				if(defined($library->{'simple'})) {
					$file .= ".ml.values.xml";
				}else {
					$file .= ".ml.xml";
				}
				debugMsg("Deleteing library: ".$file."\n");
				my $url = catfile($libraryDir, unescape($file));
				unlink($url) or do {
					warn "Unable to delete file: ".$url.": $! \n";
				}
			}
		}else {
			warn "Cannot find: ".$params->{'type'}."\n";
		}
	}

	return handleWebList($client,$params)
}

sub saveSimpleLibrary {
	my ($client, $params, $url) = @_;
	my $fh;

	if(!($url =~ /.*\.ml\.values\.xml$/)) {
		$params->{'pluginMultiLibraryError'} = 'Filename must end with .ml.values.xml';
	}

	if(!($params->{'pluginMultiLibraryError'})) {
		debugMsg("Opening library file: $url\n");
		open($fh,"> $url") or do {
	            $params->{'pluginMultiLibraryError'} = 'Error saving library';
		};
	}
	if(!($params->{'pluginMultiLibraryError'})) {
		my $templates = readTemplateConfiguration($client);
		my $template = $templates->{$params->{'librarytemplate'}};
		my %templateParameters = ();
		my $data = "";
		$data .= "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<multilibrary>\n\t<template>\n\t\t<id>".$params->{'librarytemplate'}."</id>";
		if(defined($template->{'parameter'})) {
			my $parameters = $template->{'parameter'};
			my @parametersToSelect = ();
			for my $p (@$parameters) {
				if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
					addValuesToTemplateParameter($p);
					my $value = getXMLValueOfTemplateParameter($params,$p);
					if($p->{'quotevalue'}) {
						$data .= "\n\t\t<parameter type=\"text\" id=\"".$p->{'id'}."\" quotevalue=\"1\">";
					}else {
						$data .= "\n\t\t<parameter type=\"text\" id=\"".$p->{'id'}."\">";
					}
					$data .= $value.'</parameter>';
				}
			}
		}
		$data .= "\n\t</template>\n</multilibrary>\n";
		debugMsg("Writing to file: $url\n");
		print $fh $data;
		debugMsg("Writing to file succeeded\n");
		close $fh;
	}
	
	if($params->{'pluginMultiLibraryError'}) {
		my %parameters;
		for my $p (keys %$params) {
			if($p =~ /^libraryparameter_/) {
				$parameters{$p}=$params->{$p};
			}
		}		
		$params->{'pluginMultiLibraryEditLibraryParameters'} = \%parameters;
		$params->{'pluginMultiLibraryEditLibraryFile'} = $params->{'file'};
		$params->{'pluginMultiLibraryEditLibraryFileUnescaped'} = unescape($params->{'pluginMultiLibraryEditLibraryFile'});
		if ($::VERSION ge '6.5') {
			$params->{'pluginMultiLibrarySlimserver65'} = 1;
		}
		return undef;
	}else {
		return 1;
	}
}

sub saveLibrary
{
	my ($client, $params, $url) = @_;
	my $fh;

	if(!($url =~ /.*\.ml\.xml$/)) {
		$params->{'pluginMultiLibraryError'} = 'Filename must end with .ml.xml';
	}
	if(!($params->{'pluginMultiLibraryError'})) {
		my %templates = ();
		my $error = parseLibraryContent($client,'test',$params->{'text'},\%templates);
		if($error) {
			$params->{'pluginMultiLibraryError'} = "Reading library configuration: <br>".$error;
		}
	}

	if(!($params->{'pluginMultiLibraryError'})) {
		debugMsg("Opening library configuration file: $url\n");
		open($fh,"> $url") or do {
	            $params->{'pluginMultiLibraryError'} = 'Error saving library';
		};
	}
	if(!($params->{'pluginMultiLibraryError'})) {

		debugMsg("Writing to file: $url\n");
		print $fh $params->{'text'};
		debugMsg("Writing to file succeeded\n");
		close $fh;
	}
	
	if($params->{'pluginMultiLibraryError'}) {
		$params->{'pluginMultiLibraryEditLibraryFile'} = $params->{'file'};
		$params->{'pluginMultiLibraryEditLibraryData'} = $params->{'text'};
		$params->{'pluginMultiLibraryEditLibraryFileUnescaped'} = unescape($params->{'pluginMultiLibraryEditLibraryFile'});
		if ($::VERSION ge '6.5') {
			$params->{'pluginMultiLibrarySlimserver65'} = 1;
		}
		return undef;
	}else {
		return 1;
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
	my $prefVal = Slim::Utils::Prefs::get('plugin_multilibrary_library_directory');
	if (! defined $prefVal) {
		# Default to standard library directory
		my $dir=Slim::Utils::Prefs::get('playlistdir');
		debugMsg("Defaulting plugin_multilibrary_library_directory to:$dir\n");
		Slim::Utils::Prefs::set('plugin_multilibrary_library_directory', $dir);
	}

	$prefVal = Slim::Utils::Prefs::get('plugin_multilibrary_showmessages');
	if (! defined $prefVal) {
		# Default to not show debug messages
		debugMsg("Defaulting plugin_multilibrary_showmessages to 0\n");
		Slim::Utils::Prefs::set('plugin_multilibrary_showmessages', 0);
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_multilibrary_refresh_startup');
	if (! defined $prefVal) {
		Slim::Utils::Prefs::set('plugin_multilibrary_refresh_startup', 1);
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_multilibrary_refresh_rescan');
	if (! defined $prefVal) {
		Slim::Utils::Prefs::set('plugin_multilibrary_refresh_rescan', 1);
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_multilibrary_refresh_save');
	if (! defined $prefVal) {
		Slim::Utils::Prefs::set('plugin_multilibrary_refresh_save', 1);
	}
}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_multilibrary_library_directory','plugin_multilibrary_refresh_save','plugin_multilibrary_refresh_rescan','plugin_multilibrary_refresh_startup','plugin_multilibrary_showmessages'],
	 GroupHead => string('PLUGIN_MULTILIBRARY_SETUP_GROUP'),
	 GroupDesc => string('PLUGIN_MULTILIBRARY_SETUP_GROUP_DESC'),
	 GroupLine => 1,
	 GroupSub  => 1,
	 Suppress_PrefSub  => 1,
	 Suppress_PrefLine => 1
	);
	my %setupPrefs =
	(
	plugin_multilibrary_showmessages => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_MULTILIBRARY_SHOW_MESSAGES')
			,'changeIntro' => string('PLUGIN_MULTILIBRARY_SHOW_MESSAGES')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_multilibrary_showmessages"); }
		},		
	plugin_multilibrary_refresh_rescan => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_MULTILIBRARY_REFRESH_RESCAN')
			,'changeIntro' => string('PLUGIN_MULTILIBRARY_REFRESH_RESCAN')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_multilibrary_refresh_rescan"); }
		},		
	plugin_multilibrary_refresh_startup => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_MULTILIBRARY_REFRESH_STARTUP')
			,'changeIntro' => string('PLUGIN_MULTILIBRARY_REFRESH_STARTUP')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_multilibrary_refresh_startup"); }
		},		
	plugin_multilibrary_refresh_save => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_MULTILIBRARY_REFRESH_SAVE')
			,'changeIntro' => string('PLUGIN_MULTILIBRARY_REFRESH_SAVE')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_multilibrary_refresh_save"); }
		},		
	plugin_multilibrary_library_directory => {
			'validate' => \&validateIsDirWrapper
			,'PrefChoose' => string('PLUGIN_MULTILIBRARY_LIBRARY_DIRECTORY')
			,'changeIntro' => string('PLUGIN_MULTILIBRARY_LIBRARY_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_multilibrary_library_directory"); }
		},
	);
	return (\%setupGroup,\%setupPrefs);
}
sub replaceParametersInSQL {
	my $sql = shift;
	my $parameters = shift;
	my $parameterType = shift;
	if(!defined($parameterType)) {
		$parameterType='LibraryParameter';
	}
	
	if(defined($parameters)) {
		foreach my $key (keys %$parameters) {
			my $parameter = $parameters->{$key};
			my $value = $parameter->{'value'};
			if(!defined($value)) {
				$value='';
			}
			my $parameterid = "\'$parameterType".$parameter->{'id'}."\'";
			debugMsg("Replacing ".$parameterid." with ".$value."\n");
			$sql =~ s/$parameterid/$value/g;
		}
	}
	return $sql;
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

sub getLibraryOption {
	my $library = shift;
	my $option = shift;

	if(defined($library->{'options'})){
		if(defined($library->{'options'}->{$option})) {
			return $library->{'options'}->{$option}->{'value'};
		}
	}
	return undef;
}
sub parseParameter {
	my $line = shift;
	
	if($line =~ /^\s*--\s*LibraryParameter\s*\d\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*LibraryParameter\s*(\d)\s*[:=]\s*([^:]+):\s*([^:]*):\s*(.*)$/;
		my $parameterId = $1;
		my $parameterType = $2;
		my $parameterName = $3;
		my $parameterDefinition = $4;

		$parameterType =~ s/^\s+//;
		$parameterType =~ s/\s+$//;

		$parameterName =~ s/^\s+//;
		$parameterName =~ s/\s+$//;

		$parameterDefinition =~ s/^\s+//;
		$parameterDefinition =~ s/\s+$//;

		if($parameterId && $parameterName && $parameterType) {
			my %parameter = (
				'id' => $parameterId,
				'type' => $parameterType,
				'name' => $parameterName,
				'definition' => $parameterDefinition
			);
			return \%parameter;
		}else {
			debugMsg("Error in parameter: $line\n");
			debugMsg("Parameter values: Id=$parameterId, Type=$parameterType, Name=$parameterName, Definition=$parameterDefinition\n");
			return undef;
		}
	}
	return undef;
}	

sub parseOption {
	my $line = shift;
	if($line =~ /^\s*--\s*LibraryOption\s*[^:=]+\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*LibraryOption\s*([^:=]+)\s*[:=]\s*(.+)\s*$/;
		my $optionId = $1;
		my $optionValue = $2;

		$optionId =~ s/\s+$//;

		$optionValue =~ s/^\s+//;
		$optionValue =~ s/\s+$//;

		if($optionId && $optionValue) {
			my %option = (
				'id' => $optionId,
				'value' => $optionValue
			);
			return \%option;
		}else {
			debugMsg("Error in option: $line\n");
			debugMsg("Option values: Id=$optionId, Value=$optionValue\n");
			return undef;
		}
	}
	return undef;
}	

sub createMultiLibrary {
	my $sqlstatements = shift;
	my $sql = '';
	my %parameters = ();
	my %options = ();
	for my $line (split(/[\n\r]/,$sqlstatements)) {
		chomp $line;

		my $parameter = parseParameter($line);
		if(defined($parameter)) {
			$parameters{$parameter->{'id'}} = $parameter;
		}
		my $option = parseOption($line);
		if(defined($option)) {
			$options{$option->{'id'}} = $option;
		}
		
		# skip and strip comments & empty lines
		$line =~ s/\s*--.*?$//o;
		$line =~ s/^\s*//o;

		next if $line =~ /^--/;
		next if $line =~ /^\s*$/;

		$line =~ s/\s+$//;
		if($sql) {
			if( $sql =~ /;$/ ) {
				$sql .= "\n";
			}else {
				$sql .= " ";
			}
		}
		$sql .= $line;
	}
	if($sql) {
		my %library = (
			'sql' => $sql
		);
		if(defined(%parameters)) {
			$library{'parameters'} = \%parameters;
		}
		if(defined(%options)) {
			$library{'options'} = \%options;
		}
	    	
		return \%library;
	}else {
		return undef;
	}
}
sub executeSQLForLibrary {
	my $sqlstatements = shift;
	my $limit = shift;
	my $library = shift;
	my @result;
	my $ds = getCurrentDS();
	my $dbh = getCurrentDBH();
	my $trackno = 0;
	$sqlerrors = "";
	my $contentType = getLibraryOption($library,'ContentType');
	my $limit = getLibraryOption($library,'NoOfTracks');
	my $noRepeat = getLibraryOption($library,'DontRepeatTracks');
	if(defined($contentType)) {
		debugMsg("Executing SQL for content type: $contentType\n");
	}
	for my $sql (split(/[\n\r]/,$sqlstatements)) {
    		eval {
			my $sth = $dbh->prepare( $sql );
			debugMsg("Executing: $sql\n");
			$sth->execute() or do {
				debugMsg("Error executing: $sql\n");
				$sql = undef;
			};

		        if ($sql =~ /^\(*SELECT+/oi) {
				debugMsg("Executing and collecting: $sql\n");
				my $url;
				$sth->bind_col( 1, \$url);
				while( $sth->fetch() ) {
					my $tracks = getTracksForResult($url,$contentType,$limit,$noRepeat);
				 	for my $track (@$tracks) {
						$trackno++;
						if(!$limit || $trackno<=$limit) {
							debugMsg("Adding: ".($track->url)."\n");
							push @result, $track;
						}
					}
				}
			}
			$sth->finish();
		};
		if( $@ ) {
			$sqlerrors .= $DBI::errstr."<br>$@<br>";
			warn "Database error: $DBI::errstr\n$@\n";
		}		
	}
	return \@result;
}

sub getTracksForResult {
	my $item = shift;
	my $contentType = shift;
	my $limit = shift;
	my $noRepeat = shift;
	my @result  = ();
	if(!defined($contentType) || $contentType eq 'track' || $contentType eq '') {
		my @resultTracks = ();
		my $track = objectForUrl($item);
		push @result,$track;
	}
	return \@result;
}

sub validateIsDirWrapper {
	my $arg = shift;
	if ($::VERSION ge '6.5') {
		return Slim::Utils::Validate::isDir($arg);
	}else {
		return Slim::Web::Setup::validateIsDir($arg);
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

sub objectForUrl {
	my $url = shift;
	if ($::VERSION ge '6.5') {
		return Slim::Schema->objectForUrl({
			'url' => $url
		});
	}else {
		return getCurrentDS()->objectForUrl($url,undef,undef,1);
	}
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

sub displayAsHTML {
	my $type = shift;
	my $form = shift;
	my $item = shift;
	
	if ($::VERSION ge '6.5') {
		$item->displayAsHTML($form);
	}else {
		my $ds = getCurrentDS();
		my $fieldInfo = Slim::DataStores::Base->fieldInfo;
        my $levelInfo = $fieldInfo->{$type};
        &{$levelInfo->{'listItem'}}($ds, $form, $item);
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

# A wrapper to allow us to uniformly turn on & off debug messages
sub debugMsg
{
	my $message = join '','MultiLibrary: ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_multilibrary_showmessages"));
}

sub strings {
	return <<EOF;
PLUGIN_MULTILIBRARY
	EN	Multi Library

PLUGIN_MULTILIBRARY_SETUP_GROUP
	EN	Multi Library

PLUGIN_MULTILIBRARY_SETUP_GROUP_DESC
	EN	Multi Library is a sub library plugin based on SQL queries

PLUGIN_MULTILIBRARY_LIBRARY_DIRECTORY
	EN	Library directory

PLUGIN_MULTILIBRARY_SHOW_MESSAGES
	EN	Show debug messages

SETUP_PLUGIN_MULTILIBRARY_LIBRARY_DIRECTORY
	EN	Library directory

SETUP_PLUGIN_MULTILIBRARY_SHOWMESSAGES
	EN	Debugging

PLUGIN_MULTILIBRARY_CHOOSE_BELOW
	EN	Choose a sub library of music to activate:

PLUGIN_MULTILIBRARY_EDIT_LIBRARY
	EN	Edit

PLUGIN_MULTILIBRARY_NEW_LIBRARY
	EN	Create new library

PLUGIN_MULTILIBRARY_NEW_LIBRARY_TYPES_TITLE
	EN	Select type of library

PLUGIN_MULTILIBRARY_EDIT_LIBRARY_DATA
	EN	Library Configuration

PLUGIN_MULTILIBRARY_EDIT_LIBRARY_NAME
	EN	Library Name

PLUGIN_MULTILIBRARY_EDIT_LIBRARY_FILENAME
	EN	Filename

PLUGIN_MULTILIBRARY_REMOVE_LIBRARY
	EN	Delete

PLUGIN_MULTILIBRARY_REMOVE_LIBRARY_QUESTION
	EN	Are you sure you want to delete this library ?

PLUGIN_MULTILIBRARY_TEMPLATE_GENRES_TITLE
	EN	Genres

PLUGIN_MULTILIBRARY_TEMPLATE_GENRES_SELECT_NONE
	EN	No Genres

PLUGIN_MULTILIBRARY_TEMPLATE_GENRES_SELECT_ALL
	EN	All Genres

PLUGIN_MULTILIBRARY_TEMPLATE_ARTISTS_SELECT_NONE
	EN	No Artists

PLUGIN_MULTILIBRARY_TEMPLATE_ARTISTS_SELECT_ALL
	EN	All Artists

PLUGIN_MULTILIBRARY_TEMPLATE_ARTISTS_TITLE
	EN	Artists

PLUGIN_MULTILIBRARY_SAVE
	EN	Save

PLUGIN_MULTILIBRARY_NEXT
	EN	Next

PLUGIN_MULTILIBRARY_TEMPLATE_PARAMETER_LIBRARIES
	EN	Libraries with user selectable parameters

PLUGIN_MULTILIBRARY_LIBRARYTYPE
	EN	Customize SQL
	
PLUGIN_MULTILIBRARY_LIBRARYTYPE_SIMPLE
	EN	Use predefined

PLUGIN_MULTILIBRARY_LIBRARYTYPE_ADVANCED
	EN	Customize SQL

PLUGIN_MULTILIBRARY_NEW_LIBRARY_PARAMETERS_TITLE
	EN	Please enter library parameters

PLUGIN_MULTILIBRARY_EDIT_LIBRARY_PARAMETERS_TITLE
	EN	Please enter library parameters

PLUGIN_MULTILIBRARY_LASTCHANGED
	EN	Last changed

PLUGIN_MULTILIBRARY_EDIT_LIBRARY_OVERWRITE
	EN	Overwrite existing

PLUGIN_MULTILIBRARY_ACTIVE_LIBRARY
	EN	Active library

PLUGIN_MULTILIBRARY_REFRESH_LIBRARIES
	EN	Refresh libraries

PLUGIN_MULTILIBRARY_ACTIVATING_LIBRARY
	EN	Activating

PLUGIN_MULTILIBRARY_REFRESH_RESCAN
	EN	Refresh libraries after rescan

SETUP_PLUGIN_MULTILIBRARY_REFRESH_RESCAN
	EN	Rescan refresh

PLUGIN_MULTILIBRARY_REFRESH_STARTUP
	EN	Refresh libraries at slimserver startup

SETUP_PLUGIN_MULTILIBRARY_REFRESH_STARTUP
	EN	Startup refresh

PLUGIN_MULTILIBRARY_REFRESH_SAVE
	EN	Refresh libraries after library has been save

SETUP_PLUGIN_MULTILIBRARY_REFRESH_SAVE
	EN	Refresh on save

EOF

}

1;

__END__
