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
my $externalModules = {};

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
					return objectInfoHandler(@_,undef,$id);
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
					if(scalar(@_)<6) {
						return objectInfoHandler(@_,undef,$id);
					}else {
						return objectInfoHandler(@_,$id);
					}
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
					return objectInfoHandler(@_,undef,$id);
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
		my $entry = {
			text => $item->{'text'},
		};
		if(defined($item->{'providerlink'})) {
			$entry->{'externallink'} = $item->{'providerlink'};
			$entry->{'externallinkname'} = defined($item->{'providername'})?$item->{'providername'}:$item->{'providerlink'};
		}
		if(defined($item->{'name'})) {
			$entry->{'name'} = $item->{'name'};
		}
		push @items,$entry; 
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
			type => $context,
			$context => $client->modeParam($context),
		};
		if($client->modeParam("item")) {
			$params->{'item'} = $client->modeParam("item");
		}
		
		if($module->{'type'} eq 'text') {
			executeSongInfoRequest($client, $params, \&playerResponseTextArea,undef,$params);
		}
	}
}

sub playerResponseTextArea {
	my $client = shift;
	my $params = shift;
	my $result = shift;

	my $request = $params->{'request'};
	my $cnt = 0;
	my $callbackParams = $params->{'callbackParams'};
	
	my $subMenus=0;

	my @listRef;
	if(scalar(@$result)>0) {
		my $firstItem = $result->[0];
		if(defined($firstItem->{'name'}) && scalar(@$result)>1 && !defined($callbackParams->{'item'})) {
			for my $item (@$result) {
				push @listRef,$item->{'name'};
				$subMenus=1;
				$cnt++;
			}
		}else {
			for my $item (@$result) {
				if(!defined($callbackParams->{'item'}) || $callbackParams->{'item'} eq $item->{'name'}) {
					push @listRef,$item->{'text'};
					$cnt++;
				}
			}
		}
	}
	if(scalar(@listRef)==0) {
		push @listRef,string('PLUGIN_SONGINFO_NOT_AVAILABLE'); 
	}

	if($subMenus) {
		my %params = (
			header => '{PLUGIN_SONGINFO}',
			headerAddCount => 1,
			listRef => \@listRef,
			name => \&getDisplayText,
			modeName => 'SongInfoGroup',
			onRight    => sub {
				my ($client, $item) = @_;
				my %params = (				
					'module' => $callbackParams->{'module'},
					$callbackParams->{'type'} => $callbackParams->{$callbackParams->{'type'}},
					item => $item,
				);
				Slim::Buttons::Common::pushMode($client, 'Plugins::SongInfo::Plugin',\%params);
			},

		);
		Slim::Buttons::Common::pushMode($client, 'INPUT.Choice',\%params);
	}else {
		my %params = (
			header => '{PLUGIN_SONGINFO}',
			headerAddCount => 1,
			listRef => \@listRef,
			name => \&getDisplayText,
			modeName => 'SongInfo',
		);
		Slim::Buttons::Common::pushMode($client, 'INPUT.Choice',\%params);
	}
}

sub getDisplayText {
	my ($client, $item) = @_;

	return $item;
}
sub objectInfoHandler {
        my ( $client, $url, $obj, $remoteMeta, $tags, $filter, $moduleId) = @_;
        $tags ||= {};
	my $modules = getInformationModules();
	my $module = $modules->{$moduleId};
	$log->debug("Requesting $moduleId sub menu: ".$module->{'name'});
	my $jive = undef;
	my $context = $module->{'context'};
	my $player = undef;
	my $web = undef;
	if(defined($module->{'supportremote'}) && !$module->{'supportremote'} && ref($obj) eq 'Slim::Schema::RemoteTrack') {
		return undef;
	}
	if(defined($module->{'menufunction'})) {
		no strict 'refs';
		my $result = &{$module}->{'menufunction'}($client,$url,$obj,$remoteMeta,$tags);
		use strict 'refs';
		return $result;
	}
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
	}else {
		$result->{hide} = "ip3k";
	}
	if($jive) {
		$result->{jive} = $jive;
	}
	if($web) {
		$result->{web} = $web;
	}
	return $result;
}

