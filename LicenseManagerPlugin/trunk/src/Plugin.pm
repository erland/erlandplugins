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

package Plugins::LicenseManagerPlugin::Plugin;

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
if ( main::WEBUI ) {
	require Plugins::LicenseManagerPlugin::Settings;
}
use Digest::SHA1 qw(sha1_hex);
use Date::Parse qw(str2time);
use LWP::UserAgent;
use XML::Simple;
use Slim::Networking::SimpleAsyncHTTP;

our $PLUGINVERSION =  undef;

my $prefs = preferences('plugin.licensemanager');
my $multiLibraryPrefs = preferences('plugin.licensemanager');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.licensemanager',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_LICENSEMANAGER',
});

$prefs->migrate(1, sub {
	$prefs->set('licenses', {}  );
	1;
});

sub getDisplayName {
	return 'PLUGIN_LICENSEMANAGER';
}

sub repos {
	my %repos = (
		'http://erlandplugins.googlecode.com/svn/LicenseManagerPlugin/trunk/repositories/licensedplugins.xml'   => 1,
		'http://erlandplugins.googlecode.com/svn/LicenseManagerPlugin/trunk/repositories/licensedapplets.xml'   => 2,
		'http://erlandplugins.googlecode.com/svn/LicenseManagerPlugin/trunk/repositories/licensedpatches.xml'   => 3,
	);
	return \%repos;
}

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	if ( main::WEBUI ) {
		Plugins::LicenseManagerPlugin::Settings->new();
	}

	Slim::Control::Request::addDispatch(['licensemanager','validate'], [0, 1, 1, \&validateLicense]);
	Slim::Control::Request::addDispatch(['licensemanager','applications'], [0, 1, 1, \&getApplications]);
}

sub getAccountId() {
	my $accountId = $serverPrefs->get('sn_email');
	if(defined($accountId) && $accountId ne '') {
		$accountId = sha1_hex($accountId);
		return $accountId;
	}else {
		return undef;
	}
}

sub getAccountName() {
	my $accountName = $serverPrefs->get('sn_email');
	if(defined($accountName) && $accountName ne '') {
		return $accountName;
	}else {
		return undef;
	}
}


sub validateLicense {
	my $request = shift;
	$log->debug("Entering validateLicense");

	if ($request->isNotQuery([['licensemanager'],['validate']])) {
		$log->warn("Incorrect command");
		$request->setStatusBadDispatch();
		$log->debug("Exiting validateLicense");
		return;
	}

	my $applicationId = $request->getParam('application');
	if(!defined $applicationId || $applicationId eq '') {
		$log->warn("application not defined");
		$request->setStatusBadParams();
		$log->debug("Exiting validateLicense");
		return;
	}

	my $version = $request->getParam('version');
	
	my $licenses = $prefs->get('licenses');

	my $accountId = getAccountId();

	if(defined($request->getParam('force')) && $request->getParam('force')) {
		loadLicense($accountId,$applicationId,$version);
	}

	if(checkValidityPeriod($licenses,$accountId,$applicationId,$version)) {
		$request->addResult('result', 1);
		$request->setStatusDone();
		$log->debug("Exiting validateLicense");
		return;
	}

	if(!defined($request->getParam('force')) || !$request->getParam('force')) {
		if((defined($licenses->{$applicationId}) && !defined($licenses->{$applicationId}->{'date'})) ||
			(defined($licenses->{$applicationId}) && defined($licenses->{$applicationId}->{'nextcheck'}))) {

			if($licenses->{$applicationId}->{'nextcheck'}<time()) {
				loadLicense($accountId,$applicationId,$version);
				if(checkValidityPeriod($licenses,$accountId,$applicationId,$version)) {
					$request->addResult('result', 1);
					$request->setStatusDone();
					$log->debug("Exiting validateLicense");
					return;
				}
			}
		}else {
			loadLicense($accountId,$applicationId,$version);
			if(checkValidityPeriod($licenses,$accountId,$applicationId,$version)) {
				$request->addResult('result', 1);
				$request->setStatusDone();
				$log->debug("Exiting validateLicense");
				return;
			}
		}
	}

	$request->addResult('result', 0);
	$request->setStatusDone();
	$log->debug("Exiting validateLicense");
}

