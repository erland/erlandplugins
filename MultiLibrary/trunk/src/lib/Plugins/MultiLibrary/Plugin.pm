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

use Plugins::MultiLibrary::ConfigManager::Main;
use Plugins::MultiLibrary::Template::Reader;

use Plugins::MultiLibrary::Settings;

use Slim::Schema;

my $prefs = preferences('plugin.multilibrary');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.multilibrary',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_MULTILIBRARY',
});
my $driver;

$prefs->migrate(1, sub {
	$prefs->set('library_directory', Slim::Utils::Prefs::OldPrefs->get('plugin_multilibrary_library_directory') || $serverPrefs->get('playlistdir')  );
	$prefs->set('template_directory',  Slim::Utils::Prefs::OldPrefs->get('plugin_multilibrary_template_directory')   || ''  );
	$prefs->set('download_url',  Slim::Utils::Prefs::OldPrefs->get('plugin_multilibrary_download_url')   || 'http://erland.homeip.net/datacollection/services/DataCollection'  );
	$prefs->set('question_startup', Slim::Utils::Prefs::OldPrefs->get('plugin_multilibrary_question_startup') || 0);
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_multilibrary_refresh_startup'))) {
		$prefs->set('refresh_startup', Slim::Utils::Prefs::OldPrefs->get('plugin_multilibrary_refresh_startup'));
	}
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_multilibrary_refresh_rescan'))) {
		$prefs->set('refresh_rescan', Slim::Utils::Prefs::OldPrefs->get('plugin_multilibrary_refresh_rescan'));
	}
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_multilibrary_refresh_save'))) {
		$prefs->set('refresh_save', Slim::Utils::Prefs::OldPrefs->get('plugin_multilibrary_refresh_save'));
	}
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_multilibrary_custombrowse_menus'))) {
		$prefs->set('custombrowse_menus', Slim::Utils::Prefs::OldPrefs->get('plugin_multilibrary_custombrowse_menus'));
	}
	if(defined(Slim::Utils::Prefs::OldPrefs->get('plugin_multilibrary_utf8filenames'))) {
		$prefs->set('utf8filenames', Slim::Utils::Prefs::OldPrefs->get('plugin_multilibrary_utf8filenames'));
	}
	1;
});
$prefs->setValidate('dir', 'library_directory'  );
$prefs->setValidate('dir', 'template_directory'  );

# Information on each clients multilibrary
my $htmlTemplate = 'plugins/MultiLibrary/multilibrary_list.html';
my $libraries = undef;
my $sqlerrors = '';
my %currentLibrary = ();
my $PLUGINVERSION = undef;
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
		return [$client->symbols('notesymbol'), $client->symbols('rightarrow')];
	}else {
		return [undef, $client->symbols('rightarrow')];
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
	my $class = shift;
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
			$log->debug("Do nothing on add\n");
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
		$client = UNIVERSAL::can(ref($client),"masterOrSelf")?$client->masterOrSelf():$client->master();
		$key = $client;
	}
	if(defined($key) && defined($libraryId) && defined($libraries->{$libraryId})) {
		$currentLibrary{$key} = $libraryId;
		$prefs->client($client)->set('activelibrary',$libraryId);
		$prefs->client($client)->set('activelibraryno',$libraries->{$libraryId}->{'libraryno'});
		if($showUser) {
			$client->showBriefly({
				'line'    => [ $client->string( 'PLUGIN_MULTILIBRARY'), 
						$client->string( 'PLUGIN_MULTILIBRARY_ACTIVATING_LIBRARY').": ".$libraries->{$libraryId}->{'name'} ],
				},1);
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
						$log->debug("Executing action: ".$action->{'type'}.", ".$action->{'data'}."\n");
						my @parts = split(/ /,$action->{'data'});
						my $request = $client->execute(\@parts);
						$request->source('PLUGIN_MULTILIBRARY');
					};
					if ($@) {
						$log->warn("MultiLibrary: Failed to execute action:".$action->{'type'}.", ".$action->{'data'}.":$@\n");
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

	for my $libraryid (keys %$localLibraries) {
		$localLibraries->{$libraryid}->{'libraryno'} = initDatabaseLibrary($localLibraries->{$libraryid});
	}

	$libraries = $localLibraries;

}

sub initDatabaseLibrary {
	my $library = shift;

	my $dbh = getCurrentDBH();
	my $sth = $dbh->prepare("select id from multilibrary_libraries where libraryid=?");
	$sth->bind_param(1,$library->{'id'},SQL_VARCHAR);
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
		$sth->bind_param(1,$library->{'id'},SQL_VARCHAR);
		$sth->bind_param(2,$library->{'name'},SQL_VARCHAR);
		$sth->execute();
		$sth->finish();
		$sth = $dbh->prepare("select id from multilibrary_libraries where libraryid=?");
		$sth->bind_param(1,$library->{'id'},SQL_VARCHAR);
		$sth->execute();
		$sth->bind_col(1, \$id);
		$sth->fetch();
	}
	return $id;
}

