#    Copyright (c) 2008 Erland Isaksson (erland_i@hotmail.com)
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
package Plugins::TitleSwitcher::Settings;

use strict;
use base qw(Plugins::TitleSwitcher::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Plugins::MusicInfoSCR::Settings;
use Plugins::TitleSwitcher::Plugin;

my $prefs = preferences('plugin.titleswitcher');
my $log   = logger('plugin.titleswitcher');

my $plugin; # reference to main plugin

$prefs->migrate(1, sub {
	$log->error("GOT here");
	if(!defined($prefs->get('formats'))) {
	$log->error("GOT here TOO");
		$prefs->set('formats', {'ALBUMARTIST' => 'ALBUM:5,ARTIST:10'});
	}
	1;
});

sub new {
	my $class = shift;
	$plugin   = shift;

	$class->SUPER::new($plugin,1);
}

sub name {
	return 'PLUGIN_TITLESWITCHER';
}

sub page {
	return 'plugins/TitleSwitcher/settings/basic.html';
}

sub currentPage {
	return Slim::Utils::Strings::string('PLUGIN_TITLESWITCHER_SETTINGS');
}

sub pages {
	my %page = (
		'name' => Slim::Utils::Strings::string('PLUGIN_TITLESWITCHER_SETTINGS'),
		'page' => page(),
	);
	my @pages = (\%page);
	return \@pages;
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	if ($paramRef->{'saveSettings'}) {
		my $formats = $prefs->get('formats');

		for my $key (keys %$formats) {
			if($paramRef->{'format_value_'.$key} eq '') {
				delete $formats->{$key};
			}else {
				if(validateFormat($client,$paramRef->{'format_value_'.$key})) {
					$formats->{$key} = $paramRef->{'format_value_'.$key};
				}else {
					if ($paramRef->{'AJAX'}) {
						$paramRef->{'warning'} = string('PLUGIN_TITLESWITCHER_INVALID_FORMAT').": ".$paramRef->{'format_value_'.$key};
						$paramRef->{'validated'}->{'valid'}=0;
					}else {
						if(!exists $paramRef->{'warning'}) {
							$paramRef->{'warning'}='';
						}
						$paramRef->{'warning'} .= string('PLUGIN_TITLESWITCHER_INVALID_FORMAT').": ".$paramRef->{'format_value_'.$key}."<br/>";
					}
					delete $paramRef->{'saveSettings'};
				}
			}
		}
		if($paramRef->{'format_name_new'} ne '' && $paramRef->{'format_value_new'} ne '') {
			my $name = $paramRef->{'format_name_new'};
			if(exists $paramRef->{'format_value_new'}) {
				if(validateFormat($client,$paramRef->{'format_value_new'})) {
					$formats->{$name} = $paramRef->{'format_value_new'};
				}else {
					if ($paramRef->{'AJAX'}) {
						$paramRef->{'warning'} = string('PLUGIN_TITLESWITCHER_INVALID_FORMAT').": ".$paramRef->{'format_value_new'};
						$paramRef->{'validated'}->{'valid'}=0;
					}else {
						if(!exists $paramRef->{'warning'}) {
							$paramRef->{'warning'}='';
						}
						$paramRef->{'warning'} .= string('PLUGIN_TITLESWITCHER_INVALID_FORMAT').": ".$paramRef->{'format_value_new'}."<br/>";
					}
					delete $paramRef->{'saveSettings'};
				}
			}
		}
		$paramRef->{'prefs'}->{'formats'} = $formats;
	}else {
		$paramRef->{'prefs'}->{'formats'} = $prefs->get('formats');
	}
	my $result = $class->SUPER::handler($client, $paramRef, $pageSetup);
	if ($paramRef->{'saveSettings'}) {
		$prefs->set('formats',$paramRef->{'prefs'}->{'formats'});
		Plugins::TitleSwitcher::Plugin::reloadFormats()
	}
	return $result;	
}

sub validateFormat {
	my $client = shift;
	my $format = shift;

	my $formats = Plugins::MusicInfoSCR::Settings::getFormatStrings($client);
	my @parts = split(/,/,$format);
	foreach my $part (@parts) {
		my ($name,$time) = split(/:/,$part);
		if(!exists $formats->{$name}) {
			return undef;
		}
	}
	return $format;
}
		
1;
