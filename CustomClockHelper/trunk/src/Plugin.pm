# 				Custom Clock Helper plugin 
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

use strict;
use warnings;
                   
package Plugins::CustomClockHelper::Plugin;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);

use LWP::UserAgent;
use JSON::XS;
use Data::Dumper;

use Plugins::CustomClockHelper::StyleSettings;
use Plugins::CustomClockHelper::ImportStyle;
use Plugins::CustomClockHelper::Settings;

my $prefs = preferences('plugin.customclockhelper');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.customclockhelper',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_CUSTOMCLOCKHELPER',
});

my $PLUGINVERSION = undef;

$prefs->migrate(1,sub {
	my @empty = ();
	$prefs->set('titleformats',\@empty)
});

my $customItems = {};
my $refreshCustomItems = undef;
my $customItemProviders = {};

$prefs->migrate(2, sub {
	$prefs->set('customitemsstartuprefreshinterval', 60);
	$prefs->set('customitemsrefreshinterval', 300);
	1;
});

sub getDisplayName()
{
	return string('PLUGIN_CUSTOMCLOCKHELPER'); 
}

sub initPlugin
{
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	Plugins::CustomClockHelper::ImportStyle->new($class);
	Plugins::CustomClockHelper::StyleSettings->new($class);
	Plugins::CustomClockHelper::Settings->new($class);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	Slim::Control::Request::addDispatch(['customclock','styles'], [0, 1, 0, \&getClockStyles]);
	Slim::Control::Request::addDispatch(['customclock', 'titleformats'],[0, 1, 0, \&getTitleFormats]);
	Slim::Control::Request::addDispatch(['customclock', 'customitems'],[0, 1, 0, \&getCustomItems]);
	Slim::Control::Request::addDispatch(['customclock', 'refreshcustomitems'],[0, 1, 0, \&refreshCustomItems]);
	Slim::Control::Request::addDispatch(['customclock', 'changedstyles'],[0, 1, 0, undef]);
	Slim::Control::Request::addDispatch(['customclock', 'titleformatsupdated'],[0, 1, 0, undef]);
	Slim::Control::Request::addDispatch(['customclock', 'changedcustomitems'],[0, 1, 0, undef]);
	Slim::Control::Request::subscribe(\&changedSong,[['playlist'],['newsong','delete','clear']]);
	Slim::Control::Request::subscribe(\&changedSong,[['trackstat'],['changedrating']]);
	${Slim::Music::Info::suffixes}{'binfile'} = 'binfile';
	${Slim::Music::Info::types}{'binfile'} = 'application/octet-stream';
}

sub postinitPlugin {
	my $interval = $prefs->get('customitemsstartuprefreshinterval') || 60;
	Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + ($interval), \&refreshCustomItems);
}

sub addCustomClockCustomItemProvider {
	my $id = shift;
	my $name = shift;
	my $callback = shift;
	
	$customItemProviders->{$id} = {
		name => $name,
		callback => $callback,
	};
}

sub addingCustomItems {
	my $reference = shift;
	my $items = shift;
	
	$log->info("Got refresh answer from $reference with ".(scalar(keys %$items))." number of items");
	$refreshCustomItems->{$reference} = $items;
	delete $customItemProviders->{$reference}->{refreshing};
	$customItemProviders->{$reference}->{refreshed} = 1;

	my $lastProvider = 1;
	for my $id (keys %$customItemProviders) {
		if(defined($customItemProviders->{$id}->{refreshing}) && !$customItemProviders->{$id}->{refreshed}) {
			$lastProvider = 0;
		}
	}
	if($lastProvider) {
		$log->info("This was the last one, finishing...");
		my @providers = ();
		for my $key (keys %$refreshCustomItems) {
			$customItems->{$key} = $refreshCustomItems->{$key};
			push @providers,$key;
		}
		$refreshCustomItems = undef;
		Slim::Control::Request::notifyFromArray(undef,['customclock','changedcustomitems',\@providers]);
		$log->debug("Scheduling next refresh...");
		my $interval = $prefs->get('customitemsrefreshinterval') || 300;
		Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + ($interval), \&refreshCustomItems);
	}else {
		$log->debug("Scheduling refresh of next provider");
		Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 0.1, \&refreshNextProvider);	
	}
}

