# 				MythTV plugin 
#
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

package Plugins::MythTV::Plugin;

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;
use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Unicode;
use File::Spec::Functions qw(:ALL);
use File::Slurp;
use HTTP::Date qw(time2str);
use Plugins::MythTV::Template::Reader;

use MythTV;

use Plugins::MythTV::Settings;

use Slim::Schema;
use Data::Dumper;

my $prefs = preferences('plugin.mythtv');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.mythtv',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_MYTHTV',
});

# Information on each portable library
my $htmlTemplate = 'plugins/MythTV/index.html';
my $PLUGINVERSION = undef;

my $ICONS = {};
my $driver;
my $cache = undef;

sub getDisplayName {
	return 'PLUGIN_MYTHTV';
}

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	Plugins::MythTV::Settings->new($class);

	checkDefaults();
	my $cachedir = $serverPrefs->get('cachedir');
	my $icondir  = catdir( $cachedir, 'MythTVIcons' );
	mkdir $icondir;

	$driver = $serverPrefs->get('dbsource');
	$driver =~ s/dbi:(.*?):(.*)$/$1/;

	$cache = Slim::Utils::Cache->new();
    
	if(UNIVERSAL::can("Slim::Schema","sourceInformation")) {
		my ($source,$username,$password);
		($driver,$source,$username,$password) = Slim::Schema->sourceInformation;
	}
	if($driver ne 'mysql') {
		eval "require DBIx::Class::Storage::DBI::mysql;";
		if($@) {
			$log->error("Unable to load MySQL driver: $@");
		}
	}

	
	eval {
                require GD;
                if (!GD::Image->can('jpeg')) {
			$log->error("GD doesn't support jpeg resizing, no icons will be available for MythTV in Squeezeplay");
                }
        };
	if($@) {
		$log->error("Unable to load GD: $@");
	}

	Slim::Music::TitleFormatter::addFormat('MYTHTVRECORDINGINDICATION',\&titleFormatRecordingIndication,1);
	Slim::Music::TitleFormatter::addFormat('MYTHTVRECORDING',\&titleFormatRecording,1);
	Slim::Music::TitleFormatter::addFormat('MYTHTVPENDINGRECORDING',\&titleFormatPendingRecording,1);
	addTitleFormat("MYTHTVRECORDINGINDICATION");
	addTitleFormat("MYTHTVRECORDING");
	addTitleFormat("MYTHTVPENDINGRECORDING");
}

sub postinitPlugin {
	my $sdtInstalled;
	if(UNIVERSAL::can("Slim::Utils::PluginManager","isEnabled")) {
		$sdtInstalled = Slim::Utils::PluginManager->isEnabled("Plugins::SuperDateTime::Plugin");
	}else {
		$sdtInstalled = grep(/DynamicPlayList/, Slim::Utils::PluginManager->enabledPlugins(undef));
	}
	if ($sdtInstalled) {
		if(UNIVERSAL::can("Plugins::SuperDateTime::Plugin","addCustomDisplayItemHash")) {
			Plugins::SuperDateTime::Plugin::registerProvider(\&refreshSDT)
		}		
	}

	my $customClockInstalled;
	if(UNIVERSAL::can("Slim::Utils::PluginManager","isEnabled")) {
		$customClockInstalled = Slim::Utils::PluginManager->isEnabled("Plugins::CustomClockHelper::Plugin");
	}else {
		$customClockInstalled = grep(/CustomClockHelper/, Slim::Utils::PluginManager->enabledPlugins(undef));
	}
	if ($customClockInstalled) {
		if(UNIVERSAL::can("Plugins::CustomClockHelper::Plugin","addCustomClockCustomItemProvider")) {
			Plugins::CustomClockHelper::Plugin::addCustomClockCustomItemProvider("mythtvactive","MythTV Active Recordings", \&refreshCustomClockActiveRecordings);
			Plugins::CustomClockHelper::Plugin::addCustomClockCustomItemProvider("mythtvpending","MythTV Pending Recordings", \&refreshCustomClockPendingRecordings);
		}		
	}
}