sub registerInformationModule {
	my $id = shift;
	my $data = shift;

	$externalModules->{$id} = $data;
}

sub unregisterInformationModule {
	my $id = shift;

	delete $externalModules->{$id};
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
							my $prop;
							$items{$key} = $item;
							$items{$key}->{'id'} = $key;
							$prop = getSongInfoProperty($key."webmenu");
							$items{$key}->{'webmenu'} = $prop unless not defined $prop;
							$prop = getSongInfoProperty($key."playermenu");
							$items{$key}->{'playermenu'} = $prop unless not defined $prop;
							$prop = getSongInfoProperty($key."jivemenu");
							$items{$key}->{'jivemenu'} = $prop unless not defined $prop;
						}
					}
				}
			}
		}
		use strict 'refs';
	}

	for my $key (keys %$externalModules) {
		my $item = $externalModules->{$key};
		if(defined($item->{'name'})) {
			if(!defined($item->{'minpluginversion'}) || isAllowedVersion($item->{'minpluginversion'})) {
				my $prop;
				$items{$key} = $item;
				$items{$key}->{'id'} = $key;
				$prop = getSongInfoProperty($key."webmenu");
				$items{$key}->{'webmenu'} = $prop unless not defined $prop;
				$prop = getSongInfoProperty($key."playermenu");
				$items{$key}->{'playermenu'} = $prop unless not defined $prop;
				$prop = getSongInfoProperty($key."jivemenu");
				$items{$key}->{'jivemenu'} = $prop unless not defined $prop;
			}
		}
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
			executeSongInfoRequest($client, $params,\&cliResponseTextArea,$request,$params);
		}else {
			executeSongInfoRequest($client, $params,\&cliResponseImages,$request,$params);
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
	my $callbackParams = $params->{'callbackParams'};

	my $cnt = 0;

	my $text = '';
	my @items = ();
	if(scalar(@$result)>0) {
		my $firstItem = $result->[0];
		if(defined($firstItem->{'name'}) && scalar(@$result)>1 && !defined($callbackParams->{'item'})) {
			for my $item (@$result) {
				my $entry = {
					text => $item->{'name'},
					actions => {
						go => {
							cmd => ['songinfomenu',"module:".$callbackParams->{'module'},"item:".$item->{'name'}]
						},
					},
					style => 'item',
				};
				push @items,$entry;
			}
		}else {
			for my $item (@$result) {
				if($text ne '') {
					$text .= "\n";
				}
				if(!defined($callbackParams->{'item'}) || $callbackParams->{'item'} eq $item->{'name'}) {
					$text .= $item->{'text'};
					if(defined($item->{'providername'})) {
						$text .= "\n\n".$item->{'providername'};
					}
					$cnt++;
				}
			}
		}
	}else {
		$text = string('PLUGIN_SONGINFO_NOT_AVAILABLE');
	}
	if($text ne '') {
		$request->addResult('window', {
			textarea => $text,
		});
		$request->addResult('count',0);
	}else {
		$request->addResult('item_loop',\@items);
		$request->addResult('count',scalar(@items));
	}
	$request->addResult('offset',0);
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
		my $objName = undef;
		my $obj2Name = undef;
		my $obj3Name = undef;

		my $context = "";
		my $trackId = $params->{'track'};
		if($modules->{$module}->{'context'} eq 'album') {
			my $albumId = $params->{'album'};
			if(!defined($albumId)) {
				my $track = undef;
				if(defined($trackId)) {
					if($trackId<0) {
						$track = Slim::Schema::RemoteTrack->fetchById($trackId);
					}else {
						$track = Slim::Schema->resultset('Track')->find($trackId);
					}
				}else {
					$track = Slim::Player::Playlist::song($client);
				}
				if(defined($track)) {
					if($track->remote) {
						my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $track->url );
						if ( $handler && $handler->can('getMetadataFor') ) {
							# this plugin provides track metadata, i.e. Pandora, Rhapsody
							my $meta  = $handler->getMetadataFor( $client, $track->url, 'forceCurrent' );                   
							$objName    = $meta->{album};
							$obj2Name   = $meta->{artist};
						}
					}else {
						$obj = $track->album();
						$objName = $obj->title() if defined($obj);
						if($track->artist()) {
							$obj2Name = $track->artist()->name;
						}
					}
				}
			}else {
				$obj = Slim::Schema->resultset('Album')->find($albumId);
				if($obj) {
					my @artists = $obj->artists();
					if(scalar(@artists)>0) {
						$obj2Name = $artists[0]->name;
					}
				}
				$objName = $obj->title() if defined($obj);
			}
			if(defined($objName)) {
				$context = "album=".$objName;
			}else {
				$context = "album";
			}
		}elsif($modules->{$module}->{'context'} eq 'artist') {
			my $artistId = $params->{'artist'};
			if(!defined($artistId)) {
				my $track = undef;
				if(defined($trackId)) {
					if($trackId<0) {
						$track = Slim::Schema::RemoteTrack->fetchById($trackId);
					}else {
						$track = Slim::Schema->resultset('Track')->find($trackId);
					}
				}else {
					$track = Slim::Player::Playlist::song($client);
				}
				if(defined($track)) {
					if($track->remote) {
						my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $track->url );
						if ( $handler && $handler->can('getMetadataFor') ) {
							# this plugin provides track metadata, i.e. Pandora, Rhapsody
							my $meta  = $handler->getMetadataFor( $client, $track->url, 'forceCurrent' );                   
							$objName    = $meta->{artist};
						}
					}else {
						$obj = $track->artist();
						$objName = $obj->name() if defined($obj);
					}
				}
			}else {
				$obj = Slim::Schema->resultset('Contributor')->find($artistId);
				$objName = $obj->name() if defined($obj);
			}
			if(defined($objName)) {
				$context = "artist=".$objName;
			}else {
				$context = "artist";
			}
		}elsif($modules->{$module}->{'context'} eq 'track') {
			if(!defined($trackId)) {
				$obj = Slim::Player::Playlist::song($client);
			}else {
				if($trackId<0) {
					$obj = Slim::Schema::RemoteTrack->fetchById($trackId);
				}else {
					$obj = Slim::Schema->resultset('Track')->find($trackId);
				}
			}
			if(defined($obj)) {
				if($obj->remote) {
					my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $obj->url );
					if ( $handler && $handler->can('getMetadataFor') ) {
						# this plugin provides track metadata, i.e. Pandora, Rhapsody
						my $meta  = $handler->getMetadataFor( $client, $obj->url, 'forceCurrent' );                   
						$objName    = $meta->{title};
						$obj2Name   = $meta->{album};
						$obj3Name   = $meta->{artist};
					}
				}else {
					$objName = $obj->title();
					if($obj->album()) {
						$obj2Name = $obj->album()->name;
					}
					my @artists = $obj->artists();
					if(scalar(@artists)>0) {
						$obj3Name = $artists[0]->name;
					}
				}
				$context = "track=".$objName;
			}else {
				$context = "track";
			}
		}
		if(defined($obj) || defined($objName)) {
			no strict 'refs';
			eval { 
				if($request) {
					$request->setStatusProcessing();
				}
				&{$modules->{$module}->{'function'}}($client,$callback,\&cliError,{request => $request,callbackParams=>$callbackParams},$obj,$params,$objName,$obj2Name,$obj3Name); 
			};
			if( $@ ) {
				$log->error("Error getting item from $module and $context: $@");
				if($request) {
					$request->setStatusBadDispatch();
				}
			}
			use strict 'refs';
		}else {
			$log->error("Can't find $context");
			if($request) {
				$request->setStatusBadParams();
			}
		}
	}else {
		$log->error("Can't find module: $module");
		if($request) {
			$request->setStatusBadParams();
		}
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
	if(defined($request)) {
		$request->setStatusBadDispatch();
	}
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
