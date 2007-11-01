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

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;
use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;
use Slim::Utils::Validate;
use POSIX qw(ceil);
use File::Spec::Functions qw(:ALL);
use DBI qw(:sql_types);
use FindBin qw($Bin);
use Plugins::CustomScan::Time::Stopwatch;
use Plugins::CustomScan::Template::Reader;
use Plugins::CustomScan::ModuleSettings;
use Plugins::CustomScan::Settings;
use Plugins::CustomScan::Manage;
use Plugins::CustomScan::Scanner;

my $useLongUrls = 1;

my @pluginDirs = ();
our $PLUGINVERSION =  undef;

# Indicator if hooked or not
# 0= No
# 1= Yes
my $CUSTOMSCAN_HOOK = 0;

my $prefs = preferences('plugin.customscan');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.customscan',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_CUSTOMSCAN',
});

my %empty = ();
$prefs->migrate(1, sub {
	$prefs->set('long_urls', Slim::Utils::Prefs::OldPrefs->get('plugin_customscan_long_urls') || 1  );
	$prefs->set('rescan_refresh',  Slim::Utils::Prefs::OldPrefs->get('plugin_customscan_rescan_refresh')   || 1  );
	$prefs->set('startup_refresh',  Slim::Utils::Prefs::OldPrefs->get('plugin_customscan_startup_refresh')   || 1  );
	$prefs->set('auto_rescan',  Slim::Utils::Prefs::OldPrefs->get('plugin_customscan_auto_rescan')   || 1  );
	$prefs->set('titleformats', Slim::Utils::Prefs::OldPrefs->get('plugin_customscan_titleformats')  || [] );
	my $properties = Slim::Utils::Prefs::OldPrefs->get('plugin_customscan_properties');
	my %propertiesHash = ();
	for my $property (@$properties) {
		if($property =~ /^([^=]+)=(.*)$/) {
			$propertiesHash{$1}=$2;
		}
	}
	$prefs->set('properties', \%propertiesHash);
	1;
});

sub getDisplayName {
	return 'PLUGIN_CUSTOMSCAN';
}

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	initDatabase();
	if ( !$CUSTOMSCAN_HOOK ) {
		refreshTitleFormats();
		installHook();
	}
	checkDefaults();
	Plugins::CustomScan::Settings->new($class);
	Plugins::CustomScan::Manage->new($class);
	Plugins::CustomScan::ModuleSettings->new($class);
	Slim::Utils::Scheduler::add_task(\&lateInitPlugin);
}

sub lateInitPlugin {
	Slim::Utils::Timers::setTimer(undef,time()+1,\&delayedLateInitPlugin);
	return 0;
}

sub delayedLateInitPlugin {
	Plugins::CustomScan::Scanner::initScanner($PLUGINVERSION);
}

sub shutdownPlugin {
        $log->info("disabling\n");
        if ($CUSTOMSCAN_HOOK) {
                uninstallHook();
        }
	Plugins::CustomScan::Scanner::shutdownScanner();
}

# Hook the plugin to the play events.
# Do this as soon as possible during startup.
sub installHook()
{  
	$log->info("Installing Custom Scan hooks\n");
	Slim::Control::Request::subscribe(\&Plugins::CustomScan::Plugin::commandCallback,[['rescan']]);
	Slim::Control::Request::addDispatch(['customscan','status','_module'], [0, 1, 0, \&cliGetStatus]);
	Slim::Control::Request::addDispatch(['customscan','abort'], [0, 0, 0, \&cliAbortAll]);
	Slim::Control::Request::addDispatch(['customscan','scan','_module'], [0, 0, 0, \&cliScan]);
	Slim::Control::Request::addDispatch(['customscan','clear','_module'], [0, 0, 0, \&cliClear]);
	Slim::Control::Request::addDispatch(['customscan', 'changedstatus', '_module','_status'],[0, 0, 0, undef]);
	$CUSTOMSCAN_HOOK=1;
}

# Unhook the plugin's play event callback function. 
# Do this as the plugin shuts down, if possible.
sub uninstallHook()
{
	$log->info("Uninstalling Custom Scan hooks\n");
	Slim::Control::Request::unsubscribe(\&Plugins::CustomScan::Plugin::commandCallback);
	$CUSTOMSCAN_HOOK=0;
}

sub getFunctions {
	return {}
}

sub commandCallback($) 
{
	$log->debug("Entering commandCallback\n");
	# These are the two passed parameters
	my $request=shift;
	my $client = $request->client();

	######################################
	## Rescan finished
	######################################
	if ( $request->isCommand([['rescan'],['done']]) )
	{
		if($prefs->get("auto_rescan")) {
			Plugins::CustomScan::Scanner::fullRescan();
		}elsif($prefs->get("refresh_rescan")) {
			Plugins::CustomScan::Scanner::refreshData();
		}

	}
	$log->debug("Exiting commandCallback\n");
}