sub addTitleFormat
{
	my $titleformat = shift;
	my $titleFormats = $serverPrefs->get('titleFormat');
	foreach my $format ( @$titleFormats ) {
		if($titleformat eq $format) {
			return;
		}
	}
	$log->debug("Adding: $titleformat");
	push @$titleFormats,$titleformat;
	$serverPrefs->set('titleFormat',$titleFormats);
}

sub titleFormatRecordingIndication
{
	$log->debug("Entering titleFormatRecordingIndication");
	my $recordings = getCachedActiveRecordings();
	if(scalar(@$recordings)>0) {
		$log->debug("Exiting titleFormatRecordingIndication with recording");
		return string("PLUGIN_MYTHTV_RECORDING")."...";
	}
	$log->debug("Exiting titleFormatRecordingIndication with undef");
	return undef;
}

sub titleFormatRecording
{
	$log->debug("Entering titleFormatRecording");
	my $recordings = getCachedActiveRecordings();
	if(scalar(@$recordings)>0) {
		$log->debug("Exiting titleFormatRecording with recordings");
		my $shows = ($prefs->get("titleformatactiverecordingstext")?$prefs->get("titleformatactiverecordingstext"):string("PLUGIN_MYTHTV_RECORDING")).": ";
		my $first = 1;
		foreach my $recording (@$recordings) {
			if(!$first) {
				$shows .= ", ";
			}
			$shows .= $recording->{'title'};
			$first = 0;
		}
	}
	$log->debug("Exiting titleFormatRecording with undef");
	return undef;
}

sub titleFormatPendingRecording
{
	$log->debug("Entering titleFormatPendingRecording");
	my $recordings = getCachedPendingRecordings();
	if(scalar(@$recordings)>0) {
		$log->debug("Exiting titleFormatPendingRecording with recordings");
		my $shows = ($prefs->get("titleformatpendingrecordingstext")?$prefs->get("titleformatpendingrecordingstext"):string("PLUGIN_MYTHTV_PENDINGRECORDING")).": ";
		my $index = 0;
		my $max = $prefs->get('titleformatmaxrecordings') || 3;
		foreach my $recording (@$recordings) {
			if($index) {
				$shows .= ", ";
			}
			$shows .= $recording->{'title'};
			$index++;
			if($index>=$max) {
				last;
			}
		}
		return $shows;
	}
	$log->debug("Exiting titleFormatPendingRecording with undef");
	return undef;
}

sub webPages {

	my %pages = (
		"MythTV/index\.(?:htm|xml)"     => \&handleWebActiveRecordings,
		"MythTV/previousrecordings\.(?:htm|xml)"     => \&handleWebPreviousRecordings,
		"MythTV/pendingrecordings\.(?:htm|xml)"     => \&handleWebPendingRecordings,
		"MythTV/activerecordings\.(?:htm|xml)"     => \&handleWebActiveRecordings,
		"MythTV/geticon.*\.(?:jpg|png)"     => \&handleWebGetIcon,
	);

	for my $page (keys %pages) {
		if(UNIVERSAL::can("Slim::Web::Pages","addPageFunction")) {
			Slim::Web::Pages->addPageFunction($page, $pages{$page});
		}else {
			Slim::Web::HTTP::addPageFunction($page, $pages{$page});
		}
	}
	Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_MYTHTV' => 'plugins/MythTV/index.html' });
}

sub handleWebGetIcon {
	my ($client, $params) = @_;

	if($ICONS->{$params->{'ChanId'}}) {
		$log->debug("Getting icon ".$params->{'ChanId'}." by using url: ".$params->{'path'});
		if($params->{'path'} =~ /.*\/geticon_(\d+)x(\d+)_?.*\.png/) {
			my $requestedWidth = $1;
			my $requestedHeight = $2;
			my $content = read_file(createResizedImage("MythTVIcons",$params->{'ChanId'},$requestedWidth,$requestedHeight));
			return \$content;
		}
		my $cachedir = $serverPrefs->get('cachedir');
		my $icondir  = catdir( $cachedir, 'MythTVIcons' );
		my $content = read_file(catfile($icondir,$params->{'ChanId'}));
		return \$content;
	}
	return undef;
}

