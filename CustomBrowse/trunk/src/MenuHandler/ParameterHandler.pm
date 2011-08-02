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

use base qw(Slim::Utils::Accessor);

use File::Spec::Functions qw(:ALL);
use Slim::Utils::Prefs;

__PACKAGE__->mk_accessor( rw => qw(logHandler pluginId pluginVersion propertyHandler) );

my %prefs = ();
my $driver;
sub new {
	my $class = shift;
	my $parameters = shift;

	my ($source,$username,$password);
	($driver,$source,$username,$password) = Slim::Schema->sourceInformation;

	my $self = $class->SUPER::new();
	$self->logHandler($parameters->{'logHandler'});
	$self->pluginId($parameters->{'pluginId'});
	$self->pluginVersion($parameters->{'pluginVersion'});
	$self->propertyHandler($parameters->{'propertyHandler'});

	return $self;
}

sub quoteValue {
	my $value = shift;

	if($driver eq 'SQLite') {
		$value =~ s/\'/\'\'/g;
	}else {
		$value =~ s/\\/\\\\/g;
		$value =~ s/\'/\\\'/g;
		$value =~ s/\"/\\\"/g;
	}
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
	while($originalValue =~ m/\{property:(.*?):(.*?)\}/) {
		my $propContext = $1;
		my $propName = $2;
		if(!defined($prefs{$propContext})) {
			$prefs{$propContext}=preferences($propContext);
		}
		my $propertyValue = $prefs{$propContext}->get($propName);
		if(defined($propertyValue)) {
			if($quote) {
				$propertyValue=quoteValue($propertyValue);
			}
			$originalValue =~ s/\{property:$propContext:$propName\}/$propertyValue/g;
		}else {
			$originalValue =~ s/\{property:$propContext:$propName\}//g;
		}
	}
	while($originalValue =~ m/\{clientproperty:(.*?):(.*?)\}/) {
		my $propContext = $1;
		my $propName = $2;
		if(!defined($prefs{$propContext})) {
			$prefs{$propContext}=preferences($propContext);
		}
		my $propertyValue = undef;
		if(defined($client)) {
			$propertyValue = $prefs{$propContext}->client($client)->get($propName);
		}
		if(defined($propertyValue)) {
			if($quote) {
				$propertyValue=quoteValue($propertyValue);
			}
			$originalValue =~ s/\{clientproperty:$propContext:$propName\}/$propertyValue/g;
		}else {
			$originalValue =~ s/\{clientproperty:$propContext:$propName\}//g;
		}
	}
	while($originalValue =~ m/\{context\.(.*?)\}/) {
		my $propertyValue = undef;
		my $contextHash = $context;
		if(!defined($contextHash)) {
			$contextHash = $client->modeParam($self->pluginId.".context");
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
