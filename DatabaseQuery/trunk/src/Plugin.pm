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

use Plugins::DatabaseQuery::ConfigManager::Main;

use Slim::Schema;

# Information on each clients databasequery
my $htmlTemplate = 'plugins/DatabaseQuery/databasequery_list.html';
my $dataQueries = undef;
my $sqlerrors = '';
my $soapLiteError = 0;
my $supportDownloadError = undef;
my $PLUGINVERSION = '1.1';

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
	$soapLiteError = 0;
	eval "use SOAP::Lite";
	if ($@) {
		my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
		for my $plugindir (@pluginDirs) {
			next unless -d catdir($plugindir,"DatabaseQuery","libs");
			push @INC,catdir($plugindir,"DatabaseQuery","libs");
			last;
		}
		debugMsg("Using internal implementation of SOAP::Lite\n");
		eval "use SOAP::Lite";
		if ($@) {
			$soapLiteError = 1;
			msg("DatabaseQuery: ERROR! Cant load internal implementation of SOAP::Lite, download/publish functionallity will not be available\n");
		}
	}
	if(!defined($supportDownloadError) && $soapLiteError) {
		$supportDownloadError = "Could not use the internal web service implementation, please download and install SOAP::Lite manually";
	}
	checkDefaults();
	eval {
		initDataQueries();
	};
	if( $@ ) {
	    	errorMsg("Startup error: $@\n");
	}		

	${Slim::Music::Info::suffixes}{'binfile'} = 'binfile';
	${Slim::Music::Info::types}{'binfile'} = 'application/octet-stream';
}

sub getConfigManager {
	if(!defined($configManager)) {
		my $templateDir = Slim::Utils::Prefs::get('plugin_databasequery_template_directory');
		if(!defined($templateDir) || !-d $templateDir) {
			$supportDownloadError = 'You have to specify a template directory before you can download data queries';
		}
		my %parameters = (
			'debugCallback' => \&debugMsg,
			'errorCallback' => \&errorMsg,
			'pluginId' => 'DatabaseQuery',
			'pluginVersion' => $PLUGINVERSION,
			'downloadApplicationId' => 'DatabaseQuery',
			'supportDownloadError' => $supportDownloadError,
			'addSqlErrorCallback' => \&addSQLError
		);
		$configManager = Plugins::DatabaseQuery::ConfigManager::Main->new(\%parameters);
	}
	return $configManager;
}

