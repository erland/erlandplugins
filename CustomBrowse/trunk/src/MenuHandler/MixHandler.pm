# 			MenuHandler::MixHandler module
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

package Plugins::CustomBrowse::MenuHandler::MixHandler;

use strict;

use base qw(Slim::Utils::Accessor);

use File::Spec::Functions qw(:ALL);
use Slim::Utils::Prefs;

__PACKAGE__->mk_accessor( rw => qw(logHandler pluginId pluginVersion propertyHandler itemParameterHandler mixHandlers mixes) );
my $serverPrefs = preferences('server');
my $driver;

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new();
	$self->logHandler($parameters->{'logHandler'});
	$self->pluginId($parameters->{'pluginId'});
	$self->pluginVersion($parameters->{'pluginVersion'});
	$self->propertyHandler($parameters->{'propertyHandler'});
	$self->itemParameterHandler($parameters->{'itemParameterHandler'});
	$self->mixHandlers($parameters->{'mixHandlers'});

	$driver = $serverPrefs->get('dbsource');
	$driver =~ s/dbi:(.*?):(.*)$/$1/;

	if(UNIVERSAL::can("Slim::Schema","sourceInformation")) {
		my ($source,$username,$password);
		($driver,$source,$username,$password) = Slim::Schema->sourceInformation;
	}

	return $self;
}

sub registerMixHandler {
	my $self = shift;
	my $id = shift;
	my $mixer = shift;

	$self->mixHandlers->{$id}=$mixer;
}

sub unregisterMixHandler {
	my $self = shift;
	my $id = shift;

	delete $self->mixHandlers->{$id};
}

sub setGlobalMixes {
	my $self = shift;
	my $mixes = shift;

	$self->mixes($mixes);
}
sub getGlobalMixes {
	my $self = shift;

	return $self->mixes;
}

sub isInterfaceSupported {
	my $self = shift;
	my $client = shift;
	my $mix = shift;
	my $interfaceType = shift;

	my $mixHandler = $self->mixHandlers->{$mix->{'mixtype'}};
	if($mixHandler && $mixHandler->isInterfaceSupported($client,$mix,$interfaceType)) {
		return 1;
	}
	return 0;
}

sub prepareMix {
	my $self = shift;
	my $client = shift;
	my $mix = shift;
	my $item = shift;
	my $interfaceType = shift;

	my $mixHandler = $self->mixHandlers->{$mix->{'mixtype'}};
	if($mixHandler) {
		return $mixHandler->prepareMix($client,$mix,$item,$interfaceType);
	}
	return $mix;
}

sub getMixData {
	my $self = shift;
	my $client = shift;
	my $mix = shift;
	my $item = shift;
	my $interfaceType = shift;
	my $parameter = shift;

	my $mixHandler = $self->mixHandlers->{$mix->{'mixtype'}};
	if($mixHandler) {
		return $mixHandler->getMixData($client,$mix,$item,$interfaceType,$parameter);
	}
	return undef;
}

sub getPreparedMixes {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $interfaceType = shift;

	my $mixes = $self->getMixes($client,$item,$interfaceType);
	my @webMixes = ();
	if(scalar(@$mixes)>0) {
		for my $mix (@$mixes) {
			if(!$self->isInterfaceSupported($client,$mix,$interfaceType)) {
				next;
			}
			my %webMix = (
				'name' => $mix->{'mixname'},
				'id' => $mix->{'id'}
			);
			my $image = $mix->{'miximage'};
			if(defined($image)) {
				$webMix{'image'} = $image;
			}

			my $parameters = $self->propertyHandler->getProperties();
			if(defined($item->{'customitemtype'})) {
				$parameters->{'itemtype'} = escape($item->{'customitemtype'});
			}else {
				$parameters->{'itemtype'} = $item->{'itemtype'};
			}
			$parameters->{'itemid'} = $item->{'itemid'};
			$parameters->{'itemname'} = escape(defined($item->{'itemvalue'})?$item->{'itemvalue'}:$item->{'itemname'});
			$parameters->{'itemnameuri'} = escape($parameters->{'itemname'});
			addStandardParameters($parameters);
			my $keywords = _combineKeywords($item->{'keywordparameters'},$item->{'parameters'},$parameters);

			my $url = $self->getMixData($client, $mix, $keywords, $interfaceType, 'mixurl');
			if(defined($url)) {
				$url = $self->itemParameterHandler->replaceParameters($client,$url,$keywords);
				$webMix{'url'} = $url;
				$webMix{'urlcontext'} = $mix->{'mixurlcontext'};
			}
			push @webMixes,\%webMix;
		}
	}
	return \@webMixes;
}

sub addStandardParameters {
	my $params = shift;

	if($driver eq 'mysql') {
		$params->{'RANDOMFUNCTION'} = "rand()";
	}else {
		$params->{'RANDOMFUNCTION'} = "random()";
	}
}

