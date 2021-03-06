# 				SQLPlayList plugin 
#
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
#
#    Portions of code derived from the Random Mix plugin:
#    Originally written by Kevin Deane-Freeman (slim-mail (A_t) deane-freeman.com).
#    New world order by Dan Sully - <dan | at | slimdevices.com>
#    Fairly substantial rewrite by Max Spicer

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

package Plugins::SQLPlayList::Plugin;

use strict;

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use File::Spec::Functions qw(:ALL);
use File::Slurp;
use XML::Simple;
use Data::Dumper;
use HTML::Entities;
use FindBin qw($Bin);

if ($::VERSION ge '6.5') {
	eval "use Slim::Schema";
}

# Information on each clients sqlplaylist
my $htmlTemplate = 'plugins/SQLPlayList/sqlplaylist_list.html';
my $ds = getCurrentDS();
my $template;
my $playLists = undef;
my $playListTypes = undef;
my $sqlerrors = '';

my %disable = (
	'id' => 'disable', 
	'file' => '', 
	'name' => '', 
	'sql' => '', 
	'fulltext' => ''
);
	
sub getDisplayName {
	return 'PLUGIN_SQLPLAYLIST';
}

sub getCurrentPlayList {
	my $client = shift;
	my $currentPlaying = eval { Plugins::DynamicPlayList::Plugin::getCurrentPlayList($client) };
	if ($@) {
		warn("SQLPlayList: Error getting current playlist from DynamicPlayList plugin: $@\n");
	}
	if($currentPlaying) {
		$currentPlaying =~ s/^sqlplaylist_//;
		my $playlist = getPlayList($client,$currentPlaying);
		if(defined($playlist)) {
			$currentPlaying = $playlist->{'id'};
		}else {
			$currentPlaying = undef;
		}
	}
	return $currentPlaying;
}

# Do what's necessary when play or add button is pressed
sub handlePlayOrAdd {
	my ($client, $item, $add) = @_;
	debugMsg("".($add ? 'Add' : 'Play')."$item\n");
	
	my $currentPlaying = getCurrentPlayList($client);

	# reconstruct the list of options, adding and removing the 'disable' option where applicable
	my $listRef = Slim::Buttons::Common::param($client, 'listRef');
		
	if ($item eq 'disable') {
		pop @$listRef;
		
	# only add disable option if starting a mode from idle state
	} elsif (! $currentPlaying) {
		push @$listRef, \%disable;
	}
	Slim::Buttons::Common::param($client, 'listRef', $listRef);

	my $request;
	if($item eq 'disable') {
		$request = $client->execute(['dynamicplaylist', 'playlist', 'stop']);
	}else {
		$item = "sqlplaylist_".$item;
		$request = $client->execute(['dynamicplaylist', 'playlist', ($add?'add':'play'), $item]);
	}
	if ($::VERSION ge '6.5') {
		# indicate request source
		$request->source('PLUGIN_SQLPLAYLIST');
	}
}

sub getPlayList {
	my $client = shift;
	my $type = shift;
	
	return undef unless $type;

	debugMsg("Get playlist: $type\n");
	if(!$playLists) {
		initPlayLists($client);
	}
	return undef unless $playLists;
	
	return $playLists->{$type};
}
sub initPlayListTypes {
	my $client = shift;
	if(!$playLists) {
		initPlayLists($client);
	}
	my %localPlayListTypes = ();
	for my $playlistId (keys %$playLists) {
		my $playlist = $playLists->{$playlistId};
		my $parameters = $playlist->{'parameters'};
		if(defined($parameters)) {
			my $parameter1 = $parameters->{'1'};
			if(defined($parameter1)) {
				if($parameter1->{'type'} eq 'album' || $parameter1->{'type'} eq 'artist' || $parameter1->{'type'} eq 'year' || $parameter1->{'type'} eq 'genre' || $parameter1->{'type'} eq 'playlist') {
					$localPlayListTypes{$parameter1->{'type'}} = 1;
				}
			}
		}
	}
	$playListTypes = \%localPlayListTypes;
}

sub initPlayLists {
	my $client = shift;
	my @pluginDirs = ();
	if ($::VERSION ge '6.5') {
		@pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	}else {
		@pluginDirs = catdir($Bin, "Plugins");
	}
	my %playlists = ();
	my $templates = readTemplateConfiguration();
	for my $plugindir (@pluginDirs) {
		next unless -d catdir($plugindir,"SQLPlayList","Playlists");
		readPlaylistsFromDir($client,1,catdir($plugindir,"SQLPlayList","Playlists"),\%playlists);
		readTemplatePlaylistsFromDir($client,1,catdir($plugindir,"SQLPlayList","Playlists"),\%playlists,$templates);
	}
	my $playlistDir = Slim::Utils::Prefs::get("plugin_sqlplaylist_playlist_directory");
	debugMsg("Searching for playlists in: $playlistDir\n");
	
	if (defined $playlistDir && -d $playlistDir) {
		readPlaylistsFromDir($client,0,$playlistDir,\%playlists);
		readTemplatePlaylistsFromDir($client,0,$playlistDir,\%playlists,$templates);
	}else {
		debugMsg("Skipping playlist folder scan - playlistdir is undefined.\n");
	}

	my %localPlayLists = ();
	
	for my $playlistId (keys %playlists) {
		my $playlist = parsePlaylist($playlists{$playlistId});
		if(defined($playlist)) {
			$localPlayLists{$playlist->{'id'}} = $playlist;
		}
	}
	$playLists = \%localPlayLists;
	initPlayListTypes($client);
	if(defined($client)) {
		# We need to make sure the playlists in DynamicPlayList plugin is re-read
		my $request = $client->execute(['dynamicplaylist', 'playlists']);
		if ($::VERSION ge '6.5') {
			# indicate request source
			$request->source('PLUGIN_SQLPLAYLIST');
		}
	}
}

