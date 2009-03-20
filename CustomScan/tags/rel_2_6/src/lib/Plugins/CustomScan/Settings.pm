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
package Plugins::CustomScan::Settings;

use strict;
use base qw(Plugins::CustomScan::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;

my $prefs = preferences('plugin.customscan');
my $log   = logger('plugin.customscan');

my $plugin; # reference to main plugin

sub new {
	my $class = shift;
	$plugin   = shift;

	$class->SUPER::new($plugin);
}

sub name {
	return 'PLUGIN_CUSTOMSCAN_SETTINGS';
}

sub page {
	return 'plugins/CustomScan/settings/basic.html';
}

sub currentPage {
	return name();
}

sub pages {
	my %page = (
		'name' => name(),
		'page' => page(),
	);
	my @pages = (\%page);
	return \@pages;
}

sub prefs {
        return ($prefs, qw(long_urls refresh_rescan refresh_startup auto_rescan));
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	# array prefs handled by this handler not handler::SUPER
        my @prefs = qw(titleformats);

	if ($paramRef->{'saveSettings'}) {

                for my $pref (@prefs) {

                        my $i = 0;
                        my @array;

                        while (defined $paramRef->{$pref.$i} && $paramRef->{$pref.$i} ne "-1") {

                                push @array, $paramRef->{$pref.$i};
                                $i++;
                        }

                        $prefs->set($pref, \@array);
                }
		Plugins::CustomScan::Plugin::refreshTitleFormats();
        }
	for my $pref (@prefs) {
                $paramRef->{'prefs'}->{$pref} = [ @{ $prefs->get($pref) }, "-1" ];
        }

	$paramRef->{'titleformatsOptions'}    = Plugins::CustomScan::Plugin::getAvailableTitleFormats();

	return $class->SUPER::handler($client, $paramRef);
}

		
1;
