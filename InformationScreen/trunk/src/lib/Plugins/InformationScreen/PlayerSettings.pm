package Plugins::InformationScreen::PlayerSettings;

use strict;
use base qw(Slim::Web::Settings);
use Slim::Utils::Prefs;
use Slim::Utils::Log;

my $prefs = preferences('plugin.informationscreen');
my $log   = logger('plugin.informationscreen');

sub name {
	return 'PLUGIN_INFORMATIONSCREEN';
}

sub page {
	return 'plugins/InformationScreen/settings/player.html';
}

sub needsClient { 1 }

sub prefs {
	my ($class,$client) = @_;
        return ($prefs->client($client), qw(screengroup));
}

1;

__END__
