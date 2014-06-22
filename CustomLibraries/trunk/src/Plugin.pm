# 				CustomLibraries plugin 
#
#    Copyright (c) 2007-2014 Erland Isaksson (erland_i@hotmail.com)
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

package Plugins::CustomLibraries::Plugin;

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;
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

use Plugins::CustomLibraries::ConfigManager::Main;
use Plugins::CustomLibraries::Template::Reader;

use Plugins::CustomLibraries::Settings;

use Slim::Schema;

my $prefs = preferences('plugin.customlibraries');
my $serverPrefs = preferences('server');
my $maiPrefs = undef;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.customlibraries',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_CUSTOMLIBRARIES',
});
my $driver;

$prefs->migrate(1, sub {
	$prefs->set('utf8filenames', Slim::Utils::Prefs::OldPrefs->get('plugin_customlibraries_utf8filenames'));
	mkdir(catdir(Slim::Utils::OSDetect::dirsFor('prefs'), 'customlibraries'));
	1;
});

# Information on each clients customlibraries
my $htmlTemplate = 'plugins/CustomLibraries/customlibraries_list.html';
my $libraries = undef;
my $sqlerrors = '';
my $PLUGINVERSION = undef;
my $internalMenus = undef;
my $customBrowseMenus = undef;
my $configManager = undef;

# Indicator if hooked or not
# 0= No
# 1= Yes
my $CUSTOMLIBRARIES_HOOK = 0;

sub getDisplayName {
	return 'PLUGIN_CUSTOMLIBRARIES';
}

sub getLibrary {
	my $client = shift;
	my $type = shift;
	
	return undef unless $type;

	$log->debug("Get library: $type\n");
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
	}
	return $name;
}