sub createResizedImage {
	my $cacheKey = shift;
	my $image = shift;
	my $requestedWidth = shift;
	my $requestedHeight = shift;
	
	$log->debug("Getting cached image for channel $image with size $requestedWidth,$requestedHeight");
	my $cachedir = $serverPrefs->get('cachedir');
	my $icondir  = catdir( $cachedir, $cacheKey );
	if(-e catfile($icondir,$image."_".$requestedWidth."_".$requestedHeight)) {
		$log->debug("Getting from cache");
		return catfile($icondir,$image."_".$requestedWidth."_".$requestedHeight);
	}else {
		$log->debug("Resizing");
		my $imageData = read_file(catfile($icondir,$image));
		my $origImage   = GD::Image->newFromPngData($imageData);

		my $sourceWidth = $origImage->width;
		my $sourceHeight = $origImage->height;
		my $destWidth = undef;
		my $destHeight = undef;

		if ( $sourceWidth > $sourceHeight ) {
                        $destWidth  = $requestedWidth;
                        $destHeight = $sourceHeight / ( $sourceWidth / $requestedWidth );
                }
                elsif ( $sourceHeight > $sourceWidth ) {
                        $destWidth  = $sourceWidth / ( $sourceHeight / $requestedWidth );
                        $destHeight = $requestedWidth;
                }
                else {
                        $destWidth = $destHeight = $requestedWidth;
                }

		# GD doesn't round correctly
                $destHeight =     Slim::Utils::Misc::round($destHeight);
                $destWidth =      Slim::Utils::Misc::round($destWidth);
		my $newImage = GD::Image->new($destWidth, $destHeight);

		$newImage->saveAlpha(1);
                $newImage->alphaBlending(0);
                $newImage->filledRectangle(0, 0, $destWidth, $destHeight, 0x7f000000);

		# use faster Resize algorithm on slower machines
                if ($serverPrefs->get('resampleArtwork')) {

                        $log->info("Resampling file for better quality");
                        $newImage->copyResampled(
                                $origImage,
                                0, 0,
                                0, 0,
                                $destWidth, $destHeight,
                                $sourceWidth, $sourceHeight
                        );

                } else {

                        $log->info("Resizing file for faster processing");
                        $newImage->copyResized(
                                $origImage,
                                0, 0,
                                0, 0,
                                $destWidth, $destHeight,
                                $sourceWidth, $sourceHeight
                        );
                }
		my $newImageData = $newImage->png();
		my $fh;
		open($fh,"> ".catfile($icondir,$image."_".$requestedWidth."_".$requestedHeight)) or do {
	            $log->error("Error saving resized icon: ".$!)
		};
		if(defined($fh)) {
			print $fh $newImageData;
			close $fh;
		}
		return catfile($icondir,$image."_".$requestedWidth."_".$requestedHeight);
	}
	
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params, $lines) = @_;

	$params->{'pluginMythTVItems'} = $lines;
	$params->{'pluginMythTVVersion'} = $PLUGINVERSION;
	if(defined($params->{'redirect'})) {
		return Slim::Web::HTTP::filltemplatefile('plugins/MythTV/mythtv_redirect.html', $params);
	}else {
		return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
	}
}

sub handleWebActiveRecordings {
	my ($client, $params) = @_;
	my $lines = getActiveRecordings();
	return handleWebList($client, $params, $lines);
}

sub handleWebPreviousRecordings {
	my ($client, $params) = @_;
	my $lines = getPreviousRecordings();
	return handleWebList($client, $params, $lines);
}

sub handleWebPendingRecordings {
	my ($client, $params) = @_;
	my $lines = getPendingRecordings();
	return handleWebList($client, $params, $lines);
}

