# 			PropertyHandler module
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

package Plugins::CustomBrowse::MenuHandler::PropertyHandler;

use strict;

use base qw(Slim::Utils::Accessor);

use File::Spec::Functions qw(:ALL);
use Slim::Utils::Prefs;

__PACKAGE__->mk_accessor( rw => qw(logHandler pluginId pluginVersion) );

my $prefs = preferences('plugin.custombrowse');

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new();
	$self->logHandler($parameters->{'logHandler'});
	$self->pluginId($parameters->{'pluginId'});
	$self->pluginVersion($parameters->{'pluginVersion'});

	return $self;
}

sub getProperty {
	my $self = shift;
	my $name = shift;
	my $properties = $self->getProperties();
	return $properties->{$name};
}

sub getProperties {
	my $self = shift;
	my $result = $prefs->get('properties');
	return $result;
}

1;

__END__
