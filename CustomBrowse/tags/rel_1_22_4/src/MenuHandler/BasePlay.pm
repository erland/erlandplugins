# 			BasePlay module
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

package Plugins::CustomBrowse::MenuHandler::BasePlay;

use strict;

use base 'Class::Data::Accessor';

__PACKAGE__->mk_classaccessors( qw(debugCallback errorCallback pluginId pluginVersion) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = {
		'debugCallback' => $parameters->{'debugCallback'},
		'errorCallback' => $parameters->{'errorCallback'},
		'pluginId' => $parameters->{'pluginId'},
		'pluginVersion' => $parameters->{'pluginVersion'}
	};
	bless $self,$class;
	return $self;
}

sub getItems {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $items = shift;

	my @result = ();
	return \@result;
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
