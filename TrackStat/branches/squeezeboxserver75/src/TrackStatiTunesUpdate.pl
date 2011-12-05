# 				TrackStatiTunesUpdateWin.pl
#
#    Updated by Erland Isaksson to support play counts and changed name
#    Copyright (c) 2006 Erland Isaksson (erland_i@hotmail.com)
#
#    Most of the code is from iTunesUpdate 1.7.2
#    Copyright (c) 2004 James Craig (james.craig@london.com)
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
use POSIX qw(strftime);

my $os;
if ($^O =~/darwin/i) {
	$os = 'mac';
	require Mac::AppleScript::Glue;
    	import Mac::AppleScript::Glue;
	$Mac::AppleScript::Glue::Debug{SCRIPT} = 1;
	$Mac::AppleScript::Glue::Debug{RESULT} = 1;
#	require Slim::Utils::Unicode;
#	import Slim::Utils::Unicode;
} elsif ($^O =~ /^m?s?win/i) {
	$os = 'win';
	require Win32::OLE;
	import Win32::OLE;
	Win32::OLE->Option(Warn => \&OLEError);
	Win32::OLE->Option(CP => Win32::OLE::CP_UTF8());
} else {
	die ("Unsupported operating system $os!\n");
}

##################################################
### Set the variables here                     ###
##################################################

# 1 sets chatty debug messages to ON
# 0 sets chatty debug messages to OFF
my $ITUNES_DEBUG = 0;

# handle for iTunes app
my $iTunesHandle=();
my $iTunesFullVersion;
my $iTunesVersion;

my $filename = shift;
my $looptime = shift;
die "usage: TrackStatiTunesUpdate.pl <iTunes Update history file> [loop seconds]\n" unless ($filename);
die "$filename does not exist\n" unless (-f $filename or $looptime);

do {
	if (-f $filename) {
		rename $filename, "$filename.tmp";
		open INPUT, "< $filename.tmp" or die "Unable to open input file: $filename.tmp\n";
		open OUTPUT, ">> $filename.done" or warn "Unable to open history file: $filename.done - carrying on anyway!\n"; 

		while (<INPUT>) {
			chomp;
			my ($title,$artist,$album,$location,$played,$playedDate,$rating) = /^(.*?)\|(.*?)\|(.*?)\|(.*?)\|(.*?)\|(.*?)\|(.*)$/;
			my $playCount = "";
			my $added = "";
			if($rating =~ /^(.*?)\|(.*)$/) {
				$rating = $1;
				$playCount = $2;
			}
			if($playCount =~ /^(.*?)\|(.*)$/) {
				$playCount = $1;
				$added = $2;
			}
			if ($played eq 'played' or $rating ne '' or $added ne '') {
				_logTrackToiTunes($played,title => $title, 
						artist => $artist, 
						album => $album, 
						location => $location, 
						playedDate => $playedDate, 
						playCount => $playCount,
						rating => $rating,
						added => $added);
			} else  {
				print "no update required\n";
			}
			print OUTPUT;
			print OUTPUT "\n";
		}

		close INPUT;
		close OUTPUT;
		unlink "$filename.tmp";
	} else {
		print "No data to update\n";
	}
	if ($looptime) {
		print "Sleeping for $looptime s\n";
		sleep($looptime);
	}
} while ($looptime);
exit;


sub OLEError {
	print (Win32::OLE->LastError() . "\n");
}

# A wrapper to allow us to uniformly turn on & off debug messages
sub iTunesUpdateMsg
{
   # Parameter - Message to be displayed
   my $message = join '',@_;

   if ($ITUNES_DEBUG eq 1)
   {
      print STDOUT $message;      
   }
}

