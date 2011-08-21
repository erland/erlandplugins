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
use POSIX qw(ceil);
use File::Spec::Functions qw(:ALL);
use DBI qw(:sql_types);
use FindBin qw($Bin);
use Plugins::CustomScan::Template::Reader;
use Plugins::CustomScan::ModuleSettings;
use Plugins::CustomScan::Settings;
use Plugins::CustomScan::Manage;
use Plugins::CustomScan::Scanner;
use Plugins::CustomScan::MixedTagSQLPlayListHandler;
use Scalar::Util qw(blessed);

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
$prefs->setValidate('array','titleformats');
$prefs->setValidate('hash','properties');

sub getDisplayName {
	return 'PLUGIN_CUSTOMSCAN';
}

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	Plugins::CustomScan::Scanner::initDatabase();
	if ( !$CUSTOMSCAN_HOOK ) {
		refreshTitleFormats();
		installHook();
	}
	checkDefaults();
	Plugins::CustomScan::Settings->new($class);
	Plugins::CustomScan::Manage->new($class);
	Plugins::CustomScan::ModuleSettings->new($class);
}

sub postinitPlugin {
	if($::VERSION lt '7.6') {
		Plugins::CustomScan::Scanner::initScanner($PLUGINVERSION);
	}else {
		Plugins::CustomScan::Scanner::initScanner($PLUGINVERSION,0);
	}
	if (UNIVERSAL::can("Plugins::CustomBrowse::Plugin","registerMixHandler")) {
		my %parameters = ();
		my $mixHandler = Plugins::CustomScan::MixedTagSQLPlayListHandler->new(\%parameters);
		Plugins::CustomBrowse::Plugin::registerMixHandler('customscan_mixedtag_sqlplaylist',$mixHandler);
	}
	eval "require Slim::Utils::Scanner::API;";
	if(!$@) {
		Slim::Utils::Scanner::API->onNewTrack({'cb' => \&Plugins::CustomScan::Scanner::trackChanged});
		Slim::Utils::Scanner::API->onChangedTrack({'cb' => \&Plugins::CustomScan::Scanner::trackChanged});
		Slim::Utils::Scanner::API->onDeletedTrack({'cb' => \&Plugins::CustomScan::Scanner::trackDeleted});
	}
}

sub shutdownPlugin {
        $log->info("disabling\n");
        if ($CUSTOMSCAN_HOOK) {
                uninstallHook();
        }
	Plugins::CustomScan::Scanner::shutdownScanner();
	if (UNIVERSAL::can("Plugins::CustomBrowse::Plugin","unregisterMixHandler")) {
		Plugins::CustomBrowse::Plugin::unregisterMixHandler('customscan_mixedtag_sqlplaylist');
	}
}