sub refreshNextProvider {
	Slim::Utils::Timers::killTimers(undef, \&refreshNextProvider); #Paranoia check
	my $refreshInProgress = 0;
	for my $id (keys %$customItemProviders) {
		if(defined($customItemProviders->{$id}->{refreshing}) && !$customItemProviders->{$id}->{refreshed}) {
			$refreshInProgress = 1;
			$log->info("Start refreshing $id");
			eval { 
				&{$customItemProviders->{$id}->{callback}}($id,\&addingCustomItems); 
			};
			if( $@ ) {
				$customItemProviders->{$id}->{refreshError} = 1;
	    		$log->error("Error refreshing $id: $@");
	    		my @empty = ();
	    		addingCustomItems($id,\@empty);
			}
			
		}
	}
}

sub refreshCustomItems {
	my $provider = shift;
	$log->debug("Refreshing custom items: ".($provider?$provider:""));
	Slim::Utils::Timers::killTimers(undef, \&refreshCustomItems); #Paranoia check
	if(scalar(keys %$customItemProviders)>0 && (!defined($provider) || $provider eq "" || defined($customItemProviders->{$provider}))) {
		$log->debug("Preparing for refresh");
		for my $id (keys %$customItemProviders) {
			if((!defined($customItemProviders->{$id}->{refreshing}) || !$customItemProviders->{$id}->{refreshing}) && 
				(!defined($provider) || $provider eq "" || $provider eq $id)) {
					
				$log->debug("Mark $id for refresh");

				$customItemProviders->{$id}->{refreshing} = 1;
				$customItemProviders->{$id}->{refreshed} = 0;
				delete $customItemProviders->{$id}->{refreshError};	
			}
		}	
		if(!defined($refreshCustomItems)) {
			$refreshCustomItems = {};
			$log->debug("Scheduling refresh of next provider");
			Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 0.1, \&refreshNextProvider);	
		}else {
			$log->info("Refresh already in progress, no need to schedule any provider for refresh");
		}
	}elsif(!defined($provider) || $provider eq "") {
		$log->debug("Nothing to refresh, scheduling next refresh...");
		my $interval = $prefs->get('customitemsrefreshinterval') || 300;
		Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + ($interval), \&refreshCustomItems);
	}
}

sub changedSong {
	my $request = shift;

	my $client = $request->client();

	if($request->isCommand([['playlist'],['newsong']])) {
		$log->debug("Got playlist newsong");

	}else {
		$log->debug("Got ".$request->getRequestString());
	}

	my $titleFormatsHash = {};
	my $formats = $prefs->get("titleformats");
	my $songIndex = Slim::Player::Source::playingSongIndex($client);
	my $song = Slim::Player::Playlist::song($client,$songIndex);
	for my $format (@$formats) {
		my $value = undef;
		if(defined($song)) {
			$value = Slim::Music::Info::displayText($client,$song,$format);
		}
		if(defined($value) && $value ne "") {
			$titleFormatsHash->{$format} = $value;
		}else {
			$titleFormatsHash->{$format} = $value;
		}
	}
	Slim::Control::Request::notifyFromArray($client,['customclock','titleformatsupdated',$titleFormatsHash]);
}

sub webPages {
	my %pages = (
		"CustomClockHelper/export\.(?:htm|xml|binfile)" => \&exportJSON,
	);
	for my $page (keys %pages) {
		if(UNIVERSAL::can("Slim::Web::Pages","addPageFunction")) {
			Slim::Web::Pages->addPageFunction($page, $pages{$page});
		}else {
			Slim::Web::HTTP::addPageFunction($page, $pages{$page});
		}
	}
}

sub exportJSON {
	my ($client, $params, $prepareResponseForSending, $httpClient, $response) = @_;
	my $style = Plugins::CustomClockHelper::Plugin->getStyle($params->{'style'}) || {};
	$response->header("Content-Disposition","attachment; filename=\"".$params->{'style'}.".txt\"");
	my $message = JSON::XS::encode_json($style);
	return \$message;
}

