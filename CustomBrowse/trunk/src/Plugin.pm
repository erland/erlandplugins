# 				CustomBrowse plugin 
#
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
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

package Plugins::CustomBrowse::Plugin;

use strict;

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use File::Spec::Functions qw(:ALL);
use File::Slurp;
use XML::Simple;
use Data::Dumper;
use DBI qw(:sql_types);
use FindBin qw($Bin);


my $driver;
my $browseMenus;

sub getDisplayName {
	return 'PLUGIN_CUSTOMBROWSE';
}

# Returns the display text for the currently selected item in the menu
sub getDisplayText {
	my ($client, $item) = @_;

	my $id = undef;
	my $name = '';
	if($item) {
            my $format = $item->{'itemformat'};
            if(defined($format)) {
                if($format eq 'track') {
                    my $track = objectForId('track',$item->{'itemid'});
                    $name = Slim::Music::Info::standardTitle(undef, $track);
                }
            }
            if($name eq '') {
		$name = $item->{'name'};
            }
            if(!defined($name) || $name eq '') {
		$name = $item->{'itemname'};
            }
	}
	return $name;
}


# Returns the overlay to be display next to items in the menu
sub getOverlay {
	my ($client, $item) = @_;
	my $playable = undef;

	if(defined($item->{'itemtype'})) {
		if($item->{'itemtype'} eq "track" || $item->{'itemtype'} eq "album" || $item->{'itemtype'} eq "artist" || $item->{'itemtype'} eq "year" || $item->{'itemtype'} eq "genre"  || $item->{'itemtype'} eq "playlist") {
			$playable = Slim::Display::Display::symbol('notesymbol');
		}
	}
	if(defined($item->{'menu'}) && ref($item->{'menu'}) eq 'ARRAY') {
		return [$playable, Slim::Display::Display::symbol('rightarrow')];
	}elsif(defined($item->{'menu'}) && defined($item->{'menu'}->{'menutype'})) {
		if($item->{'menu'}->{'menutype'} ne "trackdetails") {
			return [$playable, Slim::Display::Display::symbol('rightarrow')];
		}
	}
	return [$playable, undef];
}

sub setMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

        readBrowseConfiguration($client);
        getMenu($client,undef);
}