sub getMixes {
	my $self = shift;
	my $client = shift;
	my $item = shift;
	my $interfaceType = shift;

	my @mixes = ();
	if(defined($item->{'mix'})) {
		if(ref($item->{'mix'}) eq 'ARRAY') {
			my $customMixes = $item->{'mix'};
			for my $mix (@$customMixes) {
				if(defined($mix->{'mixtype'}) && defined($mix->{'mixdata'})) {
					if($mix->{'mixtype'} eq 'allforcategory') {
						my $browseMixes = $self->mixes;
						foreach my $key (keys %$browseMixes) {
							my $globalMix = $browseMixes->{$key};
							my $globalMixCategory = $globalMix->{'mixcategory'} if exists $globalMix->{'mixcategory'};
							if($globalMix->{'enabled'} && (!exists $globalMix->{'mixcategory'} || $mix->{'mixdata'} =~ /^$globalMixCategory$/ )) {
								if($self->checkMix($client, $globalMix, $item, $interfaceType)) {
									$globalMix = $self->prepareMix($client, $globalMix, $item, $interfaceType);
									push @mixes,$globalMix;
								}
							}
						}
					}elsif(defined($mix->{'mixname'}))  {
						if($self->checkMix($client, $mix, $item,$interfaceType)) {
							$mix = $self->prepareMix($client, $mix, $item, $interfaceType);
							push @mixes,$mix;
						}
					}
				}
			}
		}else {
			my $mix = $item->{'mix'};
			if(defined($mix->{'mixtype'}) && defined($mix->{'mixdata'})) {
				if($mix->{'mixtype'} eq 'allforcategory') {
					my $browseMixes = $self->mixes;
					foreach my $key (keys %$browseMixes) {
						my $globalMix = $browseMixes->{$key};
						my $globalMixCategory = $globalMix->{'mixcategory'} if exists $globalMix->{'mixcategory'};
						if($globalMix->{'enabled'} && (!exists $globalMix->{'mixcategory'} || $mix->{'mixdata'}  =~ /^$globalMixCategory$/)) {
							if($self->checkMix($client, $globalMix, $item,$interfaceType)) {
								$globalMix = $self->prepareMix($client, $globalMix, $item, $interfaceType);
								push @mixes,$globalMix;
							}
						}
					}
				}elsif(defined($mix->{'mixname'}))  {
					if($self->checkMix($client, $mix, $item,$interfaceType)) {
						$mix = $self->prepareMix($client, $mix, $item, $interfaceType);
						push @mixes,$mix;
					}
				}
			}
		}
	}
	if(defined($item->{'itemtype'}) || defined($item->{'customitemtype'})) {
		my $type;
		if(defined($item->{'customitemtype'})) {
			$type = escape($item->{'customitemtype'});
		}else {
			$type = $item->{'itemtype'};
		}
		my $browseMixes = $self->mixes;
		foreach my $key (keys %$browseMixes) {
			my $mix = $browseMixes->{$key};

			my $mixCategory = $mix->{'mixcategory'} if exists $mix->{'mixcategory'};
			if($mix->{'enabled'} && (!exists $mix->{'mixcategory'} || $type =~ /^$mixCategory$/)) {
				if($self->checkMix($client, $mix, $item,$interfaceType)) {
					$mix = $self->prepareMix($client, $mix, $item, $interfaceType);
					push @mixes,$mix;
				}
			}
		}
	}
	@mixes = sort { $a->{'mixname'} cmp $b->{'mixname'} } @mixes;
	return \@mixes;
}

sub checkMix {
	my ($self, $client, $mix, $item, $interfaceType) = @_;

	if(defined($interfaceType)) {
		if(!$self->isInterfaceSupported($client,$mix,$interfaceType)) {
			return 0;
		}
	}
	if(defined($mix->{'mixchecktype'})) {
		my $mixHandler = $self->mixHandlers->{$mix->{'mixchecktype'}};
		if(defined($mixHandler)) {
			my $parameters = $self->propertyHandler->getProperties();
			if(defined($item->{'customitemtype'})) {
				$parameters->{'itemtype'} = escape($item->{'customitemtype'});
			}else {
				$parameters->{'itemtype'} = $item->{'itemtype'};
			}
			$parameters->{'itemid'} = $item->{'itemid'};
			$parameters->{'itemname'} = $item->{'itemname'};
			addStandardParameters($parameters);
			my $keywords = _combineKeywords($item->{'keywordparameters'},$item->{'parameters'},$parameters);
			
			if(defined($item->{'itemobj'})) {
				return $mixHandler->checkMix($client,$mix,$keywords,$item->{'itemobj'});
			}else {
				return $mixHandler->checkMix($client,$mix,$keywords,undef);
			}
		}else {
			return 1;
		}
	}else {
		return 1;
	}
	return 0;
}

sub executeMix {
	my $self = shift;
	my $client = shift;
	my $mix = shift;
	my $keywords = shift;
	my $addOnly = shift;
	my $interfaceType = shift;
	my $obj = shift;
	
	if(defined($mix->{'mixtype'})) {
		my $mixHandler = $self->mixHandlers->{$mix->{'mixtype'}};
		if(defined($mixHandler)) {
			$mixHandler->executeMix($client,$mix,$keywords,$addOnly,$interfaceType,$obj);
		}
	}
}

sub _combineKeywords {
	my $parentKeywords = shift;
	my $optionKeywords = shift;
	my $selectionKeywords = shift;

	my %keywords = ();
	if(defined($parentKeywords)) {
		foreach my $keyword (keys %$parentKeywords) {
			$keywords{$keyword} = $parentKeywords->{$keyword};
		}
	}
	if(defined($optionKeywords)) {
		foreach my $keyword (keys %$optionKeywords) {
			$keywords{$keyword} = $optionKeywords->{$keyword};
		}
	}
	if(defined($selectionKeywords)) {
		foreach my $keyword (keys %$selectionKeywords) {
			$keywords{$keyword} = $selectionKeywords->{$keyword};
		}
	}
	return \%keywords;
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