sub getLibraryTrackCount {
	my $library = shift;

	my $dbh = getCurrentDBH();
	my $sth = $dbh->prepare("select count(*) from multilibrary_track where library=?");
	$sth->bind_param(1,$library->{'libraryno'},SQL_VARCHAR);
	$sth->execute();
		
	my $count = 0;
	$sth->bind_col(1, \$count);
	$sth->fetch();
	return $count;
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
	if($prefs->get('custombrowse_menus')) {
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
		$log->debug("Getting library templates from Custom Browse\n");
		no strict 'refs';
		my $items = eval { &{"Plugins::CustomBrowse::Plugin::getMultiLibraryMenus"}($client) };
		if ($@) {
			$log->warn("Error getting templates: $@\n");
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
		$log->debug("Getting library templates from Custom Browse\n");
		no strict 'refs';
		my $items = eval { &{"Plugins::CustomBrowse::Plugin::getMultiLibraryContextMenus"}($client) };
		if ($@) {
			$log->warn("Error getting templates: $@\n");
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
	return Plugins::MultiLibrary::Template::Reader::getTemplates($client,'MultiLibrary',$PLUGINVERSION,'FileCache/CustomBrowse','ContextMenuTemplates','xml');
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
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	Plugins::MultiLibrary::Settings->new($class);

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
	if ( !$MULTILIBRARY_HOOK ) {
		installHook();
	}
	addTitleFormat('TRACKNUM. ARTIST - TITLE (MULTILIBRARIES)');
	addTitleFormat('TRACKNUM. TITLE (MULTILIBRARIES)');
	addTitleFormat('PLAYING (X_OF_Y) MULTILIBRARIES');
	addTitleFormat('MULTILIBRARIES');
	Slim::Music::TitleFormatter::addFormat('MULTILIBRARIES',\&getTitleFormat);
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
	$log->debug("Adding: $titleformat");
	push @$titleFormats,$titleformat;
	$serverPrefs->set('titleFormat',$titleFormats);
}

sub getMusicInfoSCRCustomItems {
	my $customFormats = {
		'ACTIVEMULTILIBRARY' => {
			'cb' => \&getTitleFormatActive,
			'cache' => 5,
		},
	};
	return $customFormats;
}

sub getTitleFormatActive
{
	my $client = shift;
	my $song = shift;
	my $tag = shift;

	$log->debug("Entering getTitleFormatActive");
	my $library = getCurrentLibrary($client);

	if($library) {
		$log->debug("Exiting getTitleFormatActive with ".$library->{'name'});
		return $library->{'name'};
	}

	$log->debug("Exiting getTitleFormatActive with undef");
	return undef;
}

sub getTitleFormat
{
	my $song = shift;
	if(ref($song) eq 'HASH') {
		return undef;
	}

	$log->debug("Entering getTitleFormat");

	my $dbh = getCurrentDBH();
	my $sth = $dbh->prepare("select libraryid from multilibrary_libraries,multilibrary_track where multilibrary_track.track=? and multilibrary_track.library=multilibrary_libraries.id order by multilibrary_libraries.name");
	$sth->bind_param(1,$song->id,SQL_INTEGER);
	$sth->execute();
		
	my $type;
	$sth->bind_col(1, \$type);
	my $libraries = undef;
	while($sth->fetch()) {
		my $library = getLibrary(undef,$type);
		if(defined $library) {
			if(defined $libraries) {
				$libraries.=',';
			}else {
				$libraries ='';
			}
			$libraries .= $library->{'name'};
	}	}
	$sth->finish();
	if(defined $libraries) {
		$log->debug("Exiting getTitleFormat with ".$libraries);
		return $libraries;
	}

	$log->debug("Exiting getTitleFormat with undef");
	return undef;
}

sub getConfigManager {
	if(!defined($configManager)) {
		my %parameters = (
			'logHandler' => $log,
			'pluginPrefs' => $prefs,
			'pluginId' => 'MultiLibrary',
			'pluginVersion' => $PLUGINVERSION,
			'downloadApplicationId' => 'MultiLibrary',
			'addSqlErrorCallback' => \&addSQLError,
			'downloadVersion' => 2,
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
	$log->debug("Hook activated.\n");
	Slim::Control::Request::subscribe(\&Plugins::MultiLibrary::Plugin::rescanCallback,[['rescan']]);
	Slim::Control::Request::subscribe(\&Plugins::MultiLibrary::Plugin::powerCallback,[['power']]);
	$MULTILIBRARY_HOOK=1;
}

# Unhook the plugin's play event callback function. 
# Do this as the plugin shuts down, if possible.
sub uninstallHook()
{
	$log->debug("Hook deactivated.\n");
	Slim::Control::Request::unsubscribe(\&Plugins::MultiLibrary::Plugin::rescanCallback);
	Slim::Control::Request::unsubscribe(\&Plugins::MultiLibrary::Plugin::powerCallback);
	$MULTILIBRARY_HOOK=0;
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

sub powerCallback($) 
{
	$log->debug("Entering powerCallback\n");
	# These are the two passed parameters
	my $request=shift;
	my $client = $request->client();
	if($prefs->get('question_startup')) {

		######################################
		## Rescan finished
		######################################
		if ( defined($client) && $request->isCommand([['power']]) )
		{
			my $power = $request->getParam('_newvalue');
			if($power && scalar(keys %$libraries)>0) {
				#Ask for library unless the player is powered on due to an alarm
				if(!$request->source() || $request->source() ne 'ALARM') {
					$log->debug("Asking for library\n");
					Slim::Buttons::Common::pushMode($client,'Plugins::MultiLibrary::Plugin',undef);
					$client->update();
				}
			}
		}
	}
	$log->debug("Exiting powerCallback\n");
}

sub refreshLibraries {
	$log->info("MultiLibrary: Synchronizing libraries data, please wait...\n");
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
		my @sortedLibraries = ();
		for my $key (keys %$libraries) {
			push @sortedLibraries,$libraries->{$key};
		}
		@sortedLibraries = sort { 
			if(defined($a->{'libraryorder'}) && defined($b->{'libraryorder'})) {
				if($a->{'libraryorder'}!=$b->{'libraryorder'}) {
					return $a->{'libraryorder'} <=> $b->{'libraryorder'};
				}
			}
			if(defined($a->{'libraryorder'}) && !defined($b->{'libraryorder'})) {
				if($a->{'libraryorder'}!=50) {
					return $a->{'libraryorder'} <=> 50;
				}
			}
			if(!defined($a->{'libraryorder'}) && defined($b->{'libraryorder'})) {
				if($b->{'libraryorder'}!=50) {
					return 50 <=> $b->{'libraryorder'};
				}
			}
			return $a->{'libraryorder'} cmp $b->{'libraryorder'} 
		} @sortedLibraries;
		
		for my $library (@sortedLibraries) {
			eval {
				$log->debug("Checking library ".$library->{'id'}."\n");
				my $id = initDatabaseLibrary($library);
				if(defined($id)) {
					$log->debug("Deleting data for library $id\n");
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
							$log->debug("Adding new data for library ".$library->{'id'}.", running $sql\n");
							my %keywords = (
								'library' => $id
							);
							$sql = replaceParameters($sql,\%keywords);
							$sth = $dbh->prepare('INSERT INTO multilibrary_track (library,track) '.$sql);
							my $noOfTracks = $sth->execute();
							if($noOfTracks eq '0E0') {
								$noOfTracks = 0;
							}
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
							$log->debug("Added $noOfTracks songs to the library\n");
						}
					}
				}
			};
			if( $@ ) {
			    	$log->warn("Database error: $DBI::errstr\n$@\n");
			}		
		}
	};
	if( $@ ) {
	    $log->warn("Database error: $DBI::errstr\n$@\n");
	}		
	$log->info("MultiLibrary: Synchronization finished\n");
}


sub replaceParameters {
    my $originalValue = shift;
    my $parameters = shift;
    my $dbh = getCurrentDBH();

    if(defined($parameters)) {
        for my $param (keys %$parameters) {
            my $value = encode_entities($parameters->{$param},"&<>\'\"");
#	    $value = Slim::Utils::Unicode::utf8on($value);
#	    $value = Slim::Utils::Unicode::utf8encode_locale($value);
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
	$log->debug("Checking if multilibrary_track database table exists\n");
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
						updateCharSet("multilibrary_track",$charset,$collate);
						updateCharSet("multilibrary_album",$charset,$collate);
						updateCharSet("multilibrary_contributor",$charset,$collate);
						updateCharSet("multilibrary_libraries",$charset,$collate);
					}
				}
			}
		};
		if( $@ ) {
		    $log->warn("Database error: $DBI::errstr\n");
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
			if($charset ne $table_charset || ($collate && (!$table_collate || $collate ne $table_collate)) || (!$collate && $table_collate)) {
				$log->warn("Converting $table to correct charset=$charset collate=$collate\n");
				if(!$collate) {
					eval { $dbh->do("alter table $table convert to character set $charset") };
				}else {
					eval { $dbh->do("alter table $table convert to character set $charset collate $collate") };
				}
				if ($@) {
					$log->warn("Couldn't convert charsets: $@\n");
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
		opendir(DIR, catdir($plugindir,"MultiLibrary")) || next;
       		$sqlFile = catdir($plugindir,"MultiLibrary", "SQL", $driver, $file);
       		closedir(DIR);
       	}

        $log->debug("Executing SQL file $sqlFile\n");

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


                        $log->debug("Executing SQL statement: [$statement]\n");

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
		"MultiLibrary/multilibrary_list\.(?:htm|xml)"     => \&handleWebList,
		"MultiLibrary/multilibrary_refreshlibraries\.(?:htm|xml)"     => \&handleWebRefreshLibraries,
                "MultiLibrary/webadminmethods_edititem\.(?:htm|xml)"     => \&handleWebEditLibrary,
                "MultiLibrary/webadminmethods_saveitem\.(?:htm|xml)"     => \&handleWebSaveLibrary,
                "MultiLibrary/webadminmethods_savesimpleitem\.(?:htm|xml)"     => \&handleWebSaveSimpleLibrary,
                "MultiLibrary/webadminmethods_savenewitem\.(?:htm|xml)"     => \&handleWebSaveNewLibrary,
                "MultiLibrary/webadminmethods_savenewsimpleitem\.(?:htm|xml)"     => \&handleWebSaveNewSimpleLibrary,
                "MultiLibrary/webadminmethods_removeitem\.(?:htm|xml)"     => \&handleWebRemoveLibrary,
                "MultiLibrary/webadminmethods_newitemtypes\.(?:htm|xml)"     => \&handleWebNewLibraryTypes,
                "MultiLibrary/webadminmethods_newitemparameters\.(?:htm|xml)"     => \&handleWebNewLibraryParameters,
                "MultiLibrary/webadminmethods_newitem\.(?:htm|xml)"     => \&handleWebNewLibrary,
		"MultiLibrary/webadminmethods_login\.(?:htm|xml)"      => \&handleWebLogin,
		"MultiLibrary/webadminmethods_downloadnewitems\.(?:htm|xml)"      => \&handleWebDownloadNewLibraries,
		"MultiLibrary/webadminmethods_downloaditems\.(?:htm|xml)"      => \&handleWebDownloadLibraries,
		"MultiLibrary/webadminmethods_downloaditem\.(?:htm|xml)"      => \&handleWebDownloadLibrary,
		"MultiLibrary/webadminmethods_publishitemparameters\.(?:htm|xml)"      => \&handleWebPublishLibraryParameters,
		"MultiLibrary/webadminmethods_publishitem\.(?:htm|xml)"      => \&handleWebPublishLibrary,
		"MultiLibrary/webadminmethods_deleteitemtype\.(?:htm|xml)"      => \&handleWebDeleteLibraryType,
		"MultiLibrary/multilibrary_selectlibrary\.(?:htm|xml)"      => \&handleWebSelectLibrary,
	);

	for my $page (keys %pages) {
		if(UNIVERSAL::can("Slim::Web::Pages","addPageFunction")) {
			Slim::Web::Pages->addPageFunction($page, $pages{$page});
		}else {
			Slim::Web::HTTP::addPageFunction($page, $pages{$page});
		}
	}
	Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_MULTILIBRARY' => 'plugins/MultiLibrary/multilibrary_list.html' });
}

sub getCurrentLibrary {
	my $client = shift;
	if(defined($client)) {
		$client = UNIVERSAL::can(ref($client),"masterOrSelf")?$client->masterOrSelf():$client->master();
		if(!$libraries) {
			initLibraries();
		}
		my $key = $client;
		if(defined($currentLibrary{$key}) && defined($libraries->{$currentLibrary{$key}}) && isLibraryEnabledForClient($client,$libraries->{$currentLibrary{$key}})) {
			return $libraries->{$currentLibrary{$key}};
		}else {
			my $library = $prefs->client($client)->get('activelibrary');
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
		$prefs->client($client)->delete('activelibrary');
	}
	return undef;
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	# Pass on the current pref values and now playing info
	if(!defined($params->{'donotrefresh'})) {
		if(defined($params->{'cleancache'}) && $params->{'cleancache'}) {
			my $cache = Slim::Utils::Cache->new("FileCache/MultiLibrary");
			$cache->clear();
		}
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
		$weblibrary{'nooftracks'} = getLibraryTrackCount($lib);

		push @weblibraries,\%weblibrary;
	}
	@weblibraries = sort { $a->{'name'} cmp $b->{'name'} } @weblibraries;

	$params->{'pluginMultiLibraryLibraries'} = \@weblibraries;
	$params->{'pluginMultiLibraryActiveLibrary'} = $library;
	my $templateDir = $prefs->get('template_directory');
	if(!defined($templateDir) || !-d $templateDir) {
		$params->{'pluginMultiLibraryDownloadMessage'} = 'You have to specify a template directory before you can download libraries';
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
	my $prefVal = $prefs->get('library_directory');
	if (! defined $prefVal) {
		# Default to standard library directory
		my $dir=$serverPrefs->get('playlistdir');
		$log->debug("Defaulting plugin_multilibrary_library_directory to:$dir\n");
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
	$prefVal = $prefs->get('question_startup');
	if (! defined $prefVal) {
		$prefs->set('question_startup', 0);
	}
	$prefVal = $prefs->get('custombrowse_menus');
	if (! defined $prefVal) {
		$prefs->set('custombrowse_menus', 1);
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