sub getMenu {
    my $client = shift;
    my $item = shift;

    my @listRef = ();
    eval {
    if(!defined($item)) {
        for my $menu (keys %$browseMenus) {
            if(!defined($browseMenus->{$menu}->{'value'})) {
            	$browseMenus->{$menu}->{'value'} = $browseMenus->{$menu}->{'id'};
            }
            if($browseMenus->{$menu}->{'enabled'}) {
	            push @listRef,$browseMenus->{$menu};
            }
        }
	@listRef = sort { $a->{'name'} cmp $b->{'name'} } @listRef;
    }elsif(defined($item->{'menu'})) {
	my @menus = ();
	if(ref($item->{'menu'}) eq 'ARRAY') {
		foreach my $it (@{$item->{'menu'}}) {
			push @menus,$it;
		}
	}else {
		push @menus,$item->{'menu'};
	}
	foreach my $menu (@menus) {
		if(!defined($menu->{'menutype'})) {
	                my %menuItem = (
	                    'itemid' => $menu->{'id'},
	                    'itemname' => $menu->{'name'}
	                );
	                $menuItem{'value'} = $item->{'value'}."_".$menu->{'id'};
	                for my $menuKey (keys %{$menu}) {
	                    $menuItem{$menuKey} = $menu->{$menuKey};
	                }
	                my %parameters = ();
	                $menuItem{'parameters'} = \%parameters;
	                if(defined($item->{'parameters'})) {
	                    for my $param (keys %{$item->{'parameters'}}) {
	                        $menuItem{'parameters'}->{$param} = $item->{'parameters'}->{$param};
	                    }
	                }
	                if(defined($menu->{'id'})) {
	                    $menuItem{'parameters'}->{$menu->{'id'}} = $menu->{'id'};
	                }
	                push @listRef, \%menuItem;
	
	        }elsif($menu->{'menutype'} eq 'sql') {
	            my $sql = prepareMenuSQL($menu->{'menudata'},$item->{'parameters'});
	            my $menuData = getSQLMenuData($sql);
	            for my $dataItem (@$menuData) {
	                my %menuItem = (
	                    'itemid' => $dataItem->{'id'},
	                    'itemname' => $dataItem->{'name'}
	                );
	                $menuItem{'value'} = $item->{'value'}."_".$dataItem->{'name'};
	
	                for my $menuKey (keys %{$menu}) {
	                    $menuItem{$menuKey} = $menu->{$menuKey};
	                }
	                my %parameters = ();
	                $menuItem{'parameters'} = \%parameters;
	                if(defined($item->{'parameters'})) {
	                    for my $param (keys %{$item->{'parameters'}}) {
	                        $menuItem{'parameters'}->{$param} = $item->{'parameters'}->{$param};
	                    }
	                }
	                if(defined($menu->{'id'})) {
	                    $menuItem{'parameters'}->{$menu->{'id'}} = $dataItem->{'id'};
	                }
	                push @listRef, \%menuItem;
	            }
	        }elsif($menu->{'menutype'} eq 'trackdetails') {
	            my $track = objectForId('track',$item->{'parameters'}->{$menu->{'menudata'}});
	            if(defined($track)) {
	                Slim::Buttons::Common::pushModeLeft($client,'trackinfo',{'track' => $track});
	                return;
	            }   
	        }elsif($menu->{'menutype'} eq 'mode') {
	            Slim::Buttons::Common::pushModeLeft($client,$menu->{'menudata'},undef);
	            return;
	        }elsif($menu->{'menutype'} eq 'folder') {
	            my $dir = $menu->{'menudata'};
	            $dir = replaceParameters($dir,$item->{'parameters'});
	            for my $subdir (Slim::Utils::Misc::readDirectory($dir)) {
	            	if(-d catdir($dir, $subdir)) {
		                my %menuItem = (
		                    'itemid' => escape($subdir),
		                    'itemname' => $subdir
		                );
		                $menuItem{'value'} = $item->{'value'}."_".$subdir;
	
		                for my $menuKey (keys %{$menu}) {
		                    $menuItem{$menuKey} = $menu->{$menuKey};
		                }
		                my %parameters = ();
		                $menuItem{'parameters'} = \%parameters;
		                if(defined($item->{'parameters'})) {
		                    for my $param (keys %{$item->{'parameters'}}) {
		                        $menuItem{'parameters'}->{$param} = $item->{'parameters'}->{$param};
		                    }
		                }
		                if(defined($menu->{'id'})) {
		                    $menuItem{'parameters'}->{$menu->{'id'}} = escape($subdir);
		                }
		                push @listRef, \%menuItem;
			}
			@listRef = sort { $a->{'itemname'} cmp $b->{'itemname'} } @listRef;
	            }	
	        }
	}
    }
    };
    if( $@ ) {
	errorMsg("CustomBrowse: Failed to get menu:\n$@\n");
    }		
	
    if(scalar(@listRef)==0) {
        $client->bumpRight();
        return;
    }

    my $modeNamePostFix = '';
    my $menuTitle = '{PLUGIN_CUSTOMBROWSE}';
    if(defined($item)) {
	$modeNamePostFix = $item->{'value'};
	if(defined($item->{'itemname'})) {
		$menuTitle = $item->{'itemname'};
	}elsif(defined($item->{'name'})) {
		$menuTitle = $item->{'name'};
	}
    }
    # use INPUT.Choice to display the list of feeds
    my %params = (
            header     => $menuTitle.' {count}',
            listRef    => \@listRef,
            name       => \&getDisplayText,
            overlayRef => \&getOverlay,
            modeName   => 'PLUGIN.CustomBrowse'.$modeNamePostFix,
            onPlay     => sub {
                    my ($client, $item) = @_;
                    if(defined($item->{'itemtype'})) {
			my $request = undef;
			if($item->{'itemtype'} eq "track") {
				$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('track'),$item->{'itemid'})]);
			}elsif($item->{'itemtype'} eq "album") {
				$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('album'),$item->{'itemid'})]);
			}elsif($item->{'itemtype'} eq "artist") {
				$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('artist'),$item->{'itemid'})]);
			}elsif($item->{'itemtype'} eq "year") {
				$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('year'),$item->{'itemid'})]);
			}elsif($item->{'itemtype'} eq "genre") {
				$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('genre'),$item->{'itemid'})]);
			}elsif($item->{'itemtype'} eq "playlist") {
				$request = $client->execute(['playlist', 'loadtracks', sprintf('%s=%d', getLinkAttribute('playlist'),$item->{'itemid'})]);
			}else {
	                    	debugMsg("Can not play item with itemtype=".$item->{'itemtype'}."\n");
			}
			if ($::VERSION ge '6.5' && defined($request)) {
				# indicate request source
				$request->source('PLUGIN_CUSTOMBROWSE');
                        }
			if(defined($request)) {
				my $string;
				my $line1;
				my $line2;
				if (Slim::Player::Playlist::shuffle($client)) {
                                        $string = 'PLAYING_RANDOMLY_FROM';
                                } else {
                                        $string = 'NOW_PLAYING_FROM';
                                }

	                        if ($client->linesPerScreen == 1) {
        	                        $line2 = $client->doubleString($string);
                	        } else {
                        	        $line1 = $client->string($string);
	                                $line2 = $item->{'itemname'};
	                        }
				if ($::VERSION ge '6.5') {
		                        $client->showBriefly({
		                                'line'    => [ $line1, $line2 ],
		                                'overlay' => [ undef, $client->symbols('notesymbol') ],
		                        });
				}else {
					$client->showBriefly({
						'line1' => $line1,
						'line2' => $line2,
						'overlay2' => $client->symbols('notesymbol')
					});
				}
			}
                    }else {
                    	debugMsg("Can not play item with undefined itemtype\n");
                    }			
            },
            onAdd      => sub {
                    my ($client, $item) = @_;
                    my $playlist = $item->{'playlist'};
                    if(defined($item->{'itemtype'})) {
			my $request = undef;
			if($item->{'itemtype'} eq "track") {
				$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('track'),$item->{'itemid'})]);
			}elsif($item->{'itemtype'} eq "album") {
				$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('album'),$item->{'itemid'})]);
			}elsif($item->{'itemtype'} eq "artist") {
				$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('artist'),$item->{'itemid'})]);
			}elsif($item->{'itemtype'} eq "year") {
				$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('year'),$item->{'itemid'})]);
			}elsif($item->{'itemtype'} eq "genre") {
				$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('genre'),$item->{'itemid'})]);
			}elsif($item->{'itemtype'} eq "playlist") {
				$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('playlist'),$item->{'itemid'})]);
			}else {
	                    	debugMsg("Can not add item with itemtype=".$item->{'itemtype'}."\n");
			}
			if ($::VERSION ge '6.5' && defined($request)) {
				# indicate request source
				$request->source('PLUGIN_CUSTOMBROWSE');
                        }                    
			if(defined($request)) {
				my $string;
				my $line1;
				my $line2;
                                $string = 'ADDING_TO_PLAYLIST';

	                        if ($client->linesPerScreen == 1) {
        	                        $line2 = $client->doubleString($string);
                	        } else {
                        	        $line1 = $client->string($string);
	                                $line2 = $item->{'itemname'};
	                        }

				if ($::VERSION ge '6.5') {
		                        $client->showBriefly({
		                                'line'    => [ $line1, $line2 ],
		                                'overlay' => [ undef, $client->symbols('notesymbol') ],
		                        });
				}else {
					$client->showBriefly({
						'line1' => $line1,
						'line2' => $line2,
						'overlay2' => $client->symbols('notesymbol')
					});
				}
			}
                    }else {
                    	debugMsg("Can not add item with undefined itemtype\n");
                    }			
            },
            onRight    => sub {
                    my ($client, $item) = @_;
                    getMenu($client,$item);
            },
    );

    Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
}
sub prepareMenuSQL {
    my $sql = shift;
    my $parameters = shift;
    
    debugMsg("Preparing SQL: $sql\n");
    $sql = replaceParameters($sql,$parameters);

    return $sql;
}

