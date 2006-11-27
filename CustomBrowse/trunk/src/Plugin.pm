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

my $driver;
my $browseMenus;
my $browseMixes;
my $template;
my $mixer;

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

sub getMenuItems {
    my $client = shift;
    my $item = shift;
    my $option = shift;

    my @listRef = ();

    if(!defined($item)) {
        for my $menu (keys %$browseMenus) {
            if(!defined($browseMenus->{$menu}->{'value'})) {
            	$browseMenus->{$menu}->{'value'} = $browseMenus->{$menu}->{'id'};
            }
            if($browseMenus->{$menu}->{'enabled'}) {
                    if(isMenuEnabledForClient($client,$browseMenus->{$menu})) {
		            push @listRef,$browseMenus->{$menu};
                    }		
            }
        }
	@listRef = sort { 
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
		} @listRef;
    }elsif(defined($item->{'menu'})) {
	my @menus = ();
	if(ref($item->{'menu'}) eq 'ARRAY') {
		foreach my $it (@{$item->{'menu'}}) {
			if(isMenuEnabledForClient($client,$it)) {
				push @menus,$it;
			}
		}
	}else {
		if(isMenuEnabledForClient($client,$item->{'menu'})) {
			push @menus,$item->{'menu'};
		}
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
	            my $sql = prepareMenuSQL($menudata,$keywords);
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
					$modeParameters{$1}->{$2}=replaceParameters($value,$keywords);
				}else {
					$modeParameters{$name} = replaceParameters($value, $keywords);
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
	            $dir = replaceParameters($dir,$keywords);
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
	my ($client, $mix, $item) = @_;
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
			
			my $sql = prepareMenuSQL($mixcheckdata,$keywords);
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
					if ($::VERSION ge '6.5') {
						$itemObj = objectForId('year',$item->{'itemid'});
					}else {
						$itemObj = $item->{'itemid'};
					}
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
								if(checkMix($client, $globalMix, $item)) {
									push @mixes,$globalMix;
								}
							}
						}
					}elsif(defined($mix->{'mixname'}))  {
						if(checkMix($client, $mix, $item)) {
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
							if(checkMix($client, $globalMix, $item)) {
								push @mixes,$globalMix;
							}
						}
					}
				}elsif(defined($mix->{'mixname'}))  {
					if(checkMix($client, $mix, $item)) {
						push @mixes,$mix;
					}
				}
			}
		}
	}elsif(defined($item->{'itemtype'})) {
		foreach my $key (keys %$browseMixes) {
			my $mix = $browseMixes->{$key};
			if($mix->{'enabled'} && $mix->{'mixcategory'} eq $item->{'itemtype'}) {
				if(checkMix($client, $mix, $item)) {
					push @mixes,$mix;
				}
			}
		}
	}
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
        my ($client, $mixer, $addOnly,$item) = @_;

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
		Slim::Buttons::Common::popModeRight($client);
	}elsif($mixer->{'mixtype'} eq 'mode') {
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
					$modeParameters{$1}->{$2}=replaceParameters($value,$keywords);
				}else {
					$modeParameters{$name} = replaceParameters($value,$keywords);
				}
			}
		}
		Slim::Buttons::Common::pushModeLeft($client, $mode, \%modeParameters);
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
				if ($::VERSION ge '6.5') {
					$itemObj = objectForId('year',$item->{'itemid'});
				}else {
					$itemObj = $item->{'itemid'};
				}
			}elsif($item->{'itemtype'} eq "genre") {
				$itemObj = objectForId('genre',$item->{'itemid'});
			}elsif($item->{'itemtype'} eq "playlist") {
				$itemObj = objectForId('playlist',$item->{'itemid'});
			}
			if(defined($itemObj)) {
				if(UNIVERSAL::can("$class","$function")) {
					debugMsg("Calling ${class}::${function}\n");
					no strict 'refs';
					eval { &{"${class}::${function}"}($client,$itemObj,$addOnly) };
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
		Slim::Buttons::Common::popModeRight($client);
	}else {
		my $line2 = $client->doubleString('PLUGIN_CUSTOMBROWSE_MIX_NOTRACKS');
		if ($::VERSION ge '6.5') {
			$client->showBriefly({
				'line'    => [ undef, $line2 ],
				'overlay' => [ undef, $client->symbols('notesymbol') ],
			});
		}else {
			$client->showBriefly({
				'line1' => undef,
				'line2' => $line2,
				'overlay2' => $client->symbols('notesymbol')
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
	            my $sql = prepareMenuSQL($item->{'playdata'},$keywords);
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
	if(!defined($subCall) && $command eq 'loadtracks') {
		$wasShuffled = Slim::Player::Playlist::shuffle($client);
		Slim::Player::Playlist::shuffle($client, 0);
		$pos = 0;
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
			if ($::VERSION ge '6.5' && defined($request)) {
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
		if ($::VERSION ge '6.5' && defined($request)) {
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

    return $originalValue;
}

sub getSQLMenuData {
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
		
		$templateDir = Slim::Utils::Prefs::get('plugin_custombrowse_template_directory');
		if($templateDir) {
			push @include_path,$templateDir;
		}

		for my $plugindir (@pluginDirs) {
			next unless -d catdir($plugindir,'CustomBrowse/Templates');
			$templateDir = catdir($plugindir,'CustomBrowse/Templates');
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
		msg("CustomBrowse: ERROR parsing template: ".$template->error()."\n");
	}
	return $output;
}

sub initPlugin {
	my $class = shift;
	
	checkDefaults();
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
		if ($::VERSION ge '6.5') {
			$trackStat = Slim::Utils::PluginManager::enabledPlugin('TrackStat',$client);
		}else {
			$trackStat = grep(/TrackStat/,Slim::Buttons::Plugins::enabledPlugins($client));
		}

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

	readBrowseConfiguration();
	my %submenu = (
		'useMode' => 'PLUGIN.CustomBrowse',
	);
	my $menuName = Slim::Utils::Prefs::get('plugin_custombrowse_menuname');
	if($menuName) {
		Slim::Utils::Strings::addStringPointer( uc 'PLUGIN_CUSTOMBROWSE', $menuName );
	}
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
		Slim::Buttons::Home::addMenuOption($name,\%submenu);
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
	my $items = getMenuItems($client,$item,$params->{'option'});
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
						$url = replaceParameters($url,$keywords);
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

        if ($::VERSION ge '6.5') {
                $item->displayAsHTML($form);
        }else {
                my $ds = getCurrentDS();
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
        $prefVal = Slim::Utils::Prefs::get('plugin_custombrowse_menuname');
	if (! defined $prefVal) {
		my $dir=Slim::Utils::Prefs::get('playlistdir');
		debugMsg("Defaulting plugin_custombrowse_menuname to:".string('PLUGIN_CUSTOMBROWSE')."\n");
		Slim::Utils::Prefs::set('plugin_custombrowse_menuname', string('PLUGIN_CUSTOMBROWSE'));
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
}

sub setupGroup
{
	my %setupGroup =
	(
	 PrefOrder => ['plugin_custombrowse_directory','plugin_custombrowse_template_directory','plugin_custombrowse_menuname','plugin_custombrowse_properties','plugin_custombrowse_showmessages'],
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
	plugin_custombrowse_template_directory => {
			'validate' => \&validateIsDirWrapper
			,'PrefChoose' => string('PLUGIN_CUSTOMBROWSE_TEMPLATE_DIRECTORY')
			,'changeIntro' => string('PLUGIN_CUSTOMBROWSE_TEMPLATE_DIRECTORY')
			,'PrefSize' => 'large'
			,'currentValue' => sub { return Slim::Utils::Prefs::get("plugin_custombrowse_template_directory"); }
		},
	plugin_custombrowse_menuname => {
			'validate' => \&validateAcceptAllWrapper
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
                "custombrowse_editmenus\.(?:htm|xml)"     => \&handleWebEditMenus,
                "custombrowse_editmenu\.(?:htm|xml)"     => \&handleWebEditMenu,
                "custombrowse_savemenu\.(?:htm|xml)"     => \&handleWebSaveMenu,
                "custombrowse_savesimplemenu\.(?:htm|xml)"     => \&handleWebSaveSimpleMenu,
                "custombrowse_savenewmenu\.(?:htm|xml)"     => \&handleWebSaveNewMenu,
                "custombrowse_savenewsimplemenu\.(?:htm|xml)"     => \&handleWebSaveNewSimpleMenu,
                "custombrowse_removemenu\.(?:htm|xml)"     => \&handleWebRemoveMenu,
                "custombrowse_newmenutypes\.(?:htm|xml)"     => \&handleWebNewMenuTypes,
                "custombrowse_newmenuparameters\.(?:htm|xml)"     => \&handleWebNewMenuParameters,
                "custombrowse_newmenu\.(?:htm|xml)"     => \&handleWebNewMenu,
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
		if ($::VERSION ge '6.5') {
			#readBrowseConfiguration();
			addWebMenus($value);
			my $menuName = Slim::Utils::Prefs::get('plugin_custombrowse_menuname');
			if($menuName) {
				Slim::Utils::Strings::addStringPointer( uc 'PLUGIN_CUSTOMBROWSE_CUSTOM_MENUNAME', $menuName );
			}
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
				my $keywords = combineKeywords($browseMenus->{$menu}->{'menu'}->{'keywordparameters'});
				$url = replaceParameters($url,$keywords);
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

	if(defined($context) && scalar(@$context)>0) {
		$params->{'pluginCustomBrowseCurrentContext'} = $context->[scalar(@$context)-1];
	}
        if ($::VERSION ge '6.5') {
                $params->{'pluginCustomBrowseSlimserver65'} = 1;
        }

        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_list.html', $params);
}

sub handleWebEditMenus {
        my ($client, $params) = @_;

	readBrowseConfiguration($client);

	my @menus = ();
	for my $key (keys %$browseMenus) {
		push @menus,$browseMenus->{$key};
	}
	@menus = sort { $a->{'menuname'} cmp $b->{'menuname'} } @menus;
	
        $params->{'pluginCustomBrowseMenus'} = \@menus;

        if ($::VERSION ge '6.5') {
                $params->{'pluginCustomBrowseSlimserver65'} = 1;
        }

        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_editmenus.html', $params);
}

sub handleWebEditMenu {
        my ($client, $params) = @_;

	readBrowseConfiguration($client);
	
        if ($::VERSION ge '6.5') {
		$params->{'pluginCustomBrowseSlimserver65'} = 1;
        }
	my $menuId = $params->{'menu'};
	if(defined($params->{'menu'}) && defined($browseMenus->{$menuId})) {
		if(!defined($browseMenus->{$menuId}->{'simple'})) {
			my $data = undef;

			my $browseDir = Slim::Utils::Prefs::get("plugin_custombrowse_directory");
			if (!defined $browseDir || !-d $browseDir) {
				debugMsg("Skipping custom browse configuration - directory is undefined\n");
			}else {
				$data = loadMenuData($browseDir,$params->{'menu'}.".cb.xml");
			}
			if(!defined($data)) {
				my @pluginDirs = ();
				if ($::VERSION ge '6.5') {
					@pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
				}else {
					@pluginDirs = catdir($Bin, "Plugins");
				}
				for my $plugindir (@pluginDirs) {
					next unless -d catdir($plugindir,"CustomBrowse","Menus");
					$data = loadMenuData(catdir($plugindir,"CustomBrowse","Menus"),$params->{'menu'}.".cb.xml");
					if(defined($data)) {
						last;
					}
				}
			}
			if($data) {
				$data = encode_entities($data);
			}
		        $params->{'pluginCustomBrowseEditMenuData'} = $data;
			$params->{'pluginCustomBrowseEditMenuFile'} = $params->{'menu'}.".cb.xml";
			$params->{'pluginCustomBrowseEditMenuFileUnescaped'} = unescape($params->{'menu'}.".cb.xml");

			return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_editmenu.html', $params);
		}else {
			my $templateData = undef;

			my $browseDir = Slim::Utils::Prefs::get("plugin_custombrowse_directory");
			if (!defined $browseDir || !-d $browseDir) {
				debugMsg("Skipping custom browse configuration - directory is undefined\n");
			}else {
				$templateData = loadTemplateData($browseDir,$params->{'menu'}.".cb.values.xml");
			}
			if(!defined($templateData)) {
				my @pluginDirs = ();
				if ($::VERSION ge '6.5') {
					@pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
				}else {
					@pluginDirs = catdir($Bin, "Plugins");
				}
				for my $plugindir (@pluginDirs) {
					next unless -d catdir($plugindir,"CustomBrowse","Menus");
					$templateData = loadTemplateData(catdir($plugindir,"CustomBrowse","Menus"),$params->{'menu'}.".cb.values.xml");
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
						if(!%valuesHash) {
							$valuesHash{''} = '';
						}
						$currentParameterValues{$p->{'id'}} = \%valuesHash;
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
						$params->{'pluginCustomBrowseEditMenuParameters'} = \@parametersToSelect;
					}
					$params->{'pluginCustomBrowseEditMenuTemplate'} = $templateData->{'id'};
					$params->{'pluginCustomBrowseEditMenuFile'} = $params->{'menu'}.".cb.values.xml";
					$params->{'pluginCustomBrowseEditMenuFileUnescaped'} = unescape($params->{'menu'}.".cb.values.xml");
					return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_editsimplemenu.html', $params);
				}
			}
		}
	}
	return handleWebEditMenus($client,$params);
}

sub handleWebNewMenuTypes {
	my ($client, $params) = @_;
        if ($::VERSION ge '6.5') {
                $params->{'pluginCustomBrowseSlimserver65'} = 1;
        }
	my $templatesHash = readTemplateConfiguration($client);
	my @templates = ();
	for my $key (keys %$templatesHash) {
		push @templates,$templatesHash->{$key};
	}
	@templates = sort { $a->{'name'} cmp $b->{'name'} } @templates;

	$params->{'pluginCustomBrowseTemplates'} = \@templates;
	
        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_newmenutypes.html', $params);
}

sub handleWebNewMenuParameters {
	my ($client, $params) = @_;
        if ($::VERSION ge '6.5') {
                $params->{'pluginCustomBrowseSlimserver65'} = 1;
        }
	$params->{'pluginCustomBrowseNewMenuTemplate'} = $params->{'menutemplate'};
	my $templates = readTemplateConfiguration($client);
	my $template = $templates->{$params->{'menutemplate'}};
	if(defined($template->{'parameter'})) {
		my $parameters = $template->{'parameter'};
		my @parametersToSelect = ();
		for my $p (@$parameters) {
			if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
				addValuesToTemplateParameter($p);
				push @parametersToSelect,$p;
			}
		}
		$params->{'pluginCustomBrowseNewMenuParameters'} = \@parametersToSelect;
	        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_newmenuparameters.html', $params);
	}else {
		return handleWebNewMenu($client,$params);
	}
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
	if($parameter->{'type'} =~ /.*multiplelist$/ || $parameter->{'type'} =~ /.*checkboxes$/) {
		my $selectedValues = undef;
		if($parameter->{'type'} =~ /.*multiplelist$/) {
			$selectedValues = getMultipleListQueryParameter($params,'menuparameter_'.$parameter->{'id'});
		}else {
			$selectedValues = getCheckBoxesQueryParameter($params,'menuparameter_'.$parameter->{'id'});
		}
		my $values = $parameter->{'values'};
		my $result = undef;
		for my $item (@$values) {
			if(defined($selectedValues->{$item->{'id'}})) {
				if(defined($result)) {
					$result = $result.',';
				}
				if($parameter->{'quotevalue'}) {
					$result = $result.$dbh->quote(encode_entities($item->{'value'}));
				}else {
					$result = $result.encode_entities($item->{'value'});
				}
			}
		}
		if(!defined($result)) {
			$result = '';
		}
		return $result;
	}elsif($parameter->{'type'} =~ /.*singlelist$/) {
		my $values = $parameter->{'values'};
		my $selectedValue = $params->{'menuparameter_'.$parameter->{'id'}};
		my $result = undef;
		for my $item (@$values) {
			if($selectedValue eq $item->{'id'}) {
				if($parameter->{'quotevalue'}) {
					$result = $dbh->quote(encode_entities($item->{'value'}));
				}else {
					$result = encode_entities($item->{'value'});
				}
				last;
			}
		}
		if(!defined($result)) {
			$result = '';
		}
		return $result;
	}else{
		if($parameter->{'quotevalue'}) {
			return $dbh->quote(encode_entities($params->{'menuparameter_'.$parameter->{'id'}}));
		}else {
			return encode_entities($params->{'menuparameter_'.$parameter->{'id'}});
		}
	}
}

sub getXMLValueOfTemplateParameter {
	my $params = shift;
	my $parameter = shift;

	my $dbh = getCurrentDBH();
	if($parameter->{'type'} =~ /.*multiplelist$/ || $parameter->{'type'} =~ /.*checkboxes$/) {
		my $selectedValues = undef;
		if($parameter->{'type'} =~ /.*multiplelist$/) {
			$selectedValues = getMultipleListQueryParameter($params,'menuparameter_'.$parameter->{'id'});
		}else {
			$selectedValues = getCheckBoxesQueryParameter($params,'menuparameter_'.$parameter->{'id'});
		}
		my $values = $parameter->{'values'};
		my $result = undef;
		for my $item (@$values) {
			if(defined($selectedValues->{$item->{'id'}})) {
				$result = $result.'<value>';
				if($parameter->{'quotevalue'}) {
					$result = $result.encode_entities($item->{'value'});
				}else {
					$result = $result.encode_entities($item->{'value'});
				}
				$result = $result.'</value>';
			}
		}
		if(!defined($result)) {
			$result = '';
		}
		return $result;
	}elsif($parameter->{'type'} =~ /.*singlelist$/) {
		my $values = $parameter->{'values'};
		my $selectedValue = $params->{'menuparameter_'.$parameter->{'id'}};
		my $result = undef;
		for my $item (@$values) {
			if($selectedValue eq $item->{'id'}) {
				$result = $result.'<value>';
				if($parameter->{'quotevalue'}) {
					$result = encode_entities($item->{'value'});
				}else {
					$result = encode_entities($item->{'value'});
				}
				$result = $result.'</value>';
				last;
			}
		}
		if(!defined($result)) {
			$result = '';
		}
		return $result;
	}else{
		if(defined($params->{'menuparameter_'.$parameter->{'id'}}) && $params->{'menuparameter_'.$parameter->{'id'}} ne '') {
			if($parameter->{'quotevalue'}) {
				return '<value>'.encode_entities($params->{'menuparameter_'.$parameter->{'id'}}).'</value>';
			}else {
				return '<value>'.encode_entities($params->{'menuparameter_'.$parameter->{'id'}}).'</value>';
			}
		}
		return '';
	}
}

sub handleWebNewMenu {
	my ($client, $params) = @_;
        if ($::VERSION ge '6.5') {
                $params->{'pluginCustomBrowseSlimserver65'} = 1;
        }
	my $templateFile = $params->{'menutemplate'};
	my $menuFile = $templateFile;
	$templateFile =~ s/\.xml$/.template/;
	$menuFile =~ s/\.xml$//;
	my $templates = readTemplateConfiguration($client);
	my $template = $templates->{$params->{'menutemplate'}};
	my $menytype = $params->{'menutype'};

	if($menytype eq 'advanced') {
		$menuFile .= ".cb.xml";
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
		my $templateFileData = undef;
		my $doParsing = 1;
		if(defined($template->{'custombrowse_plugin_template'})) {
			my $pluginTemplate = $template->{'custombrowse_plugin_template'};
			if(defined($pluginTemplate->{'type'}) && $pluginTemplate->{'type'} eq 'final') {
				$doParsing = 0;
			}
			$templateFileData = getPluginTemplateData($client,$template,\%templateParameters);
		}else {
			$templateFileData = $templateFile;
		}
		my $menuData = undef;
		if($doParsing) {
			$menuData = fillTemplate($templateFileData,\%templateParameters);
		}else {
			$menuData = $templateFileData;
		}
		$menuData = Slim::Utils::Unicode::utf8on($menuData);
		$menuData = Slim::Utils::Unicode::utf8encode_locale($menuData);
		$menuData = encode_entities($menuData);
		if(length($menuData)>10000) {
			debugMsg("Warning! Large menu configuration, ".length($menuData)." characters\n");
		        $params->{'pluginCustomBrowseEditMenuSizeWarning'} = "This menu configuration is very large, due to size limitations it might fail when you try to save it<br>Temporary solution: If save fails, click back in web browser and copy the information in the Menu configuration field to a text file and save it to the ".Slim::Utils::Prefs::get("plugin_custombrowse_directory")." directory with a filename with extension .cb.xml";
		}
        	$params->{'pluginCustomBrowseEditMenuData'} = $menuData;
		$params->{'pluginCustomBrowseEditMenuFile'} = $menuFile;
		$params->{'pluginCustomBrowseEditMenuFileUnescaped'} = unescape($menuFile);
	        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_newmenu.html', $params);
	}else {
		$menuFile .= ".cb.values.xml";
		my %templateParameters = ();
		for my $p (keys %$params) {
			if($p =~ /^menuparameter_/) {
				$templateParameters{$p}=$params->{$p};
			}
		}
		$params->{'pluginCustomBrowseEditMenuParameters'} = \%templateParameters;
		$params->{'pluginCustomBrowseNewMenuTemplate'} = $params->{'menutemplate'};
		$params->{'pluginCustomBrowseEditMenuFile'} = $menuFile;
		$params->{'pluginCustomBrowseEditMenuFileUnescaped'} = unescape($menuFile);
	        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_newsimplemenu.html', $params);
	}
}

sub handleWebSaveSimpleMenu {
	my ($client, $params) = @_;
        if ($::VERSION ge '6.5') {
                $params->{'pluginCustomBrowseSlimserver65'} = 1;
        }
	my $templateFile = $params->{'menutemplate'};
	my $menuFile = $templateFile;
	$templateFile =~ s/\.xml$/.template/;
	$menuFile =~ s/\.xml$//;
	my $templates = readTemplateConfiguration($client);
	my $template = $templates->{$params->{'menutemplate'}};
	my $menytype = $params->{'menutype'};

	if($menytype eq 'advanced') {
		$menuFile .= ".cb.xml";
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
		my $templateFileData = undef;
		my $doParsing = 1;
		if(defined($template->{'custombrowse_plugin_template'})) {
			my $pluginTemplate = $template->{'custombrowse_plugin_template'};
			if(defined($pluginTemplate->{'type'}) && $pluginTemplate->{'type'} eq 'final') {
				$doParsing = 0;
			}
			$templateFileData = getPluginTemplateData($client,$template,\%templateParameters);
		}else {
			$templateFileData = $templateFile;
		}
		my $menuData = undef;
		if($doParsing) {
			$menuData = fillTemplate($templateFileData,\%templateParameters);
		}else {
			$menuData = $templateFileData;
		}
		$menuData = Slim::Utils::Unicode::utf8on($menuData);
		$menuData = Slim::Utils::Unicode::utf8encode_locale($menuData);
		$menuData = encode_entities($menuData);
		if(length($menuData)>10000) {
			debugMsg("Warning! Large menu configuration, ".length($menuData)." characters\n");
		        $params->{'pluginCustomBrowseEditMenuSizeWarning'} = "This menu configuration is very large, due to size limitations it might fail when you try to save it<br>Temporary solution: If save fails, click back in web browser and copy the information in the Menu configuration field to a text file and save it to the ".Slim::Utils::Prefs::get("plugin_custombrowse_directory")." directory with a filename with extension .cb.xml";
		}
        	$params->{'pluginCustomBrowseEditMenuData'} = $menuData;
		$params->{'pluginCustomBrowseEditMenuDeleteSimple'} = $params->{'file'};
		$params->{'pluginCustomBrowseEditMenuFile'} = $menuFile;
		$params->{'pluginCustomBrowseEditMenuFileUnescaped'} = unescape($menuFile);
	        return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_editmenu.html', $params);
	}else {
		$params->{'pluginCustomBrowseError'} = undef;
	
		if (!$params->{'file'}) {
			$params->{'pluginCustomBrowseError'} = 'Filename is mandatory';
		}
	
		my $browseDir = Slim::Utils::Prefs::get("plugin_custombrowse_directory");
		
		if (!defined $browseDir || !-d $browseDir) {
			$params->{'pluginCustomBrowseError'} = 'No custom menu dir configured';
		}
		my $file = unescape($params->{'file'});
		my $url = catfile($browseDir, $file);
		
		if(!saveSimpleMenu($client,$params,$url)) {
			return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_editsimplemenu.html', $params);
		}else {
			return handleWebEditMenus($client,$params)
		}
	}
}

sub handleWebRemoveMenu {
	my ($client, $params) = @_;
        if ($::VERSION ge '6.5') {
                $params->{'pluginCustomBrowseSlimserver65'} = 1;
        }
	my $browseDir = Slim::Utils::Prefs::get("plugin_custombrowse_directory");
	my $file = unescape($params->{'menu'});
	if(defined($browseMenus->{$params->{'menu'}}->{'simple'})) {
		$file .= ".cb.values.xml";
	}else {
		$file .= ".cb.xml";
	}
	my $url = catfile($browseDir, $file);
	if(defined($browseDir) && -d $browseDir && $file && -e $url) {
		unlink($url) or do {
			warn "Unable to delete file: ".$url.": $! \n";
		}
	}		
        return handleWebEditMenus($client,$params);
}

sub handleWebSaveNewSimpleMenu {
	my ($client, $params) = @_;
	$params->{'pluginCustomBrowseError'} = undef;

	if (!$params->{'file'}) {
		$params->{'pluginCustomBrowseError'} = 'All fields are mandatory';
	}

	my $browseDir = Slim::Utils::Prefs::get("plugin_custombrowse_directory");
	
	if (!defined $browseDir || !-d $browseDir) {
		$params->{'pluginCustomBrowseError'} = 'No custom menu dir configured';
	}
	my $file = unescape($params->{'file'});
	my $url = catfile($browseDir, $file);
	
	if(!defined($params->{'pluginCustomBrowseError'}) && -e $url) {
		$params->{'pluginCustomBrowseError'} = 'Invalid filename, file already exist';
	}

	if(!saveSimpleMenu($client,$params,$url)) {
		return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_newsimplemenu.html', $params);
	}else {
		return handleWebEditMenus($client,$params)
	}
}

sub handleWebSaveNewMenu {
	my ($client, $params) = @_;
	$params->{'pluginCustomBrowseError'} = undef;

	if (!$params->{'text'} || !$params->{'file'}) {
		$params->{'pluginCustomBrowseError'} = 'All fields are mandatory';
	}

	my $browseDir = Slim::Utils::Prefs::get("plugin_custombrowse_directory");
	
	if (!defined $browseDir || !-d $browseDir) {
		$params->{'pluginCustomBrowseError'} = 'No custom menu dir configured';
	}
	my $file = unescape($params->{'file'});
	my $url = catfile($browseDir, $file);
	
	if(!defined($params->{'pluginCustomBrowseError'}) && -e $url) {
		$params->{'pluginCustomBrowseError'} = 'Invalid filename, file already exist';
	}

	if(!saveMenu($client,$params,$url)) {
		return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_newmenu.html', $params);
	}else {
		return handleWebEditMenus($client,$params)
	}
}

sub handleWebSaveMenu {
	my ($client, $params) = @_;
	$params->{'pluginCustomBrowseError'} = undef;

	if (!$params->{'text'} || !$params->{'file'}) {
		$params->{'pluginCustomBrowseError'} = 'All fields are mandatory';
	}

	my $browseDir = Slim::Utils::Prefs::get("plugin_custombrowse_directory");
	
	if (!defined $browseDir || !-d $browseDir) {
		$params->{'pluginCustomBrowseError'} = 'No custom menu dir configured';
	}
	my $file = unescape($params->{'file'});
	my $url = catfile($browseDir, $file);
	
	#my $playlist = getPlayList($client,escape($params->{'name'},"^A-Za-z0-9\-_"));
	#if($playlist && $playlist->{'file'} ne unescape($params->{'file'})) {
	#	$params->{'pluginSQLPlayListError'} = 'Playlist with that name already exists';
	#}
	if(!saveMenu($client,$params,$url)) {
		return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowse/custombrowse_editmenu.html', $params);
	}else {
		if(defined($params->{'deletesimple'})) {
			my $file = unescape($params->{'deletesimple'});
			my $url = catfile($browseDir, $file);
			if(-e $url) {
				unlink($url) or do {
					warn "Unable to delete file: ".$url.": $! \n";
				}
			}
		}
		return handleWebEditMenus($client,$params)
	}
}

sub saveMenu 
{
	my ($client, $params, $url) = @_;
	my $fh;

	if(!($url =~ /.*\.cb\.xml$/)) {
		$params->{'pluginCustomBrowseError'} = 'Filename must end with .cb.xml';
	}
	if(!($params->{'pluginCustomBrowseError'})) {
		my %templates = ();
		my $error = parseMenuContent($client,'test',$params->{'text'},\%templates);
		if($error) {
			$params->{'pluginCustomBrowseError'} = "Reading menu configuration: <br>".$error;
		}
	}

	if(!($params->{'pluginCustomBrowseError'})) {
		debugMsg("Opening browse configuration file: $url\n");
		open($fh,"> $url") or do {
	            $params->{'pluginCustomBrowseError'} = 'Error saving menu';
		};
	}
	if(!($params->{'pluginCustomBrowseError'})) {

		debugMsg("Writing to file: $url\n");
		print $fh $params->{'text'};
		debugMsg("Writing to file succeeded\n");
		close $fh;
	}
	
	if($params->{'pluginCustomBrowseError'}) {
		$params->{'pluginCustomBrowseEditMenuFile'} = $params->{'file'};
		$params->{'pluginCustomBrowseEditMenuData'} = $params->{'text'};
		$params->{'pluginCustomBrowseEditMenuFileUnescaped'} = unescape($params->{'pluginCustomBrowseEditMenuFile'});
		if ($::VERSION ge '6.5') {
			$params->{'pluginCustomBrowseSlimserver65'} = 1;
		}
		return undef;
	}else {
		return 1;
	}
}

sub saveSimpleMenu {
	my ($client, $params, $url) = @_;
	my $fh;

	if(!($url =~ /.*\.cb\.values\.xml$/)) {
		$params->{'pluginCustomBrowseError'} = 'Filename must end with .cb.xml';
	}
#	if(!($params->{'pluginCustomBrowseError'})) {
#		my %templates = ();
#		my $error = parseMenuContent($client,'test',$params->{'text'},\%templates);
#		if($error) {
#			$params->{'pluginCustomBrowseError'} = "Reading menu configuration: <br>".$error;
#		}
#	}

	if(!($params->{'pluginCustomBrowseError'})) {
		debugMsg("Opening browse configuration file: $url\n");
		open($fh,"> $url") or do {
	            $params->{'pluginCustomBrowseError'} = 'Error saving menu';
		};
	}
	if(!($params->{'pluginCustomBrowseError'})) {
		my $templates = readTemplateConfiguration($client);
		my $template = $templates->{$params->{'menutemplate'}};
		my %templateParameters = ();
		my $data = "";
		$data .= "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<custombrowse>\n\t<template>\n\t\t<id>".$params->{'menutemplate'}."</id>";
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
		$data .= "\n\t</template>\n</custombrowse>\n";
		debugMsg("Writing to file: $url\n");
		print $fh $data;
		debugMsg("Writing to file succeeded\n");
		close $fh;
	}
	
	if($params->{'pluginCustomBrowseError'}) {
		my %parameters;
		for my $p (keys %$params) {
			if($p =~ /^menuparameter_/) {
				$parameters{$p}=$params->{$p};
			}
		}		
		$params->{'pluginCustomBrowseEditMenuParameters'} = \%parameters;
		$params->{'pluginCustomBrowseEditMenuFile'} = $params->{'file'};
		$params->{'pluginCustomBrowseEditMenuFileUnescaped'} = unescape($params->{'pluginCustomBrowseEditMenuFile'});
		if ($::VERSION ge '6.5') {
			$params->{'pluginCustomBrowseSlimserver65'} = 1;
		}
		return undef;
	}else {
		return 1;
	}
}

sub getMultipleListQueryParameter {
	my $params = shift;
	my $parameter = shift;

	my $query = $params->{url_query};
	my %result = ();
	if($query) {
		foreach my $param (split /\&/, $query) {
			if ($param =~ /([^=]+)=(.*)/) {
				my $name  = unescape($1);
				my $value = unescape($2);
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

# Draws the plugin's select menus web page
sub handleWebSelectMenus {
        my ($client, $params) = @_;

	readBrowseConfiguration($client);
        # Pass on the current pref values and now playing info
        $params->{'pluginCustomBrowseMenus'} = $browseMenus;
        $params->{'pluginCustomBrowseMixes'} = $browseMixes;
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
		next unless -d catdir($plugindir,"CustomBrowse","Templates");
		readTemplateConfigurationFromDir($client,catdir($plugindir,"CustomBrowse","Templates"),\%templates);
	}

	no strict 'refs';
	my @enabledplugins;
	if ($::VERSION ge '6.5') {
		@enabledplugins = Slim::Utils::PluginManager::enabledPlugins();
	}else {
		@enabledplugins = Slim::Buttons::Plugins::enabledPlugins();
	}

	for my $plugin (@enabledplugins) {
		if(UNIVERSAL::can("Plugins::$plugin","getCustomBrowseTemplates") && UNIVERSAL::can("Plugins::$plugin","getCustomBrowseTemplateData")) {
			debugMsg("Getting menu templates for: $plugin\n");
			my $items = eval { &{"Plugins::${plugin}::getCustomBrowseTemplates"}($client) };
			if ($@) {
				debugMsg("Error getting menu templates from $plugin: $@\n");
			}
			for my $item (@$items) {
				my $template = $item->{'template'};
				$template->{'custombrowse_plugin_template'}=$item;
				$template->{'custombrowse_plugin'} = "Plugins::${plugin}";
				my $templateId = $item->{'id'};
				if($plugin =~ /^([^:]+)::.*$/) {
					$templateId = lc($1)."_".$item->{'id'};
				}
				$template->{'id'} = $templateId;
				debugMsg("Adding template: $templateId\n");
				#debugMsg(Dumper($template));
				$templates{$templateId} = $template;
			}
		}
	}
	use strict 'refs';

	my $templateDir = Slim::Utils::Prefs::get('plugin_custombrowse_template_directory');
	if($templateDir && -d $templateDir) {
		readTemplateConfigurationFromDir($client,$templateDir,\%templates);
	}

	return \%templates;
}

sub readTemplateConfigurationFromDir {
    my $client = shift;
    my $browseDir = shift;
    my $templates = shift;
    debugMsg("Loading template configuration from: $browseDir\n");

    my @dircontents = Slim::Utils::Misc::readDirectory($browseDir,"xml");
    for my $item (@dircontents) {

	next if -d catdir($browseDir, $item);

        my $path = catfile($browseDir, $item);

        # read_file from File::Slurp
        my $content = eval { read_file($path) };
	my $error = parseTemplateContent($client,$item,$content,$templates);
	if($error) {
		errorMsg("Unable to read: $path\n");
	}
    }
}
sub parseMenuContent {
	my $client = shift;
	my $item = shift;
	my $content = shift;
	my $menus = shift;
	my $defaultMenu = shift;

	my $menuId = $item;
	$menuId =~ s/\.cb\.xml//;
	my $errorMsg = undef;
        if ( $content ) {
	    $content = Slim::Utils::Unicode::utf8decode($content,'utf8');
            my $xml = eval { 	XMLin($content, forcearray => ["item"], keyattr => []) };
            #debugMsg(Dumper($xml));
            if ($@) {
		    $errorMsg = "$@";
                    errorMsg("CustomBrowse: Failed to parse menu configuration because:\n$@\n");
            }else {
		my $include = isMenuEnabled($client,$xml);

		my $disabled = 0;
		if(defined($xml->{'menu'})) {
			$xml->{'menu'}->{'id'} = $menuId;
		}
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
			if($defaultMenu) {
				$xml->{'menu'}->{'defaultmenu'} = 1;
			}
	                $menus->{$menuId} = $xml->{'menu'};
		}elsif($include && $disabled) {
			$xml->{'menu'}->{'enabled'}=0;
			$xml->{'menu'}->{'enabledbrowse'}=0;
			if($defaultMenu) {
				$xml->{'menu'}->{'defaultmenu'} = 1;
			}
	                $menus->{$menuId} = $xml->{'menu'};
		}
            }
    
            # Release content
            undef $content;
        }else {
            if ($@) {
                    $errorMsg = "Incorrect information in menu data: $@";
                    errorMsg("CustomBrowse: Unable to read menu configuration:\n$@\n");
            }else {
		$errorMsg = "Incorrect information in menu data";
                errorMsg("CustomBrowse: Unable to to read menu configuration\n");
            }
        }
	return $errorMsg;
}

sub parseMenuTemplateContent {
	my $client = shift;
	my $item = shift;
	my $content = shift;
	my $menus = shift;
	my $defaultMenu = shift;
	my $templates = shift;
	my $dbh = getCurrentDBH();

	my $menuId = $item;
	$menuId =~ s/\.cb\.values\.xml//;
	my $errorMsg = undef;
        if ( $content ) {
		$content = Slim::Utils::Unicode::utf8decode($content,'utf8');
		my $valuesXml = eval { XMLin($content, forcearray => ["parameter","value"], keyattr => []) };
		#debugMsg(Dumper($valuesXml));
		if ($@) {
			$errorMsg = "$@";
			errorMsg("CustomBrowse: Failed to parse menu configuration because:\n$@\n");
		}else {
			my $templateId = $valuesXml->{'template'}->{'id'};
			my $template = $templates->{$templateId};
			$templateId =~s/\.xml//;
			my $include = undef;
			if($template) {
				$include = 1;
			}
			my $templateFile = $templateId.".template";
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
						$value .= $dbh->quote(encode_entities($v));
					}else {
						$value .= encode_entities($v);
					}
				}
				#debugMsg("Setting: ".$p->{'id'}."=".$value."\n");
				$templateParameters{$p->{'id'}}=$value;
			}
			if(defined($template->{'parameter'})) {
				my $parameters = $template->{'parameter'};
				for my $p (@$parameters) {
					if(defined($p->{'type'}) && defined($p->{'id'}) && defined($p->{'name'})) {
						if(!defined($templateParameters{$p->{'id'}})) {
							my $value = $p->{'value'};
							if(!defined($value)) {
								$value='';
							}
							debugMsg("Setting default value ".$p->{'id'}."=".$value."\n");
							$templateParameters{$p->{'id'}} = $value;
						}
					}
				}
			}
			my $templateFileData = undef;
			my $doParsing = 1;
			if(defined($template->{'custombrowse_plugin_template'})) {
				my $pluginTemplate = $template->{'custombrowse_plugin_template'};
				if(defined($pluginTemplate->{'type'}) && $pluginTemplate->{'type'} eq 'final') {
					$doParsing = 0;
				}
				$templateFileData = getPluginTemplateData($client,$template,\%templateParameters);
			}else {
				$templateFileData = $templateFile;
			}
			my $menuData = undef;
			if($doParsing) {
				$menuData = fillTemplate($templateFileData,\%templateParameters);
			}else {
				$menuData = $templateFileData;
			}
			$menuData = Slim::Utils::Unicode::utf8on($menuData);
			$menuData = Slim::Utils::Unicode::utf8encode_locale($menuData);
			#$menuData = encode_entities($menuData);
			
			my $xml = eval { 	XMLin($menuData, forcearray => ["item"], keyattr => []) };
			#debugMsg(Dumper($xml));
			if ($@) {
				$errorMsg = "$@";
				errorMsg("CustomBrowse: Failed to parse menu configuration because:\n$@\n");
			}else {
				my $disabled = 0;
				if(defined($xml->{'menu'})) {
					$xml->{'menu'}->{'id'} = $menuId;
				}
	
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
			
				$xml->{'menu'}->{'simple'} = 1;
				if($include && !$disabled) {
					$xml->{'menu'}->{'enabled'}=1;
					if($disabledBrowse) {
						$xml->{'menu'}->{'enabledbrowse'}=0;
					}else {
						$xml->{'menu'}->{'enabledbrowse'}=1;
					}
					if($defaultMenu) {
						$xml->{'menu'}->{'defaultmenu'} = 1;
					}
			                $menus->{$menuId} = $xml->{'menu'};
				}elsif($include && $disabled) {
					$xml->{'menu'}->{'enabled'}=0;
					$xml->{'menu'}->{'enabledbrowse'}=0;
					if($defaultMenu) {
						$xml->{'menu'}->{'defaultmenu'} = 1;
					}
			                $menus->{$menuId} = $xml->{'menu'};
				}
			}
	    
			# Release content
			undef $menuData;
			undef $content;
		}
	}else {
		$errorMsg = "Incorrect information in menu data";
		errorMsg("CustomBrowse: Unable to to read menu configuration\n");
	}
	return $errorMsg;
}

sub parseMixContent {
	my $client = shift;
	my $item = shift;
	my $content = shift;
	my $mixes = shift;
	my $defaultMix = shift;

	my $mixId = $item;
	$mixId =~ s/\.cb\.mix\.xml//;
	my $errorMsg = undef;
        if ( $content ) {
	    $content = Slim::Utils::Unicode::utf8decode($content,'utf8');
            my $xml = eval { 	XMLin($content, forcearray => ["item"], keyattr => []) };
            #debugMsg(Dumper($xml));
            if ($@) {
		    $errorMsg = "$@";
                    errorMsg("CustomBrowse: Failed to parse mix configuration because:\n$@\n");
            }else {
		my $include = isMenuEnabled($client,$xml);

		my $disabled = 0;
		if(defined($xml->{'mix'})) {
			$xml->{'mix'}->{'id'} = $mixId;
		}
		if(defined($xml->{'mix'}) && defined($xml->{'mix'}->{'id'})) {
			my $enabled = Slim::Utils::Prefs::get('plugin_custombrowse_mix_'.escape($xml->{'mix'}->{'id'}).'_enabled');
			if(defined($enabled) && !$enabled) {
				$disabled = 1;
			}elsif(!defined($enabled)) {
				if(defined($xml->{'defaultdisabled'}) && $xml->{'defaultdisabled'}) {
					$disabled = 1;
				}
			}
		}
		
		if($include && !$disabled) {
			$xml->{'mix'}->{'enabled'}=1;
			if($defaultMix) {
				$xml->{'mix'}->{'defaultmix'} = 1;
			}
	                $mixes->{$mixId} = $xml->{'mix'};
		}elsif($include && $disabled) {
			$xml->{'mix'}->{'enabled'}=0;
			if($defaultMix) {
				$xml->{'mix'}->{'defaultmix'} = 1;
			}
	                $mixes->{$mixId} = $xml->{'mix'};
		}
            }
    
            # Release content
            undef $content;
        }else {
            if ($@) {
                    $errorMsg = "Incorrect information in mix data: $@";
                    errorMsg("CustomBrowse: Unable to read mix configuration:\n$@\n");
            }else {
		$errorMsg = "Incorrect information in mix data";
                errorMsg("CustomBrowse: Unable to to read mix configuration\n");
            }
        }
	return $errorMsg;
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
                    errorMsg("CustomBrowse: Failed to parse menu configuration because:\n$@\n");
            }else {
		my $include = isMenuEnabled($client,$xml);
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
                    $errorMsg = "Incorrect information in menu data: $@";
                    errorMsg("CustomBrowse: Unable to read menu configuration:\n$@\n");
            }else {
		$errorMsg = "Incorrect information in menu data";
                errorMsg("CustomBrowse: Unable to to read menu configuration\n");
            }
        }
	return $errorMsg;
}

sub isMenuEnabled {
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

sub readBrowseConfiguration {
    my $client = shift;
    my $browseDir = Slim::Utils::Prefs::get("plugin_custombrowse_directory");
    debugMsg("Searching for custom browse configuration in: $browseDir\n");
    
    my %localBrowseMenus = ();
    my %localBrowseMixes = ();
    my @pluginDirs = ();
    if ($::VERSION ge '6.5') {
        @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
    }else {
        @pluginDirs = catdir($Bin, "Plugins");
    }
    my $templates = readTemplateConfiguration($client);
    for my $plugindir (@pluginDirs) {
	if( -d catdir($plugindir,"CustomBrowse","Menus")) {
		readBrowseConfigurationFromDir($client,1,catdir($plugindir,"CustomBrowse","Menus"),\%localBrowseMenus);
		readBrowseTemplateConfigurationFromDir($client,1,catdir($plugindir,"CustomBrowse","Menus"),\%localBrowseMenus, $templates);
	}
	if( -d catdir($plugindir,"CustomBrowse","Mixes")) {
		readMixConfigurationFromDir($client,1,catdir($plugindir,"CustomBrowse","Mixes"),\%localBrowseMixes);
	}
    }
    if (!defined $browseDir || !-d $browseDir) {
            debugMsg("Skipping custom browse configuration scan - directory is undefined\n");
    }else {
	    readBrowseConfigurationFromDir($client,0,$browseDir,\%localBrowseMenus);
	    readBrowseTemplateConfigurationFromDir($client,0,$browseDir,\%localBrowseMenus, $templates);
	    readMixConfigurationFromDir($client,0,$browseDir,\%localBrowseMixes);
    }
    
    my @menus = ();
    foreach my $menu (keys %localBrowseMenus) {
    	copyKeywords(undef,$localBrowseMenus{$menu});
    }
    $browseMenus = \%localBrowseMenus;
    $browseMixes = \%localBrowseMixes;
}

sub readBrowseConfigurationFromDir {
    my $client = shift;
    my $defaultMenu = shift;
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
		my $errorMsg = parseMenuContent($client,$item,$content,$localBrowseMenus,$defaultMenu);
		if($errorMsg) {
	                errorMsg("CustomBrowse: Unable to open browse configuration file: $path\n$errorMsg\n");
		}
        }else {
            if ($@) {
                    errorMsg("CustomBrowse: Unable to open browse configuration file: $path\nBecause of:\n$@\n");
            }else {
                errorMsg("CustomBrowse: Unable to open browse configuration file: $path\n");
            }
        }
    }
}

sub readBrowseTemplateConfigurationFromDir {
    my $client = shift;
    my $defaultMenu = shift;
    my $browseDir = shift;
    my $localBrowseMenus = shift;
    my $templates = shift;
    debugMsg("Loading browse template configuration from: $browseDir\n");

    my @dircontents = Slim::Utils::Misc::readDirectory($browseDir,"cb.values.xml");
    for my $item (@dircontents) {

	next if -d catdir($browseDir, $item);

        my $path = catfile($browseDir, $item);

        # read_file from File::Slurp
        my $content = eval { read_file($path) };
        if ( $content ) {
		my $errorMsg = parseMenuTemplateContent($client,$item,$content,$localBrowseMenus,$defaultMenu, $templates);
		if($errorMsg) {
	                errorMsg("CustomBrowse: Unable to open browse configuration file: $path\n$errorMsg\n");
		}
        }else {
            if ($@) {
                    errorMsg("CustomBrowse: Unable to open browse configuration file: $path\nBecause of:\n$@\n");
            }else {
                errorMsg("CustomBrowse: Unable to open browse configuration file: $path\n");
            }
        }
    }
}

sub readMixConfigurationFromDir {
    my $client = shift;
    my $defaultMenu = shift;
    my $browseDir = shift;
    my $localBrowseMenus = shift;
    debugMsg("Loading mix configuration from: $browseDir\n");

    my @dircontents = Slim::Utils::Misc::readDirectory($browseDir,"cb.mix.xml");
    for my $item (@dircontents) {

	next if -d catdir($browseDir, $item);

        my $path = catfile($browseDir, $item);

        # read_file from File::Slurp
        my $content = eval { read_file($path) };
        if ( $content ) {
		my $errorMsg = parseMixContent($client,$item,$content,$localBrowseMenus,$defaultMenu);
		if($errorMsg) {
	                errorMsg("CustomBrowse: Unable to open mix configuration file: $path\n$errorMsg\n");
		}
        }else {
            if ($@) {
                    errorMsg("CustomBrowse: Unable to open mix configuration file: $path\nBecause of:\n$@\n");
            }else {
                errorMsg("CustomBrowse: Unable to open mix configuration file: $path\n");
            }
        }
    }
}

sub loadMenuData {
    my $browseDir = shift;
    my $file = shift;

    debugMsg("Loading menu data from: $browseDir/$file\n");

    my $path = catfile($browseDir, $file);
    
    return unless -f $path;

    my $content = eval { read_file($path) };
    if ($@) {
    	debugMsg("Failed to load menu data because:\n$@\n");
    }
    if(defined($content)) {
	debugMsg("Loading of menu data succeeded\n");
    }
    return $content;
}

sub getPluginTemplateData {
	my $client = shift;
	my $template = shift;
	my $parameters = shift;
	debugMsg("Get template data from plugin\n");
	my $plugin = $template->{'custombrowse_plugin'};
	my $pluginTemplate = $template->{'custombrowse_plugin_template'};
	my $templateFileData = undef;
	no strict 'refs';
	if(UNIVERSAL::can("$plugin","getCustomBrowseTemplateData")) {
		debugMsg("Calling: $plugin :: getCustomBrowseTemplateData\n");
		$templateFileData =  eval { &{"${plugin}::getCustomBrowseTemplateData"}($client,$pluginTemplate,$parameters) };
		if ($@) {
			debugMsg("Error retreiving menu template data from $plugin: $@\n");
		}
	}
	use strict 'refs';
	return \$templateFileData;
}

sub loadTemplateData {
	my $browseDir = shift;
	my $file = shift;
	
	my $content = loadMenuData($browseDir,$file);

        if ( $content ) {
		$content = Slim::Utils::Unicode::utf8decode($content,'utf8');
		my $xml = eval { XMLin($content, forcearray => ["parameter","value"], keyattr => []) };
		#debugMsg(Dumper($valuesXml));
		if ($@) {
			errorMsg("CustomBrowse: Failed to parse menu configuration because:\n$@\n");
		}else {
			return $xml->{'template'}
		}
	}
	return undef;
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
	if($arg eq '' || $arg =~ /^[a-zA-Z0-9_]+\s*=\s*.+$/) {
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

sub objectForId {
	my $type = shift;
	my $id = shift;
	if ($::VERSION ge '6.5') {
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
	}else {
		if($type eq 'playlist') {
			$type = 'track';
		}
		return getCurrentDS()->objectForId($type,$id);
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

PLUGIN_CUSTOMBROWSE_NO_ITEMS_FOUND
	EN	No matching songs, albums or artists were found

PLUGIN_CUSTOMBROWSE_EDIT_MENUS
	EN	Edit menus

PLUGIN_CUSTOMBROWSE_EDIT_MENU_FILENAME
	EN	Filename

PLUGIN_CUSTOMBROWSE_EDIT_MENU_DATA
	EN	Menu configuration

PLUGIN_CUSTOMBROWSE_NEW_MENU_TYPES_TITLE
	EN	Select type of menu to create

PLUGIN_CUSTOMBROWSE_NEW_MENU
	EN	Create new menu

PLUGIN_CUSTOMBROWSE_NEW_MENU_PARAMETERS_TITLE
	EN	Please enter menu parameters

PLUGIN_CUSTOMBROWSE_EDIT_MENU_PARAMETERS_TITLE
	EN	Please enter menu parameters

PLUGIN_CUSTOMBROWSE_REMOVE_MENU_QUESTION
	EN	Are you sure you want to delete this menu ?

PLUGIN_CUSTOMBROWSE_REMOVE_MENU
	EN	Delete

PLUGIN_CUSTOMBROWSE_MIX_NOTRACKS
	EN	Unable to create mix

PLUGIN_CUSTOMBROWSE_REFRESH
	EN	Refresh

PLUGIN_CUSTOMBROWSE_MENUTYPE
	EN	Customize configuration

PLUGIN_CUSTOMBROWSE_MENUTYPE_SIMPLE
	EN	Use predefined

PLUGIN_CUSTOMBROWSE_MENUTYPE_ADVANCED
	EN	Customize

PLUGIN_CUSTOMBROWSE_TRACKSTAT
	EN	TrackStat

PLUGIN_CUSTOMBROWSE_TRACKSTAT_RATING
	EN	Rating:
EOF

}

1;

__END__