sub parsePlaylist {
	my $playlistHash = shift;
	my $playlistData = $playlistHash->{'data'};
	my @playlistDataArray = split(/[\n\r]+/,$playlistData);
	my $name = undef;
	my $statement = '';
	my $fulltext = '';
	my @groups = ();
	my %parameters = ();
	my %options = ();
	for my $line (@playlistDataArray) {
		#Lets add linefeed again, to make sure playlist looks ok when editing
		$line .= "\n";
		if($name && $line !~ /^\s*--\s*PlaylistGroups\s*[:=]\s*/) {
			$fulltext .= $line;
		}
		chomp $line;

		# use "--PlaylistName:" as name of playlist
		$line =~ s/^\s*--\s*PlaylistName\s*[:=]\s*//io;
		
		my $parameter = parseParameter($line);
		my $option = parseOption($line);
		if($line =~ /^\s*--\s*PlaylistGroups\s*[:=]\s*/) {
			$line =~ s/^\s*--\s*PlaylistGroups\s*[:=]\s*//io;
			if($line) {
				my @stringGroups = split(/\,/,$line);
				foreach my $item (@stringGroups) {
					# Remove all white spaces
					$item =~ s/^\s+//;
					$item =~ s/\s+$//;
					my @subGroups = split(/\//,$item);
					push @groups,\@subGroups;
				}
			}
			$line = "";
		}
		if($parameter) {
			$parameters{$parameter->{'id'}} = $parameter;
		}
		if($option) {
			$options{$option->{'id'}} = $option;
		}
			
		# skip and strip comments & empty lines
		$line =~ s/\s*--.*?$//o;
		$line =~ s/^\s*//o;

		next if $line =~ /^--/;
		next if $line =~ /^\s*$/;

		if(!$name) {
			$name = $line;
		}else {
			$line =~ s/\s+$//;
			if($statement) {
				if( $statement =~ /;$/ ) {
					$statement .= "\n";
				}else {
					$statement .= " ";
				}
			}
			$statement .= $line;
		}
	}
	
	if($name && $statement) {
		my $playlistid = escape($name,"^A-Za-z0-9\-_");
		my %playlist = (
			'id' => $playlistid, 
			'file' => $playlistHash->{'file'}, 
			'name' => $name, 
			'sql' => Slim::Utils::Unicode::utf8decode($statement,'utf8') , 
			'fulltext' => Slim::Utils::Unicode::utf8decode($fulltext,'utf8')
		);
		if(defined($playlistHash->{'defaultplaylist'})) {
			$playlist{'defaultplaylist'} = $playlistHash->{'defaultplaylist'};
		}
		if(defined($playlistHash->{'simple'})) {
			$playlist{'simple'} = $playlistHash->{'simple'};
		}
		if(scalar(@groups)>0) {
			$playlist{'groups'} = \@groups;
		}
		if(%parameters) {
			$playlist{'parameters'} = \%parameters;
			foreach my $p (keys %parameters) {
				if(defined($playLists) 
					&& defined($playLists->{$playlistid}) 
					&& defined($playLists->{$playlistid}->{'parameters'})
					&& defined($playLists->{$playlistid}->{'parameters'}->{$p})
					&& $playLists->{$playlistid}->{'parameters'}->{$p}->{'name'} eq $parameters{$p}->{'name'}
					&& defined($playLists->{$playlistid}->{'parameters'}->{$p}->{'value'})) {
					
					debugMsg("Use already existing value PlaylistParameter$p=".$playLists->{$playlistid}->{'parameters'}->{$p}->{'value'}."\n");	
					$parameters{$p}->{'value'}=$playLists->{$playlistid}->{'parameters'}->{$p}->{'value'};
				}
			}
		}
		if(%options) {
			$playlist{'options'} = \%options;
		}
		return \%playlist;
	}
}

sub initPlugin {
	checkDefaults();
}

sub webPages {

	my %pages = (
		"sqlplaylist_list\.(?:htm|xml)"     => \&handleWebList,
		"sqlplaylist_editplaylist\.(?:htm|xml)"      => \&handleWebEditPlaylist,
		"sqlplaylist_newplaylisttypes\.(?:htm|xml)"      => \&handleWebNewPlaylistTypes,
                "sqlplaylist_newplaylistparameters\.(?:htm|xml)"     => \&handleWebNewPlaylistParameters,
		"sqlplaylist_newplaylist\.(?:htm|xml)"      => \&handleWebNewPlaylist,
                "sqlplaylist_savenewsimpleplaylist\.(?:htm|xml)"     => \&handleWebSaveNewSimplePlaylist,
                "sqlplaylist_savesimpleplaylist\.(?:htm|xml)"     => \&handleWebSaveSimplePlaylist,
		"sqlplaylist_saveplaylist\.(?:htm|xml)"      => \&handleWebSavePlaylist,
		"sqlplaylist_savenewplaylist\.(?:htm|xml)"      => \&handleWebSaveNewPlaylist,
		"sqlplaylist_removeplaylist\.(?:htm|xml)"      => \&handleWebRemovePlaylist,
	);

	my $value = $htmlTemplate;

	if (grep { /^SQLPlayList::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

		$value = undef;
	} 

	#Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_SQLPLAYLIST' => $value });

	return (\%pages,$value);
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	# Pass on the current pref values and now playing info
	if(!defined($params->{'donotrefresh'})) {
		initPlayLists($client);
	}
	my $currentPlaying = eval { Plugins::DynamicPlayList::Plugin::getCurrentPlayList($client) };
	if ($@) {
		warn("SQLPlayList: Error getting current playlist from DynamicPlayList plugin: $@\n");
	}
	if($currentPlaying) {
		$currentPlaying =~ s/^sqlplaylist_//;
	}
	my $playlist = getPlayList($client,$currentPlaying);
	my $name = undef;
	if($playlist) {
		$name = $playlist->{'name'};
	}
	$params->{'pluginSQLPlayListPlayLists'} = $playLists;
	$params->{'pluginSQLPlayListNowPlaying'} = $name;
	if ($::VERSION ge '6.5') {
		$params->{'pluginSQLPlayListSlimserver65'} = 1;
	}
	if(!UNIVERSAL::can("Plugins::DynamicPlayList::Plugin","getCurrentPlayList")) {
		$params->{'pluginSQLPlayListError'} = "ERROR!!! Cannot find DynamicPlayList plugin, please make sure you have installed and enabled at least DynamicPlayList 1.3"
	}
	if(defined($params->{'redirect'})) {
		return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_redirect.html', $params);
	}else {
		return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
	}
}

# Draws the plugin's edit playlist web page
sub handleWebEditPlaylist {
	my ($client, $params) = @_;

	$params->{'pluginSQLPlayListError'} = undef;
	if ($::VERSION ge '6.5') {
		$params->{'pluginSQLPlayListSlimserver65'} = 1;
	}
	if(defined($params->{'redirect'})) {
		$params->{'pluginSQLPlayListRedirect'} = 1;
	}

	if ($params->{'type'}) {
		my $playlist = getPlayList($client,$params->{'type'});
		if($playlist) {
			if(defined($playlist->{'simple'})) {
				my $templateData = undef;
	
				my $browseDir = Slim::Utils::Prefs::get("plugin_sqlplaylist_playlist_directory");
				if (!defined $browseDir || !-d $browseDir) {
					debugMsg("Skipping playlist configuration - directory is undefined\n");
				}else {
					$templateData = loadTemplateData($browseDir,$playlist->{'file'});
				}
				if(!defined($templateData)) {
					my @pluginDirs = ();
					if ($::VERSION ge '6.5') {
						@pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
					}else {
						@pluginDirs = catdir($Bin, "Plugins");
					}
					for my $plugindir (@pluginDirs) {
						next unless -d catdir($plugindir,"SQLPlayList","Playlists");
						$templateData = loadTemplateData(catdir($plugindir,"SQLPlayList","Playlists"),$playlist->{'file'});
						if(defined($templateData)) {
							last;
						}
					}
				}
	
				if(defined($templateData)) {
					my $templates = readTemplateConfiguration($client);
					my $template = $templates->{$templateData->{'id'}};
					if(defined($template)) {
						my %currentParameterValues = ();
						my $templateDataParameters = $templateData->{'parameter'};
						for my $p (@$templateDataParameters) {
							my $values = $p->{'value'};
							my %valuesHash = ();
							for my $v (@$values) {
								$valuesHash{$v} = $v;
							}
							if(%valuesHash) {
								$currentParameterValues{$p->{'id'}} = \%valuesHash;
							}
						}
						if(defined($template->{'parameter'})) {
							my $parameters = $template->{'parameter'};
							my @parametersToSelect = ();
							for my $p (@$parameters) {
								if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
									addValuesToTemplateParameter($p,$currentParameterValues{$p->{'id'}});
									push @parametersToSelect,$p;
								}
							}
							$params->{'pluginSQLPlayListEditPlayListParameters'} = \@parametersToSelect;
						}
						$params->{'pluginSQLPlayListEditPlayListFile'} = $playlist->{'file'};
						$params->{'pluginSQLPlayListEditPlayListTemplate'} = $templateData->{'id'};
						$params->{'pluginSQLPlayListEditPlayListFileUnescaped'} = unescape($params->{'pluginSQLPlayListEditPlayListFile'});
						return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_editsimpleplaylist.html', $params);
					}
				}
			}else {
				$params->{'pluginSQLPlayListEditPlayListFile'} = escape($playlist->{'file'});
				$params->{'pluginSQLPlayListEditPlayListName'} = $playlist->{'name'};
				$params->{'pluginSQLPlayListEditPlayListGroups'} = getGroupString($playlist);
				$params->{'pluginSQLPlayListEditPlayListText'} = Slim::Utils::Unicode::utf8decode($playlist->{'fulltext'},'utf8');
				$params->{'pluginSQLPlayListEditPlayListFileUnescaped'} = unescape($params->{'pluginSQLPlayListEditPlayListFile'});
				return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_editplaylist.html', $params);
			}
		}else {
			warn "Cannot find: ".$params->{'type'};
		}
	}
	return handleWebList($client,$params);
}

sub getGroupString {
	my $playlist = shift;

	my $result = undef;
	if(defined($playlist->{'groups'})) {
		foreach my $group (@{$playlist->{'groups'}}) {
			if(defined($result)) {
				$result .= ",";
			}else {
				$result = "";
			}
			my $subresult = undef;
			foreach my $subgroup (@$group) {
				if(defined($subresult)) {
					$subresult .= "/";
				}else {
					$subresult = "";
				}
				$subresult .= $subgroup;
			}
			$result .= $subresult;
		}
	}
	return $result;
}

# Draws the plugin's edit playlist web page
sub handleWebTestNewPlaylist {
	my ($client, $params) = @_;

	handleWebTestPlaylist($client,$params);
	
	return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_newplaylist.html', $params);
}

# Draws the plugin's edit playlist web page
sub handleWebTestEditPlaylist {
	my ($client, $params) = @_;

	handleWebTestPlaylist($client,$params);
	
	return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_editplaylist.html', $params);
}

sub handleWebTestPlaylist {
	my ($client, $params) = @_;
	if(defined($params->{'deletesimple'})) {
		$params->{'pluginSQLPlayListEditPlayListDeleteSimple'} = $params->{'deletesimple'};
	}
	if(defined($params->{'redirect'})) {
		$params->{'pluginSQLPlayListRedirect'} = 1;
	}
	$params->{'pluginSQLPlayListEditPlayListFile'} = $params->{'file'};
	$params->{'pluginSQLPlayListEditPlayListName'} = $params->{'name'};
	$params->{'pluginSQLPlayListEditPlayListText'} = $params->{'text'};
	$params->{'pluginSQLPlayListEditPlayListFileUnescaped'} = unescape($params->{'file'});
	my $ds = getCurrentDS();
	if($params->{'text'}) {
		my $playlist = createSQLPlayList(Slim::Utils::Unicode::utf8decode($params->{'text'},'utf8'));
		if($playlist) {
			if(handleWebTestParameters($client,$params,$playlist)) {
				my $sql = $playlist->{'sql'};
				if(defined($playlist->{'parameters'})) {
					$sql = replaceParametersInSQL($sql,$playlist->{'parameters'});
				}
				$sql = replaceParametersInSQL($sql,getOffsetLimitParameters(100,0),'Playlist');
				my $tracks = executeSQLForPlaylist($sql);
				my @resultTracks;
				my $itemNumber = 0;
				foreach my $track (@$tracks) {
				  	my %trackInfo = ();
		            displayAsHTML('track', \%trackInfo, $track);
				  	$trackInfo{'title'} = Slim::Music::Info::standardTitle(undef,$track);
				  	$trackInfo{'odd'} = ($itemNumber+1) % 2;
		            $trackInfo{'itemobj'}          = $track;
				  	push @resultTracks,\%trackInfo;
				}
				if(@resultTracks && scalar(@resultTracks)>0) {
					$params->{'pluginSQLPlayListEditPlayListTestResult'} = \@resultTracks;
				}
			}
		}
	}

	if($sqlerrors && $sqlerrors ne '') {
		$params->{'pluginSQLPlayListError'} = $sqlerrors;
	}else {
		$params->{'pluginSQLPlayListError'} = undef;
	}
	if ($::VERSION ge '6.5') {
		$params->{'pluginSQLPlayListSlimserver65'} = 1;
	}
}

sub handleWebTestParameters {
	my ($client,$params,$playlist) = @_;
	my $parameterId = 1;
	my @parameters = ();
	
	my $i=1;
	while(defined($params->{'sqlplaylist_parameter_'.$i})) {
		$parameterId = $parameterId +1;
		if($params->{'sqlplaylist_parameter_changed'} eq $i) {
			last;
		}
		$i++;
	}
	if(defined($playlist->{'parameters'}->{$parameterId})) {
		for(my $i=1;$i<$parameterId;$i++) {
			my @parameterValues = ();
			my $parameter = $playlist->{'parameters'}->{$i};
			addParameterValues($client,\@parameterValues,$parameter);
			my %webParameter = (
				'parameter' => $parameter,
				'values' => \@parameterValues,
				'value' => $params->{'sqlplaylist_parameter_'.$i}
			);
			my %value = (
				'id' => $params->{'sqlplaylist_parameter_'.$i}
			);
			$client->param('sqlplaylist_parameter_'.$i,\%value);
			push @parameters,\%webParameter;
		}
		
		my $parameter = $playlist->{'parameters'}->{$parameterId};
		debugMsg("Getting values for: ".$parameter->{'name'}."\n");
		my @parameterValues = ();
		addParameterValues($client,\@parameterValues,$parameter);
		my %currentParameter = (
			'parameter' => $parameter,
			'values' => \@parameterValues
		);
		push @parameters,\%currentParameter;
		$params->{'pluginSQLPlayListTestParameters'} = \@parameters;
		return 0;
	}else {
		for(my $i=1;$i<$parameterId;$i++) {
			$playlist->{'parameters'}->{$i}->{'value'} = $params->{'sqlplaylist_parameter_'.$i};
		}
		return 1;
	}
}

sub addParameterValues {
	my $client = shift;
	my $listRef = shift;
	my $parameter = shift;
	
	debugMsg("Getting values for ".$parameter->{'name'}." of type ".$parameter->{'type'}."\n");
	my $sql = undef;
	if(lc($parameter->{'type'}) eq 'album') {
		$sql = "select id,title from albums order by titlesort";
	}elsif(lc($parameter->{'type'}) eq 'artist') {
		$sql = "select id,name from contributors where namesort is not null order by namesort";
	}elsif(lc($parameter->{'type'}) eq 'genre') {
		$sql = "select id,name from genres order by namesort";
	}elsif(lc($parameter->{'type'}) eq 'year') {
		$sql = "select year,year from tracks where year is not null group by year order by year";
	}elsif(lc($parameter->{'type'}) eq 'playlist') {
		$sql = "select playlist_track.playlist,tracks.title from tracks, playlist_track where tracks.id=playlist_track.playlist group by playlist_track.playlist order by titlesort";
	}elsif(lc($parameter->{'type'}) eq 'list') {
		my $value = $parameter->{'definition'};
		if(defined($value) && $value ne "" ) {
			my @values = split(/,/,$value);
			if(@values) {
				for my $valueItem (@values) {
					my @valueItemArray = split(/:/,$valueItem);
					my $id = shift @valueItemArray;
					my $name = shift @valueItemArray;
					
					if(defined($id)) {
						my %listitem = (
							'id' => $id
						);
						if(defined($name)) {
							$listitem{'name'}=$name;
						}else {
							$listitem{'name'}=$id;
						}
					  	push @$listRef, \%listitem;
					}
				}
			}else {
				debugMsg("Error, invalid parameter value: $value\n");
			}
		}
	}elsif(lc($parameter->{'type'}) eq 'custom') {
		if(defined($parameter->{'definition'}) && lc($parameter->{'definition'}) =~ /^select/ ) {
			$sql = $parameter->{'definition'};
			for (my $i=1;$i<$parameter->{'id'};$i++) {
				my $parameter = $client->param('sqlplaylist_parameter_'.$i);
				my $value = $parameter->{'id'};
				my $parameterid = "\'PlaylistParameter".$i."\'";
				debugMsg("Replacing ".$parameterid." with ".$value."\n");
				$sql =~ s/$parameterid/$value/g;
			}
		}
	}
	
	if(defined($sql)) {
		my $dbh = getCurrentDBH();
    	eval {
			my $sth = $dbh->prepare( $sql );
			debugMsg("Executing value list: $sql\n");
			$sth->execute() or do {
	            debugMsg("Error executing: $sql\n");
	            $sql = undef;
			};
			if(defined($sql)) {
				my $id;
				my $name;
				$sth->bind_columns( undef, \$id,\$name);
				while( $sth->fetch() ) {
					my %listitem = (
						'id' => $id,
						'name' => Slim::Utils::Unicode::utf8decode($name,'utf8')
					);
				  	push @$listRef, \%listitem;
			  	}
			  	debugMsg("Added ".scalar(@$listRef)." items to value list\n");
			}
			$sth->finish();
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		}		
	}
}


sub handleWebNewPlaylistTypes {
	my ($client, $params) = @_;
        if ($::VERSION ge '6.5') {
                $params->{'pluginSQLPlayListSlimserver65'} = 1;
        }
	if(defined($params->{'redirect'})) {
		$params->{'pluginSQLPlayListRedirect'} = 1;
	}
	my $templatesHash = readTemplateConfiguration($client);
	my @templates = ();
	for my $key (keys %$templatesHash) {
		push @templates,$templatesHash->{$key};
	}
	@templates = sort { $a->{'name'} cmp $b->{'name'} } @templates;

	$params->{'pluginSQLPlayListTemplates'} = \@templates;
	
        return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_newplaylisttypes.html', $params);
}

sub handleWebNewPlaylistParameters {
	my ($client, $params) = @_;
        if ($::VERSION ge '6.5') {
                $params->{'pluginSQLPlayListSlimserver65'} = 1;
        }
	if(defined($params->{'redirect'})) {
		$params->{'pluginSQLPlayListRedirect'} = 1;
	}
	$params->{'pluginSQLPlayListNewPlayListTemplate'} = $params->{'playlisttemplate'};
	my $templates = readTemplateConfiguration($client);
	my $template = $templates->{$params->{'playlisttemplate'}};
	my @parametersToSelect = ();
	if(defined($template->{'parameter'})) {
		my $parameters = $template->{'parameter'};
		for my $p (@$parameters) {
			if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
				addValuesToTemplateParameter($p);
				push @parametersToSelect,$p;
			}
		}
	}
	$params->{'pluginSQLPlayListNewPlayListParameters'} = \@parametersToSelect;
        return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_newplaylistparameters.html', $params);
}

