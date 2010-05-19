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
package Plugins::CustomClockHelper::Settings;

use strict;
use base qw(Plugins::CustomClockHelper::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings;

use Data::Dumper;

my $prefs = preferences('plugin.customclockhelper');
my $log   = logger('plugin.customclockhelper');

my $plugin; # reference to main plugin

sub new {
	my $class = shift;
	$plugin   = shift;

	$class->SUPER::new($plugin);
}

sub name {
	return 'SETUP_PLUGIN_CUSTOMCLOCKHELPER_SETTINGS';
}

sub page {
	return 'plugins/CustomClockHelper/settings/settings.html';
}

sub currentPage {
	my ($class, $client, $params) = @_;
	return Slim::Utils::Strings::string('SETUP_PLUGIN_CUSTOMCLOCKHELPER_SETTINGS');
}

sub pages {
	my ($class, $client, $params) = @_;
	my @pages = ();
	my %page = (
		'name' => Slim::Utils::Strings::string('SETUP_PLUGIN_CUSTOMCLOCKHELPER_SETTINGS'),
		'page' => page(),
	);
	push @pages,\%page;
	return \@pages;
}

sub prefs {
        return ($prefs, qw(customitemsstartuprefreshinterval customitemsrefreshinterval));
}

sub handler {
	my ($class, $client, $params) = @_;

	if(defined($params->{'saveSettings'})) {
                my $i = 0;
                my @array = ();

                while (defined $params->{"titleformats".$i} && $params->{"titleformats".$i} ne "") {
			if(validateFormat($client,$params->{"titleformats".$i})) {
	                        push @array, $params->{"titleformats".$i};
			}
                        $i++;
                }

                $prefs->set("titleformats", \@array);
  	}
	my $titleFormats = $prefs->get("titleformats");
        $params->{'prefs'}->{"pluginCustomClockHelperTitleFormats"} = $titleFormats;

	return $class->SUPER::handler($client, $params);
}

sub validateFormat {
        my $client = shift;
        my $format = shift;

        my $formats = Plugins::MusicInfoSCR::Settings::getFormatStrings($client);
        if(!exists $formats->{$format}) {
                return undef;
        }
        return $format;
}


# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;
		
1;
