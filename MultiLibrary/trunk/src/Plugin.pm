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

use Plugins::MultiLibrary::ConfigManager::Main;
use Plugins::MultiLibrary::Template::Reader;

use Slim::Schema;

# Information on each clients multilibrary
my $htmlTemplate = 'plugins/MultiLibrary/multilibrary_list.html';
my $libraries = undef;
my $sqlerrors = '';
my $soapLiteError = 0;
my $supportDownloadError = undef;
my %currentLibrary = ();
my $PLUGINVERSION = '1.3.2';
my $internalMenus = undef;
my $customBrowseMenus = undef;

my $configManager = undef;

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
		return [Slim::Display::Display::symbol('notesymbol'), Slim::Display::Display::symbol('rightarrow')];
	}else {
		return [undef, Slim::Display::Display::symbol('rightarrow')];
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
	my $currentLibrary = getCurrentLibrary($client);
	my $i = undef;
	if(defined($currentLibrary)) {
		$i = 0;
		for my $item (@listRef) {
			if($item->{'id'} eq $currentLibrary->{'id'}) {
				last;
			}
			$i = $i + 1;
		}
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header     => '{PLUGIN_MULTILIBRARY_SELECT} {count}',
		listRef    => \@listRef,
		name       => \&getDisplayText,
		overlayRef => \&getOverlay,
		modeName   => 'PLUGIN.MultiLibrary',
		parentMode => 'PLUGIN.MultiLibrary',
		onPlay     => sub {
			my ($client, $item) = @_;
			selectLibrary($client,$item->{'id'},1);
			Slim::Buttons::Common::pushMode($client, 'playlist');
		},
		onAdd      => sub {
			my ($client, $item) = @_;
			debugMsg("Do nothing on add\n");
		},
		onRight    => sub {
			my ($client, $item) = @_;
			selectLibrary($client,$item->{'id'},1);
			Slim::Buttons::Common::pushMode($client, 'playlist');
		},
	);
	if(defined($i)) {
		$params{'listIndex'} = $i;
	}
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
		if(defined($libraries->{$libraryId}->{'action'})) {
			my $actionValue = $libraries->{$libraryId}->{'action'};
			my @actions = ();
			if(ref($actionValue) eq 'ARRAY') {
				@actions = @$actionValue;
			}else {
				push @actions,$actionValue;
			}
			for my $action  (@actions) {
				if($action->{'type'} eq 'cli') {
					eval { 
						debugMsg("Executing action: ".$action->{'type'}.", ".$action->{'data'}."\n");
						my @parts = split(/ /,$action->{'data'});
						my $request = $client->execute(\@parts);
						$request->source('PLUGIN_MULTILIBRARY');
					};
					if ($@) {
						errorMsg("MultiLibrary: Failed to execute action:".$action->{'type'}.", ".$action->{'data'}.":$@\n");
					}
				}
			}
		}
		
	}
}
sub initLibraries {
	my $client = shift;

	my $itemConfiguration = getConfigManager()->readItemConfiguration($client,1);

	my $localLibraries = $itemConfiguration->{'libraries'};

	my $dbh = getCurrentDBH();

	for my $libraryid (keys %$localLibraries) {
		my $library = $localLibraries->{$libraryid};
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
		$localLibraries->{$libraryid}->{'libraryno'} = $id;
	}

	$libraries = $localLibraries;

}

sub getCustomSkipFilterTypes {
	my @result = ();
	my %notactive = (
		'id' => 'multilibrary_notactive',
		'name' => 'Not Active Library',
		'description' => 'Skip tracks which dont exist in currently active library'
	);
	push @result, \%notactive;
	my %notinlibrary = (
		'id' => 'multilibrary_notinlibrary',
		'name' => 'Not Library',
		'description' => 'Skip tracks which dont exist in selected library',
		'parameters' => [
			{
				'id' => 'library',
				'type' => 'sqlsinglelist',
				'name' => 'Library not to skip',
				'data' => 'select id,name,id from multilibrary_libraries order by name' 
			}
		]
	);
	push @result, \%notinlibrary;
	my %inlibrary = (
		'id' => 'multilibrary_inlibrary',
		'name' => 'Library',
		'description' => 'Skip tracks which exist in selected library',
		'parameters' => [
			{
				'id' => 'library',
				'type' => 'sqlsinglelist',
				'name' => 'Library to skip',
				'data' => 'select id,name,id from multilibrary_libraries order by name' 
			}
		]
	);
	push @result, \%inlibrary;
	return \@result;
}

