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
use POSIX qw(ceil);
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

my %choiceMapping = (
        'arrow_left' => 'exit_left',
        'arrow_right' => 'exit_right',
        'play' => 'dead',
	'play.single' => 'play_0',
	'play.hold' => 'create_mix',
        'add' => 'dead',
        'add.single' => 'add_0',
        'add.hold' => 'insert_0',
        'search' => 'passback',
        'stop' => 'passback',
        'pause' => 'passback'
);

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
            if(!defined($name) || $name eq '') {
		$name = $item->{'itemname'};
            }
            if(!defined($name) || $name eq '') {
		$name = $item->{'menuname'};
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
        my $params = getMenu($client,undef);
	if(defined($params)) {
		if(defined($params->{'useMode'})) {
			Slim::Buttons::Common::pushModeLeft($client, $params->{'useMode'}, $params->{'parameters'});
		}else {
			Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.CustomBrowse.Choice', $params);
		}
	}else {
	        $client->bumpRight();
	}
}
sub getMenuItems {
    my $item = shift;

    my @listRef = ();

    if(!defined($item)) {
        for my $menu (keys %$browseMenus) {
            if(!defined($browseMenus->{$menu}->{'value'})) {
            	$browseMenus->{$menu}->{'value'} = $browseMenus->{$menu}->{'id'};
            }
            if($browseMenus->{$menu}->{'enabled'}) {
	            push @listRef,$browseMenus->{$menu};
            }
        }
	@listRef = sort { $a->{'menuname'} cmp $b->{'menuname'} } @listRef;
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
	                    'itemname' => $menu->{'menuname'}
	                );
			if(defined($item->{'value'})) {
		                $menuItem{'value'} = $item->{'value'}."_".$menu->{'id'};
			}else {
		                $menuItem{'value'} = $menu->{'id'};
			}
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
			if(defined($dataItem->{'link'})) {
	                    $menuItem{'itemlink'} = $dataItem->{'link'};
			}
			if(defined($item->{'value'})) {
		                $menuItem{'value'} = $item->{'value'}."_".$dataItem->{'name'};
			}else {
		                $menuItem{'value'} = $dataItem->{'name'};
			}
	
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
		            my %params = (
		            	'useMode' => 'trackinfo',
		            	'parameters' => 
					{
						'track' => $track
					}			
		            );
		            return \%params;		
	            }
	        }elsif($menu->{'menutype'} eq 'mode') {
	            my %params = (
	            	'useMode' => $menu->{'menudata'},
	            	'parameters' => undef			
	            );
	            return \%params;		
	        }elsif($menu->{'menutype'} eq 'folder') {
	            my $dir = $menu->{'menudata'};
	            $dir = replaceParameters($dir,$item->{'parameters'});
	            $dir = Slim::Utils::Unicode::utf8off($dir);
	            for my $subdir (Slim::Utils::Misc::readDirectory($dir)) {
			my $subdirname = $subdir;
			my $fullpath = catdir($dir, $subdir);
			if(Slim::Music::Info::isWinShortcut($fullpath)) {
				$subdirname = substr($subdir,0,-4);
				$fullpath = Slim::Utils::Misc::pathFromWinShortcut(Slim::Utils::Misc::fileURLFromPath($fullpath));
				if($fullpath ne '') {
					my $tmp = $fullpath;
					$fullpath = Slim::Utils::Misc::pathFromFileURL($fullpath);
					my $libraryAudioDirUrl = getCustomBrowseProperty('libraryAudioDirUrl');
					$tmp =~ s/^$libraryAudioDirUrl//g;
					$tmp =~ s/^[\\\/]?//g;
					$subdir = $tmp;
				}
			}
	            	if(-d $fullpath) {
		                my %menuItem = (
		                    'itemid' => escapeSubDir($subdir),
		                    'itemname' => $subdirname,
		                    'itemlink' => substr($subdirname,0,1)
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
		                    $menuItem{'parameters'}->{$menu->{'id'}} = escapeSubDir($subdir);
		                }
		                push @listRef, \%menuItem;
			}
			@listRef = sort { $a->{'itemname'} cmp $b->{'itemname'} } @listRef;
	            }
	        }
	}
    }
    return \@listRef;
}
sub getCustomBrowseProperty {
	my $name = shift;
	my $properties = getCustomBrowseProperties();
	return $properties->{$name};
}