sub replaceParameters {
    my $originalValue = shift;
    my $parameters = shift;

    if(defined($parameters)) {
        for my $param (keys %$parameters) {
            my $value = $parameters->{$param};
            $originalValue =~ s/\{$param\}/$value/g;
        }
    }
    my $audiodir = Slim::Utils::Prefs::get('audiodir');
    $originalValue =~ s/\{custombrowse\.audiodir\}/$audiodir/g;
    my $audiodirurl = Slim::Utils::Misc::fileURLFromPath($audiodir);
    $originalValue =~ s/\{custombrowse\.audiodirurl\}/$audiodirurl/g;

    return $originalValue;
}

sub getSQLMenuData {
	my $sqlstatements = shift;
	my $limit = shift;
	my @result;
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
				$sth->bind_col( 1, \$id);
                                $sth->bind_col( 2, \$name);
				while( $sth->fetch() ) {
                                    my %item = (
                                        'id' => $id,
                                        'name' => Slim::Utils::Unicode::utf8decode($name,'utf8')
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

sub initPlugin {
	my $class = shift;
	
	checkDefaults();
	Slim::Buttons::Common::addMode('PLUGIN.CustomBrowse', getFunctions(), \&setMode);
}

sub webPages {

	my %pages = (
		"index\.(?:htm|xml)"     => \&handleWebList,
	);

	my $value = 'plugins/CustomBrowse/index.html';

	if (grep { /^CustomBrowse::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

		$value = undef;
	} 

	#Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_CUSTOMBROWSE' => $value });

	return (\%pages,$value);
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/index.html', $params);
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

	my $prefVal = Slim::Utils::Prefs::get('plugin_custombrowse_showmessages');
	if (! defined $prefVal) {
		# Default to standard playlist directory
		debugMsg("Defaulting plugin_custombrowse_showmessages to 0\n");
		Slim::Utils::Prefs::set('plugin_custombrowse_showmessages', 0);
	}

        $prefVal = Slim::Utils::Prefs::get('plugin_custombrowse_directory');
	if (! defined $prefVal) {
		# Default to standard playlist directory
		my $dir=Slim::Utils::Prefs::get('playlistdir');
		debugMsg("Defaulting plugin_custombrowse_directory to:$dir\n");
		Slim::Utils::Prefs::set('plugin_custombrowse_directory', $dir);
	}
}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_custombrowse_directory','plugin_custombrowse_showmessages'],
	 GroupHead => string('PLUGIN_CUSTOMBROWSE_SETUP_GROUP'),
	 GroupDesc => string('PLUGIN_CUSTOMBROWSE_SETUP_GROUP_DESC'),
	 GroupLine => 1,
	 GroupSub  => 1,
	 Suppress_PrefSub  => 1,
	 Suppress_PrefLine => 1
	);
	my %setupPrefs =
	(
	plugin_custombrowse_showmessages => {
			'validate'     => \&validateTrueFalseWrapper
			,'PrefChoose'  => string('PLUGIN_CUSTOMBROWSE_SHOW_MESSAGES')
			,'changeIntro' => string('PLUGIN_CUSTOMBROWSE_SHOW_MESSAGES')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_custombrowse_showmessages"); }
		},		
	plugin_custombrowse_directory => {
			'validate' => \&validateIsDirWrapper
			,'PrefChoose' => string('PLUGIN_CUSTOMBROWSE_DIRECTORY')
			,'changeIntro' => string('PLUGIN_CUSTOMBROWSE_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_custombrowse_directory"); }
		},
	);
	return (\%setupGroup,\%setupPrefs);
}

sub webPages {
	my %pages = (
                "custombrowse_list\.(?:htm|xml)"     => \&handleWebList,
		"custombrowse_selectmenus\.(?:htm|xml)" => \&handleWebSelectMenus,
		"custombrowse_saveselectmenus\.(?:htm|xml)" => \&handleWebSaveSelectMenus,
        );

        my $value = 'plugins/CustomBrowse/custombrowse_list.html';

        if (grep { /^CustomBrowse::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

                $value = undef;
        }

        #Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_DYNAMICPLAYLIST' => $value });

        return (\%pages,$value);
}

# Draws the plugin's web page
sub handleWebList {
        my ($client, $params) = @_;

        if ($::VERSION ge '6.5') {
                $params->{'pluginCustomBrowseSlimserver65'} = 1;
        }

        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_list.html', $params);
}

# Draws the plugin's select menus web page
sub handleWebSelectMenus {
        my ($client, $params) = @_;

	readBrowseConfiguration($client);
        # Pass on the current pref values and now playing info
        $params->{'pluginCustomBrowseMenus'} = $browseMenus;
        if ($::VERSION ge '6.5') {
                $params->{'pluginDynamicPlayListSlimserver65'} = 1;
        }

        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_selectmenus.html', $params);
}

# Draws the plugin's web page
sub handleWebSaveSelectMenus {
        my ($client, $params) = @_;

	readBrowseConfiguration($client);
        foreach my $menu (keys %$browseMenus) {
                my $menuid = "menu_".escape($browseMenus->{$menu}->{'id'});
                if($params->{$menuid}) {
                        Slim::Utils::Prefs::set('plugin_custombrowse_'.$menuid.'_enabled',1);
                }else {
                        Slim::Utils::Prefs::set('plugin_custombrowse_'.$menuid.'_enabled',0);
                }
        }

        handleWebList($client, $params);
}


sub readBrowseConfiguration {
    my $client = shift;
    my $browseDir = Slim::Utils::Prefs::get("plugin_custombrowse_directory");
    debugMsg("Searching for custom browse configuration in: $browseDir\n");
    
    my %localBrowseMenus = ();
    my @pluginDirs = ();
    if ($::VERSION ge '6.5') {
        @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
    }else {
        @pluginDirs = catdir($Bin, "Plugins");
    }
    for my $plugindir (@pluginDirs) {
	readBrowseConfigurationFromDir($client,catdir($plugindir,"CustomBrowse","Playlists"),\%localBrowseMenus);
    }
    if (!defined $browseDir || !-d $browseDir) {
            debugMsg("Skipping custom browse configuration scan - directory is undefined\n");
    }else {
	    readBrowseConfigurationFromDir($client,$browseDir,\%localBrowseMenus);
    }
    
    $browseMenus = \%localBrowseMenus;
}

sub readBrowseConfigurationFromDir {
    my $client = shift;
    my $browseDir = shift;
    my $localBrowseMenus = shift;
    debugMsg("Loading browse configuration from: $browseDir\n");

    my @dircontents = Slim::Utils::Misc::readDirectory($browseDir,"cb.xml");
    for my $item (@dircontents) {

	next if -d catdir($browseDir, $item);

        my $path = catfile($browseDir, $item);

        # read_file from File::Slurp
        my $content = eval { read_file($path) };
        if ( $content ) {
            my $xml = eval { 	XMLin($content, forcearray => ["item"], keyattr => []) };
            if ($@) {
                    errorMsg("CustomBrowse: Failed to parse browse configuration in $path because:\n$@\n");
            }else {
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
		my $disabled = 0;
		if(defined($xml->{'menu'}) and defined($xml->{'menu'}->{'id'})) {
			my $enabled = Slim::Utils::Prefs::get('plugin_custombrowse_menu_'.escape($xml->{'menu'}->{'id'}).'_enabled');
			if(defined($enabled) && !$enabled) {
				$disabled = 1;
			}elsif(!defined($enabled)) {
				if(defined($xml->{'defaultdisabled'}) && $xml->{'defaultdisabled'}) {
					$disabled = 1;
				}
			}
		}
		
		if($include && !$disabled) {
			$xml->{'menu'}->{'enabled'}=1;
	                $localBrowseMenus->{$item} = $xml->{'menu'};
		}elsif($include && $disabled) {
			$xml->{'menu'}->{'enabled'}=0;
	                $localBrowseMenus->{$item} = $xml->{'menu'};
		}
            }
    
            # Release content
            undef $content;
        }else {
            if ($@) {
                    errorMsg("CustomBrowse: Unable to open browse configuration file: $path\nBecause of:\n$@\n");
            }else {
                errorMsg("CustomBrowse: Unable to open browse configuration file: $path\n");
            }
        }
    }
}
sub validateIntWrapper {
	my $arg = shift;
	if ($::VERSION ge '6.5') {
		return Slim::Utils::Validate::isInt($arg);
	}else {
		return Slim::Web::Setup::validateInt($arg);
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

sub validateIsDirWrapper {
	my $arg = shift;
	if ($::VERSION ge '6.5') {
		return Slim::Utils::Validate::isDir($arg);
	}else {
		return Slim::Web::Setup::validateIsDir($arg);
	}
}

sub validateAcceptAllWrapper {
	my $arg = shift;
	if ($::VERSION ge '6.5') {
		return Slim::Utils::Validate::acceptAll($arg);
	}else {
		return Slim::Web::Setup::validateAcceptAll($arg);
	}
}

sub validateIntOrEmpty {
	my $arg = shift;
	if(!$arg || $arg eq '' || $arg =~ /^\d+$/) {
		return $arg;
	}
	return undef;
}

sub getCurrentDBH {
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
		return Slim::Schema->storage->dbh();
	}else {
		return Slim::Music::Info::getCurrentDataStore()->dbh();
	}
}

sub getCurrentDS {
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
		return 'Slim::Schema';
	}else {
		return Slim::Music::Info::getCurrentDataStore();
	}
}

sub objectForId {
	my $type = shift;
	my $id = shift;
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
		if($type eq 'artist') {
			$type = 'Contributor';
		}elsif($type eq 'album') {
			$type = 'Album';
		}elsif($type eq 'genre') {
			$type = 'Genre';
		}elsif($type eq 'track') {
			$type = 'Track';
		}elsif($type eq 'playlist') {
			$type = 'Playlist';
		}
		return Slim::Schema->resultset($type)->find($id);
	}else {
		if($type eq 'playlist') {
			$type = 'track';
		}
		return getCurrentDS()->objectForId($type,$id);
	}
}

sub getLinkAttribute {
	my $attr = shift;
	if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
		if($attr eq 'artist') {
			$attr = 'contributor';
		}
		return $attr.'.id';
	}
	return $attr;
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
	my $message = join '','CustomBrowse: ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_custombrowse_showmessages"));
}

sub strings {
	return <<EOF;
PLUGIN_CUSTOMBROWSE
	EN	Custom Browse

PLUGIN_CUSTOMBROWSE_SETUP_GROUP
	EN	Custom Browse

PLUGIN_CUSTOMBROWSE_SETUP_GROUP_DESC
	EN	Custom Browse is a plugin which makes it possible to create your own menus

PLUGIN_CUSTOMBROWSE_SHOW_MESSAGES
	EN	Show debug messages

SETUP_PLUGIN_CUSTOMBROWSE_SHOWMESSAGES
	EN	Debugging

PLUGIN_CUSTOMBROWSE_DIRECTORY
	EN	Browse configuration directory

SETUP_PLUGIN_CUSTOMBROWSE_DIRECTORY
	EN	Browse configuration directory

PLUGIN_CUSTOMBROWSE_SELECT_MENUS
	EN	Enable/Disable menus

PLUGIN_CUSTOMBROWSE_SELECT_MENUS_TITLE
	EN	Select enabled menus

PLUGIN_CUSTOMBROWSE_SELECT_MENUS_NONE
	EN	No Menus

PLUGIN_CUSTOMBROWSE_SELECT_MENUS_ALL
	EN	All Menus

EOF

}

1;

__END__
