#                               DatabaseQuery::Modules::XML module
#
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
#
#    Please respect amazon.com terms of service, the usage of the 
#    feeds are free but restricted to the Amazon Web Services Licensing Agreement
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

package Plugins::DatabaseQuery::Modules::XML;

use strict;

use Slim::Utils::Misc;
#use Data::Dumper;
use HTML::Entities;

sub getDatabaseQueryExportModules {
	my %module = (
		'id' => 'xml',
		'name' => 'XML',
		'extension' => 'xml',
		'description' => "XML formatted file",
		'callback' => \&createReport,
	);
	my @modules = ();
	push @modules,\%module;
	return \@modules;
		
}

sub createReport {
	my $queryId = shift;
	my $reportData = shift;
	my $dataRetreivalCallback = shift;

	my $columns = $reportData->{'columns'};
	my $rows = $reportData->{'resultitems'};

	my $result = '<?xml version="1.0" encoding="utf-8"?>'."\n";
	$result .= "<result>\n";

	for my $row (@$rows) {
		# We skip the four first columns, they just contains the context url of the row
		my $name = shift @$row;
		if(!defined($name)) {
			$name = "resultitem";
		}
		$name =~ s/\s/_/g;
		shift @$row;
		shift @$row;
		shift @$row;
		my @itemColumns = @$columns;
		$result .= "  <$name>\n";
		for my $value (@$row) {
			my $columnName = shift @itemColumns;
			my $elementName = encode_entities($columnName,"&<>%");
			$elementName =~ s/\s/_/g;
			$result .= ("    <$elementName>".(defined($value)?encode_entities($value,"&<>%"):"")."</$elementName>\n");
		}
		$result .= "  </$name>\n";
	}
	$result .= "</result>\n";
	return \$result;
}

sub debugMsg
{
	my $message = join '','DatabaseQuery:XML ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_databasequery_showmessages"));
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