sub getPendingRecordings {
	my $maxEntries = shift || 20;
	my $mythtv = new MythTV();

	my %rows = $mythtv->backend_rows('QUERY_GETALLPENDING');

	my $host = $mythtv->backend_setting('BackendServerIP');
	my $port = $mythtv->backend_setting('BackendStatusPort');

	my @lines = ();
	my $i=0;
	my $iconURLs = {};
	foreach my $row (@{$rows{'rows'}}) {
		if($i>$maxEntries) {
			last;
		}
		my $show;
		{
			# MythTV::Program currently has a slightly broken line with a numeric
			# comparision.
			local($^W) = undef;
			shift @$row;
			my $program = getProgram($mythtv,$row);
			if(defined($program)) {
				push @lines,$program if defined $program;
				$i++;
				if($program->{'icon'}) {
					my $url = "http://$host:$port/Myth/GetChannelIcon?ChanId=".$program->{'icon'};
					$iconURLs->{$program->{'icon'}} = $url;
				}
			}
		}
	}
	
	retrieveIcons($iconURLs);

	$mythtv = undef;
	return \@lines;
}

sub retrieveIcons {
	my $iconURLs = shift;

	my @iconURLArray = ();
	for my $id (keys %$iconURLs) {
		my $entry = {
			'id' => $id,
			'url' => $iconURLs->{$id},
		};
		push @iconURLArray,$entry;
	}
	if(scalar(@iconURLArray)>0) {
		$log->debug("Initiating icon caching logic");
		my @args = (\@iconURLArray);
		Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 0.1, \&cacheNextIcon, @args);	
	}else {
		$log->debug("No icons to cache");
	}
}

sub cacheNextIcon {
	my $client = shift;
        my $iconsToGet  = shift;

	my $icon = pop @$iconsToGet;
	my $iconurl = $icon->{'url'};
	my $iconid = $icon->{'id'};
        
	my $cachedir = $serverPrefs->get('cachedir');
        my $icondir  = catdir( $cachedir, 'MythTVIcons' );

        if ( $ICONS->{$iconid} ) {
                # already cached
                return;
        }
        
        my $iconpath = catfile( $icondir, $iconid );
        
        if ( $log->is_debug ) {
                $log->debug( "Caching remote icon $iconid as $iconpath" );
        }
        
        $ICONS->{$iconid} = $iconpath;
        
	$log->debug("Caching icon $iconid");
        my $http = Slim::Networking::SimpleAsyncHTTP->new(
                sub {
			$log->debug("Successfully cached icon");
			if(scalar(@$iconsToGet)>0) {
				my @args = ($iconsToGet);
				Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 0.1, \&cacheNextIcon, @args);	
			}else {
				$log->debug("Last icon cached");
			}
		},
                \&cacheIconError,
                {
                        saveAs => $iconpath,
                        iconurl   => $iconurl,
			iconid => $iconid,
                },
        );
        
        my %headers;
        
        if ( -e $iconpath ) {
                $headers{'If-Modified-Since'} = time2str( (stat $iconpath)[9] );
        }
        
        $http->get( $iconurl, %headers );
}

sub cacheIconError {
        my $http  = shift;
        my $error = $http->error;
        my $iconurl  = $http->params('iconurl');
	my $iconid = $http->params('iconid');
        
        $log->error( "Error caching remote icon $iconurl: $error" );
        
        delete $ICONS->{$iconid};
}

sub getActiveRecordings {
	my $maxEntries = shift || 20;

	my $lines = getPendingRecordings($maxEntries);
	my @result = ();
	foreach my $line (@$lines) {
		if($line->{'recstatus'} eq $MythTV::RecStatus_Types{$MythTV::recstatus_recording}) {
			push @result,$line;
		}
	}
	return \@result;
}

