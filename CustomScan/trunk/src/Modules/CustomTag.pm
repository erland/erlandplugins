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
use Slim::Utils::Unicode;
use MP3::Info;

my %rawTagNames = (
	'TT1' => 'CONTENTGROUP',
	'TIT1' => 'CONTENTGROUP',
	'TT2' => 'TITLE',
	'TIT2' => 'TITLE',
	'TT3' => 'SUBTITLE',
	'TIT3' => 'SUBTITLE',
	'TP1' => 'ARTIST',
	'TPE1' => 'ARTIST',
	'TP2' => 'BAND',
	'TPE2' => 'BAND',
	'TP3' => 'CONDUCTOR',
	'TPE3' => 'CONDUCTOR',
	'TP4' => 'MIXARTIST',
	'TPE4' => 'MIXARTIST',
	'TCM' => 'COMPOSER',
	'TCOM' => 'COMPOSER',
	'TXT' => 'LYRICIST',
	'TEXT' => 'LYRICIST',
	'TLA' => 'LANGUAGE',
	'TLAN' => 'LANGUAGE',
	'TCO' => 'CONTENTTYPE', #GENRE
	'TCON' => 'CONTENTTYPE', #GENRE
	'TAL' => 'ALBUM',
	'TALB' => 'ALBUM',
	'TRK' => 'TRACKNUM',
	'TRCK' => 'TRACKNUM',
	'TPA' => 'PARTINSET', #SET
	'TPOS' => 'PARTINSET', #SET
	'TRC' => 'ISRC',
	'TSRC' => 'ISRC',
	'TDA' => 'DATE',
	'TDAT' => 'DATE',
	'TYE' => 'YEAR',
	'TYER' => 'YEAR',
	'TIM' => 'TIME',
	'TIME' => 'TIME',
	'TRD' => 'RECORDINGDATES',
	'TRDA' => 'RECORDINGDATES',
	'TRDC' => 'RECORDINGTIME', #YEAR
	'TOR' => 'ORIGYEAR',
	'TORY' => 'ORIGYEAR',
	'TDOR' => 'ORIGRELEASETIME',
	'TBP' => 'BPM',
	'TBPM' => 'BPM',
	'TMT' => 'MEDIATYPE',
	'TMED' => 'MEDIATYPE',
	'TFT' => 'FILETYPE',
	'TFLT' => 'FILETYPE',
	'TCR' => 'COPYRIGHT',
	'TCOP' => 'COPYRIGHT',
	'TPB' => 'PUBLISHER',
	'TPUB' => 'PUBLISHER',
	'TEN' => 'ENCODEDBY',
	'TENC' => 'ENCODEDBY',
	'TSS' => 'ENCODERSETTINGS',
	'TSSE' => 'ENCODERSETTINGS',
	'TLE' => 'SONGLEN',
	'TLEN' => 'SONGLEN',
	'TSI' => 'SIZE',
	'TSIZ' => 'SIZE',
	'TDY' => 'PLAYLISTDELAY',
	'TDLY' => 'PLAYLISTDELAY',
	'TKE' => 'INITIALKEY',
	'TKEY' => 'INITIALKEY',
	'TOT' => 'ORIGALBUM',
	'TOAL' => 'ORIGALBUM',
	'TOF' => 'ORIGFILENAME',
	'TOFN' => 'ORIGFILENAME',
	'TOA' => 'ORIGARTIST',
	'TOPE' => 'ORIGARTIST',
	'TOL' => 'ORIGLYRICIST',
	'TOLY' => 'ORIGLYRICIST',
	'TOWN' => 'FILEOWNER',
	'TRSN' => 'NETRADIOSTATION',
	'TRSO' => 'NETRADIOOWNER',
	'TSST' => 'SETSUBTITLE',
	'TMOO' => 'MOOD',
	'TPRO' => 'PRODUCEDNOTICE',
	'TDEN' => 'ENCODINGTIME',
	'TDRL' => 'RELEASETIME',
	'TDTG' => 'TAGGINGTIME',
	'TSOA' => 'ALBUMSORTORDER',
	'TSOP' => 'PERFORMERSORTORDER',
	'TSOT' => 'TITLESORTORDER',
	'TXX' => 'USERTEXT',
	'TXXX' => 'USERTEXT',
	'WAF' => 'WWWAUDIOFILE',
	'WOAF' => 'WWWAUDIOFILE',
	'WAR' => 'WWWARTIST',
	'WOAR' => 'WWWARTIST',
	'WAS' => 'WWWAUDIOSOURCE',
	'WOAS' => 'WWWAUDIOSOURCE',
	'WCM' => 'WWWCOMMERCIALINFO',
	'WCOM' => 'WWWCOMMERCIALINFO',
	'WCP' => 'WWWCOPYRIGHT',
	'WCOP' => 'WWWCOPYRIGHT',
	'WPB' => 'WWWPUBLISHER',
	'WPUB' => 'WWWPUBLISHER',
	'WORS' => 'WWWRADIOPAGE',
	'WPAY' => 'WWWPAYMENT',
	'WXX' => 'WWWUSER',
	'WXXX' => 'WWWUSER',
	'IPL' => 'INVOLVEDPEOPLE',
	'IPLS' => 'INVOLVEDPEOPLE',
	'TMCL' => 'MUSICIANCREDITLIST',
	'TIPL' => 'INVOLVEDPEOPLE2',
	#'ULT' => 'UNSYNCEDLYRICS',
	#'USLT' => 'UNSYNCEDLYRICS',
	#'COM' => 'COMMENT',
	#'COMM' => 'COMMENT',
	#'USER' => 'TERMSOFUSE',
	#'UFI' => 'UNIQUEFILEID',
	#'UFID' => 'UNIQUEFILEID',
	#'MCI' => 'CDID',
	#'MCDI' => 'CDID',
	#'ETC' => 'EVENTTIMING',
	#'ETCO' => 'EVENTTIMING',
	#'MLL' => 'MPEGLOOKUP',
	#'MLLT' => 'MPEGLOOKUP',
	#'STC' => 'SYNCEDTEMPO',
	#'SYTC' => 'SYNCEDTEMPO',
	#'SLT' => 'SYNCEDLYRICS',
	#'SYLT' => 'SYNCEDLYRICS',
	#'RVA' => 'VOLUMEADJ',
	#'RVAD' => 'VOLUMEADJ',
	#'RVA2' => 'VOLUMEADJ2',
	#'EQU' => 'EQUALIZATION',
	#'EQUA' => 'EQUALIZATION',
	#'EQU2' => 'EQUALIZATION2',
	#'REV' => 'REVERB',
	#'RVRB' => 'REVERB',
	#'PIC' => 'PICTURE',
	#'APIC' => 'PICTURE',
	#'GEO' => 'GENERALOBJECT',
	#'GEOB' => 'GENERALOBJECT',
	#'CNT' => 'PLAYCOUNTER',
	#'PCNT' => 'PLAYCOUNTER',
	#'POP' => 'POPULARIMETER',
	#'POPM' => 'POPULARIMETER',
	#'BUF' => 'BUFFERSIZE',
	#'RBUF' => 'BUFFERSIZE',
	#'CRM' => 'CRYPTEDMETA',
	#'CRA' => 'AUDIOCRYPTO',
	#'AENC' => 'AUDIOCRYPTO',
	#'LNK' => 'LINKEDINFO',
	#'LINK' => 'LINKEDINFO',
	#'POSS' => 'POSITIONSYNC',
	#'COMR' => 'COMMERCIAL',
	#'ENCR' => 'CRYPTOREG',
	#'GRID' => 'GROUPINGREG',
	#'PRIV' => 'PRIVATE',
	#'OWNE' => 'OWNERSHIP',
	#'SIGN' => 'SIGNATURE',
	#'SEEK' => 'SEEKFRAME',
	#'ASPI' => 'AUDIOSEEKPOINT'
);

