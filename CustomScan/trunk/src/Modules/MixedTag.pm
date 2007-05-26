#         CustomScan::Modules::MixedTag module
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


use strict;
use warnings;
                   
package Plugins::CustomScan::Modules::MixedTag;

use Slim::Utils::Misc;
use Slim::Utils::Unicode;
use DBI qw(:sql_types);
use Slim::Utils::Strings qw(string);

my %friendlyNames = ();
my %friendlyNamesList = ();
sub getCustomScanFunctions {
	my %functions = (
		'id' => 'mixedtag',
		'order' => '60',
		'defaultenabled' => 1,
		'name' => 'Mixed Tag',
		'description' => "This module scans information from both SlimServer and Custom Tag scanning module and stores it in a common place. If you leave one of the tag fields empty in the settings it means that that information isnt scanned. Multiple value can be specified with a comma character as separator. To use custom tags these must first have been scanned with the Custom Tag scanning module, this is done automatically if both scanning modules are included in automatic scanning and you perform a Scan All operation, but if not you will have to make sure to run the Custom Tag scanning module first, before you run this scaning module",
		'alwaysRescanTrack' => 1,
		'exitScanTrack' => \&exitScanTrack,
		'properties' => [
			{
				'id' => 'mixedtagartisttags',
				'name' => 'Artist tags',
				'description' => 'Tag names to store SlimServer artists as',
				'type' => 'text',
				'value' => 'ARTIST'
			},
			{
				'id' => 'mixedtagalbumartisttags',
				'name' => 'Album Artist tags',
				'description' => 'Tag names to store SlimServer album artists as',
				'type' => 'text',
				'value' => 'ARTIST,ALBUMARTIST'
			},
			{
				'id' => 'mixedtagtrackartisttags',
				'name' => 'Track Artist tags',
				'description' => 'Tag names to store SlimServer track artists as',
				'type' => 'text',
				'value' => 'TRACKARTIST'
			},
			{
				'id' => 'mixedtagconductortags',
				'name' => 'Conductor tags',
				'description' => 'Tag names to store SlimServer conductors as',
				'type' => 'text',
				'value' => 'CONDUCTOR'
			},
			{
				'id' => 'mixedtagcomposertags',
				'name' => 'Composer tags',
				'description' => 'Tag names to store SlimServer composers as',
				'type' => 'text',
				'value' => 'COMPOSER'
			},
			{
				'id' => 'mixedtagbandtags',
				'name' => 'Band tags',
				'description' => 'Tag names to store SlimServer bands as',
				'type' => 'text',
				'value' => 'BAND'
			},
			{
				'id' => 'mixedtagalbumtags',
				'name' => 'Album tags',
				'description' => 'Tag names to store SlimServer albums as',
				'type' => 'text',
				'value' => 'ALBUM'
			},
			{
				'id' => 'mixedtaggenretags',
				'name' => 'Genre tags',
				'description' => 'Tag name to store SlimServer genres as',
				'type' => 'text',
				'value' => 'GENRE'
			},
			{
				'id' => 'mixedtagyeartags',
				'name' => 'Year tags',
				'description' => 'Tag name to store SlimServer years as',
				'type' => 'text',
				'value' => 'YEAR'
			},
			{
				'id' => 'mixedtagcustomtags',
				'name' => 'Include custom tags',
				'description' => 'Include the custom tags scanned with the Custom Tag scanning module',
				'type' => 'checkbox',
				'value' => '1'
			},
			{
				'id' => 'mixedtagfriendlynames',
				'name' => 'Names to show for user',
				'description' => 'The mapping between real tag names and names shown to user, syntax: tag(single item name:multiple items name)',
				'type' => 'text',
				'value' => 'ALBUM(Album:Albums),ARTIST(Artist:Artists),GENRE(Genre:Genres),YEAR(Year:Years),CONDUCTOR(Conductor:Contuctors),COMPOSER(Composer:Composers),BAND(Band:Bands),TRACKARTIST(Track Artist:Track Artists),ALBUMARTIST(Album Artist:Album Artists)'
			}
		]
	);
	return \%functions;
}