sub handleWebNewPlaylist {
	my ($client, $params) = @_;
        if ($::VERSION ge '6.5') {
                $params->{'pluginSQLPlayListSlimserver65'} = 1;
        }
	if(defined($params->{'redirect'})) {
		$params->{'pluginSQLPlayListRedirect'} = 1;
	}
	my $templateFile = $params->{'playlisttemplate'};
	my $playlistFile = $templateFile;
	$templateFile =~ s/\.sql\.xml$/.sql.template/;
	$playlistFile =~ s/\.sql\.xml$//;
	my $templates = readTemplateConfiguration($client);
	my $template = $templates->{$params->{'playlisttemplate'}};
	my $menytype = $params->{'playlisttype'};

	if($menytype eq 'advanced') {
		$playlistFile .= ".sql";
		my %templateParameters = ();
		if(defined($template->{'parameter'})) {
			my $parameters = $template->{'parameter'};
			my @parametersToSelect = ();
			for my $p (@$parameters) {
				if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
					addValuesToTemplateParameter($p);
					my $value = getValueOfTemplateParameter($params,$p);
					$templateParameters{$p->{'id'}} = $value;
				}
			}
		}
		my $playlistData = fillTemplate($templateFile,\%templateParameters);
		$playlistData = Slim::Utils::Unicode::utf8on($playlistData);
		$playlistData = Slim::Utils::Unicode::utf8encode_locale($playlistData);
		$playlistData = encode_entities($playlistData,"&<>\'\"");
		my %playlistHash = (
			'data' => $playlistData
		);
		my $playlist = parsePlaylist(\%playlistHash);
        	$params->{'pluginSQLPlayListEditPlayListText'} = Slim::Utils::Unicode::utf8decode($playlist->{'fulltext'},'utf8');
		$params->{'pluginSQLPlayListEditPlayListName'} = $playlist->{'name'};
		$params->{'pluginSQLPlayListEditPlayListFile'} = $playlistFile;
		$params->{'pluginSQLPlayListEditPlayListFileUnescaped'} = unescape($playlistFile);
	        return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_newplaylist.html', $params);
	}else {
		my $templateParameters = getParameterArray($params,"playlistparameter_");
		$playlistFile .= ".sql.values";
		$params->{'pluginSQLPlayListEditPlayListParameters'} = $templateParameters;
		$params->{'pluginSQLPlayListNewPlayListTemplate'} = $params->{'playlisttemplate'};
		$params->{'pluginSQLPlayListEditPlayListFile'} = $playlistFile;
		$params->{'pluginSQLPlayListEditPlayListFileUnescaped'} = unescape($playlistFile);
	        return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_newsimpleplaylist.html', $params);
	}
}

sub handleWebSaveNewSimplePlaylist {
	my ($client, $params) = @_;
	$params->{'pluginSQLPlayListError'} = undef;
	if(defined($params->{'redirect'})) {
		$params->{'pluginSQLPlayListRedirect'} = 1;
	}

	if (!$params->{'file'} && !$params->{'playlisttemplate'}) {
		$params->{'pluginSQLPlayListError'} = 'All fields are mandatory';
	}

	my $browseDir = Slim::Utils::Prefs::get("plugin_sqlplaylist_playlist_directory");
	
	if (!defined $browseDir || !-d $browseDir) {
		$params->{'pluginSQLPlayListError'} = 'No playlist directory configured';
	}
	my $file = unescape($params->{'file'});
	my $url = catfile($browseDir, $file);
	
	if(!defined($params->{'pluginSQLPlayListError'}) && -e $url) {
		$params->{'pluginSQLPlayListError'} = 'Invalid filename, file already exist';
	}

	if(!saveSimplePlaylist($client,$params,$url)) {
		my $templateParameters = getParameterArray($params,"playlistparameter_");
		$params->{'pluginSQLPlayListEditPlayListParameters'} = $templateParameters;
		$params->{'pluginSQLPlayListNewPlayListTemplate'}=$params->{'playlisttemplate'};
		return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_newsimpleplaylist.html', $params);
	}else {
		$params->{'donotrefresh'} = 1;
		initPlayLists($client);
		return handleWebList($client,$params)
	}
}

sub handleWebSaveSimplePlaylist {
	my ($client, $params) = @_;
        if ($::VERSION ge '6.5') {
                $params->{'pluginSQLPlayListSlimserver65'} = 1;
        }
	if(defined($params->{'redirect'})) {
		$params->{'pluginSQLPlayListRedirect'} = 1;
	}
	my $templateFile = $params->{'playlisttemplate'};
	$templateFile =~ s/\.sql\.xml$/.sql.template/;
	my $templates = readTemplateConfiguration($client);
	my $template = $templates->{$params->{'playlisttemplate'}};
	my $menytype = $params->{'playlisttype'};

	if($menytype eq 'advanced') {
		my %templateParameters = ();
		if(defined($template->{'parameter'})) {
			my $parameters = $template->{'parameter'};
			my @parametersToSelect = ();
			for my $p (@$parameters) {
				if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
					addValuesToTemplateParameter($p);
					my $value = getValueOfTemplateParameter($params,$p);
					$templateParameters{$p->{'id'}} = $value;
				}
			}
		}
		my $playlistData = fillTemplate($templateFile,\%templateParameters);
		$playlistData = Slim::Utils::Unicode::utf8on($playlistData);
		$playlistData = Slim::Utils::Unicode::utf8encode_locale($playlistData);
		$playlistData = encode_entities($playlistData,"&<>\'\"");
		my %playlistHash = (
			'data' => $playlistData
		);
		my $playlistFile = $params->{'file'};
		$playlistFile =~ s/\.values$//;
		my $playlist = parsePlaylist(\%playlistHash);
        	$params->{'pluginSQLPlayListEditPlayListText'} = Slim::Utils::Unicode::utf8decode($playlist->{'fulltext'},'utf8');
		$params->{'pluginSQLPlayListEditPlayListName'} = $playlist->{'name'};
		$params->{'pluginSQLPlayListEditPlayListGroups'} = getGroupString($playlist);
		$params->{'pluginSQLPlayListEditPlayListDeleteSimple'} = $params->{'file'};
		$params->{'pluginSQLPlayListEditPlayListFile'} = $playlistFile;
		$params->{'pluginSQLPlayListEditPlayListFileUnescaped'} = unescape($playlistFile);
	        return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_editplaylist.html', $params);
	}else {
		$params->{'pluginSQLPlayListError'} = undef;
	
		if (!$params->{'file'}) {
			$params->{'pluginSQLPlayListError'} = 'Filename is mandatory';
		}
	
		my $browseDir = Slim::Utils::Prefs::get("plugin_sqlplaylist_playlist_directory");
		
		if (!defined $browseDir || !-d $browseDir) {
			$params->{'pluginSQLPlayListError'} = 'No playlist directory configured';
		}
		my $file = unescape($params->{'file'});
		my $url = catfile($browseDir, $file);
		
		my %templateParameters = ();
		if(defined($template->{'parameter'})) {
			my $parameters = $template->{'parameter'};
			my @parametersToSelect = ();
			for my $p (@$parameters) {
				if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
					addValuesToTemplateParameter($p);
					my $value = getValueOfTemplateParameter($params,$p);
					$templateParameters{$p->{'id'}} = $value;
				}
			}
		}
		my $playlistData = fillTemplate($templateFile,\%templateParameters);
		$playlistData = Slim::Utils::Unicode::utf8on($playlistData);
		$playlistData = Slim::Utils::Unicode::utf8encode_locale($playlistData);
		$playlistData = encode_entities($playlistData,"&<>\'\"");
		my %playlistHash = (
			'data' => $playlistData
		);
		my $playlist = parsePlaylist(\%playlistHash);

		if(!saveSimplePlaylist($client,$params,$url)) {
			return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_editsimpleplaylist.html', $params);
		}else {
			$params->{'donotrefresh'} = 1;
			initPlayLists($client);
			if($params->{'play'}) {
				handlePlayOrAdd($client, $playlist->{'id'});
			}
			return handleWebList($client,$params)
		}
	}
}

