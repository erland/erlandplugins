#                               DatabaseQuery::Modules::CSV module
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

package Plugins::DatabaseQuery::Modules::CSV;

use strict;

use Slim::Utils::Misc;
#use Data::Dumper;

sub getDatabaseQueryExportModules {
	my %module = (
		'id' => 'csv',
		'name' => 'CSV',
		'extension' => 'csv',
		'description' => "comma separated file",
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

	my $rows = $reportData->{'resultitems'};
	my $columns = $reportData->{'columns'};

	my $result = '';
	my $first = 1;
	for my $column (@$columns) {
		if(!$first) {
			$result .= ';'
		}
		$first = 0;
		my $value = $column;
		$value =~ s/\"/\\\"/m;
		$value =~ s/;/\\;/m;
		$value =~ s/\n/\\n/m;
		$result .= $value;
	}
	$result .= "\n";

	for my $row (@$rows) {
		$first = 1;
		# We skip the four first columns, they just contains the context url of the row
		shift @$row;
		shift @$row;
		shift @$row;
		shift @$row;
		for my $column (@$row) {
			if(!$first) {
				$result .= ';'
			}
			$first = 0;
			my $value = $column;
			$value =~ s/\"/\\\"/m;
			$value =~ s/;/\\;/m;
			$value =~ s/\n/\\n/m;
			$result .= $value;
		}
		$result .= "\n";
	}
	return \$result;
}

sub debugMsg
{
	my $message = join '','DatabaseQuery:CSV ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_databasequery_showmessages"));
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
