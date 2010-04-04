# 				Song Info plugin 
#
#    Copyright (c) 2010 Erland Isaksson (erland_i@hotmail.com)
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

use strict;
use warnings;
                   
package Plugins::SongInfo::Plugin;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);

use LWP::UserAgent;
use JSON::XS;
use Data::Dumper;
use Plugins::SongInfo::Modules::LastFM;
use Plugins::SongInfo::ModuleSettings;

my $prefs = preferences('plugin.songinfo');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.songinfo',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_SONGINFO',
});

my $PLUGINVERSION = undef;

#$prefs->migrate(1,sub {
#	my @empty = ();
#	$prefs->set('titleformats',\@empty)
#});

sub getDisplayName()
{
	return string('PLUGIN_SONGINFO'); 
}

sub initPlugin
{
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	Plugins::SongInfo::ModuleSettings->new($class);
	Slim::Control::Request::addDispatch(['songinfoitems','_module'], [1, 1, 1, \&getSongInfo]);
	Slim::Control::Request::addDispatch(['songinfomodules'], [0, 1, 1, \&getSongInfoModules]);
	Slim::Control::Request::addDispatch(['songinfomenu'], [0, 1, 1, \&getSongInfoMenu]);
}

sub postinitPlugin
{
	my @trackItems = ();
	my @artistItems = ();
	my @albumItems = ();
	my $modules = getInformationModules();
	for my $key (keys %$modules) {
		my $module = $modules->{$key};
		if($module->{'type'} eq 'text' || $module->{'type'} eq 'image') {
			if($module->{'context'} eq 'track') {
				push @trackItems,$module;
			}elsif($module->{'context'} eq 'artist') {
				push @artistItems,$module;
			}elsif($module->{'context'} eq 'album') {
				push @albumItems,$module;
			}
		}
	}
	if(scalar(@trackItems)>0) {
		for my $item (@trackItems) {
			my $id = $item->{'id'};
			my $itemid = "songinfo".$item->{'id'};
			Slim::Menu::TrackInfo->registerInfoProvider( $itemid => (
				after => 'middle',
				func => sub {
					return objectInfoHandler(@_,$id);
				}
			));
		}
	}
	if(scalar(@albumItems)>0) {
		for my $item (@albumItems) {
			my $id = $item->{'id'};
			my $itemid = "songinfo".$item->{'id'};
			Slim::Menu::AlbumInfo->registerInfoProvider( $itemid => (
				after => 'middle',
				func => sub {
					return objectInfoHandler(@_,$id);
				}
			));
		}
	}
	if(scalar(@artistItems)>0) {
		for my $item (@artistItems) {
			my $id = $item->{'id'};
			my $itemid = "songinfo".$item->{'id'};
			Slim::Menu::ArtistInfo->registerInfoProvider( $itemid => (
				after => 'middle',
				func => sub {
					return objectInfoHandler(@_,$id);
				}
			));
		}
	}
}

sub webPages {
	my %pages = (
		"SongInfo/viewinfo\.html" => \&handleViewInfo,
	);
	
	for my $page (keys %pages) {
		Slim::Web::Pages->addPageFunction($page, $pages{$page});
	}
}

sub handleViewInfo {
	my ($client, $params, $callback, $httpClient, $response) = @_;

  	my $moduleId    = $params->{'module'};
	my $modules = getInformationModules();
	if(defined($modules->{$moduleId})) {
		my $module = $modules->{$moduleId};
		my $context = $module->{'context'};
		my $type = $module->{'type'};

		$params->{'pluginSongInfoModuleName'} = $module->{'name'};
		$log->debug("Getting $type menu $moduleId for $context=".$params->{$context});
		my $requestParams = {
			module => $moduleId,
			$context => $params->{$context},
		};
		
		my $callbackParams = {
			callback => $callback,
			httpClient => $httpClient,
			response => $response,
			params => $params,
		};
		if($module->{'type'} eq 'image') {
			executeSongInfoRequest($client, $params, \&webResponseImages,undef,$callbackParams);
			return undef;
		}else {
			executeSongInfoRequest($client, $params, \&webResponseText,undef,$callbackParams);
			return undef;
		}
	}
	return undef;
}

