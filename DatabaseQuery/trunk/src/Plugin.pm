# 				DatabaseQuery plugin 
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

package Plugins::DatabaseQuery::Plugin;

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

use Plugins::DatabaseQuery::Modules::CSV;
use Plugins::DatabaseQuery::Modules::XML;
use Plugins::DatabaseQuery::Modules::XMLTree;

use Plugins::DatabaseQuery::Settings;

use Plugins::DatabaseQuery::ConfigManager::Main;

use Slim::Schema;

my $prefs = preferences('plugin.databasequery');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.databasequery',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_DATABASEQUERY',
});

$prefs->migrate(1, sub {
	$prefs->set('dataqueries_directory', Slim::Utils::Prefs::OldPrefs->get('plugin_databasequery_dataqueries_directory') || $serverPrefs->get('playlistdir')  );
	$prefs->set('template_directory',  Slim::Utils::Prefs::OldPrefs->get('plugin_databasequery_template_directory')   || ''  );
	$prefs->set('download_url',  Slim::Utils::Prefs::OldPrefs->get('plugin_databasequery_download_url')   || 'http://erland.isaksson.info/datacollection/services/DataCollection'  );
	1;
});
$prefs->migrate(2, sub {
        my $url = $prefs->get('download_url');
        if(!defined($url) || $url eq 'http://erland.homeip.net/datacollection/services/DataCollection') {
                $prefs->set('download_url','http://erland.isaksson.info/datacollection/services/DataCollection');
        }
});

$prefs->setValidate('dir','dataqueries_directory');
$prefs->setValidate('dir','template_directory');

# Information on each clients databasequery
my $htmlTemplate = 'plugins/DatabaseQuery/databasequery_list.html';
my $dataQueries = undef;
my $sqlerrors = '';
my $soapLiteError = 0;
my $PLUGINVERSION = '1.1.1';

my $configManager = undef;

sub getDisplayName {
	return 'PLUGIN_DATABASEQUERY';
}

sub initDataQueries {
	my $client = shift;

	my $itemConfiguration = getConfigManager()->readItemConfiguration($client,1);

	my $localdataQueries = $itemConfiguration->{'dataqueries'};

	$dataQueries = $localdataQueries;
}

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	Plugins::DatabaseQuery::Settings->new($class);
	checkDefaults();

	${Slim::Music::Info::suffixes}{'binfile'} = 'binfile';
	${Slim::Music::Info::types}{'binfile'} = 'application/octet-stream';

	my ($driver,$source,$username,$password);
	($driver,$source,$username,$password) = Slim::Schema->sourceInformation;

	if($driver eq 'SQLite') {
		createSQLiteFunctions();
	}
}

sub createSQLiteFunctions {
	my $dbh = Slim::Schema->storage->dbh();
	$dbh->func('repeat', 2, sub {
		my ($str,$repititions) = @_;
		return $str x $repititions;
	    }, 'create_function');
	$dbh->func('floor', 1, sub {
		my ($number) = @_;
		if(!defined($number)) {
			$number = 0;
		}
		$number = floor($number); 
		return $number;
	    }, 'create_function');
	$dbh->func('if', 3, sub {
		my ($expr,$str1,$str2) = @_;
		if($expr) {
			return $str1;
		}else {
			return $str2;
		}
	    }, 'create_function');
	$dbh->func('floor', 2, sub {
		my ($number,$decimals) = @_;
		if(!defined($number)) {
			$number = 0;
		}
		if($decimals>0) {
			$number =~s/(^\d{1,}\.\d{$decimals})(.*$)/$1/; 
		}else {
			$number =~s/(^\d{1,})(.*$)/$1/; 
		}
		return $number;
	    }, 'create_function');
	$dbh->func('concat', 2, sub {
		my ($str1, $str2) = @_;
		return $str1.$str2;
	    }, 'create_function');
	$dbh->func('concat', 3, sub {
		my ($str1, $str2, $str3) = @_;
		return $str1.$str2.$str3;
	    }, 'create_function');
	$dbh->func('concat', 4, sub {
		my ($str1, $str2, $str3,$str4) = @_;
		return $str1.$str2.$str3.$str4;
	    }, 'create_function');
}

