# 			MenuHandler::SQLMenu module
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

package Plugins::CustomBrowse::MenuHandler::SQLMenu;

use strict;

use base 'Class::Data::Accessor';
use Plugins::CustomBrowse::MenuHandler::BaseMenu;
our @ISA = qw(Plugins::CustomBrowse::MenuHandler::BaseMenu);

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_classaccessors( qw(sqlHandler) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new($parameters);
	$self->{'sqlHandler'} = $parameters->{'sqlHandler'};
	bless $self,$class;
	return $self;
}

sub prepareMenu {
	my $self = shift;
	my $client = shift;
	my $menu = shift;
	my $item = shift;
	my $option = shift;
	my $result = shift;
	my $context = shift;

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
						$optionKeywords = $self->getKeywords($op);
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
					$optionKeywords = $self->getKeywords($options->[0]);
				}
			}
		}else {
			if(defined($menu->{'option'}->{'menudata'})) {
				$menudata = $menu->{'option'}->{'menudata'};
				$optionKeywords = $self->getKeywords($menu->{'option'});
			}else {
				$menudata = $menu->{'menudata'};
			}
		}
	}else {
		$menudata = $menu->{'menudata'};
	}
	my $keywords = $self->combineKeywords($menu->{'keywordparameters'},$optionKeywords,$item->{'parameters'});
	my $menuData = $self->getData($client,$menudata,$keywords,$context);
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
		if(defined($menu->{'contextid'})) {
			$menuItem{'parameters'}->{$menu->{'contextid'}} = $dataItem->{'id'};
		}elsif(defined($menu->{'id'})) {
			$menuItem{'parameters'}->{$menu->{'id'}} = $dataItem->{'id'};
		}
		push @$result, \%menuItem;
	}
	return undef;
}

sub getData {
	my $self = shift;
	my $client = shift;
	my $menudata = shift;
	my $keywords = shift;
	my $context = shift;

	return $self->sqlHandler->getData($client,$menudata,$keywords,$context);
}

1;

__END__