# Hook the plugin to the play events.
# Do this as soon as possible during startup.
sub installHook()
{  
	$log->info("Installing Custom Scan hooks\n");
	if($::VERSION lt '7.6') {
		Slim::Control::Request::subscribe(\&Plugins::CustomScan::Plugin::commandCallback,[['rescan']]);
	}
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
		Plugins::CustomScan::Scanner::createSQLiteFunctions();
		if($prefs->get("auto_rescan") && !$serverPrefs->get('autorescan')) {
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

sub getMultiLibraryTemplates {
	my $client = shift;
	return Plugins::CustomScan::Template::Reader::getTemplates($client,'CustomScan',$PLUGINVERSION,'FileCache/MultiLibrary','LibraryTemplates','xml');
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

sub webPages {

	my %pages = (
		"CustomScan/newsqlplaylist_redirect\.(?:htm|xml)"     => \&handleWebNewSQLPlayList,
	);

	for my $page (keys %pages) {
		if(UNIVERSAL::can("Slim::Web::Pages","addPageFunction")) {
			Slim::Web::Pages->addPageFunction($page, $pages{$page});
		}else {
			Slim::Web::HTTP::addPageFunction($page, $pages{$page});
		}
	}
}

sub handleWebNewSQLPlayList {
	my ($client, $params) = @_;

	my $newUnicodeHandling = 0;
	if(UNIVERSAL::can("Slim::Utils::Unicode","hasEDD")) {
		$newUnicodeHandling = 1;
	}
	my $url = 'plugins/SQLPlayList/webadminmethods_newitemparameters.html?';
	if($params->{'type'} eq 'mixedtag') {
		$url .= 'itemtemplate=customscan_randommixedtagsfrommixer';
		my %values = ();
		for my $param (keys %$params) {
			if($param =~ /^mixedtag(\d+)name$/) {
				my $tagno = $1;
				my $tagname= $params->{'mixedtag'.$tagno.'name'};
				my $tagvalue= $params->{'mixedtag'.$tagno.'value'};

				my $sql = "SELECT valuetype,value from customscan_track_attributes where module='mixedtag' and attr=? and extravalue=? limit 1";

				my $sth = Slim::Schema->storage->dbh->prepare($sql);
				$sth->bind_param(1,$tagname,SQL_VARCHAR);
				$sth->bind_param(2,$tagvalue,SQL_VARCHAR);
				eval {
					my $value;
					my $valuetype;
					$sth->execute();
					$sth->bind_col( 1, \$valuetype);
		                        $sth->bind_col( 2, \$value);
					if($sth->fetch()) {
						if($valuetype) {
							if($newUnicodeHandling) {
								$tagvalue=Slim::Utils::Unicode::utf8decode($value,'utf8');
							}else {
								$tagvalue=Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($value,'utf8'));
							}
						}
					}
					$sth->finish();
				};
				if( $@ ) {
				    $log->error("Database error: $DBI::errstr\n$@");
				}		

				$url .= '&overrideparameter_mixedtag'.($tagno).'name='.escape($tagname);
				$url .= '&overrideparameter_mixedtag'.($tagno).'value='.escape($tagvalue);
				$values{$tagno} = $tagvalue;
			}
		}
		my $i=1;
		my $playlistName = '';
		while(exists $values{$i}) {
			$playlistName .= ' '.$values{$i++};
		}
		$url .= '&overrideparameter_playlistname='.escape('Random for'.$playlistName);
	}else {
		$url .= 'itemtemplate=randomtracks.sql.xml';
	}
	$params->{'pluginCustomScanRedirect'} = $url;
	return Slim::Web::HTTP::filltemplatefile('plugins/CustomScan/customscan_redirect.html', $params);
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
sub getMultiLibraryTemplateData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;
	
	my $data = Plugins::CustomScan::Template::Reader::readTemplateData('CustomScan','LibraryTemplates',$templateItem->{'id'});
	return $data;
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

	my $newUnicodeHandling = 0;
	if(UNIVERSAL::can("Slim::Utils::Unicode","hasEDD")) {
		$newUnicodeHandling = 1;
	}

	for my $format (@$titleformats) {
		if($format) {
			Slim::Music::TitleFormatter::addFormat("CUSTOMSCAN_$format",
				sub {
					$log->debug("Retreiving title format: $format\n");
					my $track = shift;
					if(ref($track) eq 'HASH' || ref($track) ne 'Slim::Schema::Track') {
						return undef;
					}
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
								if($newUnicodeHandling) {
									$value=Slim::Utils::Unicode::utf8decode($value,'utf8');
								}else {
									$value=Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($value,'utf8'));
								}
								$result .= $value;
							}
							$sth->finish();
						};
						if( $@ ) {
		    					$log->error("Database error: $DBI::errstr\n$@\n");
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
					$log->error("Error executing SQL: $@\n$DBI::errstr\n");
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
					$log->error("Error executing SQL: $@\n$DBI::errstr\n");
				}
				$sth->finish();
				last;
			}
		}
	}

	return $result;
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

# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
