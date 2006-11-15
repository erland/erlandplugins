#         CustomScan::Modules::CustomTag module
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


use strict;
use warnings;
                   
package Plugins::CustomScan::Modules::CustomTag;

use Slim::Utils::Misc;

sub getCustomScanFunctions {
	my %functions = (
		'id' => 'customtag',
		'defaultenabled' => 1,
		'name' => 'Custom Tag',
		'alwaysRescanTrack' => 1,
		'scanTrack' => \&scanTrack
	);
	return \%functions;
		
}

sub scanTrack {
	my $track = shift;
	my @result = ();
	debugMsg("Scanning track: ".$track->title."\n");
	my $tags = Slim::Formats->readTags($track->url);
	if(defined($tags)) {
		my $customTagProperty = Plugins::CustomScan::Plugin::getCustomScanProperty("customtags");
		my $singleValueTagProperty = Plugins::CustomScan::Plugin::getCustomScanProperty("singlecustomtags");
		if($customTagProperty) {
			my @singleValueTags = ();
			if($singleValueTagProperty) {
				@singleValueTags = split(/,/,$singleValueTagProperty);
			}
			my %singleValueTagsHash = ();
			for my $singleValueTag (@singleValueTags) {
				$singleValueTagsHash{uc($singleValueTag)} = 1;
			}

			my @customTags = split(/,/,$customTagProperty);
			my %customTagsHash = ();
			for my $customTag (@customTags) {
				$customTagsHash{uc($customTag)} = 1;
			}

			for my $tag (keys %$tags) {
				$tag = uc($tag);
				if($customTagsHash{$tag}) {
					my $values = $tags->{$tag};
					if(!defined($singleValueTagsHash{$tag})) {
						my @arrayValues = Slim::Music::Info::splitTag($tags->{$tag});
						$values = \@arrayValues;
					}
					if(ref($values) eq 'ARRAY') {
						my $valueArray = $values;
						for my $value (@$valueArray) {
							my %item = (
								'name' => $tag,
								'value' => $value
							);
							push @result,\%item;
						}
					}else {
						my %item = (
							'name' => $tag,
							'value' => $values
						);
						push @result,\%item;
					}
				}
			}
		}
	}
	return \@result;
}

sub debugMsg
{
	my $message = join '','CustomScan:CustomTag ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_customscan_showmessages"));
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
