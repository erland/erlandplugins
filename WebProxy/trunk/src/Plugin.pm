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
                   
package Plugins::WebProxy::Plugin;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);

use Data::Dumper;

my $prefs = preferences('plugin.webproxy');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.webproxy',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_WEBPROXY',
});

my $PLUGINVERSION = undef;

#$prefs->migrate(1,sub {
#	my @empty = ();
#	$prefs->set('titleformats',\@empty)
#});

sub getDisplayName()
{
	return string('PLUGIN_WEBPROXY'); 
}

sub initPlugin
{
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
}

sub webPages {
	my %pages = (
		"WebProxy/proxy\.(html|jpg|jpeg|png|xml)" => \&handleProxyRequest,
	);
	
	for my $page (keys %pages) {
		Slim::Web::Pages->addPageFunction($page, $pages{$page});
	}
}

sub handleProxyRequest {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $id = $params->{id};
	my $entries = $prefs->get('entries') || {};
	$prefs->set('entries',$entries);
	if(defined($entries->{$id}) && $entries->{$id}->{url}) {
		$log->debug("Getting ".$entries->{$id}->{url});
		my $http = Slim::Networking::SimpleAsyncHTTP->new(\&getProxyResponse, \&gotErrorViaHTTP, {
			callback => $callback,
			client => $client, 
			httpClient => $httpClient,
			response => $response,
			params => $params,
			entry => $entries->{$id},
		});
		$http->get($entries->{$id}->{url});
	}else {
		$log->error("Couldn't find requested entry: $id");
	}
	return undef;
}

sub getProxyResponse {
	my $http = shift;
	my $params = $http->params();
	my $content = $http->content();
        
	my $match = $params->{entry}->{match};
	if($match && $content =~ /$match/) {
		my $url = $1;
		my $expression = $params->{entry}->{expression};
		if(defined($expression) && $expression ne "") {
			$log->debug("GOT: $url and replace using: $expression");
			$expression =~ s/\$1/$url/;
			$url = $expression;
		}
        	
		if($url && $url ne "") {
			$log->debug("Retrieving $url");
			my $http = Slim::Networking::SimpleAsyncHTTP->new(\&getRealResponse, \&gotErrorViaHTTP, {
				callback => $params->{callback}, 
				client => $params->{client}, 
				httpClient => $params->{httpClient},
				response => $params->{response},
				params => $params->{params},
			});
			$http->get($url);
		}
	}else {
		$log->error("Couldn't find matching string: $match");
	}
}

sub getRealResponse {
	my $http = shift;
	my $params = $http->params();
	my $content = $http->content();

	$params->{callback}->($params->{client},$params->{params},\$content,$params->{httpClient},$params->{response});
}

sub gotErrorViaHTTP {
	my $http = shift;
	my $params = $http->params();
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
