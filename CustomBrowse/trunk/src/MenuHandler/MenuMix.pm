# 			MenuHandler::MenuMix module
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

package Plugins::CustomBrowse::MenuHandler::MenuMix;

use strict;

use base 'Class::Data::Accessor';
use Plugins::CustomBrowse::MenuHandler::BaseMix;
our @ISA = qw(Plugins::CustomBrowse::MenuHandler::BaseMix);

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_classaccessors( qw(itemParameterHandler menuHandler menuMode) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new($parameters);
	$self->{'itemParameterHandler'} = $parameters->{'itemParameterHandler'};
	$self->{'menuMode'} = $parameters->{'menuMode'};
	$self->{'menuHandler'} = $parameters->{'menuHandler'};

	bless $self,$class;
	return $self;
}

sub executeMix {
	my $self = shift;
	my $client = shift;
	my $mix = shift;
	my $keywords = shift;
	my $addOnly = shift;
	my $web = shift;

	if($web) {
		return;
	}

	my $mixdata = $mix->{'mixdata'};
	$mixdata->{'parameters'} = $keywords;
	my $mixKeywords = $mixdata->{'keyword'};
	my @keywordArray = ();
	if(defined($mixKeywords) && ref($mixKeywords) eq 'ARRAY') {
		@keywordArray = @$mixKeywords;
	}elsif(defined($mixKeywords)) {
		push @keywordArray,$mixKeywords;
	}
	for my $keyword (@keywordArray) {
		$mixdata->{'parameters'}->{$keyword->{'name'}} = $self->itemParameterHandler->replaceParameters($client,$keyword->{'value'},$keywords);
	}
	$mixdata->{'value'} = $mix->{'id'};
	if(!defined($mixdata->{'menu'}->{'id'})) {
		$mixdata->{'menu'}->{'id'} = $mix->{'id'};
	}
	my $modeParameters = $self->menuHandler->getMenu($client,$mixdata);
	if(defined($modeParameters)) {
		if(defined($modeParameters->{'useMode'})) {
			Slim::Buttons::Common::pushModeLeft($client, $modeParameters->{'useMode'}, $modeParameters->{'parameters'});
		}else {
			Slim::Buttons::Common::pushModeLeft($client, $self->menuMode, $modeParameters);
		}
	}else {
        	$client->bumpRight();
	}
}

sub isWebSupported {
	my $self = shift;
	my $client = shift;
	my $mix = shift;

	return 0;	
}

1;

__END__
