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
use HTML::Entities;
use Scalar::Util qw(blessed);

use Plugins::CustomBrowse::ConfigManager::Main;

my $driver;
my $browseMenus;
my $browseMenusFlat;
my $browseMixes;
my $templates;
my $mixer;
my $PLUGINVERSION = '1.20';
my $sqlerrors = '';
my %uPNPCache = ();

my $configManager = undef;

my $supportDownloadError = undef;

sub getDisplayName {
	my $menuName = Slim::Utils::Prefs::get('plugin_custombrowse_menuname');
	if($menuName) {
		Slim::Utils::Strings::addStringPointer( uc 'PLUGIN_CUSTOMBROWSE', $menuName );
	}
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
        'pause' => 'passback',
	'0.hold' => 'saveRating_0',
	'1.hold' => 'saveRating_1',
	'2.hold' => 'saveRating_2',
	'3.hold' => 'saveRating_3',
	'4.hold' => 'saveRating_4',
	'5.hold' => 'saveRating_5',
	'6.hold' => 'saveRating_6',
	'7.hold' => 'saveRating_7',
	'8.hold' => 'saveRating_8',
	'9.hold' => 'saveRating_9',
	'0.single' => 'numberScroll_0',
	'1.single' => 'numberScroll_1',
	'2.single' => 'numberScroll_2',
	'3.single' => 'numberScroll_3',
	'4.single' => 'numberScroll_4',
	'5.single' => 'numberScroll_5',
	'6.single' => 'numberScroll_6',
	'7.single' => 'numberScroll_7',
	'8.single' => 'numberScroll_8',
	'9.single' => 'numberScroll_9',
	'0' => 'dead',
	'1' => 'dead',
	'2' => 'dead',
	'3' => 'dead',
	'4' => 'dead',
	'5' => 'dead',
	'6' => 'dead',
	'7' => 'dead',
	'8' => 'dead',
	'9' => 'dead'
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
            if(defined($name) && $name =~ /{.*}/) {
		$name = replaceParameters($client,$name,$item->{'parameters'});
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
	my $mixes = getMixes($client,$item);
	if(scalar(@$mixes)>0) {
		$playable = Slim::Display::Display::symbol('mixable');
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
        #readBrowseConfiguration($client);
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
sub isMenuEnabledForClient {
	my $client = shift;
	my $menu = shift;
	
	if(defined($menu->{'includedclients'})) {
		if(defined($client)) {
			my @clients = split(/,/,$menu->{'includedclients'});
			for my $clientName (@clients) {
				if($client->name eq $clientName) {
					return 1;
				}
			}
		}
		return 0;
	}elsif(defined($menu->{'excludedclients'})) {
		if(defined($client)) {
			my @clients = split(/,/,$menu->{'excludedclients'});
			for my $clientName (@clients) {
				if($client->name eq $clientName) {
					return 0;
				}
			}
		}
		return 1;
	}else {
		return 1;
	}
}

sub isMenuEnabledForCheck {
	my $client = shift;
	my $menu = shift;
	
	if(defined($menu->{'enabledcheck'})) {
		my @checkItems = ();
		my $items = $menu->{'enabledcheck'}->{'item'};
		if(ref($items) eq 'ARRAY') {
			@checkItems = @$items;
		}else {
			push @checkItems,$items;
		}
		for my $item (@checkItems) {
			my $type = $item->{'type'};
			my $data = $item->{'data'};
			if($type eq 'function') {
				my @params = split(/\|/,$data);
				if(scalar(@params)>=2) {
					my $object = @params->[0];
					my $function = @params->[1];
					if(UNIVERSAL::can($object,$function)) {
						my %callParams = ();
						my $i = 0;
						for my $keyvalue (@params) {
							if($i>=2) {
								if($keyvalue =~ /^([^=].*?)=(.*)/) {
									my $name=$1;
									my $value=$2;
									$callParams{$name}=$value;
								}
							}
							$i = $i + 1;
						}
						debugMsg("Checking menu enabled with: $function\n");
						no strict 'refs';
						my $result = eval { &{$object.'::'.$function}($client,\%callParams) };
						if( $@ ) {
						    warn "Function call error: $@\n";
						}		
						use strict 'refs';
						if(!$result) {
							return 0;
						}
					}
				}
			}
		}
	}
	return 1;
}

sub isMenuEnabledForLibrary {
	my $client = shift;
	my $menu = shift;
	
	my $library = undef;
	if(defined($client)) {
		$library = $client->prefGet('plugin_multilibrary_activelibraryno');
	}
	if(defined($menu->{'includedlibraries'})) {
		if(defined($library)) {
			my @libraries = split(/,/,$menu->{'includedlibraries'});
			for my $libraryName (@libraries) {
				if($library eq $libraryName) {
					return 1;
				}
			}
		}
		return 0;
	}elsif(defined($menu->{'excludedlibraries'})) {
		if(defined($library)) {
			my @libraries = split(/,/,$menu->{'excludedlibraries'});
			for my $libraryName (@libraries) {
				if($library eq $libraryName) {
					return 0;
				}
			}
		}
		return 1;
	}else {
		return 1;
	}
}

sub getMenuItems {
    my $client = shift;
    my $item = shift;
    my $option = shift;
    my $mainBrowseMenu = shift;

    my @listRef = ();

    if(!defined($item)) {
        for my $menu (keys %$browseMenus) {
            if(!defined($browseMenus->{$menu}->{'value'})) {
            	$browseMenus->{$menu}->{'value'} = $browseMenus->{$menu}->{'id'};
            }
            if($browseMenus->{$menu}->{'enabled'}) {
                    if(isMenuEnabledForClient($client,$browseMenus->{$menu}) && isMenuEnabledForLibrary($client,$browseMenus->{$menu}) && isMenuEnabledForCheck($client,$browseMenus->{$menu})) {
		            push @listRef,$browseMenus->{$menu};
                    }		
            }
        }
	sortMenu(\@listRef);
    }elsif(defined($item->{'menu'})) {
	my @menus = ();
	if(ref($item->{'menu'}) eq 'ARRAY') {
		foreach my $it (@{$item->{'menu'}}) {
			if(isMenuEnabledForClient($client,$it) && isMenuEnabledForLibrary($client,$it) && isMenuEnabledForCheck($client,$it)) {
				push @menus,$it;
			}
		}
	}else {
		if(isMenuEnabledForClient($client,$item->{'menu'}) && isMenuEnabledForLibrary($client,$item->{'menu'}) && isMenuEnabledForCheck($client,$item->{'menu'})) {
			push @menus,$item->{'menu'};
		}
	}
	foreach my $menu (@menus) {
		if($menu->{'topmenu'} && ((defined($client) && $client->param('mainBrowseMenu')) || $mainBrowseMenu)) {
			if(!$menu->{'enabledbrowse'}) {
				next;
			}
		}
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
                    my $menudata = undef;
                    my $optionKeywords = undef;			
		    if(defined($menu->{'option'})) {
			if(ref($menu->{'option'}) eq 'ARRAY') {
				my $foundOption = 0;
				if(defined($option)) {
					my $options = $menu->{'option'};
					foreach my $op (@$options) {
						if(defined($op->{'id'}) && $op->{'id'} eq $option) {
							$menudata = $op->{'menudata'};
							$optionKeywords = getKeywords($op);
							$foundOption = 1;
							last;
						}
					}
				}
				if(!defined($menudata)) {
					my $options = $menu->{'option'};
					if(!$foundOption && defined($options->[0]->{'menudata'})) {
						$menudata = $options->[0]->{'menudata'};
					}else {
						$menudata = $menu->{'menudata'};
					}
					if(!$foundOption && defined($options->[0]->{'keyword'})) {
						$optionKeywords = getKeywords($options->[0]);
					}
				}
			}else {
				if(defined($menu->{'option'}->{'menudata'})) {
					$menudata = $menu->{'option'}->{'menudata'};
					$optionKeywords = getKeywords($menu->{'option'});
				}else {
					$menudata = $menu->{'menudata'};
				}
			}
                    }else {
			$menudata = $menu->{'menudata'};
		    }
                    my $keywords = combineKeywords($menu->{'keywordparameters'},$optionKeywords,$item->{'parameters'});
	            my $sql = prepareMenuSQL($client,$menudata,$keywords);
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
                    my $keywords = combineKeywords($menu->{'keywordparameters'},undef,$item->{'parameters'});
		    my @params = split(/\|/,$menu->{'menudata'});
		    my $mode = shift(@params);
		    my %modeParameters = ();
		    foreach my $keyvalue (@params) {
		    	if($keyvalue =~ /^([^=].*?)=(.*)/) {
				my $name=$1;
				my $value=$2;
				if($name =~ /^([^\.].*?)\.(.*)/) {
					if(!defined($modeParameters{$1})) {
						my %hash = ();
						$modeParameters{$1}=\%hash;
					}
					$modeParameters{$1}->{$2}=replaceParameters($client,$value,$keywords);
				}else {
					$modeParameters{$name} = replaceParameters($client,$value, $keywords);
				}
			}
		    }
	            my %params = (
	            	'useMode' => $mode,
	            	'parameters' => \%modeParameters
	            );
	            return \%params;		
	        }elsif($menu->{'menutype'} eq 'folder') {
	            my $dir = $menu->{'menudata'};
                    my $keywords = combineKeywords($menu->{'keywordparameters'},undef,$item->{'parameters'});
	            $dir = replaceParameters($client,$dir,$keywords);
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
					$subdir = unescape($tmp);
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

sub getKeywords {
	my $menu = shift;
	
	if(defined($menu->{'keyword'})) {
		my %keywords = ();
		if(ref($menu->{'keyword'}) eq 'ARRAY') {
			my $keywordItems = $menu->{'keyword'};
			foreach my $keyword (@$keywordItems) {
				$keywords{$keyword->{'name'}} = $keyword->{'value'};
			}
		}else {
			$keywords{$menu->{'keyword'}->{'name'}} = $menu->{'keyword'}->{'value'};
		}
		return \%keywords;
	}
	return undef;
}

sub combineKeywords {
	my $parentKeywords = shift;
	my $optionKeywords = shift;
	my $selectionKeywords = shift;

	my %keywords = ();
	if(defined($parentKeywords)) {
		foreach my $keyword (keys %$parentKeywords) {
			$keywords{$keyword} = $parentKeywords->{$keyword};
		}
	}
	if(defined($optionKeywords)) {
		foreach my $keyword (keys %$optionKeywords) {
			$keywords{$keyword} = $optionKeywords->{$keyword};
		}
	}
	if(defined($selectionKeywords)) {
		foreach my $keyword (keys %$selectionKeywords) {
			$keywords{$keyword} = $selectionKeywords->{$keyword};
		}
	}
	return \%keywords;
}
sub copyKeywords {
	my $parent = shift;
	my $menu = shift;
	my @menus = ();
	if(ref($menu) eq 'ARRAY') {
		foreach my $item (@$menu) {
			push @menus, $item;
		}
	}else {
		push @menus,$menu;
	}

	foreach my $menuItem (@menus) {
		my %keywords = ();
		my $foundKeyword = 0;
		if(defined($parent->{'keywordparameters'})) {

			my $parameters = $parent->{'keywordparameters'};
			foreach my $key (keys %$parameters) {
				$keywords{$key} = $parameters->{$key};
				$foundKeyword = 1;
			}
		}
		if(defined($menuItem->{'keyword'})) {
			if(ref($menuItem->{'keyword'}) eq 'ARRAY') {
				my $keywordArray = $menuItem->{'keyword'};
				foreach my $keyword (@$keywordArray) {
					$keywords{$keyword->{'name'}} = $keyword->{'value'};
					$foundKeyword = 1;
				}
			}else {
				$keywords{$menuItem->{'keyword'}->{'name'}} = $menuItem->{'keyword'}->{'value'};
				$foundKeyword = 1;
			}
		}
		if($foundKeyword) {
			$menuItem->{'keywordparameters'} = \%keywords;
		}
		if(defined($menuItem->{'menu'})) {
			copyKeywords($menuItem,$menuItem->{'menu'});
		}
	}
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
    my $items = getMenuItems($client,$item);
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
	if(defined($menuTitle) && $menuTitle =~ /{.*}/) {
		$menuTitle = replaceParameters($client,$menuTitle,$item->{'parameters'});
	}
    }

    my $sorted = '0';
    if(!defined($item)) {
	$sorted = 'L';
    }else {
	if(defined($item->{'menu'}) && ref($item->{'menu'}) eq 'ARRAY') {
		my $menuArray = $item->{'menu'};
		for my $it (@$menuArray) {
			my $menulinks = getMenuLinks($it);
			if(defined($menulinks) && $menulinks eq 'alpha') {
				$sorted = 'L';
				last;
			}
		}
	}elsif(defined($item->{'menu'})) {
		my $menulinks = getMenuLinks($item->{'menu'});
		if(defined($menulinks) && $menulinks eq 'alpha') {
			$sorted = 'L';
		}
	}
    }
    # use PLUGIN.CustomBrowse.Choice to display the list of feeds
    my %params = (
            header     => $menuTitle.' {count}',
            listRef    => \@listRef,
            mainBrowseMenu => $client->param('mainBrowseMenu'),
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
            parentMode => Slim::Buttons::Common::param($client,'parentMode'),
            onCreateMix     => sub {
                    my ($client, $item) = @_;
                    createMix($client, $item);
            },				
            onInsert     => sub {
                    my ($client, $item) = @_;
                    playAddItem($client,Slim::Buttons::Common::param($client, 'listRef'),$item,'inserttracks','INSERT_TO_PLAYLIST');
            },				
            onPlay     => sub {
                    my ($client, $item) = @_;
                    my $string;		
                    if (Slim::Player::Playlist::shuffle($client)) {
                    	$string = 'PLAYING_RANDOMLY_FROM';
                    } else {
                    	$string = 'NOW_PLAYING_FROM';
                    }
                    playAddItem($client,Slim::Buttons::Common::param($client, 'listRef'),$item,'loadtracks',$string);
            },
            onAdd      => sub {
                    my ($client, $item) = @_;
                    playAddItem($client,Slim::Buttons::Common::param($client, 'listRef'),$item,'addtracks','ADDING_TO_PLAYLIST');
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

sub checkMix {
	my ($client, $mix, $item, $web) = @_;

	if(defined($web) && $web && $mix->{'mixtype'} eq 'menu') {
		return 0;
	}
	if(defined($mix->{'mixchecktype'})) {
		if($mix->{'mixchecktype'} eq 'sql') {
			my $mixcheckdata = undef;
			if(defined($mix->{'mixcheckdata'})) {
				$mixcheckdata = $mix->{'mixcheckdata'};
			}else {
				$mixcheckdata = $mix->{'mixdata'};
			}
			my $parameters = getCustomBrowseProperties();
			$parameters->{'itemid'} = $item->{'itemid'};
			$parameters->{'itemname'} = $item->{'itemname'};
			my $keywords = combineKeywords($item->{'keywordparameters'},$item->{'parameters'},$parameters);
			
			my $sql = prepareMenuSQL($client,$mixcheckdata,$keywords);
			my $sqlItems = getSQLMenuData($sql);
			if($sqlItems && scalar(@$sqlItems)>0) {
				return 1;
			}
			
		}elsif($mix->{'mixchecktype'} eq 'function') {
			if($mix->{'mixcheckdata'} =~ /^(.+)::([^:].*)$/) {
				my $class = $1;
				my $function = $2;
				my $itemObj = undef;
				my $itemObj = undef;
				if($item->{'itemtype'} eq "track") {
					$itemObj = objectForId('track',$item->{'itemid'});
				}elsif($item->{'itemtype'} eq "album") {
					$itemObj = objectForId('album',$item->{'itemid'});
				}elsif($item->{'itemtype'} eq "artist") {
					$itemObj = objectForId('artist',$item->{'itemid'});
				}elsif($item->{'itemtype'} eq "year") {
					$itemObj = objectForId('year',$item->{'itemid'});
				}elsif($item->{'itemtype'} eq "genre") {
					$itemObj = objectForId('genre',$item->{'itemid'});
				}elsif($item->{'itemtype'} eq "playlist") {
					$itemObj = objectForId('playlist',$item->{'itemid'});
				}

				if(defined($itemObj)) {
					if(UNIVERSAL::can("$class","$function")) {
						debugMsg("Calling ${class}->${function}\n");
						no strict 'refs';
						my $enabled = eval { $class->$function($itemObj) };
						if ($@) {
							debugMsg("Error calling ${class}->${function}: $@\n");
						}
						use strict 'refs';
						if($enabled) {
							return 1;
						}
					}else {
						debugMsg("Function ${class}->${function} does not exist\n");
					}
				}
			}
		}
	}else {
		return 1;
	}
	return 0;
}

sub getMixes {
	my $client = shift;
	my $item = shift;
	my $web = shift;

	my @mixes = ();
	if(defined($item->{'mix'})) {
		if(ref($item->{'mix'}) eq 'ARRAY') {
			my $customMixes = $item->{'mix'};
			for my $mix (@$customMixes) {
				if(defined($mix->{'mixtype'}) && defined($mix->{'mixdata'})) {
					if($mix->{'mixtype'} eq 'allforcategory') {
						foreach my $key (keys %$browseMixes) {
							my $globalMix = $browseMixes->{$key};
							if($globalMix->{'enabled'} && $globalMix->{'mixcategory'} eq $mix->{'mixdata'}) {
								if(checkMix($client, $globalMix, $item, $web)) {
									push @mixes,$globalMix;
								}
							}
						}
					}elsif(defined($mix->{'mixname'}))  {
						if(checkMix($client, $mix, $item,$web)) {
							push @mixes,$mix;
						}
					}
				}
			}
		}else {
			my $mix = $item->{'mix'};
			if(defined($mix->{'mixtype'}) && defined($mix->{'mixdata'})) {
				if($mix->{'mixtype'} eq 'allforcategory') {
					foreach my $key (keys %$browseMixes) {
						my $globalMix = $browseMixes->{$key};
						if($globalMix->{'enabled'} && $globalMix->{'mixcategory'} eq $mix->{'mixdata'}) {
							if(checkMix($client, $globalMix, $item,$web)) {
								push @mixes,$globalMix;
							}
						}
					}
				}elsif(defined($mix->{'mixname'}))  {
					if(checkMix($client, $mix, $item,$web)) {
						push @mixes,$mix;
					}
				}
			}
		}
	}elsif(defined($item->{'itemtype'})) {
		foreach my $key (keys %$browseMixes) {
			my $mix = $browseMixes->{$key};
			if($mix->{'enabled'} && $mix->{'mixcategory'} eq $item->{'itemtype'}) {
				if(checkMix($client, $mix, $item,$web)) {
					push @mixes,$mix;
				}
			}
		}
	}
	@mixes = sort { $a->{'mixname'} cmp $b->{'mixname'} } @mixes;
	return \@mixes;
}

sub createMix {
	my ($client,$item) = @_;
	my $mixes = getMixes($client,$item);
	for my $mix (@$mixes) {
		debugMsg("Got mix: ".$mix->{'mixname'}."\n");
	}
	if(scalar(@$mixes)==1) {
		executeMix($client,$mixes->[0],undef,$item);
	}elsif(scalar(@$mixes)>0) {
		my $params = {
			'header'     => string('CREATE_MIX').' {count}',
			'listRef'    => $mixes,
			'name'       => sub { return $_[1]->{'mixname'} },
			'overlayRef' => sub { return [undef, Slim::Display::Display::symbol('rightarrow')] },
			'item'       => $item,
			'onPlay'     => sub { 
						my ($client,$item) = @_;
						executeMix($client,$item);
					},
			'onAdd'      => sub { 
						my ($client,$item) = @_;
						executeMix($client,$item,1);
					},
			'onRight'    => sub { 
						my ($client,$item) = @_;
						executeMix($client,$item,0);
					}
		};
	
		Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', $params);
	}else {
		debugMsg("No mixes configured for this item\n");
	}
}

sub executeMix {
        my ($client, $mixer, $addOnly,$item, $web) = @_;

	if(!defined($item)) {
		$item = $client->param('item');
	}
	debugMsg("Creating mixer ".$mixer->{'mixname'}." for ".$item->{'itemname'}."\n");

	my $parameters = getCustomBrowseProperties();
	$parameters->{'itemid'} = $item->{'itemid'};
	$parameters->{'itemname'} = $item->{'itemname'};
	my $keywords = combineKeywords($item->{'keywordparameters'},$item->{'parameters'},$parameters);

	if($mixer->{'mixtype'} eq 'sql') {
		my %playItem = (
			'playtype' => 'sql',
			'playdata' => $mixer->{'mixdata'},
			'itemname' => $mixer->{'mixname'},
			'parameters' => $keywords
		);
		my $command = 'loadtracks';
		if($addOnly) {
			$command = 'addtracks';
		}
		playAddItem($client,undef,\%playItem,$command);
		if(!$web) {
			Slim::Buttons::Common::popModeRight($client);
		}
	}elsif($mixer->{'mixtype'} eq 'mode' && !$web) {
		my @params = split(/\|/,$mixer->{'mixdata'});
		my $mode = shift(@params);
		my %modeParameters = ();
		foreach my $keyvalue (@params) {
			if($keyvalue =~ /^([^=].*?)=(.*)/) {
				my $name=$1;
				my $value=$2;
				if($name =~ /^([^\.].*?)\.(.*)/) {
					if(!defined($modeParameters{$1})) {
						my %hash = ();
						$modeParameters{$1}=\%hash;
					}
					$modeParameters{$1}->{$2}=replaceParameters($client,$value,$keywords);
				}else {
					$modeParameters{$name} = replaceParameters($client,$value,$keywords);
				}
			}
		}
		Slim::Buttons::Common::pushModeLeft($client, $mode, \%modeParameters);
	}elsif($mixer->{'mixtype'} eq 'menu') {
		my $mixdata = $mixer->{'mixdata'};
		$mixdata->{'parameters'} = $parameters;
		my $keywords = $mixdata->{'keyword'};
		my @keywordArray = ();
		if(defined($keywords) && ref($keywords) eq 'ARRAY') {
			@keywordArray = @$keywords;
		}elsif(defined($keywords)) {
			push @keywordArray,$keywords;
		}
		for my $keyword (@keywordArray) {
			$mixdata->{'parameters'}->{$keyword->{'name'}} = replaceParameters($client,$keyword->{'value'},$parameters);
		}
		$mixdata->{'value'} = $mixer->{'id'};
		if(!defined($mixdata->{'menu'}->{'id'})) {
			$mixdata->{'menu'}->{'id'} = $mixer->{'id'};
		}
		my $modeParameters = getMenu($client,$mixdata);
		if(defined($modeParameters)) {
			if(defined($modeParameters->{'useMode'})) {
				Slim::Buttons::Common::pushModeLeft($client, $modeParameters->{'useMode'}, $modeParameters->{'parameters'});
			}else {
				Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.CustomBrowse.Choice', $modeParameters);
			}
		}else {
	        	$client->bumpRight();
		}
	}elsif($mixer->{'mixtype'} eq 'function') {
		if($mixer->{'mixdata'} =~ /^(.+)::([^:].*)$/) {
			my $class = $1;
			my $function = $2;
			my $itemObj = undef;
			my $itemObj = undef;
			if($item->{'itemtype'} eq "track") {
				$itemObj = objectForId('track',$item->{'itemid'});
			}elsif($item->{'itemtype'} eq "album") {
				$itemObj = objectForId('album',$item->{'itemid'});
			}elsif($item->{'itemtype'} eq "artist") {
				$itemObj = objectForId('artist',$item->{'itemid'});
			}elsif($item->{'itemtype'} eq "year") {
				$itemObj = objectForId('year',$item->{'itemid'});
			}elsif($item->{'itemtype'} eq "genre") {
				$itemObj = objectForId('genre',$item->{'itemid'});
			}elsif($item->{'itemtype'} eq "playlist") {
				$itemObj = objectForId('playlist',$item->{'itemid'});
			}
			if(defined($itemObj)) {
				if(UNIVERSAL::can("$class","$function")) {
					debugMsg("Calling ${class}::${function}\n");
					no strict 'refs';
					eval { &{"${class}::${function}"}($client,$itemObj,$addOnly,$web) };
					if ($@) {
						debugMsg("Error calling ${class}::${function}: $@\n");
					}
					use strict 'refs';
				}else {
					debugMsg("Function ${class}::${function} does not exist\n");
				}
			}else {
				debugMsg("Item for itemtype ".$item->{'itemtype'}." could not be found\n");
			}
		}
	}
}

sub musicMagicMixable {
	my $class = shift;
	my $item  = shift;

	if(Slim::Utils::Prefs::get('musicmagic')) {
		if(UNIVERSAL::can("Plugins::MusicMagic::Plugin","mixable")) {
			debugMsg("Calling Plugins::MusicMagic::Plugin->mixable\n");
			my $enabled = eval { Plugins::MusicMagic::Plugin->mixable($item) };
			if ($@) {
				debugMsg("Error calling Plugins::MusicMagic::Plugin->mixable: $@\n");
			}
			if($enabled) {
				return 1;
			}
		}
	}
}

sub musicMagicMix {
	my $client = shift;
	my $item = shift;
	my $addOnly = shift;
	my $web = shift;

	my $trackUrls = undef;
	if(ref($item) eq 'Slim::Schema::Album') {
		my $trackObj = $item->tracks->next;
		if($trackObj) {
			$trackUrls = eval { Plugins::MusicMagic::Plugin::getMix($client,$trackObj->path,'album') };
		}
	}elsif(ref($item) eq 'Slim::Schema::Track') {
		$trackUrls = eval { Plugins::MusicMagic::Plugin::getMix($client,$item->path,'track') };
	}elsif(ref($item) eq 'Slim::Schema::Contributor') {
		$trackUrls = eval { Plugins::MusicMagic::Plugin::getMix($client,$item->name,'artist') };
	}elsif(ref($item) eq 'Slim::Schema::Genre') {
		$trackUrls = eval { Plugins::MusicMagic::Plugin::getMix($client,$item->name,'genre') };
	}elsif(ref($item) eq 'Slim::Schema::Year') {
		$trackUrls = eval { Plugins::MusicMagic::Plugin::getMix($client,$item->id,'year') };
	}
	if ($@) {
		debugMsg("Error calling MusicMagic plugin: $@\n");
	}
	if($trackUrls && scalar(@$trackUrls)>0) {
		debugMsg("Got mix with ".scalar(@$trackUrls)." tracks\n");
		my %playItem = (
			'playtype' => 'all',
			'itemname' => $mixer->{'mixname'}
		);
		my $command = 'loadtracks';
		if($addOnly) {
			$command = 'addtracks';
		}
		my @tracks = Slim::Schema->rs('Track')->search({ 'url' => $trackUrls });

		my @trackItems = ();
		for my $track (@tracks) {
			my %trackItem = (
				'itemid' => $track->id,
				'itemurl' => $track->url,
				'itemname' => $track->title,
				'itemtype' => 'track'
			);
			push @trackItems,\%trackItem;
		}
		playAddItem($client,\@trackItems,\%playItem,$command);
		if(!$web) {
			Slim::Buttons::Common::popModeRight($client);
		}
	}else {
		if(!$web) {
			my $line2 = $client->doubleString('PLUGIN_CUSTOMBROWSE_MIX_NOTRACKS');
			$client->showBriefly({
				'line'    => [ undef, $line2 ],
				'overlay' => [ undef, $client->symbols('notesymbol') ],
			});
		}
	}
}

sub playAddItem {
	my ($client,$listRef, $item, $command, $displayString, $subCall) = @_;
	my @items = ();
	if(!defined($item->{'playtype'})) {
		push @items,$item;
	}elsif($item->{'playtype'} eq 'all') {
		if(defined($listRef)) {
			@items = @$listRef;
		}else {
			push @items,$item;
		}
	}elsif($item->{'playtype'} eq 'sql') {
		if(defined($item->{'playdata'})) {
                    my $keywords = combineKeywords($item->{'keywordparameters'},undef,$item->{'parameters'});
	            my $sql = prepareMenuSQL($client,$item->{'playdata'},$keywords);
	            my $sqlItems = getSQLMenuData($sql);
		    foreach my $sqlItem (@$sqlItems) {
			my %addItem = (
				'itemtype' => 'track',
				'itemid' => $sqlItem->{'id'},
				'itemname' => $sqlItem->{'name'}
			);
			push @items, \%addItem;
		    }		
		}else {
			msg("CustomBrowse: ERROR, no playdata element found\n");
		}
	}
	my $request = undef;
	my $playedMultiple = undef;
	my $wasShuffled = undef;
	my $pos = undef;
	my $selectedPos = undef;
	my $postPlay = 0;
	if(!defined($subCall) && $command eq 'loadtracks') {
		$wasShuffled = Slim::Player::Playlist::shuffle($client);
		Slim::Player::Playlist::shuffle($client, 0);
		$request = $client->execute(['playlist', 'clear']);
		# indicate request source
		$request->source('PLUGIN_CUSTOMBROWSE');
		$pos = 0;
		$selectedPos = 0;
		$postPlay = 1;
		$command = 'addtracks';
	}
	foreach my $it (@items) {
		if(defined($it->{'itemtype'})) {
			if($it->{'itemtype'} eq "track") {
				debugMsg("Execute $command on ".$it->{'itemname'}."\n");
				$request = $client->execute(['playlist', $command, sprintf('%s=%d', getLinkAttribute('track'),$it->{'itemid'})]);
				if(defined($item->{'itemid'}) && $it->{'itemid'} eq $item->{'itemid'}) {
					$selectedPos = $pos;
				}
			}elsif($it->{'itemtype'} eq "album") {
				debugMsg("Execute $command on ".$it->{'itemname'}."\n");
				$request = $client->execute(['playlist', $command, sprintf('%s=%d', getLinkAttribute('album'),$it->{'itemid'})]);
			}elsif($it->{'itemtype'} eq "artist") {
				debugMsg("Execute $command on ".$it->{'itemname'}."\n");
				$request = $client->execute(['playlist', $command, sprintf('%s=%d', getLinkAttribute('artist'),$it->{'itemid'})]);
			}elsif($it->{'itemtype'} eq "year") {
				debugMsg("Execute $command on ".$it->{'itemname'}."\n");
				$request = $client->execute(['playlist', $command, sprintf('%s=%d', getLinkAttribute('year'),$it->{'itemid'})]);
			}elsif($it->{'itemtype'} eq "genre") {
				debugMsg("Execute $command on ".$it->{'itemname'}."\n");
				$request = $client->execute(['playlist', $command, sprintf('%s=%d', getLinkAttribute('genre'),$it->{'itemid'})]);
			}elsif($it->{'itemtype'} eq "playlist") {
				debugMsg("Execute $command on ".$it->{'itemname'}."\n");
				$request = $client->execute(['playlist', $command, sprintf('%s=%d', getLinkAttribute('playlist'),$it->{'itemid'})]);
			}else {
				my $subItems = getMenuItems($client,$it);
				if(ref($subItems) eq 'ARRAY') {
					for my $subitem (@$subItems) {
						playAddItem($client,$subItems,$subitem,$command,undef,1);
						if($command eq 'loadtracks') {
							$command = 'addtracks';
						}
						$playedMultiple = 1;
					}
				}
			}
			if (defined($request)) {
				# indicate request source
				$request->source('PLUGIN_CUSTOMBROWSE');
			}
		}else {
			my $subItems = getMenuItems($client,$it);
			if(ref($subItems) eq 'ARRAY') {
				for my $subitem (@$subItems) {
					playAddItem($client,$subItems,$subitem,$command,undef,1);
					if($command eq 'loadtracks') {
						$command = 'addtracks';
					}
					$playedMultiple = 1;
				}
			}
		}			
		if($command eq 'loadtracks') {
			$command = 'addtracks';
		}
		if(defined($pos)) {
			$pos = $pos + 1;
		}
	}
	if(defined($selectedPos)) {
		$request = $client->execute(['playlist', 'jump', $selectedPos]);
		if (defined($request)) {
			# indicate request source
			$request->source('PLUGIN_CUSTOMBROWSE');
		}
	}
	if (!defined($subCall) && $wasShuffled) {
        	$client->execute(["playlist", "shuffle", 1]);
        }
	if(($playedMultiple || defined($request)) && defined($displayString)) {
		my $line1;
		my $line2;

		if ($client->linesPerScreen == 1) {
			$line2 = $client->doubleString($displayString);
		} else {
			$line1 = $client->string($displayString);
			$line2 = $item->{'itemname'};
			if(!defined($line2)) {
				$line2 = $item->{'menuname'};
			}
		}
		$client->showBriefly({
			'line'    => [ $line1, $line2 ],
			'overlay' => [ undef, $client->symbols('notesymbol') ],
		});
	}
}
sub prepareMenuSQL {
    my $client = shift;
    my $sql = shift;
    my $parameters = shift;
    
    debugMsg("Preparing SQL: $sql\n");
    $sql = replaceParameters($client,$sql,$parameters);

    return $sql;
}

sub replaceParameters {
    my $client = shift;
    my $originalValue = shift;
    my $parameters = shift;
    my $dbh = getCurrentDBH();

    if(defined($parameters)) {
        for my $param (keys %$parameters) {
            my $value = $dbh->quote($parameters->{$param});
	    $value = substr($value, 1, -1);
	    $value = Slim::Utils::Unicode::utf8on($value);
	    $value = Slim::Utils::Unicode::utf8encode_locale($value);
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
    while($originalValue =~ m/\{clientproperty\.(.*?)\}/) {
	my $propertyValue = undef;
	if(defined($client)) {
		$propertyValue = $client->prefGet($1);
	}
	if(defined($propertyValue)) {
		$propertyValue = $dbh->quote($propertyValue);
	    	$propertyValue = substr($propertyValue, 1, -1);
		$originalValue =~ s/\{clientproperty\.$1\}/$propertyValue/g;
	}else {
		$originalValue =~ s/\{clientproperty\..*?\}//g;
	}
    }

    return $originalValue;
}

sub getSQLMenuData {
	my $sqlstatements = shift;
	my @result =();
	my $dbh = getCurrentDBH();
	my $trackno = 0;
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

	        if ($sql =~ /^\(*SELECT+/oi) {
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
		    warn "Database error: $DBI::errstr\n$@\n";
		    addSQLError("Running: $sql got error: <br>".$DBI::errstr);
		}		
	}
	return \@result;
}


sub uPNPCallback {
	my $device = shift;
	my $event = shift;

	if($event eq 'add') {
		debugMsg("Adding uPNP ".$device->getfriendlyname."\n");
		$uPNPCache{$device->getudn} = $device;
	}else {
		debugMsg("Removing uPNP ".$device->getfriendlyname."\n");
		$uPNPCache{$device->getudn} = undef;
	}
}

sub getAvailableuPNPDevices {
	my @result = ();
	for my $key (keys %uPNPCache) {
		my $device = $uPNPCache{$key};
		my %item = (
			'id' => $device->getudn,
			'name' => $device->getfriendlyname,
			'value' => $device->getudn
		);
		push @result,\%item;
	}
	return \@result;
}

sub isuPNPDeviceAvailable {
	my $client = shift;
	my $params = shift;
	if(defined($params->{'device'})) {
		if(defined($uPNPCache{$params->{'device'}})) {
			return 1;
		}
	}
	return 0;
}

sub initPlugin {
	my $class = shift;
	
	checkDefaults();
	Slim::Utils::UPnPMediaServer::registerCallback( \&uPNPCallback );
	my $soapLiteError = 0;
	eval "use SOAP::Lite";
	if ($@) {
		my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
		for my $plugindir (@pluginDirs) {
			next unless -d catdir($plugindir,"CustomBrowse","libs");
			push @INC,catdir($plugindir,"CustomBrowse","libs");
			last;
		}
		debugMsg("Using internal implementation of SOAP::Lite\n");
		eval "use SOAP::Lite";
		if ($@) {
			$soapLiteError = 1;
			msg("CustomBrowse: ERROR! Cant load internal implementation of SOAP::Lite, download/publish functionallity will not be available\n");
		}
	}

	my %choiceFunctions =  %{Slim::Buttons::Input::Choice::getFunctions()};
	$choiceFunctions{'create_mix'} = sub {Slim::Buttons::Input::Choice::callCallback('onCreateMix', @_)};
	$choiceFunctions{'saveRating'} = sub {
		my $client = shift;
		my $button = shift;
		my $digit = shift;
		my $listIndex = Slim::Buttons::Common::param($client,'listIndex');
		my $listRef = Slim::Buttons::Common::param($client,'listRef');
		my $item  = $listRef->[$listIndex];
		my $trackStat;
		$trackStat = Slim::Utils::PluginManager::enabledPlugin('TrackStat',$client);

		if($trackStat && defined($item->{'itemtype'}) && $item->{'itemtype'} eq 'track' && (Slim::Utils::Prefs::get("plugin_trackstat_rating_10scale") || $digit<=5)) {
			my $rating = $digit*20;
			if(Slim::Utils::Prefs::get("plugin_trackstat_rating_10scale")) {
				$rating = $digit*10;
			}
			$rating .= '%';
			my $request = $client->execute(['trackstat', 'setrating', sprintf('%d', $item->{'itemid'}),$rating]);
			$request->source('PLUGIN_CUSTOMBROWSE');
			$client->showBriefly(
				$client->string( 'PLUGIN_CUSTOMBROWSE_TRACKSTAT'),
				$client->string( 'PLUGIN_CUSTOMBROWSE_TRACKSTAT_RATING').(' *' x $digit),
				3);
		}
		
	};
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

	my $templateDir = Slim::Utils::Prefs::get('plugin_custombrowse_template_directory');
	if(!defined($templateDir) || !-d $templateDir) {
		$supportDownloadError = 'You have to specify a template directory before you can download menus';
	}
	if(!defined($supportDownloadError) && $soapLiteError) {
		$supportDownloadError = "Could not use the internal web service implementation, please download and install SOAP::Lite manually";
	}


	eval {
		getConfigManager();
		readBrowseConfiguration();
	};
	if ($@) {
		errorMsg("Failed to load Custom Browse:\n$@\n");
	}
	my %submenu = (
		'useMode' => 'PLUGIN.CustomBrowse',
	);
	my $menuName = Slim::Utils::Prefs::get('plugin_custombrowse_menuname');
	if($menuName) {
		Slim::Utils::Strings::addStringPointer( uc 'PLUGIN_CUSTOMBROWSE', $menuName );
	}
	if(Slim::Utils::Prefs::get('plugin_custombrowse_menuinsidebrowse')) {
		Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC',string('PLUGIN_CUSTOMBROWSE'),\%submenu);
	}
	addPlayerMenus();
	delSlimserverPlayerMenus();
}

sub getConfigManager {
	if(!defined($configManager)) {
		my %parameters = (
			'debugCallback' => \&debugMsg,
			'errorCallback' => \&errorMsg,
			'pluginId' => 'CustomBrowse',
			'pluginVersion' => $PLUGINVERSION,
			'supportDownloadError' => $supportDownloadError,
			'addSqlErrorCallback' => \&addSQLError
		);
		$configManager = Plugins::CustomBrowse::ConfigManager::Main->new(\%parameters);
	}
	return $configManager;
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
		my %submenubrowse = (
			'useMode' => 'PLUGIN.CustomBrowse',
			'selectedMenu' => $browseMenus->{$menu}->{'id'},
			'mainBrowseMenu' => 1
		);
		my %submenuhome = (
			'useMode' => 'PLUGIN.CustomBrowse',
			'selectedMenu' => $browseMenus->{$menu}->{'id'},
			'mainBrowseMenu' => 1
		);
		Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC',$name,\%submenubrowse);
		Slim::Buttons::Home::addMenuOption($name,\%submenuhome);
            }else {
                Slim::Buttons::Home::delSubMenu('BROWSE_MUSIC',$name);
		Slim::Buttons::Home::delMenuOption($name);
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
	my $items = getMenuItems($client,$item,$params->{'option'},$params->{'mainBrowseMenu'});
	if(ref($items) eq 'ARRAY') {
		my @resultItems = ();
		my %pagebar = ();
		$result{'pageinfo'}=\%pagebar;
		$result{'pageinfo'}->{'totalitems'} = scalar(@$items);
		my $itemsPerPage = Slim::Utils::Prefs::get('itemsPerPage');
		$result{'pageinfo'}->{'itemsperpage'} = $itemsPerPage;
		my $menulinks = getMenuLinks($currentMenu,$params->{'option'});
		if(defined($currentMenu) && defined($menulinks) && $menulinks eq 'alpha') {
			my %alphaMap = ();
			my $itemNo = 0;
			my $prevLetter = '';
			my $letter = '';
			my $pageItemNo=0;
			my $startItemNo = 0;
			my $moveAlphaLetter = 0;
			for my $alphaIt (@$items) {
				if($pageItemNo>=$itemsPerPage) {
					if($alphaIt->{'itemlink'} ne $letter) {
						$pageItemNo = $pageItemNo - $itemsPerPage-$moveAlphaLetter;
						$startItemNo = $itemNo;
						$moveAlphaLetter = 0;
					}else {
						$moveAlphaLetter = $moveAlphaLetter +1;
					}
				}
				$prevLetter = $letter;
				$letter = $alphaIt->{'itemlink'};
				if(defined($letter) && (!defined($prevLetter) || $letter ne $prevLetter)) {
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
			if(defined($params->{'option'})) {
				$result{'pageinfo'}->{'otherparams'} = $context->{'url'}.$context->{'valueUrl'}.'&option='.$params->{'option'};
			}else {
				$result{'pageinfo'}->{'otherparams'} = $context->{'url'}.$context->{'valueUrl'};
			}
		}
		my $count = 0;
		my $prevLetter = '';
		for my $it (@$items) {
			if(defined($itemsPerPage) && $itemsPerPage>0) {
				$count = $count + 1;
				if($count>$itemsPerPage) {
					if(defined($currentMenu) && defined($menulinks) && $menulinks eq 'alpha') {
						if($prevLetter ne $it->{'itemlink'}) {
							last;
						}else {
							$result{'pageinfo'}->{'enditem'} = $result{'pageinfo'}->{'enditem'} +1;
						}
					}else {
						last;
					}
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
						my $keywords = combineKeywords($it->{'menu'}->{'keywordparameters'},undef,$params);
						$url = replaceParameters($client,$url,$keywords);
						$it->{'externalurl'}=$url;
					}
				}else {
					my $id = $it->{'itemid'};
					$id = Slim::Utils::Unicode::utf8on($id);
					$id = Slim::Utils::Unicode::utf8encode_locale($id);
					if(defined($context)) {
						$it->{'url'}=$context->{'url'}.','.$it->{'id'}.$context->{'valueUrl'}.'&'.$it->{'id'}.'='.=escape($id);
					}else {
						$it->{'url'}='&hierarchy='.$it->{'id'}.'&'.$it->{'id'}.'='.escape($id);
					}
					if((defined($client) && $client->param('mainBrowseMenu')) || $params->{'mainBrowseMenu'}) {
						$it->{'url'} .= "&mainBrowseMenu=1";
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
			my $mixes = getMixes($client,$it,1);
			if(scalar(@$mixes)>0) {
				my @webMixes = ();
				for my $mix (@$mixes) {
					my %webMix = (
						'name' => $mix->{'mixname'},
						'id' => $mix->{'id'}
					);
					my $image = $mix->{'miximage'};
					if(defined($image)) {
						$webMix{'image'} = $image;
					}
					my $url = $mix->{'mixurl'};
					if(defined($url)) {
						my $parameters = getCustomBrowseProperties();
						$parameters->{'itemid'} = $it->{'itemid'};
						$parameters->{'itemname'} = $it->{'itemname'};
						my $keywords = combineKeywords($it->{'keywordparameters'},$it->{'parameters'},$parameters);
						$url = replaceParameters($client,$url,$keywords);
						$webMix{'url'} = $url;
					}
					if($mix->{'mixtype'} ne 'menu' && !($mix->{'mixtype'} eq 'mode' && !defined($url))) {
						push @webMixes,\%webMix;
					}
				}
				$it->{'mixes'} = \@webMixes;
				#$it->{'mixable'} = 1;
			}
			push @resultItems, $it;
			if(defined($currentMenu) && defined($menulinks) && $menulinks eq 'alpha') {
				$prevLetter = $it->{'itemlink'};
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
	my $options = getMenuOptions($currentMenu);
	if(scalar(@$options)>0) {
		$result{'options'} = $options;
	}
	return \%result;
}

sub getMenuOptions {
	my $menu = shift;

	my @options = ();

	if(defined($menu) && defined($menu->{'option'})) {
		if(ref($menu->{'option'}) eq 'ARRAY') {
			my $menuoptions = $menu->{'option'};
			for my $op (@$menuoptions) {
				my %option = (
					'id' => $op->{'id'},
					'name' => $op->{'name'},
				);
				push @options, \%option;
			}
		}
	}
	return \@options;
}

sub getMenuLinks {
	my $menu = shift;
	my $option = shift;

	my $menulinks = undef;

	if(!defined($menu)) {
		return undef;
	}
	if(defined($menu->{'option'})) {
		if(ref($menu->{'option'}) eq 'ARRAY') {
			my $options = $menu->{'option'};
			my $foundOption = 0;
			if(defined($option)) {
				for my $op (@$options) {
					if(defined($op->{'id'}) && $op->{'id'} eq $option) {
						$menulinks = $op->{'menulinks'};
						$foundOption = 1;
					}
				}
			}
			if(!defined($menulinks)) {
				if(!$foundOption && defined($options->[0]->{'menulinks'})) {
					$menulinks = $options->[0]->{'menulinks'};
				}
			}
		}else {
			$menulinks = $menu->{'option'}->{'menulinks'};
		}
	}
	if(!defined($menulinks)) {
		$menulinks = $menu->{'menulinks'};
	}
	return $menulinks;
}

sub displayAsHTML {
        my $type = shift;
        my $form = shift;
        my $item = shift;

	$item->displayAsHTML($form);
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
			if($menu->{'id'} eq escape($group)) {
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
				if($menu->{'id'} eq escape($group)) {
					$item = $menu;
				}
			}
		}else {
			if($currentItems->{'id'} eq escape($group)) {
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

	$prefVal = Slim::Utils::Prefs::get('plugin_custombrowse_menuinsidebrowse');
	if (! defined $prefVal) {
		debugMsg("Defaulting plugin_custombrowse_menuinsidebrowse to 1\n");
		Slim::Utils::Prefs::set('plugin_custombrowse_menuinsidebrowse', 1);
	}
        $prefVal = Slim::Utils::Prefs::get('plugin_custombrowse_directory');
	if (! defined $prefVal) {
		my $dir=Slim::Utils::Prefs::get('playlistdir');
		debugMsg("Defaulting plugin_custombrowse_directory to:$dir\n");
		Slim::Utils::Prefs::set('plugin_custombrowse_directory', $dir);
	}
        $prefVal = Slim::Utils::Prefs::get('plugin_custombrowse_menuname');
	if (! defined $prefVal) {
		my $dir=Slim::Utils::Prefs::get('playlistdir');
		debugMsg("Defaulting plugin_custombrowse_menuname to:".string('PLUGIN_CUSTOMBROWSE')."\n");
		Slim::Utils::Prefs::set('plugin_custombrowse_menuname', string('PLUGIN_CUSTOMBROWSE'));
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_custombrowse_download_url');
	if (! defined $prefVal) {
		debugMsg("Defaulting plugin_custombrowse_download_url\n");
		Slim::Utils::Prefs::set('plugin_custombrowse_download_url', 'http://erland.homeip.net/datacollection/services/DataCollection');
	}
	$prefVal = Slim::Utils::Prefs::get('plugin_custombrowse_properties');
	if (! $prefVal) {
		debugMsg("Defaulting plugin_custombrowse_properties\n");
		my @properties = ();
		push @properties, 'libraryDir='.Slim::Utils::Prefs::get('audiodir');
		push @properties, 'libraryAudioDirUrl='.Slim::Utils::Misc::fileURLFromPath(Slim::Utils::Prefs::get('audiodir'));
		push @properties, 'mixsize=20';
		Slim::Utils::Prefs::set('plugin_custombrowse_properties', \@properties);
	}else {
	        my @properties = Slim::Utils::Prefs::getArray('plugin_custombrowse_properties');
		my $mixsize = undef;
		for my $property (@properties) {
			if($property =~ /^mixsize=/) {
				$mixsize = 1;
			}
		}
		if(!$mixsize) {
			Slim::Utils::Prefs::push('plugin_custombrowse_properties', 'mixsize=20');
		}
	}
	my $slimserverMenus = getSlimserverMenus();
	for my $menu (@$slimserverMenus) {
		$prefVal = Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_'.$menu->{'id'}.'_enabled');
		if(! defined $prefVal) {
			Slim::Utils::Prefs::set('plugin_custombrowse_slimservermenu_'.$menu->{'id'}.'_enabled',1);
		}
	}
}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_custombrowse_directory','plugin_custombrowse_template_directory','plugin_custombrowse_menuname','plugin_custombrowse_menuinsidebrowse','plugin_custombrowse_properties','plugin_custombrowse_showmessages'],
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
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_CUSTOMBROWSE_SHOW_MESSAGES')
			,'changeIntro' => string('PLUGIN_CUSTOMBROWSE_SHOW_MESSAGES')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_custombrowse_showmessages"); }
		},
	plugin_custombrowse_menuinsidebrowse => {
			'validate'     => \&Slim::Utils::Validate::trueFalse
			,'PrefChoose'  => string('PLUGIN_CUSTOMBROWSE_MENUINSIDEBROWSE')
			,'changeIntro' => string('PLUGIN_CUSTOMBROWSE_MENUINSIDEBROWSE')
			,'options' => {
					 '1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_custombrowse_menuinsidebrowse"); }
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
			'validate' => \&Slim::Utils::Validate::isDir
			,'PrefChoose' => string('PLUGIN_CUSTOMBROWSE_DIRECTORY')
			,'changeIntro' => string('PLUGIN_CUSTOMBROWSE_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_custombrowse_directory"); }
		},
	plugin_custombrowse_template_directory => {
			'validate' => \&Slim::Utils::Validate::isDir
			,'PrefChoose' => string('PLUGIN_CUSTOMBROWSE_TEMPLATE_DIRECTORY')
			,'changeIntro' => string('PLUGIN_CUSTOMBROWSE_TEMPLATE_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_custombrowse_template_directory"); }
		},
	plugin_custombrowse_menuname => {
			'validate' => \&Slim::Utils::Validate::acceptAll
			,'PrefChoose' => string('PLUGIN_CUSTOMBROWSE_MENUNAME')
			,'changeIntro' => string('PLUGIN_CUSTOMBROWSE_MENUNAME')
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_custombrowse_menuname"); }
		},
	);
	return (\%setupGroup,\%setupPrefs);
}

sub webPages {
	my %pages = (
                "custombrowse_list\.(?:htm|xml)"     => \&handleWebList,
                "webadminmethods_edititems\.(?:htm|xml)"     => \&handleWebEditMenus,
                "webadminmethods_edititem\.(?:htm|xml)"     => \&handleWebEditMenu,
                "webadminmethods_saveitem\.(?:htm|xml)"     => \&handleWebSaveMenu,
                "webadminmethods_savesimpleitem\.(?:htm|xml)"     => \&handleWebSaveSimpleMenu,
                "webadminmethods_savenewitem\.(?:htm|xml)"     => \&handleWebSaveNewMenu,
                "webadminmethods_savenewsimpleitem\.(?:htm|xml)"     => \&handleWebSaveNewSimpleMenu,
                "webadminmethods_removeitem\.(?:htm|xml)"     => \&handleWebRemoveMenu,
                "webadminmethods_newitemtypes\.(?:htm|xml)"     => \&handleWebNewMenuTypes,
                "webadminmethods_newitemparameters\.(?:htm|xml)"     => \&handleWebNewMenuParameters,
                "webadminmethods_newitem\.(?:htm|xml)"     => \&handleWebNewMenu,
		"webadminmethods_login\.(?:htm|xml)"      => \&handleWebLogin,
		"webadminmethods_downloadnewitems\.(?:htm|xml)"      => \&handleWebDownloadNewMenus,
		"webadminmethods_downloaditems\.(?:htm|xml)"      => \&handleWebDownloadMenus,
		"webadminmethods_downloaditem\.(?:htm|xml)"      => \&handleWebDownloadMenu,
		"webadminmethods_publishitemparameters\.(?:htm|xml)"      => \&handleWebPublishMenuParameters,
		"webadminmethods_publishitem\.(?:htm|xml)"      => \&handleWebPublishMenu,
		"webadminmethods_deleteitemtype\.(?:htm|xml)"      => \&handleWebDeleteMenuType,
                "custombrowse_mix\.(?:htm|xml)"     => \&handleWebMix,
                "custombrowse_executemix\.(?:htm|xml)"     => \&handleWebExecuteMix,
                "custombrowse_add\.(?:htm|xml)"     => \&handleWebAdd,
                "custombrowse_play\.(?:htm|xml)"     => \&handleWebPlay,
                "custombrowse_addall\.(?:htm|xml)"     => \&handleWebAddAll,
                "custombrowse_playall\.(?:htm|xml)"     => \&handleWebPlayAll,
		"custombrowse_selectmenus\.(?:htm|xml)" => \&handleWebSelectMenus,
		"custombrowse_saveselectmenus\.(?:htm|xml)" => \&handleWebSaveSelectMenus,
        );

        my $value = 'plugins/CustomBrowse/custombrowse_list.html';

        if (grep { /^CustomBrowse::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

                $value = undef;
        }
	if(defined($value)) {
		#readBrowseConfiguration();
		addWebMenus(undef,$value);
		my $menuName = Slim::Utils::Prefs::get('plugin_custombrowse_menuname');
		if($menuName) {
			Slim::Utils::Strings::addStringPointer( uc 'PLUGIN_CUSTOMBROWSE_CUSTOM_MENUNAME', $menuName );
		}
		if(Slim::Utils::Prefs::get('plugin_custombrowse_menuinsidebrowse')) {
		        Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_CUSTOMBROWSE' => $value });
		}
		delSlimserverWebMenus();
	}

	if(Slim::Utils::Prefs::get('plugin_custombrowse_menuinsidebrowse')) {
	        return (\%pages);
	}else {
		return (\%pages,$value);
	}
}

sub delSlimserverWebMenus {
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_artist_enabled')) {
		Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_ARTIST' => undef });
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_genre_enabled')) {
		Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_GENRE' => undef });
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_album_enabled')) {
		Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_ALBUM' => undef });
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_year_enabled')) {
		Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_YEAR' => undef });
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_newmusic_enabled')) {
		Slim::Web::Pages->addPageLinks("browse", {'BROWSE_NEW_MUSIC' => undef });
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_playlist_enabled')) {
		Slim::Web::Pages->addPageLinks("browse", {'SAVED_PLAYLISTS' => undef });
	}
}

sub delSlimserverPlayerMenus {
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_artist_enabled')) {
		Slim::Buttons::Home::delSubMenu("BROWSE_MUSIC", 'BROWSE_BY_ARTIST');
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_genre_enabled')) {
		Slim::Buttons::Home::delSubMenu("BROWSE_MUSIC", 'BROWSE_BY_GENRE');
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_album_enabled')) {
		Slim::Buttons::Home::delSubMenu("BROWSE_MUSIC", 'BROWSE_BY_ALBUM');
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_year_enabled')) {
		Slim::Buttons::Home::delSubMenu("BROWSE_MUSIC", 'BROWSE_BY_YEAR');
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_newmusic_enabled')) {
		Slim::Buttons::Home::delSubMenu("BROWSE_MUSIC", 'BROWSE_NEW_MUSIC');
	}
	if(!Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_playlist_enabled')) {
		Slim::Buttons::Home::delSubMenu("BROWSE_MUSIC", 'SAVED_PLAYLISTS');
	}
}

sub addWebMenus {
	my $client = shift;
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
				my $keywords = combineKeywords($browseMenus->{$menu}->{'menu'}->{'keywordparameters'});
				$url = replaceParameters($client,$url,$keywords);
			}
			debugMsg("Adding menu: $name\n");
		        Slim::Web::Pages->addPageLinks("browse", { $name => $url });
		}else {
			debugMsg("Adding menu: $name\n");
		        Slim::Web::Pages->addPageLinks("browse", { $name => $value."?hierarchy=".escape($browseMenus->{$menu}->{'id'} )."&mainBrowseMenu=1"});
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

	$sqlerrors = '';
	if(defined($params->{'refresh'})) {
		readBrowseConfiguration($client);
	}
	my $items = getPageItemsForContext($client,$params,$browseMenus);
	my $context = getContext($client,$params,$browseMenus,0);

	if($items->{'artwork'}) {
		$params->{'pluginCustomBrowseArtworkSupported'} = 1;
	}
	$params->{'pluginCustomBrowsePageInfo'} = $items->{'pageinfo'};
	$params->{'pluginCustomBrowseOptions'} = $items->{'options'};
	$params->{'pluginCustomBrowseItems'} = $items->{'items'};
	$params->{'pluginCustomBrowseContext'} = $context;
	$params->{'pluginCustomBrowseSelectedOption'} = $params->{'option'};
	if($params->{'mainBrowseMenu'}) {
		$params->{'pluginCustomBrowseMainBrowseMenu'} = 1;
	}

	if(defined($context) && scalar(@$context)>0) {
		$params->{'pluginCustomBrowseCurrentContext'} = $context->[scalar(@$context)-1];
	}
	if($sqlerrors && $sqlerrors ne '') {
		$params->{'pluginCustomBrowseError'} = $sqlerrors;
	}
	$params->{'pluginCustomBrowseVersion'} = $PLUGINVERSION;

        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_list.html', $params);
}


sub handleWebEditMenus {
        my ($client, $params) = @_;
	return getConfigManager()->webEditItems($client,$params);	
}

sub handleWebEditMenu {
        my ($client, $params) = @_;
	return getConfigManager()->webEditItem($client,$params);	
}

sub handleWebDeleteMenuType {
	my ($client, $params) = @_;
	return getConfigManager()->webDeleteItemType($client,$params);	
}

sub handleWebNewMenuTypes {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItemTypes($client,$params);	
}

sub handleWebNewMenuParameters {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItemParameters($client,$params);	
}

sub handleWebLogin {
	my ($client, $params) = @_;
	return getConfigManager()->webLogin($client,$params);	
}

sub handleWebPublishMenuParameters {
	my ($client, $params) = @_;
	return getConfigManager()->webPublishItemParameters($client,$params);	
}

sub handleWebPublishMenu {
	my ($client, $params) = @_;
	return getConfigManager()->webPublishItem($client,$params);	
}

sub handleWebDownloadMenus {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadItems($client,$params);	
}

sub handleWebDownloadNewMenus {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadNewItems($client,$params);	
}

sub handleWebDownloadMenu {
	my ($client, $params) = @_;
	return getConfigManager()->webDownloadItem($client,$params);	
}

sub handleWebNewMenu {
	my ($client, $params) = @_;
	return getConfigManager()->webNewItem($client,$params);	
}

sub handleWebSaveSimpleMenu {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveSimpleItem($client,$params);	
}

sub handleWebRemoveMenu {
	my ($client, $params) = @_;
	return getConfigManager()->webRemoveItem($client,$params);	
}

sub handleWebSaveNewSimpleMenu {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveNewSimpleItem($client,$params);	
}

sub handleWebSaveNewMenu {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveNewItem($client,$params);	
}

sub handleWebSaveMenu {
	my ($client, $params) = @_;
	return getConfigManager()->webSaveItem($client,$params);	
}



sub handleWebPlayAdd {
	my ($client, $params,$addOnly,$gotoparent) = @_;
	return unless $client;
	if(!defined($params->{'hierarchy'})) {
		readBrowseConfiguration($client);
	}
	my $items = getPageItemsForContext($client,$params,$browseMenus);
	if(defined($items->{'items'})) {
		my $playItems = $items->{'items'};
		my $loadCommand = 'loadtracks';
		foreach my $playItem (@$playItems) {
			if($addOnly) {
				debugMsg("Adding ".$playItem->{'itemname'}."\n");
				playAddItem($client,undef,$playItem,'addtracks',undef);
			}else {
				debugMsg("Playing ".$playItem->{'itemname'}."\n");
				playAddItem($client,undef,$playItem,$loadCommand,undef);
			}
			$loadCommand = 'addtracks';
		}
	}
	my $hierarchy = $params->{'hierarchy'};
	if(defined($hierarchy)) {
		my @hierarchyItems = (split /,/, $hierarchy);
		my $newHierarchy = '';
		my $i=0;
		my $noOfHierarchiesToUse = scalar(@hierarchyItems)-1;
		foreach my $hierarchyItem (@hierarchyItems) {
			if($i && $i<$noOfHierarchiesToUse) {
				$newHierarchy = $newHierarchy.',';
			}
			if($i<$noOfHierarchiesToUse) {
				$newHierarchy = $hierarchyItem;
			}
			$i=$i+1;
		}
		$params->{'hierarchy'} = $newHierarchy;
	}
	if(!$gotoparent) {
		$params->{'hierarchy'} = $hierarchy;
	}
	return handleWebList($client,$params);
}
sub handleWebPlay {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,0,1);
}

sub handleWebAdd {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,1,1);
}

sub handleWebPlayAll {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,0,0);
}

sub handleWebAddAll {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client,$params,1,0);
}

sub handleWebMix {
	my ($client, $params) = @_;
	return unless $client;
	if(!defined($params->{'hierarchy'})) {
		readBrowseConfiguration($client);
	}
	my $item = undef;
	my $nextitem = undef;
	my $contextItems = getContext($client,$params,$browseMenus,0);
	my @contexts = @$contextItems;

	my $currentcontext = undef;
	if(scalar(@contexts)>1) {
		my $context = @contexts[scalar(@contexts)-2];
		$item = $context->{'item'};
		$item->{'parameters'} = $context->{'parameters'};
	}
	if(scalar(@contexts)>0) {
		$currentcontext = @contexts[scalar(@contexts)-1];
		$nextitem = $currentcontext->{'item'};
		$nextitem->{'parameters'} = $currentcontext->{'parameters'};
	}
	my $items = getMenuItems($client,$item);
	my $selecteditem = undef;
	for my $it (@$items) {
		if($it->{'itemid'} eq $params->{$nextitem->{'id'}}) {
			$selecteditem = $it;
		}
	}
	if(defined($selecteditem)) {
		my $mixes = getMixes($client,$selecteditem,1);
		my @webMixes = ();
		for my $mix (@$mixes) {
			my %webMix = (
				'name' => $mix->{'mixname'},
				'id' => $mix->{'id'}
			);
			my $image = $mix->{'miximage'};
			if(defined($image)) {
				$mix->{'image'} = $image;
			}
			my $url = $mix->{'mixurl'};
			if(defined($url)) {
				my $parameters = getCustomBrowseProperties();
				$parameters->{'itemid'} = $selecteditem->{'itemid'};
				$parameters->{'itemname'} = $selecteditem->{'itemname'};
				my $keywords = combineKeywords($selecteditem->{'keywordparameters'},$selecteditem->{'parameters'},$parameters);
				$url = replaceParameters($client,$url,$keywords);
				$webMix{'url'} = $url;
			}
			push @webMixes,\%webMix;
		}
		if(scalar(@webMixes)>1) {
			$params->{'pluginCustomBrowseMixes'} = \@webMixes;
			$params->{'pluginCustomBrowseItemUrl'} = $currentcontext->{'url'}.$currentcontext->{'valueUrl'};
			pop @$contextItems;
			$params->{'pluginCustomBrowseContext'} = $contextItems;
			return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_listmixes.html', $params);
		}elsif(scalar(@webMixes)>0) {
			if(!defined(@webMixes->[0]->{'url'})) {
				$params->{'mix'} = @webMixes->[0]->{'id'};
				return handleWebExecuteMix($client,$params);
			}else {
				$params->{'pluginCustomBrowseRedirect'} = @webMixes->[0]->{'url'};
				return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_redirect.html', $params);
			}
		}
	}
	
	#Go back to current page if no mixers could be found
	my $hierarchy = $params->{'hierarchy'};
	if(defined($hierarchy)) {
		my @hierarchyItems = (split /,/, $hierarchy);
		my $newHierarchy = '';
		my $i=0;
		my $noOfHierarchiesToUse = scalar(@hierarchyItems)-1;
		foreach my $hierarchyItem (@hierarchyItems) {
			if($i && $i<$noOfHierarchiesToUse) {
				$newHierarchy = $newHierarchy.',';
			}
			if($i<$noOfHierarchiesToUse) {
				$newHierarchy = $hierarchyItem;
			}
			$i=$i+1;
		}
		$params->{'hierarchy'} = $newHierarchy;
	}
	return handleWebList($client,$params);
}

sub handleWebExecuteMix {
	my ($client, $params) = @_;
	return unless $client;
	if(!defined($params->{'hierarchy'})) {
		readBrowseConfiguration($client);
	}
	my $item = undef;
	my $nextitem = undef;
	my $contextItems = getContext($client,$params,$browseMenus,0);
	my @contexts = @$contextItems;

	my $currentcontext = undef;
	if(scalar(@contexts)>1) {
		my $context = @contexts[scalar(@contexts)-2];
		$item = $context->{'item'};
		$item->{'parameters'} = $context->{'parameters'};
	}
	if(scalar(@contexts)>0) {
		$currentcontext = @contexts[scalar(@contexts)-1];
		$nextitem = $currentcontext->{'item'};
		$nextitem->{'parameters'} = $currentcontext->{'parameters'};
	}
	my $items = getMenuItems($client,$item);
	my $selecteditem = undef;
	for my $it (@$items) {
		if($it->{'itemid'} eq $params->{$nextitem->{'id'}}) {
			$selecteditem = $it;
		}
	}
	if(defined($selecteditem)) {
		my $mixes = getMixes($client,$selecteditem,1);
		for my $mix (@$mixes) {
			if($mix->{'id'} eq $params->{'mix'}) {
				executeMix($client,$mix,0,$selecteditem,1);
				last;
			}
		}
	}
	
	#Go back to current page if no mixers could be found
	my $hierarchy = $params->{'hierarchy'};
	if(defined($hierarchy)) {
		my @hierarchyItems = (split /,/, $hierarchy);
		my $newHierarchy = '';
		my $i=0;
		my $noOfHierarchiesToUse = scalar(@hierarchyItems)-1;
		foreach my $hierarchyItem (@hierarchyItems) {
			if($i && $i<$noOfHierarchiesToUse) {
				$newHierarchy = $newHierarchy.',';
			}
			if($i<$noOfHierarchiesToUse) {
				$newHierarchy = $hierarchyItem;
			}
			$i=$i+1;
		}
		$params->{'hierarchy'} = $newHierarchy;
	}
	return handleWebList($client,$params);
}

# Draws the plugin's select menus web page
sub handleWebSelectMenus {
        my ($client, $params) = @_;

	if(!defined($browseMenusFlat)) {
		readBrowseConfiguration($client);
	}
        # Pass on the current pref values and now playing info
	my @menus = ();
	for my $key (keys %$browseMenusFlat) {
		my %webmenu = ();
		my $menu = $browseMenusFlat->{$key};
		for my $key (keys %$menu) {
			$webmenu{$key} = $menu->{$key};
		} 
		if(defined($webmenu{'menuname'}) && defined($webmenu{'menugroup'})) {
			$webmenu{'menuname'} = $webmenu{'menugroup'}.'/'.$webmenu{'menuname'};
		}
		push @menus,\%webmenu;
	}
	@menus = sort { $a->{'menuname'} cmp $b->{'menuname'} } @menus;

        $params->{'pluginCustomBrowseMenus'} = \@menus;
        $params->{'pluginCustomBrowseMixes'} = $browseMixes;

	$params->{'pluginCustomBrowseSlimserverMenus'} = getSlimserverMenus();

        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_selectmenus.html', $params);
}

sub getSlimserverMenus {
	my @slimserverMenus = ();
	my %browseByAlbum = (
		'id' => 'album',
		'name' => string('BROWSE_BY_ALBUM'),
		'enabled' => Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_album_enabled')
	);
	push @slimserverMenus,\%browseByAlbum;
	my %browseByArtist = (
		'id' => 'artist',
		'name' => string('BROWSE_BY_ARTIST'),
		'enabled' => Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_artist_enabled')
	);
	push @slimserverMenus,\%browseByArtist;
	my %browseByGenre = (
		'id' => 'genre',
		'name' => string('BROWSE_BY_GENRE'),
		'enabled' => Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_genre_enabled')
	);
	push @slimserverMenus,\%browseByGenre;
	my %browseByYear = (
		'id' => 'year',
		'name' => string('BROWSE_BY_YEAR'),
		'enabled' => Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_year_enabled')
	);
	push @slimserverMenus,\%browseByYear;
	my %browseNewMusic = (
		'id' => 'newmusic',
		'name' => string('BROWSE_NEW_MUSIC'),
		'enabled' => Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_newmusic_enabled')
	);
	push @slimserverMenus,\%browseNewMusic;
	my %browsePlaylist = (
		'id' => 'playlist',
		'name' => string('SAVED_PLAYLISTS').' (Player menu)',
		'enabled' => Slim::Utils::Prefs::get('plugin_custombrowse_slimservermenu_playlist_enabled')
	);
	push @slimserverMenus,\%browsePlaylist;
	return \@slimserverMenus;
}

# Draws the plugin's web page
sub handleWebSaveSelectMenus {
        my ($client, $params) = @_;

	if(!defined($browseMenusFlat)) {
		readBrowseConfiguration($client);
	}
        foreach my $menu (keys %$browseMenusFlat) {
                my $menuid = "menu_".escape($browseMenusFlat->{$menu}->{'id'});
                my $menubrowseid = "menubrowse_".escape($browseMenusFlat->{$menu}->{'id'});
                if($params->{$menuid}) {
                        Slim::Utils::Prefs::set('plugin_custombrowse_'.$menuid.'_enabled',1);
			$browseMenusFlat->{$menu}->{'enabled'}=1;
			if(!defined($browseMenusFlat->{$menu}->{'forceenabledbrowse'})) {
				if($params->{$menubrowseid}) {
                	        	Slim::Utils::Prefs::set('plugin_custombrowse_'.$menubrowseid.'_enabled',1);
					$browseMenusFlat->{$menu}->{'enabledbrowse'}=1;
		                }else {
	        			Slim::Utils::Prefs::set('plugin_custombrowse_'.$menubrowseid.'_enabled',0);
					$browseMenusFlat->{$menu}->{'enabledbrowse'}=0;
	                	}
			}
                }else {
                        Slim::Utils::Prefs::set('plugin_custombrowse_'.$menuid.'_enabled',0);
			$browseMenusFlat->{$menu}->{'enabled'}=0;
			if(!defined($browseMenusFlat->{$menu}->{'forceenabledbrowse'})) {
				$browseMenusFlat->{$menu}->{'enabledbrowse'}=0;
			}
                }
        }
        foreach my $mix (keys %$browseMixes) {
                my $mixid = "mix_".escape($browseMixes->{$mix}->{'id'});
                if($params->{$mixid}) {
                        Slim::Utils::Prefs::set('plugin_custombrowse_'.$mixid.'_enabled',1);
			$browseMixes->{$mix}->{'enabled'}=1;
                }else {
                        Slim::Utils::Prefs::set('plugin_custombrowse_'.$mixid.'_enabled',0);
			$browseMixes->{$mix}->{'enabled'}=0;
                }
        }
	my $slimserverMenus = getSlimserverMenus();
        foreach my $menu (@$slimserverMenus) {
                my $menuid = "slimservermenu_".escape($menu->{'id'});
                if($params->{$menuid}) {
                        Slim::Utils::Prefs::set('plugin_custombrowse_'.$menuid.'_enabled',1);
                }else {
                        Slim::Utils::Prefs::set('plugin_custombrowse_'.$menuid.'_enabled',0);
                }
        }
	$params->{'refresh'} = 1;
        handleWebList($client, $params);
}

sub readBrowseConfiguration {
	my $client = shift;

	my $itemConfiguration = getConfigManager()->readItemConfiguration($client,undef,undef,1);
	my $localBrowseMenus = $itemConfiguration->{'menus'};
	$templates = $itemConfiguration->{'templates'};

	my @menus = ();
	foreach my $menu (keys %$localBrowseMenus) {
		copyKeywords(undef,$localBrowseMenus->{$menu});
	}
	$browseMenus = structureBrowseMenus($localBrowseMenus);
	$browseMenusFlat = $localBrowseMenus;
	$browseMixes = $itemConfiguration->{'mixes'};
	
	my $value = 'plugins/CustomBrowse/custombrowse_list.html';
	if (grep { /^CustomBrowse::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {
		$value = undef;
	}
	addWebMenus($client,$value);
	delSlimserverWebMenus();
	delSlimserverPlayerMenus();
	addPlayerMenus();
}

sub getMultiLibraryMenus {
	my $client = shift;

	my $itemConfiguration = getConfigManager()->readItemConfiguration($client,1,'MultiLibrary::Plugin');
    	$templates = $itemConfiguration->{'templates'};
	my $localBrowseMenus = $itemConfiguration->{'menus'};
	foreach my $menu (keys %$localBrowseMenus) {
		copyKeywords(undef,$localBrowseMenus->{$menu});
	}
    
	my @result = ();
	for my $menuKey (keys %$localBrowseMenus) {
		my $menu = $localBrowseMenus->{$menuKey};
		if(defined($menu->{'simple'})) {
			if($menu->{'librarysupported'}) {
				my $xml = getConfigManager()->webAdminMethods->loadTemplateValues($client,$menuKey,$localBrowseMenus->{$menuKey});
				my $templateId = $xml->{'id'};
				my $template = $templates->{$templateId};
				my $templateParameters = $template->{'parameter'};
				my $valueParameters = $xml->{'parameter'};
				for my $tp (@$templateParameters) {
					my $found = 0;
					for my $vp (@$valueParameters) {
						if($vp->{'id'} eq $tp->{'id'}) {
							$found = 1;
							last;
						}
					}
					if(!$found && ($tp->{'id'} eq 'library' || $tp->{'id'} eq 'menuname' || $tp->{'id'} eq 'menugroup' || $tp->{'id'} eq 'includedclients' || $tp->{'id'} eq 'excludedclients')) {
						my %newParameter = (
							'id' => $tp->{'id'},
							'quotevalue' => $tp->{'quotevalue'}
						);
						push @$valueParameters,\%newParameter;
					}
				}
				my $data = "";
				$data .= "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<custombrowse>\n\t<template>\n\t\t<id>".$templateId."</id>";
				my $menuname = undef;
				my $menugroup = undef;
				for my $p (@$valueParameters) {
					if($p->{'id'} eq 'menuname') {
						my $values = $p->{'value'};
						if(defined($values) && scalar(@$values)>0) {
							$menuname = $values->[0];
						}
					}elsif($p->{'id'} eq 'library') {
						my @values = ();
						push @values,'{libraryno}';
						$p->{'value'} = \@values;
					}elsif($p->{'id'} eq 'menugroup') {
						my $currentValues = $p->{'value'};
						if(defined($currentValues) && scalar(@$currentValues)>0) {
							$menugroup = $currentValues->[0];
						}
						my @values = ();
						push @values,'{libraryname}';
						$p->{'value'} = \@values;
					}elsif($p->{'id'} eq 'includedclients') {
						my @values = ();
						push @values,'{includedclients}';
						$p->{'value'} = \@values;
					}elsif($p->{'id'} eq 'excludedclients') {
						my @values = ();
						push @values,'{excludedclients}';
						$p->{'value'} = \@values;
					}
					my $values = $p->{'value'};
					my $value = '';
					if(defined($values)) {
						if(scalar(@$values)>0) {
							for my $v (@$values) {
								$value .= '<value>';
								$value .= $v;
								$value .= '</value>';
							}
						}
					}
					if($p->{'quotevalue'}) {
						$data .= "\n\t\t<parameter type=\"text\" id=\"".$p->{'id'}."\" quotevalue=\"1\">";
					}else {
						$data .= "\n\t\t<parameter type=\"text\" id=\"".$p->{'id'}."\">";
					}
					$data .= $value.'</parameter>';
				}
				$data .= "\n\t</template>\n</custombrowse>\n";
				if(defined($menuname)) {
					my %menu = (
						'id' => $menuKey,
						'name' => $menuname,
						'group' => $menugroup,
						'content' => $data
					);
					push @result,\%menu;
				}
			}
		}
	}
	return \@result;
}

sub structureBrowseMenus {
	my $menus = shift;
	my %localMenuItems = ();
	my @localMenuItemsArray  = ();

	for my $menuKey (keys %$menus) {
		my $menu = $menus->{$menuKey};
		my $group = $menu->{'menugroup'};
		if(defined($group) && $menu->{'enabled'}) {
			my $currentLevel = \@localMenuItemsArray;
			my $grouppath = 'group';
			my $enabled = 1;
			my @currentgroups = split(/\//,$group);
			for my $group (@currentgroups) {
				my $groupId = $group;
				$groupId =~ s/^\s*//g;
				$groupId =~ s/\s*$//g;
				my $groupName = $groupId;
				# ' character in group ids are a bad idea
				$groupId =~ s/\'/_/g;
				$grouppath .= "_".escape($groupId);
				#debugMsg("Got group: ".$grouppath."\n");
				my $existingItem = undef;
				for my $item (@$currentLevel) {
					if($item->{'id'} eq 'group_'.escape($groupId)) {
						$existingItem = $item;
						last;
					}
				}
				if(defined($existingItem)) {
					if($enabled && $menu->{'enabled'}) {
						$existingItem->{'enabled'} = 1;
					}
					if($enabled && $menu->{'enabledbrowse'}) {
						$existingItem->{'enabledbrowse'} = 1;
					}
					if(defined($menu->{'includedclients'})) {
						if(defined($existingItem->{'includedclients'})) {
							my @existingClients = split(/,/,$existingItem->{'includedclients'});
							my @clients = split(/,/,$menu->{'includedclients'});
							for my $clientName (@clients) {
								my $bFound = 0;
								for my $existingClientName (@existingClients) {
									if($existingClientName eq $clientName) {
										$bFound = 1;
									}
								}
								if(!$bFound) {
									$existingItem->{'includedclients'} .= ",$clientName";
								}
							}
						}
					}else {
						$existingItem->{'includedclients'} = undef;
					}
					if(defined($menu->{'excludedclients'})) {
						if(defined($existingItem->{'excludedclients'})) {
							my @existingClients = split(/,/,$existingItem->{'excludedclients'});
							my @clients = split(/,/,$menu->{'excludedclients'});
							my $excludedClients = '';
							for my $clientName (@clients) {
								my $bFound = 0;
								for my $existingClientName (@existingClients) {
									if($existingClientName eq $clientName) {
										$bFound = 1;
									}
								}
								if($bFound) {
									if($excludedClients ne '') {
										$excludedClients .= ",";
									}
									$excludedClients .= $clientName;
								}
							}
							if($excludedClients eq '') {
								$existingItem->{'excludedclients'} = undef;
							}else {
								$existingItem->{'excludedclients'} = $excludedClients;
							}
						}
					}else {
						$existingItem->{'excludedclients'} = undef;
					}
					if(defined($menu->{'includedlibraries'})) {
						if(defined($existingItem->{'includedlibraries'})) {
							my @existingLibraries = split(/,/,$existingItem->{'includedlibraries'});
							my @libraries = split(/,/,$menu->{'includedlibraries'});
							for my $libraryName (@libraries) {
								my $bFound = 0;
								for my $existingLibraryName (@existingLibraries) {
									if($existingLibraryName eq $libraryName) {
										$bFound = 1;
									}
								}
								if(!$bFound) {
									$existingItem->{'includedlibraries'} .= ",$libraryName";
								}
							}
						}
					}else {
						$existingItem->{'includedlibraries'} = undef;
					}
					if(defined($menu->{'excludedlibraries'})) {
						if(defined($existingItem->{'excludedlibraries'})) {
							my @existingLibraries = split(/,/,$existingItem->{'excludedlibraries'});
							my @libraries = split(/,/,$menu->{'excludedlibraries'});
							my $excludedLibraries = '';
							for my $libraryName (@libraries) {
								my $bFound = 0;
								for my $existingLibraryName (@existingLibraries) {
									if($existingLibraryName eq $libraryName) {
										$bFound = 1;
									}
								}
								if($bFound) {
									if($excludedLibraries ne '') {
										$excludedLibraries .= ",";
									}
									$excludedLibraries .= $libraryName;
								}
							}
							if($excludedLibraries eq '') {
								$existingItem->{'excludedlibraries'} = undef;
							}else {
								$existingItem->{'excludedlibraries'} = $excludedLibraries;
							}
						}
					}else {
						$existingItem->{'excludedlibraries'} = undef;
					}

					$currentLevel = $existingItem->{'menu'};
				}else {
					my @level = ();
					my %currentItemGroup = (
						'id' => 'group_'.escape($groupId),
						'topmenu' => 1,
						'menu' => \@level,
						'menuname' => $groupName,
					);
					if($enabled && $menu->{'enabled'}) {
						$currentItemGroup{'enabled'} = 1;
					}
					if($enabled && $menu->{'enabledbrowse'}) {
						$currentItemGroup{'enabledbrowse'} = 1;
					}
					if(defined($menu->{'includedclients'})) {
						$currentItemGroup{'includedclients'} = $menu->{'includedclients'};
					}
					if(defined($menu->{'excludedclients'})) {
						$currentItemGroup{'excludedclients'} = $menu->{'excludedclients'};
					}
					if(defined($menu->{'includedlibraries'})) {
						$currentItemGroup{'includedlibraries'} = $menu->{'includedlibraries'};
					}
					if(defined($menu->{'excludedlibraries'})) {
						$currentItemGroup{'excludedlibraries'} = $menu->{'excludedlibraries'};
					}
					push @$currentLevel,\%currentItemGroup;
					sortMenu($currentLevel);
					$currentLevel = \@level;
				}
			}
			push @$currentLevel,$menu;
			sortMenu($currentLevel);
		}else {
			push @localMenuItemsArray,$menu
		}
	}
	for my $item (@localMenuItemsArray) {
		$localMenuItems{$item->{'id'}} = $item;
	}
	return \%localMenuItems;
}

sub sortMenu {
	my $menu = shift;
	@$menu = sort { 
		if(defined($a->{'menuorder'}) && defined($b->{'menuorder'})) {
			if($a->{'menuorder'}!=$b->{'menuorder'}) {
				return $a->{'menuorder'} <=> $b->{'menuorder'};
			}
		}
		if(defined($a->{'menuorder'}) && !defined($b->{'menuorder'})) {
			if($a->{'menuorder'}!=50) {
				return $a->{'menuorder'} <=> 50;
			}
		}
		if(!defined($a->{'menuorder'}) && defined($b->{'menuorder'})) {
			if($b->{'menuorder'}!=50) {
				return 50 <=> $b->{'menuorder'};
			}
		}
		return $a->{'menuname'} cmp $b->{'menuname'} 
	} @$menu;
}


sub validateProperty {
	my $arg = shift;
	if($arg eq '' || $arg =~ /^[a-zA-Z0-9_]+\s*=\s*.+$/) {
		return $arg;
	}else {
		return undef;
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
	return Slim::Schema->storage->dbh();
}

sub objectForId {
	my $type = shift;
	my $id = shift;
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
	}elsif($type eq 'year') {
		$type = 'Year';
	}
	return Slim::Schema->resultset($type)->find($id);
}

sub getLinkAttribute {
	my $attr = shift;
	if($attr eq 'artist') {
		$attr = 'contributor';
	}
	return $attr.'.id';
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

sub addSQLError {
	my $error = shift;
	$sqlerrors .= $error;
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

PLUGIN_CUSTOMBROWSE_MENUINSIDEBROWSE
	EN	Show Custom Browse menu inside Browse menu (requires slimserver restart)

PLUGIN_CUSTOMBROWSE_PROPERTIES
	EN	Properties to use in queries and menus

SETUP_PLUGIN_CUSTOMBROWSE_SHOWMESSAGES
	EN	Debugging

SETUP_PLUGIN_CUSTOMBROWSE_MENUINSIDEBROWSE
	EN	Menu position

SETUP_PLUGIN_CUSTOMBROWSE_PROPERTIES
	EN	Properties to use in queries and menus

PLUGIN_CUSTOMBROWSE_DIRECTORY
	EN	Browse configuration directory

PLUGIN_CUSTOMBROWSE_TEMPLATE_DIRECTORY
	EN	Browse templates directory

SETUP_PLUGIN_CUSTOMBROWSE_DIRECTORY
	EN	Browse configuration directory

SETUP_PLUGIN_CUSTOMBROWSE_TEMPLATE_DIRECTORY
	EN	Browse templates directory

PLUGIN_CUSTOMBROWSE_MENUNAME
	EN	Menu name

SETUP_PLUGIN_CUSTOMBROWSE_MENUNAME
	EN	Menu name (Slimserver 6.5 only, requires restart)

PLUGIN_CUSTOMBROWSE_SELECT_MENUS
	EN	Enable/Disable menus/mixers

PLUGIN_CUSTOMBROWSE_SELECT_MENUS_TITLE
	EN	Select enabled menus

PLUGIN_CUSTOMBROWSE_SELECT_MENUS_BROWSE_TITLE
	EN	Show in<br>browse and home menu

PLUGIN_CUSTOMBROWSE_SELECT_MENUS_NONE
	EN	No Menus

PLUGIN_CUSTOMBROWSE_SELECT_MENUS_ALL
	EN	All Menus

PLUGIN_CUSTOMBROWSE_SELECT_MIXES_TITLE
	EN	Select enabled mixers

PLUGIN_CUSTOMBROWSE_SELECT_MIXES_NONE
	EN	No Mixers

PLUGIN_CUSTOMBROWSE_SELECT_MIXES_ALL
	EN	All Mixers

PLUGIN_CUSTOMBROWSE_SELECT_SLIMSERVER_MENUS_TITLE
	EN	Select enabled slimserver menus (changes requires slimserver restart)

PLUGIN_CUSTOMBROWSE_NO_ITEMS_FOUND
	EN	No matching songs, albums or artists were found

PLUGIN_CUSTOMBROWSE_EDIT_MENUS
	EN	Edit menus

PLUGIN_CUSTOMBROWSE_EDIT_ITEM_FILENAME
	EN	Filename

PLUGIN_CUSTOMBROWSE_EDIT_ITEM_DATA
	EN	Menu configuration

PLUGIN_CUSTOMBROWSE_NEW_ITEM_TYPES_TITLE
	EN	Select type of menu to create

PLUGIN_CUSTOMBROWSE_NEW_ITEM
	EN	Create new menu

PLUGIN_CUSTOMBROWSE_NEW_ITEM_PARAMETERS_TITLE
	EN	Please enter menu parameters

PLUGIN_CUSTOMBROWSE_EDIT_ITEM_PARAMETERS_TITLE
	EN	Please enter menu parameters

PLUGIN_CUSTOMBROWSE_REMOVE_ITEM_QUESTION
	EN	Are you sure you want to delete this menu ?

PLUGIN_CUSTOMBROWSE_REMOVE_ITEM_TYPE_QUESTION
	EN	Removing a menu type might cause problems later if it is used in existing menus, are you really sure you want to delete this menu type ?

PLUGIN_CUSTOMBROWSE_REMOVE_ITEM
	EN	Delete

PLUGIN_CUSTOMBROWSE_MIX_NOTRACKS
	EN	Unable to create mix

PLUGIN_CUSTOMBROWSE_REFRESH
	EN	Refresh

PLUGIN_CUSTOMBROWSE_ITEMTYPE
	EN	Customize configuration

PLUGIN_CUSTOMBROWSE_ITEMTYPE_SIMPLE
	EN	Use predefined

PLUGIN_CUSTOMBROWSE_ITEMTYPE_ADVANCED
	EN	Customize

PLUGIN_CUSTOMBROWSE_TRACKSTAT
	EN	TrackStat

PLUGIN_CUSTOMBROWSE_TRACKSTAT_RATING
	EN	Rating:

PLUGIN_CUSTOMBROWSE_LOGIN_USER
	EN	Username

PLUGIN_CUSTOMBROWSE_LOGIN_PASSWORD
	EN	Password

PLUGIN_CUSTOMBROWSE_LOGIN_FIRSTNAME
	EN	First name

PLUGIN_CUSTOMBROWSE_LOGIN_LASTNAME
	EN	Last name

PLUGIN_CUSTOMBROWSE_LOGIN_EMAIL
	EN	e-mail

PLUGIN_CUSTOMBROWSE_ANONYMOUSLOGIN
	EN	Anonymous

PLUGIN_CUSTOMBROWSE_LOGIN
	EN	Login

PLUGIN_CUSTOMBROWSE_REGISTERLOGIN
	EN	Register &amp; Login

PLUGIN_CUSTOMBROWSE_REGISTER_TITLE
	EN	Register a new user

PLUGIN_CUSTOMBROWSE_LOGIN_TITLE
	EN	Login

PLUGIN_CUSTOMBROWSE_DOWNLOAD_ITEMS
	EN	Download more menus

PLUGIN_CUSTOMBROWSE_PUBLISH_ITEM
	EN	Publish

PLUGIN_CUSTOMBROWSE_PUBLISH
	EN	Publish

PLUGIN_CUSTOMBROWSE_PUBLISHPARAMETERS_TITLE
	EN	Please specify information about the menu

PLUGIN_CUSTOMBROWSE_PUBLISH_NAME
	EN	Name

PLUGIN_CUSTOMBROWSE_PUBLISH_DESCRIPTION
	EN	Description

PLUGIN_CUSTOMBROWSE_PUBLISH_ID
	EN	Unique identifier

PLUGIN_CUSTOMBROWSE_LASTCHANGED
	EN	Last changed

PLUGIN_CUSTOMBROWSE_PUBLISHMESSAGE
	EN	Thanks for choosing to publish your menu. The advantage of publishing a menu is that other users can use it and it will also be used for ideas of new functionallity in the Custom Browse plugin. Publishing a menu is also a great way of improving the functionality in the Custom Browse plugin by showing the developer what types of menus you use, besides those already included with the plugin.

PLUGIN_CUSTOMBROWSE_REGISTERMESSAGE
	EN	You can choose to publish your menu either anonymously or by registering a user and login. The advantage of registering is that other people will be able to see that you have published the menu, you will get credit for it and you will also be sure that no one else can update or change your published menu. The e-mail adress will only be used to contact you if I have some questions to you regarding one of your menus, it will not show up on any web pages. If you already have registered a user, just hit the Login button.

PLUGIN_CUSTOMBROWSE_LOGINMESSAGE
	EN	You can choose to publish your menu either anonymously or by registering a user and login. The advantage of registering is that other people will be able to see that you have published the menu, you will get credit for it and you will also be sure that no one else can update or change your published menu. Hit the &quot;Register &amp; Login&quot; button if you have not previously registered.

PLUGIN_CUSTOMBROWSE_PUBLISHMESSAGE_DESCRIPTION
	EN	It is important that you enter a good description of your menu, describe what your menu do and if it is based on one of the existing menus it is a good idea to mention this and describe which extensions you have made. <br><br>It is also a good idea to try to make the &quot;Unique identifier&quot; as uniqe as possible as this will be used for filename when downloading the menu. This is especially important if you have choosen to publish your menu anonymously as it can easily be overwritten if the identifier is not unique. Please try to not use spaces and language specific characters in the unique identifier since these could cause problems on some operating systems.

PLUGIN_CUSTOMBROWSE_REFRESH_DOWNLOADED_ITEMS
	EN	Download last version of existing menus

PLUGIN_CUSTOMBROWSE_DOWNLOAD_TEMPLATE_OVERWRITE_WARNING
	EN	A menu type with that name already exists, please change the name or select to overwrite the existing menu type

PLUGIN_CUSTOMBROWSE_DOWNLOAD_TEMPLATE_OVERWRITE
	EN	Overwrite existing

PLUGIN_CUSTOMBROWSE_PUBLISH_OVERWRITE
	EN	Overwrite existing

PLUGIN_CUSTOMBROWSE_DOWNLOAD_TEMPLATE_NAME
	EN	Unique identifier

PLUGIN_CUSTOMBROWSE_EDIT_ITEM_OVERWRITE
	EN	Overwrite existing

PLUGIN_CUSTOMBROWSE_SELECT_MIXES
	EN	Select mix to create

PLUGIN_CUSTOMBROWSE_DOWNLOAD_QUESTION
	EN	This operation will download latest version of all menus, this might take some time. Please note that this will overwrite any local changes you have made in built-in or previously downloaded menu types. Are you sure you want to continue ?
EOF

}

1;

__END__