sub checkCustomSkipFilterType	 {
	my $client = shift;
	my $filter = shift;
	my $track = shift;

	my $parameters = $filter->{'parameter'};
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

	}elsif($filter->{'id'} eq 'multilibrary_notinlibrary') {
		my $dbh = getCurrentDBH();
		for my $parameter (@$parameters) {
			if($parameter->{'id'} eq 'library') {
				my $libraries = $parameter->{'value'};
				my $library = $libraries->[0] if(defined($libraries) && scalar(@$libraries)>0);

				my $sth = $dbh->prepare("select track from multilibrary_track where library=? and track=?");
				$sth->bind_param(1,$library,SQL_INTEGER);
				$sth->bind_param(2,$track->id,SQL_INTEGER);
				$sth->execute();
				my $id = undef;
				$sth->bind_col(1, \$id);
				if(!$sth->fetch()) {
					return 1;
				}
			}
		}

	}elsif($filter->{'id'} eq 'multilibrary_inlibrary') {
		my $dbh = getCurrentDBH();
		for my $parameter (@$parameters) {
			if($parameter->{'id'} eq 'library') {
				my $libraries = $parameter->{'value'};
				my $library = $libraries->[0] if(defined($libraries) && scalar(@$libraries)>0);
	
				my $sth = $dbh->prepare("select track from multilibrary_track where library=? and track=?");
				$sth->bind_param(1,$library,SQL_INTEGER);
				$sth->bind_param(2,$track->id,SQL_INTEGER);
				$sth->execute();
				my $id = undef;
				$sth->bind_col(1, \$id);
				if($sth->fetch()) {
					return 1;
				}
			}
		}
	}

	return 0;
}

sub getAvailableInternalMenus {
	my $client = shift;

	my @result = ();
	my $menus = getInternalMenuTemplates($client);
	if(defined($menus)) {
		for my $menu (@$menus) {
			my %item = (
				'id' => $menu->{'id'},
				'name' => $menu->{'name'},
				'value' => $menu->{'id'}
			);
			push @result,\%item;
		}
	}
	return \@result;
}

sub getAvailableCustomBrowseMenus {
	my $client = shift;

	my @result = ();
	if(Slim::Utils::Prefs::get('plugin_multilibrary_custombrowse_menus')) {
		my $menus = getCustomBrowseMenuTemplates($client);
		if(defined($menus)) {
			for my $menu (@$menus) {
				my %item = (
					'id' => $menu->{'id'},
					'name' => $menu->{'name'},
					'value' => $menu->{'id'}
				);
				push @result,\%item;
			}
		}
	}
	return \@result;
}

sub getInternalMenuTemplates {
	my $client = shift;
	return getInternalTemplates($client,'Menus');
}

sub getInternalContextMenuTemplates {
	my $client = shift;
	return getInternalTemplates($client,'ContextMenus');
}