sub checkValidityPeriod {
	my $licenses = shift;
	my $accountId = shift;
	my $applicationId = shift;
	my $version = shift;

	if(defined($licenses->{$applicationId})) {
		if(defined($licenses->{$applicationId}->{'date'})) {
			if($licenses->{$applicationId}->{'checksum'} eq sha1_hex("$PLUGINVERSION:$applicationId:".(defined($version)?$version:"").":".$licenses->{$applicationId}->{'date'}.":$accountId")) {
				my $time = str2time($licenses->{$applicationId}->{'date'});
				if(time()<=$time) {
					return 1;
				}
			}
		}
	}
	return 0;
}

sub loadLicense {
	my $accountId = shift;
	my $applicationId = shift;
	my $version = shift;

	my $versionString = "";
	if(defined($version)) {
		$versionString="&version=$version";
	}else {
		$version = "";
	}

	$log->info("Retrieving license for $applicationId");
	my $http = LWP::UserAgent->new;
	my $response = $http->get("http://license.isaksson.info/getlicense.php?user=$accountId&application=$applicationId$versionString");
	if($response->is_success) {
		my $date = $response->content;
		$date =~ s/\015?\012?$//;
		my $licenses = $prefs->get('licenses');
		if(defined($date) and $date ne '') {
			$licenses->{$applicationId} = {
				'name' => $applicationId,
				'date' => $date,
				'checksum' => sha1_hex("$PLUGINVERSION:$applicationId:$version:$date:$accountId")
			};
			my $time = str2time($licenses->{$applicationId}->{'date'});
			if($time<time()) {
				$licenses->{$applicationId}->{'nextcheck'} = time()+3600*24;
			}
		}else {
			$licenses->{$applicationId} = {
				'name' => $applicationId,
				'date' => undef,
				'nextcheck' => time()+3600*24,
			};
		}
		$prefs->set('licenses',$licenses);
	}
}

sub getApplications {
	my $request = shift;

	if ($request->isNotQuery([['licensemanager','applications']])) {
		$log->warn("Incorrect command");
		$request->setStatusBadDispatch();
		return;
	}

	my $type = $request->getParam('type');
	my $targetPlat = $request->getParam('targetPlat');
	my $targetVers = $request->getParam('targetVers');
	my $lang = $request->getParam('lang');

	my $repos = repos();
	my $data = { remaining => scalar keys %$repos, results => [] };

	for my $repo (keys %$repos) {

		getExtensions({
			'name'   => $repo, 
			'type'   => $type, 
			'target' => $targetPlat,
			'version'=> $targetVers, 
			'lang'   => $lang,
			'cb'     => \&_getApplicationsCB,
			'pt'     => [ $request, $data ],
		});
	}

	if (!scalar keys %$repos) {

		_getApplicationsCB($request, $data, []);
	}

	if (!$request->isStatusDone()) {

		$request->setStatusProcessing();
	}
}

sub _getApplicationsCB {
	my $request = shift;
	my $data    = shift;
	my $res     = shift;

	push @{$data->{'results'}}, @$res;

	return if (--$data->{'remaining'} > 0);

	$request->addResult('count',scalar(@{$data->{'results'}}));
	$request->addResult('item_loop',$data->{'results'});

	$request->setStatusDone();
}

sub getExtensions {
	my $args = shift;

	my $cache = Slim::Utils::Cache->new;

	if ( my $cached = $cache->get( $args->{'name'} . '_XML' ) ) {

		main::DEBUGLOG && $log->debug("using cached extensions xml $args->{name}");
	
		_parseXML($args, $cached);

	} else {
	
		main::DEBUGLOG && $log->debug("fetching extensions xml $args->{name}");

		Slim::Networking::SimpleAsyncHTTP->new(
			\&_parseResponse, \&_noResponse, { 'args' => $args, 'cache' => 1 }
		)->get( $args->{'name'} );
	}
}

