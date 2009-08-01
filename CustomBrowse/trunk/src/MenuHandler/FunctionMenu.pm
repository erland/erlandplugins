# 			MenuHandler::FunctionMenu module
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

package Plugins::CustomBrowse::MenuHandler::FunctionMenu;

use strict;

use base qw(Slim::Utils::Accessor);
use Plugins::CustomBrowse::MenuHandler::SQLMenu;
our @ISA = qw(Plugins::CustomBrowse::MenuHandler::SQLMenu);

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_accessor( rw => qw(sqlHandler) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new($parameters);

	return $self;
}

sub getData {
	my $self = shift;
	my $client = shift;
	my $menudata = shift;
	my $keywords = shift;
	my $context = shift;

	my $result = undef;
	my @functions = split(/\|/,$menudata);
	if(scalar(@functions)>0) {
		my $dataFunction = @functions->[0];
		if($dataFunction =~ /^(.+)::([^:].*)$/) {
			my $class = $1;
			my $function = $2;

			shift @functions;
			for my $item (@functions) {
				if($item =~ /^(.+?)=(.*)$/) {
					$keywords->{$1}=$2;
				}
			}
			if(UNIVERSAL::can("$class","$function")) {
				$self->logHandler->debug("Calling ${class}->${function}\n");
				no strict 'refs';
				$result = eval { $class->$function($client,$keywords,$context) };
				if ($@) {
					$self->logHandler->warn("Error calling ${class}->${function}: $@\n");
				}
			}
		}
	}
	return $result;
}

1;

__END__
