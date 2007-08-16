# 				iPod plugin 
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

package Plugins::iPod::Plugin;

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

use Plugins::iPod::ConfigManager::Main;

use Slim::Schema;

# Information on each iPod library
my $htmlTemplate = 'plugins/iPod/ipod_list.html';
my $libraries = undef;
my $sqlerrors = '';
my $soapLiteError = 0;
my $gnuPodError = 0;
my $supportDownloadError = undef;
my %currentLibrary = ();
my $PLUGINVERSION = '1.0';

my $configManager = undef;

# Indicator if hooked or not
# 0= No
# 1= Yes
my $IPOD_HOOK = 0;

sub getDisplayName {
	return 'PLUGIN_IPOD';
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
	my $sth = $dbh->prepare("select id from ipod_libraries where libraryid=?");
	$sth->bind_param(1,$library->{'id'},SQL_VARCHAR);
	$sth->execute();
		
	my $id;
	$sth->bind_col(1, \$id);
	if($sth->fetch()) {
		$sth->finish();
		$sth = $dbh->prepare("UPDATE ipod_libraries set name=? where id=?");
		$sth->bind_param(1,$library->{'name'},SQL_VARCHAR);
		$sth->bind_param(2,$id,SQL_INTEGER);
		$sth->execute();
	}else {
		$sth->finish();
		$sth = $dbh->prepare("INSERT into ipod_libraries (libraryid,name) values (?,?)");
		$sth->bind_param(1,$library->{'id'},SQL_VARCHAR);
		$sth->bind_param(2,$library->{'name'},SQL_VARCHAR);
		$sth->execute();
		$sth->finish();
		$sth = $dbh->prepare("select id from ipod_libraries where libraryid=?");
		$sth->bind_param(1,$library->{'id'},SQL_VARCHAR);
		$sth->execute();
		$sth->bind_col(1, \$id);
		$sth->fetch();
	}
	return $id;
}

sub initPlugin {
	$soapLiteError = 0;
	eval "use SOAP::Lite";
	if ($@) {
		my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
		for my $plugindir (@pluginDirs) {
			next unless -d catdir($plugindir,"iPod","libs");
			push @INC,catdir($plugindir,"iPod","libs");
			last;
		}
		debugMsg("Using internal implementation of SOAP::Lite\n");
		eval "use SOAP::Lite";
		if ($@) {
			$soapLiteError = 1;
			msg("iPod: ERROR! Cant load internal implementation of SOAP::Lite, download/publish functionallity will not be available\n");
		}
	}
	if(!defined($supportDownloadError) && $soapLiteError) {
		$supportDownloadError = "Could not use the internal web service implementation, please download and install SOAP::Lite manually";
	}


	eval "use GNUpod::FileMagic";
	if ($@) {
		my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
		for my $plugindir (@pluginDirs) {
			next unless -d catdir($plugindir,"iPod","libs");
			push @INC,catdir($plugindir,"iPod","libs");
			last;
		}
		debugMsg("Using internal implementation of GNUpod\n");
		eval "use GNUpod::FileMagic";
		if ($@) {
			$gnuPodError = 1;
			msg("iPod: ERROR! Cant load internal implementation of GNUpod::FileMagic, iPod export functionallity will not be available\n$@\n");
		}
	}
	eval "use Plugins::iPod::Scan";
	if ($@) {
		msg("iPod: ERROR! Cant load scanning module\n$@\n");
		$gnuPodError = 1;
	}

	checkDefaults();
	initDatabase();
	eval {
		initLibraries();
	};
	if( $@ ) {
	    	errorMsg("Startup error: $@\n");
	}		

	if(Slim::Utils::Prefs::get("plugin_ipod_refresh_startup")) {
		refreshLibraries();
	}
	if ( !$IPOD_HOOK ) {
		installHook();
	}
}