sub checkDefaults {

	my $prefVal = $prefs->get('showmessages');
	if (! defined $prefVal) {
		$prefs->set('showmessages', 0);
	}

	if(!defined($prefs->get("refresh_startup"))) {
		$prefs->set("refresh_startup",1);
	}
	if(!defined($prefs->get("refresh_rescan"))) {
		$prefs->set("refresh_rescan",1);
	}
	if(!defined($prefs->get("auto_rescan"))) {
		$prefs->set("auto_rescan",1);
	}
	if(!defined($prefs->get("long_urls"))) {
		$prefs->set("long_urls",1);
	}

	if(!defined($prefs->get("properties"))) {
		my %empty = ();
		$prefs->set("properties",\%empty);
	}

	if (!defined($prefs->get('titleformats'))) {
		my @titleFormats = ();
		$prefs->set('titleformats', \@titleFormats);
	}
}

sub getPluginModules {
	return Plugins::CustomScan::Scanner::getPluginModules();
}

sub getSQLPlayListTemplates {
	my $client = shift;
	return Plugins::CustomScan::Template::Reader::getTemplates($client,'CustomScan',$PLUGINVERSION,'FileCache/SQLPlayList','PlaylistTemplates','xml');
}
sub getSQLPlayListPlaylists {
	my $client = shift;
	my $result = Plugins::CustomScan::Template::Reader::getTemplates($client,'CustomScan',$PLUGINVERSION,'FileCache/SQLPlayList','Playlists','xml','template','playlist','simple',1);
	my @filteredResult = ();
	my $dbh = getCurrentDBH();
	for my $playlist (@$result) {
		my $sql = undef;
		my $include = 1;
		if($playlist->{'id'} =~ /^cslastfm_/) {
			$sql = "SELECT id from customscan_contributor_attributes where module='cslastfm' limit 1";
			$include = 0;
		}elsif($playlist->{'id'} =~ /^customtag_/) {
			$sql = "SELECT id from customscan_track_attributes where module='customtag' limit 1";
			$include = 0;
		}elsif($playlist->{'id'} =~ /^mixedtag_/) {
			$sql = "SELECT id from customscan_track_attributes where module='mixedtag' limit 1";
			$include = 0;
		}elsif($playlist->{'id'} =~ /^csamazon_/) {
			$sql = "SELECT id from customscan_album_attributes where module='csamazon' limit 1";
			$include = 0;
		}
		if(defined($sql)) {
			my $sth = $dbh->prepare($sql);
			eval {
				$sth->execute();
				if($sth->fetch()) {
					$include = 1;
				}
			};
		}
		if($include) {
			push @filteredResult,$playlist;
		}
	}
	return \@filteredResult;
}

sub getDatabaseQueryDataQueries {
	my $client = shift;
	my $result = Plugins::CustomScan::Template::Reader::getTemplates($client,'CustomScan',$PLUGINVERSION,'FileCache/DatabaseQuery','DataQueries','xml','template','dataquery','simple',1);
	my @filteredResult = ();
	my $dbh = getCurrentDBH();
	for my $query (@$result) {
		my $sql = undef;
		my $include = 1;
		if($query->{'id'} =~ /^cslastfm_/) {
			$sql = "SELECT id from customscan_contributor_attributes where module='cslastfm' limit 1";
			$include = 0;
		}elsif($query->{'id'} =~ /^customtag_/) {
			$sql = "SELECT id from customscan_track_attributes where module='customtag' limit 1";
			$include = 0;
		}elsif($query->{'id'} =~ /^mixedtag_/) {
			$sql = "SELECT id from customscan_track_attributes where module='mixedtag' limit 1";
			$include = 0;
		}elsif($query->{'id'} =~ /^csamazon_/) {
			$sql = "SELECT id from customscan_album_attributes where module='csamazon' limit 1";
			$include = 0;
		}
		if(defined($sql)) {
			my $sth = $dbh->prepare($sql);
			eval {
				$sth->execute();
				if($sth->fetch()) {
					$include = 1;
				}
			};
		}
		if($include) {
			push @filteredResult,$query;
		}
	}
	return \@filteredResult;
}
sub getDatabaseQueryTemplates {
	my $client = shift;
	return Plugins::CustomScan::Template::Reader::getTemplates($client,'CustomScan',$PLUGINVERSION,'FileCache/DatabaseQuery','DataQueryTemplates','xml');
}