sub getTemplate {
	if(!defined($template)) {
		my @pluginDirs = ();
		if ($::VERSION ge '6.5') {
			@pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
		}else {
			@pluginDirs = catdir($Bin, "Plugins");
		}
		my @include_path = ();
		my $templateDir = undef;
		for my $plugindir (@pluginDirs) {
			next unless -d catdir($plugindir,'SQLPlayList/Templates');
			$templateDir = catdir($plugindir,'SQLPlayList/Templates');
			push @include_path,$templateDir;
		}
	
	
		$template = Template->new({
	
	                INCLUDE_PATH => \@include_path,
	                COMPILE_DIR => catdir( Slim::Utils::Prefs::get('cachedir'), 'templates' ),
	                FILTERS => {
	                        'string'        => \&Slim::Utils::Strings::string,
	                        'getstring'     => \&Slim::Utils::Strings::getString,
	                        'resolvestring' => \&Slim::Utils::Strings::resolveString,
	                        'nbsp'          => \&nonBreaking,
	                        'uri'           => \&URI::Escape::uri_escape_utf8,
	                        'unuri'         => \&URI::Escape::uri_unescape,
	                        'utf8decode'    => \&Slim::Utils::Unicode::utf8decode,
	                        'utf8encode'    => \&Slim::Utils::Unicode::utf8encode,
	                        'utf8on'        => \&Slim::Utils::Unicode::utf8on,
	                        'utf8off'       => \&Slim::Utils::Unicode::utf8off,
	                },
	
	                EVAL_PERL => 1,
	        });
	}
	return $template;
}

sub fillTemplate {
	my $filename = shift;
	my $params = shift;

	
	my $output = '';
	$params->{'LOCALE'} = 'utf-8';
	my $template = getTemplate();
	if(!$template->process($filename,$params,\$output)) {
		msg("SQLPlayList: ERROR parsing template: ".$template->error()."\n");
	}
	return $output;
}

sub addValuesToTemplateParameter {
	my $p = shift;
	my $currentValues = shift;

	if($p->{'type'} =~ '^sql.*') {
		my $listValues = getSQLTemplateData($p->{'data'});
		if(defined($currentValues)) {
			for my $v (@$listValues) {
				if($currentValues->{$v->{'value'}}) {
					$v->{'selected'} = 1;
				}
			}
		}
		$p->{'values'} = $listValues;
	}elsif($p->{'type'} =~ '.*list$' || $p->{'type'} =~ '.*checkboxes$') {
		my @listValues = ();
		my @values = split(/,/,$p->{'data'});
		for my $value (@values){
			my @idName = split(/=/,$value);
			my %listValue = (
				'id' => @idName->[0],
				'name' => @idName->[1]
			);
			if(scalar(@idName)>2) {
				$listValue{'value'} = @idName->[2];
			}else {
				$listValue{'value'} = @idName->[0];
			}
			push @listValues, \%listValue;
		}
		if(defined($currentValues)) {
			for my $v (@listValues) {
				if($currentValues->{$v->{'value'}}) {
					$v->{'selected'} = 1;
				}
			}
		}
		$p->{'values'} = \@listValues;
	}elsif(defined($currentValues)) {
		for my $v (keys %$currentValues) {
			$p->{'value'} = $v;
		}
	}
}

sub getValueOfTemplateParameter {
	my $params = shift;
	my $parameter = shift;

	my $dbh = getCurrentDBH();
	my $result = undef;
	if($parameter->{'type'} =~ /.*multiplelist$/ || $parameter->{'type'} =~ /.*checkboxes$/) {
		my $selectedValues = undef;
		if($parameter->{'type'} =~ /.*multiplelist$/) {
			$selectedValues = getMultipleListQueryParameter($params,'playlistparameter_'.$parameter->{'id'});
		}else {
			$selectedValues = getCheckBoxesQueryParameter($params,'playlistparameter_'.$parameter->{'id'});
		}
		my $values = $parameter->{'values'};
		for my $item (@$values) {
			if(defined($selectedValues->{$item->{'id'}})) {
				if(defined($result)) {
					$result = $result.',';
				}
				if($parameter->{'quotevalue'}) {
					$result = $result.$dbh->quote(encode_entities($item->{'value'},"&<>\'\""));
				}else {
					$result = $result.encode_entities($item->{'value'},"&<>\'\"");
				}
			}
		}
		if(!defined($result)) {
			$result = '';
		}
	}elsif($parameter->{'type'} =~ /.*singlelist$/) {
		my $values = $parameter->{'values'};
		my $selectedValue = $params->{'playlistparameter_'.$parameter->{'id'}};
		for my $item (@$values) {
			if($selectedValue eq $item->{'id'}) {
				if($parameter->{'quotevalue'}) {
					$result = $dbh->quote(encode_entities($item->{'value'},"&<>\'\""));
				}else {
					$result = encode_entities($item->{'value'},"&<>\'\"");
				}
				last;
			}
		}
		if(!defined($result)) {
			$result = '';
		}
	}else{
		if($params->{'playlistparameter_'.$parameter->{'id'}}) {
			if($parameter->{'quotevalue'}) {
				$result = $dbh->quote(encode_entities($params->{'playlistparameter_'.$parameter->{'id'}},"&<>\'\""));
			}else {
				$result = encode_entities($params->{'playlistparameter_'.$parameter->{'id'}},"&<>\'\"");
			}
		}else {
			$result = '';
		}
	}
	if(defined($result)) {
		$result = Slim::Utils::Unicode::utf8on($result);
		$result = Slim::Utils::Unicode::utf8encode_locale($result);
	}
	return $result;
}

sub getXMLValueOfTemplateParameter {
	my $params = shift;
	my $parameter = shift;

	my $dbh = getCurrentDBH();
	my $result = undef;
	if($parameter->{'type'} =~ /.*multiplelist$/ || $parameter->{'type'} =~ /.*checkboxes$/) {
		my $selectedValues = undef;
		if($parameter->{'type'} =~ /.*multiplelist$/) {
			$selectedValues = getMultipleListQueryParameter($params,'playlistparameter_'.$parameter->{'id'});
		}else {
			$selectedValues = getCheckBoxesQueryParameter($params,'playlistparameter_'.$parameter->{'id'});
		}
		my $values = $parameter->{'values'};
		for my $item (@$values) {
			if(defined($selectedValues->{$item->{'id'}})) {
				$result = $result.'<value>';
				if($parameter->{'quotevalue'}) {
					$result = $result.encode_entities($item->{'value'},"&<>\'\"");
				}else {
					$result = $result.encode_entities($item->{'value'},"&<>\'\"");
				}
				$result = $result.'</value>';
			}
		}
		if(!defined($result)) {
			$result = '';
		}
	}elsif($parameter->{'type'} =~ /.*singlelist$/) {
		my $values = $parameter->{'values'};
		my $selectedValue = $params->{'playlistparameter_'.$parameter->{'id'}};
		for my $item (@$values) {
			if($selectedValue eq $item->{'id'}) {
				$result = '<value>';
				if($parameter->{'quotevalue'}) {
					$result .= encode_entities($item->{'value'},"&<>\'\"");
				}else {
					$result .= encode_entities($item->{'value'},"&<>\'\"");
				}
				$result .= '</value>';
				last;
			}
		}
		if(!defined($result)) {
			$result = '';
		}
	}else{
		if(defined($params->{'playlistparameter_'.$parameter->{'id'}}) && $params->{'playlistparameter_'.$parameter->{'id'}} ne '') {
			if($parameter->{'quotevalue'}) {
				$result = '<value>'.encode_entities($params->{'playlistparameter_'.$parameter->{'id'}},"&<>\'\"").'</value>';
			}else {
				$result = '<value>'.encode_entities($params->{'playlistparameter_'.$parameter->{'id'}},"&<>\'\"").'</value>';
			}
		}else {
			$result = '';
		}
	}
	if(defined($result)) {
		$result = Slim::Utils::Unicode::utf8on($result);
		$result = Slim::Utils::Unicode::utf8encode_locale($result);
	}
	return $result;
}


sub getMultipleListQueryParameter {
	my $params = shift;
	my $parameter = shift;

	my $query = $params->{url_query};
	my %result = ();
	if($query) {
		foreach my $param (split /\&/, $query) {
			if ($param =~ /([^=]+)=(.*)/) {
				my $name  = unescape($1,1);
				my $value = unescape($2,1);
				if($name eq $parameter) {
					# We need to turn perl's internal
					# representation of the unescaped
					# UTF-8 string into a "real" UTF-8
					# string with the appropriate magic set.
					if ($value ne '*' && $value ne '') {
						$value = Slim::Utils::Unicode::utf8on($value);
						$value = Slim::Utils::Unicode::utf8encode_locale($value);
					}
					$result{$value} = 1;
				}
			}
		}
	}
	return \%result;
}

sub getParameterArray {
	my $params = shift;
	my $prefix = shift;

	my $query = $params->{url_query};
	my @result = ();
	if($query) {
		foreach my $param (split /\&/, $query) {
			if ($param =~ /([^=]+)=(.*)/) {
				my $name  = unescape($1,1);
				my $value = unescape($2,1);
				if($name =~ /^$prefix/) {
					# We need to turn perl's internal
					# representation of the unescaped
					# UTF-8 string into a "real" UTF-8
					# string with the appropriate magic set.
					if ($value ne '*' && $value ne '') {
						$value = Slim::Utils::Unicode::utf8on($value);
						$value = Slim::Utils::Unicode::utf8encode_locale($value);
					}
					my %parameter = (
						'id' => $name,
						'value' => $value
					);
					push @result,\%parameter;
				}
			}
		}
	}
	return \@result;
}

