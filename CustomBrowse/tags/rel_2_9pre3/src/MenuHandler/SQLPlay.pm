# 			MenuHandler::SQLPlay module
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

package Plugins::CustomBrowse::MenuHandler::SQLPlay;

use strict;

use base qw(Slim::Utils::Accessor);
use Plugins::CustomBrowse::MenuHandler::BasePlay;
our @ISA = qw(Plugins::CustomBrowse::MenuHandler::BasePlay);

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_accessor( rw => qw(sqlHandler) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new($parameters);
	$self->sqlHandler($parameters->{'sqlHandler'});

	return $self;
}

sub getItems {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $items = shift;

	my @result = ();
	if(defined($item->{'playdata'})) {
		my $keywords = $self->combineKeywords($item->{'keywordparameters'},undef,$item->{'parameters'});
		my $sqlItems = $self->sqlHandler->getData($client,$item->{'playdata'},$keywords);
		foreach my $sqlItem (@$sqlItems) {
			my $type = 'track';
			if(defined($sqlItem->{'type'})) {
				$type = $sqlItem->{'type'};
			}
			my %addItem = (
				'itemtype' => $type,
				'itemid' => $sqlItem->{'id'},
				'itemname' => $sqlItem->{'name'}
			);
			push @result, \%addItem;
		}		
	}else {
		$self->errorCallback->("CustomBrowse: ERROR, no playdata element found\n");
	}
	return \@result;
}

1;

__END__
