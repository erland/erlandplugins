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



sub getSongInfo {
	my $request = shift;
	my $client = $request->client();
	
	# get our parameters
  	my $module    = $request->getParam('_module');
	my $modules = getInformationModules();
	if(defined($modules->{$module})) {
		my $obj = undef;
		my $context = "";
		my $trackId = $request->getParam('track');
		if($modules->{$module}->{'context'} eq 'album') {
			my $albumId = $request->getParam('album');
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
			my $artistId = $request->getParam('artist');
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
			my $paramHash = $request->getParamsCopy();
			no strict 'refs';
			eval { 
				$request->setStatusProcessing();
				&{$modules->{$module}->{'function'}}($client,\&cliResponse,\&cliError,{request => $request},$obj,$paramHash); 
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
