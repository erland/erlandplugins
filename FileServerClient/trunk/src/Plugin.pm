# 				File Server Client plugin 
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

package Plugins::FileServerClient::Plugin;

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use MIME::Base64::Perl;
use Data::Dumper;

my @pluginDirs = ();
our $PLUGINVERSION =  undef;

my $prefs = preferences('plugin.fileserverclient');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.fileserverclient',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_FILESERVERCLIENT',
});
my $responses = {};
my $counter = 0;
my $servers = {};

sub getDisplayName {
	return 'PLUGIN_FILESERVERCLIENT';
}

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	Slim::Control::Request::addDispatch(['fileserver.dir'],[0,1,0,undef]);
	Slim::Control::Request::addDispatch(['fileserver.get'],[0,1,0,undef]);
	Slim::Control::Request::addDispatch(['fileserver','dirresult','_handle','_dirs'],[0,1,0,\&getDirResponse]);
	Slim::Control::Request::addDispatch(['fileserver','getresult','_handle','_file','_data'],[0,1,0,\&getFileResponse]);
	Slim::Control::Request::addDispatch(['fileserver','register','_id','_model'],[0,1,0,\&registerCallback]);

	${Slim::Music::Info::suffixes}{'binfile'} = 'binfile';
	${Slim::Music::Info::types}{'binfile'} = 'application/octet-stream';
}

sub getFunctions {
	return {}
}

sub webPages {

	my %pages = (
		"FileServerClient/index\.(?:htm|xml)"     => \&handleWebList,
		"FileServerClient/viewfile\.binfile"     => \&handleWebFile,
	);

	for my $page (keys %pages) {
		if(UNIVERSAL::can("Slim::Web::Pages","addPageFunction")) {
			Slim::Web::Pages->addPageFunction($page, $pages{$page});
		}else {
			Slim::Web::HTTP::addPageFunction($page, $pages{$page});
		}
	}
	Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_FILESERVERCLIENT' => 'plugins/FileServerClient/index.html' });
}

sub handleWebList {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $handle = $counter++;
	my $dir = "/";
	if(defined($params->{'dir'}) && $params->{'dir'} ne "") {
		$dir = $params->{'dir'};
	}

	my $server = $params->{'server'};
	my @serverList = ();
	for my $serverId (keys %$servers) {
		my $entry = {
			'id' => $serverId,
			'name' => $servers->{$serverId}->{'name'}." (".$servers->{$serverId}->{'model'}.")",
		};
		push @serverList,$entry;
	}

	if((!defined($server) || $server eq "") && scalar(@serverList)>0) {
		$server = @serverList->[0]->{'id'}
	}
	$params->{'pluginFileServerServers'} = \@serverList;
	$params->{'pluginFileServerClientVersion'} = $PLUGINVERSION;

	if(defined($server) && $server ne "") {
		Slim::Control::Request::notifyFromArray(undef,["fileserver.dir",$server,$handle,$dir]);
		$params->{'pluginFileServerCurrentServer'} = $server;
		$params->{'pluginFileServerCurrentDirectory'} = $dir;
		$responses->{$handle} = {
			'params' => $params,
			'callback' => $callback,
			'httpClient' => $httpClient,
			'response' => $response,
			'timeout' => 30
		};
		return undef;
	}else {
		return Slim::Web::HTTP::filltemplatefile('plugins/FileServerClient/index.html', $params);
	}
}

sub handleWebFile {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $handle = $counter++;
	my $file = $params->{'file'};

	my $server = $params->{'server'};

	Slim::Control::Request::notifyFromArray(undef,["fileserver.get",$server,$handle,$file]);
	$params->{'pluginFileServerClientVersion'} = $PLUGINVERSION;

	$responses->{$handle} = {
		'params' => $params,
		'callback' => $callback,
		'httpClient' => $httpClient,
		'response' => $response,
		'timeout' => 30
	};
	return undef;
}

sub registerCallback {
	my $request = shift;

	my $id = $request->getParam("_id");
	my $model = $request->getParam("_model");
	if($model eq 'jive') {
		$model = "Controller";
	}elsif($model eq 'fab4') {
		$model = "Touch";
	}elsif($model eq 'baby') {
		$model = "Radio";
	}elsif($model eq 'squeezeplay') {
		$model = "SqueezePlay";
	}
	
	my $client = Slim::Player::Client::getClient($id);
	if($client) {
		$servers->{$id} = {
			name => $client->name,
			model => $model,
		}
	}else {
		$servers->{$id} = {
			name => $id,
			model => $model,
		}
	}
	$log->info("Registering: ".Dumper($servers->{$id}));
	$request->setStatusDone();
}

sub getFileResponse {
	my $request = shift;

	my $client = $request->client();

	my $handle = $request->getParam("_handle");
	return unless exists $responses->{$handle};

	my $file = $request->getParam("_file");
	my $basefile;
	if($file =~ /^.*\/([^\/]+)$/) {
		$basefile = $1;
	}
	my $data = $request->getParam("_data");
	if(defined($data)) {
		$data = MIME::Base64::Perl::decode_base64($data);
	}
	$request->setStatusDone();
	my $params = $responses->{$handle}->{'params'};
	$responses->{$handle}->{'response'}->header("Content-Disposition","attachment; filename=".$basefile);
	$responses->{$handle}->{'callback'}->($client,$params,\$data, $responses->{$handle}->{'httpClient'},$responses->{$handle}->{'response'});
	delete $responses->{$handle};
}

sub getDirResponse {
	my $request = shift;

	my $client = $request->client();

	my $handle = $request->getParam("_handle");
	return unless exists $responses->{$handle};

	my $files = $request->getParam("_dirs");
	@$files = sort {$a->{'name'} cmp $b->{'name'}} @$files;
	for my $file (@$files) {
		if($file->{'name'} =~ /\.([^\/]+)$/) {
			$file->{'extension'} = $1;
		}else {
			$file->{'extension'} = 'binfile';
		}
	}	
	$request->setStatusDone();

	my $params = $responses->{$handle}->{'params'};
	$params->{'pluginFileServerClientItems'} = $files;
	my $content = Slim::Web::HTTP::filltemplatefile('plugins/FileServerClient/index.html', $params);
	$responses->{$handle}->{'callback'}->($client,$params,$content, $responses->{$handle}->{'httpClient'},$responses->{$handle}->{'response'});
	delete $responses->{$handle};
}

1;

__END__
