# 			MenuHandler::ModeMix module
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

package Plugins::CustomBrowse::MenuHandler::ModeMix;

use strict;

use base 'Class::Data::Accessor';
use Plugins::CustomBrowse::MenuHandler::BaseMix;
our @ISA = qw(Plugins::CustomBrowse::MenuHandler::BaseMix);

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_classaccessors( qw(itemParameterHandler) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new($parameters);
	$self->{'itemParameterHandler'} = $parameters->{'itemParameterHandler'};

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
	my @params = split(/\|/,$mix->{'mixdata'});
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
				$modeParameters{$1}->{$2}=$self->itemParameterHandler->replaceParameters($client,$value,$keywords);
			}else {
				$modeParameters{$name} = $self->itemParameterHandler->replaceParameters($client,$value,$keywords);
			}
		}
	}
	Slim::Buttons::Common::pushModeLeft($client, $mode, \%modeParameters);
}

sub isWebSupported {
	my $self = shift;
	my $client = shift;
	my $mix = shift;

	if(defined($mix->{'mixurl'})) {
		return 1;	
	}else {
		return 0;
	}
}

1;

__END__