sub getCustomScanFunctions {
	my @result = ();
	if(!$gnuPodError) {
		push @result,Plugins::iPod::Scan::getCustomScanFunctions();
	}
	return \@result;
}
sub getConfigManager {
	if(!defined($configManager)) {
		my $templateDir = Slim::Utils::Prefs::get('plugin_ipod_template_directory');
		if(!defined($templateDir) || !-d $templateDir) {
			$supportDownloadError = 'You have to specify a template directory before you can download libraries';
		}
		my %parameters = (
			'debugCallback' => \&debugMsg,
			'errorCallback' => \&errorMsg,
			'pluginId' => 'iPod',
			'pluginVersion' => $PLUGINVERSION,
			'downloadApplicationId' => 'iPod',
			'supportDownloadError' => $supportDownloadError,
			'addSqlErrorCallback' => \&addSQLError
		);
		$configManager = Plugins::iPod::ConfigManager::Main->new(\%parameters);
	}
	return $configManager;
}

sub shutdownPlugin {
        if ($IPOD_HOOK) {
                uninstallHook();
        }
}

# Hook the plugin to the play events.
# Do this as soon as possible during startup.
sub installHook()
{  
	debugMsg("Hook activated.\n");
	Slim::Control::Request::subscribe(\&Plugins::iPod::Plugin::rescanCallback,[['rescan']]);
	$IPOD_HOOK=1;
}

# Unhook the plugin's play event callback function. 
# Do this as the plugin shuts down, if possible.
sub uninstallHook()
{
	debugMsg("Hook deactivated.\n");
	Slim::Control::Request::unsubscribe(\&Plugins::iPod::Plugin::rescanCallback);
	$IPOD_HOOK=0;
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
		if(Slim::Utils::Prefs::get("plugin_ipod_refresh_rescan")) {
			refreshLibraries();
		}

	}
	debugMsg("Exiting rescanCallback\n");
}