sub getCheckBoxesQueryParameter {
	my $params = shift;
	my $parameter = shift;

	my %result = ();
	foreach my $key (keys %$params) {
		my $pattern = '^'.$parameter.'_(.*)';
		if ($key =~ /$pattern/) {
			my $id  = unescape($1);
			$result{$id} = 1;
		}
	}
	return \%result;
}

sub getSQLTemplateData {
	my $sqlstatements = shift;
	my @result =();
	my $ds = getCurrentDS();
	my $dbh = getCurrentDBH();
	my $trackno = 0;
	my $sqlerrors = "";
    	for my $sql (split(/[;]/,$sqlstatements)) {
    	eval {
			$sql =~ s/^\s+//g;
			$sql =~ s/\s+$//g;
			my $sth = $dbh->prepare( $sql );
			debugMsg("Executing: $sql\n");
			$sth->execute() or do {
	            debugMsg("Error executing: $sql\n");
	            $sql = undef;
			};

	        if ($sql =~ /^SELECT+/oi) {
				debugMsg("Executing and collecting: $sql\n");
				my $id;
                                my $name;
                                my $value;
				$sth->bind_col( 1, \$id);
                                $sth->bind_col( 2, \$name);
                                $sth->bind_col( 3, \$value);
				while( $sth->fetch() ) {
                                    my %item = (
                                        'id' => $id,
                                        'name' => Slim::Utils::Unicode::utf8decode($name,'utf8'),
					'value' => Slim::Utils::Unicode::utf8decode($value,'utf8')
                                    );
                                    push @result, \%item;
				}
			}
			$sth->finish();
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n";
		}		
	}
	return \@result;
}

sub readPlaylistsFromDir {
	my $client = shift;
	my $defaultPlaylist = shift;
	my $playlistDir = shift;
	my $playlists = shift;

	debugMsg("Loading playlists from: $playlistDir\n");
	my @dircontents = Slim::Utils::Misc::readDirectory($playlistDir,"sql");

	for my $item (@dircontents) {
		next if !($item =~ /\.sql$/);
		my $path = catfile($playlistDir, $item);
		
		if ( -d $path) {
			readPlaylistsFromDir($client,$defaultPlaylist,$path,$playlists);
		}else {
			# read_file from File::Slurp
			debugMsg("Loading playlist $path\n");
			my $content = eval { read_file($path) };
			if ( $content ) {
				my $playlistId = $item;
				$playlistId =~ s/\.sql$//;
				my %playlist =  ();
				$playlist{'data'} = $content;
				$playlist{'file'} = $item;
				if($defaultPlaylist) {
					$playlist{'defaultplaylist'} = 1;
				}
		                $playlists->{$playlistId} = \%playlist;
			}else {
				if ($@) {
					errorMsg("SQLPlayList: Unable to open playlist: $path\nBecause of:\n$@\n");
				}else {
					errorMsg("SQLPlayList: Unable to open playlist: $path\n");
				}
			}
		}
	}
}

sub readTemplatePlaylistsFromDir {
    my $client = shift;
    my $defaultPlaylist = shift;
    my $playlistDir = shift;
    my $localPlaylists = shift;
    my $templates = shift;
    debugMsg("Loading template playlists from: $playlistDir\n");

    my @dircontents = Slim::Utils::Misc::readDirectory($playlistDir,"sql.values");
    for my $item (@dircontents) {

	next if -d catdir($playlistDir, $item);

        my $path = catfile($playlistDir, $item);

        # read_file from File::Slurp
        my $content = eval { read_file($path) };
        if ( $content ) {
		my $errorMsg = parseTemplatePlaylistContent($client,$item,$content,$localPlaylists,$defaultPlaylist, $templates);
		if($errorMsg) {
	                errorMsg("SQLPlayList: Unable to open template playlist: $path\n$errorMsg\n");
		}
        }else {
            if ($@) {
                    errorMsg("SQLPlayList: Unable to open template playlist: $path\nBecause of:\n$@\n");
            }else {
                errorMsg("SQLPlayList: Unable to open template playlist: $path\n");
            }
        }
    }
}

sub readTemplateConfiguration {
    my $client = shift;
    my @pluginDirs = ();
    if ($::VERSION ge '6.5') {
        @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
    }else {
        @pluginDirs = catdir($Bin, "Plugins");
    }
    my %templates = ();
    for my $plugindir (@pluginDirs) {
	next unless -d catdir($plugindir,"SQLPlayList","Templates");
	readTemplateConfigurationFromDir($client,catdir($plugindir,"SQLPlayList","Templates"),\%templates);
    }
    return \%templates;
}

sub readTemplateConfigurationFromDir {
    my $client = shift;
    my $templateDir = shift;
    my $templates = shift;
    debugMsg("Loading template configuration from: $templateDir\n");

    my @dircontents = Slim::Utils::Misc::readDirectory($templateDir,"sql.xml");
    for my $item (@dircontents) {

	next if -d catdir($templateDir, $item);

        my $path = catfile($templateDir, $item);

        # read_file from File::Slurp
        my $content = eval { read_file($path) };
	my $error = parseTemplateContent($client,$item,$content,$templates);
	if($error) {
		errorMsg("Unable to read: $path\n");
	}
    }
}

sub parseTemplateContent {
	my $client = shift;
	my $key = shift;
	my $content = shift;
	my $templates = shift;

	my $errorMsg = undef;
        if ( $content ) {
	    $content = Slim::Utils::Unicode::utf8decode($content,'utf8');
            my $xml = eval { 	XMLin($content, forcearray => ["parameter"], keyattr => []) };
            #debugMsg(Dumper($xml));
            if ($@) {
		    $errorMsg = "$@";
                    errorMsg("SQLPlayList: Failed to parse playlist template configuration because:\n$@\n");
            }else {
		my $include = isTemplateEnabled($client,$xml);
		if(defined($xml->{'template'})) {
			$xml->{'template'}->{'id'} = $key;
		}
		if($include && defined($xml->{'template'})) {
	                $templates->{$key} = $xml->{'template'};
		}
            }
    
            # Release content
            undef $content;
        }else {
            if ($@) {
                    $errorMsg = "Incorrect information in template data: $@";
                    errorMsg("SQLPlayList: Unable to read template configuration:\n$@\n");
            }else {
		$errorMsg = "Incorrect information in template data";
                errorMsg("SQLPlayList: Unable to to read template configuration\n");
            }
        }
	return $errorMsg;
}

sub parseTemplatePlaylistContent {
	my $client = shift;
	my $item = shift;
	my $content = shift;
	my $playlists = shift;
	my $defaultPlaylist = shift;
	my $templates = shift;
	my $dbh = getCurrentDBH();

	my $playlistId = $item;
	$playlistId =~ s/\.sql\.values$//;
	my $errorMsg = undef;
        if ( $content ) {
		$content = Slim::Utils::Unicode::utf8decode($content,'utf8');
		my $valuesXml = eval { XMLin($content, forcearray => ["parameter","value"], keyattr => []) };
		#debugMsg(Dumper($valuesXml));
		if ($@) {
			$errorMsg = "$@";
			errorMsg("SQLPlayList: Failed to parse playlist template because:\n$@\n");
		}else {
			my $templateId = $valuesXml->{'template'}->{'id'};
			my $template = $templates->{$templateId};
			$templateId =~s/\.sql\.xml$//;
			my $include = undef;
			if($template) {
				my $templateFile = $templateId.".sql.template";
				my %templateParameters = ();
				my $parameters = $valuesXml->{'template'}->{'parameter'};
				for my $p (@$parameters) {
					my $values = $p->{'value'};
					my $value = '';
					for my $v (@$values) {
						if($value ne '') {
							$value .= ',';
						}
						if($p->{'quotevalue'}) {
							$value .= $dbh->quote(encode_entities($v,"&<>\'\""));
						}else {
							$value .= encode_entities($v,"&<>\'\"");
						}
					}
					$templateParameters{$p->{'id'}}=$value;
				}
				my $playlistData = fillTemplate($templateFile,\%templateParameters);
				$playlistData = Slim::Utils::Unicode::utf8on($playlistData);
				$playlistData = Slim::Utils::Unicode::utf8encode_locale($playlistData);
			
				my %playlist =  ();
	
				$playlist{'simple'} = 1;
				if($defaultPlaylist) {
					$playlist{'defaultplaylist'} = 1;
				}
				$playlist{'file'} = $item;
				$playlist{'data'} = $playlistData;
		                $playlists->{$playlistId} = \%playlist;
			}
		}
		    
		# Release content
		undef $content;
	}else {
		$errorMsg = "Incorrect information in playlist data";
		errorMsg("SQLPlayList: Unable to to read playlist data\n");
	}
	return $errorMsg;
}

sub loadTemplateData {
	my $browseDir = shift;
	my $file = shift;
	
	my $path = catfile($browseDir, $file);
	if( -f $path ) {
		my $content = eval { read_file($path) };
	        if ( $content ) {
			$content = Slim::Utils::Unicode::utf8decode($content,'utf8');
			my $xml = eval { XMLin($content, forcearray => ["parameter","value"], keyattr => []) };
			#debugMsg(Dumper($valuesXml));
			if ($@) {
				errorMsg("SQLPlayList: Failed to parse template data because:\n$@\n");
			}else {
				return $xml->{'template'}
			}
		}else {
			debugMsg("Failed to load template data because:\n$@\n");
		}
		if ($@) {
			debugMsg("Failed to load template data because:\n$@\n");
		}
	}
	return undef;
}


sub isTemplateEnabled {
	my $client = shift;
	my $xml = shift;

	my $include = 1;
	if(defined($xml->{'minslimserverversion'})) {
		if($::VERSION lt $xml->{'minslimserverversion'}) {
			$include = 0;
		}
	}
	if(defined($xml->{'maxslimserverversion'})) {
		if($::VERSION gt $xml->{'maxslimserverversion'}) {
			$include = 0;
		}
	}
	if(defined($xml->{'requireplugins'}) && $include) {
		$include = 0;
		my $requiredPlugins = $xml->{'requireplugins'};
		my $enabledPlugin = 1;
		foreach my $plugin (split /,/, $requiredPlugins) {
			if($enabledPlugin) {
				if ($::VERSION ge '6.5') {
					$enabledPlugin = Slim::Utils::PluginManager::enabledPlugin($plugin,$client);
				}else {
					$enabledPlugin = grep(/$plugin/,Slim::Buttons::Plugins::enabledPlugins($client));
				}
			}
		}
		if($enabledPlugin) {
			$include = 1;
		}
	}
	if(defined($xml->{'database'}) && $include) {
		$include = 0;
		my $driver = Slim::Utils::Prefs::get('dbsource');
		$driver =~ s/dbi:(.*?):(.*)$/$1/;
		if($driver eq $xml->{'database'}) {
			$include = 1;
		}
	}
	return $include;
}