sub getInternalTemplates {
	my $client = shift;
	my $dir = shift;
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	my @result = ();
	for my $plugindir (@pluginDirs) {
		my $templateDir = catdir($plugindir,'MultiLibrary',$dir);
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
sub getCustomBrowseMenuTemplates {
	my $client = shift;
	my @result = ();
	if(UNIVERSAL::can("Plugins::CustomBrowse::Plugin","getMultiLibraryMenus")) {
		debugMsg("Getting library templates from Custom Browse\n");
		no strict 'refs';
		my $items = eval { &{"Plugins::CustomBrowse::Plugin::getMultiLibraryMenus"}($client) };
		if ($@) {
			debugMsg("Error getting templates: $@\n");
		}
		use strict 'refs';
		for my $item (@$items) {
			my %menu = (
				'id' => $item->{'id'},
				'name' => $item->{'name'},
				'group' => $item->{'group'},
				'content' => $item->{'content'}
			);
			if(defined($item->{'group'}) && $item->{'group'} ne '') {
				$menu{'name'} = $item->{'group'}.'/'.$item->{'name'};
			}
			push @result,\%menu;
		}
	}
	@result = sort { $a->{'name'} cmp $b->{'name'} } @result;
	return \@result;
}

sub getCustomBrowseContextMenuTemplates {
	my $client = shift;
	my @result = ();
	if(UNIVERSAL::can("Plugins::CustomBrowse::Plugin","getMultiLibraryContextMenus")) {
		debugMsg("Getting library templates from Custom Browse\n");
		no strict 'refs';
		my $items = eval { &{"Plugins::CustomBrowse::Plugin::getMultiLibraryContextMenus"}($client) };
		if ($@) {
			debugMsg("Error getting templates: $@\n");
		}
		use strict 'refs';
		for my $item (@$items) {
			my %menu = (
				'id' => $item->{'id'},
				'name' => $item->{'name'},
				'group' => $item->{'group'},
				'content' => $item->{'content'}
			);
			if(defined($item->{'group'}) && $item->{'group'} ne '') {
				$menu{'name'} = $item->{'group'}.'/'.$item->{'name'};
			}
			push @result,\%menu;
		}
	}
	@result = sort { $a->{'name'} cmp $b->{'name'} } @result;
	return \@result;
}

sub getCustomBrowseMenus {
	my $client = shift;
	my @result = ();
	$internalMenus = getInternalMenuTemplates($client);
	$customBrowseMenus = getCustomBrowseMenuTemplates($client);

	for my $libraryid (keys %$libraries) {
		my $library = $libraries->{$libraryid};
		my $menusValue = $library->{'menus'};
		my %menus = ();
		my @menusArray = ();
		if(defined($menusValue))  {
			@menusArray = split(/\,/,$menusValue);
			for  my $menu (@menusArray) {
				$menus{$menu} = 1;
			}
		}
		my %availableMenus = ();
		for my $menu (@$internalMenus) {
			if($menus{$menu->{'id'}} || !defined($menusValue)) {
				$availableMenus{$menu->{'id'}} = $menu;
			}
		}
		for my $menu (@$customBrowseMenus) {
			if($menus{$menu->{'id'}}) {
				$availableMenus{$menu->{'id'}} = $menu;
			}
		}
		for my $menuKey (keys %availableMenus) {
			my $menu = $availableMenus{$menuKey};
			my $content = getMenuContent($library,$menu);
			my %templateItem = (
				'id' => $libraryid.'_'.$menuKey,
				'libraryid' => $libraryid,
				'libraryno' => $library->{'libraryno'},
				'libraryname' => $library->{'name'},
				'librarytype' => $menuKey,
				'type' => 'simple',
				'menu' => $content
			);
			push @result,\%templateItem;
		}
	}
	return \@result;
}

sub getCustomBrowseContextMenus {
	my $client = shift;
	my @result = ();
	$internalMenus = getInternalContextMenuTemplates($client);
	$customBrowseMenus = getCustomBrowseContextMenuTemplates($client);

	my %availableMenus = ();
	for my $menu (@$internalMenus) {
		$availableMenus{$menu->{'id'}} = $menu;
	}
	for my $menu (@$customBrowseMenus) {
		$availableMenus{$menu->{'id'}} = $menu;
	}

	for my $menuKey (keys %availableMenus) {
		my $menu = $availableMenus{$menuKey};
		my $content = getContextMenuContent($menu);
		my %templateItem = (
			'id' => $menuKey,
			'type' => 'simple',
			'menu' => $content
		);
		push @result,\%templateItem;
	}
	return \@result;
}

sub getCustomBrowseContextTemplates {
	my $client = shift;
	return Plugins::MultiLibrary::Template::Reader::getTemplates($client,'MultiLibrary','ContextMenuTemplates','xml');
}

sub getCustomBrowseContextTemplateData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;
	
	my $data = Plugins::MultiLibrary::Template::Reader::readTemplateData('MultiLibrary','ContextMenuTemplates',$templateItem->{'id'});
	return $data;
}

sub getMenuContent {
	my $library = shift;
	my $menu = shift;
	my %parameters = (
		'libraryid' => $library->{'id'},
		'libraryno' => $library->{'libraryno'},
		'libraryname' => $library->{'name'},
		'contextlibrary' => 1,
		'activelibrary' => ''
	);
	if(defined($library->{'menugroup'}) && $library->{'menugroup'} ne '') {
		$parameters{'libraryname'} = $library->{'menugroup'}.'/'.$library->{'name'};
	}
	if(defined($library->{'includedclients'})) {
		$parameters{'includedclients'} = $library->{'includedclients'};
	}else {
		$parameters{'includedclients'} = '';
	}
	if(defined($library->{'excludedclients'})) {
		$parameters{'excludedclients'} = $library->{'excludedclients'};
	}else {
		$parameters{'excludedclients'} = '';
	}
	if(defined($library->{'enabledbrowse'})) {
		if($menu->{'content'} !~ /<enabledbrowse>.*<\/enabledbrowse>/) {
			my $data = $menu->{'content'};
			$data =~ s/<template>/<enabledbrowse>{enabledbrowse}<\/enabledbrowse>\n\t<template>/m;
			$menu->{'content'} = $data;
		}
		if(ref($library->{'enabledbrowse'}) ne 'HASH') {
			$parameters{'enabledbrowse'} = $library->{'enabledbrowse'};
		}else {
			$parameters{'enabledbrowse'} = '';
		}
	}else {
		$parameters{'enabledbrowse'} = '';
	}
	if(defined($menu->{'group'}) && $menu->{'group'} ne '') {
		$parameters{'libraryname'} = $parameters{'libraryname'}."/".$menu->{'group'};
	}
	my $content = replaceParameters($menu->{'content'},\%parameters);
					
	return $content;
}

sub getContextMenuContent {
	my $menu = shift;

	my %parameters = (
		'libraryid' => '',
		'libraryno' => '',
		'contextlibrary' => 1,
		'activelibrary' => '',
		'libraryname' => '',
		'includedclients' => '',
		'excludedclients' => '',
		'enabledbrowse' => ''
	);
	my $content = replaceParameters($menu->{'content'},\%parameters);
					
	return $content;
}

sub getCustomBrowseMenuData {
	my $client = shift;
	my $menu = shift;

	if(defined($menu->{'libraryid'}) && defined($libraries->{$menu->{'libraryid'}})) {
		if(!defined($customBrowseMenus)) {
			$customBrowseMenus = getCustomBrowseMenuTemplates($client);
		}
		my $selectedMenu = undef;
		for my $m (@$customBrowseMenus) {
			if($m->{'id'} eq $menu->{'librarytype'}) {
				$selectedMenu = $m;
				last;
			}
		}
		if(!defined($selectedMenu)) {
			if(!defined($internalMenus)) {
				$internalMenus = getInternalMenuTemplates($client);
			}
			for my $m (@$internalMenus) {
				if($m->{'id'} eq $menu->{'librarytype'}) {
					$selectedMenu = $m;
					last;
				}
			}
		}
		if(defined($selectedMenu)) {
			my $library = $libraries->{$menu->{'libraryid'}};
			my $content = getMenuContent($library,$selectedMenu);
			return $content;
		}
	}
	return undef;
}

sub getCustomBrowseContextMenuData {
	my $client = shift;
	my $menu = shift;

	if(defined($menu->{'id'})) {
		if(!defined($customBrowseMenus)) {
			$customBrowseMenus = getCustomBrowseContextMenuTemplates($client);
		}
		my $selectedMenu = undef;
		for my $m (@$customBrowseMenus) {
			if($m->{'id'} eq $menu->{'id'}) {
				$selectedMenu = $m;
				last;
			}
		}
		if(!defined($selectedMenu)) {
			if(!defined($internalMenus)) {
				$internalMenus = getInternalContextMenuTemplates($client);
			}
			for my $m (@$internalMenus) {
				if($m->{'id'} eq $menu->{'id'}) {
					$selectedMenu = $m;
					last;
				}
			}
		}
		if(defined($selectedMenu)) {
			my $content = getContextMenuContent($selectedMenu);
			return $content;
		}
	}
	return undef;
}

sub initPlugin {
	$soapLiteError = 0;
	eval "use SOAP::Lite";
	if ($@) {
		my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
		for my $plugindir (@pluginDirs) {
			next unless -d catdir($plugindir,"MultiLibrary","libs");
			push @INC,catdir($plugindir,"MultiLibrary","libs");
			last;
		}
		debugMsg("Using internal implementation of SOAP::Lite\n");
		eval "use SOAP::Lite";
		if ($@) {
			$soapLiteError = 1;
			msg("MultiLibrary: ERROR! Cant load internal implementation of SOAP::Lite, download/publish functionallity will not be available\n");
		}
	}
	if(!defined($supportDownloadError) && $soapLiteError) {
		$supportDownloadError = "Could not use the internal web service implementation, please download and install SOAP::Lite manually";
	}
	checkDefaults();
	initDatabase();
	eval {
		initLibraries();
	};
	if( $@ ) {
	    	errorMsg("Startup error: $@\n");
	}		

	if(Slim::Utils::Prefs::get("plugin_multilibrary_refresh_startup")) {
		refreshLibraries();
	}
	if ( !$MULTILIBRARY_HOOK ) {
		installHook();
	}
}

sub getConfigManager {
	if(!defined($configManager)) {
		my $templateDir = Slim::Utils::Prefs::get('plugin_multilibrary_template_directory');
		if(!defined($templateDir) || !-d $templateDir) {
			$supportDownloadError = 'You have to specify a template directory before you can download libraries';
		}
		my %parameters = (
			'debugCallback' => \&debugMsg,
			'errorCallback' => \&errorMsg,
			'pluginId' => 'MultiLibrary',
			'pluginVersion' => $PLUGINVERSION,
			'downloadApplicationId' => 'MultiLibrary',
			'supportDownloadError' => $supportDownloadError,
			'addSqlErrorCallback' => \&addSQLError
		);
		$configManager = Plugins::MultiLibrary::ConfigManager::Main->new(\%parameters);
	}
	return $configManager;
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
	Slim::Control::Request::subscribe(\&Plugins::MultiLibrary::Plugin::powerCallback,[['power']]);
	$MULTILIBRARY_HOOK=1;
}

# Unhook the plugin's play event callback function. 
# Do this as the plugin shuts down, if possible.
sub uninstallHook()
{
	debugMsg("Hook deactivated.\n");
	Slim::Control::Request::unsubscribe(\&Plugins::MultiLibrary::Plugin::rescanCallback);
	Slim::Control::Request::unsubscribe(\&Plugins::MultiLibrary::Plugin::powerCallback);
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

sub powerCallback($) 
{
	debugMsg("Entering powerCallback\n");
	# These are the two passed parameters
	my $request=shift;
	my $client = $request->client();
	if(Slim::Utils::Prefs::get('plugin_multilibrary_question_startup')) {

		######################################
		## Rescan finished
		######################################
		if ( defined($client) && $request->isCommand([['power']]) )
		{
			my $power = $request->getParam('_newvalue');
			if($power) {
				debugMsg("Asking for library\n");
				Slim::Buttons::Common::pushMode($client,'PLUGIN.MultiLibrary::Plugin',undef);
				$client->update();
			}
		}
	}
	debugMsg("Exiting powerCallback\n");
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
							
							$sth = $dbh->prepare('INSERT INTO multilibrary_album (library,album) SELECT ?,tracks.album FROM tracks,multilibrary_track where tracks.id=multilibrary_track.track and multilibrary_track.library=? group by tracks.album');
							$sth->bind_param(1,$id,SQL_INTEGER);
							$sth->bind_param(2,$id,SQL_INTEGER);
							$sth->execute();
							$sth->finish();
		
							$sth = $dbh->prepare('INSERT INTO multilibrary_contributor (library,contributor) SELECT ?,contributor_track.contributor FROM tracks,contributor_track,multilibrary_track where tracks.id=multilibrary_track.track and tracks.id=contributor_track.track and multilibrary_track.library=? group by contributor_track.contributor');
							$sth->bind_param(1,$id,SQL_INTEGER);
							$sth->bind_param(2,$id,SQL_INTEGER);
							$sth->execute();
							$sth->finish();

							$sth = $dbh->prepare('INSERT INTO multilibrary_year (library,year) SELECT ?,tracks.year FROM tracks,multilibrary_track where tracks.id=multilibrary_track.track and multilibrary_track.library=? group by tracks.year');
							$sth->bind_param(1,$id,SQL_INTEGER);
							$sth->bind_param(2,$id,SQL_INTEGER);
							$sth->execute();
							$sth->finish();

							$sth = $dbh->prepare('INSERT INTO multilibrary_genre (library,genre) SELECT ?,genre_track.genre FROM tracks,genre_track,multilibrary_track where tracks.id=multilibrary_track.track and tracks.id=genre_track.track and multilibrary_track.library=? group by genre_track.genre');
							$sth->bind_param(1,$id,SQL_INTEGER);
							$sth->bind_param(2,$id,SQL_INTEGER);
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
		"webadminmethods_deleteitemtype\.(?:htm|xml)"      => \&handleWebDeleteLibraryType,
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
				selectLibrary($client,$library);
				return $libraries->{$library};
			}else {
				if(scalar(keys %$libraries)==1) {
					for my $key (keys %$libraries) {
						if(isLibraryEnabledForClient($client,$libraries->{$key})) {
							selectLibrary($client,$key);
							return $libraries->{$key};
						}
					}
				}
			}
		}	
	}
	if(defined($client)) {
		$client->prefDelete('plugin_multilibrary_activelibrary');
	}
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
	if(defined($supportDownloadError)) {
		$params->{'pluginMultiLibraryDownloadMessage'} = $supportDownloadError;
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
	$prefVal = Slim::Utils::Prefs::get('plugin_multilibrary_question_startup');
	if (! defined $prefVal) {
		Slim::Utils::Prefs::set('plugin_multilibrary_question_startup', 0);
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_multilibrary_custombrowse_menus');
	if (! defined $prefVal) {
		Slim::Utils::Prefs::set('plugin_multilibrary_custombrowse_menus', 1);
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_multilibrary_download_url');
	if (! defined $prefVal) {
		Slim::Utils::Prefs::set('plugin_multilibrary_download_url', 'http://erland.homeip.net/datacollection/services/DataCollection');
	}
}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_multilibrary_library_directory','plugin_multilibrary_template_directory','plugin_multilibrary_refresh_save','plugin_multilibrary_refresh_rescan','plugin_multilibrary_refresh_startup','plugin_multilibrary_question_startup','plugin_multilibrary_custombrowse_menus','plugin_multilibrary_showmessages'],
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
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_MULTILIBRARY_SHOW_MESSAGES')
			,'changeIntro' => string('PLUGIN_MULTILIBRARY_SHOW_MESSAGES')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_multilibrary_showmessages"); }
		},		
	plugin_multilibrary_refresh_rescan => {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_MULTILIBRARY_REFRESH_RESCAN')
			,'changeIntro' => string('PLUGIN_MULTILIBRARY_REFRESH_RESCAN')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_multilibrary_refresh_rescan"); }
		},		
	plugin_multilibrary_refresh_startup => {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_MULTILIBRARY_REFRESH_STARTUP')
			,'changeIntro' => string('PLUGIN_MULTILIBRARY_REFRESH_STARTUP')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_multilibrary_refresh_startup"); }
		},		
	plugin_multilibrary_question_startup => {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_MULTILIBRARY_QUESTION_STARTUP')
			,'changeIntro' => string('PLUGIN_MULTILIBRARY_QUESTION_STARTUP')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_multilibrary_question_startup"); }
		},		
	plugin_multilibrary_refresh_save => {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_MULTILIBRARY_REFRESH_SAVE')
			,'changeIntro' => string('PLUGIN_MULTILIBRARY_REFRESH_SAVE')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_multilibrary_refresh_save"); }
		},		
	plugin_multilibrary_custombrowse_menus => {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_MULTILIBRARY_CUSTOMBROWSE_MENUS')
			,'changeIntro' => string('PLUGIN_MULTILIBRARY_CUSTOMBROWSE_MENUS')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_multilibrary_custombrowse_menus"); }
		},		
	plugin_multilibrary_library_directory => {
			'validate' => \&Slim::Utils::Validate::isDir
			,'PrefChoose' => string('PLUGIN_MULTILIBRARY_LIBRARY_DIRECTORY')
			,'changeIntro' => string('PLUGIN_MULTILIBRARY_LIBRARY_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_multilibrary_library_directory"); }
		},
	plugin_multilibrary_template_directory => {
			'validate' => \&Slim::Utils::Validate::isDir
			,'PrefChoose' => string('PLUGIN_MULTILIBRARY_TEMPLATE_DIRECTORY')
			,'changeIntro' => string('PLUGIN_MULTILIBRARY_TEMPLATE_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_multilibrary_template_directory"); }
		},
	);
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

PLUGIN_MULTILIBRARY_TEMPLATE_DIRECTORY
	EN	Library templates directory

SETUP_PLUGIN_MULTILIBRARY_LIBRARY_DIRECTORY
	EN	Library directory

SETUP_PLUGIN_MULTILIBRARY_SHOWMESSAGES
	EN	Debugging

SETUP_PLUGIN_MULTILIBRARY_TEMPLATE_DIRECTORY
	EN	Library templates directory

PLUGIN_MULTILIBRARY_CHOOSE_BELOW
	EN	Choose a sub library of music to activate:

PLUGIN_MULTILIBRARY_EDIT_ITEM
	EN	Edit

PLUGIN_MULTILIBRARY_NEW_ITEM
	EN	Create new library

PLUGIN_MULTILIBRARY_NEW_ITEM_TYPES_TITLE
	EN	Select type of library

PLUGIN_MULTILIBRARY_EDIT_ITEM_DATA
	EN	Library Configuration

PLUGIN_MULTILIBRARY_EDIT_ITEM_NAME
	EN	Library Name

PLUGIN_MULTILIBRARY_EDIT_ITEM_FILENAME
	EN	Filename

PLUGIN_MULTILIBRARY_REMOVE_ITEM_QUESTION
	EN	Are you sure you want to delete this library ?

PLUGIN_MULTILIBRARY_REMOVE_ITEM_TYPE_QUESTION
	EN	Removing a library type might cause problems later if it is used in existing libraries, are you really sure you want to delete this library type ?

PLUGIN_MULTILIBRARY_REMOVE_ITEM
	EN	Delete

PLUGIN_MULTILIBRARY_REMOVE_ITEM_QUESTION
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

PLUGIN_MULTILIBRARY_ITEMTYPE
	EN	Customize SQL
	
PLUGIN_MULTILIBRARY_ITEMTYPE_SIMPLE
	EN	Use predefined

PLUGIN_MULTILIBRARY_ITEMTYPE_ADVANCED
	EN	Customize SQL

PLUGIN_MULTILIBRARY_NEW_ITEM_PARAMETERS_TITLE
	EN	Please enter library parameters

PLUGIN_MULTILIBRARY_EDIT_ITEM_PARAMETERS_TITLE
	EN	Please enter library parameters

PLUGIN_MULTILIBRARY_LOGIN_USER
	EN	Username

PLUGIN_MULTILIBRARY_LOGIN_PASSWORD
	EN	Password

PLUGIN_MULTILIBRARY_LOGIN_FIRSTNAME
	EN	First name

PLUGIN_MULTILIBRARY_LOGIN_LASTNAME
	EN	Last name

PLUGIN_MULTILIBRARY_LOGIN_EMAIL
	EN	e-mail

PLUGIN_MULTILIBRARY_ANONYMOUSLOGIN
	EN	Anonymous

PLUGIN_MULTILIBRARY_LOGIN
	EN	Login

PLUGIN_MULTILIBRARY_REGISTERLOGIN
	EN	Register &amp; Login

PLUGIN_MULTILIBRARY_REGISTER_TITLE
	EN	Register a new user

PLUGIN_MULTILIBRARY_LOGIN_TITLE
	EN	Login

PLUGIN_MULTILIBRARY_DOWNLOAD_ITEMS
	EN	Download more libraries

PLUGIN_MULTILIBRARY_PUBLISH_ITEM
	EN	Publish

PLUGIN_MULTILIBRARY_PUBLISH
	EN	Publish

PLUGIN_MULTILIBRARY_PUBLISHPARAMETERS_TITLE
	EN	Please specify information about the library

PLUGIN_MULTILIBRARY_PUBLISH_NAME
	EN	Name

PLUGIN_MULTILIBRARY_PUBLISH_DESCRIPTION
	EN	Description

PLUGIN_MULTILIBRARY_PUBLISH_ID
	EN	Unique identifier

PLUGIN_MULTILIBRARY_LASTCHANGED
	EN	Last changed

PLUGIN_MULTILIBRARY_PUBLISHMESSAGE
	EN	Thanks for choosing to publish your library. The advantage of publishing a library is that other users can use it and it will also be used for ideas of new functionallity in the Multi Library plugin. Publishing a library is also a great way of improving the functionality in the Multi Library plugin by showing the developer what types of libraries you use, besides those already included with the plugin.

PLUGIN_MULTILIBRARY_REGISTERMESSAGE
	EN	You can choose to publish your library either anonymously or by registering a user and login. The advantage of registering is that other people will be able to see that you have published the library, you will get credit for it and you will also be sure that no one else can update or change your published library. The e-mail adress will only be used to contact you if I have some questions to you regarding one of your libraries, it will not show up on any web pages. If you already have registered a user, just hit the Login button.

PLUGIN_MULTILIBRARY_LOGINMESSAGE
	EN	You can choose to publish your library either anonymously or by registering a user and login. The advantage of registering is that other people will be able to see that you have published the library, you will get credit for it and you will also be sure that no one else can update or change your published library. Hit the &quot;Register &amp; Login&quot; button if you have not previously registered.

PLUGIN_MULTILIBRARY_PUBLISHMESSAGE_DESCRIPTION
	EN	It is important that you enter a good description of your library, describe what your library do and if it is based on one of the existing libraries it is a good idea to mention this and describe which extensions you have made. <br><br>It is also a good idea to try to make the &quot;Unique identifier&quot; as uniqe as possible as this will be used for filename when downloading the library. This is especially important if you have choosen to publish your library anonymously as it can easily be overwritten if the identifier is not unique. Please try to not use spaces and language specific characters in the unique identifier since these could cause problems on some operating systems.

PLUGIN_MULTILIBRARY_REFRESH_DOWNLOADED_ITEMS
	EN	Download last version of existing libraries

PLUGIN_MULTILIBRARY_DOWNLOAD_TEMPLATE_OVERWRITE_WARNING
	EN	A library type with that name already exists, please change the name or select to overwrite the existing library type

PLUGIN_MULTILIBRARY_DOWNLOAD_TEMPLATE_OVERWRITE
	EN	Overwrite existing

PLUGIN_MULTILIBRARY_PUBLISH_OVERWRITE
	EN	Overwrite existing

PLUGIN_MULTILIBRARY_DOWNLOAD_TEMPLATE_NAME
	EN	Unique identifier

PLUGIN_MULTILIBRARY_EDIT_ITEM_OVERWRITE
	EN	Overwrite existing

PLUGIN_MULTILIBRARY_DOWNLOAD_ITEMS
	EN	Download more libraries

PLUGIN_MULTILIBRARY_DOWNLOAD_QUESTION
	EN	This operation will download latest version of all libraries, this might take some time. Please note that this will overwrite any local changes you have made in built-in or previously downloaded library types. Are you sure you want to continue ?

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

PLUGIN_MULTILIBRARY_CUSTOMBROWSE_MENUS
	EN	Selectable Custom Browse menus

SETUP_PLUGIN_MULTILIBRARY_CUSTOMBROWSE_MENUS
	EN	Custom Browse menus

PLUGIN_MULTILIBRARY_QUESTION_STARTUP
	EN	Ask for library at startup

SETUP_PLUGIN_MULTILIBRARY_QUESTION_STARTUP
	EN	Ask for library

PLUGIN_MULTILIBRARY_REFRESH_SAVE
	EN	Refresh libraries after library has been save

SETUP_PLUGIN_MULTILIBRARY_REFRESH_SAVE
	EN	Refresh on save

PLUGIN_MULTILIBRARY_SELECT
	EN	Select a library
EOF

}

1;

__END__
