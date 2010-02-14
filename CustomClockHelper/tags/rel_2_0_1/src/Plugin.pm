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

my $prefs = preferences('plugin.customclockhelper');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.customclockhelper',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_CUSTOMCLOCKHELPER',
});

my $PLUGINVERSION = undef;

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
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	Slim::Control::Request::addDispatch(['customclock','styles'], [0, 1, 0, \&getClockStyles]);
	Slim::Control::Request::addDispatch(['customclock', 'changedstyles'],[0, 1, 0, undef]);
	${Slim::Music::Info::suffixes}{'binfile'} = 'binfile';
	${Slim::Music::Info::types}{'binfile'} = 'application/octet-stream';
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
	$response->header("Content-Disposition","attachment; filename=\"".$params->{'style'}.".json\"");
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
		my $response = $http->get("http://erlandplugins.googlecode.com/svn/CustomClock/trunk/clockstyles2.json");
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
	Slim::Control::Request::notifyFromArray($client,['customclock','changedstyles',\@stylesArray]);
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
	Slim::Control::Request::notifyFromArray($client,['customclock','changedstyles',\@stylesArray]);
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

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