sub getCustomScanFunctions {
	my %functions = (
		'id' => 'customtag',
		'defaultenabled' => 1,
		'name' => 'Custom Tag',
		'description' => "This module scans information from custom tags in your music files<br><br>The mapping between MP3 ID3 standard frame names to tag names can be found in the Modules/CustomTag.pm file, the names shall in most cases be the same as shown in your tagging software",
		'alwaysRescanTrack' => 1,
		'scanTrack' => \&scanTrack,
		'properties' => [
			{
				'id' => 'customtags',
				'name' => 'Tags to scan',
				'description' => 'Comma separated list with the tags that shall be scanned',
				'type' => 'text',
				'value' => 'OWNER,ORIGIN'
			},
			{
				'id' => 'singlecustomtags',
				'name' => 'Single value tags',
				'description' => 'Comma separated list with scanned tags that shall not be splitted to several values separated by ;. These tags must also be added to "Tags to scan" to be included in the scan',
				'type' => 'text',
				'value' => 'ORIGIN'
			},
			{
				'id' => 'customsorttags',
				'name' => 'Sort tag mapping',
				'description' => 'Comma separated list with the tags and their corresponding sort tag, for example: "ORIGARTIST=ORIGARTISTSORT,OWNER=OWNERSORT". If the scanned tag shall be used for sorting the tag does not have to be listed here.',
				'type' => 'text',
				'value' => ''
			}
		]
	);
	return \%functions;
		
}

