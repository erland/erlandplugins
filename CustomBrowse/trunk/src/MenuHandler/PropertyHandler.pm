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

use base 'Class::Data::Accessor';

use File::Spec::Functions qw(:ALL);

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

sub getProperty {
	my $self = shift;
	my $name = shift;
	my $properties = $self->getProperties();
	return $properties->{$name};
}

sub getProperties {
	my $self = shift;
	my $array = Slim::Utils::Prefs::get('plugin_custombrowse_properties');
	my %result = ();
	foreach my $item (@$array) {
		if($item =~ m/^([a-zA-Z0-9]+?)\s*=\s*(.+)\s*$/) {
			my $name = $1;
			my $value = $2;
			$self->debugCallback->("Got property: $name=$value\n");
			$result{$name}=$value;
		}
	}
	return \%result;
}

1;

__END__
