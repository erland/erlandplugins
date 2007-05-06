# 			SQLHandler module
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

package Plugins::CustomBrowse::MenuHandler::SQLHandler;

use strict;

use base 'Class::Data::Accessor';

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_classaccessors( qw(debugCallback errorCallback pluginId pluginVersion itemParameterHandler addSqlErrorCallback) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = {
		'debugCallback' => $parameters->{'debugCallback'},
		'errorCallback' => $parameters->{'errorCallback'},
		'pluginId' => $parameters->{'pluginId'},
		'pluginVersion' => $parameters->{'pluginVersion'},
		'itemParameterHandler' => $parameters->{'itemParameterHandler'},
		'addSqlErrorCallback' => $parameters->{'addSqlErrorCallback'}
	};

	bless $self,$class;
	return $self;
}

sub getData {
    my $self = shift;
    my $client = shift;
    my $sql = shift;
    my $parameters = shift;
    my $context = shift;
    
    $self->debugCallback->("Preparing SQL: $sql\n");
    $sql = $self->itemParameterHandler->replaceParameters($client,$sql,$parameters,$context,1);

    return $self->_execute($sql);
}

sub _execute {
	my $self = shift;
	my $sqlstatements = shift;
	my @result =();
	my $dbh = getCurrentDBH();
	my $trackno = 0;
    	for my $sql (split(/[;]/,$sqlstatements)) {
    	eval {
			$sql =~ s/^\s+//g;
			$sql =~ s/\s+$//g;
			my $sth = $dbh->prepare( $sql );
			$self->debugCallback->("Executing: $sql\n");
			$sth->execute() or do {
	            $self->debugCallback->("Error executing: $sql\n");
	            $sql = undef;
			};

	        if ($sql =~ /^\(*SELECT+/oi) {
				$self->debugCallback->("Executing and collecting: $sql\n");
				my $id;
                                my $name;
                                my $link;
				$sth->bind_col( 1, \$id);
                                $sth->bind_col( 2, \$name);
				# bind optional column
				eval {
	                                $sth->bind_col( 3, \$link);
				};
				while( $sth->fetch() ) {
                                    my %item = (
                                        'id' => $id,
                                        'name' => Slim::Utils::Unicode::utf8decode($name,'utf8')
                                    );
				    if(defined($link)) {
					$item{'link'} = Slim::Utils::Unicode::utf8decode($link,'utf8');
                                    }
                                    push @result, \%item;
				}
			}
			$sth->finish();
		};
		if( $@ ) {
		    warn "Database error: $DBI::errstr\n$@\n";
		    $self->addSqlErrorCallback->("Running: $sql got error: <br>".$DBI::errstr);
		}		
	}
	return \@result;
}

sub getCurrentDBH {
	return Slim::Schema->storage->dbh();
}

1;

__END__
