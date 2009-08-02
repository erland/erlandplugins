# 			MenuHandler::FunctionPlay module
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

package Plugins::CustomBrowse::MenuHandler::FunctionPlay;

use strict;

use base qw(Slim::Utils::Accessor);
use Plugins::CustomBrowse::MenuHandler::BasePlay;
our @ISA = qw(Plugins::CustomBrowse::MenuHandler::BasePlay);

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_accessor( rw => qw(itemParameterHandler) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new($parameters);
	$self->itemParameterHandler($parameters->{'itemParameterHandler'});

	return $self;
}

sub getItems {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $items = shift;

	my $result = undef;
	if(defined($item->{'playdata'})) {
		my @functions = split(/\|/,$item->{'playdata'});
		if(scalar(@functions)>0) {
			my $dataFunction = @functions->[0];
			if($dataFunction =~ /^(.+)::([^:].*)$/) {
				my $class = $1;
				my $function = $2;

				shift @functions;
				my $keywords = $self->combineKeywords($item->{'keywordparameters'},undef,$item->{'parameters'});
				my %parameters = ();
				for my $item (@functions) {
					if($item =~ /^(.+?)=(.*)$/) {
						$parameters{$1}=$self->itemParameterHandler->replaceParameters($client,$2,$keywords);
					}
				}
				if(UNIVERSAL::can("$class","$function")) {
					$self->logHandler->debug("Calling ${class}->${function}\n");
					no strict 'refs';
					$result = eval { &{"${class}::${function}"}($client,\%parameters) };
					if ($@) {
						$self->logHandler->warn("Error calling ${class}->${function}: $@\n");
					}
				}else {
					$self->logHandler->warn("Error calling ${class}->${function}: function does not exist\n");
				}
			}
		}
	}else {
		$self->logHandler->warn("CustomBrowse: ERROR, no playdata element found\n");
	}
	return $result;
}

1;

__END__