sub _logTrackToiTunes($%)
{
	my $action = shift;
	my %data = @_;
	my %monthHash = qw/01 January 02 February 03 March 04 April 05 May 06 June 07 July 08 August 09 September 10 October 11 November 12 December/;
	my ($year,$month,$day,$hr,$min,$sec) = $data{playedDate} =~ /(....)(..)(..)(..)(..)(..)/ ;

	iTunesUpdateMsg("==logTrackToiTunes()\n");

	my $trackHandle = _searchiTunes( title => $data{title}, 
							artist => $data{artist},
							location => $data{location}
							);
	if ($trackHandle) {
		if ($action eq 'played') {
			iTunesUpdateMsg("Marking as played in iTunes\n");

			if ($os eq 'win') {
				if($data{playCount} ne "") {
					if($data{playCount}>$trackHandle->{playedCount}) {
						$trackHandle->{playedCount} = $data{playCount};
					}
				}else {
					# If no play count was supplied we will just increase the current play count
					$trackHandle->{playedCount}++;
				}
		    
				my $playedDate = $trackHandle->{playedDate};
				#iTunesUpdateMsg "$data{playedDate} vs ".$playedDate->Date("yyyyMMdd").$playedDate->Time("HHmmss")."\n";
				# check that the new playedDate is later than that in iTunes
				if ($data{playedDate} gt $playedDate->Date("yyyyMMdd").$playedDate->Time("HHmmss")) {
					# convert to nice unambiguous format
					my ($year,$month,$day,$hr,$min,$sec) = $data{playedDate} =~ /(....)(..)(..)(..)(..)(..)/ ;
					#iTunesUpdateMsg "$year-$month-$day update: $hr:$min:$sec\n";
					$trackHandle->{playedDate} = "$year-$month-$day $hr:$min:$sec";
					#iTunesUpdateMsg("Modified playedDate\n");
				}
			} elsif ($os eq 'mac') {
				if($data{playCount} ne "") {
					if($data{playCount}>$trackHandle->played_count()) {
						$trackHandle->set(played_count => $data{playCount});
					}
				}else {
					# If no play count was supplied we will just increase the current play count
					$trackHandle->set(played_count => $trackHandle->played_count() + 1);
				}

				my $playedDate = $trackHandle->played_date->{_ref};
				#iTunesUpdateMsg "$data{playedDate} vs ".$playedDate->Date("yyyyMMdd").$playedDate->Time("HHmmss")."\n";
				# check that the new playedDate is later than that in iTunes
				if ($data{playedDate}) {
					# convert date to nice unambiguous format
					my $newPlayedDate = "$day $monthHash{$month} $year $hr:$min:$sec";
					$trackHandle->set(played_date => \"date \"$newPlayedDate\""); 
				}
			}
		}
		if ($data{rating} ne "") {
			iTunesUpdateMsg("Updating rating in iTunes\n");
			if ($os eq 'win') {
				$trackHandle->{rating} = $data{rating};
			} elsif ($os eq 'mac') {
				$trackHandle->set(rating => $data{rating} );
			}
		}
	} else {
		iTunesUpdateMsg("Track not found in iTunes\n");
	}

	return 0;
}

sub _searchiTunes {
	my %searchTerms=@_;

	# don't bother unless we have a location and at least one of title/artist/album
	return 0 unless $searchTerms{location} and ($searchTerms{title} or $searchTerms{artist} or $searchTerms{album});

	# create searchString and remove duplicate/trailing whitespace as well.
	my $searchString = "";
	if ($searchTerms{title}) {
		$searchString .= "$searchTerms{artist} ";
		}
	if ($searchTerms{album}) {
		$searchString .= "$searchTerms{album} ";
		}
	if ($searchTerms{title}) {
		$searchString .= "$searchTerms{title}";
	}
	iTunesUpdateMsg( "Searching iTunes for \"$searchString\"\n");

	_openiTunes() or return 0;

	if ($os eq 'win') {
		return _searchiTunesWin($searchString, $searchTerms{location});
	} elsif ($os eq 'mac') {
		return _searchiTunesMac($searchString, $searchTerms{location});
	}
	return 0;
}