sub getPreviousRecordings {
	my $maxEntries = shift || 100;
	my $mythtv = new MythTV();

	my %rows = $mythtv->backend_rows('QUERY_RECORDINGS Delete');

	my $host = $mythtv->backend_setting('BackendServerIP');
	my $port = $mythtv->backend_setting('BackendStatusPort');

	my @lines = ();
	my $i=0;
	my $iconURLs = {};
	foreach my $row (@{$rows{'rows'}}) {
		if($i>$maxEntries) {
			last;
		}
		my $show;
		{
			# MythTV::Program currently has a slightly broken line with a numeric
			# comparision.
			local($^W) = undef;
			my $program = getProgram($mythtv,$row,0);
			if(defined $program) {
				push @lines,$program;
				$i++;

				if($program->{'icon'}) {
					my $url = "http://$host:$port/Myth/GetChannelIcon?ChanId=".$program->{'icon'};
					$iconURLs->{$program->{'icon'}} = $url;
				}
			}
		}
	}

	retrieveIcons($iconURLs);

	$mythtv = undef;
	return \@lines;
}

sub getNextPrograms {
	my $maxEntries = shift||20;

	my $mythtv = new MythTV();
	
	my $sql = "select ".
		"program.title,".
		"program.subtitle,".
		"program.description,".
		"program.category,".
		"channel.chanid,".
		"channel.channum,".
		"channel.callsign,".
		"channel.name,".
		"null filename,".
		"null fs_high,".
		"null fs_low,".
		"unix_timestamp(program.starttime) starttime,".
		"unix_timestamp(program.endtime) endtime,".
		"null duplicate,".
		"null shareble,".
		"null findid,".
		"null hostname,".
		"channel.sourceid,".
		"null cardid,".
		"null inputid,".
		"null recpriority,".
		"null recstatus,".
		"null recordid,".
		"null rectype,".
		"null dupin,".
		"null dupmethod,".
		"null recstartts,".
		"null recendts,".
		"program.previouslyshown,".
		"0 progflags,".
		"null recgroup,".
		"channel.commfree,".
		"channel.outputfilters,".
		"program.seriesid,".
		"program.programid,".
		"null lastmodified,".
		"program.stars,".
		"program.airdate,".
		"if(program.airdate is null,0,1),".
		"null playgroup,".
		"null recpriority2,".
		"null parentid,".
		"null storagegroup,".
		"program.audioprop,".
		"program.videoprop,".
		"program.subtitletypes ".
	"from program left join channel on program.chanid=channel.chanid where endtime>=now() group by channel.callsign,program.chanid,program.starttime order by program.starttime limit $maxEntries";
	my $sth = $mythtv->{'dbh'}->prepare($sql);
	my @lines = ();
	eval {
		$log->debug("Executing $sql");
		$sth->execute();

		while (my @row = $sth->fetchrow) {
			# MythTV::Program currently has a slightly broken line with a numeric
			# comparision.
			local($^W) = undef;
			my $program = getProgram($mythtv,\@row,0);
			push @lines,$program if defined $program;
		}
		$sth->finish;
	};
	if( $@ ) {
		$log->warn("Database error: $DBI::errstr\n$@");
	}

	$mythtv = undef;
	return \@lines;
}

sub getProgram {
	my $mythtv = shift;
	my $row = shift;
	my $onlyRecording = shift;

	$onlyRecording=1 if !defined($onlyRecording);

	my $host = $mythtv->backend_setting('BackendServerIP');
	my $port = $mythtv->backend_setting('BackendStatusPort');

	my $show = new MythTV::Program(@$row);
	my %entry = (
		'channel' => $show->{'channame'},
#		'icon' => "http://$host:$port/Myth/GetChannelIcon?ChanId=".$show->{'chanid'},
		'icon' => $show->{'chanid'},
		'startdate' => Slim::Utils::DateTime::shortDateF($show->{'starttime'}),
		'starttime' => Slim::Utils::DateTime::timeF($show->{'starttime'}),
		'enddate' => Slim::Utils::DateTime::shortDateF($show->{'endtime'}),
		'endtime' => Slim::Utils::DateTime::timeF($show->{'endtime'}),
		'title' => Slim::Utils::Unicode::utf8decode($show->{'title'}),
		'subtitle' => Slim::Utils::Unicode::utf8decode($show->{'subtitle'}),
		'description' => Slim::Utils::Unicode::utf8decode($show->{'description'}),
	);
	if($onlyRecording && (!exists $show->{'recstatus'} || ($show->{'recstatus'} ne $MythTV::recstatus_recording && $show->{'recstatus'} ne $MythTV::recstatus_willrecord))) {
		return undef;
	}elsif(exists $show->{'recstatus'}) {
		$entry{'recstatus'} = $MythTV::RecStatus_Types{$show->{'recstatus'}};
	}

	if($entry{'subtitle'} eq 'Untitled') {
		delete $entry{'subtitle'};
	}
	if($entry{'description'} eq 'No Description') {
		delete $entry{'description'};
	}
	return \%entry;
}