sub getStyleKey {
	my $style = shift;

	my $models = $style->{'models'};
	@$models = sort { $a cmp $b } @$models;
	return $style->{'name'}." - ".join(',',@$models);
}

sub getStyles {
	my $localOnly = shift;

	$log->debug("Getting downloaded styles");

	my $styles = {};
	if(!$localOnly) {
		my $http = LWP::UserAgent->new;
		my $response = $http->get("http://erlandplugins.googlecode.com/svn/CustomClock/trunk/clockstyles4.json");
		if($response->is_success) {
			my $jsonStyles = $response->content;
			eval {
				my $decodedStyles = JSON::XS::decode_json($jsonStyles);
				my $stylesArray = $decodedStyles->{'data'}->{'item_loop'};
				for my $item (@$stylesArray) {
					my $key = getStyleKey($item);
					$styles->{$key} = $item;
				}
			};
			if ($@) {
				$log->error("Failed parse online styles:\n$@\n");
			}else {
				$log->debug("Got online styles");
			}
		}else {
			$log->error("Unable to get online styles");
		}
	}
	if($prefs->get("styles")) {
		$log->debug("Got locally saved styles");
		my $localStyles = $prefs->get("styles");
		for my $key (keys %$localStyles) {
			$styles->{$key} = $localStyles->{$key};
		}
	}
	$log->debug("GOT: ".Dumper($styles));
	return $styles;
}

sub getStyle {
	my $self = shift;
	my $style = shift;

	my $styles = getStyles();
	if(defined($styles->{$style})) {
		return $styles->{$style};
	}
	return undef;
}

sub setStyle {
	my $self = shift;
	my $client = shift;
	my $styleId = shift;
	my $styleData = shift;

	my $styles = getStyles(1);
	if(defined($styleData)) {
		$styles->{$styleId} = $styleData;
	}else {
		delete $styles->{$styleId};
	}
	$prefs->set("styles",$styles);

	my @stylesArray = ();
	for my $style (keys %$styles) {
		push @stylesArray,$styles->{$style}
	}
	Slim::Control::Request::notifyFromArray(undef,['customclock','changedstyles',\@stylesArray]);
}

sub renameAndSetStyle {
	my $self = shift;
	my $client = shift;
	my $styleId = shift;
	my $newStyleId = shift;
	my $styleData = shift;

	my $styles = getStyles(1);
	delete $styles->{$styleId};
	$styles->{$newStyleId} = $styleData;
	$prefs->set("styles",$styles);

	my @stylesArray = ();
	for my $style (keys %$styles) {
		push @stylesArray,$styles->{$style}
	}
	Slim::Control::Request::notifyFromArray(undef,['customclock','changedstyles',\@stylesArray]);
}

sub getClockStyles {
	my $request = shift;

	my $styles = getStyles();

	my @stylesArray = ();
	for my $style (keys %$styles) {
		push @stylesArray,$styles->{$style}
	}
	$request->addResult('item_loop', \@stylesArray);
	$request->setStatusDone();
}

sub getCustomItems {
	my $request = shift;

	my $category = $request->getParam('category');
	my $result = {};
	if(defined($category)) {
		$result->{$category} = $customItems->{$category}
	}else {
		$result = $customItems;
	}
	$request->addResult('items', $result);
	$request->setStatusDone();
}

sub getTitleFormats {
	my $request = shift;

	my $client = $request->client();

	my $titleFormatsHash = {};
	my $formats = $prefs->get("titleformats");
	my $songIndex = Slim::Player::Source::playingSongIndex($client);
	my $song = Slim::Player::Playlist::song($client,$songIndex);
	for my $format (@$formats) {
		my $value = undef;
		if(defined($song)) {
			$value = Slim::Music::Info::displayText($client,$song,$format);
		}
		if(defined($value) && $value ne "") {
			$titleFormatsHash->{$format} = $value;
		}else {
			$titleFormatsHash->{$format} = $value;
		}
	}

	$request->addResult('titleformats', $titleFormatsHash);
	$request->setStatusDone();
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
