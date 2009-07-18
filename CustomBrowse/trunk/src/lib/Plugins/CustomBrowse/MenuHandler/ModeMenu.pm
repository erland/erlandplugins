# 			MenuHandler::ModeMenu module
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

package Plugins::CustomBrowse::MenuHandler::ModeMenu;

use strict;

use base qw(Slim::Utils::Accessor);
use Plugins::CustomBrowse::MenuHandler::BaseMenu;
our @ISA = qw(Plugins::CustomBrowse::MenuHandler::BaseMenu);

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_accessor( rw => qw(itemParameterHandler) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new($parameters);
	$self->itemParameterHandler($parameters->{'itemParameterHandler'});

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

	my $keywords = $self->combineKeywords($menu->{'keywordparameters'},undef,$item->{'parameters'});
	my @params = split(/\|/,$menu->{'menudata'});
	my $mode = shift(@params);
	my %modeParameters = ();
	foreach my $keyvalue (@params) {
		if($keyvalue =~ /^([^=].*?)=(.*)/) {
			my $name=$1;
			my $value=$2;
			if($name =~ /^([^\.].*?)\.(.*)/) {
				if(!defined($modeParameters{$1})) {
					my %hash = ();
					$modeParameters{$1}=\%hash;
				}
				$modeParameters{$1}->{$2}=$self->itemParameterHandler->replaceParameters($client,$value,$keywords,$context);
			}else {
				$modeParameters{$name} = $self->itemParameterHandler->replaceParameters($client,$value, $keywords,$context);
			}
		}
	}
	my %params = (
		'useMode' => $mode,
		'parameters' => \%modeParameters
	);
	return \%params;		
}

sub hasCustomUrl {
	return 1;
}

sub getCustomUrl {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $params = shift;
	my $parent = shift;
	my $context = shift;
	
	if(defined($item->{'menu'}->{'menuurl'})) {
		my $url = $item->{'menu'}->{'menuurl'};
		my $keywords = $self->combineKeywords($item->{'menu'}->{'keywordparameters'},undef,$params);
		$url = $self->itemParameterHandler->replaceParameters($client,$url,$keywords,$context);
		return $url;
	}
	return undef;
}

1;

__END__