sub getRecording {
	my $mythtv = shift;
	my $row = shift;
	my $host = $mythtv->backend_setting('BackendServerIP');
	my $port = $mythtv->backend_setting('BackendStatusPort');

	my $show = new MythTV::Recording(@$row);
	my %entry = (
		'channel' => $show->{'channame'},
#		'icon' => "http://$host:$port/Myth/GetChannelIcon?ChanId=".$show->{'chanid'},
		'icon' => $show->{'chanid'},
		'startdate' => Slim::Utils::DateTime::shortDateF($show->{'starttime'}),
		'starttime' => Slim::Utils::DateTime::timeF($show->{'starttime'}),
		'enddate' => Slim::Utils::DateTime::shortDateF($show->{'endtime'}),
		'endtime' => Slim::Utils::DateTime::timeF($show->{'endtime'}),
		'title' => Slim::Utils::Unicode::utf8decode($show->{'title'}),
		'subtitle' => Slim::Utils::Unicode::utf8decode($show->{'subtitle'}),
		'description' => Slim::Utils::Unicode::utf8decode($show->{'description'}),
	);
	if(exists $show->{'recstatus'} && ($show->{'recstatus'} ne $MythTV::recstatus_recording && $show->{'recstatus'} ne $MythTV::recstatus_willrecord)) {
		next;
	}else {
		$entry{'recstatus'} = $MythTV::RecStatus_Types{$show->{'recstatus'}};
	}
	if($entry{'subtitle'} eq 'Untitled') {
		delete $entry{'subtitle'};
	}
	if($entry{'description'} eq 'No Description') {
		delete $entry{'description'};
	}
	return \%entry;
}

sub refreshSDT {
	my $timer = shift;
	my $client = shift;
	my $refreshId = shift;

	my $recordings = getCachedActiveRecordings();

	Plugins::SuperDateTime::Plugin::delCustomDisplayGroup("mythtvactive");

	my $idx = 10000;
	foreach my $recording (@$recordings) {
		my $recStatus = ((defined($recording->{'recstatus'}) && $recording->{'recstatus'} eq $MythTV::RecStatus_Types{$MythTV::recstatus_recording})?'Rec':'');

		my $entry = {
			'title' => $recording->{'title'},
			'channel' => $recording->{'channel'},
			'startdate' => $recording->{'startdate'},
			'starttime' => $recording->{'starttime'},
			'endtime' => $recording->{'endtime'},
			'recstatus' => $recStatus,
			'icon' => '/plugins/MythTV/geticon.png?ChanId='.$recording->{'icon'}
		};
		Plugins::SuperDateTime::Plugin::addCustomDisplayItemHash("mythtvactive", $idx,$entry);
		$idx = $idx + 1;
	}

	$recordings = getCachedPendingRecordings();

	Plugins::SuperDateTime::Plugin::delCustomDisplayGroup("mythtvpending");

	$idx = 10000;
	foreach my $recording (@$recordings) {
		my $recStatus = ((defined($recording->{'recstatus'}) && $recording->{'recstatus'} eq $MythTV::RecStatus_Types{$MythTV::recstatus_recording})?'Rec':'');

		my $entry = {
			'title' => $recording->{'title'},
			'channel' => $recording->{'channel'},
			'startdate' => $recording->{'startdate'},
			'starttime' => $recording->{'starttime'},
			'endtime' => $recording->{'endtime'},
			'recstatus' => $recStatus,
			'icon' => '/plugins/MythTV/geticon.png?ChanId='.$recording->{'icon'}
		};
		Plugins::SuperDateTime::Plugin::addCustomDisplayItemHash("mythtvpending", $idx,$entry);
		$idx = $idx + 1;
	}
	Plugins::SuperDateTime::Plugin::refreshData(undef,$client,$refreshId);
}

