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
package Plugins::CustomScan::Manage;

use strict;
use base qw(Plugins::CustomScan::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Plugins::CustomScan::Scanner;

my $prefs = preferences('plugin.customscan');
my $log   = logger('plugin.customscan');

my $plugin; # reference to main plugin

sub new {
	my $class = shift;
	$plugin   = shift;

	$class->SUPER::new($plugin,1);
}

sub name {
	return 'PLUGIN_CUSTOMSCAN';
}

sub page {
	return 'plugins/CustomScan/settings/manage.html';
}

sub currentPage {
	return Slim::Utils::Strings::string('PLUGIN_CUSTOMSCAN_MANAGE');
}

sub pages {
	my %page = (
		'name' => Slim::Utils::Strings::string('PLUGIN_CUSTOMSCAN_MANAGE'),
		'page' => page(),
	);
	my @pages = (\%page);
	return \@pages;
}

sub handler {
	my ($class, $client, $params) = @_;
	$params->{'nosubmit'} = 1;
	if(defined($params->{'scantype'})) {
		handlerScan($class,$client,$params);
	}
	my $modules = Plugins::CustomScan::Scanner::getPluginModules();
	my @webModules = ();
	for my $key (keys %$modules) {
		my $module = $modules->{$key};
		my %webModule = (
			'id' => $key,
			'name' => $module->{'name'},
			'enabled' => $module->{'enabled'},
			'status' => statusToString(Plugins::CustomScan::Scanner::isScanning($key)),
			'scanText' => $module->{'scanText'},
			'clearEnabled' => (defined($module->{'clearEnabled'})?$module->{'clearEnabled'}:1),
			'scanEnabled' => (defined($module->{'scanEnabled'})?$module->{'scanEnabled'}:1),
			'dataprovidername' => $module->{'dataprovidername'},
			'dataproviderlink' => $module->{'dataproviderlink'},
		);
		push @webModules,\%webModule;
	}
	@webModules = sort { lc($a->{'id'}) cmp lc($b->{'id'}) } @webModules;
	$params->{'pluginCustomScanModules'} = \@webModules;
	$params->{'pluginCustomScanScanning'} = Plugins::CustomScan::Scanner::isScanning();
	$params->{'pluginCustomScanVersion'} = ${Plugins::CustomScan::Plugin::PLUGINVERSION};

	return $class->SUPER::handler($client, $params);
}

sub handlerScan {
	my ($class, $client, $params) = @_;

	if($params->{'module'} eq 'allmodules') {
		if($params->{'scantype'} eq 'scan') {
			$params->{'pluginCustomScanErrorMessage'} = Plugins::CustomScan::Scanner::fullRescan();
		}elsif($params->{'scantype'} eq 'clear') {
			$params->{'pluginCustomScanErrorMessage'} = Plugins::CustomScan::Scanner::fullClear();
		}elsif($params->{'scantype'} eq 'abort') {
			$params->{'pluginCustomScanErrorMessage'} = Plugins::CustomScan::Scanner::fullAbort();
		}
	}else {
		if($params->{'scantype'} eq 'scan') {
			$params->{'pluginCustomScanErrorMessage'} = Plugins::CustomScan::Scanner::moduleRescan($params->{'module'});
		}elsif($params->{'scantype'} eq 'clear') {
			$params->{'pluginCustomScanErrorMessage'} = Plugins::CustomScan::Scanner::moduleClear($params->{'module'});
		}
	}
}

sub statusToString {
	my $status = shift;
	if($status == 1) {
		return "PLUGIN_CUSTOMSCAN_STATUS_RUNNING";
	}elsif($status == -1 || $status == -2) {
		return "PLUGIN_CUSTOMSCAN_STATUS_FAILURE";
	}
	return undef;
}
		
1;