# Returns the overlay to be display next to items in the menu
sub getOverlay {
	my ($client, $item) = @_;
	my $itemId = $item->{'id'};
	return [undef, $client->symbols('rightarrow')];
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
	}elsif(defined($library->{'excludedclients'} && ref($library->{'excludedclients'}) ne 'HASH')) {
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


sub initLibraries {
	my $client = shift;

	my $itemConfiguration = getConfigManager()->readItemConfiguration($client,1);

	my $localLibraries = $itemConfiguration->{'libraries'};

	for my $libraryid (keys %$localLibraries) {
		my $localLibrary = $localLibraries->{$libraryid};
		my $sql = $localLibrary->{'track'}->{'data'};
		$sql =~ s/\{library\}/\'\%s\'/g;
		my $library = {
			id => 'customlibraries_'.$libraryid,
			name => $localLibrary->{'name'},
			sql => 'INSERT OR IGNORE INTO library_track (library, track) '.$sql
		};
		$log->debug("Registering library using: ".Dumper($library));
		my $id = Slim::Music::VirtualLibraries->getRealId('customlibraries_'.$libraryid);
		if(defined($id)) {
			$log->debug("Found existing with id: ".$id);
			my $existingLibraries = Slim::Music::VirtualLibraries->getLibraries();
			delete $existingLibraries->{$id};
		}
		Slim::Music::VirtualLibraries->registerLibrary($library);
		
		Slim::Menu::BrowseLibrary->deregisterNode('customlibraries_'.$libraryid);
		if($localLibrary->{'enabledbrowse'}) {
			Slim::Utils::Strings::storeExtraStrings([{
                        strings => { EN => $localLibrary->{'name'}},
                        token   => uc('plugin_customlibraries_menuname_'.$libraryid),
                }]);
			Slim::Menu::BrowseLibrary->registerNode({
                        type         => 'link',
                        name         => uc('plugin_customlibraries_menuname_'.$libraryid),
                        params       => { library_id => Slim::Music::VirtualLibraries->getRealId('customlibraries_'.$libraryid) },
                        feed         => sub {
                        	my ($client, $cb, $args, $pt) = @_;
                        	my @items = ();
                        	if(Slim::Menu::BrowseLibrary::isEnabledNode($client,'myMusicArtists') && $serverPrefs->get('useUnifiedArtistsList')) {
	                        	push @items,{
	                        		type => 'link',
	                        		name => string('BROWSE_BY_ARTIST'),
	                        		url => sub {
		                                my ($client, $callback, $args, $pt) = @_;
	                                	Slim::Menu::BrowseLibrary::_artists($client,
	                                		sub {
			                                        my $items = shift;
			                                        $log->debug("Browsing artists");
			        								if(defined($maiPrefs) && $maiPrefs->get('browseArtistPictures')) {
				                                        $items->{items} = [ map { 
				                                                $_->{image} ||= 'imageproxy/mai/artist/' . ($_->{id} || 0) . '/image.png';
				                                                $_;
				                                        } @{$items->{items}} ];
			        								}
			        
			                                        $callback->($items);
			                                }, $args, $pt);
	                        			},
	                        		jiveIcon => 'html/images/artists.png',
	                        		icon => 'html/images/artists.png',
	                        		passthrough => [{ 
	                        			library_id => $pt->{'library_id'},
	                        			searchTags => [
	                        				'library_id:'.$pt->{'library_id'}
	                        			],
	                        				
	                        		}],
	                        	};
                        	}
                        	if(Slim::Menu::BrowseLibrary::isEnabledNode($client,'myMusicArtistsAlbumArtists') && !$serverPrefs->get('useUnifiedArtistsList')) {
	                        	push @items,{
	                        		type => 'link',
	                        		name => string('BROWSE_BY_ALBUMARTIST'),
	                        		url => sub {
		                                my ($client, $callback, $args, $pt) = @_;
	                                	Slim::Menu::BrowseLibrary::_artists($client,
	                                		sub {
			                                        my $items = shift;
			                                        $log->debug("Browsing album artists");
			        								if(defined($maiPrefs) && $maiPrefs->get('browseArtistPictures')) {
				                                        $items->{items} = [ map { 
				                                                $_->{image} ||= 'imageproxy/mai/artist/' . ($_->{id} || 0) . '/image.png';
				                                                $_;
				                                        } @{$items->{items}} ];
			        								}
			        
			                                        $callback->($items);
			                                }, $args, $pt);
	                        			},
	                        		jiveIcon => 'html/images/artists.png',
	                        		icon => 'html/images/artists.png',
	                        		passthrough => [{ 
	                        			library_id => $pt->{'library_id'},
	                        			searchTags => [
	                        				'library_id:'.$pt->{'library_id'},
	                        				'role_id:ALBUMARTIST'
	                        			],
	                        				
	                        		}],
	                        	};
                        	}
                        	if(Slim::Menu::BrowseLibrary::isEnabledNode($client,'myMusicArtistsAllArtists') && !$serverPrefs->get('useUnifiedArtistsList')) {
	                        	push @items,{
	                        		type => 'link',
	                        		name => string('BROWSE_BY_ALL_ARTISTS'),
	                        		url => sub {
		                                my ($client, $callback, $args, $pt) = @_;
	                                	Slim::Menu::BrowseLibrary::_artists($client,
	                                		sub {
			                                        my $items = shift;
			                                        $log->debug("Browsing all artists");
			        								if(defined($maiPrefs) && $maiPrefs->get('browseArtistPictures')) {
				                                        $items->{items} = [ map { 
				                                                $_->{image} ||= 'imageproxy/mai/artist/' . ($_->{id} || 0) . '/image.png';
				                                                $_;
				                                        } @{$items->{items}} ];
			        								}
			        
			                                        $callback->($items);
			                                }, $args, $pt);
	                        			},
	                        		jiveIcon => 'html/images/artists.png',
	                        		icon => 'html/images/artists.png',
	                        		passthrough => [{ 
	                        			library_id => $pt->{'library_id'},
	                        			searchTags => [
	                        				'library_id:'.$pt->{'library_id'},
	                        				'role_id:'.join ',', Slim::Schema::Contributor->contributorRoles()
	                        			],
	                        				
	                        		}],
	                        	};
                        	}
                        	push @items,{
                        		type => 'link',
                        		name => string('BROWSE_BY_ALBUM'),
                        		url => \&Slim::Menu::BrowseLibrary::_albums,
                        		icon => 'html/images/albums.png',
                        		passthrough => [{ 
                        			library_id => $pt->{'library_id'},
                        			searchTags => [
                        				'library_id:'.$pt->{'library_id'}
                        			],
                        				
                        		}],
                        	};
                        	push @items,{
                        		type => 'link',
                        		name => string('BROWSE_BY_GENRE'),
                        		url => \&Slim::Menu::BrowseLibrary::_genres,
                        		icon => 'html/images/genres.png',
                        		passthrough => [{ 
                        			library_id => $pt->{'library_id'},
                        			searchTags => [
                        				'library_id:'.$pt->{'library_id'}
                        			],
                        				
                        		}],
                        	};
                        	push @items,{
                        		type => 'link',
                        		name => string('BROWSE_BY_YEAR'),
                        		url => \&Slim::Menu::BrowseLibrary::_years,
                        		icon => 'html/images/years.png',
                        		passthrough => [{ 
                        			library_id => $pt->{'library_id'},
                        			searchTags => [
                        				'library_id:'.$pt->{'library_id'}
                        			],
                        				
                        		}],
                        	};
                        	push @items,{
                        		type => 'link',
                        		name => string('PLAYLISTS'),
                        		url => \&Slim::Menu::BrowseLibrary::_playlists,
                        		icon => 'html/images/playlists.png',
                        		passthrough => [{ 
                        			library_id => $pt->{'library_id'},
                        			searchTags => [
                        				'library_id:'.$pt->{'library_id'}
                        			],
                        				
                        		}],
                        	};
                        	
							$cb->({
								items => \@items,
							});
                        },
                        icon => 'html/images/musicfolder.png',
                        jiveIcon => 'html/images/musicfolder.png',
                        condition    => sub {
                        	my ($client, $nodeId) = @_;
                        	
                        	my $libraryId = $nodeId;
                        	$libraryId =~ s/^customlibraries_//;
                        	if(defined($client) && defined($libraries->{$libraryId}) && defined($libraries->{$libraryId}->{'includedclients'}) && $libraries->{$libraryId}->{'includedclients'} ne "") {
                        		my @clients = split(',',$libraries->{$libraryId}->{'includedclients'});
                        		foreach my $c (@clients) {
                        			if($client->name eq $c) {
                        				$log->debug("Included on player: $c");
                        				return 1;
                        			}
                        		}
                        		return undef;
                        	}
                        	if(defined($client) && defined($libraries->{$libraryId}) && defined($libraries->{$libraryId}->{'excludedclients'}) && $libraries->{$libraryId}->{'excludedclients'} ne "") {
                        		my @clients = split(',',$libraries->{$libraryId}->{'excludedclients'});
                        		foreach my $c (@clients) {
                        			if($client->name eq $c) {
                        				$log->debug("Excluded from player: $c");
                        				return undef;
                        			}
                        		}
                        	}
                        	
                        	return Slim::Menu::BrowseLibrary::isEnabledNode($client,$nodeId);
                        },
                        id           => 'customlibraries_'.$libraryid,
                        weight       => 60,
                        cache        => 1,
                });
		}
	}

	$libraries = $localLibraries;
	
	

}

sub getLibraryTrackCount {
	my $libraryId = shift;

	my $dbh = getCurrentDBH();
	my $sth = $dbh->prepare("select count(*) from library_track where library=?");
	$log->debug("Count for library: ".Slim::Music::VirtualLibraries->getNameForId($libraryId));
	$sth->bind_param(1,$libraryId,SQL_VARCHAR);
	$sth->execute();
		
	my $count = 0;
	$sth->bind_col(1, \$count);
	$sth->fetch();
	return $count;
}


sub getInternalTemplates {
	my $client = shift;
	my $dir = shift;
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	my @result = ();
	for my $plugindir (@pluginDirs) {
		my $templateDir = catdir($plugindir,'CustomLibraries',$dir);
		next unless -d $templateDir;
		my @dircontents = Slim::Utils::Misc::readDirectory($templateDir,'xml');
		for my $item (@dircontents) {
			next if -d catdir($templateDir,$item);
			my $templateId = $item;
			$templateId =~ s/\.xml$//;
			my $path = catfile($templateDir,$item);
			my $content = eval { read_file($path) };
			if(defined($content)) {
				$content = Slim::Utils::Unicode::utf8decode($content,'utf8');
				my $xml = eval { 	XMLin($content, forcearray => ["parameter","value"], keyattr => []) };
				if(defined($xml)) {
					my $parameters = $xml->{'template'}->{'parameter'};
					my $menuname = undef;
					for my $p (@$parameters) {
						if($p->{'id'} eq 'menuname') {
							my $values = $p->{'value'};
							if(defined($values) && scalar(@$values)>0) {
								$menuname = $values->[0];
								last;
							}
						}
					}
					if(defined($menuname)) {
						my %menu = (
							'id' => 'ml_'.$templateId,
							'name' => $menuname,
							'content' => $content
						);
						push @result,\%menu;
					}
				}
			}
		}
	}
	return \@result;
}

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	Plugins::CustomLibraries::Settings->new($class);
}

