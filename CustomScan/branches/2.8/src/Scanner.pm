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

package Plugins::CustomScan::Scanner;

use strict;

use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;
use File::Spec::Functions qw(:ALL);
use DBI qw(:sql_types);
use Time::Stopwatch;

#Load internal scanning modules
use Plugins::CustomScan::Modules::MixedTag;
use Plugins::CustomScan::Modules::CustomTag;
use Plugins::CustomScan::Modules::RatingTag;
#use Plugins::CustomScan::Modules::Amazon; #Disabled until new API has been implemented
use Plugins::CustomScan::Modules::LastFM;

our %scanningModulesInProgress = ();
my $scanningAborted = 0;
my $useLongUrls = 1;
my $PLUGINVERSION;
my $modules = ();
my $driver;

my $prefs = preferences('plugin.customscan');
my $serverPrefs = preferences('server');

my $log = Slim::Utils::Log::logger('plugin.customscan');

sub initScanner {
	$PLUGINVERSION = shift;

	$modules = getPluginModules();
	for my $key (keys %$modules) {
		my $module = $modules->{$key};
		my $properties = $module->{'properties'};
		for my $property (@$properties) {
			my $value = Plugins::CustomScan::Plugin::getCustomScanProperty($property->{'id'});
			if(!defined($value)) {
				Plugins::CustomScan::Plugin::setCustomScanProperty($property->{'id'},$property->{'value'});
			}
		}
	}

	for my $key (keys %$modules) {
		my $module = $modules->{$key};
		my $initFunction = $module->{'initModule'};
		if(defined($module->{'initModule'})) {
			no strict 'refs';
			$log->debug("Calling: initModule on $key\n");
			eval { &{$module->{'initModule'}}(); };
			if ($@) {
				$log->error("CustomScan: Failed to call initModule on module $key: $@\n");
			}
			use strict 'refs';
		}
	}
	if($prefs->get("refresh_startup") && !$serverPrefs->get('autorescan')) {
		refreshData();
	}
}

sub initDatabase {
	#Check if tables exists and create them if not
	$driver = $serverPrefs->get('dbsource');
	$driver =~ s/dbi:(.*?):(.*)$/$1/;
    
	if(UNIVERSAL::can("Slim::Schema","sourceInformation")) {
		my ($source,$username,$password);
		($driver,$source,$username,$password) = Slim::Schema->sourceInformation;
	}

	$log->debug("Checking if customscan_track_attributes database table exists\n");
	my $dbh = getCurrentDBH();
	if($driver eq 'SQLite') {
		createSQLiteFunctions();
	}
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
	if($driver eq 'mysql') {
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
	}

	if($driver eq 'mysql') {
		my $sth = $dbh->prepare("show index from customscan_album_attributes;");
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
	}else {
		$log->info("Creating indexes\n");
		executeSQLFile("dbindex.sql");
	}
}