sub getCustomBrowseProperties {
	my $array = Slim::Utils::Prefs::get('plugin_custombrowse_properties');
	my %result = ();
	foreach my $item (@$array) {
		if($item =~ m/^([a-zA-Z0-9]+?)\s*=\s*(.+)\s*$/) {
			my $name = $1;
			my $value = $2;
			debugMsg("Got property: $name=$value\n");
			$result{$name}=$value;
		}
	}
	return \%result;
}
sub escapeSubDir {
	my $dir = shift;
	my $result = Slim::Utils::Misc::fileURLFromPath($dir);
	if (Slim::Utils::OSDetect::OS() eq "win") {
		return substr($result,8);
	}else {
		return substr($result,3);
	}
}

sub getMenu {
    my $client = shift;
    my $item = shift;

    my $selectedMenu = $client->param('selectedMenu');
    if(!defined($item) && defined($selectedMenu)) {
        for my $menu (keys %$browseMenus) {
		if($browseMenus->{$menu}->{'enabled'} && $selectedMenu eq $browseMenus->{$menu}->{'id'}) {
			$item = $browseMenus->{$menu};
			if(!defined($item->{'value'})) {
				$item->{'value'} = $item->{'id'};
			}
		}
	}
    }

    my @listRef = undef;
    my $items = getMenuItems($item);
    if(ref($items) eq 'ARRAY') {
    	@listRef = @$items;
    }else {
	return $items;     
    }
    
    if(scalar(@listRef)==0) {
        return undef;
    }

    my $modeNamePostFix = '';
    my $menuTitle = '{PLUGIN_CUSTOMBROWSE}';
    if(defined($item)) {
	$modeNamePostFix = $item->{'value'};
	if(defined($item->{'itemname'})) {
		$menuTitle = $item->{'itemname'};
	}elsif(defined($item->{'menuname'})) {
		$menuTitle = $item->{'menuname'};
	}
    }

    my $sorted = '0';
    if(!defined($item)) {
	$sorted = 'L';
    }else {
	if(defined($item->{'menu'}) && ref($item->{'menu'}) eq 'ARRAY') {
		my $menuArray = $item->{'menu'};
		for my $it (@$menuArray) {
			if(defined($it->{'menulinks'}) && $it->{'menulinks'} eq 'alpha') {
				$sorted = 'L';
				last;
			}
		}
	}elsif(defined($item->{'menu'})) {
		if(defined($item->{'menu'}->{'menulinks'}) && $item->{'menu'}->{'menulinks'} eq 'alpha') {
			$sorted = 'L';
		}
	}
    }

    # use PLUGIN.CustomBrowse.Choice to display the list of feeds
    my %params = (
            header     => $menuTitle.' {count}',
            listRef    => \@listRef,
            lookupRef  => sub {
				my ($index) = @_;
				my $sortListRef = Slim::Buttons::Common::param($client,'listRef');
				my $sortItem  = $sortListRef->[$index];
				if(defined($sortItem->{'itemlink'})) {
					return $sortItem->{'itemlink'};
				}elsif(defined($sortItem->{'itemname'})) {
					return $sortItem->{'itemname'};
				}else {
					return $sortItem->{'menuname'};
				}
			},
            isSorted => $sorted,
            name       => \&getDisplayText,
            overlayRef => \&getOverlay,
            modeName   => 'PLUGIN.CustomBrowse'.$modeNamePostFix,
            onCreateMix     => sub {
                    my ($client, $item) = @_;
                    createMix($client, $item);
            },				
            onInsert     => sub {
                    my ($client, $item) = @_;
                    playAddItem($client,$item,'inserttracks','INSERT_TO_PLAYLIST');
            },				
            onPlay     => sub {
                    my ($client, $item) = @_;
                    my $string;		
                    if (Slim::Player::Playlist::shuffle($client)) {
                    	$string = 'PLAYING_RANDOMLY_FROM';
                    } else {
                    	$string = 'NOW_PLAYING_FROM';
                    }
                    playAddItem($client,$item,'loadtracks',$string);
            },
            onAdd      => sub {
                    my ($client, $item) = @_;
                    playAddItem($client,$item,'addtracks','ADDING_TO_PLAYLIST');
            },
            onRight    => sub {
                    my ($client, $item) = @_;
                    my $params = getMenu($client,$item);
                    if(defined($params)) {
	                    if(defined($params->{'useMode'})) {
	                    	Slim::Buttons::Common::pushModeLeft($client, $params->{'useMode'}, $params->{'parameters'});
	                    }else {
	                    	Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.CustomBrowse.Choice', $params);
	                    }
                    }else {
		        $client->bumpRight();
                    }
            },
    );
    return \%params;
}