sub getCustomBrowseMenus {
	my $client = shift;
	my $result = Plugins::CustomScan::Template::Reader::getTemplates($client,'CustomScan',$PLUGINVERSION,'FileCache/CustomBrowse','Menus','xml','template','menu','simple',1);
	my @filteredResult = ();
	my $dbh = getCurrentDBH();
	for my $playlist (@$result) {
		my $sql = undef;
		my $include = 1;
		if($playlist->{'id'} =~ /^cslastfm_/) {
			$sql = "SELECT id from customscan_contributor_attributes where module='cslastfm' limit 1";
			$include = 0;
		}elsif($playlist->{'id'} =~ /^customtag_/) {
			$sql = "SELECT id from customscan_track_attributes where module='customtag' limit 1";
			$include = 0;
		}elsif($playlist->{'id'} =~ /^mixedtag_/) {
			$sql = "SELECT id from customscan_track_attributes where module='mixedtag' limit 1";
			$include = 0;
		}elsif($playlist->{'id'} =~ /^csamazon_/) {
			$sql = "SELECT id from customscan_album_attributes where module='csamazon' limit 1";
			$include = 0;
		}
		if(defined($sql)) {
			my $sth = $dbh->prepare($sql);
			eval {
				$sth->execute();
				if($sth->fetch()) {
					$include = 1;
				}
			};
		}
		if($include) {
			push @filteredResult,$playlist;
		}
	}
	return \@filteredResult;
}
sub getCustomBrowseTemplates {
	my $client = shift;
	return Plugins::CustomScan::Template::Reader::getTemplates($client,'CustomScan',$PLUGINVERSION,'FileCache/CustomBrowse','MenuTemplates','xml');
}
sub getCustomBrowseContextTemplates {
	my $client = shift;
	return Plugins::CustomScan::Template::Reader::getTemplates($client,'CustomScan',$PLUGINVERSION,'FileCache/CustomBrowse','ContextMenuTemplates','xml');
}

sub getCustomBrowseContextMenus {
	my $client = shift;
	my $result = Plugins::CustomScan::Template::Reader::getTemplates($client,'CustomScan',$PLUGINVERSION,'FileCache/CustomBrowse','ContextMenus','xml','template','menu','simple',1);
	my @filteredResult = ();
	my $dbh = getCurrentDBH();
	for my $playlist (@$result) {
		my $sql = undef;
		my $include = 1;
		if($playlist->{'id'} =~ /^cslastfm_/) {
			$sql = "SELECT id from customscan_contributor_attributes where module='cslastfm' limit 1";
			$include = 0;
		}elsif($playlist->{'id'} =~ /^customtag_/) {
			$sql = "SELECT id from customscan_track_attributes where module='customtag' limit 1";
			$include = 0;
		}elsif($playlist->{'id'} =~ /^mixedtag_/) {
			$sql = "SELECT id from customscan_track_attributes where module='mixedtag' limit 1";
			$include = 0;
		}elsif($playlist->{'id'} =~ /^csamazon_/) {
			$sql = "SELECT id from customscan_album_attributes where module='csamazon' limit 1";
			$include = 0;
		}
		if(defined($sql)) {
			my $sth = $dbh->prepare($sql);
			eval {
				$sth->execute();
				if($sth->fetch()) {
					$include = 1;
				}
			};
		}
		if($include) {
			push @filteredResult,$playlist;
		}
	}
	return \@filteredResult;
}
sub getCustomBrowseMixes {
	my $client = shift;
	return Plugins::CustomScan::Template::Reader::getTemplates($client,'CustomScan',$PLUGINVERSION,'FileCache/CustomBrowse','Mixes','xml','mix');
}
sub getSQLPlayListTemplateData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;
	
	my $data = Plugins::CustomScan::Template::Reader::readTemplateData('CustomScan','PlaylistTemplates',$templateItem->{'id'});
	return $data;
}

sub getSQLPlayListPlaylistData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;
	my $data = Plugins::CustomScan::Template::Reader::readTemplateData('CustomScan','Playlists',$templateItem->{'id'},"xml");
	return $data;
}

sub getDatabaseQueryDataQueryData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;
	my $data = Plugins::CustomScan::Template::Reader::readTemplateData('CustomScan','DataQueries',$templateItem->{'id'},"xml");
	return $data;
}

sub getCustomBrowseMenuData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;
	my $data = Plugins::CustomScan::Template::Reader::readTemplateData('CustomScan','Menus',$templateItem->{'id'},"xml");
	return $data;
}

sub getDatabaseQueryTemplateData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;
	
	my $data = Plugins::CustomScan::Template::Reader::readTemplateData('CustomScan','DataQueryTemplates',$templateItem->{'id'});
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

