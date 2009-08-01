# 			ConfigManager::QueryWebAdminMethods module
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

package Plugins::DatabaseQuery::ConfigManager::QueryWebAdminMethods;

use strict;
use Plugins::DatabaseQuery::ConfigManager::WebAdminMethods;
our @ISA = qw(Plugins::DatabaseQuery::ConfigManager::WebAdminMethods);

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Data::Dumper;
sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new($parameters);
	bless $self,$class;
	return $self;
}

sub updateTemplateBeforePublish {
	my $self = shift;
	my $client = shift;
	my $params = shift;	
	my $template = shift;
	
	$template = $self->SUPER::updateTemplateBeforePublish($client,$params,$template);

	if($params->{'itemname'}) {
		my $name = $params->{'itemname'};
		$template =~ s/id="queryname" name="(.*?)" value=".*"/id="queryname" name="$1" value="$name"/;
	}

	return $template;
}

sub updateContentBeforePublish {
	my $self = shift;
	my $client = shift;
	my $params = shift;	
	my $content = shift;

	$content = $self->SUPER::updateContentBeforePublish($client,$params,$content);

	$content =~ s/<name>.*?<\/name>/<name>[% queryname %]<\/name>/;
	return $content;
}

sub getTemplateParametersForPublish {
	my $self = shift;
	my $client = shift;
	my $params = shift;

	return '		<parameter type="text" id="queryname" name="Data query name" value="'.$params->{'itemname'}.'"/>'."\n";
}

sub checkSaveItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $item = shift;

	my $dataQueries = $params->{'items'};
	if(defined($dataQueries)) {
		my $id = unescape($params->{'file'});
		my $regexp = ".".$self->extension."\$";
		$regexp =~ s/\./\\./;
		$id =~ s/$regexp//;
		for my $key (keys %$dataQueries) {
			my $dataQuery = $dataQueries->{$key};
			if($dataQuery && $dataQuery->{'name'} eq $item->{'name'} && $dataQuery->{'id'} ne $id && !defined($dataQuery->{'defaultitem'}) && !defined($dataQuery->{'simple'})) {
				return 'Data query with that name already exists';
			}
		}
	}
	return undef;
}

sub checkSaveSimpleItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;

	my $dataQueries = $params->{'items'};
	if(defined($dataQueries)) {
		my $id = escape($params->{'file'});
		my $regexp = ".".$self->simpleExtension."\$";
		$regexp =~ s/\./\\./;
		$id =~ s/$regexp//;
		for my $key (keys %$dataQueries) {
			my $dataQuery = $dataQueries->{$key};
			if($dataQuery && $dataQuery->{'name'} eq $params->{'itemparameter_queryname'} && $dataQuery->{'id'} ne $id && !defined($dataQuery->{'defaultitem'})) {
				return 'Data query with that name already exists';
			}
		}
	}
	return undef;
}

# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

# don't use the external one because it doesn't know about the difference
# between a param and not...
#*unescape = \&URI::Escape::unescape;
sub unescape {
        my $in      = shift;
        my $isParam = shift;

        $in =~ s/\+/ /g if $isParam;
        $in =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

        return $in;
}
1;

__END__