sub createMix {
	my ($client,$item) = @_;
	if(defined($item->{'itemtype'})) {
		my $Imports = Slim::Music::Import->importers;

		my @mixers = ();

#		for my $import (keys %{$Imports}) {
#			next if !$Imports->{$import}->{'mixer'};
#			next if !$Imports->{$import}->{'use'};
#
#			if ($::VERSION ge '6.5') {
#				if (eval {$import->mixable($item)}) {
#					push @mixers, $import;
#				}
#			}else {
#				push @mixers, $import;
#			}
#		}

		my $itemObj = undef;
		if($item->{'itemtype'} eq "track") {
			$itemObj = objectForId('track',$item->{'itemid'});
		}elsif($item->{'itemtype'} eq "album") {
			$itemObj = objectForId('album',$item->{'itemid'});
		}elsif($item->{'itemtype'} eq "artist") {
			$itemObj = objectForId('artist',$item->{'itemid'});
		}elsif($item->{'itemtype'} eq "year") {
#			$itemObj = objectForId('year',$item->{'itemid'});
		}elsif($item->{'itemtype'} eq "genre") {
			$itemObj = objectForId('genre',$item->{'itemid'});
		}elsif($item->{'itemtype'} eq "playlist") {
			$itemObj = objectForId('playlist',$item->{'itemid'});
		}else {
			debugMsg("Can not create mix for item with itemtype=".$item->{'itemtype'}."\n");
		}

		if(defined($itemObj)) {
			msg("CustomBrowse: Creating mix not supported yet\n"); 
		}
	}else {
		debugMsg("Can not play/add item with undefined itemtype\n");
	}			
}