sub scanTrack {
	my $track = shift;
	my @result = ();
	debugMsg("Scanning track: ".$track->title."\n");
	my $tags = Slim::Formats->readTags($track->url);
	if($track->content_type() eq 'mp3') {
		eval {
			getRawMP3Tags($track->url,$tags);
		};
		if ($@) {
			msg("CustomScan:CustomTag: Failed to load raw tags from ".$track->url.":$@\n");
		}
	}
	if(defined($tags)) {
		my $customTagProperty = Plugins::CustomScan::Plugin::getCustomScanProperty("customtags");
		my $customSortTagProperty = Plugins::CustomScan::Plugin::getCustomScanProperty("customsorttags");
		my $singleValueTagProperty = Plugins::CustomScan::Plugin::getCustomScanProperty("singlecustomtags");
		if($customTagProperty) {
			my @singleValueTags = ();
			if($singleValueTagProperty) {
				@singleValueTags = split(/\s*,\s*/,$singleValueTagProperty);
			}
			my %singleValueTagsHash = ();
			for my $singleValueTag (@singleValueTags) {
				$singleValueTagsHash{uc($singleValueTag)} = 1;
			}

			my @customTags = split(/\s*,\s*/,$customTagProperty);
			my %customTagsHash = ();
			for my $customTag (@customTags) {
				$customTagsHash{uc($customTag)} = 1;
			}

			my @customSortTags = split(/\s*,\s*/,$customSortTagProperty);
			my %customSortTagsHash = ();
			for my $customSortTag (@customSortTags) {
				if($customSortTag =~ /^\s*(.*)\s*=\s*(.*).*$/) {
					my $tag = $1;
					my $sortTag = $2;
					$customSortTagsHash{uc($tag)} = uc($sortTag);
				}
			}

			for my $tag (keys %$tags) {
				$tag = uc($tag);
				if($customTagsHash{$tag}) {
					my $values = $tags->{$tag};
					if(!defined($singleValueTagsHash{$tag})) {
						my @arrayValues = Slim::Music::Info::splitTag($tags->{$tag});
						$values = \@arrayValues;
					}
					my $sortValues = undef;
					my $sortTag = $customSortTagsHash{$tag};
					if(defined($sortTag)) {
						for my $key (keys %$tags) {
							if(uc($sortTag) eq uc($key)) {
								$sortValues = $tags->{$key};
								if(!defined($singleValueTagsHash{$tag})) {
									my @arrayValues = Slim::Music::Info::splitTag($tags->{$key});
									$sortValues = \@arrayValues;
								}
								last;
							}
						}
					}
					if(ref($values) eq 'ARRAY') {
						my $valueArray = $values;
						my $index = 0;
						for my $value (@$valueArray) {
							$value =~ s/^\s*//;
							$value =~ s/\s*$//;
							if($value ne '') {
								my %item = (
									'name' => $tag,
									'value' => $value
								);
								if(defined($sortValues)) {
									my $sortValue = undef;
									if(ref($sortValues) eq 'ARRAY') {
										if(scalar(@$sortValues)>$index) {
											$sortValue = $sortValues->[$index];
										}
									}elsif($index==0) {
										$sortValue = $sortValues;
									}
									if(defined($sortValue)) {
										$item{'valuesort'} = $sortValue;
									}
								}
								push @result,\%item;
							}
							$index = $index + 1;
						}
					}else {
						$values =~ s/^\s*//;
						$values =~ s/\s*$//;
						if($values ne '') {
							my %item = (
								'name' => $tag,
								'value' => $values
							);
							if(defined($sortValues)) {
								if(ref($sortValues) eq 'ARRAY') {
									$sortValues = $sortValues->[0];
								}
								$item{'valuesort'} = $sortValues;
							}
							push @result,\%item;
						}
					}
				}
			}
		}
	}
	return \@result;
}


sub getRawMP3Tags {
	my $url = shift;
	my $tags = shift;


	my $file = Slim::Utils::Misc::pathFromFileURL($url);
	my $rawTags = MP3::Info::get_mp3tag($file,2,1);
	for my $t (keys %$rawTags) {
		if(defined($rawTagNames{$t})) {
			my $tagName = $rawTagNames{$t};
			if(!defined($tags->{$tagName})) {
				my $value = $rawTags->{$t};
				my $encoding = '';
				if($value =~ /^(.)/) { 
					$encoding = $1;
					if($encoding eq "\001" || $encoding eq "\002" || $encoding eq "\003") {
						# strip first char (text encoding)
						$value =~ s/^.//;
					}
				}
				if ($encoding eq "\001" || $encoding eq "\002") { 
					$value =  eval { Slim::Utils::Unicode::decode('utf16', $value) } || Slim::Utils::Unicode::decode('utf16le', $value);
				} elsif ($encoding eq "\003") {
					$value =  Slim::Utils::Unicode::decode('utf8', $value);
				}
				# Remove null character at end
				$value =~ s/\0$//;
				$value =~ s/^\0//;
				$tags->{$tagName} = $value;
			}
		}
	}
}

sub debugMsg
{
	my $message = join '','CustomScan:CustomTag ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_customscan_showmessages"));
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
