# 			MenuHandler::SQLMix module
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

package Plugins::CustomBrowse::MenuHandler::WrappedMix;

use strict;

use base qw(Slim::Utils::Accessor);
use Plugins::CustomBrowse::MenuHandler::BaseMix;
our @ISA = qw(Plugins::CustomBrowse::MenuHandler::BaseMix);

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_accessor( rw => qw(propertyHandler sqlHandler playHandler menuHandler itemParameterHandler mixHandler) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new($parameters);
	$self->propertyHandler($parameters->{'propertyHandler'});
	$self->sqlHandler($parameters->{'sqlHandler'});
	$self->menuHandler($parameters->{'menuHandler'});
	$self->playHandler($parameters->{'playHandler'});
	$self->mixHandler($parameters->{'mixHandler'});
	$self->itemParameterHandler($parameters->{'itemParameterHandler'});

	return $self;
}

sub isInterfaceSupported {
	my $self = shift;
	my $client = shift;
	my $mix = shift;
	my $interfaceType = shift;

	return $self->mixHandler->isInterfaceSupported($self, $client, $mix, $interfaceType);
}

sub executeMix {
	my $self = shift;
	my $client = shift;
	my $mix = shift;
	my $keywords = shift;
	my $addOnly = shift;
	my $interfaceType = shift;

	$self->mixHandler->executeMix($self, $client, $mix, $keywords, $addOnly, $interfaceType);

}
sub checkMix {
	my $self = shift;
	my $client = shift;
	my $mix = shift;
	my $keywords = shift;


	return $self->mixHandler->checkMix($self, $client, $mix, $keywords);
}

sub getMixData {
	my $self = shift;
	my $client = shift;
	my $mix = shift;
	my $keywords = shift;
	my $interfaceType = shift;
	my $parameter = shift;

	my $result = $self->mixHandler->getMixData($self, $client, $mix, $keywords, $interfaceType, $parameter);

}

1;

__END__