# Draws the plugin's edit playlist web page
sub handleWebSavePlaylist {
	my ($client, $params) = @_;

	$params->{'pluginSQLPlayListError'} = undef;
	if(defined($params->{'redirect'})) {
		$params->{'pluginSQLPlayListRedirect'} = 1;
	}

	if($params->{'testonly'} eq "1") {
		return handleWebTestEditPlaylist($client,$params);
	}

	handleWebTestPlaylist($client,$params);
	
	if (!$params->{'text'} || !$params->{'file'} || !$params->{'name'}) {
		$params->{'pluginSQLPlayListError'} = 'All fields besides groups are mandatory';
	}

	my $playlistDir = Slim::Utils::Prefs::get("plugin_sqlplaylist_playlist_directory");
	
	if (!defined $playlistDir || !-d $playlistDir) {
		$params->{'pluginSQLPlayListError'} = 'No playlist dir defined';
	}
	my $url = catfile($playlistDir, unescape($params->{'file'}));
	if (!-e $url && !defined($params->{'deletesimple'})) {
		$params->{'pluginSQLPlayListError'} = 'File doesnt exist';
	}
	
	my $playlist = getPlayList($client,escape($params->{'name'},"^A-Za-z0-9\-_"));
	if($playlist && $playlist->{'file'} ne unescape($params->{'file'}) && !defined($playlist->{'defaultplaylist'}) && !defined($playlist->{'simple'})) {
		$params->{'pluginSQLPlayListError'} = 'Playlist with that name already exists';
	}
	if(!savePlaylist($client,$params,$url)) {
		if(defined($params->{'deletesimple'})) {
			$params->{'pluginSQLPlayListEditPlayListDeleteSimple'} = $params->{'deletesimple'};
		}
		return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_editplaylist.html', $params);
	}else {
		if(defined($params->{'deletesimple'})) {
			my $file = unescape($params->{'deletesimple'});
			my $url = catfile($playlistDir, $file);
			if(-e $url) {
				unlink($url) or do {
					warn "Unable to delete file: ".$url.": $! \n";
				}
			}
		}
		$params->{'donotrefresh'} = 1;
		initPlayLists($client);
		if($params->{'play'}) {
			handlePlayOrAdd($client, $playlist->{'id'});
		}
		return handleWebList($client,$params)
	}

}

# Draws the plugin's edit playlist web page
sub handleWebSaveNewPlaylist {
	my ($client, $params) = @_;

	if(defined($params->{'redirect'})) {
		$params->{'pluginSQLPlayListRedirect'} = 1;
	}

	$params->{'pluginSQLPlayListError'} = undef;
	
	if($params->{'testonly'} eq "1") {
		return handleWebTestNewPlaylist($client,$params);
	}

	handleWebTestPlaylist($client,$params);
	
	if (!$params->{'text'} || !$params->{'file'} || !$params->{'name'}) {
		$params->{'pluginSQLPlayListError'} = 'All fields besides groups are mandatory';
	}

	my $playlistDir = Slim::Utils::Prefs::get("plugin_sqlplaylist_playlist_directory");
	
	if (!defined $playlistDir || !-d $playlistDir) {
		$params->{'pluginSQLPlayListError'} = 'No playlist dir defined';
	}
	debugMsg("Got file: ".$params->{'file'}."\n");
	if($params->{'file'} !~ /.*\.sql$/) {
		$params->{'pluginSQLPlayListError'} = 'File name must end with .sql';
	}
	
	if($params->{'file'} !~ /^[0-9A-Za-z\._\- ]*$/) {
		$params->{'pluginSQLPlayListError'} = 'File name is only allowed to contain characters a-z , A-Z , 0-9 , - , _ , . , and space';
	}

	my $url = catfile($playlistDir, unescape($params->{'file'}));
	if (-e $url) {
		$params->{'pluginSQLPlayListError'} = 'File already exist';
	}
	my $playlist = getPlayList($client,escape($params->{'name'},"^A-Za-z0-9\-_"));
	if($playlist) {
		$params->{'pluginSQLPlayListError'} = 'Playlist with that name already exists';
	}

	if(!savePlaylist($client,$params,$url)) {
		return Slim::Web::HTTP::filltemplatefile('plugins/SQLPlayList/sqlplaylist_newplaylist.html', $params);
	}else {
		$params->{'donotrefresh'} = 1;
		initPlayLists($client);
		return handleWebList($client,$params)
	}

}

sub handleWebRemovePlaylist {
	my ($client, $params) = @_;

	if(defined($params->{'redirect'})) {
		$params->{'pluginSQLPlayListRedirect'} = 1;
	}

	if ($params->{'type'}) {
		my $playlist = getPlayList($client,$params->{'type'});
		if($playlist) {
			my $playlistDir = Slim::Utils::Prefs::get("plugin_sqlplaylist_playlist_directory");
			
			if (!defined $playlistDir || !-d $playlistDir) {
				warn "No playlist dir defined\n"
			}else {
				debugMsg("Deleteing playlist: ".$playlist->{'file'}."\n");
				my $url = catfile($playlistDir, unescape($playlist->{'file'}));
				unlink($url) or do {
					warn "Unable to delete file: ".$url.": $! \n";
				}
			}
		}else {
			warn "Cannot find: ".$params->{'type'}."\n";
		}
	}

	return handleWebList($client,$params)
}

sub saveSimplePlaylist {
	my ($client, $params, $url) = @_;
	my $fh;

	if(!($url =~ /.*\.sql\.values$/)) {
		$params->{'pluginSQLPlayListError'} = 'Filename must end with .sql.values';
	}

	if(!($params->{'pluginSQLPlayListError'})) {
		debugMsg("Opening playlist file: $url\n");
		open($fh,"> $url") or do {
	            $params->{'pluginSQLPlayListError'} = 'Error saving playlist';
		};
	}
	if(!($params->{'pluginSQLPlayListError'})) {
		my $templates = readTemplateConfiguration($client);
		my $template = $templates->{$params->{'playlisttemplate'}};
		my %templateParameters = ();
		my $data = "";
		$data .= "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<sqlplaylist>\n\t<template>\n\t\t<id>".$params->{'playlisttemplate'}."</id>";
		if(defined($template->{'parameter'})) {
			my $parameters = $template->{'parameter'};
			my @parametersToSelect = ();
			for my $p (@$parameters) {
				if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
					addValuesToTemplateParameter($p);
					my $value = getXMLValueOfTemplateParameter($params,$p);
					if($p->{'quotevalue'}) {
						$data .= "\n\t\t<parameter type=\"text\" id=\"".$p->{'id'}."\" quotevalue=\"1\">";
					}else {
						$data .= "\n\t\t<parameter type=\"text\" id=\"".$p->{'id'}."\">";
					}
					$data .= $value.'</parameter>';
				}
			}
		}
		$data .= "\n\t</template>\n</sqlplaylist>\n";
		debugMsg("Writing to file: $url\n");
		print $fh $data;
		debugMsg("Writing to file succeeded\n");
		close $fh;
	}
	
	if($params->{'pluginSQLPlayListError'}) {
		my %parameters;
		for my $p (keys %$params) {
			if($p =~ /^playlistparameter_/) {
				$parameters{$p}=$params->{$p};
			}
		}		
		$params->{'pluginSQLPlayListEditPlayListParameters'} = \%parameters;
		$params->{'pluginSQLPlayListEditPlayListFile'} = $params->{'file'};
		$params->{'pluginSQLPlayListEditPlayListFileUnescaped'} = unescape($params->{'pluginSQLPlayListEditPlayListFile'});
		if ($::VERSION ge '6.5') {
			$params->{'pluginSQLPlayListSlimserver65'} = 1;
		}
		return undef;
	}else {
		return 1;
	}
}

sub savePlaylist 
{
	my ($client, $params, $url) = @_;
	my $fh;
	if(!($params->{'pluginSQLPlayListError'})) {
		debugMsg("Opening playlist file: $url\n");
	    open($fh,"> $url") or do {
	            $params->{'pluginSQLPlayListError'} = 'Error saving playlist';
	    };
	}
	if(!($params->{'pluginSQLPlayListError'})) {

		debugMsg("Writing to file: $url\n");
		print $fh "-- PlaylistName: ".$params->{'name'}."\n";
		if($params->{'groups'}) {
			print $fh "-- PlaylistGroups: ".$params->{'groups'}."\n";
		}
		print $fh $params->{'text'};
		debugMsg("Writing to file succeeded\n");
		close $fh;
	}
	
	if($params->{'pluginSQLPlayListError'}) {
		$params->{'pluginSQLPlayListEditPlayListFile'} = $params->{'file'};
		$params->{'pluginSQLPlayListEditPlayListText'} = $params->{'text'};
		$params->{'pluginSQLPlayListEditPlayListName'} = $params->{'name'};
		$params->{'pluginSQLPlayListEditPlayListGroups'} = $params->{'groups'};
		$params->{'pluginSQLPlayListEditPlayListFileUnescaped'} = unescape($params->{'pluginSQLPlayListEditPlayListFile'});
		return undef;
	}else {
		return 1;
	}
}


sub getFunctions {
	# Functions to allow mapping of mixes to keypresses
	return {
		'up' => sub  {
			my $client = shift;
			$client->bumpUp();
		},
		'down' => sub  {
			my $client = shift;
			$client->bumpDown();
		},
		'left' => sub  {
			my $client = shift;
			Slim::Buttons::Common::popModeRight($client);
		},
		'right' => sub  {
			my $client = shift;
			$client->bumpRight();
		}
	}
}

