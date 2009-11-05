#    Copyright (c) 2007 Erland Isaksson (erland_i@hotmail.com)
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

package Plugins::CustomScan::Validators;

use strict;

use Slim::Utils::Misc;

sub isInt {
        my ($val) = @_;

        if ($val !~ /^-?\d+$/) { #not an integer
                return undef;

        }
        return $val;
}

sub isDirOrEmpty {
	my $arg = shift;
	if(!$arg || $arg eq '') {
		return $arg;
	}else {
		return isDir($arg);
	}
}

sub isDir {
	my $val = shift;
        if (-d $val) {
                return $val;
        }
	return undef;
}

sub isFile {
	my $val = shift;
        if (-r $val) {
                return $val;
        }
	return undef;
}

1;

__END__