sub _parseResponse {
	my $http = shift;
	my $args = $http->params('args');

	my $xml  = {};

	eval { 
		$xml = XMLin($http->content,
			SuppressEmpty => undef,
			KeyAttr     => { 
				title   => 'lang', 
				desc    => 'lang',
			},
			ContentKey  => '-content',
			GroupTags   => {
				applets => 'applet', 
				plugins => 'plugin',
				patches => 'patch',
			},
			ForceArray => [ 'applet', 'wallpaper', 'sound', 'plugin', 'patch', 'title', 'desc', 'changes' ],
		 );
	};

	if ($@) {

		$log->warn("Error parsing $args->{name}: $@");

	} else {

		my $cache = Slim::Utils::Cache->new;
		
		$cache->set( $args->{'name'} . '_XML', $xml, '5m' );
	}

	_parseXML($args, $xml);
}

sub _noResponse {
	my $http = shift;
	my $error= shift;
	my $args = $http->params('args');

	$log->warn("error fetching $args->{name} - $error");

	if ($args->{'onError'}) {
		$args->{'onError'}->( $args->{'name'}, $error );
	}

	$args->{'cb'}->( @{$args->{'pt'}}, [] );
}

sub _parseXML {
	my $args = shift;
	my $xml  = shift;

	my $typeList    = $args->{'type'};
	my $target  = $args->{'target'};
	my $version = $args->{'version'};
	my $lang    = $args->{'lang'};
	my $details = $args->{'details'};
	my $forcedCheck = $args->{'forcedCheck'} || 0;

	my $types = {};
	my @values = split(',',$typeList);
	for my $t (@values) {
		$types->{$t}=1;
	}
	my $targetRE = $target ? qr/$target/ : undef;

	my $debug = main::DEBUGLOG && $log->is_debug;

	my $repoTitle;
	
	$debug && $log->debug("searching $args->{name} for type: $typeList target: $target version: $version");

	my @res = ();
	my $info;

	for my $type (keys %$types) {
		if ($xml->{ $type . 's' } && ref $xml->{ $type . 's' } eq 'ARRAY') {

			for my $entry (@{ $xml->{ $type . 's' } }) {

				if ($version && $entry->{'minTarget'} && $entry->{'maxTarget'}) {
					if (!Slim::Utils::Versions->checkVersion($version, $entry->{'minTarget'}, $entry->{'maxTarget'})) {
						$debug && $log->debug("entry $entry->{name} does not match, bad target version [$version outside $entry->{minTarget}, $entry->{maxTarget}]");
						next;
					}
				}

				my $new = {
					'name'    => $entry->{'name'},
				};

				if ($entry->{'licenseLink'}) {
					$new->{'licenseLink'} = $entry->{'licenseLink'};
				}

				$debug && $log->debug("entry $new->{name}");

				my $request = Slim::Control::Request::executeRequest(undef,['licensemanager','validate','application:'.$entry->{'name'},'version:'.$entry->{'version'},'force:'.$forcedCheck]);
				my $result = $request->getResult("result");
				if($result) {
					$new->{'licensed'} = 1
				}

				if ($details) {

					if ($entry->{'title'} && ref $entry->{'title'} eq 'HASH') {
						$new->{'title'} = $entry->{'title'}->{ $lang } || $entry->{'title'}->{ 'EN' };
					} else {
						$new->{'title'} = $entry->{'name'};
					}
				
					if ($entry->{'desc'} && ref $entry->{'desc'} eq 'HASH') {
						$new->{'desc'} = $entry->{'desc'}->{ $lang } || $entry->{'desc'}->{ 'EN' };
					}
				
					$new->{'creator'} = $entry->{'creator'} if $entry->{'creator'};
					$new->{'email'}   = $entry->{'email'}   if $entry->{'email'};
				}

				push @res, $new;
			}

		} else {

			$debug && $log->debug("no $type entry in $args->{name}");
		}
	}

	if ($details) {

		if ( $xml->{details} && $xml->{details}->{title} 
				 && ($xml->{details}->{title}->{$lang} || $xml->{details}->{title}->{EN}) ) {
			
			$repoTitle = $xml->{details}->{title}->{$lang} || $xml->{details}->{title}->{EN};
			
		} else {
			
			# fall back to repo's URL if no title is provided
			$repoTitle = $args->{name};
		}
		
		$info = {
			'name'   => $args->{'name'},
			'title'  => $repoTitle,
		};
		
	}

	$debug && $log->debug("found " . scalar(@res) . " extensions");

	$args->{'cb'}->( @{$args->{'pt'}}, \@res, $info );
}


1;

__END__
