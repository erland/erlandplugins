# 				PortableSync plugin 
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

package Plugins::PortableSync::Plugin;

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

use Plugins::PortableSync::ConfigManager::Main;

use Plugins::PortableSync::Settings;

use Slim::Schema;

my $prefs = preferences('plugin.portablesync');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.portablesync',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_PORTABLESYNC',
});
my $driver;

$prefs->migrate(1, sub {
	$prefs->set('library_directory', Slim::Utils::Prefs::OldPrefs->get('plugin_portablesync_library_directory') || $serverPrefs->get('playlistdir')  );
	$prefs->set('template_directory',  Slim::Utils::Prefs::OldPrefs->get('plugin_portablesync_template_directory')   || ''  );
	$prefs->set('download_url',  Slim::Utils::Prefs::OldPrefs->get('plugin_portablesync_download_url')   || 'http://erland.homeip.net/datacollection/services/DataCollection'  );
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_portablesync_refresh_startup'))) {
		$prefs->set('refresh_startup', Slim::Utils::Prefs::OldPrefs->get('plugin_portablesync_refresh_startup'));
	}
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_portablesync_refresh_rescan'))) {
		$prefs->set('refresh_rescan', Slim::Utils::Prefs::OldPrefs->get('plugin_portablesync_refresh_rescan'));
	}
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_portablesync_refresh_save'))) {
		$prefs->set('refresh_save', Slim::Utils::Prefs::OldPrefs->get('plugin_portablesync_refresh_save'));
	}
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_portablesync_utf8filenames'))) {
		$prefs->set('utf8filenames', Slim::Utils::Prefs::OldPrefs->get('plugin_portablesync_utf8filenames'));
	}
	1;
});
$prefs->setValidate('dir', 'library_directory'  );
$prefs->setValidate('dir', 'template_directory'  );

# Information on each portable library
my $htmlTemplate = 'plugins/PortableSync/portable_list.html';
my $libraries = undef;
my $sqlerrors = '';
my $gnuPodError = 0;
my %currentLibrary = ();
my $PLUGINVERSION = undef;

my $configManager = undef;

# Indicator if hooked or not
# 0= No
# 1= Yes
my $PORTABLESYNC_HOOK = 0;

sub getDisplayName {
	return 'PLUGIN_PORTABLESYNC';
}

sub getDisplayText {
	my ($client, $item) = @_;

	my $name = '';
	if($item) {
		$name = $item->{'libraryname'};
	}
	return $name;
}

sub initLibraries {
	my $client = shift;

	my $itemConfiguration = getConfigManager()->readItemConfiguration($client,1);

	my $localLibraries = $itemConfiguration->{'libraries'};

	for my $libraryid (keys %$localLibraries) {
		$localLibraries->{$libraryid}->{'libraryno'} = initDatabaseLibrary($localLibraries->{$libraryid});
	}

	$libraries = $localLibraries;
	return $libraries;
}

sub initDatabaseLibrary {
	my $library = shift;

	my $dbh = getCurrentDBH();
	my $sth = $dbh->prepare("select id from portable_libraries where libraryid=?");
	$sth->bind_param(1,$library->{'id'},SQL_VARCHAR);
	$sth->execute();
		
	my $id;
	$sth->bind_col(1, \$id);
	if($sth->fetch()) {
		$sth->finish();
		$sth = $dbh->prepare("UPDATE portable_libraries set name=? where id=?");
		$sth->bind_param(1,$library->{'name'},SQL_VARCHAR);
		$sth->bind_param(2,$id,SQL_INTEGER);
		$sth->execute();
	}else {
		$sth->finish();
		$sth = $dbh->prepare("INSERT into portable_libraries (libraryid,name) values (?,?)");
		$sth->bind_param(1,$library->{'id'},SQL_VARCHAR);
		$sth->bind_param(2,$library->{'name'},SQL_VARCHAR);
		$sth->execute();
		$sth->finish();
		$sth = $dbh->prepare("select id from portable_libraries where libraryid=?");
		$sth->bind_param(1,$library->{'id'},SQL_VARCHAR);
		$sth->execute();
		$sth->bind_col(1, \$id);
		$sth->fetch();
	}
	return $id;
}

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	Plugins::PortableSync::Settings->new($class);

	eval "use Plugins::PortableSync::Scan";
	if ($@) {
		$log->error("ERROR! Cant load scanning module\n$@\n");
		$gnuPodError = 1;
	}

	checkDefaults();
	initDatabase();
	eval {
		initLibraries();
	};
	if( $@ ) {
	    	$log->error("Startup error: $@\n");
	}		

	if($prefs->get("refresh_startup") && !$serverPrefs->get('autorescan')) {
		refreshLibraries();
	}
	if ( !$PORTABLESYNC_HOOK ) {
		installHook();
	}
}

