# 			BaseMenu module
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

package Plugins::CustomBrowse::MenuHandler::BaseMenu;

use strict;

use base qw(Slim::Utils::Accessor);

__PACKAGE__->mk_accessor( rw => qw(logHandler pluginId pluginVersion) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new();
	$self->logHandler($parameters->{'logHandler'});
	$self->pluginId($parameters->{'pluginId'});
	$self->pluginVersion($parameters->{'pluginVersion'});

	return $self;
}

sub prepareMenu {
	return undef;
}

sub hasCustomUrl {
	return undef;
}

sub getCustomUrl {
	return undef;
}
sub getOverlay {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	return $client->symbols('rightarrow');
}

sub getKeywords {
	my $self = shift;
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
	my $self = shift;
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

1;

__END__