sub checkDefaults {
	my $prefVal = Slim::Utils::Prefs::get('plugin_sqlplaylist_playlist_directory');
	if (! defined $prefVal) {
		# Default to standard playlist directory
		my $dir=Slim::Utils::Prefs::get('playlistdir');
		debugMsg("Defaulting plugin_sqlplaylist_playlist_directory to:$dir\n");
		Slim::Utils::Prefs::set('plugin_sqlplaylist_playlist_directory', $dir);
	}

	$prefVal = Slim::Utils::Prefs::get('plugin_sqlplaylist_showmessages');
	if (! defined $prefVal) {
		# Default to not show debug messages
		debugMsg("Defaulting plugin_sqlplaylist_showmessages to 0\n");
		Slim::Utils::Prefs::set('plugin_sqlplaylist_showmessages', 0);
	}
}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_sqlplaylist_playlist_directory','plugin_sqlplaylist_showmessages'],
	 GroupHead => string('PLUGIN_SQLPLAYLIST_SETUP_GROUP'),
	 GroupDesc => string('PLUGIN_SQLPLAYLIST_SETUP_GROUP_DESC'),
	 GroupLine => 1,
	 GroupSub  => 1,
	 Suppress_PrefSub  => 1,
	 Suppress_PrefLine => 1
	);
	my %setupPrefs =
	(
	plugin_sqlplaylist_showmessages => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_SQLPLAYLIST_SHOW_MESSAGES')
			,'changeIntro' => string('PLUGIN_SQLPLAYLIST_SHOW_MESSAGES')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_sqlplaylist_showmessages"); }
		},		
	plugin_sqlplaylist_playlist_directory => {
			'validate' => \&validateIsDirWrapper
			,'PrefChoose' => string('PLUGIN_SQLPLAYLIST_PLAYLIST_DIRECTORY')
			,'changeIntro' => string('PLUGIN_SQLPLAYLIST_PLAYLIST_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_sqlplaylist_playlist_directory"); }
		},
	);
	return (\%setupGroup,\%setupPrefs);
}
sub replaceParametersInSQL {
	my $sql = shift;
	my $parameters = shift;
	my $parameterType = shift;
	if(!defined($parameterType)) {
		$parameterType='PlaylistParameter';
	}
	
	if(defined($parameters)) {
		foreach my $key (keys %$parameters) {
			my $parameter = $parameters->{$key};
			my $value = $parameter->{'value'};
			if(!defined($value)) {
				$value='';
			}
			my $parameterid = "\'$parameterType".$parameter->{'id'}."\'";
			debugMsg("Replacing ".$parameterid." with ".$value."\n");
			$sql =~ s/$parameterid/$value/g;
		}
	}
	return $sql;
}
sub getTracksForPlaylist {
	my $client = shift;
	my $playlist = shift;
	my $limit = shift;
	my $offset = shift;
	my $parameters = shift;

	my $sqlstatements = $playlist->{'sql'};
	my $dbh = getCurrentDBH();
	$sqlstatements = replaceParametersInSQL($sqlstatements,$parameters);
	my $offsetLimitParameters = getOffsetLimitParameters($limit,$offset);
	$sqlstatements = replaceParametersInSQL($sqlstatements,$offsetLimitParameters,'Playlist');
	my $unlimitedOption = getPlaylistOption($playlist,'Unlimited');
	if($unlimitedOption) {
		$limit = undef;
	}
	my $result= executeSQLForPlaylist($sqlstatements,$limit);
	
	return $result;
}

sub getPlaylistOption {
	my $playlist = shift;
	my $option = shift;

	if(defined($playlist->{'options'})){
		if(defined($playlist->{'options'}->{$option})) {
			return $playlist->{'options'}->{$option};
		}
	}
	return undef;
}
sub getOffsetLimitParameters {
	my $limit = shift;
	my $offset = shift;

	my %offsetLimitParameters = ();
	my %offsetParameter = (
		'id' => 'Offset',
		'value' => $offset
	);
	my %limitParameter = (
		'id' => 'Limit',
		'value' => $limit
	);
	$offsetLimitParameters{'PlaylistOffset'} = \%offsetParameter;
	$offsetLimitParameters{'PlaylistLimit'} = \%limitParameter;
	return \%offsetLimitParameters;
}
sub parseParameter {
	my $line = shift;
	
	if($line =~ /^\s*--\s*PlaylistParameter\s*\d\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*PlaylistParameter\s*(\d)\s*[:=]\s*([^:]+):\s*([^:]*):\s*(.*)$/;
		my $parameterId = $1;
		my $parameterType = $2;
		my $parameterName = $3;
		my $parameterDefinition = $4;

		$parameterType =~ s/^\s+//;
		$parameterType =~ s/\s+$//;

		$parameterName =~ s/^\s+//;
		$parameterName =~ s/\s+$//;

		$parameterDefinition =~ s/^\s+//;
		$parameterDefinition =~ s/\s+$//;

		if($parameterId && $parameterName && $parameterType) {
			my %parameter = (
				'id' => $parameterId,
				'type' => $parameterType,
				'name' => $parameterName,
				'definition' => $parameterDefinition
			);
			return \%parameter;
		}else {
			debugMsg("Error in parameter: $line\n");
			debugMsg("Parameter values: Id=$parameterId, Type=$parameterType, Name=$parameterName, Definition=$parameterDefinition\n");
			return undef;
		}
	}
	return undef;
}	

sub parseOption {
	my $line = shift;
	if($line =~ /^\s*--\s*PlaylistOption\s*[^:=]+\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*PlaylistOption\s*([^:=]+)\s*[:=]\s*(.+)\s*$/;
		my $optionId = $1;
		my $optionValue = $2;

		$optionId =~ s/\s+$//;

		$optionValue =~ s/^\s+//;
		$optionValue =~ s/\s+$//;

		if($optionId && $optionValue) {
			my %option = (
				'id' => $optionId,
				'value' => $optionValue
			);
			return \%option;
		}else {
			debugMsg("Error in option: $line\n");
			debugMsg("Option values: Id=$optionId, Value=$optionValue\n");
			return undef;
		}
	}
	return undef;
}	

sub createSQLPlayList {
	my $sqlstatements = shift;
	my $sql = '';
	my %parameters = ();
	my %options = ();
	for my $line (split(/[\n\r]/,$sqlstatements)) {
		chomp $line;

		my $parameter = parseParameter($line);
		if(defined($parameter)) {
			$parameters{$parameter->{'id'}} = $parameter;
		}
		my $option = parseOption($line);
		if(defined($option)) {
			$options{$option->{'id'}} = $option;
		}
		
		# skip and strip comments & empty lines
		$line =~ s/\s*--.*?$//o;
		$line =~ s/^\s*//o;

		next if $line =~ /^--/;
		next if $line =~ /^\s*$/;

		$line =~ s/\s+$//;
		if($sql) {
			if( $sql =~ /;$/ ) {
				$sql .= "\n";
			}else {
				$sql .= " ";
			}
		}
		$sql .= $line;
	}
	if($sql) {
		my %playlist = (
			'sql' => $sql
		);
		if(defined(%parameters)) {
			$playlist{'parameters'} = \%parameters;
		}
		if(defined(%options)) {
			$playlist{'options'} = \%options;
		}
	    	
		return \%playlist;
	}else {
		return undef;
	}
}
sub executeSQLForPlaylist {
	my $sqlstatements = shift;
	my $limit = shift;
	my @result;
	my $ds = getCurrentDS();
	my $dbh = getCurrentDBH();
	my $trackno = 0;
	$sqlerrors = "";
    for my $sql (split(/[\n\r]/,$sqlstatements)) {
    	eval {
			my $sth = $dbh->prepare( $sql );
			debugMsg("Executing: $sql\n");
			$sth->execute() or do {
	            debugMsg("Error executing: $sql\n");
	            $sql = undef;
			};

	        if ($sql =~ /^SELECT+/oi) {
				debugMsg("Executing and collecting: $sql\n");
				my $url;
				$sth->bind_columns( undef, \$url);
				while( $sth->fetch() ) {
				  my $track = objectForUrl($url);
				  $trackno++;
				  if(!$limit || $trackno<=$limit) {
					debugMsg("Adding: ".($track->url)."\n");
				  	push @result, $track;
				  }
				}
			}
			$sth->finish();
		};
		if( $@ ) {
			$sqlerrors .= $DBI::errstr."<br>$@<br>";
		    warn "Database error: $DBI::errstr\n$@\n";
		}		
	}
	return \@result;
}
sub getDynamicPlayLists {
	my ($client) = @_;

	if(!$playLists) {
		initPlayLists($client);
	}
	
	my %result = ();
	
	foreach my $playlist (sort keys %$playLists) {
		my $playlistid = "sqlplaylist_".$playlist;
		my $current = $playLists->{$playlist};
		my %currentResult = (
			'id' => $playlist,
			'name' => $current->{'name'},
			'url' => "plugins/SQLPlayList/sqlplaylist_editplaylist.html?type=".escape($playlist)."&redirect=1"
		);
		if(defined($current->{'parameters'})) {
			my $parameters = $current->{'parameters'};
			foreach my $pk (%$parameters) {
				my %parameter = (
					'id' => $pk,
					'type' => $parameters->{$pk}->{'type'},
					'name' => $parameters->{$pk}->{'name'},
					'definition' => $parameters->{$pk}->{'definition'}
				);
				$currentResult{'parameters'}->{$pk} = \%parameter;
			}
		}
		if($current->{'groups'} && scalar($current->{'groups'})>0) {
			$currentResult{'groups'} = $current->{'groups'};
		}
		$result{$playlistid} = \%currentResult;
	}
	
	return \%result;
}

sub getNextDynamicPlayListTracks {
	my ($client,$dynamicplaylist,$limit,$offset,$parameters) = @_;
	
	debugMsg("Getting tracks for: ".$dynamicplaylist->{'id'}."\n");
	my $playlist = getPlayList($client,$dynamicplaylist->{'id'});
	my $result = getTracksForPlaylist($client,$playlist,$limit,$offset,$parameters);
	
	return \@{$result};
}

sub validateIsDirWrapper {
	my $arg = shift;
	if ($::VERSION ge '6.5') {
		return Slim::Utils::Validate::isDir($arg);
	}else {
		return Slim::Web::Setup::validateIsDir($arg);
	}
}

sub validateTrueFalseWrapper {
	my $arg = shift;
	if ($::VERSION ge '6.5') {
		return Slim::Utils::Validate::trueFalse($arg);
	}else {
		return Slim::Web::Setup::validateTrueFalse($arg);
	}
}

sub objectForUrl {
	my $url = shift;
	if ($::VERSION ge '6.5') {
		return Slim::Schema->objectForUrl({
			'url' => $url
		});
	}else {
		return getCurrentDS()->objectForUrl($url,undef,undef,1);
	}
}

sub getCurrentDBH {
	if ($::VERSION ge '6.5') {
		return Slim::Schema->storage->dbh();
	}else {
		return Slim::Music::Info::getCurrentDataStore()->dbh();
	}
}

sub getCurrentDS {
	if ($::VERSION ge '6.5') {
		return 'Slim::Schema';
	}else {
		return Slim::Music::Info::getCurrentDataStore();
	}
}

sub commit {
	my $dbh = shift;
	if (!$dbh->{'AutoCommit'}) {
		$dbh->commit();
	}
}

sub rollback {
	my $dbh = shift;
	if (!$dbh->{'AutoCommit'}) {
		$dbh->rollback();
	}
}

sub displayAsHTML {
	my $type = shift;
	my $form = shift;
	my $item = shift;
	
	if ($::VERSION ge '6.5') {
		$item->displayAsHTML($form);
	}else {
		my $ds = getCurrentDS();
		my $fieldInfo = Slim::DataStores::Base->fieldInfo;
        my $levelInfo = $fieldInfo->{$type};
        &{$levelInfo->{'listItem'}}($ds, $form, $item);
	}
}

