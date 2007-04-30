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

package Plugins::CustomBrowse::MenuHandler::SQLMix;

use strict;

use base 'Class::Data::Accessor';
use Plugins::CustomBrowse::MenuHandler::BaseMix;
our @ISA = qw(Plugins::CustomBrowse::MenuHandler::BaseMix);

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_classaccessors( qw(propertyHandler sqlHandler playHandler) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new($parameters);
	$self->{'propertyHandler'} = $parameters->{'propertyHandler'};
	$self->{'sqlHandler'} = $parameters->{'sqlHandler'};
	$self->{'playHandler'} = $parameters->{'playHandler'};

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

	my %playItem = (
		'playtype' => 'sql',
		'playdata' => $mix->{'mixdata'},
		'itemname' => $mix->{'mixname'},
		'parameters' => $keywords
	);
	$self->playHandler->playAddItem($client,undef,\%playItem,$addOnly);
	if(!$web) {
		Slim::Buttons::Common::popModeRight($client);
	}
}

sub checkMix {
	my $self = shift;
	my $client = shift;
	my $mix = shift;
	my $keywords = shift;

	my $mixcheckdata = undef;
	if(defined($mix->{'mixcheckdata'})) {
		$mixcheckdata = $mix->{'mixcheckdata'};
	}else {
		$mixcheckdata = $mix->{'mixdata'};
	}
	
	my $sqlItems = $self->sqlHandler->getData($client,$mixcheckdata,$keywords);
	if($sqlItems && scalar(@$sqlItems)>0) {
		return 1;
	}
	return 0;
}
sub isWebSupported {
	my $self = shift;
	my $client = shift;
	my $mix = shift;

	return 1;	
}

1;

__END__