sub getCustomScanFunctions {
	my @result = ();
	if(!$gnuPodError) {
		push @result,Plugins::PortableSync::Scan::getCustomScanFunctions();
	}
	return \@result;
}
sub getConfigManager {
	if(!defined($configManager)) {
		my %parameters = (
			'logHandler' => $log,
			'pluginPrefs' => $prefs,
			'pluginId' => 'PortableSync',
			'pluginVersion' => $PLUGINVERSION,
			'downloadApplicationId' => 'PortableSync',
			'addSqlErrorCallback' => \&addSQLError,
			'downloadVersion' => 1,
		);
		$configManager = Plugins::PortableSync::ConfigManager::Main->new(\%parameters);
	}
	return $configManager;
}

sub shutdownPlugin {
        if ($PORTABLESYNC_HOOK) {
                uninstallHook();
        }
}

# Hook the plugin to the play events.
# Do this as soon as possible during startup.
sub installHook()
{  
	$log->debug("Hook activated.\n");
	Slim::Control::Request::subscribe(\&Plugins::PortableSync::Plugin::rescanCallback,[['rescan']]);
	$PORTABLESYNC_HOOK=1;
}

# Unhook the plugin's play event callback function. 
# Do this as the plugin shuts down, if possible.
sub uninstallHook()
{
	$log->debug("Hook deactivated.\n");
	Slim::Control::Request::unsubscribe(\&Plugins::PortableSync::Plugin::rescanCallback);
	$PORTABLESYNC_HOOK=0;
}

sub rescanCallback($) 
{
	$log->debug("Entering rescanCallback\n");
	# These are the two passed parameters
	my $request=shift;
	my $client = $request->client();

	######################################
	## Rescan finished
	######################################
	if ( $request->isCommand([['rescan'],['done']]) )
	{
		if($prefs->get("refresh_rescan")) {
			refreshLibraries();
		}

	}
	$log->debug("Exiting rescanCallback\n");
}


