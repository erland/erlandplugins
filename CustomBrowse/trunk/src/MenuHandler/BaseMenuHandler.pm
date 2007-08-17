# 			MenuHandler::BaseMenuHandler module
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

package Plugins::CustomBrowse::MenuHandler::BaseMenuHandler;

use strict;

use base 'Class::Data::Accessor';

use Plugins::CustomBrowse::MenuHandler::MixHandler;
use File::Spec::Functions qw(:ALL);
use POSIX qw(ceil);
use Text::Unidecode;
use HTML::Entities;

__PACKAGE__->mk_classaccessors( qw(debugCallback errorCallback pluginId pluginVersion mixHandler propertyHandler itemParameterHandler items menuTitle menuMode menuHandlers overlayCallback displayTextCallback requestSource playHandlers showMixBeforeExecuting sqlHandler) );

use Data::Dumper;

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = {
		'debugCallback' => $parameters->{'debugCallback'},
		'errorCallback' => $parameters->{'errorCallback'},
		'pluginId' => $parameters->{'pluginId'},
		'pluginVersion' => $parameters->{'pluginVersion'},
		'propertyHandler' => $parameters->{'propertyHandler'},
		'itemParameterHandler' => $parameters->{'itemParameterHandler'},
		'menuTitle' => $parameters->{'menuTitle'},
		'menuMode' => $parameters->{'menuMode'},
		'menuHandlers' => $parameters->{'menuHandlers'},
		'overlayCallback' => $parameters->{'overlayCallback'},
		'displayTextCallback' => $parameters->{'displayTextCallback'},
		'playHandlers' => $parameters->{'playHandlers'},
		'requestSource' => $parameters->{'requestSource'},
		'showMixBeforeExecuting' => $parameters->{'showMixBeforeExecuting'},
		'sqlHandler' => $parameters->{'sqlHandler'},
	};

	my %parameters = (
		'debugCallback' => $parameters->{'debugCallback'},
		'errorCallback' => $parameters->{'errorCallback'},
		'pluginId' => $parameters->{'pluginId'},
		'pluginVersion' => $parameters->{'pluginVersion'},
		'propertyHandler' => $parameters->{'propertyHandler'},
		'itemParameterHandler' => $parameters->{'itemParameterHandler'},
		'mixHandlers' => $parameters->{'mixHandlers'}
	);
	$self->{'mixHandler'} = Plugins::CustomBrowse::MenuHandler::MixHandler->new(\%parameters);

	$self->{'items'} = undef;
	bless $self,$class;
	return $self;
}

sub getMenuItems {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $context = shift;
	my $interfaceType = shift;

	if(!defined($interfaceType)) {
		$interfaceType = 'player';
	}	
	return $self->_getMenuItems($client,$item,undef,undef,$context,$interfaceType);
}

sub _getFunctionMenu {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $context = shift;
	my $parameters = shift;

	my $result = undef;
	my @functions = split(/\|/,$item->{'menufunction'});
	if(scalar(@functions)>0) {
		my $dataFunction = @functions->[0];
		if($dataFunction =~ /^(.+)::([^:].*)$/) {
			my $class = $1;
			my $function = $2;

			shift @functions;
			my $keywords = _combineKeywords($item->{'keywordparameters'},$item->{'parameters'},$parameters);
			my %empty = ();
			for my $item (@functions) {
				if($item =~ /^(.+)=(.*)$/) {
					$keywords->{$1}=$self->itemParameterHandler->replaceParameters($client,$2,$keywords,$context);;
				}
			}
			if(UNIVERSAL::can("$class","$function")) {
				$self->debugCallback->("Calling ${class}->${function}\n");
				no strict 'refs';
				$result = eval { $class->$function($client,$keywords) };
				if ($@) {
					$self->debugCallback->("Error calling ${class}->${function}: $@\n");
				}
			}
		}
	}
	return $result;
}

sub _getFunctionItemFormat {
	my $self = shift;
	my $client = shift;
	my $item = shift;

	my $result = undef;
	my @functions = split(/\|/,$item->{'itemformatdata'});
	if(scalar(@functions)>0) {
		my $dataFunction = @functions->[0];
		if($dataFunction =~ /^(.+)::([^:].*)$/) {
			my $class = $1;
			my $function = $2;

			shift @functions;
			my %keywords = ();
			for my $it (@functions) {
				if($it =~ /^(.+)=(.*)$/) {
					$keywords{$1}=$2;
				}
			}
			no strict 'refs';
			if(UNIVERSAL::can("$class","$function")) {
				$self->debugCallback->("Calling ${class}->${function}\n");
				$result = eval { $class->$function($client,$item, \%keywords) };
				if ($@) {
					$self->debugCallback->("Error calling ${class}->${function}: $@\n");
				}
			}
			use strict 'refs';
		}
	}
	return $result;
}