sub getFriendlyNameForMixedTagList {
	my $self = shift;
	my $client = shift;
	my $item = shift;

	my $name = getFriendlyNameByTagName($item->{'itemid'},1);
	if(!defined($name)) {
		$name = getFriendlyNameByTagName($item->{'itemid'});
		if(!defined($name)) {
			return $item->{'itemid'}."s";
		}else {
			return $name."s";
		}
	}
	return $name;
}
sub getFriendlyNameForMixedTag {
	my $self = shift;
	my $client = shift;
	my $item = shift;

	my $name = getFriendlyNameByTagName($item->{'itemid'});
	if(!defined($name)) {
		return $item->{'itemid'};
	}
	return $name;
}

sub getFriendlyNameByTagName {
	my $tagName = shift;
	my $multiple = shift;

	my $names = undef;
	if($multiple) {
		$names = \%friendlyNamesList;
	}else {
		$names = \%friendlyNames;
	}
	if(defined($names->{$tagName})) {
		return $names->{$tagName};
	}else {
		if(scalar(keys %$names)==0) {
			parseTag(Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagfriendlynames"));		
			parseTag(Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagartisttags"));		
			parseTag(Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagalbumartisttags"));		
			parseTag(Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagtrackartisttags"));		
			parseTag(Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagconductortags"));		
			parseTag(Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagcomposertags"));		
			parseTag(Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagbandtags"));		
			parseTag(Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagalbumtags"));		
			parseTag(Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtaggenretags"));		
			parseTag(Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagyeartags"));		
		}
		if(defined($names->{$tagName})) {
			return $names->{$tagName};
		}
	}
	return undef;
}
sub parseTag {
	my $tags = shift;
	my @tagArray = split(/\s*,\s*/,$tags);
	for my $tag (@tagArray) {
		if($tag =~ /^\s*(.+)\s*\((.+):(.+)\)\s*$/) {
			parseAndSetFriendlyNames($1,$2,$3);
		}elsif($tag =~ /^\s*(.+)\s*\((.+)\)\s*$/) {
			parseAndSetFriendlyNames($1,$2);
		}
	}
}
sub exitScanTrack {
	debugMsg("Scanning init track\n");
	%friendlyNames = ();
	%friendlyNamesList = ();
	my $tags = Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagartisttags");
	updateTags($tags,"INSERT INTO customscan_track_attributes (track,url,musicbrainz_id,module,attr,value,valuesort,extravalue,valuetype) SELECT tracks.id,tracks.url,case when tracks.musicbrainz_id regexp '.+-.+'>0 then tracks.musicbrainz_id else null end,'mixedtag',?,contributors.name,contributors.namesort,contributors.id,'artist' from tracks,contributor_track,contributors where tracks.audio=1 and tracks.id=contributor_track.track and contributor_track.role=1 and contributor_track.contributor=contributors.id");

	$tags = Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagalbumartisttags");
	updateTags($tags,"INSERT INTO customscan_track_attributes (track,url,musicbrainz_id,module,attr,value,valuesort,extravalue,valuetype) SELECT tracks.id,tracks.url,case when tracks.musicbrainz_id regexp '.+-.+'>0 then tracks.musicbrainz_id else null end,'mixedtag',?,contributors.name,contributors.namesort,contributors.id,'artist' from tracks,contributor_track,contributors where tracks.audio=1 and tracks.id=contributor_track.track and contributor_track.role=5 and contributor_track.contributor=contributors.id");

	$tags = Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagtrackartisttags");
	updateTags($tags,"INSERT INTO customscan_track_attributes (track,url,musicbrainz_id,module,attr,value,valuesort,extravalue,valuetype) SELECT tracks.id,tracks.url,case when tracks.musicbrainz_id regexp '.+-.+'>0 then tracks.musicbrainz_id else null end,'mixedtag',?,contributors.name,contributors.namesort,contributors.id,'artist' from tracks,contributor_track,contributors where tracks.audio=1 and tracks.id=contributor_track.track and contributor_track.role=6 and contributor_track.contributor=contributors.id");

	$tags = Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagconductortags");
	updateTags($tags,"INSERT INTO customscan_track_attributes (track,url,musicbrainz_id,module,attr,value,valuesort,extravalue,valuetype) SELECT tracks.id,tracks.url,case when tracks.musicbrainz_id regexp '.+-.+'>0 then tracks.musicbrainz_id else null end,'mixedtag',?,contributors.name,contributors.namesort,contributors.id,'artist' from tracks,contributor_track,contributors where tracks.audio=1 and tracks.id=contributor_track.track and contributor_track.role=3 and contributor_track.contributor=contributors.id");

	$tags = Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagcomposertags");
	updateTags($tags,"INSERT INTO customscan_track_attributes (track,url,musicbrainz_id,module,attr,value,valuesort,extravalue,valuetype) SELECT tracks.id,tracks.url,case when tracks.musicbrainz_id regexp '.+-.+'>0 then tracks.musicbrainz_id else null end,'mixedtag',?,contributors.name,contributors.namesort,contributors.id,'artist' from tracks,contributor_track,contributors where tracks.audio=1 and tracks.id=contributor_track.track and contributor_track.role=2 and contributor_track.contributor=contributors.id");

	$tags = Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagbandtags");
	updateTags($tags,"INSERT INTO customscan_track_attributes (track,url,musicbrainz_id,module,attr,value,valuesort,extravalue,valuetype) SELECT tracks.id,tracks.url,case when tracks.musicbrainz_id regexp '.+-.+'>0 then tracks.musicbrainz_id else null end,'mixedtag',?,contributors.name,contributors.namesort,contributors.id,'artist' from tracks,contributor_track,contributors where tracks.audio=1 and tracks.id=contributor_track.track and contributor_track.role=4 and contributor_track.contributor=contributors.id");

	$tags = Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagalbumtags");
	updateTags($tags,"INSERT INTO customscan_track_attributes (track,url,musicbrainz_id,module,attr,value,valuesort,extravalue,valuetype) SELECT tracks.id,tracks.url,case when tracks.musicbrainz_id regexp '.+-.+'>0 then tracks.musicbrainz_id else null end,'mixedtag',?,albums.title,albums.titlesort,albums.id,'album' from tracks,albums where tracks.audio=1 and tracks.album=albums.id");

	$tags = Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtaggenretags");
	updateTags($tags,"INSERT INTO customscan_track_attributes (track,url,musicbrainz_id,module,attr,value,valuesort,extravalue,valuetype) SELECT tracks.id,tracks.url,case when tracks.musicbrainz_id regexp '.+-.+'>0 then tracks.musicbrainz_id else null end,'mixedtag',?,genres.name,genres.namesort,genres.id,'genre' from tracks,genre_track,genres where tracks.audio=1 and tracks.id=genre_track.track and genre_track.genre=genres.id");

	$tags = Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagyeartags");
	updateTags($tags,"INSERT INTO customscan_track_attributes (track,url,musicbrainz_id,module,attr,value,valuesort,extravalue,valuetype) SELECT tracks.id,tracks.url,case when tracks.musicbrainz_id regexp '.+-.+'>0 then tracks.musicbrainz_id else null end,'mixedtag',?,if(tracks.year=0,'".string('UNK')."',tracks.year),if(tracks.year=0,'".uc(string('UNK'))."',tracks.year),tracks.year,'year' from tracks where tracks.audio=1");

	$tags = Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagcustomtags");
	if($tags) {
		eval {
			debugMsg("Writing custom tags\n");
			my $dbh = Slim::Schema->storage->dbh();
			my $sth = $dbh->prepare("INSERT INTO customscan_track_attributes (track,url,musicbrainz_id,module,attr,value,valuesort,extravalue) SELECT tracks.id,tracks.url,case when tracks.musicbrainz_id regexp '.+-.+'>0 then tracks.musicbrainz_id else null end,'mixedtag',customscan_track_attributes.attr,customscan_track_attributes.value,customscan_track_attributes.valuesort,customscan_track_attributes.value from tracks,customscan_track_attributes where tracks.audio=1 and tracks.id=customscan_track_attributes.track and customscan_track_attributes.module='customtag'");
			$sth->execute();
		};
		if ($@) {
			Slim::Utils::Misc::msg("CustomScan: Failed to scan SlimServer Custom Scan custom tags: $@\n");
		}	
	}
	parseTag(Plugins::CustomScan::Plugin::getCustomScanProperty("mixedtagfriendlynames"));
}

sub parseAndSetFriendlyNames {
	my $tag = shift;
	my $name = shift;
	my $nameList = shift;

	$friendlyNames{$tag}=$name;
	if(defined($nameList)) {
		$friendlyNamesList{$tag}=$nameList;
	}
}

sub updateTags {
	my $tags = shift;
	my $sql = shift;

	my @tagArray = split(/\s*,\s*/,$tags);
	for my $tag (@tagArray) {
		if($tag =~ /^\s*(.+)\s*\((.+):(.+)\)\s*$/) {
			parseAndSetFriendlyNames($1,$2,$3);
			$tag = $1;
		}elsif($tag =~ /^\s*(.+)\s*\((.+)\)\s*$/) {
			parseAndSetFriendlyNames($1,$2);
			$tag = $1;
		}
		eval {
			debugMsg("Writing $tag using: $sql\n");
			my $dbh = Slim::Schema->storage->dbh();
			my $sth = $dbh->prepare($sql);
			$sth->bind_param(1,$tag,SQL_VARCHAR);
			$sth->execute();
		};
		if ($@) {
			Slim::Utils::Misc::msg("CustomScan: Failed to scan SlimServer tags: $@\n");
		}	
	}
}

sub quoteValue {
	my $value = shift;
	if(defined($value)) {
		$value = Slim::Schema->storage->dbh()->quote($value);
		$value = substr($value, 1, -1);
	}
	return $value;
}
sub getMixedTagMenuItems {
	my $self = shift;
	my $client = shift;
	my $parameters = shift;

	my $tags = $parameters->{'usedtags'};
	my $supportedTags = undef;
	if(defined($tags)) {
		my @tagArray = split(/\,/,$tags);
		for my $tag (@tagArray) {
			my $value = undef;
			if($tag =~ /^(.*)?\(.*\)$/) {
				$tag = $1;
				$value = $1;
			}
			$tag = uc($tag);
			if(defined($supportedTags)) {
				$supportedTags .= ",";
			}else {
				$supportedTags = "";
			}
			$supportedTags .= "'".quoteValue($tag)."'";
		}
	}
	my @items = ();
	my $currentTag = undef;
	my $currentValue = undef;
	if(defined($parameters)) {
		for my $p (keys %$parameters) {
			if($p =~ /^level(\d+)_(.+)$/) {
				my %filterItem = (
					'id' => $1,
					'tag' => $2,
					'value' => $parameters->{$p}
				);
				push @items,\%filterItem;
			}elsif($p =~ /^level(\d+)$/) {
				my %filterItem = (
					'id' => $1,
					'tag' => $parameters->{$p},
					'value' => undef
				);
				push @items,\%filterItem;
			}
		}
	}
	@items = sort {return $a->{'id'} cmp $b->{'id'}} @items;

	my %selectedValues = ();
	my $selectedTags = undef;
	for my $it (@items) {
		if(defined($it->{'value'})) {
			if(!defined($selectedValues{$it->{'tag'}})) {
				$selectedValues{$it->{'tag'}} = '';
			}else {
				$selectedValues{$it->{'tag'}} .= ',';
			}
			$selectedValues{$it->{'tag'}} .= "'".quoteValue($it->{'value'})."'";
			if(defined($selectedTags)) {
				$selectedTags .= ",";
			}else {
				$selectedTags = "";
			}
			$selectedTags .= "'".quoteValue($it->{'tag'})."'";
		}
	}

	my $currentLevel = scalar(@items)+1;
	my $currentItem = pop @items;
	my $levelTag = undef;
	if(defined($currentItem) && !defined($currentItem->{'value'})) {
		$currentTag = $currentItem->{'tag'};
	}elsif(defined($currentItem)) {
		$levelTag = $currentItem->{'tag'};
	}

	my $tagssql = undef;
	if(defined($currentTag)) {
		$tagssql = "select customscan_track_attributes.extravalue,customscan_track_attributes.value,substr(ifnull(customscan_track_attributes.valuesort,customscan_track_attributes.value),1,1),customscan_track_attributes.valuetype from customscan_track_attributes ";
		for my $it (@items) {
			if(defined($it->{'value'})) {
				my $attr = "attr".$it->{'id'};
				$tagssql .= "join customscan_track_attributes $attr on customscan_track_attributes.track=$attr.track and $attr.module='mixedtag' and $attr.attr='".quoteValue($it->{'tag'})."' and $attr.extravalue='".quoteValue($it->{'value'})."' ";
			}
		}
		if(defined($parameters->{'activelibrary'}) && $parameters->{'activelibrary'}) {
				$tagssql .= " join multilibrary_track on customscan_track_attributes.track=multilibrary_track.track and multilibrary_track.library=\{clientproperty.plugin_multilibrary_activelibraryno\} ";		
		}elsif(defined($parameters->{'library'})) {
				$tagssql .= " join multilibrary_track on customscan_track_attributes.track=multilibrary_track.track and multilibrary_track.library=".$parameters->{'library'};		
		}
		$tagssql .= " where customscan_track_attributes.module='mixedtag' and customscan_track_attributes.attr='".quoteValue($currentTag)."'";
		if(defined($selectedValues{$currentTag})) {
			my $values = $selectedValues{$currentTag};
			$tagssql .=" and customscan_track_attributes.extravalue not in ($values)";
		}
		if(defined($parameters->{'track'}) && !defined($selectedTags)) {
			$tagssql .=" and customscan_track_attributes.track=".$parameters->{'track'};
		}
		$tagssql .=" group by customscan_track_attributes.extravalue order by ifnull(customscan_track_attributes.valuesort,customscan_track_attributes.value)";
	}

	my $taggroupssql = undef;
	my $trackssql = undef;
	my $albumssql = undef;
	if(!defined($currentTag)) {
		$taggroupssql = "select customscan_track_attributes.attr,customscan_track_attributes.attr,substr(customscan_track_attributes.attr,1,1) from customscan_track_attributes ";
		if(defined($parameters->{'activelibrary'}) && $parameters->{'activelibrary'}) {
				$taggroupssql .= " join multilibrary_track on customscan_track_attributes.track=multilibrary_track.track and multilibrary_track.library=\{clientproperty.plugin_multilibrary_activelibraryno\} ";		
		}elsif(defined($parameters->{'library'})) {
				$taggroupssql .= " join multilibrary_track on customscan_track_attributes.track=multilibrary_track.track and multilibrary_track.library=".$parameters->{'library'};		
		}
		$taggroupssql .= " where ";
		for my $it (@items) {
			if(defined($it->{'value'})) {
				$taggroupssql .= "exists(select * from customscan_track_attributes attr where attr.module='mixedtag' and customscan_track_attributes.track=attr.track and attr.attr='".quoteValue($it->{'tag'})."' and attr.extravalue='".quoteValue($it->{'value'})."') and ";
			}
		}
		if(defined($currentItem)) {
			$taggroupssql .= "exists(select * from customscan_track_attributes attr where attr.module='mixedtag' and customscan_track_attributes.track=attr.track and attr.attr='".quoteValue($currentItem->{'tag'})."' and attr.extravalue='".quoteValue($currentItem->{'value'})."') and ";
		}
		if(scalar(keys %selectedValues)>0) {
			my $subquery = undef;
			for my $key (keys %selectedValues) {
				my $values = $selectedValues{$key};
				if(defined($subquery)) {
					$subquery .= " or ";
				}else {
					$subquery = "(";
				}
				$subquery .= "(customscan_track_attributes.attr='".quoteValue($key)."' and customscan_track_attributes.extravalue not in ($values))";
			}
			$taggroupssql .= "$subquery or customscan_track_attributes.attr not in ($selectedTags)) and ";
		}
		if(defined($supportedTags)) {
			$taggroupssql .=" customscan_track_attributes.attr in ($supportedTags) and "
		}
		if(defined($parameters->{'track'}) && !defined($selectedTags)) {
			$taggroupssql .=" customscan_track_attributes.track=".$parameters->{'track'}." and ";
		}
		$taggroupssql .= "customscan_track_attributes.module='mixedtag' group by customscan_track_attributes.attr order by customscan_track_attributes.attr";
	}

	# Create All songs SQL
	$trackssql = "select tracks.id,tracks.title,substr(tracks.titlesort,1,1) from tracks ";
	for my $it (@items) {
		if(defined($it->{'value'})) {
			my $attr = "attr".$it->{'id'};
			$trackssql .= "join customscan_track_attributes $attr on tracks.id=$attr.track and $attr.module='mixedtag' and $attr.attr='".quoteValue($it->{'tag'})."' and $attr.extravalue='".quoteValue($it->{'value'})."' ";
		}
	}
	if(defined($currentItem->{'value'})) {
		$trackssql .= "join customscan_track_attributes on tracks.id=customscan_track_attributes.track and customscan_track_attributes.module='mixedtag' and customscan_track_attributes.attr='".quoteValue($currentItem->{'tag'})."' and customscan_track_attributes.extravalue='".quoteValue($currentItem->{'value'})."' ";
	}
	if(defined($parameters->{'activelibrary'}) && $parameters->{'activelibrary'}) {
		$trackssql .= " join multilibrary_track on tracks.id=multilibrary_track.track and multilibrary_track.library=\{clientproperty.plugin_multilibrary_activelibraryno\} ";		
	}elsif(defined($parameters->{'library'})) {
		$trackssql .= " join multilibrary_track on tracks.id=multilibrary_track.track and multilibrary_track.library=".$parameters->{'library'};		
	}
	$trackssql .= " where tracks.audio=1";
	$trackssql .=" group by tracks.id order by tracks.disc,tracks.tracknum";

	if(defined($currentItem)) {

		if(!defined($parameters->{'findalbums'}) || $parameters->{'findalbums'} ne '0') {
			# Create All albums SQL
			$albumssql = "select albums.id,albums.title,substr(albums.titlesort,1,1) from albums join tracks on tracks.album=albums.id ";
			for my $it (@items) {
				if(defined($it->{'value'})) {
					my $attr = "attr".$it->{'id'};
					$albumssql .= "join customscan_track_attributes $attr on tracks.id=$attr.track and $attr.module='mixedtag' and $attr.attr='".quoteValue($it->{'tag'})."' and $attr.extravalue='".quoteValue($it->{'value'})."' ";
				}
			}
			if(defined($currentItem->{'value'})) {
				$albumssql .= "join customscan_track_attributes on tracks.id=customscan_track_attributes.track and customscan_track_attributes.module='mixedtag' and customscan_track_attributes.attr='".quoteValue($currentItem->{'tag'})."' and customscan_track_attributes.extravalue='".quoteValue($currentItem->{'value'})."' ";
			}
			if(defined($parameters->{'activelibrary'}) && $parameters->{'activelibrary'}) {
				$albumssql .= " join multilibrary_track on tracks.id=multilibrary_track.track and multilibrary_track.library=\{clientproperty.plugin_multilibrary_activelibraryno\} ";		
			}elsif(defined($parameters->{'library'})) {
				$albumssql .= " join multilibrary_track on tracks.id=multilibrary_track.track and multilibrary_track.library=".$parameters->{'library'};		
			}
			$albumssql .= " where tracks.audio=1";
			$albumssql .=" group by albums.id order by albums.titlesort";
		}
	}
	
	my @menus = ();
	if(defined($taggroupssql)) {
		my %menu = (
			'id' => 'level'.$currentLevel,
			'playtype' => 'none',
			'menutype' => 'sql',
			'menudata' => $taggroupssql,
			'menulinks' => 'alpha',
			'playtypeall' => 'none',
			'itemformat' => 'function',
			'itemformatdata' => 'Plugins::CustomScan::Modules::MixedTag::getFriendlyNameForMixedTagList',
			'menufunction' => 'Plugins::CustomScan::Modules::MixedTag::getMixedTagMenuItems'
		);
		if(defined($levelTag)) {
			my $menuName = Plugins::CustomScan::Modules::MixedTag::getFriendlyNameByTagName($levelTag);
			if(!defined($menuName)) {
				$menuName = $levelTag;
			}
			$menu{'menuname'} = $menuName;
		}
		if(defined($parameters->{'track'}) && !defined($selectedTags)) {
			$menu{'menufunction'} .= "|track=".$parameters->{'track'};
		}
		if(defined($parameters->{'usedtags'})) {
			$menu{'menufunction'} .= "|usedtags=".$parameters->{'usedtags'};
		}
		if(defined($parameters->{'findtracks'})) {
			$menu{'menufunction'} .= "|findtracks=".$parameters->{'findtracks'};
		}
		if(defined($parameters->{'findalbums'})) {
			$menu{'menufunction'} .= "|findalbums=".$parameters->{'findalbums'};
		}
		if(defined($parameters->{'playalltracks'})) {
			$menu{'menufunction'} .= "|playalltracks=".$parameters->{'playalltracks'};
		}
		
		if(defined($parameters->{'activelibrary'})) {
			$menu{'menufunction'} .= "|activelibrary=1";
		}elsif(defined($parameters->{'library'})) {
			$menu{'menufunction'} .= "|library=".$parameters->{'library'};
		}
		push @menus,\%menu;
	}

	if(defined($tagssql)) {
		my $menuName = Plugins::CustomScan::Modules::MixedTag::getFriendlyNameByTagName($currentTag,1);
		if(!defined($menuName)) {
			$menuName = Plugins::CustomScan::Modules::MixedTag::getFriendlyNameByTagName($currentTag);
			if(!defined($menuName)) {
				$menuName = $currentTag;
			}
			$menuName .= "s";
		}
		my %menu = (
			'id' => 'level'.$currentLevel."_".$currentTag,
			'menuname' => $menuName,
			'menulinks' => 'alpha',
			'menutype' => 'sql',
			'menudata' => $tagssql,
			'itemtype' => 'sql',
			'playtypeall' => 'none',
			'menufunction' => 'Plugins::CustomScan::Modules::MixedTag::getMixedTagMenuItems'
		);
		if(defined($trackssql)) {
			$menu{'playtype'} = 'sql';
			$menu{'playdata'} = $trackssql;
		}
		if(defined($parameters->{'track'}) && !defined($selectedTags)) {
			$menu{'menufunction'} .= "|track=".$parameters->{'track'};
		}
		if(defined($parameters->{'usedtags'})) {
			$menu{'menufunction'} .= "|usedtags=".$parameters->{'usedtags'};
		}
		if(defined($parameters->{'findtracks'})) {
			$menu{'menufunction'} .= "|findtracks=".$parameters->{'findtracks'};
		}
		if(defined($parameters->{'findalbums'})) {
			$menu{'menufunction'} .= "|findalbums=".$parameters->{'findalbums'};
		}
		if(defined($parameters->{'playalltracks'})) {
			$menu{'menufunction'} .= "|playalltracks=".$parameters->{'playalltracks'};
		}
		
		if(defined($parameters->{'activelibrary'})) {
			$menu{'menufunction'} .= "|activelibrary=1";
		}elsif(defined($parameters->{'library'})) {
			$menu{'menufunction'} .= "|library=".$parameters->{'library'};
		}
		push @menus,\%menu;
	}

	if(defined($albumssql) && scalar(keys %selectedValues)>0) {
		my %trackDetails = (
			'id' => 'trackdetails',
			'menuname' => 'Song',
			'menutype' => 'trackdetails',
			'menudata' => 'track|0'
		);
		my $sql = "select tracks.id,tracks.title from tracks ";
		if(defined($parameters->{'activelibrary'}) && $parameters->{'activelibrary'}) {
			$trackDetails{'menudata'} .= "|library=\{clientproperty.plugin_multilibrary_activelibraryno\}";
			$sql .= " join multilibrary_track on tracks.id=multilibrary_track.track and multilibrary_track.library=\{clientproperty.plugin_multilibrary_activelibraryno\} ";		
		}elsif(defined($parameters->{'library'})) {
			$trackDetails{'menudata'} .= "|library=".$parameters->{'library'};
			$sql .= " join multilibrary_track on tracks.id=multilibrary_track.track and multilibrary_track.library=".$parameters->{'library'};		
		}
		$sql .= " where tracks.audio=1 and tracks.album=\{album\} group by tracks.id order by tracks.disc,tracks.tracknum";
		my %menutracks = (
			'id' => 'track',
			'menuname' => 'Songs',
			'itemformat' => "track",
			'itemtype' => "track",
			'menutype' => 'sql',
			'menudata' => $sql,
			'menu' => \%trackDetails
		);

		if(!defined($parameters->{'playalltracks'}) || $parameters->{'playalltracks'} ne '0') {
			$menutracks{'playtype'} = 'all';
		}
		my %menualbums = (
			'id' => 'album',
			'menuname' => 'Albums',
			'menulinks' => 'alpha',
			'itemformat' => "album",
			'itemtype' => "album",
			'menutype' => 'sql',
			'menudata' => $albumssql,
			'menu' => \%menutracks
		);
		my %allalbums = (
			'id' => 'matchingalbums',
			'playtypeall' => 'none',
			'playtype' => 'sql',
			'playdata' => $albumssql,
			'menuname' => string('PLUGIN_CUSTOMSCAN_MATCHING_ALBUMS'),
			'menu' => \%menualbums
		);
		push @menus,\%allalbums;
	}

	if(defined($trackssql) && (!defined($parameters->{'findtracks'}) || $parameters->{'findtracks'} ne '0') && scalar(keys %selectedValues)>0) {
		my %trackDetails = (
			'id' => 'trackdetails',
			'menuname' => 'Song',
			'menutype' => 'trackdetails',
			'menudata' => 'track|0'
		);
		if(defined($parameters->{'activelibrary'}) && $parameters->{'activelibrary'}) {
			$trackDetails{'menudata'} .= "|library=\{clientproperty.plugin_multilibrary_activelibraryno\}";
		}elsif(defined($parameters->{'library'})) {
			$trackDetails{'menudata'} .= "|library=".$parameters->{'library'};
		}
		my %menutracks = (
			'id' => 'track',
			'menuname' => 'Songs',
			'itemformat' => "track",
			'itemtype' => 'track',
			'menutype' => 'sql',
			'menudata' => $trackssql,
			'menu' => \%trackDetails
		);
		if(!defined($parameters->{'playalltracks'}) || $parameters->{'playalltracks'} ne '0') {
			$menutracks{'playtype'} = 'all';
		}
		my %alltracks = (
			'id' => 'matchingsongs',
			'menuname' => string('PLUGIN_CUSTOMSCAN_MATCHING_SONGS'),
			'playtypeall' => 'none',
			'playtype' => 'sql',
			'playdata' => $trackssql,
			'menu' => \%menutracks
		);
		push @menus,\%alltracks;
	}

	if(scalar(@menus)>1) {
		return \@menus;
	}else {
		return @menus->[0];
	}
}

sub debugMsg
{
	my $message = join '','CustomScan:MixedTag ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_customscan_showmessages"));
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