sub postinitPlugin {
	eval {
		initDataQueries();
	};
	if( $@ ) {
	    	$log->warn("Startup error: $@\n");
	}		
}

sub getConfigManager {
	if(!defined($configManager)) {
		my %parameters = (
			'logHandler' => $log,
			'pluginPrefs' => $prefs,
			'pluginId' => 'DatabaseQuery',
			'pluginVersion' => $PLUGINVERSION,
			'downloadApplicationId' => 'DatabaseQuery',
			'addSqlErrorCallback' => \&addSQLError,
			'downloadVersion' => 2,
		);
		$configManager = Plugins::DatabaseQuery::ConfigManager::Main->new(\%parameters);
	}
	return $configManager;
}

sub webPages {

	my %pages = (
		"DatabaseQuery/databasequery_list\.(?:htm|xml)"     => \&handleWebList,
		"DatabaseQuery/databasequery_refreshdataqueries\.(?:htm|xml)"     => \&handleWebRefreshDataQueries,
		"DatabaseQuery/databasequery_executedataquery\.(?:htm|xml|binfile)"     => \&handleWebExecuteDataQuery,
                "DatabaseQuery/webadminmethods_edititem\.(?:htm|xml)"     => \&handleWebEditDataQuery,
                "DatabaseQuery/webadminmethods_saveitem\.(?:htm|xml)"     => \&handleWebSaveDataQuery,
                "DatabaseQuery/webadminmethods_savesimpleitem\.(?:htm|xml)"     => \&handleWebSaveSimpleDataQuery,
                "DatabaseQuery/webadminmethods_savenewitem\.(?:htm|xml)"     => \&handleWebSaveNewDataQuery,
                "DatabaseQuery/webadminmethods_savenewsimpleitem\.(?:htm|xml)"     => \&handleWebSaveNewSimpleDataQuery,
                "DatabaseQuery/webadminmethods_removeitem\.(?:htm|xml)"     => \&handleWebRemoveDataQuery,
                "DatabaseQuery/webadminmethods_newitemtypes\.(?:htm|xml)"     => \&handleWebNewDataQueryTypes,
                "DatabaseQuery/webadminmethods_newitemparameters\.(?:htm|xml)"     => \&handleWebNewDataQueryParameters,
                "DatabaseQuery/webadminmethods_newitem\.(?:htm|xml)"     => \&handleWebNewDataQuery,
		"DatabaseQuery/webadminmethods_login\.(?:htm|xml)"      => \&handleWebLogin,
		"DatabaseQuery/webadminmethods_downloadnewitems\.(?:htm|xml)"      => \&handleWebDownloadNewDataQueries,
		"DatabaseQuery/webadminmethods_downloaditems\.(?:htm|xml)"      => \&handleWebDownloadDataQueries,
		"DatabaseQuery/webadminmethods_downloaditem\.(?:htm|xml)"      => \&handleWebDownloadDataQuery,
		"DatabaseQuery/webadminmethods_publishitemparameters\.(?:htm|xml)"      => \&handleWebPublishDataQueryParameters,
		"DatabaseQuery/webadminmethods_publishitem\.(?:htm|xml)"      => \&handleWebPublishDataQuery,
		"DatabaseQuery/webadminmethods_deleteitemtype\.(?:htm|xml)"      => \&handleWebDeleteDataQueryType,
	);

	for my $page (keys %pages) {
		if(UNIVERSAL::can("Slim::Web::Pages","addPageFunction")) {
			Slim::Web::Pages->addPageFunction($page, $pages{$page});
		}else {
			Slim::Web::HTTP::addPageFunction($page, $pages{$page});
		}
	}

	Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_DATABASEQUERY' => 'plugins/DatabaseQuery/databasequery_list.html' });
}


# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	# Pass on the current pref values and now playing info
	if(!defined($params->{'donotrefresh'})) {
		if(defined($params->{'cleancache'}) && $params->{'cleancache'}) {
			my $cache = Slim::Utils::Cache->new("FileCache/DatabaseQuery");
			$cache->clear();
		}
		initDataQueries($client);
	}
	if($params->{'execute'}) {
		my $queryId = $params->{'file'};
		$queryId =~ s/\.dataquery\.xml$//;
		$queryId =~ s/\.dataquery\.values\.xml$//;
		$params->{'type'} = $queryId;
		return handleWebExecuteDataQuery($client, $params);
	}

	my $name = undef;
	my @webDataQueries = ();
	for my $key (keys %$dataQueries) {
		my %webDataQuery = ();
		my $dataQuery = $dataQueries->{$key};
		for my $attr (keys %$dataQuery) {
			$webDataQuery{$attr} = $dataQuery->{$attr};
		}
		push @webDataQueries,\%webDataQuery;
	}
	@webDataQueries = sort { $a->{'name'} cmp $b->{'name'} } @webDataQueries;

	$params->{'pluginDatabaseQueryDataQueries'} = \@webDataQueries;
	my @webExportModules = ();
	my $exportModules = getExportModules();
	for my $key (keys %$exportModules) {
		my %webModule = ();
		my $module = $exportModules->{$key};
		for my $attr (keys %$module) {
			$webModule{$attr} = $module->{$attr};
		}
		push @webExportModules,\%webModule;
	}
	@webExportModules = sort { $a->{'name'} cmp $b->{'name'} } @webExportModules;
	
	$params->{'pluginDatabaseQueryExportModules'} = \@webExportModules;
	$params->{'pluginDatabaseQueryVersion'} = $PLUGINVERSION;
	if(defined($params->{'redirect'})) {
		return Slim::Web::HTTP::filltemplatefile('plugins/DatabaseQuery/databasequery_redirect.html', $params);
	}else {
		return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
	}
}

sub handleWebRefreshDataQueries {
	my ($client, $params) = @_;

	return handleWebList($client,$params);
}