sub webPages {

	my %pages = (
		"databasequery_list\.(?:htm|xml)"     => \&handleWebList,
		"databasequery_refreshdataqueries\.(?:htm|xml)"     => \&handleWebRefreshDataQueries,
		"databasequery_executedataquery\.(?:htm|xml|binfile)"     => \&handleWebExecuteDataQuery,
                "webadminmethods_edititem\.(?:htm|xml)"     => \&handleWebEditDataQuery,
                "webadminmethods_saveitem\.(?:htm|xml)"     => \&handleWebSaveDataQuery,
                "webadminmethods_savesimpleitem\.(?:htm|xml)"     => \&handleWebSaveSimpleDataQuery,
                "webadminmethods_savenewitem\.(?:htm|xml)"     => \&handleWebSaveNewDataQuery,
                "webadminmethods_savenewsimpleitem\.(?:htm|xml)"     => \&handleWebSaveNewSimpleDataQuery,
                "webadminmethods_removeitem\.(?:htm|xml)"     => \&handleWebRemoveDataQuery,
                "webadminmethods_newitemtypes\.(?:htm|xml)"     => \&handleWebNewDataQueryTypes,
                "webadminmethods_newitemparameters\.(?:htm|xml)"     => \&handleWebNewDataQueryParameters,
                "webadminmethods_newitem\.(?:htm|xml)"     => \&handleWebNewDataQuery,
		"webadminmethods_login\.(?:htm|xml)"      => \&handleWebLogin,
		"webadminmethods_downloadnewitems\.(?:htm|xml)"      => \&handleWebDownloadNewDataQueries,
		"webadminmethods_downloaditems\.(?:htm|xml)"      => \&handleWebDownloadDataQueries,
		"webadminmethods_downloaditem\.(?:htm|xml)"      => \&handleWebDownloadDataQuery,
		"webadminmethods_publishitemparameters\.(?:htm|xml)"      => \&handleWebPublishDataQueryParameters,
		"webadminmethods_publishitem\.(?:htm|xml)"      => \&handleWebPublishDataQuery,
		"webadminmethods_deleteitemtype\.(?:htm|xml)"      => \&handleWebDeleteDataQueryType,
	);

	my $value = $htmlTemplate;

	if (grep { /^DatabaseQuery::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

		$value = undef;
	} 

	#Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_DATABASEQUERY' => $value });

	return (\%pages,$value);
}


# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	# Pass on the current pref values and now playing info
	if(!defined($params->{'donotrefresh'})) {
		initDataQueries($client);
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
	if(defined($supportDownloadError)) {
		$params->{'pluginDatabaseQueryDownloadMessage'} = $supportDownloadError;
	}
	$params->{'pluginDatabaseQueryVersion'} = $PLUGINVERSION;
	if(defined($params->{'redirect'})) {
		return Slim::Web::HTTP::filltemplatefile('plugins/DatabaseQuery/databasequery_redirect.html', $params);
	}else {
		return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
	}
}

sub handleWebRefreshDataQueries {
	my ($client, $params) = @_;

	initDataQueries($client);
	return handleWebList($client,$params);
}

sub getExportModules {
	my %plugins = ();
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		my $dir = catdir($plugindir,"DatabaseQuery","Modules");
		next unless -d $dir;
		my @dircontents = Slim::Utils::Misc::readDirectory($dir,"pm");
		for my $plugin (@dircontents) {
			if ($plugin =~ s/(.+)\.pm$/$1/i) {
				my $fullname = "Plugins::DatabaseQuery::Modules::$plugin";
				no strict 'refs';
				eval "use $fullname";
				if ($@) {
					msg("DatabaseQuery: Failed to load module $fullname: $@\n");
				}elsif(UNIVERSAL::can("${fullname}","getDatabaseQueryExportModules")) {
					my $data = eval { &{$fullname . "::getDatabaseQueryExportModules"}(); };
					if ($@) {
						msg("DatabaseQuery: Failed to call module $fullname: $@\n");
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
	}
	my @enabledplugins = Slim::Utils::PluginManager::enabledPlugins();
	for my $plugin (@enabledplugins) {
		my $fullname = "Plugins::$plugin";
		no strict 'refs';
		eval "use $fullname";
		if ($@) {
			msg("DatabaseQuery: Failed to load module $fullname: $@\n");
		}elsif(UNIVERSAL::can("${fullname}","getDatabaseQueryExportModules")) {
			my $data = eval { &{$fullname . "::getDatabaseQueryExportModules"}(); };
			if ($@) {
				msg("DatabaseQuery: Failed to load module $fullname: $@\n");
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
					errorMsg("Report error: $@\n");
				}
				if(defined($resultText)) {
					$response->header("Content-Disposition","attachment; filename=result.".$module->{'extension'});
					return $resultText;
				}
			}
			$params->{'pluginDatabaseQueryId'} = $dataQuery->{'id'};
			$params->{'pluginDatabaseQueryName'} = $dataQuery->{'name'};
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
				debugMsg("Executing: $sql\n");
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
						$value = Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($value,'utf8')) if defined($value);
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
	my $prefVal = Slim::Utils::Prefs::get('plugin_databasequery_dataqueries_directory');
	if (! defined $prefVal) {
		# Default to standard data queries directory
		my $dir=Slim::Utils::Prefs::get('playlistdir');
		debugMsg("Defaulting plugin_databasequery_dataqueries_directory to:$dir\n");
		Slim::Utils::Prefs::set('plugin_databasequery_dataqueries_directory', $dir);
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_databasequery_showmessages');
	if (! defined $prefVal) {
		# Default to not show debug messages
		debugMsg("Defaulting plugin_databasequery_showmessages to 0\n");
		Slim::Utils::Prefs::set('plugin_databasequery_showmessages', 0);
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_databasequery_download_url');
	if (! defined $prefVal) {
		Slim::Utils::Prefs::set('plugin_databasequery_download_url', 'http://erland.homeip.net/datacollection/services/DataCollection');
	}
}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_databasequery_dataqueries_directory','plugin_databasequery_template_directory','plugin_databasequery_showmessages'],
	 GroupHead => string('PLUGIN_DATABASEQUERY_SETUP_GROUP'),
	 GroupDesc => string('PLUGIN_DATABASEQUERY_SETUP_GROUP_DESC'),
	 GroupLine => 1,
	 GroupSub  => 1,
	 Suppress_PrefSub  => 1,
	 Suppress_PrefLine => 1
	);
	my %setupPrefs =
	(
	plugin_databasequery_showmessages => {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_DATABASEQUERY_SHOW_MESSAGES')
			,'changeIntro' => string('PLUGIN_DATABASEQUERY_SHOW_MESSAGES')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_databasequery_showmessages"); }
		},		
	plugin_databasequery_dataqueries_directory => {
			'validate' => \&Slim::Utils::Validate::isDir
			,'PrefChoose' => string('PLUGIN_DATABASEQUERY_DATAQUERIES_DIRECTORY')
			,'changeIntro' => string('PLUGIN_DATABASEQUERY_DATAQUERIES_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_databasequery_dataqueries_directory"); }
		},
	plugin_databasequery_template_directory => {
			'validate' => \&Slim::Utils::Validate::isDir
			,'PrefChoose' => string('PLUGIN_DATABASEQUERY_TEMPLATE_DIRECTORY')
			,'changeIntro' => string('PLUGIN_DATABASEQUERY_TEMPLATE_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_databasequery_template_directory"); }
		},
	);
	getConfigManager()->initWebAdminMethods();
	return (\%setupGroup,\%setupPrefs);
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
	my $message = join '','DatabaseQuery: ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_databasequery_showmessages"));
}

sub strings {
	return <<EOF;
PLUGIN_DATABASEQUERY
	EN	Database Query

PLUGIN_DATABASEQUERY_SETUP_GROUP
	EN	Database Query

PLUGIN_DATABASEQUERY_SETUP_GROUP_DESC
	EN	Database Query is a plugin to make it easier to retrive data from the SlimServer database without using a SQL client application

PLUGIN_DATABASEQUERY_DATAQUERIES_DIRECTORY
	EN	Data queries directory

PLUGIN_DATABASEQUERY_SHOW_MESSAGES
	EN	Show debug messages

PLUGIN_DATABASEQUERY_TEMPLATE_DIRECTORY
	EN	Data queries templates directory

SETUP_PLUGIN_DATABASEQUERY_DATAQUERIES_DIRECTORY
	EN	Data queries directory

SETUP_PLUGIN_DATABASEQUERY_SHOWMESSAGES
	EN	Debugging

SETUP_PLUGIN_DATABASEQUERY_TEMPLATE_DIRECTORY
	EN	Data queries templates directory

PLUGIN_DATABASEQUERY_CHOOSE_BELOW
	EN	Choose a data query to run:

PLUGIN_DATABASEQUERY_EDIT_ITEM
	EN	Edit

PLUGIN_DATABASEQUERY_NEW_ITEM
	EN	Create new data query

PLUGIN_DATABASEQUERY_NEW_ITEM_TYPES_TITLE
	EN	Select type of data query

PLUGIN_DATABASEQUERY_EDIT_ITEM_DATA
	EN	Data Query Configuration

PLUGIN_DATABASEQUERY_EDIT_ITEM_NAME
	EN	Data Query Name

PLUGIN_DATABASEQUERY_EDIT_ITEM_FILENAME
	EN	Filename

PLUGIN_DATABASEQUERY_REMOVE_ITEM_QUESTION
	EN	Are you sure you want to delete this data query ?

PLUGIN_DATABASEQUERY_REMOVE_ITEM_TYPE_QUESTION
	EN	Removing a data query type might cause problems later if it is used in existing data queries, are you really sure you want to delete this data query type ?

PLUGIN_DATABASEQUERY_REMOVE_ITEM
	EN	Delete

PLUGIN_DATABASEQUERY_REMOVE_ITEM_QUESTION
	EN	Are you sure you want to delete this data query ?

PLUGIN_DATABASEQUERY_SAVE
	EN	Save

PLUGIN_DATABASEQUERY_NEXT
	EN	Next

PLUGIN_DATABASEQUERY_ITEMTYPE
	EN	Customize SQL
	
PLUGIN_DATABASEQUERY_ITEMTYPE_SIMPLE
	EN	Use predefined

PLUGIN_DATABASEQUERY_ITEMTYPE_ADVANCED
	EN	Customize SQL

PLUGIN_DATABASEQUERY_NEW_ITEM_PARAMETERS_TITLE
	EN	Please enter data query parameters

PLUGIN_DATABASEQUERY_EDIT_ITEM_PARAMETERS_TITLE
	EN	Please enter data query parameters

PLUGIN_DATABASEQUERY_LOGIN_USER
	EN	Username

PLUGIN_DATABASEQUERY_LOGIN_PASSWORD
	EN	Password

PLUGIN_DATABASEQUERY_LOGIN_FIRSTNAME
	EN	First name

PLUGIN_DATABASEQUERY_LOGIN_LASTNAME
	EN	Last name

PLUGIN_DATABASEQUERY_LOGIN_EMAIL
	EN	e-mail

PLUGIN_DATABASEQUERY_ANONYMOUSLOGIN
	EN	Anonymous

PLUGIN_DATABASEQUERY_LOGIN
	EN	Login

PLUGIN_DATABASEQUERY_REGISTERLOGIN
	EN	Register &amp; Login

PLUGIN_DATABASEQUERY_REGISTER_TITLE
	EN	Register a new user

PLUGIN_DATABASEQUERY_LOGIN_TITLE
	EN	Login

PLUGIN_DATABASEQUERY_DOWNLOAD_ITEMS
	EN	Download more data queries

PLUGIN_DATABASEQUERY_PUBLISH_ITEM
	EN	Publish

PLUGIN_DATABASEQUERY_PUBLISH
	EN	Publish

PLUGIN_DATABASEQUERY_PUBLISHPARAMETERS_TITLE
	EN	Please specify information about the data query

PLUGIN_DATABASEQUERY_PUBLISH_NAME
	EN	Name

PLUGIN_DATABASEQUERY_PUBLISH_DESCRIPTION
	EN	Description

PLUGIN_DATABASEQUERY_PUBLISH_ID
	EN	Unique identifier

PLUGIN_DATABASEQUERY_LASTCHANGED
	EN	Last changed

PLUGIN_DATABASEQUERY_PUBLISHMESSAGE
	EN	Thanks for choosing to publish your data query. The advantage of publishing a data query is that other users can use it and it will also be used for ideas of new functionallity in the Database Query plugin. Publishing a data queary is also a great way of improving the functionality in the Database Query plugin by showing the developer what types of data queries you use, besides those already included with the plugin.

PLUGIN_DATABASEQUERY_REGISTERMESSAGE
	EN	You can choose to publish your data query either anonymously or by registering a user and login. The advantage of registering is that other people will be able to see that you have published the data query, you will get credit for it and you will also be sure that no one else can update or change your published data query. The e-mail adress will only be used to contact you if I have some questions to you regarding one of your data queries, it will not show up on any web pages. If you already have registered a user, just hit the Login button.

PLUGIN_DATABASEQUERY_LOGINMESSAGE
	EN	You can choose to publish your data query either anonymously or by registering a user and login. The advantage of registering is that other people will be able to see that you have published the data query, you will get credit for it and you will also be sure that no one else can update or change your published data query. Hit the &quot;Register &amp; Login&quot; button if you have not previously registered.

PLUGIN_DATABASEQUERY_PUBLISHMESSAGE_DESCRIPTION
	EN	It is important that you enter a good description of your data query, describe what your data query do and if it is based on one of the existing data queries it is a good idea to mention this and describe which extensions you have made. <br><br>It is also a good idea to try to make the &quot;Unique identifier&quot; as uniqe as possible as this will be used for filename when downloading the data query. This is especially important if you have choosen to publish your data query anonymously as it can easily be overwritten if the identifier is not unique. Please try to not use spaces and language specific characters in the unique identifier since these could cause problems on some operating systems.

PLUGIN_DATABASEQUERY_REFRESH_DOWNLOADED_ITEMS
	EN	Download last version of existing data queries

PLUGIN_DATABASEQUERY_DOWNLOAD_TEMPLATE_OVERWRITE_WARNING
	EN	A data query type with that name already exists, please change the name or select to overwrite the existing data query type

PLUGIN_DATABASEQUERY_DOWNLOAD_TEMPLATE_OVERWRITE
	EN	Overwrite existing

PLUGIN_DATABASEQUERY_PUBLISH_OVERWRITE
	EN	Overwrite existing

PLUGIN_DATABASEQUERY_DOWNLOAD_TEMPLATE_NAME
	EN	Unique identifier

PLUGIN_DATABASEQUERY_EDIT_ITEM_OVERWRITE
	EN	Overwrite existing

PLUGIN_DATABASEQUERY_DOWNLOAD_ITEMS
	EN	Download more data queries

PLUGIN_DATABASEQUERY_DOWNLOAD_QUESTION
	EN	This operation will download latest version of all data queries, this might take some time. Please note that this will overwrite any local changes you have made in built-in or previously downloaded data query types. Are you sure you want to continue ?

PLUGIN_DATABASEQUERY_REFRESH_DATAQUERIES
	EN	Refresh data queries

PLUGIN_DATABASEQUERY_EXECUTE
	EN	Execute

PLUGIN_DATABASEQUERY_EXECUTE_AND_EXPORT
	EN	Execute and export as

EOF

}

1;

__END__