sub _getMenuItems {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $option = shift;
	my $mainBrowseMenu = shift;
	my $context = shift;
	my $interfaceType = shift;
	my $params = shift;

	my @listRef = ();

	# If top menu
	if(!defined($item)) {
		my $browseMenus = $self->items;
		for my $menu (keys %$browseMenus) {
			if(!defined($browseMenus->{$menu}->{'value'})) {
				$browseMenus->{$menu}->{'value'} = $browseMenus->{$menu}->{'id'};
			}

			# Check if menu is enabled
			if($browseMenus->{$menu}->{'enabled'}) {
				if($self->_isMenuEnabledForClient($client,$browseMenus->{$menu}) && 
						$self->_isMenuEnabledForLibrary($client,$browseMenus->{$menu}) && 
						$self->_isMenuEnabledForCheck($client,$browseMenus->{$menu})) {
					push @listRef,$browseMenus->{$menu};
				}		
			}
		}
		$self->_sortMenu(\@listRef);
		return \@listRef;
	# Else, if sub menu
	}
	if(defined($item->{'menufunction'})) {
		my $functionData = $self->_getFunctionMenu($client,$item,$context,$item->{'parameters'});
		if(defined($functionData)) {
			$item->{'menu'} = $functionData;
		}
	}
	if(defined($item->{'menu'})) {
		my @menus = ();

		# Check if menu is enabled
		if(ref($item->{'menu'}) eq 'ARRAY') {
			foreach my $it (@{$item->{'menu'}}) {
				if($self->_isMenuEnabledForClient($client,$it) && 
						$self->_isMenuEnabledForLibrary($client,$it) && 
						$self->_isMenuEnabledForCheck($client,$it)) {

					push @menus,$it;
				}
			}
		}else {
			if($self->_isMenuEnabledForClient($client,$item->{'menu'}) && 
					$self->_isMenuEnabledForLibrary($client,$item->{'menu'}) && 
					$self->_isMenuEnabledForCheck($client,$item->{'menu'})) {

				push @menus,$item->{'menu'};
			}
		}

		# Iterate through enabled menus
		foreach my $menu (@menus) {
			if($menu->{'topmenu'} && ((defined($client) && $client->param('mainBrowseMenu')) || $mainBrowseMenu)) {
				if(!$menu->{'enabledbrowse'}) {
					next;
				}
			}
			if(defined($interfaceType) && ($interfaceType eq 'cli' || $interfaceType eq 'player') && defined($menu->{'itemformat'}) && ($menu->{'itemformat'} =~ /image$/ || $menu->{'itemformat'} =~ /url$/)) {
				next;
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
					if(defined($menu->{'contextid'})) {
						$menuItem{'parameters'}->{$menu->{'contextid'}} = $menu->{'contextid'};
					}elsif(defined($menu->{'id'})) {
						$menuItem{'parameters'}->{$menu->{'id'}} = $menu->{'id'};
					}
				}
				push @listRef, \%menuItem;
	
			}else {
				my $menuHandler = $self->menuHandlers->{$menu->{'menutype'}};
				if(defined($menuHandler)) {
					my $params = $menuHandler->prepareMenu($client,$menu,$item,$option,\@listRef,$context,$params);
					if(defined($params)) {
						return $params;
					}
				}
			}
		}
    	}
	return \@listRef;
}

