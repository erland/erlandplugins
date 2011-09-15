# 				License Manager plugin 
#
#    Copyright (c) 2011 Erland Isaksson (erland_i@hotmail.com)
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

package Plugins::LicenseManagerPlugin::Settings;

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::OSDetect;

my $prefs = preferences('plugin.licensemanager');
my $log   = logger('plugin.licensemanager');

my $os   = Slim::Utils::OSDetect->getOS();

sub name {
	return Slim::Web::HTTP::CSRF->protectName('SETUP_PLUGIN_LICENSEMANAGER_GROUP');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/LicenseManagerPlugin/settings/basic.html');
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	# get plugin info from defined repos
	my $repos = Plugins::LicenseManagerPlugin::Plugin->repos;

	my $data = { remaining => scalar keys %$repos, results => {}, errors => {} };

	my $forcedCheck = 0;
	if($params->{'saveSettings'}) {
		$forcedCheck = 1;
	}
	for my $repo (keys %$repos) {
		Plugins::LicenseManagerPlugin::Plugin::getExtensions({
			'client' => $client,
			'name'   => $repo, 
			'type'   => 'plugin,applet,patche', 
			'target' => Slim::Utils::OSDetect::OS(),
			'version'=> $::VERSION, 
			'lang'   => $Slim::Utils::Strings::currentLang,
			'details'=> 1,
			'forcedCheck' => $forcedCheck,
			'cb'     => \&_getReposCB,
			'pt'     => [ $class, $client, $params, $callback, \@args, $data, $repos->{$repo} ],
			'onError'=> sub { $data->{'errors'}->{ $_[0] } = $_[1] },
		});
	}

	if (!keys %$repos) {
		_getReposCB( $class, $client, $params, $callback, \@args, $data, undef, {}, {} );
	}
}

sub _getReposCB {
	my ($class, $client, $params, $callback, $args, $data, $weight, $res, $info) = @_;
	if (scalar @$res) {

		$data->{'results'}->{ $info->{'name'} } = {
			'title'   => $info->{'title'},
			'entries' => $res,
			'weight'  => $weight,
		};
	}

	if ( --$data->{'remaining'} <= 0 ) {

		$callback->($client, $params, $class->_addInfo($client, $params, $data), @$args);
	}
}

sub _addInfo {
	my ($class, $client, $params, $data) = @_;

	my @results = sort { $a->{'weight'} !=  $b->{'weight'} ?
						 $a->{'weight'} <=> $b->{'weight'} : 
						 $a->{'title'} cmp $b->{'title'} } values %{$data->{'results'}};

	my @res;

	for my $res (@results) {
		push @res, @{$res->{'entries'}};
	}

	# prune out duplicate entries, favour favour higher version numbers
	
	# pass 1 - find the higher version numbers
	my $max = {};

	for my $repo (@results) {
		for my $entry (@{$repo->{'entries'}}) {
			my $name = $entry->{'name'};
			if (!defined $max->{$name} || Slim::Utils::Versions->compareVersions($entry->{'version'}, $max->{$name}) > 0) {
				$max->{$name} = $entry->{'version'};
			}
		}
	}

	my $accountId = Plugins::LicenseManagerPlugin::Plugin::getAccountId();
	# pass 2 - prune out lower versions or entries which are hidden as they are shown in enabled plugins
	for my $repo (@results) {
		my $i = 0;
		while (my $entry = $repo->{'entries'}->[$i]) {
			if ($max->{$entry->{'name'}} ne $entry->{'version'}) {
				splice @{$repo->{'entries'}}, $i, 1;
				next;
			}
			if(defined($entry->{'licenseLink'})) {
				$entry->{'licenseLink'} =~ s/USER/$accountId/;
			}
			$i++;
		}
	}

	$params->{'avail'}    = \@results;
	$params->{'accountId'} = $accountId;
	$params->{'accountName'} = Plugins::LicenseManagerPlugin::Plugin::getAccountName();
	for my $repo (keys %{$data->{'errors'}}) {
		$params->{'warning'} .= Slim::Utils::Strings::string("PLUGIN_EXTENSIONS_REPO_ERROR") . " $repo - $data->{errors}->{$repo}<p/>";
	}

	return $class->SUPER::handler($client, $params);
}


1;