sub refreshLibraries {
	$log->info("Synchronizing libraries data, please wait...\n");
	eval {
		initLibraries();
		my $dbh = getCurrentDBH();
		my $libraryIds = '';
		for my $key (keys %$libraries) {
			if($libraryIds ne '') {
				$libraryIds .= ',';
			}
			$libraryIds .= $dbh->quote($key);
		}
	
		# remove non existent libraries
		$log->debug("Deleting removed libraries\n");
		my $sth = undef;
		if($libraryIds ne '') {
			$sth = $dbh->prepare("DELETE from portable_libraries where libraryid not in ($libraryIds)");
		}else {
			$sth = $dbh->prepare("DELETE from portable_libraries");
		}
		$sth->execute();
		$sth->finish();

		$sth = $dbh->prepare("DELETE from portable_track where library not in (select id from portable_libraries)");
		$sth->execute();
		$sth->finish();

		my $sql;
		my $count;
		my $timeMeasure = Time::Stopwatch->new();
		$timeMeasure->clear();

		$timeMeasure->start();
		$log->debug("Starting to update musicbrainz id's in portable data based on urls\n");
		# Now lets set all musicbrainz id's not already set
		if($driver eq 'mysql') {
			$sql = "UPDATE tracks,portable_track SET portable_track.musicbrainz_id=tracks.musicbrainz_id where tracks.url=portable_track.slimserverurl and tracks.musicbrainz_id like '%-%' and portable_track.musicbrainz_id is null";
		}else {
			$sql = "UPDATE portable_track SET musicbrainz_id=(select musicbrainz_id from tracks where tracks.url=portable_track.slimserverurl and tracks.musicbrainz_id like '%-%' and portable_track.musicbrainz_id is null) where exists (select musicbrainz_id from tracks where tracks.url=portable_track.slimserverurl and tracks.musicbrainz_id like '%-%' and portable_track.musicbrainz_id is null)";
		}
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
		$log->debug("Finished updating musicbrainz id's in portable data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
		main::idleStreams();
		$timeMeasure->stop();
		$timeMeasure->clear();

		$timeMeasure->start();
		$log->debug("Starting to update portable data based on musicbrainz ids\n");
		if($driver eq 'mysql') {
			# First lets refresh all urls with musicbrainz id's
			$sql = "UPDATE tracks,portable_track SET portable_track.slimserverurl=tracks.url, portable_track.track=tracks.id where tracks.musicbrainz_id is not null and tracks.musicbrainz_id=portable_track.musicbrainz_id and (portable_track.slimserverurl!=tracks.url or portable_track.track!=tracks.id) and length(tracks.url)<512";
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
		}else {
			# First lets refresh all urls with musicbrainz id's
			$sql = "create temporary table temp_portable_track as select tracks.id,tracks.url,tracks.musicbrainz_id from tracks,portable_track where tracks.musicbrainz_id is not null and tracks.musicbrainz_id=portable_track.musicbrainz_id and (portable_track.slimserverurl!=tracks.url or portable_track.track!=tracks.id)";
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
			}else {
				$sth->finish();
				# First lets refresh all urls with musicbrainz id's
				$sql = "UPDATE portable_track SET slimserverurl=(select url from temp_portable_track where temp_portable_track.musicbrainz_id=portable_track.musicbrainz_id), track=(select id from temp_portable_track where temp_portable_track.musicbrainz_id=portable_track.musicbrainz_id) where exists (select id from temp_portable_track where temp_portable_track.musicbrainz_id=portable_track.musicbrainz_id)";
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
				# First lets refresh all urls with musicbrainz id's
				$sql = "drop table temp_portable_track";
				$sth = $dbh->prepare( $sql );
				eval {
					$sth->execute();
					commit($dbh);
				};
				if( $@ ) {
				    warn "Database error: $DBI::errstr\n";
				    eval {
				    	rollback($dbh); #just die if rollback is failing
				    };
				}
			}
			$sth->finish();
		}
		$log->debug("Finished updating portable data based on musicbrainz ids, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
		main::idleStreams();
		$timeMeasure->stop();
		$timeMeasure->clear();

		$timeMeasure->start();
		$log->debug("Starting to update portable data based on urls\n");
		# First lets refresh all urls with musicbrainz id's
		if($driver eq 'mysql') {
			$sql = "UPDATE portable_track JOIN tracks on tracks.url=portable_track.slimserverurl and portable_track.musicbrainz_id is null set portable_track.track=tracks.id where portable_track.track!=tracks.id";
		}else {
			$sql = "UPDATE portable_track set track=(select id from tracks where tracks.url=portable_track.slimserverurl and tracks.id!=portable_track.track) where exists (select id from tracks where tracks.url=portable_track.slimserverurl and tracks.id!=portable_track.track)"	
		}
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
		$log->debug("Finished updating portable data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
		main::idleStreams();
		$timeMeasure->stop();
		$timeMeasure->clear();
	
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n$@\n";
	}		
	$log->info("Synchronization finished\n");
}


sub replaceParameters {
    my $originalValue = shift;
    my $parameters = shift;
    my $dbh = getCurrentDBH();

    if(defined($parameters)) {
        for my $param (keys %$parameters) {
            my $value = encode_entities($parameters->{$param},"&<>\'\"");
	    $value = Slim::Utils::Unicode::utf8on($value);
	    $value = Slim::Utils::Unicode::utf8encode_locale($value);
            $originalValue =~ s/\{$param\}/$value/g;
        }
    }
    while($originalValue =~ m/\{property\.(.*?)\}/) {
	my $propertyValue = $serverPrefs->get($1);
	if(defined($propertyValue)) {
		$propertyValue = encode_entities($propertyValue,"&<>\'\"");
	    	$propertyValue = substr($propertyValue, 1, -1);
		$originalValue =~ s/\{property\.$1\}/$propertyValue/g;
	}else {
		$originalValue =~ s/\{property\..*?\}//g;
	}
    }

    return $originalValue;
}

sub initDatabase {
	$driver = $serverPrefs->get('dbsource');
	$driver =~ s/dbi:(.*?):(.*)$/$1/;
    
	if(UNIVERSAL::can("Slim::Schema","sourceInformation")) {
		my ($source,$username,$password);
		($driver,$source,$username,$password) = Slim::Schema->sourceInformation;
	}
    
	#Check if tables exists and create them if not
	$log->debug("Checking if portable_track database table exists\n");
	my $dbh = getCurrentDBH();
	my $st = $dbh->table_info();
	my $tblexists;
	while (my ( $qual, $owner, $table, $type ) = $st->fetchrow_array()) {
		if($table eq "portable_track") {
			$tblexists=1;
		}
	}
	unless ($tblexists) {
		$log->info("Creating database tables\n");
		executeSQLFile("dbcreate.sql");
	}

	if($driver eq 'mysql') {
		my $sth = $dbh->prepare("show create table tracks");
		my $charset;
		eval {
			$log->debug("Checking charsets on tables\n");
			$sth->execute();
			my $line = undef;
			$sth->bind_col( 2, \$line);
			if( $sth->fetch() ) {
				if(defined($line) && ($line =~ /.*CHARSET\s*=\s*([^\s\r\n]+).*/)) {
					$charset = $1;
					my $collate = '';
					if($line =~ /.*COLLATE\s*=\s*([^\s\r\n]+).*/) {
						$collate = $1;
					}elsif($line =~ /.*collate\s+([^\s\r\n]+).*/) {
						$collate = $1;
					}
					$log->debug("Got tracks charset = $charset and collate = $collate\n");
				
					if(defined($charset)) {
					
						$sth->finish();
						updateCharSet("portable_track",$charset,$collate);
						updateCharSet("portable_libraries",$charset,$collate);
					}
				}
			}
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		}
		$sth->finish();
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
			$log->debug("Got $table charset = $table_charset and collate = $table_collate\n");
			if($charset ne $table_charset || ($collate && (!$table_collate || $collate ne $table_collate))) {
				$log->debug("Converting $table to correct charset=$charset collate=$collate\n");
				if(!$collate) {
					eval { $dbh->do("alter table $table convert to character set $charset") };
				}else {
					eval { $dbh->do("alter table $table convert to character set $charset collate $collate") };
				}
				if ($@) {
					$log->debug("Couldn't convert charsets: $@\n");
				}
			}
		}
	}
	$sth->finish();
}

sub executeSQLFile {
        my $file  = shift;

        my $sqlFile;
	for my $plugindir (Slim::Utils::OSDetect::dirsFor('Plugins')) {
		opendir(DIR, catdir($plugindir,"PortableSync")) || next;
       		$sqlFile = catdir($plugindir,"PortableSync", "SQL", $driver, $file);
       		closedir(DIR);
       	}

        $log->debug("Executing SQL file $sqlFile\n");

        open(my $fh, $sqlFile) or do {

                $log->error("Couldn't open: $sqlFile : $!\n");
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


                        $log->debug("Executing SQL statement: [$statement]\n");

                        eval { $dbh->do($statement) };

                        if ($@) {
                                $log->error("Couldn't execute SQL statement: [$statement] : [$@]\n");
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
		"PortableSync/portable_list\.(?:htm|xml)"     => \&handleWebList,
		"PortableSync/portablesync_refreshlibraries\.(?:htm|xml)"     => \&handleWebRefreshLibraries,
                "PortableSync/webadminmethods_edititem\.(?:htm|xml)"     => \&handleWebEditLibrary,
                "PortableSync/webadminmethods_saveitem\.(?:htm|xml)"     => \&handleWebSaveLibrary,
                "PortableSync/webadminmethods_savesimpleitem\.(?:htm|xml)"     => \&handleWebSaveSimpleLibrary,
                "PortableSync/webadminmethods_savenewitem\.(?:htm|xml)"     => \&handleWebSaveNewLibrary,
                "PortableSync/webadminmethods_savenewsimpleitem\.(?:htm|xml)"     => \&handleWebSaveNewSimpleLibrary,
                "PortableSync/webadminmethods_removeitem\.(?:htm|xml)"     => \&handleWebRemoveLibrary,
                "PortableSync/webadminmethods_newitemtypes\.(?:htm|xml)"     => \&handleWebNewLibraryTypes,
                "PortableSync/webadminmethods_newitemparameters\.(?:htm|xml)"     => \&handleWebNewLibraryParameters,
                "PortableSync/webadminmethods_newitem\.(?:htm|xml)"     => \&handleWebNewLibrary,
		"PortableSync/webadminmethods_login\.(?:htm|xml)"      => \&handleWebLogin,
		"PortableSync/webadminmethods_downloadnewitems\.(?:htm|xml)"      => \&handleWebDownloadNewLibraries,
		"PortableSync/webadminmethods_downloaditems\.(?:htm|xml)"      => \&handleWebDownloadLibraries,
		"PortableSync/webadminmethods_downloaditem\.(?:htm|xml)"      => \&handleWebDownloadLibrary,
		"PortableSync/webadminmethods_publishitemparameters\.(?:htm|xml)"      => \&handleWebPublishLibraryParameters,
		"PortableSync/webadminmethods_publishitem\.(?:htm|xml)"      => \&handleWebPublishLibrary,
		"PortableSync/webadminmethods_deleteitemtype\.(?:htm|xml)"      => \&handleWebDeleteLibraryType
	);

	for my $page (keys %pages) {
		if(UNIVERSAL::can("Slim::Web::Pages","addPageFunction")) {
			Slim::Web::Pages->addPageFunction($page, $pages{$page});
		}else {
			Slim::Web::HTTP::addPageFunction($page, $pages{$page});
		}
	}
	Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_PORTABLESYNC' => 'plugins/PortableSync/portable_list.html' });
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	# Pass on the current pref values and now playing info
	if(!defined($params->{'donotrefresh'})) {
		if(defined($params->{'cleancache'}) && $params->{'cleancache'}) {
			my $cache = Slim::Utils::Cache->new("FileCache/PortableSync");
			$cache->clear();
		}
		initLibraries($client);
	}
	my $name = undef;
	my @weblibraries = ();
	for my $key (keys %$libraries) {
		my %weblibrary = ();
		my $lib = $libraries->{$key};
		for my $attr (keys %$lib) {
			$weblibrary{$attr} = $lib->{$attr};
		}
		push @weblibraries,\%weblibrary;
	}
	@weblibraries = sort { $a->{'name'} cmp $b->{'name'} } @weblibraries;

	$params->{'pluginPortableSyncLibraries'} = \@weblibraries;
	my $templateDir = $prefs->get('template_directory');
	if(!defined($templateDir) || !-d $templateDir) {
		$params->{'pluginPortableSyncDownloadMessage'} = 'You have to specify a template directory before you can download libraries';
	}
	$params->{'pluginPortableSyncVersion'} = $PLUGINVERSION;
	if(defined($params->{'redirect'})) {
		return Slim::Web::HTTP::filltemplatefile('plugins/PortableSync/portablesync_redirect.html', $params);
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

	if($params->{'type'}) {
		my $libraryId = unescape($params->{'type'});
		selectLibrary($client,$libraryId);
	}
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

sub handleWebLogin {
	my ($client, $params) = @_;
	return getConfigManager()->webLogin($client,$params);	
}

sub handleWebPublishLibraryParameters {
	my ($client, $params) = @_;
	return getConfigManager()->webPublishItemParameters($client,$params);	
}

sub handleWebPublishLibrary {
	my ($client, $params) = @_;
	return getConfigManager()->webPublishItem($client,$params);	
}

sub handleWebDownloadLibraries {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadItems($client,$params);	
}

sub handleWebDownloadNewLibraries {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadNewItems($client,$params);	
}

sub handleWebDownloadLibrary {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadItem($client,$params);	
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
	my $prefVal = $prefs->get('library_directory');
	if (! defined $prefVal) {
		# Default to standard library directory
		my $dir=$serverPrefs->get('playlistdir');
		$log->debug("Defaulting library_directory to:$dir\n");
		$prefs->set('library_directory', $dir);
	}
	$prefVal = $prefs->get('refresh_startup');
	if (! defined $prefVal) {
		$prefs->set('refresh_startup', 1);
	}
	$prefVal = $prefs->get('refresh_rescan');
	if (! defined $prefVal) {
		$prefs->set('refresh_rescan', 1);
	}
	$prefVal = $prefs->get('refresh_save');
	if (! defined $prefVal) {
		$prefs->set('refresh_save', 1);
	}
	$prefVal = $prefs->get('utf8filenames');
	if (! defined $prefVal) {
		if(Slim::Utils::OSDetect::OS() eq 'win') {
			$prefs->set('utf8filenames', 0);
		}else {
			$prefs->set('utf8filenames', 1);
		}
	}
	$prefVal = $prefs->get('download_url');
	if (! defined $prefVal) {
		$prefs->set('download_url', 'http://erland.homeip.net/datacollection/services/DataCollection');
	}
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

sub validateIsDirOrEmpty {
	my $arg = shift;
	if(!$arg || $arg eq '') {
		return $arg;
	}else {
		return Slim::Utils::Validate::isDir($arg);
	}
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

1;

__END__