sub _combineKeywords {
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


sub _isMenuEnabledForClient {
	my $self = shift;
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

sub _isMenuEnabledForCheck {
	my $self = shift;
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
						$self->debugCallback->("Checking menu enabled with: $function\n");
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

sub _isMenuEnabledForLibrary {
	my $self = shift;
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

sub getMenu {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $context = shift;
	my $interfaceType = shift;

	if(!defined($interfaceType)) {
		$interfaceType = 'player';
	}
	my $selectedMenu = $client->param('selectedMenu');

	if(!defined($item) && defined($selectedMenu)) {
		my $browseMenus = $self->items;
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
	my $items = $self->getMenuItems($client,$item,$context,$interfaceType);
	if(ref($items) eq 'ARRAY') {
		@listRef = @$items;
	}else {
		return $items;     
	}
    
	if(scalar(@listRef)==0) {
		return undef;
	}

	my $modeNamePostFix = '';
    	my $menuTitle = $self->menuTitle;
	if(defined($item)) {
		$modeNamePostFix = $item->{'value'};
		$menuTitle = $self->getItemText($client,$item,$context);
	}

	my $sorted = '0';
	if(!defined($item)) {
		$sorted = 'L';
	}else {
		if(defined($item->{'menu'}) && ref($item->{'menu'}) eq 'ARRAY') {
			my $menuArray = $item->{'menu'};
			for my $it (@$menuArray) {
				my $menulinks = $self->_getMenuLinks($it);
				if(defined($menulinks) && $menulinks eq 'alpha') {
					$sorted = 'L';
					last;
				}
			}
		}elsif(defined($item->{'menu'})) {
			my $menulinks = $self->_getMenuLinks($item->{'menu'});
			if(defined($menulinks) && $menulinks eq 'alpha') {
				$sorted = 'L';
			}
		}
	}

	my %params = (
		header     => 
			sub {
				my $client = shift;
				my $item = shift;
				return $self->getHeaderText($client,$item,$client->param($self->pluginId.".context"));
			},
		listRef    => \@listRef,
		menuTitle  => $menuTitle,
		mainBrowseMenu => $client->param('mainBrowseMenu'),
		lookupRef  => 
			sub {
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
		name       => $self->displayTextCallback,
		overlayRef => $self->overlayCallback,
		modeName   => 'PLUGIN.'.$self->pluginId.$modeNamePostFix,
		parentMode => Slim::Buttons::Common::param($client,'parentMode'),
		onCreateMix => 
			sub {
				my ($client, $item) = @_;
				$self->_createMix($client, $item);
			},				
		onInsert => 
			sub {
				my ($client, $item) = @_;
				$self->_playAddItem($client,
					Slim::Buttons::Common::param($client, 'listRef'),
					$item,'inserttracks','INSERT_TO_PLAYLIST');
			},				
		onPlay => 
			sub {
				my ($client, $item) = @_;
				my $string;		
				if (Slim::Player::Playlist::shuffle($client)) {
					$string = 'PLAYING_RANDOMLY_FROM';
				} else {
					$string = 'NOW_PLAYING_FROM';
				}
				$self->_playAddItem($client,
					Slim::Buttons::Common::param($client, 'listRef'),
					$item,'loadtracks',$string);
			},
		onAdd => 
			sub {
				my ($client, $item) = @_;
				$self->_playAddItem($client,
					Slim::Buttons::Common::param($client, 'listRef'),
					$item,'addtracks','ADDING_TO_PLAYLIST');
			},
		onRight => 
			sub {
				my ($client, $item) = @_;
				my $context = $client->param($self->pluginId.".context");
				my $params = $self->getMenu($client,$item,$context);
				if(defined($params)) {
					if(defined($params->{'useMode'})) {
						Slim::Buttons::Common::pushModeLeft($client, $params->{'useMode'}, 
							$params->{'parameters'});
					}else {
						Slim::Buttons::Common::pushModeLeft($client, $self->menuMode, $params);

					}
				}else {
					$client->bumpRight();
				}
			},
	);

	if(defined($context)) {
		$params{$self->pluginId.".context"} = $context;
	}
	return \%params;
}

sub getHeaderText {
	my ($self,$client, $item, $context) = @_;
	if(defined($item->{'menuheader'})) {
		my $menuTitle = $item->{'menuheader'};
		my $listIndex = $client->param('listIndex');
		my $listRef = $client->param('listRef');
		my %standardParameters = (
			'count' => ' ('.($listIndex+1).' '.$client->string('OF').' '.scalar(@$listRef).')'
		);
		my $keywords = _combineKeywords($item->{'parameters'},\%standardParameters);
		$menuTitle = $self->itemParameterHandler->replaceParameters($client,$menuTitle,$keywords,$context);
		return $menuTitle;
	}else {
		return $client->param('menuTitle').' {count}';
	}
}

sub _getMenuLinks {
	my $self = shift;
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

sub getPageItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $contextParams = shift;
	my $checkContextType = shift;
	my $interfaceType = shift;

	if(!defined($interfaceType)) {
		$interfaceType eq 'web';
	}
	my $currentItems =  $self->items;

	my $item = undef;
	my $contextItems = $self->getContext($client,$params);
	my @contexts = @$contextItems;

	my $context = undef;
	my $currentMenu = undef;
	if(scalar(@contexts)>0) {
		$context = @contexts[scalar(@contexts)-1];
		my $contextItem = $context->{'item'};
		my %resultItem = ();
		for my $key (keys %$contextItem) {
			$resultItem{$key} = $contextItem->{$key};
		}
		$resultItem{'parameters'} = $context->{'parameters'};
		if(!defined($resultItem{'itemid'})) {
			my $id = undef;
			if(defined($resultItem{'contextid'})) {
				$id = $resultItem{'contextid'};
			}elsif(defined($resultItem{'id'})) {
				$id = $resultItem{'id'};
			}
			if(defined($id)) {
				$resultItem{'itemid'} = $context->{'parameters'}->{$id};
			}
		}
		$item = \%resultItem;
	}
	return $item;
}

sub getPageItemsForContext {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $contextParams = shift;
	my $checkContextType = shift;
	my $interfaceType = shift;

	if(!defined($interfaceType)) {
		$interfaceType eq 'web';
	}
	my $currentItems =  $self->items;

	my $item = undef;
	my $contextItems = $self->getContext($client,$params);
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
	my $items = undef;
	if(defined($currentMenu) || !defined($params->{'hierarchy'})) {
		$items = $self->_getMenuItems($client,$item,$params->{'option'},$params->{'mainBrowseMenu'},$contextParams,$interfaceType,$params);
	}
	if(defined($items) && ref($items) eq 'ARRAY') {
		my @resultItems = ();
		my %pagebar = ();
		$result{'pageinfo'}=\%pagebar;
		$result{'pageinfo'}->{'totalitems'} = scalar(@$items);
		my $itemsPerPage = Slim::Utils::Prefs::get('itemsPerPage');
		if(defined($params->{'itemsperpage'})) {
			$itemsPerPage = $params->{'itemsperpage'};
		}
		$result{'pageinfo'}->{'itemsperpage'} = $itemsPerPage;
		my $menulinks = $self->_getMenuLinks($currentMenu,$params->{'option'});
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
			if(defined($contextParams) && defined($contextParams->{'itemurl'})) {
				$result{'pageinfo'}->{'otherparams'} .= $contextParams->{'itemurl'};
			}
			if(defined($contextParams) && defined($contextParams->{'noitems'})) {
				$result{'pageinfo'}->{'otherparams'} .= $contextParams->{'noitems'};
			}
		}
		my $count = 0;
		my $prevLetter = '';
		$result{'playable'} = 1;
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
			$it->{'itemname'} = $self->getItemText($client,$it);
			if(defined($it->{'itemseparator'})) {
				my $separator = $it->{'itemseparator'};
				if($it->{'itemname'} =~ /^(.*?)$separator(.*)$/ms) {
					$it->{'itemname'} = $1;
					$it->{'itemvalue'} = $2;
				}
			}
			if(defined($it->{'menu'}) || defined($it->{'menufunction'})) {
				my $hasExternalUrl = undef;
				if(defined($it->{'menu'}) && ref($it->{'menu'}) ne 'ARRAY' && defined($it->{'menu'}->{'menutype'})) {
					my $menuHandler = $self->menuHandlers->{$it->{'menu'}->{'menutype'}};
					if(defined($menuHandler) && $menuHandler->hasCustomUrl($it->{'menu'})) {
						$hasExternalUrl = 1;
						my $customUrl = $menuHandler->getCustomUrl($client,$it,$params,$item,$contextParams);
						if(defined($customUrl)) {
							$it->{'slimserverurl'} = $customUrl;
						}
					}
				}
				if(!$hasExternalUrl) {
					my $id = $it->{'itemid'};
					my $attributeName = undef;
					if(defined($it->{'contextid'})) {
						$attributeName = $it->{'contextid'};
					}
					if(!defined($attributeName)) {
						 $attributeName = $it->{'id'};
					}

					if(defined($context)) {
						if(defined($contextParams) && defined($contextParams->{'hierarchy'})) {
							$it->{'url'}=$contextParams->{'hierarchy'};
						}else {
							$it->{'url'} = $context->{'url'}.',';
						}
						$it->{'url'} .= $attributeName.$context->{'valueUrl'}.'&'.$attributeName.'='.=escape(escape($id));
					}else {
						$it->{'url'}='&hierarchy='.$attributeName.'&'.$attributeName.'='.escape(escape($id));
					}
					if(defined($contextParams)) {
						$it->{'url'} .= $contextParams->{'itemurl'};
						my $regExp = "&"."contexttype=";
						my $type = undef;
						if($contextParams->{'itemurl'} !~ /$regExp/) {
							if(defined($it->{'menuwebcontext'})) {
								$type = escape($it->{'menuwebcontext'});
							}elsif(defined($it->{'itemtype'})) {
								$type = escape($it->{'itemtype'});
							}
							if(defined($type)) {
								$it->{'url'} .= "&contexttype=$type";
							}
						}
						if($checkContextType) {
							my $contextitems = $self->items;
							if(!defined($type) || !defined($contextitems->{'group_'.$type})) {
								$it->{'url'} = undef;
							}
						}
						$regExp = "&"."contextname=";
						if(defined($it->{'url'}) && $contextParams->{'itemurl'} !~ /$regExp/) {
							my $name = undef;
							if(defined($it->{'itemvalue'})) {
								$name = escape($it->{'itemvalue'});
							}else {
								$name = escape($it->{'itemname'});
							}
							$it->{'url'} .= "&contextname=$name";
						}
						$regExp = "&"."contextid=";
						if(defined($it->{'url'}) && $contextParams->{'itemurl'} !~ /$regExp/) {
							my $contextid = undef;
							if(defined($it->{'itemid'})) {
								$contextid = escape($id);
							}
							$it->{'url'} .= "&contextid=$contextid";
						}
					}
					if(defined($it->{'url'}) && ((defined($client) && $client->param('mainBrowseMenu')) || $params->{'mainBrowseMenu'})) {
						$it->{'url'} .= "&mainBrowseMenu=1";
					}
				}
			}
			if(defined($it->{'itemformat'})) {
				my $format = $it->{'itemformat'};
				if($format eq 'track') {
					my $track = Slim::Schema->resultset('Track')->find($it->{'itemid'});
					$track->displayAsHTML($it);
					$result{'artwork'} = 0;
				}elsif($format eq 'trackconcat') {
					my $track = Slim::Schema->resultset('Track')->find($it->{'itemid'});
					$track->displayAsHTML($it);
					delete $it->{'itemobj'};
					$result{'artwork'} = 0;
				}elsif($format eq 'albumconcat' || $format eq 'album') {
					my $album = Slim::Schema->resultset('Album')->find($it->{'itemid'});
					$album->displayAsHTML($it);
					$result{'artwork'} = 1;
				}elsif($format eq 'titleformat' && defined($it->{'itemformatdata'})) {
					$result{'artwork'} = 0;
				}elsif($format eq 'titleformatconcat' && defined($it->{'itemformatdata'})) {
					$result{'artwork'} = 0;
				}elsif($format eq 'function' && defined($it->{'itemformatdata'})) {
					$result{'artwork'} = 0;
				}elsif($format eq 'functionconcat' && defined($it->{'itemformatdata'})) {
					$result{'artwork'} = 0;
				}elsif($format =~ /image$/) {
					my $urlId = $format;
					if(defined($it->{'itemseparator'})) {
						my $separator = $it->{'itemseparator'};
						if($it->{'itemvalue'} =~ /^(.*?)$separator(.*)$/) {
							$it->{'itemvalue'} = $1;
							$it->{$urlId} = $2;
						}
						if(!defined($it->{$urlId})) {
							if(defined($it->{'itemvalue'})) {
								$it->{$urlId} = $it->{'itemvalue'};
							}else {
								$it->{$urlId} = $it->{'itemname'};
							}
						}
						if(defined($it->{'itemformatascii'}) && defined($it->{$urlId})) {
							$it->{$urlId} = unidecode($it->{$urlId});
						}
					}
				}elsif($format =~ /url$/) {
					my $urlId = $format;
					if(defined($it->{'itemseparator'})) {
						my $separator = $it->{'itemseparator'};
						if($it->{'itemvalue'} =~ /^(.*?)$separator(.*)$/) {
							$it->{'itemvalue'} = $1;
							$it->{$urlId} = $2;
						}
					}
					if(!defined($it->{$urlId})) {
						if(defined($it->{'itemvalue'})) {
							$it->{$urlId} = $it->{'itemvalue'};
						}else {
							$it->{$urlId} = $it->{'itemname'};
						}
					}
					if(defined($it->{'itemformatascii'}) && defined($it->{$urlId})) {
						$it->{$urlId} = unidecode($it->{$urlId});
					}
				}else {
					$result{'artwork'} = 0;
				}

			}else {
				$result{'artwork'} = 0;
			}
			if(defined($it->{'itemtype'})) {
				if($it->{'itemtype'} eq "track") {
					$it->{'attributes'} = sprintf('&%s=%d', 'track.id',$it->{'itemid'});
				}else {
					if(!defined($it->{'menu'}) && !defined($it->{'menufunction'})) {
						if($it->{'itemtype'} eq "album") {
							$it->{'attributes'} = sprintf('&%s=%d', 'album.id',$it->{'itemid'});
						}elsif($it->{'itemtype'} eq "artist") {
							$it->{'attributes'} = sprintf('&%s=%d', 'contributor.id',$it->{'itemid'});
						}elsif($it->{'itemtype'} eq "year") {
							$it->{'attributes'} = sprintf('&%s=%d', 'year.id',$it->{'itemid'});
						}elsif($it->{'itemtype'} eq "genre") {
							$it->{'attributes'} = sprintf('&%s=%d', 'genre.id',$it->{'itemid'});
						}elsif($it->{'itemtype'} eq "playlist") {
							$it->{'attributes'} = sprintf('&%s=%d', 'playlist.id',$it->{'itemid'});
						}
					}
				}
			}
			my $mixes = $self->getPreparedMixes($client,$it,$interfaceType);
			if(scalar(@$mixes)>0) {
				$it->{'mixes'} = $mixes;
			}
			if($result{'playable'} && ((defined($it->{'playtype'}) && $it->{'playtype'} eq 'none') || (defined($it->{'playtypeall'}) && $it->{'playtypeall'} eq 'none'))) {
				$result{'playable'} = 0;
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
	my $options = $self->_getMenuOptions($currentMenu);
	if(scalar(@$options)>0) {
		$result{'options'} = $options;
	}
	return \%result;
}

sub getPreparedMixes {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $interfaceType = shift;

	return $self->mixHandler->getPreparedMixes($client,$item,$interfaceType);
}

sub getMixes {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $interfaceType = shift;

	return $self->mixHandler->getMixes($client,$item,$interfaceType);
}

sub getGlobalMixes {
	my $self = shift;
	return $self->mixHandler->getGlobalMixes();
}

sub setGlobalMixes {
	my $self = shift;
	my $mixes = shift;

	return $self->mixHandler->setGlobalMixes($mixes);
}

sub _getMenuOptions {
	my $self = shift;
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

sub getContext {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $realNames = shift;

	my @result = ();

	if(defined($params->{'hierarchy'})) {
		my $groupsstring = unescape($params->{'hierarchy'});
		my @groups = (split /,/, $groupsstring);

		my @itemsArray = ();
		my $currentItems = $self->items;
		for my $key (keys %$currentItems) {
			push @itemsArray,$currentItems->{$key};
		}
		my %parameterContainer = ();
		my $contextItems = $self->_getSubContext($client,$params,\@groups,\@itemsArray,0,\%parameterContainer, $realNames);
		@result = @$contextItems;
	}
	return \@result;
}

sub _getSubContext {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $groups = shift;
	my $currentItems = shift;
	my $level = shift;
	my $parameterContainer = shift;
	my $realNames = shift;

	my @result = ();

	if($groups && scalar(@$groups)>$level) {
		my $group = unescape(@$groups[$level]);
		my $item = undef;
		if(ref($currentItems) eq 'ARRAY') {
			for my $menu (@$currentItems) {
				if(defined($menu->{'contextid'}) && $menu->{'contextid'} eq escape($group)) {
					$item = $menu;
					last;
				}elsif($menu->{'id'} eq escape($group)) {
					$item = $menu;
					last;
				}
			}
		}else {
			if(defined($currentItems->{'contextid'}) && $currentItems->{'contextid'} eq escape($group)) {
				$item = $currentItems;
			}elsif($currentItems->{'id'} eq escape($group)) {
				$item = $currentItems;
			}
		}
		if(defined($item)) {
			my $currentUrl = escape($group);
			my $currentValue = '';
			if(defined($params->{$group})) {
				$currentValue = escape($params->{$group});
			}
			my %parameters = ();
			$parameters{$currentUrl} = unescape($params->{$group}) if defined($params->{$group});
			$parameterContainer->{$currentUrl}=unescape($params->{$group}) if defined($params->{$group});
			my $name;
			if(defined($item->{'menuname'})) {
				$name = $item->{'menuname'};
			}else {
				if(defined($item->{'contextid'})) {
					$name = $item->{'contextid'};
				}else {
					$name = $item->{'id'};
				}
			}
			my %resultItem = (
				'url' => $currentUrl,
				'valueUrl' => '&'.$currentUrl.'='.$currentValue,
				'parameters' => \%parameters,
				'name' => $name,
				'item' => $item,
				'value' => $currentValue,
				'enabled' => 1
			);
			if(!$level) {
				$resultItem{'url'} = '&hierarchy='.$resultItem{'url'};
			}
			push @result, \%resultItem;

			if(defined($item->{'menufunction'})) {
				my $functionData = $self->_getFunctionMenu($client,$item,undef,$parameterContainer);
				if(defined($functionData)) {
					$item->{'menu'} = $functionData;
					if(defined($item->{'menu'}) && ref($item->{'menu'}) eq 'ARRAY') {
						if(defined($item->{'menu'}->[0]->{'menuname'})) {
							$resultItem{'name'} = $item->{'menu'}->[0]->{'menuname'};
						}
					}elsif(defined($item->{'menu'})) {
						if(defined($item->{'menu'}->{'menuname'})) {
							$resultItem{'name'} = $item->{'menu'}->{'menuname'};
						}
					}
				}
			}
			if(defined($realNames) && $realNames) {
				if(defined($item->{'pathtype'})) {
					if($item->{'pathtype'} eq 'sql') {
						my $data = $item->{'pathtypedata'};
						my %context = (
							'itemid' => $currentValue
						);
						my $result = $self->sqlHandler->getData($client,$data,$parameterContainer,\%context);
						if(scalar(@$result)>0) {
							$resultItem{'name'} = $result->[0]->{'name'};
						}
					}elsif($item->{'pathtype'} eq 'none') {
						$resultItem{'enabled'} = 0;
					}
				}elsif(defined($item->{'itemtype'})) {
					if($item->{'itemtype'} eq 'artist') {
						my $artist = Slim::Schema->resultset('Contributor')->find($currentValue);
						$resultItem{'name'} = $artist->name;
					}elsif($item->{'itemtype'} eq 'album') {
						my $album = Slim::Schema->resultset('Album')->find($currentValue);
						$resultItem{'name'} = $album->title;
					}elsif($item->{'itemtype'} eq 'genre') {
						my $genre = Slim::Schema->resultset('Genre')->find($currentValue);
						$resultItem{'name'} = $genre->name;
					}elsif($item->{'itemtype'} eq 'year') {
						$resultItem{'name'} = $currentValue;
					}elsif($item->{'itemtype'} eq 'track') {
						my $track = Slim::Schema->resultset('Track')->find($currentValue);
						$resultItem{'name'} = Slim::Music::Info::standardTitle(undef, $track);
					}
				}
			}
			if(defined($item->{'menu'})) {
				my $childResult = $self->_getSubContext($client,$params,$groups,$item->{'menu'},$level+1,$parameterContainer,$realNames);
				for my $child (@$childResult) {
					if(!$level) {
						$child->{'url'} = '&hierarchy='.$currentUrl.','.$child->{'url'};;
					}else {
						$child->{'url'} = $currentUrl.','.$child->{'url'};
					}
					$child->{'valueUrl'} = '&'.$currentUrl.'='.$currentValue.$child->{'valueUrl'};
					$child->{'parameters'}->{$currentUrl} = unescape($params->{$group}) if defined($params->{$group});
					push @result,$child;
				}
			}
		}
	}
	return \@result;
}

sub setMenuItems {
	my $self = shift;
	my $menus = shift;
	my %localMenuItems = ();
	my @localMenuItemsArray  = ();

	for my $menuKey (keys %$menus) {
		my $menu = $menus->{$menuKey};
		$self->copyKeywords(undef,$menu);
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
				#$self->debugCallback->("Got group: ".$grouppath."\n");
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
					$self->_sortMenu($currentLevel);
					$currentLevel = \@level;
				}
			}
			push @$currentLevel,$menu;
			$self->_sortMenu($currentLevel);
		}else {
			push @localMenuItemsArray,$menu
		}
	}
	for my $item (@localMenuItemsArray) {
		$localMenuItems{$item->{'id'}} = $item;
	}
	$self->items(\%localMenuItems);
}

sub _sortMenu {
	my $self = shift;
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

sub _createMix {
	my ($self,$client,$item) = @_;

	my $mixes = $self->mixHandler->getMixes($client,$item,'player');
	for my $mix (@$mixes) {
		$self->debugCallback->("Got mix: ".$mix->{'mixname'}."\n");
	}

	if(!$self->showMixBeforeExecuting && scalar(@$mixes)==1) {
		$self->executeMix($client,$mixes->[0],undef,$item);
	}elsif(scalar(@$mixes)>0) {
		my $params = {
			'header'     => '{CREATE_MIX} {count}',
			'listRef'    => $mixes,
			'name'       => sub { return $_[1]->{'mixname'} },
			'overlayRef' => sub { return [undef, Slim::Display::Display::symbol('rightarrow')] },
			'item'       => $item,
			'onPlay'     => sub { 
						my ($client,$item) = @_;
						$self->executeMix($client,$item);
					},
			'onAdd'      => sub { 
						my ($client,$item) = @_;
						$self->executeMix($client,$item,1);
					},
			'onRight'    => sub { 
						my ($client,$item) = @_;
						$self->executeMix($client,$item,0);
					}
		};
	
		Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', $params);
	}else {
		$self->debugCallback->("No mixes configured for this item\n");
	}
}

sub executeMix {
        my ($self, $client, $mixer, $addOnly,$item, $interfaceType) = @_;

	if(!defined($item)) {
		$item = $client->param('item');
	}
	if(!defined($interfaceType)) {
		$interfaceType='player';
	}
	$self->debugCallback->("Creating mixer ".$mixer->{'mixname'}." for ".$item->{'itemname'}."\n");

	my $parameters = $self->propertyHandler->getProperties();
	$parameters->{'itemid'} = $item->{'itemid'};
	$parameters->{'itemname'} = $item->{'itemname'};
	$parameters->{'itemtype'} = $item->{'itemtype'};
	my $keywords = _combineKeywords($item->{'keywordparameters'},$item->{'parameters'},$parameters);

	$self->mixHandler->executeMix($client,$mixer,$keywords,$interfaceType,$addOnly);
}

sub getItemOverlay {
	my $self = shift;
	my $client = shift;
	my $item = shift;

	my $playable = undef;
	if(defined($item->{'itemtype'})) {
		if($item->{'itemtype'} eq "track" || $item->{'itemtype'} eq "album" || $item->{'itemtype'} eq "artist" || $item->{'itemtype'} eq "year" || $item->{'itemtype'} eq "genre"  || $item->{'itemtype'} eq "playlist") {
			$playable = Slim::Display::Display::symbol('notesymbol');
		}
	}
	my $mixes = $self->mixHandler->getMixes($client,$item,'player');
	if(scalar(@$mixes)>0) {
		$playable = Slim::Display::Display::symbol('mixable');
	}
	if((defined($item->{'menu'}) && ref($item->{'menu'}) eq 'ARRAY') || defined($item->{'menufunction'})) {
		return [$playable, Slim::Display::Display::symbol('rightarrow')];
	}elsif(defined($item->{'menu'}) && defined($item->{'menu'}->{'menutype'})) {
		my $menuHandler = $self->menuHandlers->{$item->{'menu'}->{'menutype'}};
		return [$playable, $menuHandler->getOverlay($item->{'menu'})];
	}
	return [$playable, undef];

}
sub hasCustomUrl {
	my $self = shift;
	my $client = shift;
	my $item = shift;

	if(defined($item->{'menutype'})) {
		my $menuHandler = $self->menuHandlers->{$item->{'menutype'}};
		if(defined($menuHandler)) {
			return $menuHandler->hasCustomUrl($item);
		}
	}
	return 0;
}

sub getCustomUrl {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $context = shift;

	if(defined($item->{'menutype'})) {
		my $menuHandler = $self->menuHandlers->{$item->{'menutype'}};
		if(defined($menuHandler)) {
			my %tmp = (
				'menu' => $item
			);
			return $menuHandler->getCustomUrl($client,\%tmp,$context);
		}
	}
	return undef;
}
sub getItemText {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $context = shift;

	if(!defined($item)) {
		return '';
	}
	my $name = '';
	my $format = $item->{'itemformat'};
	my $prefix = '';
	if(defined($format)) {
		if($format eq 'track') {
			my $track = Slim::Schema->resultset('Track')->find($item->{'itemid'});
			$name = Slim::Music::Info::standardTitle(undef, $track);
                }elsif($format eq 'trackconcat') {
			my $track = Slim::Schema->resultset('Track')->find($item->{'itemid'});
			$prefix = Slim::Music::Info::standardTitle(undef, $track)." ";
                }elsif($format eq 'titleformat' && defined($item->{'itemformatdata'})) {
			my $track = Slim::Schema->resultset('Track')->find($item->{'itemid'});
			$name = Slim::Music::Info::displayText($client,$track,$item->{'itemformatdata'});
		}elsif($format eq 'titleformatconcat' && defined($item->{'itemformatdata'})) {
			my $track = Slim::Schema->resultset('Track')->find($item->{'itemid'});
			$prefix = Slim::Music::Info::displayText($client,$track,$item->{'itemformatdata'})." "
		}elsif($format eq 'function' && defined($item->{'itemformatdata'})) {
			$name = $self->_getFunctionItemFormat($client,$item);
		}elsif($format eq 'functionconcat' && defined($item->{'itemformatdata'})) {
			$prefix = $self->_getFunctionItemFormat($client,$item)." ";
		}elsif($format eq 'album') {
			my $album = Slim::Schema->resultset('Album')->find($item->{'itemid'});
			$name = $album->title;
                }elsif($format eq 'albumconcat') {
			my $album = Slim::Schema->resultset('Album')->find($item->{'itemid'});
			$prefix = $album->title." ";
                }
	}
	if((!defined($name) || $name eq '') && defined($item->{'itemname'})) {
		$name = $prefix.$item->{'itemname'};
	}
	if((!defined($name) || $name eq '') && defined($item->{'menuname'})){
		$name = $prefix.$item->{'menuname'};
	}
	if(defined($item->{'menuprefix'})) {
		if(defined($name)) {
			$name = $item->{'menuprefix'}.$name;
		}else {
			$name = $item->{'menuprefix'};
		}
	}
	if(defined($name) && $name =~ /{.*}/ms) {
		$name = $self->itemParameterHandler->replaceParameters($client,$name,$item->{'parameters'},$context);
	}
	return $name;
}

sub playAddItem {
	my ($self,$client,$listRef, $item, $addOnly,$context) = @_;

	if($addOnly) {
		$self->_playAddItem($client,$listRef,$item,"addtracks",undef,undef,$context);
	}else {
		$self->_playAddItem($client,$listRef,$item,"loadtracks",undef,undef,$context);
	}
}
sub _playAddItem {
	my ($self,$client,$listRef, $item, $command, $displayString, $subCall,$context,$playAll) = @_;
	my @items = ();
	if($playAll) {
		@items = @$listRef;
	}elsif(!defined($item->{'playtype'})) {
		push @items,$item;
	}else {
		my $playHandler = $self->playHandlers->{$item->{'playtype'}};
		if(defined($playHandler)) {
			my $tmpItems = $playHandler->getItems($client,$item,$listRef);
			push @items,@$tmpItems;
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
		$request->source($self->requestSource);
		$pos = 0;
		$selectedPos = 0;
		$postPlay = 1;
		$command = 'addtracks';
	}
	my @tracks = ();
	foreach my $it (@items) {
		if(defined($it->{'itemtype'}) && ($it->{'itemtype'} eq 'track') || ($it->{'itemtype'} ne 'track' && !defined($it->{'menu'}) && !defined($it->{'menufunction'}))) {
			$request = undef;
			my $played = 0;
			if($it->{'itemtype'} eq "track") {
				$self->debugCallback->("Adding track ".$it->{'itemname'}."\n");
				push @tracks,$it->{'itemid'};
				if(defined($item->{'itemid'}) && $it->{'itemid'} eq $item->{'itemid'}) {
					$selectedPos = $pos;
				}
				$played = 1;
			}else {
				if(scalar(@tracks)>0) {
					$self->_playTracks($client,$command,\@tracks,$item->{'itemid'});
					if($command eq 'loadtracks') {
						$command = 'addtracks';
					}
				}
				if($it->{'itemtype'} eq "album") {
					$self->debugCallback->("Execute $command on ".$it->{'itemname'}."\n");
					$request = $client->execute(['playlist', $command, 
						sprintf('%s=%d', 'album.id',$it->{'itemid'})]);
					$played = 1;
				}elsif($it->{'itemtype'} eq "artist") {
					$self->debugCallback->("Execute $command on ".$it->{'itemname'}."\n");
					$request = $client->execute(['playlist', $command, 
						sprintf('%s=%d', 'contributor.id',$it->{'itemid'})]);
					$played = 1;
				}elsif($it->{'itemtype'} eq "year") {
					$self->debugCallback->("Execute $command on ".$it->{'itemname'}."\n");
					$request = $client->execute(['playlist', $command, 
						sprintf('%s=%d', 'year.id',$it->{'itemid'})]);
					$played = 1;
				}elsif($it->{'itemtype'} eq "genre") {
					$self->debugCallback->("Execute $command on ".$it->{'itemname'}."\n");
					$request = $client->execute(['playlist', $command, 
						sprintf('%s=%d', 'genre.id',$it->{'itemid'})]);
					$played = 1;
				}elsif($it->{'itemtype'} eq "playlist") {
					$self->debugCallback->("Execute $command on ".$it->{'itemname'}."\n");
					$request = $client->execute(['playlist', $command, 
						sprintf('%s=%d', 'playlist.id',$it->{'itemid'})]);
					$played = 1;
				}
			}
			if(!$played) {
				my $subItems = $self->getMenuItems($client,$it,$context);
				if(ref($subItems) eq 'ARRAY') {
					$self->_playAddItem($client,$subItems,undef,$command,undef,1,$context,1);
					if($command eq 'loadtracks') {
						$command = 'addtracks';
					}
					$playedMultiple = 1;
				}
			}
			if (defined($request)) {
				# indicate request source
				$request->source($self->requestSource);
			}
		}else {
			if(scalar(@tracks)>0) {
				$self->_playTracks($client,$command,\@tracks,$item->{'itemid'});
				if($command eq 'loadtracks') {
					$command = 'addtracks';
				}
			}

			my $subItems = $self->getMenuItems($client,$it,$context);
			if(ref($subItems) eq 'ARRAY') {
				$self->_playAddItem($client,$subItems,undef,$command,undef,1,$context,1);
				if($command eq 'loadtracks') {
					$command = 'addtracks';
				}
				$playedMultiple = 1;
			}
		}			
		if($command eq 'loadtracks' && scalar(@tracks)==0) {
			$command = 'addtracks';
		}
		if(defined($pos)) {
			$pos = $pos + 1;
		}
	}
	if(scalar(@tracks)>0) {
		$self->_playTracks($client,$command,\@tracks,$item->{'itemid'});
	}
	if(defined($selectedPos)) {
		$request = $client->execute(['playlist', 'jump', $selectedPos]);
		if (defined($request)) {
			# indicate request source
			$request->source($self->requestSource);
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
			$line2 = $self->getItemText($client,$item);
		}
		$client->showBriefly({
			'line'    => [ $line1, $line2 ],
			'overlay' => [ undef, $client->symbols('notesymbol') ],
		});
	}
}

sub _playTracks {
	my $self = shift;
	my $client = shift;
	my $command = shift;
	my $trackIds = shift;

	my %orderHash = ();
	my $i = 0;
	for my $t (@$trackIds) {
		$orderHash{$t}=$i;
		$i++;
	}
	my @rawtracks = Slim::Schema->search('Track', { 'id' => { 'in' => $trackIds } })->all;
	@rawtracks = sort { $orderHash{$a->id()} <=> $orderHash{$b->id()} } @rawtracks;
	$self->debugCallback->("Execute $command on ".scalar(@rawtracks)." items of ".scalar(@$trackIds)."\n");
	my $request = $client->execute(['playlist', $command, 'listRef',\@rawtracks]);
	@$trackIds = ();
	# indicate request source
	$request->source($self->requestSource);
}
sub copyKeywords {
	my $self = shift;
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
			$self->copyKeywords($menuItem,$menuItem->{'menu'});
		}
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