sub addTitleFormat
{
	my $titleformat = shift;
	my $titleFormats = $serverPrefs->get('titleFormat');

	foreach my $format ( @$titleFormats ) {
		if($titleformat eq $format) {
			return;
		}
	}
	$log->info("Adding: $titleformat\n");
	push @$titleFormats,$titleformat;
	$serverPrefs->set('titleFormat',$titleFormats);
}


sub refreshTitleFormats() {
        my $titleformats = $prefs->get('titleformats');
	for my $format (@$titleformats) {
		if($format) {
			Slim::Music::TitleFormatter::addFormat("CUSTOMSCAN_$format",
				sub {
					$log->debug("Retreiving title format: $format\n");
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
		    					$log->warn("Database error: $DBI::errstr\n$@\n");
						}
					}
					$log->debug("Finished retreiving title format: $format=$result\n");
					return $result;
				});
			addTitleFormat("DISC-TRACKNUM. TITLE - CUSTOMSCAN_$format");
		}
	}
}

sub setCustomScanProperty {
	my $name = shift;
	my $value = shift;

        my $properties = $prefs->get('properties');
	$properties->{$name} = $value;
	$prefs->set('properties',$properties);
}


sub getCustomSkipFilterTypes {
	my @result = ();

	my %customtag = (
		'id' => 'customscan_customtag_customtag',
		'name' => 'Custom tag',
		'description' => 'Skip songs which have a custom tag',
		'parameters' => [
			{
				'id' => 'customtag',
				'type' => 'sqlsinglelist',
				'name' => 'Custom tag',
				'data' => 'select distinct attr,attr,attr from customscan_track_attributes order by attr'
			}
		]
	);
	push @result, \%customtag;
	my %notcustomtag = (
		'id' => 'customscan_customtag_notcustomtag',
		'name' => 'Not Custom tag',
		'description' => 'Skip songs which dont have a custom tag',
		'parameters' => [
			{
				'id' => 'customtag',
				'type' => 'sqlsinglelist',
				'name' => 'Custom tag',
				'data' => 'select distinct attr,attr,attr from customscan_track_attributes order by attr'
			}
		]
	);
	push @result, \%notcustomtag;
	return \@result;
}

sub checkCustomSkipFilterType {
	my $client = shift;
	my $filter = shift;
	my $track = shift;

	my $currentTime = time();
	my $parameters = $filter->{'parameter'};
	my $result = 0;
	my $dbh = getCurrentDBH();
	if($filter->{'id'} eq 'customscan_customtag_customtag') {
		my $matching = 0;
		for my $parameter (@$parameters) {
			if($parameter->{'id'} eq 'customtag') {
				my $values = $parameter->{'value'};
				my $customtag = $values->[0] if(defined($values) && scalar(@$values)>0);

				my $sth = $dbh->prepare("select track from customscan_track_attributes where track=? and module='customtag' and attr=?");
				eval {
					$sth->bind_param(1, $track->id , SQL_INTEGER);
					$sth->bind_param(2, $customtag , SQL_VARCHAR);
					$sth->execute();
					if( $sth->fetch() ) {
						$result = 1;
					}
				};
				if ($@) {
					$log->warn("Error executing SQL: $@\n$DBI::errstr\n");
				}
				$sth->finish();
				last;
			}
		}
	}elsif($filter->{'id'} eq 'customscan_customtag_notcustomtag') {
		my $matching = 0;
		for my $parameter (@$parameters) {
			if($parameter->{'id'} eq 'customtag') {
				my $values = $parameter->{'value'};
				my $customtag = $values->[0] if(defined($values) && scalar(@$values)>0);

				my $sth = $dbh->prepare("select track from customscan_track_attributes where track=? and module='customtag' and attr=?");
				$result = 1;
				eval {
					$sth->bind_param(1, $track->id , SQL_INTEGER);
					$sth->bind_param(2, $customtag , SQL_VARCHAR);
					$sth->execute();
					if( $sth->fetch() ) {
						$result = 0;
					}
				};
				if ($@) {
					$result = 0;
					$log->warn("Error executing SQL: $@\n$DBI::errstr\n");
				}
				$sth->finish();
				last;
			}
		}
	}

	return $result;
}

