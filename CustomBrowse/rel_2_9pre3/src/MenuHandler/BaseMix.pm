# 			MenuHandler::BaseMix module
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

package Plugins::CustomBrowse::MenuHandler::BaseMix;

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

sub isInterfaceSupported {
	my $self = shift;
	my $client = shift;
	my $mix = shift;
	my $interfaceType = shift;

	#Override in your own implementation
	return 1;
}

sub executeMix {
	#Override in your own implementation
}
sub checkMix {
	my $self = shift;
	my $client = shift;
	my $mix = shift;
	my $keywords = shift;

	#Override in your own implementation
	return 1;
}

sub getMixData {
	my $self = shift;
	my $client = shift;
	my $mix = shift;
	my $item = shift;
	my $interfaceType = shift;
	my $parameter = shift;

	return $mix->{$parameter};
}

sub prepareMix {
	my $self = shift;
	my $client = shift;
	my $mix = shift;
	my $item = shift;
	my $interfaceType = shift;

	return $mix;
}

1;

__END__