sub refreshCustomClockActiveRecordings {
	my $reference = shift;
	my $callback = shift;
	
	my $recordings = getCachedActiveRecordings();

	my $result = {};
	my $idx = 10000;
	foreach my $recording (@$recordings) {
		my $recStatus = ((defined($recording->{'recstatus'}) && $recording->{'recstatus'} eq $MythTV::RecStatus_Types{$MythTV::recstatus_recording})?'Rec':'');

		my $entry = {
			'title' => $recording->{'title'},
			'channel' => $recording->{'channel'},
			'startdate' => $recording->{'startdate'},
			'starttime' => $recording->{'starttime'},
			'endtime' => $recording->{'endtime'},
			'recstatus' => $recStatus,
			'icon' => '/plugins/MythTV/geticon.png?ChanId='.$recording->{'icon'}
		};
		$result->{$idx}=$entry;
		$idx = $idx + 1;
	}
	&{$callback}($reference,$result);
}

sub refreshCustomClockPendingRecordings {
	my $reference = shift;
	my $callback = shift;
	
	my $recordings = getCachedPendingRecordings();

	my $result = {};
	my $idx = 10000;
	foreach my $recording (@$recordings) {
		my $recStatus = ((defined($recording->{'recstatus'}) && $recording->{'recstatus'} eq $MythTV::RecStatus_Types{$MythTV::recstatus_recording})?'Rec':'');

		my $entry = {
			'title' => $recording->{'title'},
			'channel' => $recording->{'channel'},
			'startdate' => $recording->{'startdate'},
			'starttime' => $recording->{'starttime'},
			'endtime' => $recording->{'endtime'},
			'recstatus' => $recStatus,
			'icon' => '/plugins/MythTV/geticon.png?ChanId='.$recording->{'icon'}
		};
		$result->{$idx}=$entry;
		$idx = $idx + 1;
	}
	&{$callback}($reference,$result);
}


sub getCachedActiveRecordings {
	my $cachedData = undef;
	my $timestamp = $cache->get("MythTV-ActiveRecordings-timestamp");
	my $pollingInterval = $prefs->get('pollinginterval')||1;
	if(!defined($timestamp) || $timestamp>(time()-($pollingInterval*60))) {
		$cachedData = $cache->get("MythTV-ActiveRecordings-data");
	}
	my $lines = undef;
	if(defined($cachedData)) {
		$lines = $cachedData;
	}else {
		$lines = getActiveRecordings();
		$cache->set("MythTV-ActiveRecordings-timestamp",time());
		$cache->set("MythTV-ActiveRecordings-data",$lines);
	}
	return $lines;
}

sub preprocessInformationScreenActiveRecordings {
	my $client = shift;
	my $screen = shift;

	my $lines = getCachedActiveRecordings($client,$screen);
	return prepareInformationScreenData($client,$screen,$lines);
}

sub getCachedPendingRecordings {
	my $cachedData = undef;
	my $timestamp = $cache->get("MythTV-PendingRecordings-timestamp");
	my $pollingInterval = $prefs->get('pollinginterval')||1;
	if(!defined($timestamp) || $timestamp>(time()-($pollingInterval*60))) {
		$cachedData = $cache->get("MythTV-PendingRecordings-data");
	}
	my $lines = undef;
	if(defined($cachedData)) {
		$lines = $cachedData;
	}else {
		$lines = getPendingRecordings();
		$cache->set("MythTV-PendingRecordings-timestamp",time());
		$cache->set("MythTV-PendingRecordings-data",$lines);
	}
	return $lines;
}

