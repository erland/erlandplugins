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


sub getRawMP3Tags {
	my $url = shift;
	my $tags = shift;


	my $file = Slim::Utils::Misc::pathFromFileURL($url);
	open(my $fh, $file);
	my %rawTags = ();
	MP3::Info::_get_v2tag($fh, 2, 1, \%rawTags);
	for my $t (keys %rawTags) {
		if(defined($rawTagNames{$t})) {
			my $tagName = $rawTagNames{$t};
			if(!defined($tags->{$tagName})) {
				$tags->{$tagName} = $rawTags{$t};
			}
		}
	}
	close($fh);
}

sub debugMsg
{
	my $message = join '','CustomScan:CustomTag ',@_;
	msg ($message) if (Slim::Utils::Prefs::get("plugin_customscan_showmessages"));
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