sub initDatabase {
	#Check if tables exists and create them if not
	$log->debug("Checking if customscan_track_attributes database table exists\n");
	my $dbh = getCurrentDBH();
	my $st = $dbh->table_info();
	my $tblexists;
	while (my ( $qual, $owner, $table, $type ) = $st->fetchrow_array()) {
		if($table eq "customscan_track_attributes") {
			$tblexists=1;
		}
	}
	unless ($tblexists) {
		$log->warn("CustomScan: Creating database tables\n");
		executeSQLFile("dbcreate.sql");
	}

	eval { $dbh->do("select valuesort from customscan_track_attributes limit 1;") };
	if ($@) {
		$log->warn("CustomScan: Upgrading database adding table column valuesort, please wait...\n");
		executeSQLFile("dbupgrade_valuesort.sql");
	}

	eval { $dbh->do("select extravalue from customscan_track_attributes limit 1;") };
	if ($@) {
		$log->warn("CustomScan: Upgrading database adding table column extravalue, please wait...\n");
		executeSQLFile("dbupgrade_extravalue.sql");
	}

	eval { $dbh->do("select valuetype from customscan_track_attributes limit 1;") };
	if ($@) {
		$log->warn("CustomScan: Upgrading database adding table column valuetype, please wait...\n");
		executeSQLFile("dbupgrade_valuetype.sql");
	}

	my $sth = $dbh->prepare("select version()");
	my $majorMysqlVersion = undef;
	my $minorMysqlVersion = undef;
	eval {
		$log->info("Checking MySQL version\n");
		$sth->execute();
		my $version = undef;
		$sth->bind_col( 1, \$version);
		if( $sth->fetch() ) {
			if(defined($version) && (lc($version) =~ /^(\d+)\.(\d+)\.(\d+)[^\d]*/)) {
				$majorMysqlVersion = $1;
				$minorMysqlVersion = $2;
				$log->info("Got MySQL $version\n");
			}
		}
		$sth->finish();
	};
	if( $@ ) {
	    $log->error("Database error: $DBI::errstr\n$@\n");
	}
	if(!defined($majorMysqlVersion)) {
		$majorMysqlVersion = 5;
		$minorMysqlVersion = 0;
		$log->warn("Unable to retrieve MySQL version, using default\n");
	}
	$useLongUrls = 1;
	if($majorMysqlVersion<5 || !$prefs->get("long_urls")) {
		$useLongUrls = 0;
		$prefs->set("long_urls",0);
	}
	$sth = $dbh->prepare("show create table customscan_track_attributes");
	eval {
		$log->info("Checking datatype on customscan_track_attributes\n");
		$sth->execute();
		my $line = undef;
		$sth->bind_col( 2, \$line);
		if( $sth->fetch() ) {
			if(defined($line) && (lc($line) =~ /url.*(text|mediumtext)/m)) {
				$log->warn("CustomScan: Upgrading database changing type of url column, please wait...\n");
				if($useLongUrls) {
					executeSQLFile("dbupgrade_url_type.sql");
				}else {
					executeSQLFile("dbupgrade_url_type255.sql");
				}
			}elsif(defined($line) && $useLongUrls && (lc($line) =~ /url.*(varchar\(255\))/m)) {
				$log->warn("CustomScan: Upgrading database changing type of url column to varchar(511), please wait...\n");
				executeSQLFile("dbupgrade_url_type.sql");
			}elsif(defined($line) && !$useLongUrls && (lc($line) =~ /url.*(varchar\(511\))/m)) {
				$log->warn("CustomScan: Upgrading database changing type of url column to varchar(255), please wait...\n");
				executeSQLFile("dbupgrade_url_type255.sql");
			}
			if(defined($line) && (lc($line) =~ /attr.*(varchar\(255\))/m)) {
				$log->warn("CustomScan: Upgrading database changing type of attr column to varchar(40), please wait...\n");
				executeSQLFile("dbupgrade_attr_type.sql");
			}
		}
	};
	if( $@ ) {
	    $log->error("Database error: $DBI::errstr\n$@\n");
	}
	$sth->finish();
	$sth = $dbh->prepare("show create table tracks");
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
					updateCharSet("customscan_contributor_attributes",$charset,$collate);
					updateCharSet("customscan_album_attributes",$charset,$collate);
					updateCharSet("customscan_track_attributes",$charset,$collate);
				}
			}
		}
	};
	if( $@ ) {
	    $log->error("Database error: $DBI::errstr\n");
	}
	$sth->finish();
	$sth = $dbh->prepare("show index from customscan_album_attributes;");
	my $timeMeasure = Time::Stopwatch->new();

	eval {
		$log->debug("Checking if indexes is needed for customscan_album_attributes\n");
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
			$timeMeasure->clear();
			$timeMeasure->start();
			$log->warn("CustomScan: No musicbrainzIndex index found in customscan_album_attributes, creating index...\n");
			eval { $dbh->do("create index musicbrainzIndex on customscan_album_attributes (musicbrainz_id);") };
			if ($@) {
				$log->error("Couldn't add index: $@\n");
			}else {
				$log->warn("Index created after ".$timeMeasure->getElapsedTime()." seconds\n");
			}
			$timeMeasure->stop();
		}
		if(!$foundValue) {
			$timeMeasure->clear();
			$timeMeasure->start();
			$log->warn("CustomScan: No module_attr_value_idx index found in customscan_album_attributes, creating index...\n");
			eval { $dbh->do("create index module_attr_value_idx on customscan_album_attributes (module,attr,value);") };
			if ($@) {
				$log->error("Couldn't add index: $@\n");
			}else {
				$log->warn("Index created after ".$timeMeasure->getElapsedTime()." seconds\n");
			}
			$timeMeasure->stop();
		}
	};
	if( $@ ) {
	    $log->error("Database error: $DBI::errstr\n$@\n");
	}
	$sth->finish();
	$sth = $dbh->prepare("show index from customscan_contributor_attributes;");
	eval {
		$log->debug("Checking if indexes is needed for customscan_contributor_attributes\n");
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
			$timeMeasure->clear();
			$timeMeasure->start();
			$log->warn("CustomScan: No musicbrainzIndex index found in customscan_contributor_attributes, creating index...\n");
			eval { $dbh->do("create index musicbrainzIndex on customscan_contributor_attributes (musicbrainz_id);") };
			if ($@) {
				$log->error("Couldn't add index: $@\n");
			}else {
				$log->warn("Index created after ".$timeMeasure->getElapsedTime()." seconds\n");
			}
			$timeMeasure->stop();
		}
		if(!$foundValue) {
			$timeMeasure->clear();
			$timeMeasure->start();
			$log->warn("CustomScan: No module_attr_value_idx index found in customscan_contributor_attributes, creating index...\n");
			eval { $dbh->do("create index module_attr_value_idx on customscan_contributor_attributes (module,attr,value);") };
			if ($@) {
				$log->error("Couldn't add index: $@\n");
			}else {
				$log->warn("Index created after ".$timeMeasure->getElapsedTime()." seconds\n");
			}
			$timeMeasure->stop();
		}
	};
	if( $@ ) {
	    $log->error("Database error: $DBI::errstr\n$@\n");
	}
	$sth->finish();
	$sth = $dbh->prepare("show index from customscan_track_attributes;");
	eval {
		$log->info("Checking if indexes is needed for customscan_track_attributes\n");
		$sth->execute();
		my $keyname;
		$sth->bind_col( 3, \$keyname );
		my $foundMB = 0;
		my $foundUrl = 0;
		my $foundValue = 0;
		my $foundAttrModule = 0;
		my $foundModuleAttrExtraValue = 0;
		my $foundExtraValueAttrModuleTrack = 0;
		my $foundTrackModuleAttrExtraValue = 0;
		my $foundModuleAttrExtraValue = 0;
		my $foundModuleAttrValueSort = 0;
		while( $sth->fetch() ) {
			if($keyname eq "musicbrainzIndex") {
				$foundMB = 1;
			}elsif($keyname eq "urlIndex") {
				$foundUrl = 1;
			}elsif($keyname eq "module_attr_value_idx") {
				$foundValue = 1;
			}elsif($keyname eq "attr_module_idx") {
				$foundAttrModule = 1;
			}elsif($keyname eq "extravalue_attr_module_track_idx") {
				$foundExtraValueAttrModuleTrack = 1;
			}elsif($keyname eq "track_module_attr_extravalue_idx") {
				$foundTrackModuleAttrExtraValue = 1;
			}elsif($keyname eq "module_attr_extravalue_idx") {
				$foundModuleAttrExtraValue = 1;
			}elsif($keyname eq "module_attr_valuesort_idx") {
				$foundModuleAttrValueSort = 1;
			}
		}
		if(!$foundMB) {
			$timeMeasure->clear();
			$timeMeasure->start();
			$log->warn("CustomScan: No musicbrainzIndex index found in customscan_track_attributes, creating index...\n");
			eval { $dbh->do("create index musicbrainzIndex on customscan_track_attributes (musicbrainz_id);") };
			if ($@) {
				$log->error("Couldn't add index: $@\n");
			}else {
				$log->warn("Index created after ".$timeMeasure->getElapsedTime()." seconds\n");
			}
			$timeMeasure->stop();
		}
		if(!$foundUrl) {
			$timeMeasure->clear();
			$timeMeasure->start();
			$log->warn("CustomScan: No urlIndex index found in customscan_track_attributes, creating index...\n");
			eval { $dbh->do("create index urlIndex on customscan_track_attributes (url(255));") };
			if ($@) {
				$log->error("Couldn't add index: $@\n");
			}else {
				$log->warn("CustomScan: Index creation finished\n");
			}
		}
		if(!$foundValue) {
			$timeMeasure->clear();
			$timeMeasure->start();
			$log->warn("CustomScan: No module_attr_value_idx index found in customscan_track_attributes, creating index...\n");
			eval { $dbh->do("create index module_attr_value_idx on customscan_track_attributes (module,attr,value);") };
			if ($@) {
				$log->error("Couldn't add index: $@\n");
			}else {
				$log->warn("Index created after ".$timeMeasure->getElapsedTime()." seconds\n");
			}
			$timeMeasure->stop();
		}
		if(!$foundAttrModule) {
			$timeMeasure->clear();
			$timeMeasure->start();
			$log->warn("CustomScan: No attr_module_idx index found in customscan_track_attributes, creating index...\n");
			eval { $dbh->do("create index attr_module_idx on customscan_track_attributes (attr,module);") };
			if ($@) {
				$log->error("Couldn't add index: $@\n");
			}else {
				$log->warn("Index created after ".$timeMeasure->getElapsedTime()." seconds\n");
			}
			$timeMeasure->stop();
		}
		if(!$foundExtraValueAttrModuleTrack) {
			$timeMeasure->clear();
			$timeMeasure->start();
			$log->warn("CustomScan: No extravalue_attr_module_track_idx index found in customscan_track_attributes, creating index...\n");
			eval { $dbh->do("create index extravalue_attr_module_track_idx on customscan_track_attributes (extravalue,attr,module,track);") };
			if ($@) {
				$log->error("Couldn't add index: $@\n");
			}else {
				$log->warn("CustomScan: Index creation finished\n");
			}
		}
		if(!$foundTrackModuleAttrExtraValue) {
			$timeMeasure->clear();
			$timeMeasure->start();
			$log->warn("CustomScan: No track_module_attr_extravalue_idx index found in customscan_track_attributes, creating index...\n");
			eval { $dbh->do("create index track_module_attr_extravalue_idx on customscan_track_attributes (track,module,attr,extravalue);") };
			if ($@) {
				$log->error("Couldn't add index: $@\n");
			}else {
				$log->warn("Index created after ".$timeMeasure->getElapsedTime()." seconds\n");
			}
			$timeMeasure->stop();
		}
		if(!$foundModuleAttrExtraValue) {
			$timeMeasure->clear();
			$timeMeasure->start();
			$log->warn("CustomScan: No module_attr_extravalue_idx index found in customscan_track_attributes, creating index...\n");
			eval { $dbh->do("create index module_attr_extravalue_idx on customscan_track_attributes (module,attr,extravalue);") };
			if ($@) {
				$log->error("Couldn't add index: $@\n");
			}else {
				$log->warn("Index created after ".$timeMeasure->getElapsedTime()." seconds\n");
			}
			$timeMeasure->stop();
		}
		if(!$foundModuleAttrValueSort) {
			$timeMeasure->clear();
			$timeMeasure->start();
			$log->warn("CustomScan: No module_attr_valuesort_idx index found in customscan_track_attributes, creating index...\n");
			eval { $dbh->do("create index module_attr_valuesort_idx on customscan_track_attributes (module,attr,valuesort);") };
			if ($@) {
				$log->error("Couldn't add index: $@\n");
			}else {
				$log->warn("Index created after ".$timeMeasure->getElapsedTime()." seconds\n");
			}
			$timeMeasure->stop();
		}
	};
	if( $@ ) {
	    $log->error("Database error: $DBI::errstr\n$@\n");
	}
	$sth->finish();

	if($prefs->get("refresh_startup")) {
		$log->warn("CustomScan: Synchronizing Custom Scan data, please wait...\n");
		Plugins::CustomScan::Scanner::refreshData();
		$log->warn("CustomScan: Synchronization finished\n");
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
				$log->warn("Converting $table to correct charset=$charset collate=$collate\n");
				if(!$collate) {
					eval { $dbh->do("alter table $table convert to character set $charset") };
				}else {
					eval { $dbh->do("alter table $table convert to character set $charset collate $collate") };
				}
				if ($@) {
					$log->error("Couldn't convert charsets: $@\n");
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
		opendir(DIR, catdir($plugindir,"CustomScan")) || next;
       		$sqlFile = catdir($plugindir,"CustomScan", "SQL", "mysql", $file);
       		closedir(DIR);
       	}

        $log->info("Executing SQL file $sqlFile\n");

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
sub getAvailableTitleFormats {
	my $dbh = getCurrentDBH();
	my %result = ();
	$result{'-1'} = ' ';
        my $titleformats = $prefs->get('titleformats');
	for my $format (@$titleformats) {
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
	my $result = $prefs->get('properties');
	return $result;
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
	return Slim::Utils::Validate::isInt($arg);
}

sub validateTrueFalseWrapper {
	my $arg = shift;
	return Slim::Utils::Validate::trueFalse($arg);
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
	return Slim::Utils::Validate::isDir($arg);
}

sub validateAcceptAllWrapper {
	my $arg = shift;
	return Slim::Utils::Validate::acceptAll($arg);
}

sub validateIntOrEmpty {
	my $arg = shift;
	if(!$arg || $arg eq '' || $arg =~ /^\d+$/) {
		return $arg;
	}
	return undef;
}

sub cliGetStatus {
	$log->debug("Entering cliGetStatus\n");
	my $request = shift;
	
	if ($request->isNotQuery([['customscan'],['status']])) {
		$log->warn("Incorrect command\n");
		$request->setStatusBadDispatch();
		$log->debug("Exiting cliGetStatus\n");
		return;
	}
	# get our parameters
  	my $moduleKey    = $request->getParam('_module');
	my $modules = getPluginModules();
	my @resultModules = ();
  	if(!defined $moduleKey || $moduleKey eq '') {
		push @resultModules,keys %$modules;
  	}elsif(!defined($modules->{$moduleKey})) {
		$log->warn("Incorrect module specified\n");
		$request->setStatusBadParams();
		$log->debug("Exiting cliGetStatus\n");
		return;
	}else {
		push @resultModules,$moduleKey;
	}

  	$request->addResult('count',scalar(@resultModules));
	my $moduleno = 0;
	for my $key (@resultModules) {
	  	$request->addResultLoop('@modules',$moduleno,'id',$key);
	  	$request->addResultLoop('@modules',$moduleno,'name',$modules->{$key}->{'name'});
		if(defined(Plugins::CustomScan::Scanner::isScanning($key))) {
		  	$request->addResultLoop('@modules',$moduleno,'status',Plugins::CustomScan::Scanner::isScanning($key));
		}else {
		  	$request->addResultLoop('@modules',$moduleno,'status',0);
		}
		$moduleno++;
	}
	
	$request->setStatusDone();
	$log->debug("Exiting cliGetStatus\n");
}


sub cliAbortAll {
	$log->debug("Entering cliAbortAll\n");
	my $request = shift;
	
	if ($request->isNotCommand([['customscan'],['abortall']])) {
		$log->warn("Incorrect command\n");
		$request->setStatusBadDispatch();
		$log->debug("Exiting cliAbortAll\n");
		return;
	}

	Plugins::CustomScan::Scanner::fullAbort();
	$request->setStatusDone();
	$log->debug("Exiting cliAbortAll\n");
}

sub cliScan {
	$log->debug("Entering cliScan\n");
	my $request = shift;
	
	if ($request->isNotCommand([['customscan'],['scan']])) {
		$log->warn("Incorrect command\n");
		$request->setStatusBadDispatch();
		$log->debug("Exiting cliScan\n");
		return;
	}

  	my $moduleKey = $request->getParam('_module');
	my $modules = getPluginModules();
  	if(defined $moduleKey && $moduleKey ne '' && !defined($modules->{$moduleKey})) {
		$log->warn("Incorrect module specified\n");
		$request->setStatusBadParams();
		$log->debug("Exiting cliClear\n");
		return;
  	}

	if(!defined($moduleKey)) {
		Plugins::CustomScan::Scanner::fullRescan();
	}else {
		Plugins::CustomScan::Scanner::moduleRescan($moduleKey);
	}
	$request->setStatusDone();
	$log->debug("Exiting cliScan\n");
}

sub cliClear {
	$log->debug("Entering cliClear\n");
	my $request = shift;
	
	if ($request->isNotCommand([['customscan'],['clear']])) {
		$log->warn("Incorrect command\n");
		$request->setStatusBadDispatch();
		$log->debug("Exiting cliClear\n");
		return;
	}

  	my $moduleKey = $request->getParam('_module');
	my $modules = getPluginModules();
  	if(defined $moduleKey && $moduleKey ne '' && !defined($modules->{$moduleKey})) {
		$log->warn("Incorrect module specified\n");
		$request->setStatusBadParams();
		$log->debug("Exiting cliClear\n");
		return;
  	}

	if(!defined($moduleKey)) {
		Plugins::CustomScan::Scanner::fullClear();
	}else {
		Plugins::CustomScan::Scanner::moduleClear($moduleKey);
	}

	$request->setStatusDone();
	$log->debug("Exiting cliClear\n");
}

sub getCurrentDBH {
	return Slim::Schema->storage->dbh();
}

sub getCurrentDS {
	return 'Slim::Schema';
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

1;

__END__
