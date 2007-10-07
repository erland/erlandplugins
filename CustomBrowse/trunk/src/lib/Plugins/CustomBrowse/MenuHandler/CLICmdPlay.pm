# 			MenuHandler::FunctionCmdPlay module
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

package Plugins::CustomBrowse::MenuHandler::CLICmdPlay;

use strict;

use base 'Class::Data::Accessor';
use Plugins::CustomBrowse::MenuHandler::BasePlay;
our @ISA = qw(Plugins::CustomBrowse::MenuHandler::BasePlay);

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_classaccessors( qw(itemParameterHandler requestSource) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new($parameters);
	$self->{'itemParameterHandler'} = $parameters->{'itemParameterHandler'};
	$self->{'requestSource'} = $parameters->{'requestSource'};
	bless $self,$class;
	return $self;
}

sub implementsPlay {

	return 1;
}

sub play {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $items = shift;
	my $cmd = shift;

	my $result = undef;
	if(defined($item->{'playdata'})) {
		my @cmds = split(/\|/,$item->{'playdata'});
		for my $cmd (@cmds) {
			my $keywords = $self->combineKeywords($item->{'keywordparameters'},undef,$item->{'parameters'});
			$cmd=$self->itemParameterHandler->replaceParameters($client,$cmd,$keywords);
			my @cmdParts = split(/ /,$cmd);
			my $request = $client->execute(\@cmdParts);
			if(defined($request)) {
				$request->source($self->requestSource);
			}else {
				$self->errorCallback->("CustomBrowse: ERROR, couldn't execute CLI command $cmd\n");
			}
		}
	}else {
		$self->errorCallback->("CustomBrowse: ERROR, no playdata element found\n");
	}
	return 0;
}

1;

__END__