sub _searchiTunesWin {
    my $searchString = shift;
    my $fileLocation = shift;
	my $IITrackKindFile = 1;
	my $ITPlaylistSearchFieldVisible = 1;
	
	# reverse the slashes in case Squeezebox Server was running on UNIX
	$fileLocation =~ s/\//\\/g;
	
	#replace \\ with \ - not consistent within iTunes (not in my library at least)
	$fileLocation =~ s/\\\\/\\/;

	my $mainLibrary = $iTunesHandle->LibraryPlaylist;	
	my $trackCollection = $mainLibrary->Search($searchString, $ITPlaylistSearchFieldVisible);
	if ($trackCollection)
	{
		iTunesUpdateMsg("Found ",$trackCollection->Count," track(s) in iTunes\n");
		for (my $j = 1; $j <= $trackCollection->Count ; $j++) {
			my $iTunesLoc = $trackCollection->Item($j)->Location;
			#change double \\ to \ 
			$iTunesLoc =~ s/\\\\/\\/;

			#check the location and type
			if ($trackCollection->Item($j)->Kind == $IITrackKindFile
				and lc($fileLocation) eq lc($iTunesLoc))
			{
				#we have the file (hopefully)
				iTunesUpdateMsg("Found track in iTunes\n");
				return $trackCollection->Item($j);
			} else {
				iTunesUpdateMsg("Checking for: $fileLocation\n");
				iTunesUpdateMsg("False match:  $iTunesLoc\n");
			}
		}
	}
	return 0;
}

sub _searchiTunesMac {
        my $searchString = shift;
        my $fileLocation = shift;

	# reverse the slashes in case Squeezebox Server was running on Windows
	$fileLocation =~ s/\\/\//g;

	#remove leading drive letter 
	$fileLocation =~ s/^\w\://i; 
	
	#OSX iTunes seems to store some accented characters as 2 characters
	#this function should recombine them
	#$fileLocation = Slim::Utils::Unicode::recomposeUnicode($fileLocation);

	my $trax = $iTunesHandle->search_library_playlist_1_for($searchString);
	for my $track (@{$trax}) {
		my $iTunesLoc = $track->location->{_ref};
		# modify iTunesLoc to match the location string
		$iTunesLoc =~ s/^alias "[^:]*:(.*)"$/$1/;
		$iTunesLoc =~ tr/:/\//;

		# have to do a substring match as the begining of the two
		# strings is different
		my $xpect = length($fileLocation) - length($iTunesLoc);
		my $found = index(lc($fileLocation), lc($iTunesLoc));
		if ($xpect >= 0 and $found == $xpect) {
			iTunesUpdateMsg("Found track in iTunes: $iTunesLoc\n");
			return $track;
		} else {
			iTunesUpdateMsg("Checking for: $fileLocation\n");
			iTunesUpdateMsg("False Match:  $iTunesLoc\n");
		}
	}
	return 0;
}



sub _openiTunes {
	my $failure;

	unless ($iTunesHandle) {
		iTunesUpdateMsg ("Attempting to make connection to iTunes...\n");
		if ($os eq 'win') {
			$iTunesHandle = Win32::OLE->GetActiveObject('iTunes.Application');
			unless ($iTunesHandle) {
				$iTunesHandle = new Win32::OLE( "iTunes.Application") 
			}
		} elsif ($os eq 'mac') {
			$iTunesHandle = new Mac::AppleScript::Glue::Application('iTunes');
		} else {
			iTunesUpdateMsg("iTunes not supported on plattform\n");
			return 0;
		}
		unless ($iTunesHandle) {
			iTunesUpdateMsg( "Failed to launch iTunes!!!\n");
			return 0;
		}
		$iTunesFullVersion = $iTunesHandle->Version;
		iTunesUpdateMsg ("Connection established to iTunes: $iTunesFullVersion\n");
		($iTunesVersion) = split /\./,$iTunesFullVersion;
	} else {
		#iTunesUpdateMsg ("iTunes already open: testing connection\n");
		$iTunesHandle->Version or $failure = 1;	
		if ($failure) {
			iTunesUpdateMsg ("iTunes dead: reopening...\n");
			undef $iTunesHandle;
			return _openiTunes();
		}
	}
	return 1;
}