sub postinitPlugin {
	if(isPluginsInstalled(undef,'MusicArtistInfo')) {
		$maiPrefs = preferences('plugin.musicartistinfo');
	}
	eval {
		initLibraries();
	};
	if( $@ ) {
	    	$log->error("Startup error: $@\n");
	}		

}


sub getConfigManager {
	if(!defined($configManager)) {
		my %parameters = (
			'logHandler' => $log,
			'pluginPrefs' => $prefs,
			'pluginId' => 'CustomLibraries',
			'pluginVersion' => $PLUGINVERSION,
			'addSqlErrorCallback' => \&addSQLError,
		);
		$configManager = Plugins::CustomLibraries::ConfigManager::Main->new(\%parameters);
	}
	return $configManager;
}


sub refreshLibraries {
	$log->info("CustomLibraries: Synchronizing libraries data, please wait...\n");
	my $dbh = getCurrentDBH();
	for my $libraryid (keys %$libraries) {
		if(defined(Slim::Music::VirtualLibraries->getRealId('customlibraries_'.$libraryid))) {
			my $id = Slim::Music::VirtualLibraries->getRealId('customlibraries_'.$libraryid);
			$log->info("CustomLibraries: Deleting entries for ".Slim::Music::VirtualLibraries->getNameForId($id));
			my $delete_sth = $dbh->prepare_cached('DELETE FROM library_track WHERE library = ?');
		    $delete_sth->execute($id);
		    $delete_sth->finish();
			$log->info("CustomLibraries: Creating entries for ".Slim::Music::VirtualLibraries->getNameForId($id));
			$log->debug("CustomLibraries: Using: ".Slim::Music::VirtualLibraries::getLibraries()->{$id}->{sql});
		    $dbh->do(sprintf(Slim::Music::VirtualLibraries::getLibraries()->{$id}->{sql},$id));
		}
	}
	
	$log->info("CustomLibraries: Synchronization finished\n");
}


