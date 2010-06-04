# 			MenuHandler::FunctionMix module
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

package Plugins::CustomBrowse::MenuHandler::FunctionMix;

use strict;

use base qw(Slim::Utils::Accessor);
use Plugins::CustomBrowse::MenuHandler::BaseMix;
our @ISA = qw(Plugins::CustomBrowse::MenuHandler::BaseMix);

use File::Spec::Functions qw(:ALL);

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new($parameters);

	return $self;
}

sub executeMix {
	my $self = shift;
	my $client = shift;
	my $mix = shift;
	my $keywords = shift;
	my $addOnly = shift;
	my $interfaceType = shift;

	if($mix->{'mixdata'} =~ /^(.+)::([^:].*)$/) {
		my $class = $1;
		my $function = $2;
		my $itemObj = undef;
		my $itemObj = undef;
		if($keywords->{'itemtype'} eq "track") {
			$itemObj = Slim::Schema->resultset('Track')->find($keywords->{'itemid'});
		}elsif($keywords->{'itemtype'} eq "album") {
			$itemObj = Slim::Schema->resultset('Album')->find($keywords->{'itemid'});
		}elsif($keywords->{'itemtype'} eq "artist") {
			$itemObj = Slim::Schema->resultset('Contributor')->find($keywords->{'itemid'});
		}elsif($keywords->{'itemtype'} eq "year") {
			$itemObj = Slim::Schema->resultset('Year')->find($keywords->{'itemid'});
		}elsif($keywords->{'itemtype'} eq "genre") {
			$itemObj = Slim::Schema->resultset('Genre')->find($keywords->{'itemid'});
		}elsif($keywords->{'itemtype'} eq "playlist") {
			$itemObj = Slim::Schema->resultset('Playlist')->find($keywords->{'itemid'});
		}
		if(defined($itemObj)) {
			if(UNIVERSAL::can("$class","$function")) {
				$self->logHandler->debug("Calling ${class}::${function}\n");
				no strict 'refs';
				eval { &{"${class}::${function}"}($client,$itemObj,$addOnly,$interfaceType) };
				if ($@) {
					$self->logHandler->warn("Error calling ${class}::${function}: $@\n");
				}
				use strict 'refs';
			}else {
				$self->logHandler->warn("Function ${class}::${function} does not exist\n");
			}
		}else {
			$self->logHandler->warn("Item for itemtype ".$keywords->{'itemtype'}." could not be found\n");
		}
	}
}

sub checkMix {
	my $self = shift;
	my $client = shift;
	my $mix = shift;
	my $keywords = shift;
	my $obj = shift;

	if($mix->{'mixcheckdata'} =~ /^(.+)::([^:].*)$/) {
		my $class = $1;
		my $function = $2;
		my $itemObj = undef;
		if($keywords->{'itemtype'} eq "track") {
			if(defined($obj)) {
				$itemObj = $obj;
			}else {
				$itemObj = Slim::Schema->resultset('Track')->find($keywords->{'itemid'});
			}
		}elsif($keywords->{'itemtype'} eq "album") {
			if(defined($obj)) {
				$itemObj = $obj;
			}else {
				$itemObj = Slim::Schema->resultset('Album')->find($keywords->{'itemid'});
			}
		}elsif($keywords->{'itemtype'} eq "artist") {
			if(defined($obj)) {
				$itemObj = $obj;
			}else {
				$itemObj = Slim::Schema->resultset('Contributor')->find($keywords->{'itemid'});
			}
		}elsif($keywords->{'itemtype'} eq "year") {
			if(defined($obj)) {
				$itemObj = $obj;
			}else {
				$itemObj = Slim::Schema->resultset('Year')->find($keywords->{'itemid'});
			}
		}elsif($keywords->{'itemtype'} eq "genre") {
			if(defined($obj)) {
				$itemObj = $obj;
			}else {
				$itemObj = Slim::Schema->resultset('Genre')->find($keywords->{'itemid'});
			}
		}elsif($keywords->{'itemtype'} eq "playlist") {
			if(defined($obj)) {
				$itemObj = $obj;
			}else {
				$itemObj = Slim::Schema->resultset('Playlist')->find($keywords->{'itemid'});
			}
		}elsif(defined($keywords->{'itemtype'})) {
			$itemObj = {};
			$itemObj->{'type'} = $keywords->{'itemtype'};
			$itemObj->{'id'} = $keywords->{'itemid'};
			$itemObj->{'name'} = $keywords->{'itemname'};
		}

		if(defined($itemObj)) {
			if(UNIVERSAL::can("$class","$function")) {
				$self->logHandler->debug("Calling ${class}->${function}\n");
				no strict 'refs';
				my $enabled = eval { $class->$function($itemObj) };
				if ($@) {
					$self->logHandler->warn("Error calling ${class}->${function}: $@\n");
				}
				use strict 'refs';
				if($enabled) {
					return 1;
				}
			}else {
				$self->logHandler->warn("Function ${class}->${function} does not exist\n");
			}
		}
	}
	return 0;
}

sub isInterfaceSupported {
	my $self = shift;
	my $client = shift;
	my $mix = shift;
	my $interfaceType = shift;

	if(defined($mix->{'mixsupport'})) {
		my @supportItems = split(/,/,$mix->{'mixsupport'});
		my $found = 0;
		for my $item (@supportItems) {
			if($item eq $interfaceType) {
				$found = 1;
			}
		}
		if(!$found) {
			return 0;
		}
	}

	return 1;	
}

1;

__END__
