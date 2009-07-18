# 			ConfigManager::ContentParser module
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

package Plugins::DatabaseQuery::ConfigManager::ContentParser;

use strict;
use base qw(Slim::Utils::Accessor);
use Plugins::DatabaseQuery::ConfigManager::BaseParser;
our @ISA = qw(Plugins::DatabaseQuery::ConfigManager::BaseParser);

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

sub new {
	my $class = shift;
	my $parameters = shift;

	$parameters->{'contentType'} = 'dataquery';
	my $self = $class->SUPER::new($parameters);
	return $self;
}

sub parse {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $content = shift;
	my $items = shift;
	my $globalcontext = shift;
	my $localcontext = shift;

	return $self->parseContent($client,$item,$content,$items,$globalcontext,$localcontext);
}

sub checkContent {
	my $self = shift;
	my $xml = shift;
	my $globalcontext = shift;
	my $localcontext = shift;

	if(defined($localcontext) && defined($localcontext->{'simple'})) {
		$xml->{'dataquery'}->{'simple'} = 1;
	}
	if(defined($localcontext) && defined($localcontext->{'downloadidentifier'})) {
		$xml->{'dataquery'}->{'downloadeditem'} = 1;
	}
	$xml->{'dataquery'}->{'enabled'}=1;
	if($globalcontext->{'source'} eq 'plugin' || $globalcontext->{'source'} eq 'builtin') {
		$xml->{'dataquery'}->{'defaultitem'} = 1;
	}else {
		$xml->{'dataquery'}->{'customitem'} = 1;
	}
	return 1;
}
# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;
1;

__END__