sub preprocessInformationScreenPendingRecordings {
	my $client = shift;
	my $screen = shift;

	my $lines = getCachedPendingRecordings();
	return prepareInformationScreenData($client,$screen,$lines,1);
}

sub prepareInformationScreenData {
	my $client = shift;
	my $screen = shift;
	my $lines = shift;
	my $recordingIndication = shift;

	if(scalar(@$lines)==0) {
		return 0;
	}

	my @empty = ();
	my $groups = \@empty;
	if(exists $screen->{'items'}->{'item'}) {
		$groups = $screen->{'items'}->{'item'};
		if(ref($groups) ne 'ARRAY') {
			push @empty,$groups;
			$groups = \@empty;
		}
	}
	my $menuGroup = {
		'id' => 'menu',
		'type' => 'simplemenu',
	};
	my @menuItems = ();
	my $index = 1;
	foreach my $recording (@$lines) {
		my $group = {
			'id' => $index,
			'type' => 'menuitem',
			'style' => 'item_no_arrow',
		};
		#my $channelName = " (".$recording->{'channel'}.")";
		my $recStatus = '';
		if($recordingIndication) {
			$recStatus = ((defined($recording->{'recstatus'}) && $recording->{'recstatus'} eq $MythTV::RecStatus_Types{$MythTV::recstatus_recording})?' (Rec)':'');
		}
		my @items = ();
		my $text = {
			'id' => 'text',
			'type' => 'text',
			'value' => $recording->{'title'}."\n".$recording->{'startdate'}." ".$recording->{'starttime'}." - ".$recording->{'endtime'}.$recStatus,
		};
		push @items,$text;
		my $icon = {
			'id' => 'icon',
			'type' => 'icon',
			'icon' => '/plugins/MythTV/geticon.png?ChanId='.$recording->{'icon'},
			'preprocessing' => 'artwork',
			'preprocessingData' => 'thumb',
		};
		push @items,$icon;
		$group->{'item'} = \@items;
		push @menuItems, $group;
		$index++;
	}
	$menuGroup->{'item'} = \@menuItems;
	push @$groups,$menuGroup;
	$screen->{'items'}->{'item'} = $groups;
	return 1;
}

sub getInformationScreenScreens {
	my $client = shift;
	return Plugins::MythTV::Template::Reader::getTemplates($client,'MythTV',$PLUGINVERSION,'FileCache/InformationScreen','Screens','xml','template','screen','simple',1);
}

sub getInformationScreenTemplates {
        my $client = shift;
        return Plugins::MythTV::Template::Reader::getTemplates($client,'MythTV',$PLUGINVERSION,'FileCache/InformationScreen','ScreenTemplates','xml');
}

sub getInformationScreenTemplateData {
        my $client = shift;
        my $templateItem = shift;
        my $parameterValues = shift;
        my $data = Plugins::MythTV::Template::Reader::readTemplateData('MythTV','ScreenTemplates',$templateItem->{'id'});
        return $data;
}


sub getInformationScreenScreenData {
        my $client = shift;
        my $templateItem = shift;
        my $parameterValues = shift;
        my $data = Plugins::MythTV::Template::Reader::readTemplateData('MythTV','Screens',$templateItem->{'id'},"xml");
        return $data;
}

sub checkDefaults {
	my $prefVal = $prefs->get('backend_host');
	if (! defined $prefVal) {
		# Default to standard library directory
		$log->debug("Defaulting backend_host to: localhost\n");
		$prefs->set('backend_host', 'localhost');
	}
	my $prefVal = $prefs->get('pollinginterval');
	if (! defined $prefVal) {
		# Default to standard library directory
		$log->debug("Defaulting pollinginterval to: 1 minute\n");
		$prefs->set('pollinginterval', 1);
	}
}

# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

# don't use the external one because it doesn't know about the difference
# between a param and not...
#*unescape = \&URI::Escape::unescape;
sub unescape {
        my $in      = shift;
        my $isParam = shift;

        $in =~ s/\+/ /g if $isParam;
        $in =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

        return $in;
}

1;

__END__
