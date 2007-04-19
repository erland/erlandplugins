# 			ConfigManager::MenuWebAdminMethods module
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

package Plugins::CustomBrowse::ConfigManager::MenuWebAdminMethods;

use strict;
use Plugins::CustomBrowse::ConfigManager::WebAdminMethods;
our @ISA = qw(Plugins::CustomBrowse::ConfigManager::WebAdminMethods);

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
		$template =~ s/id="menuname" name="(.*?)" value=".*"/id="menuname" name="$1" value="$name"/;
	}

	return $template;
}

sub updateContentBeforePublish {
	my $self = shift;
	my $client = shift;
	my $params = shift;	
	my $content = shift;

	$content = $self->SUPER::updateContentBeforePublish($client,$params,$content);

	$content =~ s/<menuname>.*?<\/menuname>/<menuname>[% menuname %]<\/menuname>/;
	return $content;
}

sub getTemplateParametersForPublish {
	my $self = shift;
	my $client = shift;
	my $params = shift;

	return '		<parameter type="text" id="menuname" name="Menu name" value="'.$params->{'itemname'}.'"/>'."\n";
}

sub checkSaveItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;
	my $item = shift;
#	my $items = $params->{'items'};
#	if(defined($items)) {
#		my $id = unescape($params->{'file'});
#		my $regexp = ".".$self->extension."\$";
#		$regexp =~ s/\./\\./;
#		$id =~ s/$regexp//;
#		for my $key (keys %$items) {
#			my $currentItem = $items->{$key};
#			if($currentItem && $currentItem->{'menuname'} eq $item->{'menuname'} && $currentItem->{'id'} ne $id && !defined($currentItem->{'defaultitem'})) {
#				return 'Menu with that name already exists';
#			}
#		}
#	}
	return undef;
}

sub checkSaveSimpleItem {
	my $self = shift;
	my $client = shift;
	my $params = shift;

	my $items = $params->{'items'};
#	if(defined($items)) {
#		my $id = unescape($params->{'file'});
#		my $regexp = ".".$self->simpleExtension."\$";
#		$regexp =~ s/\./\\./;
#		$id =~ s/$regexp//;
#		for my $key (keys %$items) {
#			my $currentItem = $items->{$key};
#			if($currentItem && $currentItem->{'menuname'} eq $params->{'itemparameter_menuname'} && $currentItem->{'id'} ne $id && !defined($currentItem->{'defaultitem'})) {
#				return 'Menu with that name already exists';
#			}
#		}
#	}
	return undef;
}

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
