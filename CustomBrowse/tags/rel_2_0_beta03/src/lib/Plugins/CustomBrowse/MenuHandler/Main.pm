# 			MenuHandler::Main module
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

package Plugins::CustomBrowse::MenuHandler::Main;

use strict;

use base 'Class::Data::Accessor';
use Plugins::CustomBrowse::MenuHandler::BaseMenuHandler;
our @ISA = qw(Plugins::CustomBrowse::MenuHandler::BaseMenuHandler);

use Plugins::CustomBrowse::MenuHandler::SQLHandler;
use Plugins::CustomBrowse::MenuHandler::ParameterHandler;
use Plugins::CustomBrowse::MenuHandler::PropertyHandler;
use Plugins::CustomBrowse::MenuHandler::FunctionMenu;
use Plugins::CustomBrowse::MenuHandler::SQLMenu;
use Plugins::CustomBrowse::MenuHandler::TrackDetailsMenu;
use Plugins::CustomBrowse::MenuHandler::ModeMenu;
use Plugins::CustomBrowse::MenuHandler::FolderMenu;
use Plugins::CustomBrowse::MenuHandler::SQLMix;
use Plugins::CustomBrowse::MenuHandler::MenuMix;
use Plugins::CustomBrowse::MenuHandler::ModeMix;
use Plugins::CustomBrowse::MenuHandler::FunctionMix;
use Plugins::CustomBrowse::MenuHandler::SQLPlay;
use Plugins::CustomBrowse::MenuHandler::FunctionPlay;
use Plugins::CustomBrowse::MenuHandler::FunctionCmdPlay;
use Plugins::CustomBrowse::MenuHandler::CLICmdPlay;
use Plugins::CustomBrowse::MenuHandler::AllPlay;

use File::Spec::Functions qw(:ALL);

sub new {
	my $class = shift;
	my $parameters = shift;

	my $propertyHandler = Plugins::CustomBrowse::MenuHandler::PropertyHandler->new($parameters);
	$parameters->{'propertyHandler'} = $propertyHandler;
	my $parameterHandler = Plugins::CustomBrowse::MenuHandler::ParameterHandler->new($parameters);
	$parameters->{'itemParameterHandler'} = $parameterHandler;
	my $sqlHandler = Plugins::CustomBrowse::MenuHandler::SQLHandler->new($parameters);
	$parameters->{'sqlHandler'} = $sqlHandler;
	my %menuHandlers = (
		'function' => Plugins::CustomBrowse::MenuHandler::FunctionMenu->new($parameters),
		'sql' => Plugins::CustomBrowse::MenuHandler::SQLMenu->new($parameters),
		'trackdetails' => Plugins::CustomBrowse::MenuHandler::TrackDetailsMenu->new($parameters),
		'mode' => Plugins::CustomBrowse::MenuHandler::ModeMenu->new($parameters),
		'folder' => Plugins::CustomBrowse::MenuHandler::FolderMenu->new($parameters)
	);
	my %mixHandlers = (
		'sql' => Plugins::CustomBrowse::MenuHandler::SQLMix->new($parameters),
		'function' => Plugins::CustomBrowse::MenuHandler::FunctionMix->new($parameters),
		'mode' => Plugins::CustomBrowse::MenuHandler::ModeMix->new($parameters),
		'menu' => Plugins::CustomBrowse::MenuHandler::MenuMix->new($parameters)
	);
	my %playHandlers = (
		'sql' => Plugins::CustomBrowse::MenuHandler::SQLPlay->new($parameters),
		'function' => Plugins::CustomBrowse::MenuHandler::FunctionPlay->new($parameters),
		'functioncmd' => Plugins::CustomBrowse::MenuHandler::FunctionCmdPlay->new($parameters),
		'clicmd' => Plugins::CustomBrowse::MenuHandler::CLICmdPlay->new($parameters),
		'all' => Plugins::CustomBrowse::MenuHandler::AllPlay->new($parameters),
	);
	$parameters->{'menuHandlers'} = \%menuHandlers;
	$parameters->{'mixHandlers'} = \%mixHandlers;
	$parameters->{'playHandlers'} = \%playHandlers;

	my $self = $class->SUPER::new($parameters);
	bless $self,$class;
	$mixHandlers{'menu'}->menuHandler($self);
	$mixHandlers{'sql'}->playHandler($self);
	return $self;
}

1;

__END__