sub webResponseImages {
	my $client = shift;
	my $params = shift;
	my $result = shift;
	$params = $params->{callbackParams};

	my $webParams = $params->{params};

	my $cnt = 0;
	
	my @items = ();
	for my $item (@$result) {
		push @items, {
			text => $item->{'text'},
			image => $item->{'url'},
		};
		$cnt++;
	}
	$webParams->{pluginSongInfoItems} = \@items;
	
	my $output = Slim::Web::HTTP::filltemplatefile('plugins/SongInfo/viewimages.html', $webParams);

	$params->{callback}->($client,$params->{params},$output,$params->{httpClient},$params->{response});	
}

sub webResponseText {
	my $client = shift;
	my $params = shift;
	my $result = shift;
	$params = $params->{callbackParams};
	my $webParams = $params->{params};

	my $cnt = 0;
	
	my @items = ();
	for my $item (@$result) {
		push @items, {
			text => $item->{'text'},
		};
		$cnt++;
	}
	$webParams->{pluginSongInfoItems} = \@items;
	
	my $output = Slim::Web::HTTP::filltemplatefile('plugins/SongInfo/viewtext.html', $webParams);

	$params->{callback}->($client,$params->{params},$output,$params->{httpClient},$params->{response});	
}

sub setMode {
	my ($class, $client, $method) = @_;

	if($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	# get our parameters
  	my $moduleId    = $client->modeParam('module');
	my $modules = getInformationModules();
	if(defined($modules->{$moduleId})) {
		my $module = $modules->{$moduleId};
		my $context = $module->{'context'};
		my $type = $module->{'type'};

		$log->debug("Getting $type menu $moduleId for $context=".$client->modeParam($context));
		my $params = {
			module => $moduleId,
			$context => $client->modeParam($context),
		};
		
		if($module->{'type'} eq 'text') {
			executeSongInfoRequest($client, $params, \&playerResponseTextArea);
		}
	}
}

sub playerResponseTextArea {
	my $client = shift;
	my $params = shift;
	my $result = shift;

	my $request = $params->{'request'};
	my $cnt = 0;
	
	my @listRef;
	for my $item (@$result) {
		push @listRef,$item->{'text'};
		$cnt++;
	}
	if(scalar(@listRef)==0) {
		push @listRef,string('PLUGIN_SONGINFO_NOT_AVAILABLE'); 
	}

	my %params = (
		header => '{PLUGIN_SONGINFO}',
		headerAddCount => 1,
		listRef => \@listRef,
		name => \&getDisplayText,
		modeName => 'SongInfo',
	);
	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice',\%params);
}

sub getDisplayText {
	my ($client, $item) = @_;

	return $item;
}
sub objectInfoHandler {
        my ( $client, $url, $obj, $remoteMeta, $tags, $moduleId) = @_;
        $tags ||= {};
	my $modules = getInformationModules();
	my $module = $modules->{$moduleId};
	$log->debug("Requesting $moduleId sub menu: ".$module->{'name'});

	my $jive = undef;
	my $context = $module->{'context'};
	my $player = undef;
	my $web = undef;
	if($tags->{menuMode}) {
		if(!$module->{'jivemenu'}) {
			return undef;
		}
		my $actions = {
			go => {
				player => 0,
				cmd => ['songinfomenu'],
				params => {
					module => $moduleId,
					$context => $obj->id,
				},
			},
		};
		$jive->{actions} = $actions;
		if($module->{'type'} eq 'image') {
			$jive->{'window'} = {
				menuStyle => 'album',
			}
		}
	}elsif($module->{'type'} eq 'text') {
		if($module->{'playermenu'}) {
			$player = {
				mode => 'Plugins::SongInfo::Plugin',
				modeParams => {
					'module' => $moduleId,
					$context => $obj->id,
				},
			}
		}
		if($module->{'webmenu'}) {
			$web = {
				url => "plugins/SongInfo/viewinfo.html?module=$moduleId&$context=".$obj->id
			};
		}
	}elsif($module->{'type'} eq 'image') {
		if($module->{'webmenu'}) {
			$web = {
				url => "plugins/SongInfo/viewinfo.html?module=$moduleId&$context=".$obj->id
			};
		}
	}else {
		return undef;
	}
	my $result = {
		type => 'redirect',
		name => $module->{'name'},
		favorites => 0,
	};
	if($player) {
		$result->{player} = $player;
	}
	if($jive) {
		$result->{jive} = $jive;
	}
	if($web) {
		$result->{web} = $web;
	}
	return $result;
}
sub getInformationModules {
	my %items = ();

	for my $plugin (qw(LastFM)) {
		no strict 'refs';
		my $fullname = "Plugins::SongInfo::Modules::$plugin";
		if(UNIVERSAL::can("${fullname}","getSongInfoFunctions")) {
			my $data = eval { &{"${fullname}::getSongInfoFunctions"}($PLUGINVERSION); };
			if ($@) {
				$log->error("SongInfo: Failed to call module $fullname: $@\n");
			}elsif(defined($data)) {
				for my $key (keys %$data) {
					my $item = $data->{$key};
					if(defined($item->{'name'})) {
						if(!defined($data->{'minpluginversion'}) || isAllowedVersion($data->{'minpluginversion'})) {
							$items{$key} = $item;
							$items{$key}->{'id'} = $key;
							$items{$key}->{'plugin'} = $fullname;
						}
					}
				}
			}
		}
		use strict 'refs';
	}

	my @enabledplugins = Slim::Utils::PluginManager->enabledPlugins();
	for my $plugin (@enabledplugins) {
		my $fullname = "$plugin";
		no strict 'refs';
		eval "use $fullname";
		if ($@) {
			$log->error("SongInfo: Failed to load module $fullname: $@\n");
		}elsif(UNIVERSAL::can("${fullname}","getSongInfoFunctions")) {
			my $data = eval { &{$fullname . "::getSongInfoFunctions"}($PLUGINVERSION); };
			if ($@) {
				$log->error("SongInfo: Failed to call module $fullname: $@\n");
			}elsif(defined($data)) {
				for my $key (keys %$data) {
					my $item = $data->{$key};
					if(defined($item->{'name'})) {
						if(!defined($data->{'minpluginversion'}) || isAllowedVersion($data->{'minpluginversion'})) {
							$items{$key} = $item;
							$items{$key}->{'id'} = $key;
							$items{$key}->{'plugin'} = $fullname;
						}
					}
				}
			}
		}
		use strict 'refs';
	}
	return \%items;
}


sub getSongInfoMenu {
	my $request = shift;
	my $client = $request->client();
	
	# get our parameters
  	my $moduleId    = $request->getParam('module');
	my $modules = getInformationModules();
	if(defined($modules->{$moduleId})) {
		my $module = $modules->{$moduleId};
		my $context = $module->{'context'};
		my $type = $module->{'type'};

		$log->debug("Getting $type menu $moduleId for $context=".$request->getParam($context));
		
		my $params = $request->getParamsCopy();
		if($module->{'type'} eq 'text') {
			executeSongInfoRequest($client, $params,\&cliResponseTextArea,$request);
		}else {
			executeSongInfoRequest($client, $params,\&cliResponseImages,$request);
		}
	}else {
		$request->setStatusDone();
	}
}

sub cliResponseTextArea {
	my $client = shift;
	my $params = shift;
	my $result = shift;

	my $request = $params->{'request'};
	my $cnt = 0;
	
	my $text = '';
	for my $item (@$result) {
		if($text ne '') {
			$text .= "\n";
		}
		$text .= $item->{'text'};
		$cnt++;
	}
	if($text eq '') {
		$text = string('PLUGIN_SONGINFO_NOT_AVAILABLE'); 
	}
	$request->addResult('window', {
		textarea => $text,
	});
	$request->addResult('offset',0);
	$request->addResult('count',0);
	$request->setStatusDone();
}

sub cliResponseImages {
	my $client = shift;
	my $params = shift;
	my $result = shift;

	my $request = $params->{'request'};
	my $cnt = 0;
	
	my @items = ();
	for my $item (@$result) {
		push @items, {
			text => $item->{'text'},
			icon => $item->{'url'},
			showBigArtwork => 1,
			actions => {
				do => {
					cmd => ['artwork',$item->{'url'}]
				},
			},
			style => 'item',
		};
		$cnt++;
	}
	$request->addResult('window', {
		menustyle => 'album',
	});
	$request->addResult('item_loop',\@items);
	$request->addResult('offset',0);
	$request->addResult('count',$cnt);
	$request->setStatusDone();
}

sub getSongInfo {
	my $request = shift;
	my $client = $request->client();
	
	my $params = $request->getParamsCopy();
	executeSongInfoRequest($client, $params, \&cliResponse, $request);
}

sub executeSongInfoRequest {
	my $client = shift;
	my $params = shift;
	my $callback = shift;
	my $request = shift;
	my $callbackParams = shift;

	# get our parameters
  	my $module    = $params->{'_module'}||$params->{'module'};
	my $modules = getInformationModules();
	if(defined($modules->{$module})) {
		my $obj = undef;
		my $context = "";
		my $trackId = $params->{'track'};
		if($modules->{$module}->{'context'} eq 'album') {
			my $albumId = $params->{'album'};
			if(!defined($albumId)) {
				my $track = undef;
				if(defined($trackId)) {
					$track = Slim::Schema->resultset('Track')->find($trackId);
				}else {
					$track = Slim::Player::Playlist::song($client);
				}
				if(defined($track)) {
					$obj = $track->album();
				}
			}else {
				$obj = Slim::Schema->resultset('Album')->find($albumId);
			}
			if(defined($obj)) {
				$context = "album=".$obj->title;
			}else {
				$context = "album";
			}
		}elsif($modules->{$module}->{'context'} eq 'artist') {
			my $artistId = $params->{'artist'};
			if(!defined($artistId)) {
				my $track = undef;
				if(defined($trackId)) {
					$track = Slim::Schema->resultset('Track')->find($trackId);
				}else {
					$track = Slim::Player::Playlist::song($client);
				}
				if(defined($track)) {
					$obj = $track->artist();
				}
			}else {
				$obj = Slim::Schema->resultset('Contributor')->find($artistId);
			}
			if(defined($obj)) {
				$context = "artist=".$obj->name;
			}else {
				$context = "artist";
			}
		}elsif($modules->{$module}->{'context'} eq 'track') {
			if(!defined($trackId)) {
				$obj = Slim::Player::Playlist::song($client);
			}else {
				$obj = Slim::Schema->resultset('Track')->find($trackId);
			}
			if(defined($obj)) {
				$context = "track=".$obj->title;
			}else {
				$context = "track";
			}
		}

		if(defined($obj)) {
			no strict 'refs';
			eval { 
				if($request) {
					$request->setStatusProcessing();
				}
				&{$modules->{$module}->{'function'}}($client,$callback,\&cliError,{request => $request,callbackParams=>$callbackParams},$obj,$params); 
			};
			if( $@ ) {
			    $log->error("Error getting item from $module and $context: $@");
			}
			use strict 'refs';
		}else {
			$log->error("Can't find $context");
		}
	}else {
		$log->error("Can't find module: $module");
	}
	$log->debug("Exiting getSongInfo\n");
}

sub getSongInfoModules {
	my $request = shift;
	my $client = $request->client();
	
	# get our parameters
  	my $type    = $request->getParam('type');
  	my $context    = $request->getParam('context');
	my $modules = getInformationModules();
	my $cnt = 0;
	for my $key (keys %$modules) {
		my $module = $modules->{$key};
		if((!defined($type) || $module->{'type'} eq $type) && (!defined($context) || $context eq $module->{'context'})) {
			$request->addResultLoop('item_loop',$cnt,'id',$key);
			$request->addResultLoop('item_loop',$cnt,'type',$module->{'type'});
			$request->addResultLoop('item_loop',$cnt,'context',$module->{'context'});
			$request->addResultLoop('item_loop',$cnt,'name',$module->{'name'});
			$cnt++;
		}
	}
	$request->addResult('count',$cnt);
	$log->debug("Exiting getSongInfoModules\n");
	$request->setStatusDone();
}

sub cliResponse {
	my $client = shift;
	my $params = shift;
	my $result = shift;

	my $request = $params->{'request'};
	my $cnt = 0;
	for my $item (@$result) {
		for my $key (keys %$item) {
			$request->addResultLoop('item_loop',$cnt,$key,$item->{$key});
		}
		$cnt++;
	}
	$request->addResult('count',$cnt);
	$request->setStatusDone();
}

sub cliError {
	my $client = shift;
	my $params = shift;
	my $result = shift;

	my $request = $params->{'request'};
	$log->error("Error!");
	$request->setStatusDone();
}

sub setSongInfoProperty {
	my $name = shift;
	my $value = shift;

	my $properties = $prefs->get('properties');
	$properties->{$name} = $value;
	$prefs->set('properties',$properties);
}

sub getSongInfoProperty {
	my $name = shift;
	my $properties = getSongInfoProperties();
	return $properties->{$name};
}

sub getSongInfoProperties {
	my $result = $prefs->get('properties');
	return $result;
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