sub getExportModules {
	my %plugins = ();
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		for my $plugin (qw(CSV XML XMLTree)) {
			no strict 'refs';
			my $fullname = "Plugins::DatabaseQuery::Modules::$plugin";
			if(UNIVERSAL::can("${fullname}","getDatabaseQueryExportModules")) {
				my $data = eval { &{"${fullname}::getDatabaseQueryExportModules"}($PLUGINVERSION); };
				if ($@) {
					$log->warn("Failed to call module $fullname: $@\n");
				}else {
					my @modules = ();
					if(ref($data) eq 'ARRAY') {
						push @modules,@$data;
					}else {
						push @modules,$data;
					}
					for my $module (@modules) {
						if(defined($module) && defined($module->{'id'}) && defined($module->{'name'}) && defined($module->{'callback'})) {
							$plugins{$module->{'id'}} = $module;
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
			$log->warn("Failed to load module $fullname: $@\n");
		}elsif(UNIVERSAL::can("${fullname}","getDatabaseQueryExportModules")) {
			my $data = eval { &{$fullname . "::getDatabaseQueryExportModules"}(); };
			if ($@) {
				$log->warn("Failed to load module $fullname: $@\n");
			}elsif(defined($data)) {
				my @modules = ();
				if(ref($data) eq 'ARRAY') {
					push @modules,@$data;
				}else {
					push @modules,$data;
				}
				for my $module (@modules) {
					if(defined($module->{'id'}) && defined($module->{'name'}) && defined($module->{'callback'})) {
						$plugins{$module->{'id'}} = $module;
					}
				}
			}
		}
		use strict 'refs';
	}
	return \%plugins;
}

sub handleWebExecuteDataQuery {
	my ($client, $params, $prepareResponseForSending, $httpClient, $response) = @_;

	initDataQueries($client);

	$params->{'pluginDatabaseQueryVersion'} = $PLUGINVERSION;
	if($params->{'type'}) {
		my $dataQueryId = unescape($params->{'type'});
		if(defined($dataQueries->{$dataQueryId})) {
			my $dataQuery = $dataQueries->{$dataQueryId};
			my %parameters = ();
			my $result = executeDataQueryTree($dataQuery,$params,\%parameters);
			my $modules = getExportModules();
			if(!defined($result->{'error'}) && defined($params->{'as'}) && defined($modules->{$params->{'as'}})) {
				my $module = $modules->{$params->{'as'}};
				my $resultText = eval { $module->{'callback'}($dataQueryId, $result,\&getMoreData); };
				if($@) {
					$log->warn("Report error: $@\n");
				}
				if(defined($resultText)) {
					$response->header("Content-Disposition","attachment; filename=result.".$module->{'extension'});
					return $resultText;
				}
			}
			$params->{'pluginDatabaseQueryId'} = $dataQuery->{'id'};
			$params->{'pluginDatabaseQuery'} = $dataQuery;
			$params->{'pluginDatabaseQueryColumns'} = $result->{'columns'};
			$params->{'pluginDatabaseQueryResultItems'} = $result->{'resultitems'};
			if(exists $params->{'hierarchy'}) {
				$params->{'pluginDatabaseQueryContextUrl'} = 'hierarchy='.$params->{'hierarchy'}; 
				my @path = split(/,/,$params->{'hierarchy'});
				for my $attr (@path) {
					$params->{'pluginDatabaseQueryContextUrl'} .= '&'.$attr.'='.$params->{$attr};
				}
			}
			my @webExportModules = ();
			for my $key (keys %$modules) {
				my %webModule = ();
				my $module = $modules->{$key};
				for my $attr (keys %$module) {
					$webModule{$attr} = $module->{$attr};
				}
				push @webExportModules,\%webModule;
			}
			@webExportModules = sort { $a->{'name'} cmp $b->{'name'} } @webExportModules;
	
			$params->{'pluginDatabaseQueryExportModules'} = \@webExportModules;

			if(defined($result->{'error'})) {
				$params->{'pluginDatabaseQueryError'} = $result->{'error'};
			}
		
			return Slim::Web::HTTP::filltemplatefile('plugins/DatabaseQuery/databasequery_viewdataquery.html', $params);
		}
	}
	return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
}

sub getMoreData {
	my $dataQueryId = shift;
	my $path = shift;
	my $parameters = shift;

	my $dataQuery = $dataQueries->{$dataQueryId};
	return executeDataQueryTree($dataQuery,$parameters,$parameters,$path);
}

sub executeDataQueryTree {
	my $dataQuery = shift;
	my $params = shift;
	my $parameters = shift;
	my $fullPath = shift;
	my $handledPath = shift;

	my @path = ();
	if(defined($fullPath)) {
		@path = @$fullPath;
	}else {
		if(defined($params->{'hierarchy'})) {
			@path = split(/,/,$params->{'hierarchy'});
		}
	}
	if(!exists $dataQuery->{'querytree'}) {
		return executeDataQuery($dataQuery,$parameters,$handledPath);
	}
	my $queryTree = $dataQuery->{'querytree'};
	my @queryTrees = ();
	if(ref($queryTree) eq 'ARRAY') {
		for my $tree (@$queryTree) {
			push  @queryTrees,$tree;
		}
	}else {
		push @queryTrees,$queryTree;
	}
	if(scalar(@path)>0) {
		my $firstPath = shift @path;
		my $queryTreeToUse = undef;
		for my $tree (@queryTrees) {
			if($tree->{'queryid'} eq $firstPath) {
				$queryTreeToUse = $tree;
				last;
			}
		}
		if(!defined($queryTreeToUse)) {
			my %result = (
				'error' => "No query defined for specified hierarchy",
			);
			return \%result;
		}else {
			$parameters->{$firstPath} = $params->{$firstPath};
			if(!defined($handledPath)) {
				my @empty = ();
				$handledPath = \@empty;
			}
			push @$handledPath,$firstPath;
			return executeDataQueryTree($queryTreeToUse,$params,$parameters,\@path,$handledPath);
		}
	}

	my %result = ();
	for my $tree (@queryTrees) {
		my $subresult = executeDataQuery($tree,$parameters,$handledPath);
		if(!defined($result{'resultitems'}) && defined($subresult->{'resultitems'})) {
			$result{'columns'} = $subresult->{'columns'};
			$result{'resultitems'} = $subresult->{'resultitems'};
		}elsif(defined($result{'resultitems'}) && defined($subresult->{'resultitems'})) {
			my $previousResult = $result{'resultitems'};
			my $newResult = $subresult->{'resultitems'};
			push @$previousResult,@$newResult;
		}else {
			if(!defined($result{'error'})) {
				$result{'error'} = '';
			}else {
				$result{'error'} .= "\n";
			}
			$result{'error'} .= $subresult->{'error'};
		}
	}
	if(!defined($result{'resultitems'}) && !defined($result{'error'})) {
		$result{'error'} = "No query defined";
	}
	return \%result;
}

sub executeDataQuery {
	my $dataQuery = shift;
	my $parameters = shift;
	my $path = shift;

	my $newUnicodeHandling = 0;
	if(UNIVERSAL::can("Slim::Utils::Unicode","hasEDD")) {
		$newUnicodeHandling = 1;
	}

	my $sql = $dataQuery->{'query'} if exists $dataQuery->{'query'};
	my $queryId = $dataQuery->{'queryid'} if exists $dataQuery->{'queryid'};
	my $subQueriesExists = 0;
	$subQueriesExists = 1 if exists $dataQuery->{'querytree'};

	my @statements = ();
	if(ref($sql) eq 'ARRAY') {
		for my $statement (@$sql) {
			push  @statements,$statement;
		}
	}else {
		push @statements,$sql;
	}
	my %result = ();
	if(scalar(@statements)==0) {
		$result{'error'} .= "No query defined";
	}
	for my $sql (@statements) {
		if(defined($sql)) {
			$sql =~ s/^\s*(.*)\s*$/$1/;
		}
		eval {
			if(defined($sql)) {
				$sql = replaceParameters($sql,$parameters);
				$log->debug("Executing: $sql\n");
				my $sth = getCurrentDBH()->prepare($sql);
				$sth->execute();
				my @resultItems = ();
				my @columns = ();
				my $i;
				for ( $i = 1 ; $i <= $sth->{NUM_OF_FIELDS} ; $i++ ) {
				    push @columns,$sth->{NAME}->[$i-1];
				}
				my @values = ();
				while( @values = $sth->fetchrow_array() ) {
					my @resultValues = @values;
					for my $value (@resultValues) {
						if($newUnicodeHandling) {
							$value = Slim::Utils::Unicode::utf8decode($value,'utf8') if defined($value);
						}else {
							$value = Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($value,'utf8')) if defined($value);
						}
					}
					my @pathelements = ();
					if($subQueriesExists && defined($queryId) && $queryId ne '' && defined($path)) {
						@pathelements = @$path;
						push @pathelements,$queryId;
					}elsif($subQueriesExists && defined($queryId) && $queryId ne '') {
						push @pathelements,$queryId;
					}
					if(scalar(@pathelements)>0) {
						my $itemurl = undef;
						for my $key (@pathelements) {
							if(!defined($itemurl)) {
								$itemurl = 'hierarchy=';
							}else {
								$itemurl .= ',';
							}
							$itemurl .= $key;
						}
						for my $key (keys %$parameters) {
							$itemurl .= '&'.$key.'='.$parameters->{$key};
						}
						$itemurl .= '&'.$queryId.'='.@resultValues->[0];
						unshift @resultValues,$parameters;
						unshift @resultValues,\@pathelements;
						unshift @resultValues,$itemurl;
						unshift @resultValues,$queryId;
					}else {
						unshift @resultValues,undef;
						unshift @resultValues,undef;
						unshift @resultValues,undef;
						unshift @resultValues,$queryId;
					}
					push @resultItems,\@resultValues;
				}
				$sth->finish();
		
				if(!defined($result{'columns'})) {
					$result{'columns'} = \@columns;
				}
				if(!defined($result{'resultitems'})) {
					$result{'resultitems'} = \@resultItems;
				}else {
					my $previous = $result{'resultitems'};
					push @$previous,@resultItems,
				}
			}else {
				if(!defined($result{'error'})) {
					$result{'error'} = '';
				}else {
					$result{'error'} .= "\n";
				}
				$result{'error'} .= "No query defined";
			}
		};
		if($@) {
			if(!defined($result{'error'})) {
				$result{'error'} = '';
			}else {
				$result{'error'} .= "\n";
			}
			$result{'error'} .= "$@, $DBI::errstr";
		}
	}
	return \%result;
}

sub replaceParameters {
	my $originalValue = shift;
	my $parameters = shift;
	my $quote = shift;

	if(defined($parameters)) {
		for my $param (keys %$parameters) {
			my $propertyValue = $parameters->{$param};
			if(!defined($propertyValue)) {
				$propertyValue='';
			}
			if($quote) {
				$propertyValue =~ s/\'/\\\'/g;
				$propertyValue =~ s/\"/\\\"/g;
				$propertyValue =~ s/\\/\\\\/g;
			}
			$originalValue =~ s/\{$param\}/$propertyValue/g;
		}
	}

	return $originalValue;
}

sub handleWebEditDataQuery {
        my ($client, $params) = @_;
	return getConfigManager()->webEditItem($client,$params);	
}

sub handleWebDeleteDataQueryType {
	my ($client, $params) = @_;
	return getConfigManager()->webDeleteItemType($client,$params);	
}

sub handleWebNewDataQueryTypes {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItemTypes($client,$params);	
}

sub handleWebNewDataQueryParameters {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItemParameters($client,$params);	
}

sub handleWebLogin {
	my ($client, $params) = @_;
	return getConfigManager()->webLogin($client,$params);	
}

sub handleWebPublishDataQueryParameters {
	my ($client, $params) = @_;
	return getConfigManager()->webPublishItemParameters($client,$params);	
}

sub handleWebPublishDataQuery {
	my ($client, $params) = @_;
	return getConfigManager()->webPublishItem($client,$params);	
}

sub handleWebDownloadDataQueries {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadItems($client,$params);	
}

sub handleWebDownloadNewDataQueries {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadNewItems($client,$params);	
}

sub handleWebDownloadDataQuery {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadItem($client,$params);	
}

sub handleWebNewDataQuery {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItem($client,$params);	
}

sub handleWebSaveSimpleDataQuery {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveSimpleItem($client,$params);	
}

sub handleWebRemoveDataQuery {
	my ($client, $params) = @_;
	return getConfigManager()->webRemoveItem($client,$params);	
}

sub handleWebSaveNewSimpleDataQuery {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveNewSimpleItem($client,$params);	
}

sub handleWebSaveNewDataQuery {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveNewItem($client,$params);	
}

sub handleWebSaveDataQuery {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveItem($client,$params);	
}


sub checkDefaults {
	my $prefVal = $prefs->get('dataqueries_directory');
	if (! defined $prefVal) {
		# Default to standard data queries directory
		my $dir=$serverPrefs->get('playlistdir');
		$log->debug("Defaulting dataqueries_directory to:$dir\n");
		$prefs->set('dataqueries_directory', $dir);
	}
	$prefVal = $prefs->get('download_url');
	if (! defined $prefVal) {
		$prefs->set('download_url', 'http://erland.isaksson.info/datacollection/services/DataCollection');
	}
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
