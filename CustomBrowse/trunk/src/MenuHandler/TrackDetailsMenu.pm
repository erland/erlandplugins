# 			MenuHandler::TrackDetails module
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

package Plugins::CustomBrowse::MenuHandler::TrackDetailsMenu;

use strict;
use Plugins::CustomBrowse::MenuHandler::BaseMenu;
our @ISA = qw(Plugins::CustomBrowse::MenuHandler::BaseMenu);

use File::Spec::Functions qw(:ALL);

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new($parameters);
	bless $self,$class;
	return $self;
}

sub prepareMenu {
	my $self = shift;
	my $client = shift;
	my $menu = shift;
	my $item = shift;
	my $option = shift;
	my $result = shift;

	my $track = Slim::Schema->resultset('Track')->find($item->{'parameters'}->{$menu->{'menudata'}});
	if(defined($track)) {
		my %params = (
			'useMode' => 'trackinfo',
			'parameters' => 
			{
				'track' => $track
			}			
		);
		return \%params;		
	}
	return undef;
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

	my $id;
	if($item->{'menu'}->{'menudata'} eq $item->{'id'}) {
		$id = $item->{'itemid'};
	}else {
		$id = $parent->{'parameters'}->{$item->{'menu'}->{'menudata'}};
	}
	return 'songinfo.html?item='.escape($id).'&player='.$params->{'player'};
}

sub getOverlay {
	return undef;
}

# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