sub refreshLibraries {
	msg("iPod: Synchronizing libraries data, please wait...\n");
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
		debugMsg("Deleting removed libraries\n");
		my $sth = undef;
		if($libraryIds ne '') {
			$sth = $dbh->prepare("DELETE from ipod_libraries where libraryid not in ($libraryIds)");
		}else {
			$sth = $dbh->prepare("DELETE from ipod_libraries");
		}
		$sth->execute();
		$sth->finish();

		$sth = $dbh->prepare("DELETE from ipod_track where library not in (select id from ipod_libraries)");
		$sth->execute();
		$sth->finish();

		my $sql;
		my $count;
		my $timeMeasure = Time::Stopwatch->new();
		$timeMeasure->clear();

		$timeMeasure->start();
		debugMsg("Starting to update musicbrainz id's in iPod data based on urls\n");
		# Now lets set all musicbrainz id's not already set
		$sql = "UPDATE tracks,ipod_track SET ipod_track.musicbrainz_id=tracks.musicbrainz_id where tracks.url=ipod_track.slimserverurl and tracks.musicbrainz_id like '%-%' and ipod_track.musicbrainz_id is null";
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
		debugMsg("Finished updating musicbrainz id's in iPod data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
		main::idleStreams();
		$timeMeasure->stop();
		$timeMeasure->clear();

		$timeMeasure->start();
		debugMsg("Starting to update iPod data based on musicbrainz ids\n");
		# First lets refresh all urls with musicbrainz id's
		$sql = "UPDATE tracks,ipod_track SET ipod_track.slimserverurl=tracks.url, ipod_track.track=tracks.id where tracks.musicbrainz_id is not null and tracks.musicbrainz_id=ipod_track.musicbrainz_id and (ipod_track.slimserverurl!=tracks.url or ipod_track.track!=tracks.id) and length(tracks.url)<512";
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
		debugMsg("Finished updating iPod data based on musicbrainz ids, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
		main::idleStreams();
		$timeMeasure->stop();
		$timeMeasure->clear();

		$timeMeasure->start();
		debugMsg("Starting to update iPod data based on urls\n");
		# First lets refresh all urls with musicbrainz id's
		$sql = "UPDATE ipod_track JOIN tracks on tracks.url=ipod_track.slimserverurl and ipod_track.musicbrainz_id is null set ipod_track.track=tracks.id where ipod_track.track!=tracks.id";
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
		debugMsg("Finished updating iPod data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
		main::idleStreams();
		$timeMeasure->stop();
		$timeMeasure->clear();
	
	};
	if( $@ ) {
	    warn "Database error: $DBI::errstr\n$@\n";
	}		
	msg("iPod: Synchronization finished\n");
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
	my $propertyValue = Slim::Utils::Prefs::get($1);
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
	my $driver = Slim::Utils::Prefs::get('dbsource');
	$driver =~ s/dbi:(.*?):(.*)$/$1/;
    
	#Check if tables exists and create them if not
	debugMsg("Checking if ipod_track database table exists\n");
	my $dbh = getCurrentDBH();
	my $st = $dbh->table_info();
	my $tblexists;
	while (my ( $qual, $owner, $table, $type ) = $st->fetchrow_array()) {
		if($table eq "ipod_track") {
			$tblexists=1;
		}
	}
	unless ($tblexists) {
		msg("iPod: Creating database tables\n");
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
					updateCharSet("ipod_track",$charset,$collate);
					updateCharSet("ipod_libraries",$charset,$collate);
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
		opendir(DIR, catdir($plugindir,"iPod")) || next;
       		$sqlFile = catdir($plugindir,"iPod", "SQL", $driver, $file);
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
		"ipod_list\.(?:htm|xml)"     => \&handleWebList,
		"ipod_refreshlibraries\.(?:htm|xml)"     => \&handleWebRefreshLibraries,
                "webadminmethods_edititem\.(?:htm|xml)"     => \&handleWebEditLibrary,
                "webadminmethods_saveitem\.(?:htm|xml)"     => \&handleWebSaveLibrary,
                "webadminmethods_savesimpleitem\.(?:htm|xml)"     => \&handleWebSaveSimpleLibrary,
                "webadminmethods_savenewitem\.(?:htm|xml)"     => \&handleWebSaveNewLibrary,
                "webadminmethods_savenewsimpleitem\.(?:htm|xml)"     => \&handleWebSaveNewSimpleLibrary,
                "webadminmethods_removeitem\.(?:htm|xml)"     => \&handleWebRemoveLibrary,
                "webadminmethods_newitemtypes\.(?:htm|xml)"     => \&handleWebNewLibraryTypes,
                "webadminmethods_newitemparameters\.(?:htm|xml)"     => \&handleWebNewLibraryParameters,
                "webadminmethods_newitem\.(?:htm|xml)"     => \&handleWebNewLibrary,
		"webadminmethods_login\.(?:htm|xml)"      => \&handleWebLogin,
		"webadminmethods_downloadnewitems\.(?:htm|xml)"      => \&handleWebDownloadNewLibraries,
		"webadminmethods_downloaditems\.(?:htm|xml)"      => \&handleWebDownloadLibraries,
		"webadminmethods_downloaditem\.(?:htm|xml)"      => \&handleWebDownloadLibrary,
		"webadminmethods_publishitemparameters\.(?:htm|xml)"      => \&handleWebPublishLibraryParameters,
		"webadminmethods_publishitem\.(?:htm|xml)"      => \&handleWebPublishLibrary,
		"webadminmethods_deleteitemtype\.(?:htm|xml)"      => \&handleWebDeleteLibraryType
	);

	my $value = $htmlTemplate;

	if (grep { /^iPod::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

		$value = undef;
	} 

	#Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_IPOD' => $value });

	return (\%pages,$value);
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	# Pass on the current pref values and now playing info
	if(!defined($params->{'donotrefresh'})) {
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

	$params->{'pluginiPodLibraries'} = \@weblibraries;
	if(defined($supportDownloadError)) {
		$params->{'pluginiPodDownloadMessage'} = $supportDownloadError;
	}
	$params->{'pluginiPodVersion'} = $PLUGINVERSION;
	if(defined($params->{'redirect'})) {
		return Slim::Web::HTTP::filltemplatefile('plugins/iPod/ipod_redirect.html', $params);
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
	my $prefVal = Slim::Utils::Prefs::get('plugin_ipod_library_directory');
	if (! defined $prefVal) {
		# Default to standard library directory
		my $dir=Slim::Utils::Prefs::get('playlistdir');
		debugMsg("Defaulting plugin_ipod_library_directory to:$dir\n");
		Slim::Utils::Prefs::set('plugin_ipod_library_directory', $dir);
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_ipod_showmessages');
	if (! defined $prefVal) {
		# Default to not show debug messages
		debugMsg("Defaulting plugin_ipod_showmessages to 0\n");
		Slim::Utils::Prefs::set('plugin_ipod_showmessages', 0);
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_ipod_refresh_startup');
	if (! defined $prefVal) {
		Slim::Utils::Prefs::set('plugin_ipod_refresh_startup', 1);
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_ipod_refresh_rescan');
	if (! defined $prefVal) {
		Slim::Utils::Prefs::set('plugin_ipod_refresh_rescan', 1);
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_ipod_refresh_save');
	if (! defined $prefVal) {
		Slim::Utils::Prefs::set('plugin_ipod_refresh_save', 1);
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_ipod_utf8filenames');
	if (! defined $prefVal) {
		if(Slim::Utils::OSDetect::OS() eq 'win') {
			Slim::Utils::Prefs::set('plugin_ipod_utf8filenames', 0);
		}else {
			Slim::Utils::Prefs::set('plugin_ipod_utf8filenames', 1);
		}
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_ipod_download_url');
	if (! defined $prefVal) {
		Slim::Utils::Prefs::set('plugin_ipod_download_url', 'http://erland.homeip.net/datacollection/services/DataCollection');
	}
}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_ipod_library_directory','plugin_ipod_template_directory','plugin_ipod_refresh_save','plugin_ipod_refresh_rescan','plugin_ipod_refresh_startup','plugin_ipod_utf8filenames','plugin_ipod_showmessages'],
	 GroupHead => string('PLUGIN_IPOD_SETUP_GROUP'),
	 GroupDesc => string('PLUGIN_IPOD_SETUP_GROUP_DESC'),
	 GroupLine => 1,
	 GroupSub  => 1,
	 Suppress_PrefSub  => 1,
	 Suppress_PrefLine => 1
	);
	my %setupPrefs =
	(
	plugin_ipod_showmessages => {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_IPOD_SHOW_MESSAGES')
			,'changeIntro' => string('PLUGIN_IPOD_SHOW_MESSAGES')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_ipod_showmessages"); }
		},		
	plugin_ipod_refresh_rescan => {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_IPOD_REFRESH_RESCAN')
			,'changeIntro' => string('PLUGIN_IPOD_REFRESH_RESCAN')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_ipod_refresh_rescan"); }
		},		
	plugin_ipod_refresh_startup => {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_IPOD_REFRESH_STARTUP')
			,'changeIntro' => string('PLUGIN_IPOD_REFRESH_STARTUP')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_ipod_refresh_startup"); }
		},		
	plugin_ipod_refresh_save => {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_IPOD_REFRESH_SAVE')
			,'changeIntro' => string('PLUGIN_IPOD_REFRESH_SAVE')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_ipod_refresh_save"); }
		},		
	plugin_ipod_utf8filenames => {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_IPOD_UTF8FILENAMES')
			,'changeIntro' => string('PLUGIN_IPOD_UTF8FILENAMES')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_ipod_utf8filenames"); }
		},
	plugin_ipod_library_directory => {
			'validate' => \&Slim::Utils::Validate::isDir
			,'PrefChoose' => string('PLUGIN_IPOD_LIBRARY_DIRECTORY')
			,'changeIntro' => string('PLUGIN_IPOD_LIBRARY_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_ipod_library_directory"); }
		},
	plugin_ipod_template_directory => {
			'validate' => \&Slim::Utils::Validate::isDir
			,'PrefChoose' => string('PLUGIN_IPOD_TEMPLATE_DIRECTORY')
			,'changeIntro' => string('PLUGIN_IPOD_TEMPLATE_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_ipod_template_directory"); }
		},
	);
	getConfigManager()->initWebAdminMethods();
	return (\%setupGroup,\%setupPrefs);
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

# A wrapper to allow us to uniformly turn on & off debug messages
sub debugMsg
{
	my $message = join '','iPod: ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_ipod_showmessages"));
}

sub strings {
	return <<EOF;
PLUGIN_IPOD
	EN	iPod

PLUGIN_IPOD_SETUP_GROUP
	EN	iPod

PLUGIN_IPOD_SETUP_GROUP_DESC
	EN	iPod is a plugin for synchronizing SlimServer with iPod

PLUGIN_IPOD_LIBRARY_DIRECTORY
	EN	Library directory

PLUGIN_IPOD_SHOW_MESSAGES
	EN	Show debug messages

PLUGIN_IPOD_TEMPLATE_DIRECTORY
	EN	Library templates directory

SETUP_PLUGIN_IPOD_LIBRARY_DIRECTORY
	EN	Library directory

SETUP_PLUGIN_IPOD_SHOWMESSAGES
	EN	Debugging

SETUP_PLUGIN_IPOD_TEMPLATE_DIRECTORY
	EN	Library templates directory

PLUGIN_IPOD_CHOOSE_BELOW
	EN	Choose a sub library of music to edit:

PLUGIN_IPOD_EDIT_ITEM
	EN	Edit

PLUGIN_IPOD_NEW_ITEM
	EN	Create new library

PLUGIN_IPOD_NEW_ITEM_TYPES_TITLE
	EN	Select type of library

PLUGIN_IPOD_EDIT_ITEM_DATA
	EN	Library Configuration

PLUGIN_IPOD_EDIT_ITEM_NAME
	EN	Library Name

PLUGIN_IPOD_EDIT_ITEM_FILENAME
	EN	Filename

PLUGIN_IPOD_REMOVE_ITEM_QUESTION
	EN	Are you sure you want to delete this library ?

PLUGIN_IPOD_REMOVE_ITEM_TYPE_QUESTION
	EN	Removing a library type might cause problems later if it is used in existing libraries, are you really sure you want to delete this library type ?

PLUGIN_IPOD_REMOVE_ITEM
	EN	Delete

PLUGIN_IPOD_REMOVE_ITEM_QUESTION
	EN	Are you sure you want to delete this library ?

PLUGIN_IPOD_SAVE
	EN	Save

PLUGIN_IPOD_NEXT
	EN	Next

PLUGIN_IPOD_TEMPLATE_PARAMETER_LIBRARIES
	EN	Libraries with user selectable parameters

PLUGIN_IPOD_ITEMTYPE
	EN	Customize SQL
	
PLUGIN_IPOD_ITEMTYPE_SIMPLE
	EN	Use predefined

PLUGIN_IPOD_ITEMTYPE_ADVANCED
	EN	Customize SQL

PLUGIN_IPOD_NEW_ITEM_PARAMETERS_TITLE
	EN	Please enter library parameters

PLUGIN_IPOD_EDIT_ITEM_PARAMETERS_TITLE
	EN	Please enter library parameters

PLUGIN_IPOD_LOGIN_USER
	EN	Username

PLUGIN_IPOD_LOGIN_PASSWORD
	EN	Password

PLUGIN_IPOD_LOGIN_FIRSTNAME
	EN	First name

PLUGIN_IPOD_LOGIN_LASTNAME
	EN	Last name

PLUGIN_IPOD_LOGIN_EMAIL
	EN	e-mail

PLUGIN_IPOD_ANONYMOUSLOGIN
	EN	Anonymous

PLUGIN_IPOD_LOGIN
	EN	Login

PLUGIN_IPOD_REGISTERLOGIN
	EN	Register &amp; Login

PLUGIN_IPOD_REGISTER_TITLE
	EN	Register a new user

PLUGIN_IPOD_LOGIN_TITLE
	EN	Login

PLUGIN_IPOD_DOWNLOAD_ITEMS
	EN	Download more libraries

PLUGIN_IPOD_PUBLISH_ITEM
	EN	Publish

PLUGIN_IPOD_PUBLISH
	EN	Publish

PLUGIN_IPOD_PUBLISHPARAMETERS_TITLE
	EN	Please specify information about the library

PLUGIN_IPOD_PUBLISH_NAME
	EN	Name

PLUGIN_IPOD_PUBLISH_DESCRIPTION
	EN	Description

PLUGIN_IPOD_PUBLISH_ID
	EN	Unique identifier

PLUGIN_IPOD_LASTCHANGED
	EN	Last changed

PLUGIN_IPOD_PUBLISHMESSAGE
	EN	Thanks for choosing to publish your library. The advantage of publishing a library is that other users can use it and it will also be used for ideas of new functionallity in the Multi Library plugin. Publishing a library is also a great way of improving the functionality in the Multi Library plugin by showing the developer what types of libraries you use, besides those already included with the plugin.

PLUGIN_IPOD_REGISTERMESSAGE
	EN	You can choose to publish your library either anonymously or by registering a user and login. The advantage of registering is that other people will be able to see that you have published the library, you will get credit for it and you will also be sure that no one else can update or change your published library. The e-mail adress will only be used to contact you if I have some questions to you regarding one of your libraries, it will not show up on any web pages. If you already have registered a user, just hit the Login button.

PLUGIN_IPOD_LOGINMESSAGE
	EN	You can choose to publish your library either anonymously or by registering a user and login. The advantage of registering is that other people will be able to see that you have published the library, you will get credit for it and you will also be sure that no one else can update or change your published library. Hit the &quot;Register &amp; Login&quot; button if you have not previously registered.

PLUGIN_IPOD_PUBLISHMESSAGE_DESCRIPTION
	EN	It is important that you enter a good description of your library, describe what your library do and if it is based on one of the existing libraries it is a good idea to mention this and describe which extensions you have made. <br><br>It is also a good idea to try to make the &quot;Unique identifier&quot; as uniqe as possible as this will be used for filename when downloading the library. This is especially important if you have choosen to publish your library anonymously as it can easily be overwritten if the identifier is not unique. Please try to not use spaces and language specific characters in the unique identifier since these could cause problems on some operating systems.

PLUGIN_IPOD_REFRESH_DOWNLOADED_ITEMS
	EN	Download last version of existing libraries

PLUGIN_IPOD_DOWNLOAD_TEMPLATE_OVERWRITE_WARNING
	EN	A library type with that name already exists, please change the name or select to overwrite the existing library type

PLUGIN_IPOD_DOWNLOAD_TEMPLATE_OVERWRITE
	EN	Overwrite existing

PLUGIN_IPOD_PUBLISH_OVERWRITE
	EN	Overwrite existing

PLUGIN_IPOD_DOWNLOAD_TEMPLATE_NAME
	EN	Unique identifier

PLUGIN_IPOD_EDIT_ITEM_OVERWRITE
	EN	Overwrite existing

PLUGIN_IPOD_DOWNLOAD_ITEMS
	EN	Download more libraries

PLUGIN_IPOD_DOWNLOAD_QUESTION
	EN	This operation will download latest version of all libraries, this might take some time. Please note that this will overwrite any local changes you have made in built-in or previously downloaded library types. Are you sure you want to continue ?

PLUGIN_IPOD_REFRESH_LIBRARIES
	EN	Refresh libraries

PLUGIN_IPOD_REFRESH_RESCAN
	EN	Refresh libraries after rescan

SETUP_PLUGIN_IPOD_REFRESH_RESCAN
	EN	Rescan refresh

PLUGIN_IPOD_REFRESH_STARTUP
	EN	Refresh libraries at slimserver startup

SETUP_PLUGIN_IPOD_REFRESH_STARTUP
	EN	Startup refresh

PLUGIN_IPOD_UTF8FILENAMES
	EN	UTF-8 encoded filenames (requires slimserver restart)

SETUP_PLUGIN_IPOD_UTF8FILENAMES
	EN	Filename encoding

PLUGIN_IPOD_REFRESH_SAVE
	EN	Refresh libraries after library has been save

SETUP_PLUGIN_IPOD_REFRESH_SAVE
	EN	Refresh on save

PLUGIN_IPOD_SELECT
	EN	Select a library
EOF

}

1;

__END__
