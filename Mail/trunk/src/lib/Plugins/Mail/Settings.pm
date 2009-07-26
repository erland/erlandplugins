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
package Plugins::Mail::Settings;

use strict;
use base qw(Plugins::Mail::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings;
use Crypt::Tea;

my $prefs = preferences('plugin.mail');
my $log   = logger('plugin.mail');

my $plugin; # reference to main plugin

# migrate old prefs across
$prefs->migrate(1, sub {
        $prefs->set('pollinginterval', 5);
        $prefs->set('mailfolder', "INBOX");

        1;
});

$prefs->setValidate({'validator' => 'intlimit', 'low' => 1,}, 'pollinginterval');

sub new {
	my $class = shift;
	$plugin   = shift;

	$class->SUPER::new($plugin,1);
}

sub name {
	return 'PLUGIN_MAIL';
}

sub page {
	return 'plugins/Mail/settings/basic.html';
}

sub currentPage {
	return Slim::Utils::Strings::string('PLUGIN_MAIL_SETTINGS');
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
        return ($prefs, qw(mailhost mailtype mailaccount mailfolder pollinginterval));
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	if ($paramRef->{'saveSettings'} && $paramRef->{'pref_mailpassword'}) {
		$prefs->set('mailpassword', encrypt($paramRef->{'pref_mailpassword'},"Six by nine. Forty two."));
	}elsif(!$paramRef->{'saveSettings'}) {
		$paramRef->{'pref_mailpassword'} = decrypt($prefs->get('mailpassword'),"Six by nine. Forty two.");
	}
	my $result = $class->SUPER::handler($client, $paramRef);

	return $result;
}

		
1;