sub webPages {

	my %pages = (
		"CustomLibraries/customlibraries_list\.(?:htm|xml)"     => \&handleWebList,
		"CustomLibraries/customlibraries_refreshlibraries\.(?:htm|xml)"     => \&handleWebRefreshLibraries,
                "CustomLibraries/webadminmethods_edititem\.(?:htm|xml)"     => \&handleWebEditLibrary,
                "CustomLibraries/webadminmethods_saveitem\.(?:htm|xml)"     => \&handleWebSaveLibrary,
                "CustomLibraries/webadminmethods_savesimpleitem\.(?:htm|xml)"     => \&handleWebSaveSimpleLibrary,
                "CustomLibraries/webadminmethods_savenewitem\.(?:htm|xml)"     => \&handleWebSaveNewLibrary,
                "CustomLibraries/webadminmethods_savenewsimpleitem\.(?:htm|xml)"     => \&handleWebSaveNewSimpleLibrary,
                "CustomLibraries/webadminmethods_removeitem\.(?:htm|xml)"     => \&handleWebRemoveLibrary,
                "CustomLibraries/webadminmethods_newitemtypes\.(?:htm|xml)"     => \&handleWebNewLibraryTypes,
                "CustomLibraries/webadminmethods_newitemparameters\.(?:htm|xml)"     => \&handleWebNewLibraryParameters,
                "CustomLibraries/webadminmethods_newitem\.(?:htm|xml)"     => \&handleWebNewLibrary,
		"CustomLibraries/webadminmethods_deleteitemtype\.(?:htm|xml)"      => \&handleWebDeleteLibraryType,
		"CustomLibraries/customlibraries_selectlibrary\.(?:htm|xml)"      => \&handleWebSelectLibrary,
	);

	for my $page (keys %pages) {
		if(UNIVERSAL::can("Slim::Web::Pages","addPageFunction")) {
			Slim::Web::Pages->addPageFunction($page, $pages{$page});
		}else {
			Slim::Web::HTTP::addPageFunction($page, $pages{$page});
		}
	}
	Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_CUSTOMLIBRARIES' => 'plugins/CustomLibraries/customlibraries_list.html' });
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	# Pass on the current pref values and now playing info
	if(!defined($params->{'donotrefresh'})) {
		if(defined($params->{'cleancache'}) && $params->{'cleancache'}) {
			my $cacheVersion = $PLUGINVERSION;
			$cacheVersion =~ s/^.*\.([^\.]+)$/\1/;
			my $cache = Slim::Utils::Cache->new("PluginCache/CustomLibraries",$cacheVersion);
			$cache->clear();
		}
		initLibraries($client);
	}
	my $name = undef;
	my @weblibraries = ();
	my $totalLibraries = Slim::Music::VirtualLibraries::getLibraries();
	for my $key (keys %$libraries) {
		my %weblibrary = ();
		$weblibrary{'editable'} = 1;
		my $lib = $libraries->{$key};
		for my $attr (keys %$lib) {
			$weblibrary{$attr} = $lib->{$attr};
		}
		if(!isLibraryEnabledForClient($client,\%weblibrary)) {
			$weblibrary{'enabled'} = 0;
		}
		$weblibrary{'nooftracks'} = getLibraryTrackCount(Slim::Music::VirtualLibraries->getRealId('customlibraries_'.$key));

		push @weblibraries,\%weblibrary;
	}
	@weblibraries = sort { $a->{'name'} cmp $b->{'name'} } @weblibraries;

	$params->{'pluginCustomLibrariesLibraries'} = \@weblibraries;
	$params->{'pluginCustomLibrariesVersion'} = $PLUGINVERSION;

	$params->{'licensemanager'} = isPluginsInstalled($client,'LicenseManagerPlugin');
	my $request = Slim::Control::Request::executeRequest($client,['licensemanager','validate','application:CustomLibraries']);
	$params->{'licensed'} = $request->getResult("result");

	if(defined($params->{'redirect'})) {
		return Slim::Web::HTTP::filltemplatefile('plugins/CustomLibraries/customlibraries_redirect.html', $params);
	}else {
		return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
	}
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

sub handleWebRefreshLibraries {
	my ($client, $params) = @_;

	refreshLibraries($client);
	return handleWebList($client,$params);
}

sub handleWebEditLibrary {
        my ($client, $params) = @_;
	return getConfigManager()->webEditItem($client,$params);	
}

sub handleWebDeleteLibraryType {
	my ($client, $params) = @_;
	return getConfigManager()->webDeleteItemType($client,$params);	
}

sub handleWebNewLibraryTypes {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItemTypes($client,$params);	
}

sub handleWebNewLibraryParameters {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItemParameters($client,$params);	
}

sub handleWebNewLibrary {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItem($client,$params);	
}

sub handleWebSaveSimpleLibrary {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveSimpleItem($client,$params);	
}

sub handleWebRemoveLibrary {
	my ($client, $params) = @_;
	return getConfigManager()->webRemoveItem($client,$params);	
}

sub handleWebSaveNewSimpleLibrary {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveNewSimpleItem($client,$params);	
}

sub handleWebSaveNewLibrary {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveNewItem($client,$params);	
}

sub handleWebSaveLibrary {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveItem($client,$params);	
}


sub findAvailableLibraries {
	my $client = shift;
	my $request = Slim::Control::Request::executeRequest($client,['libraries']);
	my @libraries = $request->getResult("folder_loop");
	my @result = ();
	foreach my $library (@libraries) {
		my %item = (
			'id' => $library->{'id'},
			'name' => $library->{'name'},
			'value' => $library->{'id'}
		);
		push @result,\%item;
	}
	return \@result;
}

sub objectForId {
	my $type = shift;
	my $id = shift;
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
}

sub objectForUrl {
	my $url = shift;
	return Slim::Schema->objectForUrl({
		'url' => $url
	});
}

sub getCurrentDBH {
	return Slim::Schema->storage->dbh();
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