sub getLinkAttribute {
	my $attr = shift;
	if ($::VERSION ge '6.5') {
		if($attr eq 'artist') {
			$attr = 'contributor';
		}
		return $attr.'.id';
	}
	return $attr;
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

# A wrapper to allow us to uniformly turn on & off debug messages
sub debugMsg
{
	my $message = join '','SQLPlayList: ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_sqlplaylist_showmessages"));
}

sub strings {
	return <<EOF;
PLUGIN_SQLPLAYLIST
	EN	SQL Playlist

PLUGIN_SQLPLAYLIST_DISABLED
	EN	SQL Playlist Stopped

PLUGIN_SQLPLAYLIST_BEFORE_NUM_TRACKS
	EN	Now Playing will show

PLUGIN_SQLPLAYLIST_AFTER_NUM_TRACKS
	EN	upcoming songs and

PLUGIN_SQLPLAYLIST_AFTER_NUM_OLD_TRACKS
	EN	recently played songs.

PLUGIN_SQLPLAYLIST_SETUP_GROUP
	EN	SQL PlayList

PLUGIN_SQLPLAYLIST_SETUP_GROUP_DESC
	EN	SQL PlayList is a smart playlist plugins based on SQL queries

PLUGIN_SQLPLAYLIST_PLAYLIST_DIRECTORY
	EN	Playlist directory

PLUGIN_SQLPLAYLIST_SHOW_MESSAGES
	EN	Show debug messages

PLUGIN_SQLPLAYLIST_NUMBER_OF_TRACKS
	EN	Number of tracks

PLUGIN_SQLPLAYLIST_NUMBER_OF_OLD_TRACKS
	EN	Number of old tracks

SETUP_PLUGIN_SQLPLAYLIST_PLAYLIST_DIRECTORY
	EN	Playlist directory

SETUP_PLUGIN_SQLPLAYLIST_SHOWMESSAGES
	EN	Debugging

SETUP_PLUGIN_SQLPLAYLIST_NUMBER_OF_TRACKS
	EN	Number of tracks

SETUP_PLUGIN_SQLPLAYLIST_NUMBER_OF_OLD_TRACKS
	EN	Number of old tracks

PLUGIN_SQLPLAYLIST_BEFORE_NUM_TRACKS
	EN	Now Playing will show

PLUGIN_SQLPLAYLIST_AFTER_NUM_TRACKS
	EN	upcoming songs and

PLUGIN_SQLPLAYLIST_AFTER_NUM_OLD_TRACKS
	EN	recently played songs.

PLUGIN_SQLPLAYLIST_CHOOSE_BELOW
	EN	Choose a playlist with music from your library:

PLUGIN_SQLPLAYLIST_CONTEXT_CHOOSE_BELOW
	EN	Choose a playlist with music from your library related to

PLUGIN_SQLPLAYLIST_PLAYING
	EN	Playing

PLUGIN_SQLPLAYLIST_PRESS_RIGHT
	EN	Press RIGHT to stop adding songs

PLUGIN_SQLPLAYLIST_GENERAL_HELP
	EN	You can add or remove songs from your mix at any time. To stop adding songs, clear your playlist or click to

PLUGIN_SQLPLAYLIST_DISABLE
	EN	Stop adding songs

PLUGIN_SQLPLAYLIST_CONTINUOUS_MODE
	EN	Add new items when old ones finish

PLUGIN_SQLPLAYLIST_NOW_PLAYING_FAILED
	EN	Failed 

PLUGIN_SQLPLAYLIST_EDIT_PLAYLIST
	EN	Edit

PLUGIN_SQLPLAYLIST_NEW_PLAYLIST
	EN	Create new playlist

PLUGIN_SQLPLAYLIST_NEW_PLAYLIST_TYPES_TITLE
	EN	Select type of playlist

PLUGIN_SQLPLAYLIST_EDIT_PLAYLIST_QUERY
	EN	SQL Query

PLUGIN_SQLPLAYLIST_EDIT_PLAYLIST_NAME
	EN	Playlist Name

PLUGIN_SQLPLAYLIST_EDIT_PLAYLIST_FILENAME
	EN	Filename

PLUGIN_SQLPLAYLIST_EDIT_PLAYLIST_GROUPS
	EN	Groups

PLUGIN_SQLPLAYLIST_REMOVE_PLAYLIST
	EN	Delete

PLUGIN_SQLPLAYLIST_REMOVE_PLAYLIST_QUESTION
	EN	Are you sure you want to delete this playlist ?

PLUGIN_SQLPLAYLIST_TEMPLATE_GENRES_TITLE
	EN	Genres

PLUGIN_SQLPLAYLIST_TEMPLATE_GENRES_SELECT_NONE
	EN	No Genres

PLUGIN_SQLPLAYLIST_TEMPLATE_GENRES_SELECT_ALL
	EN	All Genres

PLUGIN_SQLPLAYLIST_TEMPLATE_ARTISTS_SELECT_NONE
	EN	No Artists

PLUGIN_SQLPLAYLIST_TEMPLATE_ARTISTS_SELECT_ALL
	EN	All Artists

PLUGIN_SQLPLAYLIST_TEMPLATE_CUSTOM
	EN	Blank playlist

PLUGIN_SQLPLAYLIST_TEMPLATE_ARTISTS_TITLE
	EN	Artists

PLUGIN_SQLPLAYLIST_TEMPLATE_INCLUDING_GENRES
	EN	Playlist including songs for selected genres only

PLUGIN_SQLPLAYLIST_TEMPLATE_INCLUDING_ARTISTS
	EN	Playlist including songs for selected artists only

PLUGIN_SQLPLAYLIST_TEMPLATE_INCLUDING_GENRES_INCLUDING_ARTISTS
	EN	Playlist including songs for selected genres and selected artists only

PLUGIN_SQLPLAYLIST_TEMPLATE_EXCLUDING_GENRES
	EN	Playlist excluding all songs for selected genres

PLUGIN_SQLPLAYLIST_TEMPLATE_EXCLUDING_ARTISTS
	EN	Playlist excluding all songs for selected aritsts

PLUGIN_SQLPLAYLIST_TEMPLATE_EXCLUDING_GENRES_EXCLUDING_ARTISTS
	EN	Playlist excluding all songs for selected aritsts and excluding all songs for selected genres

PLUGIN_SQLPLAYLIST_TEMPLATE_RANDOM
	EN	Playlist with all songs

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATED
	EN	Playlist with all top rated songs (4 and 5)

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATED_INCLUDING_GENRES
	EN	Playlist with all top rated songs (4 and 5) for the selected genres

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATED_INCLUDING_GENRES_INCLUDING_ARTISTS
	EN	Playlist with all top rated songs (4 and 5) for the selected genres and selected artists only

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATED_INCLUDING_ARTISTS
	EN	Playlist with all top rated songs (4 and 5) for the selected artists

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATED_EXCLUDING_GENRES
	EN	Playlist with all top rated songs (4 and 5) excluding songs in selected genres

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATED_EXCLUDING_ARTISTS
	EN	Playlist with all top rated songs (4 and 5) excluding songs in selected artists

PLUGIN_SQLPLAYLIST_TESTPLAYLIST
	EN	Test

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATED_EXCLUDING_GENRES_EXCLUDING_ARTISTS
	EN	Playlist with all top rated songs (4 and 5) excluding all songs for selected aritsts and excluding all songs for selected genres

PLUGIN_SQLPLAYLIST_TEMPLATE_MAXTRACKLENGTH
	EN	Max track length (in seconds)

PLUGIN_SQLPLAYLIST_TEMPLATE_MINTRACKLENGTH
	EN	Min track length (in seconds)

PLUGIN_SQLPLAYLIST_TEMPLATE_MAXTRACKYEAR
	EN	Only include tracks before or equal to this year

PLUGIN_SQLPLAYLIST_TEMPLATE_MINTRACKYEAR
	EN	Only include tracks after or equal to this year

PLUGIN_SQLPLAYLIST_TEMPLATE_NOTREPEAT
	EN	Do not repeat tracks within same playlist

PLUGIN_SQLPLAYLIST_SAVE
	EN	Save

PLUGIN_SQLPLAYLIST_SAVEPLAY
	EN	Save &amp; Play

PLUGIN_SQLPLAYLIST_NEXT
	EN	Next

PLUGIN_SQLPLAYLIST_NEXTPLAY
	EN	Next &amp; Play

PLUGIN_SQLPLAYLIST_TEST_CHOOSE_PARAMETERS
	EN	This playlist requires parameters, please select values

PLUGIN_SQLPLAYLIST_TEMPLATE_PARAMETER_PLAYLISTS
	EN	Playlists with user selectable parameters

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATEDFORYEAR
	EN	Playlist with top rated songs (4 and 5) for user selectable year

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATEDFORGENRE
	EN	Playlist with top rated songs (4 and 5) for user selectable genre

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATEDFORARTIST
	EN	Playlist with top rated songs (4 and 5) for user selectable artist

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATEDFORALBUM
	EN	Playlist with top rated songs (4 and 5) for user selectable album

PLUGIN_SQLPLAYLIST_TEMPLATE_TOPRATEDFORPLAYLIST
	EN	Playlist with top rated songs (4 and 5) for user selectable playlist

PLUGIN_SQLPLAYLIST_TEMPLATE_WITHSPECIFICRATING
	EN	Playlist with songs with user selectable rating

PLUGIN_SQLPLAYLIST_TEMPLATE_WITHSPECIFICRATINGFORARTIST
	EN	Playlist with songs with user selectable rating and artist

PLUGIN_SQLPLAYLIST_TEMPLATE_TRACKSTAT_PLAYLISTS
	EN	All the following playlists requires that the TrackStat plugin is installed

PLUGIN_SQLPLAYLIST_TEMPLATE_INCLUDE_COMMENT
	EN	Include tracks with COMMENT tag

PLUGIN_SQLPLAYLIST_TEMPLATE_EXCLUDE_COMMENT
	EN	Exclude tracks with COMMENT tag

PLUGIN_SQLPLAYLIST_PLAYLISTTYPE
	EN	Customize SQL
	
PLUGIN_SQLPLAYLIST_PLAYLISTTYPE_SIMPLE
	EN	Use predefined

PLUGIN_SQLPLAYLIST_PLAYLISTTYPE_ADVANCED
	EN	Customize SQL

PLUGIN_SQLPLAYLIST_NEW_PLAYLIST_PARAMETERS_TITLE
	EN	Please enter playlist parameters

PLUGIN_SQLPLAYLIST_EDIT_PLAYLIST_PARAMETERS_TITLE
	EN	Please enter playlist parameters
EOF

}

1;

__END__