sub playAddItem {
	my ($client,$item, $command, $displayString) = @_;
	if(defined($item->{'itemtype'})) {
		my $request = undef;
		if($item->{'itemtype'} eq "track") {
			$request = $client->execute(['playlist', $command, sprintf('%s=%d', getLinkAttribute('track'),$item->{'itemid'})]);
		}elsif($item->{'itemtype'} eq "album") {
			$request = $client->execute(['playlist', $command, sprintf('%s=%d', getLinkAttribute('album'),$item->{'itemid'})]);
		}elsif($item->{'itemtype'} eq "artist") {
			$request = $client->execute(['playlist', $command, sprintf('%s=%d', getLinkAttribute('artist'),$item->{'itemid'})]);
		}elsif($item->{'itemtype'} eq "year") {
			$request = $client->execute(['playlist', $command, sprintf('%s=%d', getLinkAttribute('year'),$item->{'itemid'})]);
		}elsif($item->{'itemtype'} eq "genre") {
			$request = $client->execute(['playlist', $command, sprintf('%s=%d', getLinkAttribute('genre'),$item->{'itemid'})]);
		}elsif($item->{'itemtype'} eq "playlist") {
			$request = $client->execute(['playlist', $command, sprintf('%s=%d', getLinkAttribute('playlist'),$item->{'itemid'})]);
		}else {
			debugMsg("Can not play/add item with itemtype=".$item->{'itemtype'}."\n");
		}
		if ($::VERSION ge '6.5' && defined($request)) {
			# indicate request source
			$request->source('PLUGIN_CUSTOMBROWSE');
		}
		if(defined($request)) {
			my $line1;
			my $line2;

			if ($client->linesPerScreen == 1) {
				$line2 = $client->doubleString($displayString);
			} else {
				$line1 = $client->string($displayString);
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
		debugMsg("Can not play/add item with undefined itemtype\n");
	}			
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
    my $dbh = getCurrentDBH();

    if(defined($parameters)) {
        for my $param (keys %$parameters) {
            my $value = $dbh->quote($parameters->{$param});
	    $value = substr($value, 1, -1);
            $originalValue =~ s/\{$param\}/$value/g;
        }
    }
    while($originalValue =~ m/\{custombrowse\.(.*?)\}/) {
	my $propertyValue = getCustomBrowseProperty($1);
	if(defined($propertyValue)) {
		$propertyValue = $dbh->quote($propertyValue);
	    	$propertyValue = substr($propertyValue, 1, -1);
		$originalValue =~ s/\{custombrowse\.$1\}/$propertyValue/g;
	}else {
		$originalValue =~ s/\{custombrowse\..*?\}//g;
	}
    }
    while($originalValue =~ m/\{property\.(.*?)\}/) {
	my $propertyValue = Slim::Utils::Prefs::get($1);
	if(defined($propertyValue)) {
		$propertyValue = $dbh->quote($propertyValue);
	    	$propertyValue = substr($propertyValue, 1, -1);
		$originalValue =~ s/\{property\.$1\}/$propertyValue/g;
	}else {
		$originalValue =~ s/\{property\..*?\}//g;
	}
    }

    return $originalValue;
}

sub getSQLMenuData {
	my $sqlstatements = shift;
	my $limit = shift;
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
                                my $link;
				$sth->bind_col( 1, \$id);
                                $sth->bind_col( 2, \$name);
				# bind optional column
				eval {
	                                $sth->bind_col( 3, \$link);
				};
				while( $sth->fetch() ) {
                                    my %item = (
                                        'id' => $id,
                                        'name' => Slim::Utils::Unicode::utf8decode($name,'utf8')
                                    );
				    if(defined($link)) {
					$item{'link'} = Slim::Utils::Unicode::utf8decode($link,'utf8');
                                    }
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
	my %choiceFunctions =  %{Slim::Buttons::Input::Choice::getFunctions()};
	$choiceFunctions{'create_mix'} = sub {Slim::Buttons::Input::Choice::callCallback('onCreateMix', @_)};
	$choiceFunctions{'insert'} = sub {Slim::Buttons::Input::Choice::callCallback('onInsert', @_)};
	Slim::Buttons::Common::addMode('PLUGIN.CustomBrowse.Choice',\%choiceFunctions,\&Slim::Buttons::Input::Choice::setMode);
	for my $buttonPressMode (qw{repeat hold hold_release single double}) {
		if(!defined($choiceMapping{'play.' . $buttonPressMode})) {
			$choiceMapping{'play.' . $buttonPressMode} = 'dead';
		}
		if(!defined($choiceMapping{'add.' . $buttonPressMode})) {
			$choiceMapping{'add.' . $buttonPressMode} = 'dead';
		}
		if(!defined($choiceMapping{'search.' . $buttonPressMode})) {
			$choiceMapping{'search.' . $buttonPressMode} = 'passback';
		}
		if(!defined($choiceMapping{'stop.' . $buttonPressMode})) {
			$choiceMapping{'stop.' . $buttonPressMode} = 'passback';
		}
		if(!defined($choiceMapping{'pause.' . $buttonPressMode})) {
			$choiceMapping{'pause.' . $buttonPressMode} = 'passback';
		}
	}
        Slim::Hardware::IR::addModeDefaultMapping('PLUGIN.CustomBrowse.Choice',\%choiceMapping);

	Slim::Buttons::Common::addMode('PLUGIN.CustomBrowse', getFunctions(), \&setMode);

	readBrowseConfiguration();
	my %submenu = (
		'useMode' => 'PLUGIN.CustomBrowse',
	);
	Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC',string('PLUGIN_CUSTOMBROWSE'),\%submenu);
	addPlayerMenus();
}

sub addPlayerMenus {
        for my $menu (keys %$browseMenus) {
            if(!defined($browseMenus->{$menu}->{'value'})) {
            	$browseMenus->{$menu}->{'value'} = $browseMenus->{$menu}->{'id'};
            }
            my $name;
            if(defined($browseMenus->{$menu}->{'itemname'})) {
            	$name = $browseMenus->{$menu}->{'itemname'};
            }else {
            	$name = $browseMenus->{$menu}->{'menuname'};
            }
            if($browseMenus->{$menu}->{'enabledbrowse'}) {
		my %submenu = (
			'useMode' => 'PLUGIN.CustomBrowse',
			'selectedMenu' => $browseMenus->{$menu}->{'id'}
		);
		Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC',$name,\%submenu);
            }else {
                Slim::Buttons::Home::delSubMenu('BROWSE_MUSIC',$name);
            }
        }
}
sub getPageItemsForContext {
	my $client = shift;
	my $params = shift;
	my $currentItems = shift;

	my $item = undef;
	my $contextItems = getContext($client,$params,$currentItems,0);
	my @contexts = @$contextItems;

	my $context = undef;
	my $currentMenu = undef;
	if(scalar(@contexts)>0) {
		$context = @contexts[scalar(@contexts)-1];
		$item = $context->{'item'};
		$item->{'parameters'} = $context->{'parameters'};
		if(defined($item->{'menu'}) && ref($item->{'menu'}) eq 'ARRAY') {
			foreach my $it (@{$item->{'menu'}}) {
				$currentMenu = $it;
			}
		}elsif(defined($item->{'menu'})) {
			$currentMenu = $item->{'menu'};
		}
	}
	my %result = ();
	my $items = getMenuItems($item);
	if(ref($items) eq 'ARRAY') {
		my @resultItems = ();
		my %pagebar = ();
		$result{'pageinfo'}=\%pagebar;
		$result{'pageinfo'}->{'totalitems'} = scalar(@$items);
		my $itemsPerPage = Slim::Utils::Prefs::get('itemsPerPage');
		$result{'pageinfo'}->{'itemsperpage'} = $itemsPerPage;
		if(defined($currentMenu) && defined($currentMenu->{'menulinks'}) && $currentMenu->{'menulinks'} eq 'alpha') {
			my %alphaMap = ();
			my $itemNo = 0;
			my $prevLetter = '';
			my $letter = '';
			my $pageItemNo=0;
			my $startItemNo = 0;
			for my $alphaIt (@$items) {
				if($pageItemNo>=$itemsPerPage) {
					$pageItemNo = $pageItemNo - $itemsPerPage;
					$startItemNo = $itemNo;
				}
				$prevLetter = $letter;
				$letter = $alphaIt->{'itemlink'};
				if($letter ne $prevLetter) {
					$alphaMap{$letter}=$startItemNo;
				}
				$itemNo =$itemNo + 1;
				$pageItemNo = $pageItemNo + 1;
			}
			$result{'pageinfo'}->{'alphamap'}=\%alphaMap;
		}
		my $start = 0;
		if(defined($params->{'start'})) {
			$start = $params->{'start'};
			@$items = splice(@$items,$params->{'start'});
		}
		$result{'pageinfo'}->{'currentpage'} = int($start/$itemsPerPage);
		$result{'pageinfo'}->{'totalpages'} = ceil($result{'pageinfo'}->{'totalitems'}/$itemsPerPage) || 0;
		$result{'pageinfo'}->{'enditem'} = $start+$itemsPerPage -1;
		$result{'pageinfo'}->{'startitem'} = $start || 0;
		if($result{'pageinfo'}->{'enditem'}>=$result{'pageinfo'}->{'totalitems'}) {
			$result{'pageinfo'}->{'enditem'} = $result{'pageinfo'}->{'totalitems'}-1;
		}
		if(defined($context)) {
			$result{'pageinfo'}->{'otherparams'} = $context->{'url'}.$context->{'valueUrl'};
		}
		my $count = 0;
		for my $it (@$items) {
			if(defined($itemsPerPage) && $itemsPerPage>0) {
				$count = $count + 1;
				if($count>$itemsPerPage) {
					last;
				}
			}
			if(!defined($it->{'itemid'})) {
				$it->{'itemid'} = $it->{'id'}
			}
			if(!defined($it->{'itemname'})) {
				$it->{'itemname'} = $it->{'menuname'}
			}
			if(defined($it->{'menu'})) {
				if(ref($it->{'menu'}) ne 'ARRAY' && defined($it->{'menu'}->{'menutype'}) && $it->{'menu'}->{'menutype'} eq 'trackdetails') {
					my $id;
					if($it->{'menu'}->{'menudata'} eq $it->{'id'}) {
						$id = $it->{'itemid'};
					}else {
						$id = $item->{'parameters'}->{$it->{'menu'}->{'menudata'}};
					}
					$it->{'externalurl'}='songinfo.html?item='.escape($id).'&player='.$params->{'player'};
				}elsif(ref($it->{'menu'}) ne 'ARRAY' && defined($it->{'menu'}->{'menutype'}) && $it->{'menu'}->{'menutype'} eq 'mode') {
					if(defined($it->{'menu'}->{'menuurl'})) {
						my $url = $it->{'menu'}->{'menuurl'};
						$url = replaceParameters($url,$params);
						$it->{'externalurl'}=$url;
					}
				}else {
					if(defined($context)) {
						$it->{'url'}=$context->{'url'}.','.$it->{'id'}.$context->{'valueUrl'}.'&'.$it->{'id'}.'='.=escape($it->{'itemid'});
					}else {
						$it->{'url'}='&hierarchy='.$it->{'id'}.'&'.$it->{'id'}.'='.escape($it->{'itemid'});
					}
				}
			}
			if(defined($it->{'itemformat'})) {
				my $format = $it->{'itemformat'};
				if($format eq 'track') {
					my $track = objectForId('track',$it->{'itemid'});
					displayAsHTML('track',$it,$track);
				}elsif($format eq 'album') {
					$result{'artwork'} = 1;
					my $track = objectForId('album',$it->{'itemid'});
					displayAsHTML('album',$it,$track);
				}

			}
			if(defined($it->{'itemtype'})) {
				if($it->{'itemtype'} eq "track") {
					$it->{'attributes'} = sprintf('&%s=%d', getLinkAttribute('track'),$it->{'itemid'});
				}elsif($it->{'itemtype'} eq "album") {
					$it->{'attributes'} = sprintf('&%s=%d', getLinkAttribute('album'),$it->{'itemid'});
				}elsif($it->{'itemtype'} eq "artist") {
					$it->{'attributes'} = sprintf('&%s=%d', getLinkAttribute('artist'),$it->{'itemid'});
				}elsif($it->{'itemtype'} eq "year") {
					$it->{'attributes'} = sprintf('&%s=%d', getLinkAttribute('year'),$it->{'itemid'});
				}elsif($it->{'itemtype'} eq "genre") {
					$it->{'attributes'} = sprintf('&%s=%d', getLinkAttribute('genre'),$it->{'itemid'});
				}elsif($it->{'itemtype'} eq "playlist") {
					$it->{'attributes'} = sprintf('&%s=%d', getLinkAttribute('playlist'),$it->{'itemid'});
				}
			}
			if(defined($it->{'externalurl'}) || defined($it->{'url'})) {
				push @resultItems, $it;
			}
		}
		$result{'items'} = \@resultItems;
	}else {
		my @resultItems = ();
		$result{'items'} = \@resultItems;
		my %pagebar = ();
		$result{'pageinfo'}=\%pagebar;
		$result{'pageinfo'}->{'totalitems'} = 0;
		my $itemsPerPage = Slim::Utils::Prefs::get('itemsPerPage');
		$result{'pageinfo'}->{'itemsperpage'} = $itemsPerPage;
		$result{'pageinfo'}->{'currentpage'} = 0;
		$result{'pageinfo'}->{'totalpages'} = 0;
		$result{'pageinfo'}->{'enditem'} = 0;
		$result{'pageinfo'}->{'startitem'} = 0;
	}
	return \%result;
}

sub displayAsHTML {
        my $type = shift;
        my $form = shift;
        my $item = shift;

        if ($::VERSION ge '6.5' && $::REVISION ge '7505') {
                $item->displayAsHTML($form);
        }else {
                my $ds = Plugins::TrackStat::Storage::getCurrentDS();
                my $fieldInfo = Slim::DataStores::Base->fieldInfo;
	        my $levelInfo = $fieldInfo->{$type};
        	&{$levelInfo->{'listItem'}}($ds, $form, $item);
        }
}


sub getContext {
	my $client = shift;
	my $params = shift;
	my $currentItems = shift;
	my $level = shift;
	my @result = ();
	if(defined($params->{'hierarchy'})) {
		my $groupsstring = unescape($params->{'hierarchy'});
		my @groups = (split /,/, $groupsstring);
		my $group = $groups[$level];
		my $item = undef;
		foreach my $menuKey (keys %$currentItems) {
			my $menu = $currentItems->{$menuKey};
			if($menu->{'id'} eq $group) {
				$item = $menu;
			}
		}
		if(defined($item)) {
			my $currentUrl = escape($group);
			my $currentValue;
			if(defined($params->{$group})) {
				$currentValue = escape($params->{$group});
			}else {
				$currentValue = escape($group);
			}
			my %parameters = ();
			$parameters{$currentUrl} = $params->{$group};
			my $name;
			if(defined($item->{'menuname'})) {
				$name = $item->{'menuname'};
			}else {
				$name = $item->{'id'};
			}
			my %resultItem = (
				'url' => '&hierarchy='.$currentUrl,
				'valueUrl' => '&'.$currentUrl.'='.$currentValue,
				'parameters' => \%parameters,
				'name' => $name,
				'item' => $item
			);
			push @result, \%resultItem;

			if(defined($item->{'menu'})) {
				my $childResult = getSubContext($client,$params,\@groups,$item->{'menu'},$level+1);
				for my $child (@$childResult) {
					$child->{'url'} = '&hierarchy='.$currentUrl.','.$child->{'url'};
					$child->{'valueUrl'} = '&'.$currentUrl.'='.$currentValue.$child->{'valueUrl'};
					$child->{'parameters'}->{$currentUrl} = $params->{$group};
					push @result,$child;
				}
			}
		}
	}
	return \@result;
}

sub getSubContext {
	my $client = shift;
	my $params = shift;
	my $groups = shift;
	my $currentItems = shift;
	my $level = shift;
	my @result = ();
	if($groups && scalar(@$groups)>$level) {
		my $group = unescape(@$groups[$level]);
		my $item = undef;
		if(ref($currentItems) eq 'ARRAY') {
			for my $menu (@$currentItems) {
				if($menu->{'id'} eq $group) {
					$item = $menu;
				}
			}
		}else {
			if($currentItems->{'id'} eq $group) {
				$item = $currentItems;
			}
		}
		if(defined($item)) {
			my $currentUrl = escape($group);
			my $currentValue = escape($params->{$group});
			my %parameters = ();
			$parameters{$currentUrl} = $params->{$group};
			my $name;
			if(defined($item->{'menuname'})) {
				$name = $item->{'menuname'};
			}else {
				$name = $item->{'id'};
			}
			my %resultItem = (
				'url' => $currentUrl,
				'valueUrl' => '&'.$currentUrl.'='.$currentValue,
				'parameters' => \%parameters,
				'name' => $name,
				'item' => $item
			);
			push @result, \%resultItem;

			if(defined($item->{'menu'})) {
				my $childResult = getSubContext($client,$params,$groups,$item->{'menu'},$level+1);
				for my $child (@$childResult) {
					$child->{'url'} = $currentUrl.','.$child->{'url'};
					$child->{'valueUrl'} = '&'.$currentUrl.'='.$currentValue.$child->{'valueUrl'};
					$child->{'parameters'}->{$currentUrl} = $params->{$group};
					push @result,$child;
				}
			}
		}
	}
	return \@result;
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
		debugMsg("Defaulting plugin_custombrowse_showmessages to 0\n");
		Slim::Utils::Prefs::set('plugin_custombrowse_showmessages', 0);
	}

        $prefVal = Slim::Utils::Prefs::get('plugin_custombrowse_directory');
	if (! defined $prefVal) {
		my $dir=Slim::Utils::Prefs::get('playlistdir');
		debugMsg("Defaulting plugin_custombrowse_directory to:$dir\n");
		Slim::Utils::Prefs::set('plugin_custombrowse_directory', $dir);
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_custombrowse_properties');
	if (! $prefVal) {
		debugMsg("Defaulting plugin_custombrowse_properties\n");
		my @properties = ();
		push @properties, 'libraryDir='.Slim::Utils::Prefs::get('audiodir');
		push @properties, 'libraryAudioDirUrl='.Slim::Utils::Misc::fileURLFromPath(Slim::Utils::Prefs::get('audiodir'));
		Slim::Utils::Prefs::set('plugin_custombrowse_properties', \@properties);
	}
}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_custombrowse_directory','plugin_custombrowse_properties','plugin_custombrowse_showmessages'],
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
	plugin_custombrowse_properties => {
			'validate' => \&validateProperty
			,'isArray' => 1
			,'arrayAddExtra' => 1
			,'arrayDeleteNull' => 1
			,'arrayDeleteValue' => ''
			,'arrayBasicValue' => ''
			,'inputTemplate' => 'setup_input_array_txt.html'
			,'changeAddlText' => string('PLUGIN_CUSTOMBROWSE_PROPERTIES')
			,'PrefSize' => 'large'
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
	if(defined($value)) {
		if ($::VERSION ge '6.5') {
			readBrowseConfiguration();
			addWebMenus($value);
	        	Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_CUSTOMBROWSE' => $value });
		}else {
	        	Slim::Web::Pages::addLinks("browse", { 'PLUGIN_CUSTOMBROWSE' => $value });
		}
	}

        return (\%pages);
}

sub addWebMenus {
	my $value = shift;
        for my $menu (keys %$browseMenus) {
            if(!defined($browseMenus->{$menu}->{'value'})) {
            	$browseMenus->{$menu}->{'value'} = $browseMenus->{$menu}->{'id'};
            }
            my $name;
            if(defined($browseMenus->{$menu}->{'itemname'})) {
		$name = $browseMenus->{$menu}->{'itemname'};
            }else {
		$name = $browseMenus->{$menu}->{'menuname'};
            }
            if ( !Slim::Utils::Strings::stringExists($name) ) {
               	Slim::Utils::Strings::addStringPointer( uc $name, $name );
            }
            if($browseMenus->{$menu}->{'enabledbrowse'}) {
		if(defined($browseMenus->{$menu}->{'menu'}) && ref($browseMenus->{$menu}->{'menu'}) ne 'ARRAY' && $browseMenus->{$menu}->{'menu'}->{'menutype'} eq 'mode') {
			my $url;
			if(defined($browseMenus->{$menu}->{'menu'}->{'menuurl'})) {
				$url = $browseMenus->{$menu}->{'menu'}->{'menuurl'};
				$url = replaceParameters($url);
			}
			debugMsg("Adding menu: $name\n");
		        Slim::Web::Pages->addPageLinks("browse", { $name => $url });
		}else {
			debugMsg("Adding menu: $name\n");
		        Slim::Web::Pages->addPageLinks("browse", { $name => $value."?hierarchy=".escape($browseMenus->{$menu}->{'id'} )});
		}
            }else {
		debugMsg("Removing menu: $name\n");
		Slim::Web::Pages->addPageLinks("browse", {$name => undef});
            }
        }
}
# Draws the plugin's web page
sub handleWebList {
        my ($client, $params) = @_;

	if(!defined($params->{'hierarchy'})) {
		readBrowseConfiguration($client);
	}
	my $items = getPageItemsForContext($client,$params,$browseMenus);
	my $context = getContext($client,$params,$browseMenus,0);

	if($items->{'artwork'}) {
		$params->{'pluginCustomBrowseArtworkSupported'} = 1;
	}
	$params->{'pluginCustomBrowsePageInfo'} = $items->{'pageinfo'};
	$params->{'pluginCustomBrowseItems'} = $items->{'items'};
	$params->{'pluginCustomBrowseContext'} = $context;
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
                $params->{'pluginCustomBrowseSlimserver65'} = 1;
        }

        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_selectmenus.html', $params);
}

# Draws the plugin's web page
sub handleWebSaveSelectMenus {
        my ($client, $params) = @_;

	readBrowseConfiguration($client);
        foreach my $menu (keys %$browseMenus) {
                my $menuid = "menu_".escape($browseMenus->{$menu}->{'id'});
                my $menubrowseid = "menubrowse_".escape($browseMenus->{$menu}->{'id'});
                if($params->{$menuid}) {
                        Slim::Utils::Prefs::set('plugin_custombrowse_'.$menuid.'_enabled',1);
			$browseMenus->{$menu}->{'enabled'}=1;
			if($params->{$menubrowseid}) {
                	        Slim::Utils::Prefs::set('plugin_custombrowse_'.$menubrowseid.'_enabled',1);
				$browseMenus->{$menu}->{'enabledbrowse'}=1;
	                }else {
        			Slim::Utils::Prefs::set('plugin_custombrowse_'.$menubrowseid.'_enabled',0);
				$browseMenus->{$menu}->{'enabledbrowse'}=0;
                	}
                }else {
                        Slim::Utils::Prefs::set('plugin_custombrowse_'.$menuid.'_enabled',0);
			$browseMenus->{$menu}->{'enabled'}=0;
			$browseMenus->{$menu}->{'enabledbrowse'}=0;
                }
        }
        my $value = 'plugins/CustomBrowse/custombrowse_list.html';
        if (grep { /^CustomBrowse::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {
                $value = undef;
        }
	if ($::VERSION ge '6.5') {
		addWebMenus($value);
	}
	addPlayerMenus();
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
		if(defined($xml->{'menu'}) && defined($xml->{'menu'}->{'id'})) {
			my $enabled = Slim::Utils::Prefs::get('plugin_custombrowse_menu_'.escape($xml->{'menu'}->{'id'}).'_enabled');
			if(defined($enabled) && !$enabled) {
				$disabled = 1;
			}elsif(!defined($enabled)) {
				if(defined($xml->{'defaultdisabled'}) && $xml->{'defaultdisabled'}) {
					$disabled = 1;
				}
			}
		}
		my $disabledBrowse = 1;
		if(defined($xml->{'menu'}) && defined($xml->{'menu'}->{'id'})) {
			my $enabled = Slim::Utils::Prefs::get('plugin_custombrowse_menubrowse_'.escape($xml->{'menu'}->{'id'}).'_enabled');
			if(defined($enabled) && $enabled) {
				$disabledBrowse = 0;
			}elsif(!defined($enabled)) {
				if(defined($xml->{'defaultenabledbrowse'}) && $xml->{'defaultenabledbrowse'}) {
					$disabledBrowse = 0;
				}
			}
		}
		
		if($include && !$disabled) {
			$xml->{'menu'}->{'enabled'}=1;
			if($disabledBrowse) {
				$xml->{'menu'}->{'enabledbrowse'}=0;
			}else {
				$xml->{'menu'}->{'enabledbrowse'}=1;
			}
	                $localBrowseMenus->{$item} = $xml->{'menu'};
		}elsif($include && $disabled) {
			$xml->{'menu'}->{'enabled'}=0;
			$xml->{'menu'}->{'enabledbrowse'}=0;
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

sub validateProperty {
	my $arg = shift;
	if($arg eq '' || $arg =~ /^[a-zA-Z0-9]+\s*=\s*.+$/) {
		return $arg;
	}else {
		return undef;
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

PLUGIN_CUSTOMBROWSE_PROPERTIES
	EN	Properties to use in queries and menus

SETUP_PLUGIN_CUSTOMBROWSE_SHOWMESSAGES
	EN	Debugging

SETUP_PLUGIN_CUSTOMBROWSE_PROPERTIES
	EN	Properties to use in queries and menus

PLUGIN_CUSTOMBROWSE_DIRECTORY
	EN	Browse configuration directory

SETUP_PLUGIN_CUSTOMBROWSE_DIRECTORY
	EN	Browse configuration directory

PLUGIN_CUSTOMBROWSE_SELECT_MENUS
	EN	Enable/Disable menus

PLUGIN_CUSTOMBROWSE_SELECT_MENUS_TITLE
	EN	Select enabled menus

PLUGIN_CUSTOMBROWSE_SELECT_MENUS_BROWSE_TITLE
	EN	Show in<br>browse menu

PLUGIN_CUSTOMBROWSE_SELECT_MENUS_NONE
	EN	No Menus

PLUGIN_CUSTOMBROWSE_SELECT_MENUS_ALL
	EN	All Menus

EOF

}

1;

__END__
