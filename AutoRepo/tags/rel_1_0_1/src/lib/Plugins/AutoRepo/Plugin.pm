# 				AutoRepo plugin 
#
#    Copyright (c) 2009 Erland Isaksson (erland_i@hotmail.com)
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

package Plugins::AutoRepo::Plugin;

use strict;

use base qw(Slim::Plugin::Base);
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

use XML::Simple;

require Plugins::AutoRepo::Settings;
my $prefs = preferences('plugin.autorepo');
my $extensionPrefs = preferences('plugin.extensions');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.autorepo',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_AUTOREPO',
});

# Information on each portable library
my $PLUGINVERSION = undef;

my $g_repositories = {};

sub getDisplayName {
	return 'PLUGIN_AUTOREPO';
}

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};

		Plugins::AutoRepo::Settings->new($class);
}

sub postinitPlugin {
	my $found = 0;
	my $extensionRepositories = $extensionPrefs->{'repos'};
	foreach my $repo (@$extensionRepositories) {
		if($repo =~ /AutoRepo\/repositories.xml$/) {
			$found = 1;
			last;
		}
	}
	if(!$found) {
		Slim::Plugin::Extensions::Plugin->addRepo("http://localhost:".$serverPrefs->get('httpport')."/plugins/AutoRepo/repositories.xml");
	}
	refreshRepositories();
}

sub webPages {

	my %pages = (
		"AutoRepo/repositories\.(?:xml)"     => \&handleWebGetRepositories,
	);

	for my $page (keys %pages) {
		if(UNIVERSAL::can("Slim::Web::Pages","addPageFunction")) {
			Slim::Web::Pages->addPageFunction($page, $pages{$page});
		}else {
			Slim::Web::HTTP::addPageFunction($page, $pages{$page});
		}
	}
}

sub getRepositories {
	return $g_repositories;
}

sub refreshRepositories {
        my $http = LWP::UserAgent->new;
        my $response = $http->get("http://erlandplugins.googlecode.com/svn/repository/trunk/autorepo.xml");
	$g_repositories = {};
        if($response->is_success) {
                my $repositoriesContent = $response->content;
                chomp $repositoriesContent;
		my $repositoriesXML = eval { XMLin($repositoriesContent, forcearray => ["repository"], keyattr => [] )};
		if (!$@) {
			my $repositories = $repositoriesXML->{'repository'};
			push @$repositories,Slim::Networking::SqueezeNetwork->url('/public/plugins/logitech.xml');
			foreach my $repository (@$repositories) {
				$g_repositories->{$repository} = undef;
				downloadRepository($repository);
			}
		}
	}
	resetScheduledRefresh();
}

sub resetScheduledRefresh {
	if($prefs->get('refresh_interval')>0) {
		Slim::Utils::Timers::killTimers(undef,\&refreshRepositories);
		Slim::Utils::Timers::setTimer(undef,Time::HiRes::time()+$prefs->get('refresh_interval')*60,\&refreshRepositories);
	}else {
		Slim::Utils::Timers::killTimers(undef,\&refreshRepositories);
	}
}

sub downloadRepository {
	my $repository = shift;
	$log->debug("Downloading: $repository");
	Slim::Networking::SimpleAsyncHTTP->new(\&gotViaHTTP,\&gotErrorViaHTTP,
			{
				'url' => $repository,
				'timeout' => 60,
				'cache' => 1,
				'expires' => 60,
			})->get($repository);

}

sub gotViaHTTP {
	my $http = shift;

	my $content = $http->content();
	my $repositoryXML = eval { XMLin($content, forcearray => [], keyattr => [] )};
	if (!$@) {
		$log->info("Downloaded: ".$http->params('url'));
		$log->debug($content);
		$g_repositories->{$http->params('url')} = $content;
	}else {
		$log->error("Error parsing ".$http->params('url').": $@");
	}
};

sub gotErrorViaHTTP {
	my $http = shift;
	my $error = shift;

	$log->error("Error retrieving: ".$http->params('url').": $error");
};

sub handleWebGetRepositories {
	my ($client, $params) = @_;

	my $content = '<?xml version="1.0"?><extensions><details><title lang="EN">'.string("PLUGIN_AUTOREPO_REPOSITORY_NAME").'</title></details>';
	my $subContent = getRepositoryContent("plugins");
	if(defined($subContent)) {
		$content .= "<plugins>".$subContent."</plugins>";
	}
	$subContent = getRepositoryContent("applets");
	if(defined($subContent)) {
		$content .= "<applets>".$subContent."</applets>";
	}
	$subContent = getRepositoryContent("wallpapers");
	if(defined($subContent)) {
		$content .= "<wallpapers>".$subContent."</wallpapers>";
	}
	$subContent = getRepositoryContent("sounds");
	if(defined($subContent)) {
		$content .= "<sounds>".$subContent."</sounds>";
	}
	$content .="</extensions>";
	return \$content;
}

sub getRepositoryContent {
	my $contentType = shift;

	my $content = "";
	foreach my $repository (keys %$g_repositories) {
	        my $repositoryContent = $g_repositories->{$repository};
		if(defined($repositoryContent)) {
			$log->debug("Handling $repository");
			my $repositoryXML = eval { XMLin($repositoryContent, forcearray => [], keyattr => [] )};
			if (!$@) {
				if($repositoryContent =~ /<$contentType>(.*)<\/$contentType>/s) {
					$content .= $1;
				}
			}else {
				$log->error("Failed to parse configuration ($repository) because:\n$@");
			}
		}
	}
	chomp $content;
	$content =~ s/^\s+//;
	$content =~ s/\s+$//;
	if($content eq "") {
		return undef;
	}
	return $content;
}

1;

__END__
