# 			ParameterHandler module
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

package Plugins::CustomBrowse::MenuHandler::ParameterHandler;

use strict;

use base 'Class::Data::Accessor';

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_classaccessors( qw(debugCallback errorCallback pluginId pluginVersion propertyHandler) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = {
		'debugCallback' => $parameters->{'debugCallback'},
		'errorCallback' => $parameters->{'errorCallback'},
		'pluginId' => $parameters->{'pluginId'},
		'pluginVersion' => $parameters->{'pluginVersion'},
		'propertyHandler' => $parameters->{'propertyHandler'}
	};

	bless $self,$class;
	return $self;
}

sub quoteValue {
	my $value = shift;
	$value =~ s/\'/\\\'/g;
	$value =~ s/\"/\\\"/g;
	$value =~ s/\\/\\\\/g;
	return $value;
}

sub replaceParameters {
	my $self = shift;
	my $client = shift;
	my $originalValue = shift;
	my $parameters = shift;
	my $context = shift;
	my $quote = shift;

	if(defined($parameters)) {
		for my $param (keys %$parameters) {
			my $propertyValue = $parameters->{$param};
			if($quote) {
				$propertyValue=quoteValue($propertyValue);
			}
			$originalValue =~ s/\{$param\}/$propertyValue/g;
		}
	}
	while($originalValue =~ m/\{custombrowse\.(.*?)\}/) {
		my $propertyValue = $self->propertyHandler->getProperty($1);
		if(defined($propertyValue)) {
			if($quote) {
				$propertyValue=quoteValue($propertyValue);
			}
			$originalValue =~ s/\{custombrowse\.$1\}/$propertyValue/g;
		}else {
			$originalValue =~ s/\{custombrowse\..*?\}//g;
		}
	}
	while($originalValue =~ m/\{property\.(.*?)\}/) {
		my $propertyValue = Slim::Utils::Prefs::get($1);
		if(defined($propertyValue)) {
			if($quote) {
				$propertyValue=quoteValue($propertyValue);
			}
			$originalValue =~ s/\{property\.$1\}/$propertyValue/g;
		}else {
			$originalValue =~ s/\{property\..*?\}//g;
		}
	}
	while($originalValue =~ m/\{clientproperty\.(.*?)\}/) {
		my $propertyValue = undef;
		if(defined($client)) {
			$propertyValue = $client->prefGet($1);
		}
		if(defined($propertyValue)) {
			if($quote) {
				$propertyValue=quoteValue($propertyValue);
			}
			$originalValue =~ s/\{clientproperty\.$1\}/$propertyValue/g;
		}else {
			$originalValue =~ s/\{clientproperty\..*?\}//g;
		}
	}
	while($originalValue =~ m/\{context\.(.*?)\}/) {
		my $propertyValue = undef;
		my $contextHash = $context;
		if(!defined($contextHash)) {
			$contextHash = $client->param($self->pluginId.".context");
		}
		if(defined($contextHash)) {
			$propertyValue = $contextHash->{$1};
			#$propertyValue = Slim::Utils::Unicode::utf8on($propertyValue);
			#$propertyValue = Slim::Utils::Unicode::utf8encode_locale($propertyValue);
		}
		if(defined($propertyValue)) {
			if($quote) {
				$propertyValue=quoteValue($propertyValue);
			}
			$originalValue =~ s/\{context\.$1\}/$propertyValue/g;
		}else {
			$originalValue =~ s/\{context\..*?\}//g;
		}
	}

	return $originalValue;
}

1;

__END__