sub createSQLiteFunctions {
	if($driver eq 'SQLite') {
		my $dbh = getCurrentDBH();
		$dbh->func('if', 3, sub {
			my ($expr,$true,$false) = @_;
			return $expr?$true:$false;
		    }, 'create_function');
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
			if($charset ne $table_charset || ($collate && (!$table_collate || $collate ne $table_collate)) || (!$collate && $table_collate)) {
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
       		$sqlFile = catdir($plugindir,"CustomScan", "SQL", $driver, $file);
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

sub shutdownScanner {
        $log->info("disabling\n");
	if(!$modules) {
		for my $key (keys %$modules) {
			my $module = $modules->{$key};
			my $initFunction = $module->{'exitModule'};
			if(defined($module->{'exitModule'})) {
				no strict 'refs';
				$log->debug("Calling: exitModule on $key\n");
				eval { &{$module->{'exitModule'}}(); };
				if ($@) {
					$log->error("CustomScan: Failed to call exitModule on module $key: $@\n");
				}
				use strict 'refs';
			}
		}
	}
}

sub getPluginModules {
	my %plugins = ();
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		# Disabled Amazon until new API has been implemented
		for my $plugin (qw(MixedTag CustomTag LastFM RatingTag)) {
			no strict 'refs';
			my $fullname = "Plugins::CustomScan::Modules::$plugin";
			if(UNIVERSAL::can("${fullname}","getCustomScanFunctions")) {
				my $data = eval { &{"${fullname}::getCustomScanFunctions"}($PLUGINVERSION); };
				if ($@) {
					$log->error("CustomScan: Failed to call module $fullname: $@\n");
				}elsif(defined($data) && defined($data->{'id'}) && defined($data->{'name'})) {
					if(!defined($data->{'minpluginversion'}) || isAllowedVersion($data->{'minpluginversion'})) {
						$plugins{$fullname} = $data;
						my $enabled = $prefs->get('module_'.$data->{'id'}.'_enabled');
						if((!defined($enabled) && $data->{'defaultenabled'})|| $enabled) {
							$plugins{$fullname}->{'enabled'} = 1;
						}else {
							$plugins{$fullname}->{'enabled'} = 0;
						}
						my $active = $prefs->get('module_'.$data->{'id'}.'_active');
						if((!defined($active))|| $active) {
							$plugins{$fullname}->{'active'} = 1;
						}else {
							$plugins{$fullname}->{'active'} = 0;
						}
						my $order = $prefs->get('module_'.$data->{'id'}.'_order');
						if((!defined($order) && $data->{'order'})) {
							$plugins{$fullname}->{'order'} = $data->{'order'};
						}else {
							$plugins{$fullname}->{'order'} = $order;
						}
					}
				}
			}
			use strict 'refs';
		}
	}
	my @enabledplugins = Slim::Utils::PluginManager->enabledPlugins();
	for my $plugin (@enabledplugins) {
		my $fullname = "$plugin";
		no strict 'refs';
		eval "use $fullname";
		if ($@) {
			$log->error("CustomScan: Failed to load module $fullname: $@\n");
		}elsif(UNIVERSAL::can("${fullname}","getCustomScanFunctions")) {
			my $data = eval { &{$fullname . "::getCustomScanFunctions"}(); };
			if ($@) {
				$log->error("CustomScan: Failed to load module $fullname: $@\n");
			}elsif(defined($data)) {
				my @functions = ();
				if(ref($data) eq 'ARRAY') {
					push @functions,@$data;
				}else {
					push @functions,$data;
				}
				for my $function (@functions) {
					if(defined($function->{'id'}) && defined($function->{'name'})) {
						$plugins{$fullname."->".$function->{'id'}} = $function;
						my $enabled = $prefs->get('module_'.$function->{'id'}.'_enabled');
						if((!defined($enabled) && $function->{'defaultenabled'})|| $enabled) {
							$plugins{$fullname."->".$function->{'id'}}->{'enabled'} = 1;
						}else {
							$plugins{$fullname."->".$function->{'id'}}->{'enabled'} = 0;
						}
						my $active = $prefs->get('module_'.$function->{'id'}.'_active');
						if((!defined($active))|| $active) {
							$plugins{$fullname."->".$function->{'id'}}->{'active'} = 1;
						}else {
							$plugins{$fullname."->".$function->{'id'}}->{'active'} = 0;
						}
						my $order = $prefs->get('module_'.$function->{'id'}.'_order');
						if((!defined($order) && $function->{'order'})) {
							$plugins{$fullname."->".$function->{'id'}}->{'order'} = $function->{'order'};
						}else {
							$plugins{$fullname."->".$function->{'id'}}->{'order'} = $order;
						}
					}
				}
			}
		}
		use strict 'refs';
	}
	return \%plugins;
}

sub isAllowedVersion {
	my $minpluginversion = shift;

	my $include = 1;
	if(defined($minpluginversion) && $minpluginversion =~ /(\d+)\.(\d+).*/) {
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
	return $include;
}

sub fullRescan {
	$log->info("Performing rescan\n");
	
	if(scalar(grep (/1/,values %scanningModulesInProgress))>0) {
		$log->warn("CustomScan: Scanning already in progress, wait until its finished\n");
		return "Scanning already in progress, wait until its finished";
	}
	my @moduleKeys = ();
	my $array = getSortedModuleKeys();
	push @moduleKeys,@$array;
	for my $key (@moduleKeys) {
		my $module = $modules->{$key};
		if($module->{'enabled'} && $module->{'active'} && (!defined($module->{'licensed'}) || $module->{'licensed'})) {
			$scanningModulesInProgress{$key}=1;
			Slim::Control::Request::notifyFromArray(undef, ['customscan', 'changedstatus', $key, 1]);
		}
	}

	$scanningAborted = 0;
	refreshData();

	$modules = getPluginModules();

	for my $key (keys %$modules) {
		my $module = $modules->{$key};
		if($module->{'enabled'} && $module->{'active'} && defined($module->{'licensed'}) && !$module->{'licensed'}) {
			$log->warn("Not using ".$module->{'name'}." module because no license was detected");
		}
	}

	for my $key (@moduleKeys) {
		my $module = $modules->{$key};
		if($module->{'enabled'} && $module->{'active'} && (!defined($module->{'licensed'}) || $module->{'licensed'}) && defined($module->{'scanInit'})) {
			no strict 'refs';
			$log->debug("Calling: scanInit on $key\n");
			eval { &{$module->{'scanInit'}}(); };
			if ($@) {
				$log->error("CustomScan: Failed to call scanInit on module $key: $@\n");
				$scanningModulesInProgress{$key}=-1;
			}
			use strict 'refs';
		}
	}
	my %scanningContext = ();
	initArtistScan(undef,\%scanningContext);
	return;
}
sub moduleRescan {
	my $moduleKey = shift;
	
	if($scanningModulesInProgress{$moduleKey} == 1 || $scanningModulesInProgress{$moduleKey} == -1) {
		$log->warn("CustomScan: Scanning already in progress, wait until its finished\n");
		return "Scanning already in progress, wait until its finished";
	}
	$log->info("Performing module rescan\n");
	if(!$modules) {
		$modules = getPluginModules();
	}
	my $module = $modules->{$moduleKey};
	if(defined($module) && defined($module->{'id'}) && $module->{'active'} && (!defined($module->{'licensed'}) || $module->{'licensed'})) {
		$scanningModulesInProgress{$moduleKey} = 1;
		Slim::Control::Request::notifyFromArray(undef, ['customscan', 'changedstatus', $moduleKey, 1]);
		if(!defined($module->{'requiresRefresh'}) || $module->{'requiresRefresh'}) {
			refreshData();
		}
	}

	if(defined($module) && defined($module->{'id'})) {
		if(defined($module->{'scanInit'})) {
			no strict 'refs';
			$log->debug("Calling: scanInit on $moduleKey\n");
			eval { &{$module->{'scanInit'}}(); };
			if ($@) {
				$log->error("CustomScan: Failed to call scanInit on module $moduleKey: $@\n");
				$scanningModulesInProgress{$moduleKey}=-1;
			}
			use strict 'refs';
		}
		my %scanningContext = ();
		initArtistScan($moduleKey,\%scanningContext);
	}
	return;
}

sub moduleClear {
	my $moduleKey = shift;
	my $sqlErrors = '';
	if($scanningModulesInProgress{$moduleKey} == 1 || $scanningModulesInProgress{$moduleKey} == -1) {
		$log->warn("CustomScan: Scanning already in progress, wait until its finished\n");
		return "Scanning already in progress, wait until its finished";
	}
	$log->info("Performing module clear\n");
	if(!$modules) {
		$modules = getPluginModules();
	}
	my $module = $modules->{$moduleKey};
	my $timeMeasure = Time::Stopwatch->new();
	if(defined($module) && defined($module->{'id'})) {
		eval {
			$timeMeasure->clear();
			$timeMeasure->start();
			$log->info("Deleting artist data...\n");
			my $dbh = getCurrentDBH();
			my $limit = "";
			if($driver eq 'mysql') {
				$limit = " limit 1000";
			}
			my $sth = $dbh->prepare("DELETE FROM customscan_contributor_attributes where module=?".$limit);
			$sth->bind_param(1,$module->{'id'},SQL_VARCHAR);
			my $count = 1;
			while (defined($count)) {
				$count = $sth->execute();
				if($count eq '0E0') {
					$count = undef;
				}
				main::idleStreams();
				$log->info("Clearing contributor data...\n");
			}
			commit($dbh);
			$sth->finish();
			$log->info("Deleted artist data after ".$timeMeasure->getElapsedTime()." seconds\n");
			$timeMeasure->stop();

			$timeMeasure->clear();
			$timeMeasure->start();
			$log->info("Deleting album data...\n");
			$sth = $dbh->prepare("DELETE FROM customscan_album_attributes where module=?".$limit);
			$sth->bind_param(1,$module->{'id'},SQL_VARCHAR);
			my $count = 1;
			while (defined($count)) {
				$count = $sth->execute();
				if($count eq '0E0') {
					$count = undef;
				}
				main::idleStreams();
				$log->info("Clearing album data...\n");
			}
			commit($dbh);
			$sth->finish();
			$log->info("Deleted album data after ".$timeMeasure->getElapsedTime()." seconds\n");
			$timeMeasure->stop();

			my $clearWithDelete=1;
			eval {
				my $sth = $dbh->prepare("SELECT COUNT(id) FROM customscan_track_attributes where module=?");
				$sth->bind_param(1,$module->{'id'},SQL_VARCHAR);
				my $count = undef;
				$sth->execute();
				$sth->bind_col(1, \$count);
				if($sth->fetch()) {
					if($count>40000) {
						$clearWithDelete = 0;
					}
				}
				$sth->finish();
			};
			if( $@ ) {
			    $log->error("Database error: $DBI::errstr, $@\n");
			    $sqlErrors .= "Database error: $DBI::errstr, ";
		   	}
			$timeMeasure->clear();
			$timeMeasure->start();
			$log->info("Deleting track data...\n");
			if($clearWithDelete) {
				eval {
					$log->info("Clearing track data with delete\n");
					my $sth = $dbh->prepare("DELETE FROM customscan_track_attributes where module=?".$limit);
					$sth->bind_param(1,$module->{'id'},SQL_VARCHAR);
					my $count = 1;
					while (defined($count)) {
						$count = $sth->execute();
						if($count eq '0E0') {
							$count = undef;
						}
						main::idleStreams();
						$log->debug("Clearing track data...\n");
					}
					commit($dbh);
					$sth->finish();
				};
			}else {
				eval {
					$log->info("Clearing track data with drop\n");
					$log->debug("Clearing track data, dropping temporary tables...\n");
					my $sth = $dbh->prepare("DROP TABLE IF EXISTS customscan_track_attributes_old");
					$sth->execute();
					$sth->finish();
					commit($dbh);
					$log->debug("Clearing track data, renaming current table...\n");
					if($driver eq 'SQLite') {
						$sth = $dbh->prepare("CREATE TEMPORARY TABLE customscan_track_attributes_old as select * from customscan_track_attributes where module!=?");
					}else {
						$sth = $dbh->prepare("CREATE TEMPORARY TABLE customscan_track_attributes_old select * from customscan_track_attributes where module!=?");
					}
					$sth->bind_param(1,$module->{'id'},SQL_VARCHAR);
					$sth->execute();
					$sth->finish();
					$log->debug("Clearing track data, recreating empty table...\n");
					$sth = $dbh->prepare("DROP TABLE customscan_track_attributes");
					$sth->execute();
					$sth->finish();
					initDatabase();
					main::idleStreams();
					$log->debug("Clearing track data, inserting data in new table...\n");
					$sth = $dbh->prepare("INSERT INTO customscan_track_attributes select * from customscan_track_attributes_old");
					$sth->execute();
					$sth->finish();
					$log->debug("Clearing track data, dropping temporary table...\n");
					$sth = $dbh->prepare("DROP TABLE customscan_track_attributes_old");
					$sth->execute();
					$sth->finish();
					commit($dbh);
					main::idleStreams();
				};
			}
			if( $@ ) {
			    $log->error("Database error: $DBI::errstr\n");
			    $sqlErrors .= "Database error: $DBI::errstr, ";
			    eval {
			    	rollback($dbh); #just die if rollback is failing
			    };
		   	}else {
				$log->info("Deleted track data after ".$timeMeasure->getElapsedTime()." seconds\n");
				$timeMeasure->stop();
			}
		};
		if( $@ ) {
		    $log->error("Database error: $DBI::errstr\n$@\n");
		    $sqlErrors .= "Database error: $DBI::errstr, ";
		}
	}
	if($sqlErrors!='') {
		return $sqlErrors;
	}else {
		return;
	}
}

sub fullAbort {
	if(scalar(grep (/1/,values %scanningModulesInProgress))>0) {
		$scanningAborted = 1;
		$log->warn("CustomScan: Aborting scanning...\n");
		return;
	}
}

sub isScanning {
	my $module = shift;

	if(!defined($module)) {
		if(scalar(grep (/1/,values %scanningModulesInProgress))>0) {
			return 1;
		}
	}elsif(exists $scanningModulesInProgress{$module}) {
		if($scanningModulesInProgress{$module} == 1 || $scanningModulesInProgress{$module} == -1) {
			return 1;
		}
	}
	return 0;
}

sub fullClear {
	if(scalar(grep (/1/,values %scanningModulesInProgress))>0) {
		$log->warn("CustomScan: Scanning already in progress, wait until its finished\n");
		return "Scanning already in progress, wait until its finished";
	}
	$log->info("Performing full clear\n");
	eval {
		my $dbh = getCurrentDBH();
		my $sth = $dbh->prepare("DROP table customscan_contributor_attributes");
		$sth->execute();
		commit($dbh);
		$sth->finish();

		$sth = $dbh->prepare("DROP table customscan_album_attributes");
		$sth->execute();
		commit($dbh);
		$sth->finish();

		$sth = $dbh->prepare("DROP table customscan_track_attributes");
		$sth->execute();
		commit($dbh);
		$sth->finish();
	};
	if( $@ ) {
	    $log->error("Database error: $DBI::errstr\n$@\n");
	    return "An error occured $DBI::errstr";
	}
	initDatabase();
	return;
}

sub exitScan {
	my $moduleKey = shift;
	my $scanningContext = shift;

	my @moduleKeys = ();
	if(defined($moduleKey)) {
		push @moduleKeys,$moduleKey;
	}else {
		my $array = getSortedModuleKeys();
		push @moduleKeys,@$array;
	}
	my $analyzeTracks = 0;
	my $analyzeAlbums = 0;
	my $analyzeArtists = 0;
	for my $key (@moduleKeys) {
		my $module = $modules->{$key};
		if(defined($module->{'scanTrack'}) || defined($module->{'initScanTrack'}) || defined($module->{'exitScanTrack'})) {
			$analyzeTracks = 1;
		}
		if(defined($module->{'scanAlbum'}) || defined($module->{'initScanAlbum'}) || defined($module->{'exitScanAlbum'})) {
			$analyzeAlbums = 1;
		}
		if(defined($module->{'scanArtist'}) || defined($module->{'initScanArtist'}) || defined($module->{'exitScanArtist'})) {
			$analyzeArtists = 1;
		}
		if(defined($module->{'scanExit'})) {
			no strict 'refs';
			$log->debug("Calling: scanExit on $key\n");
			eval { &{$module->{'scanExit'}}(); };
			if ($@) {
				$log->error("CustomScan: Failed to call scanExit on module $key: $@\n");
				$scanningModulesInProgress{$key}=-1;
			}
			use strict 'refs';
		}
		if($scanningModulesInProgress{$key} == 1) {
			$scanningModulesInProgress{$key}=0;
			Slim::Control::Request::notifyFromArray(undef, ['customscan', 'changedstatus', $key, 0]);
		}elsif($scanningModulesInProgress{$key} == -1) {
			$scanningModulesInProgress{$key}=-2;
			Slim::Control::Request::notifyFromArray(undef, ['customscan', 'changedstatus', $key, -2]);
		}
	}
	$log->info("Optimizing SQLite database");
	my $dbh = getCurrentDBH();
	if($driver eq 'SQLite') {
		if($analyzeTracks) {
			$dbh->do("ANALYZE customscan_track_attributes");
		}
		if($analyzeAlbums) {
			$dbh->do("ANALYZE customscan_album_attributes");
		}
		if($analyzeArtists) {
			$dbh->do("ANALYZE customscan_contributor_attributes");
		}
	}else {
		if($analyzeTracks) {
			$dbh->do("ANALYZE table customscan_track_attributes");
		}
		if($analyzeAlbums) {
			$dbh->do("ANALYZE table customscan_album_attributes");
		}
		if($analyzeArtists) {
			$dbh->do("ANALYZE table customscan_contributor_attributes");
		}
	}
	commit($dbh);
	if(!isScanning(undef)) {
		$scanningAborted = 0;
	}
	$log->info("Rescan finished".($moduleKey?" of $moduleKey":"")."\n");
}

sub initArtistScan {
	my $moduleKey = shift;
	my $scanningContext = shift;

	my $dbh = getCurrentDBH();
	my @moduleKeys = ();
	if(defined($moduleKey)) {
		push @moduleKeys,$moduleKey;
	}else {
		my $array = getSortedModuleKeys();
		push @moduleKeys,@$array;
	}
	my $needToScanArtists = 0;
	for my $key (@moduleKeys) {
		my $module = $modules->{$key};
		my $moduleId = $key;
		my $moduleId = $module->{'id'};
		if((defined($module->{'scanArtist'}) || defined($module->{'initScanArtist'}) || defined($module->{'exitScanArtist'})) && defined($module->{'alwaysRescanArtist'}) && $module->{'alwaysRescanArtist'}) {
			my $timeMeasure = Time::Stopwatch->new();
			$timeMeasure->clear();
			$timeMeasure->start();
			$log->info("Clearing artist data for ".$moduleId."\n");
			my $limit = "";
			if($driver eq 'mysql') {
				$limit = " limit 1000";
			}
			eval {
				my $sth = $dbh->prepare("DELETE FROM customscan_contributor_attributes where module=".$dbh->quote($moduleId).$limit);
				my $count = 1;
				while (defined($count)) {
					$count = $sth->execute();
					if($count eq '0E0') {
						$count = undef;
					}
					$log->debug("Clearing artist data...\n");
					main::idleStreams();
				}
				commit($dbh);
				$sth->finish();
			};
			if( $@ ) {
			    $log->error("Database error: $DBI::errstr\n$@\n");
			    eval {
			    	rollback($dbh); #just die if rollback is failing
			    };
		   	}else {
				$log->info("Deleted artist data after ".$timeMeasure->getElapsedTime()." seconds\n");
			}
			$timeMeasure->stop();
		}
		if(defined($module->{'scanArtist'})) {
			$needToScanArtists = 1;
		}
	}
	if($needToScanArtists) {
		my @joins = ();
		push @joins, 'contributorTracks';
		$scanningContext->{'noOfArtists'} = Slim::Schema->resultset('Contributor')->search(
			{'contributorTracks.role' => {'in' => [1,5]}},
			{
				'group_by' => 'me.id',
				'join' => \@joins
			}
		)->count;
		$scanningContext->{'currentArtistNo'} = 0;
		$log->info("Got ".$scanningContext->{'noOfArtists'}." artists");
	}
	my %context = ();
	Slim::Utils::Scheduler::add_task(\&initScanArtist,$moduleKey,\@moduleKeys,\%context,$scanningContext);
}

sub initScanArtist {
	my $moduleKey = shift;
	my $moduleKeys = shift;
	my $context = shift;
	my $scanningContext = shift;

	my $key = undef;
	if(ref($moduleKeys) eq 'ARRAY') {
		$key = shift @$moduleKeys;
	}

	my $result = undef;
	if(defined($key)) {
		my $module = $modules->{$key};
		if(defined($module->{'initScanArtist'})) {
			no strict 'refs';
			$log->debug("Calling: ".$key."::initScanArtist\n");
			eval { $result = &{$module->{'initScanArtist'}}($context); };
			if ($@) {
				$log->error("CustomScan: Failed to call initScanArtist on module $key: $@\n");
				$scanningModulesInProgress{$key}=-1;
			}
			use strict 'refs';
		}
	}
	if(defined($result)) {
		unshift @$moduleKeys,$key;
		return 1;
	}elsif(scalar(@$moduleKeys)>0) {
		return 1;
	}else {
		Slim::Utils::Scheduler::add_task(\&scanArtist,$moduleKey,$scanningContext);
		return 0;
	}
}
sub getSortedModuleKeys {
	my @moduleArray = ();
	for my $key (keys %$modules) {
		if($modules->{$key}->{'enabled'} && $modules->{$key}->{'active'} && (!defined($modules->{$key}->{'licensed'}) || $modules->{$key}->{'licensed'})) {
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
	my $scanningContext = shift;

	my $dbh = getCurrentDBH();
	my @moduleKeys = ();
	if(defined($moduleKey)) {
		push @moduleKeys,$moduleKey;
	}else {
		my $array = getSortedModuleKeys();
		push @moduleKeys,@$array;
	}
	my $needToScanAlbums = 0;
	for my $key (@moduleKeys) {
		my $module = $modules->{$key};
		my $moduleId = $module->{'id'};
		if((defined($module->{'scanAlbum'}) || defined($module->{'initScanAlbum'}) || defined($module->{'exitScanAlbum'})) && defined($module->{'alwaysRescanAlbum'}) && $module->{'alwaysRescanAlbum'}) {
			my $timeMeasure = Time::Stopwatch->new();
			$timeMeasure->clear();
			$timeMeasure->start();
			$log->info("Clearing album data for ".$moduleId."\n");
			my $limit = "";
			if($driver eq 'mysql') {
				$limit = " limit 1000";
			}
			eval {
				my $sth = $dbh->prepare("DELETE FROM customscan_album_attributes where module=".$dbh->quote($moduleId).$limit);
				my $count = 1;
				while (defined($count)) {
					$count = $sth->execute();
					if($count eq '0E0') {
						$count = undef;
					}
					main::idleStreams();
					$log->debug("Clearing album data...\n");
				}
				commit($dbh);
				$sth->finish();
			};
			if( $@ ) {
			    $log->error("Database error: $DBI::errstr\n");
			    eval {
			    	rollback($dbh); #just die if rollback is failing
			    };
		   	}else {
				$log->info("Deleted album data after ".$timeMeasure->getElapsedTime()." seconds\n");
			}
			$timeMeasure->stop();
		}
		if(defined($module->{'initScanAlbum'})) {
			no strict 'refs';
			$log->debug("Calling: ".$key."::initScanAlbum\n");
			eval { &{$module->{'initScanAlbum'}}(); };
			if ($@) {
				$log->error("CustomScan: Failed to call initScanAlbum on module $key: $@\n");
				$scanningModulesInProgress{$key}=-1;
			}
			use strict 'refs';
		}
		if(defined($module->{'scanAlbum'})) {
			$needToScanAlbums = 1;
		}
	}
	if($needToScanAlbums) {
		$scanningContext->{'noOfAlbums'} = Slim::Schema->resultset('Album')->count;
		$scanningContext->{'currentAlbumNo'} = 0;
		$log->info("Got ".$scanningContext->{'noOfAlbums'}." albums");
	}
	my %context = ();
	Slim::Utils::Scheduler::add_task(\&initScanAlbum,$moduleKey,\@moduleKeys,\%context,$scanningContext);
}

sub initScanAlbum {
	my $moduleKey = shift;
	my $moduleKeys = shift;
	my $context = shift;
	my $scanningContext = shift;

	my $key = undef;
	if(ref($moduleKeys) eq 'ARRAY') {
		$key = shift @$moduleKeys;
	}

	my $result = undef;
	if(defined($key)) {
		my $module = $modules->{$key};
		if(defined($module->{'initScanAlbum'})) {
			no strict 'refs';
			$log->debug("Calling: ".$key."::initScanAlbum\n");
			eval { $result = &{$module->{'initScanAlbum'}}($context); };
			if ($@) {
				$log->error("CustomScan: Failed to call initScanAlbum on module $key: $@\n");
				$scanningModulesInProgress{$key}=-1;
			}
			use strict 'refs';
		}
	}
	if(defined($result)) {
		unshift @$moduleKeys,$key;
		return 1;
	}elsif(scalar(@$moduleKeys)>0) {
		return 1;
	}else {
		Slim::Utils::Scheduler::add_task(\&scanAlbum,$moduleKey,$scanningContext);
		return 0;
	}
}

sub initTrackScan {
	my $moduleKey = shift;
	my $scanningContext = shift;

	my $dbh = getCurrentDBH();
	my @moduleKeys = ();
	if(defined($moduleKey)) {
		push @moduleKeys,$moduleKey;
	}else {
		my $array = getSortedModuleKeys();
		push @moduleKeys,@$array;
	}
	my $needToScanTracks = 0;
	for my $key (@moduleKeys) {
		my $module = $modules->{$key};
		my $moduleId = $module->{'id'};
		if((defined($module->{'scanTrack'}) || defined($module->{'initScanTrack'}) || defined($module->{'exitScanTrack'})) && defined($module->{'alwaysRescanTrack'}) && $module->{'alwaysRescanTrack'}) {
			my $timeMeasure = Time::Stopwatch->new();
			$timeMeasure->clear();
			$timeMeasure->start();
			$log->info("Clearing track data for ".$moduleId."\n");
			my $clearWithDelete=1;
			eval {
				my $sth = $dbh->prepare("SELECT COUNT(id) FROM customscan_track_attributes where module=".$dbh->quote($moduleId));
				my $count = undef;
				$sth->execute();
				$sth->bind_col(1, \$count);
				if($sth->fetch()) {
					if($count>40000) {
						$clearWithDelete = 0;
					}
				}
				$sth->finish();
			};
			if( $@ ) {
			    $log->error("Database error: $DBI::errstr, $@\n");
		   	}
			if($clearWithDelete) {
				$log->info("Start clearing track data with delete\n");
				my $limit = "";
				if($driver eq 'mysql') {
					$limit = " limit 1000";
				}
				eval {
					my $sth = $dbh->prepare("DELETE FROM customscan_track_attributes where module=".$dbh->quote($moduleId).$limit);
					my $count = 1;
					while (defined($count)) {
						$count = $sth->execute();
						if($count eq '0E0') {
							$count = undef;
						}
						main::idleStreams();
						$log->debug("Clearing track data...(Elasped time: ".$timeMeasure->getElapsedTime()." seconds)\n");
					}
					commit($dbh);
					$sth->finish();
				};
			}else {
				$log->info("Start clearing track data with drop\n");
				eval {
					$log->debug("Clearing track data, dropping temporary tables...\n");
					my $sth = $dbh->prepare("DROP TABLE IF EXISTS customscan_track_attributes_old");
					$sth->execute();
					$sth->finish();
					commit($dbh);
					$log->debug("Clearing track data, renaming current table...\n");
					if($driver eq 'SQLite') {
						$sth = $dbh->prepare("CREATE TEMPORARY TABLE customscan_track_attributes_old as select * from customscan_track_attributes where module!=?");
					}else {
						$sth = $dbh->prepare("CREATE TEMPORARY TABLE customscan_track_attributes_old select * from customscan_track_attributes where module!=?");
					}
					$sth->bind_param(1,$moduleId,SQL_VARCHAR);
					$sth->execute();
					$sth->finish();
					$log->debug("Clearing track data, recreating empty table...\n");
					$sth = $dbh->prepare("DROP TABLE customscan_track_attributes");
					$sth->execute();
					$sth->finish();
					initDatabase();
					main::idleStreams();
					$log->debug("Clearing track data, inserting data in new table...\n");
					$sth = $dbh->prepare("INSERT INTO customscan_track_attributes select * from customscan_track_attributes_old");
					$sth->execute();
					$sth->finish();
					$log->debug("Clearing track data, dropping temporary table...\n");
					$sth = $dbh->prepare("DROP TABLE customscan_track_attributes_old");
					$sth->execute();
					$sth->finish();
					commit($dbh);
					main::idleStreams();
				};
			}
			if( $@ ) {
			    $log->error("Database error: $DBI::errstr\n");
			    eval {
			    	rollback($dbh); #just die if rollback is failing
			    };
		   	}else {
				$log->info("Deleted track data after ".$timeMeasure->getElapsedTime()." seconds\n");
			}
		}
		if(defined($module->{'scanTrack'})) {
			$needToScanTracks = 1;
		}
	}
	if($needToScanTracks) {
		$scanningContext->{'noOfTracks'} = Slim::Schema->resultset('Track')->count;
		$scanningContext->{'currentTrackNo'} = 0;
		$log->info("Got ".$scanningContext->{'noOfTracks'}." tracks");
	}
	my %context = ();
	Slim::Utils::Scheduler::add_task(\&initScanTrack,$moduleKey,\@moduleKeys,\%context,$scanningContext);
}

sub initScanTrack {
	my $moduleKey = shift;
	my $moduleKeys = shift;
	my $context = shift;
	my $scanningContext = shift;

	my $key = undef;
	if(ref($moduleKeys) eq 'ARRAY') {
		$key = shift @$moduleKeys;
	}

	my $result = undef;
	if(defined($key)) {
		my $module = $modules->{$key};
		if(defined($module->{'initScanTrack'})) {
			no strict 'refs';
			$log->debug("Calling: ".$key."::initScanTrack\n");
			eval { $result = &{$module->{'initScanTrack'}}($context); };
			if ($@) {
				$log->error("CustomScan: Failed to call initScanTrack on module $key: $@\n");
				$scanningModulesInProgress{$key}=-1;
			}
			use strict 'refs';
		}
	}
	if(defined($result)) {
		unshift @$moduleKeys,$key;
		if(!$scanningAborted) {
			return 1;
		}
	}elsif(scalar(@$moduleKeys)>0 && !$scanningAborted) {
		return 1;
	}

	Slim::Utils::Scheduler::add_task(\&scanTrack,$moduleKey,$scanningContext);
	return 0;
}

sub scanArtist {
	my $moduleKey = shift;
	my $scanningContext = shift;

	my $artist = undef;
	if(defined($scanningContext->{'currentArtistNo'})) {
		my @joins = ();
		push @joins, 'contributorTracks';
		$artist = Slim::Schema->resultset('Contributor')->search(
			{'contributorTracks.role' => {'in' => [1,5]}},
			{
				'group_by' => 'me.id',
				'join' => \@joins
			}
		)->slice($scanningContext->{'currentArtistNo'},$scanningContext->{'currentArtistNo'})->single;
		$scanningContext->{'currentArtistNo'}++;
		if(defined($artist) && $artist->id eq Slim::Schema->variousArtistsObject->id) {
			$log->debug("CustomScan: Skipping artist ".$artist->name."\n");
			$artist = Slim::Schema->resultset('Contributor')->search(
				{'contributorTracks.role' => {'in' => [1,5]}},
				{
					'group_by' => 'me.id',
					'join' => \@joins
				}
			)->slice($scanningContext->{'currentArtistNo'},$scanningContext->{'currentArtistNo'})->single;
			$scanningContext->{'currentArtistNo'}++;
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
		$log->debug("Scanning artist ".$scanningContext->{'currentArtistNo'}." of ".$scanningContext->{'noOfArtists'});
		$log->debug("Scanning artist: ".$artist->name);
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
					$log->debug("Calling: ".$key."::scanArtist\n");
					my $attributes = eval { &{$module->{'scanArtist'}}($artist); };
					if ($@) {
						$log->error("CustomScan: Failed to call scanArtist on module $key: $@\n");
						$scanningModulesInProgress{$key}=-1;
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
								if(defined($attribute->{'valuesort'})) {
									$attribute->{'valuesort'} = Slim::Utils::Text::ignoreCaseArticles($attribute->{'valuesort'});
								}elsif(defined($attribute->{'value'})) {
									$attribute->{'valuesort'} = Slim::Utils::Text::ignoreCaseArticles($attribute->{'value'});
								}
								$sth->bind_param(7, $attribute->{'valuesort'} , SQL_VARCHAR);
								$sth->bind_param(8, $attribute->{'extravalue'} , SQL_VARCHAR);
								$sth->bind_param(9, $attribute->{'valuetype'} , SQL_VARCHAR);
								$sth->execute();
								commit($dbh);
							};
							if( $@ ) {
							    $log->error("Database error: $DBI::errstr\n");
							    eval {
							    	rollback($dbh); #just die if rollback is failing
							    };
							    $log->warn("Error values: ".$artist->id.", ".$artist->name.", ".$artist->musicbrainz_id.", ".$moduleId.", ".$attribute->{'name'}.", ".$attribute->{'value'}.", ".$attribute->{'valuesort'}.", ".$attribute->{'extravalue'}.", ".$attribute->{'valuetype'}."\n");
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
	my %context = ();
	Slim::Utils::Scheduler::add_task(\&exitScanArtist,$moduleKey,\@moduleKeys,\%context,$scanningContext);
	return 0;
}

sub exitScanArtist {
	my $moduleKey = shift;
	my $moduleKeys = shift;
	my $context = shift;
	my $scanningContext = shift;

	my $key = undef;
	if(ref($moduleKeys) eq 'ARRAY') {
		$key = shift @$moduleKeys;
	}
	my $result = undef;
	if(defined($key)) {
		my $module = $modules->{$key};
		if(defined($module->{'exitScanArtist'})) {
			no strict 'refs';
			$log->debug("Calling: ".$key."::exitScanArtist\n");
			eval { $result = &{$module->{'exitScanArtist'}}($context); };
			if ($@) {
				$log->error("CustomScan: Failed to call exitScanArtist on module $key: $@\n");
				$scanningModulesInProgress{$key}=-1;
			}
			use strict 'refs';
		}
	}
	if(defined($result)) {
		unshift @$moduleKeys,$key;
		return 1;
	}elsif(scalar(@$moduleKeys)>0) {
		return 1;
	}else {
		initAlbumScan($moduleKey,$scanningContext);
		return 0;
	}
}

sub scanAlbum {
	my $moduleKey = shift;
	my $scanningContext = shift;

	my $album = undef;
	if(defined($scanningContext->{'currentAlbumNo'})) {
		$album = Slim::Schema->resultset('Album')->slice($scanningContext->{'currentAlbumNo'},$scanningContext->{'currentAlbumNo'})->single;
		$scanningContext->{'currentAlbumNo'}++;
		while(defined($album) && (!$album->title || $album->title eq string('NO_ALBUM'))) {
			if($album->title) {
				$log->debug("CustomScan: Skipping album ".$album->title."\n");
			}else {
				$log->debug("CustomScan: Skipping album with no title\n");
			}
			$album = Slim::Schema->resultset('Album')->slice($scanningContext->{'currentAlbumNo'},$scanningContext->{'currentAlbumNo'})->single;
			$scanningContext->{'currentAlbumNo'}++;
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
		$log->debug("Scanning albums ".$scanningContext->{'currentAlbumNo'}." of ".$scanningContext->{'noOfAlbums'});
		$log->debug("Scanning album: ".$album->title);
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
					$log->debug("Calling: ".$key."::scanAlbum\n");
					my $attributes = eval { &{$module->{'scanAlbum'}}($album); };
					if ($@) {
						$log->error("CustomScan: Failed to call scanAlbum on module $key: $@\n");
						$scanningModulesInProgress{$key}=-1;
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
								if(defined($attribute->{'valuesort'})) {
									$attribute->{'valuesort'} = Slim::Utils::Text::ignoreCaseArticles($attribute->{'valuesort'});
								}elsif(defined($attribute->{'value'})) {
									$attribute->{'valuesort'} = Slim::Utils::Text::ignoreCaseArticles($attribute->{'value'});
								}
								$sth->bind_param(7, $attribute->{'valuesort'} , SQL_VARCHAR);
								$sth->bind_param(8, $attribute->{'extravalue'} , SQL_VARCHAR);
								$sth->bind_param(9, $attribute->{'valuetype'} , SQL_VARCHAR);
								$sth->execute();
								commit($dbh);
							};
							if( $@ ) {
							    $log->error("Database error: $DBI::errstr\n");
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
	my %context = ();
	Slim::Utils::Scheduler::add_task(\&exitScanAlbum,$moduleKey,\@moduleKeys,\%context,$scanningContext);
	return 0;
}

sub exitScanAlbum {
	my $moduleKey = shift;
	my $moduleKeys = shift;
	my $context = shift;
	my $scanningContext = shift;

	my $key = undef;
	if(ref($moduleKeys) eq 'ARRAY') {
		$key = shift @$moduleKeys;
	}
	my $result = undef;
	if(defined($key)) {
		my $module = $modules->{$key};
		if(defined($module->{'exitScanAlbum'})) {
			no strict 'refs';
			$log->debug("Calling: ".$key."::exitScanAlbum\n");
			eval { $result = &{$module->{'exitScanAlbum'}}($context); };
			if ($@) {
				$log->error("CustomScan: Failed to call exitScanAlbum on module $key: $@\n");
				$scanningModulesInProgress{$key}=-1;
			}
			use strict 'refs';
		}
	}
	if(defined($result)) {
		unshift @$moduleKeys,$key;
		return 1;
	}elsif(scalar(@$moduleKeys)>0) {
		return 1;
	}else {
		initTrackScan($moduleKey,$scanningContext);
		return 0;
	}
}

sub scanTrack {
	my $moduleKey = shift;
	my $scanningContext = shift;

	my $track = undef;
	if(defined($scanningContext->{'currentTrackNo'})) {
		$track = Slim::Schema->resultset('Track')->slice($scanningContext->{'currentTrackNo'},$scanningContext->{'currentTrackNo'})->single;
		$scanningContext->{'currentTrackNo'}++;
		my $maxCharacters = ($useLongUrls?511:255);
		# Skip non audio tracks and tracks with url longer than max number of characters
		while(defined($track) && (!$track->audio || ($driver eq 'mysql' && length($track->url)>$maxCharacters))) {
			$track = Slim::Schema->resultset('Track')->slice($scanningContext->{'currentTrackNo'},$scanningContext->{'currentTrackNo'})->single;
			$scanningContext->{'currentTrackNo'}++;
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
		$log->debug("Scanning track ".$scanningContext->{'currentTrackNo'}." of ".$scanningContext->{'noOfTracks'});
		$log->debug("Scanning track: ".$track->title);
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
					$log->debug("Calling: ".$key."::scanTrack\n");
					my $attributes = eval { &{$module->{'scanTrack'}}($track); };
					if ($@) {
						$log->error("CustomScan: Failed to call scanTrack on module $key: $@\n");
						$scanningModulesInProgress{$key}=-1;
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
								if(defined($attribute->{'valuesort'})) {
									$attribute->{'valuesort'} = Slim::Utils::Text::ignoreCaseArticles($attribute->{'valuesort'});
								}elsif(defined($attribute->{'value'})) {
									$attribute->{'valuesort'} = Slim::Utils::Text::ignoreCaseArticles($attribute->{'value'});
								}
								$sth->bind_param(7, $attribute->{'valuesort'} , SQL_VARCHAR);
								$sth->bind_param(8, $attribute->{'extravalue'} , SQL_VARCHAR);
								$sth->bind_param(9, $attribute->{'valuetype'} , SQL_VARCHAR);
								$sth->execute();
								commit($dbh);
							};
							if( $@ ) {
							    $log->error("Database error: $DBI::errstr\n");
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
	my %context = ();
	Slim::Utils::Scheduler::add_task(\&exitScanTrack,$moduleKey,\@moduleKeys,\%context,$scanningContext);
	return 0;
}

sub exitScanTrack {
	my $moduleKey = shift;
	my $moduleKeys = shift;
	my $context = shift;
	my $scanningContext = shift;

	my $key = undef;
	if(ref($moduleKeys) eq 'ARRAY') {
		$key = shift @$moduleKeys;
	}
	my $result = undef;
	if(defined($key)) {
		my $module = $modules->{$key};
		if(defined($module->{'exitScanTrack'})) {
			no strict 'refs';
			$log->debug("Calling: ".$key."::exitScanTrack\n");
			eval { $result = &{$module->{'exitScanTrack'}}($context); };
			if ($@) {
				$log->error("CustomScan: Failed to call exitScanTrack on module $key: $@\n");
				$scanningModulesInProgress{$key}=-1;
			}
			use strict 'refs';
		}
	}
	if(defined($result)) {
		unshift @$moduleKeys,$key;
		if(!$scanningAborted) {
			return 1;
		}
	}elsif(scalar(@$moduleKeys)>0 && !$scanningAborted) {
		return 1;
	}

	exitScan($moduleKey,$scanningContext);
	return 0;
}

sub refreshData 
{
	my $dbh = getCurrentDBH();
	my $sth;
	my $sthupdate;
	my $sql;
	my $sqlupdate;
	my $count;
	my $timeMeasure = Time::Stopwatch->new();
	$timeMeasure->clear();

	my $performRefresh = 0;
	if(!$modules) {
		$modules = getPluginModules();
	}
	for my $moduleKey (keys %$modules) {
		my $module = $modules->{$moduleKey};
		if(defined($module) && defined($module->{'id'}) && $module->{'active'} && (!defined($module->{'licensed'}) || $module->{'licensed'})) {
			if(!defined($module->{'requiresRefresh'}) || $module->{'requiresRefresh'}) {
				$log->info("Refresh triggered by module: ".$module->{'name'});				
				$performRefresh=1;
				last;
			}
		}
	}
	if(!$performRefresh) {
		$log->info("CustomScan: No refresh needed\n");
		return;
	}

	$log->warn("CustomScan: Synchronizing Custom Scan data, please wait...\n");
	$timeMeasure->start();
	$log->info("Starting to update musicbrainz id's in custom scan artist data based on names\n");
	# Now lets set all musicbrainz id's not already set
	if($driver eq 'mysql') {
		$sql = "UPDATE contributors,customscan_contributor_attributes SET customscan_contributor_attributes.musicbrainz_id=contributors.musicbrainz_id where contributors.name=customscan_contributor_attributes.name and contributors.musicbrainz_id like '%-%' and customscan_contributor_attributes.musicbrainz_id is null";
	}else {
		$sql = "UPDATE customscan_contributor_attributes SET musicbrainz_id=(select contributors.musicbrainz_id from contributors where contributors.name=customscan_contributor_attributes.name and contributors.musicbrainz_id like '%-%' and customscan_contributor_attributes.musicbrainz_id is null) where exists (select contributors.musicbrainz_id from contributors where contributors.name=customscan_contributor_attributes.name and contributors.musicbrainz_id like '%-%' and customscan_contributor_attributes.musicbrainz_id is null)";
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
	    $log->error("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}

	$sth->finish();
	$log->info("Finished updating musicbrainz id's in custom scan artist data based on names, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	main::idleStreams();
	$timeMeasure->stop();
	$timeMeasure->clear();

	$timeMeasure->start();
	$log->info("Starting to update custom scan artist data based on musicbrainz ids\n");
	# First lets refresh all urls with musicbrainz id's
	if($driver eq 'mysql') {
		$sql = "UPDATE contributors,customscan_contributor_attributes SET customscan_contributor_attributes.name=contributors.name, customscan_contributor_attributes.contributor=contributors.id where contributors.musicbrainz_id is not null and contributors.musicbrainz_id=customscan_contributor_attributes.musicbrainz_id and (customscan_contributor_attributes.name!=contributors.name or customscan_contributor_attributes.contributor!=contributors.id)";
	}else {
		$sql = "UPDATE customscan_contributor_attributes SET name=(select contributors.name from contributors where contributors.musicbrainz_id is not null and contributors.musicbrainz_id=customscan_contributor_attributes.musicbrainz_id and (customscan_contributor_attributes.name!=contributors.name or customscan_contributor_attributes.contributor!=contributors.id)), contributor=(select contributors.id from contributors where contributors.musicbrainz_id is not null and contributors.musicbrainz_id=customscan_contributor_attributes.musicbrainz_id and (customscan_contributor_attributes.name!=contributors.name or customscan_contributor_attributes.contributor!=contributors.id)) where exists (select contributors.name from contributors where contributors.musicbrainz_id is not null and contributors.musicbrainz_id=customscan_contributor_attributes.musicbrainz_id and (customscan_contributor_attributes.name!=contributors.name or customscan_contributor_attributes.contributor!=contributors.id))";
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
	    $log->error("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}
	$sth->finish();
	$log->info("Finished updating custom scan artist data based on musicbrainz ids, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	main::idleStreams();
	$timeMeasure->stop();

	$timeMeasure->clear();

	$timeMeasure->start();
	$log->info("Starting to update custom scan artist data based on names\n");
	# First lets refresh all urls with musicbrainz id's
	if($driver eq 'mysql') {
		$sql = "UPDATE contributors,customscan_contributor_attributes SET customscan_contributor_attributes.contributor=contributors.id where customscan_contributor_attributes.musicbrainz_id is null and contributors.name=customscan_contributor_attributes.name and customscan_contributor_attributes.contributor!=contributors.id";
	}else {
		$sql = "UPDATE customscan_contributor_attributes SET contributor=(select contributors.id from contributors where customscan_contributor_attributes.musicbrainz_id is null and contributors.name=customscan_contributor_attributes.name and customscan_contributor_attributes.contributor!=contributors.id) where exists (select contributors.id from contributors where customscan_contributor_attributes.musicbrainz_id is null and contributors.name=customscan_contributor_attributes.name and customscan_contributor_attributes.contributor!=contributors.id)";
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
	    $log->error("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}
	$sth->finish();
	$log->info("Finished updating custom scan artist data based on names, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	main::idleStreams();
	$timeMeasure->stop();

	$timeMeasure->clear();

	$timeMeasure->start();
	$log->info("Starting to update musicbrainz id's in custom scan album data based on titles\n");
	# Now lets set all musicbrainz id's not already set
	if($driver eq 'mysql') {
		$sql = "UPDATE albums,customscan_album_attributes SET customscan_album_attributes.musicbrainz_id=albums.musicbrainz_id where albums.title=customscan_album_attributes.title and albums.musicbrainz_id like '%-%' and customscan_album_attributes.musicbrainz_id is null";
	}else {
		$sql = "UPDATE customscan_album_attributes SET musicbrainz_id=(select albums.musicbrainz_id from albums where albums.title=customscan_album_attributes.title and albums.musicbrainz_id like '%-%' and customscan_album_attributes.musicbrainz_id is null) where exists (select albums.musicbrainz_id from albums where albums.title=customscan_album_attributes.title and albums.musicbrainz_id like '%-%' and customscan_album_attributes.musicbrainz_id is null)";
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
	    $log->error("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}

	$sth->finish();
	$log->info("Finished updating musicbrainz id's in custom scan album data based on titles, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	main::idleStreams();
	$timeMeasure->stop();
	$timeMeasure->clear();

	$timeMeasure->start();
	$log->info("Starting to update custom scan album data based on musicbrainz ids\n");
	# First lets refresh all urls with musicbrainz id's
	if($driver eq 'mysql') {
		$sql = "UPDATE albums,customscan_album_attributes SET customscan_album_attributes.title=albums.title, customscan_album_attributes.album=albums.id where albums.musicbrainz_id is not null and albums.musicbrainz_id=customscan_album_attributes.musicbrainz_id and (customscan_album_attributes.title!=albums.title or customscan_album_attributes.album!=albums.id)";
	}else {
		$sql = "UPDATE customscan_album_attributes SET title=(select albums.title from albums where albums.musicbrainz_id is not null and albums.musicbrainz_id=customscan_album_attributes.musicbrainz_id and (customscan_album_attributes.title!=albums.title or customscan_album_attributes.album!=albums.id)), album=(select albums.id from albums where albums.musicbrainz_id is not null and albums.musicbrainz_id=customscan_album_attributes.musicbrainz_id and (customscan_album_attributes.title!=albums.title or customscan_album_attributes.album!=albums.id)) where exists (select albums.title from albums where albums.musicbrainz_id is not null and albums.musicbrainz_id=customscan_album_attributes.musicbrainz_id and (customscan_album_attributes.title!=albums.title or customscan_album_attributes.album!=albums.id))";
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
	    $log->error("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}
	$sth->finish();
	$log->info("Finished updating custom scan album data based on musicbrainz ids, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	main::idleStreams();
	$timeMeasure->stop();
	$timeMeasure->clear();

	$timeMeasure->start();
	$log->info("Starting to update custom scan album data based on titles\n");
	# First lets refresh all urls with musicbrainz id's
	if($driver eq 'mysql') {
		$sql = "UPDATE albums,customscan_album_attributes SET customscan_album_attributes.album=albums.id where customscan_album_attributes.musicbrainz_id is null and albums.title=customscan_album_attributes.title and customscan_album_attributes.album!=albums.id";
	}else {
		$sql = "UPDATE customscan_album_attributes SET album=(select albums.id from albums where customscan_album_attributes.musicbrainz_id is null and albums.title=customscan_album_attributes.title and customscan_album_attributes.album!=albums.id) where exists (select albums.id from albums where customscan_album_attributes.musicbrainz_id is null and albums.title=customscan_album_attributes.title and customscan_album_attributes.album!=albums.id)";
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
	    $log->error("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}
	$sth->finish();
	$log->info("Finished updating custom scan album data based on titles, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	main::idleStreams();
	$timeMeasure->stop();
	$timeMeasure->clear();

	$timeMeasure->start();
	$log->info("Starting to update musicbrainz id's in custom scan track data based on urls\n");
	# Now lets set all musicbrainz id's not already set
	if($driver eq 'mysql') {
		$sql = "UPDATE tracks,customscan_track_attributes SET customscan_track_attributes.musicbrainz_id=tracks.musicbrainz_id where tracks.url=customscan_track_attributes.url and tracks.musicbrainz_id like '%-%' and customscan_track_attributes.musicbrainz_id is null";
	}else {
		$sql = "UPDATE customscan_track_attributes SET musicbrainz_id=(select tracks.musicbrainz_id from tracks where tracks.url=customscan_track_attributes.url and tracks.musicbrainz_id like '%-%' and customscan_track_attributes.musicbrainz_id is null) where exists (select tracks.musicbrainz_id from tracks where tracks.url=customscan_track_attributes.url and tracks.musicbrainz_id like '%-%' and customscan_track_attributes.musicbrainz_id is null)";
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
	    $log->error("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}

	$sth->finish();
	$log->info("Finished updating musicbrainz id's in custom scan track data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	main::idleStreams();
	$timeMeasure->stop();
	$timeMeasure->clear();

	$timeMeasure->start();
	$log->info("Starting to update custom scan track data based on musicbrainz ids\n");
	# First lets refresh all urls with musicbrainz id's
	if($driver eq 'mysql') {
		$sql = "UPDATE tracks,customscan_track_attributes SET customscan_track_attributes.url=tracks.url, customscan_track_attributes.track=tracks.id where tracks.musicbrainz_id is not null and tracks.musicbrainz_id=customscan_track_attributes.musicbrainz_id and (customscan_track_attributes.url!=tracks.url or customscan_track_attributes.track!=tracks.id) and length(tracks.url)<512";
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
		    $log->error("Database error: $DBI::errstr\n");
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
	}else {
		$sql = "drop table if exists temp_customscan_track_attributes";
		$sth = $dbh->prepare( $sql );
		eval {
			$sth->execute();
			commit($dbh);
		};
		if( $@ ) {
		    $log->error("Database error: $DBI::errstr\n");
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}
		$sql = "create temp table temp_customscan_track_attributes as select tracks.id as id,tracks.url as url,tracks.musicbrainz_id as musicbrainz_id from tracks,customscan_track_attributes where customscan_track_attributes.musicbrainz_id is not null and customscan_track_attributes.musicbrainz_id=tracks.musicbrainz_id and (customscan_track_attributes.url!=tracks.url or customscan_track_attributes.track!=tracks.id)";
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
		    $log->error("Database error: $DBI::errstr\n");
		    eval {
		    	rollback($dbh); #just die if rollback is failing
		    };
		}else {
			$sql = "create index if not exists temp_musicbrainz_cstrackidx on temp_customscan_track_attributes (musicbrainz_id)";
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
			    $log->error("Database error: $DBI::errstr\n");
			    eval {
			    	rollback($dbh); #just die if rollback is failing
			    };
			}else {
				$sql = "UPDATE customscan_track_attributes SET url=(select url from temp_customscan_track_attributes where temp_customscan_track_attributes.musicbrainz_id=customscan_track_attributes.musicbrainz_id),track=(select id from temp_customscan_track_attributes where temp_customscan_track_attributes.musicbrainz_id=customscan_track_attributes.musicbrainz_id) where exists (select id from temp_customscan_track_attributes where temp_customscan_track_attributes.musicbrainz_id=customscan_track_attributes.musicbrainz_id)";
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
				    $log->error("Database error: $DBI::errstr\n");
				    eval {
				    	rollback($dbh); #just die if rollback is failing
				    };
				}
				$sql = "drop table temp_customscan_track_attributes";
				$sth = $dbh->prepare( $sql );
				eval {
					$sth->execute();
					commit($dbh);
				};
				if( $@ ) {
				    $log->error("Database error: $DBI::errstr\n");
				    eval {
				    	rollback($dbh); #just die if rollback is failing
				    };
				}
			}
		}
	}
	$sth->finish();
	$log->info("Finished updating custom scan track data based on musicbrainz ids, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	main::idleStreams();
	$timeMeasure->stop();
	$timeMeasure->clear();

	$timeMeasure->start();
	$log->info("Starting to update custom scan track data based on urls\n");
	# First lets refresh all urls with musicbrainz id's
	if($driver eq 'mysql') {
		$sql = "UPDATE customscan_track_attributes JOIN tracks on tracks.url=customscan_track_attributes.url and customscan_track_attributes.musicbrainz_id is null set customscan_track_attributes.track=tracks.id where customscan_track_attributes.track!=tracks.id";
	}else {
		$sql = "UPDATE customscan_track_attributes set track=(select tracks.id from tracks where customscan_track_attributes.track!=tracks.id and tracks.url=customscan_track_attributes.url and customscan_track_attributes.musicbrainz_id is null) where exists (select tracks.id from tracks where customscan_track_attributes.track!=tracks.id and tracks.url=customscan_track_attributes.url and customscan_track_attributes.musicbrainz_id is null)";
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
	    $log->error("Database error: $DBI::errstr\n");
	    eval {
	    	rollback($dbh); #just die if rollback is failing
	    };
	}
	$sth->finish();
	$log->info("Finished updating custom scan track data based on urls, updated $count items : It took ".$timeMeasure->getElapsedTime()." seconds\n");
	main::idleStreams();
	if($driver eq 'SQLite') {
		$timeMeasure->stop();
		$timeMeasure->clear();

		$timeMeasure->start();
		$log->info("Start optimizing SQLite database");
		my $dbh = getCurrentDBH();
		$dbh->do("ANALYZE customscan_track_attributes");
		$dbh->do("ANALYZE customscan_album_attributes");
		$dbh->do("ANALYZE customscan_contributor_attributes");
		commit($dbh);
		$log->info("Finished optimizing SQLite database : It took ".$timeMeasure->getElapsedTime()." seconds");
	}
	$log->warn("CustomScan: Synchronization finished\n");
	$timeMeasure->stop();
	$timeMeasure->clear();
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


1;

__END__
