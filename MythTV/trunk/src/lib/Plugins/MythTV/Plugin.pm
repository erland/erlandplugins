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
		my $cachedir = $serverPrefs->get('cachedir');
		my $icondir  = catdir( $cachedir, 'MythTVIcons' );
		my $content = read_file(catfile($icondir,$params->{'ChanId'}));
		return \$content;
	}
	return undef;
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
					cacheIcon($url,$program->{'icon'});
				}
			}
		}
	}
	$mythtv = undef;
	return \@lines;
}

sub cacheIcon {
        my ( $iconurl, $iconid ) = @_;
        
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
        
        my $http = Slim::Networking::SimpleAsyncHTTP->new(
                sub {},
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
	my $mythtv = new MythTV();

	my $host = $mythtv->backend_setting('BackendServerIP');
	my $port = $mythtv->backend_setting('BackendStatusPort');

	$mythtv->backend_rows('QUERY_RECORDINGS Delete');
	my %rows = $mythtv->backend_rows('QUERY_RECORDINGS Recording');

	my @lines = ();
	my $i=0;
	foreach my $row (@{$rows{'rows'}}) {
		if($i>$maxEntries) {
			last;
		}
		my $show;
		{
			# MythTV::Program currently has a slightly broken line with a numeric
			# comparision.
			local($^W) = undef;
			my $program = getProgram($mythtv,$row);
			if(defined $program) {
				push @lines,$program;
				$i++;

				if($program->{'icon'}) {
					my $url = "http://$host:$port/Myth/GetChannelIcon?ChanId=".$program->{'icon'};
					cacheIcon($url,$program->{'icon'});
				}
			}
		}
	}
	$mythtv = undef;
	return \@lines;
}

sub getPreviousRecordings {
	my $maxEntries = shift || 100;
	my $mythtv = new MythTV();

	my %rows = $mythtv->backend_rows('QUERY_RECORDINGS Delete');

	my $host = $mythtv->backend_setting('BackendServerIP');
	my $port = $mythtv->backend_setting('BackendStatusPort');

	my @lines = ();
	my $i=0;
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
					cacheIcon($url,$program->{'icon'});
				}
			}
		}
	}
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

sub checkInformationScreenActiveRecordings {
	my $client = shift;
	my $screen = shift;

	my $lines = getActiveRecordings();
	if(scalar(@$lines)>0) {
		return 1;
	}else {
		return 0;
	}
}

sub preprocessInformationScreenActiveRecordings {
	my $client = shift;
	my $group = shift;


	my $lines = getActiveRecordings();
	$log->error("GOT: ".Dumper($lines));
	return 1;
}

sub preprocessInformationScreenPendingRecordings {
	my $client = shift;
	my $screen = shift;

	my $lines = getPendingRecordings();
	if(scalar(@$lines)==0) {
		return 0;
	}

	my @empty = ();
	my $groups = \@empty;
	if(exists $screen->{'items'}->{'group'}) {
		$groups = $screen->{'items'}->{'group'};
		if(ref($groups) ne 'ARRAY') {
			push @empty,$groups;
			$groups = \@empty;
		}
	}
	my $menuGroup = {
		'id' => 'menu',
		'type' => 'group',
	};
	my @menuItems = ();
	my $index = 1;
	foreach my $recording (@$lines) {
		my $group = {
			'id' => 'item'.$index++,
			'type' => 'group',
			'style' => 'item_no_arrow',
		};
		my @items = ();
		my $text = {
			'id' => 'text',
			'type' => 'label',
			'value' => $recording->{'title'}."\n".$recording->{'startdate'}." ".$recording->{'starttime'},
		};
		push @items,$text;
		my $icon = {
			'id' => 'icon',
			'type' => 'icon',
			'icon' => 'icon',#plugins/CustomBrowse/html/images/custombrowse.png',
			'preprocessing' => 'artwork',
		};
		push @items,$icon;
#		my $arrow = {
#			'id' => 'arrow',
#			'type' => 'icon',
#			'icon' => 'arrow',
#		};
#		push @items,$arrow;
		$group->{'item'} = \@items;
		push @menuItems, $group;
		$index++;
		if($index>5) {
			last;
		}
	}
	$menuGroup->{'item'} = \@menuItems;
	$screen->{'items'}->{'group'} = $menuGroup;
	$log->error("GOT: ".Dumper($screen));
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
