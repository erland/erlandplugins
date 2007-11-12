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
use Win32::OLE;
Win32::OLE->Option(Warn => \&OLEError);

##################################################
### Set the variables here                     ###
##################################################

# 1 sets chatty debug messages to ON
# 0 sets chatty debug messages to OFF
my $ITUNES_DEBUG = 0;

# handle for iTunes app
my $iTunesHandle=();

my $filename = shift;
my $looptime = shift;
die "usage: iTunesUpdateWin.pl <iTunes Update history file> [loop seconds]\n" unless ($filename);
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
				_logTrackToiTunesWin($played,title => $title, 
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

sub _logTrackToiTunesWin($%)
{
	my $action = shift;
	my %data = @_;
	my $status;
	#my %monthHash = qw/01 Jan 02 Feb 03 Mar 04 Apr 05 May 06 Jun 07 Jul 08 Aug 09 Sep 10 Oct 11 Nov 12 Dec/;

	iTunesUpdateMsg("==logTrackToiTunesWin()\n");

	my $trackHandle = _searchiTunesWin( title => $data{title}, 
							artist => $data{artist},
							location => $data{location}
							);
	if ($trackHandle) {
		if ($action eq 'played') {
			iTunesUpdateMsg("Marking as played in iTunes\n");

			if($data{playCount} ne "") {
				if($data{playCount}>$trackHandle->{playedCount}) {
					$status = $trackHandle->{playedCount} = $data{playCount};
				}
			}else {
				# If no play count was supplied we will just increase the current play count
				$status = $trackHandle->{playedCount}++;
		    	#iTunesUpdateMsg("Incremented playedCount: was $status\n");
		    }
		    
		    my $playedDate = $trackHandle->{playedDate};
		    #iTunesUpdateMsg "$data{playedDate} vs ".$playedDate->Date("yyyyMMdd").$playedDate->Time("HHmmss")."\n";
		    # check that the new playedDate is later than that in iTunes
			if ($data{playedDate} gt $playedDate->Date("yyyyMMdd").$playedDate->Time("HHmmss")) {
				# convert to nice unambiguous format
				my ($year,$month,$day,$hr,$min,$sec) = $data{playedDate} =~ /(....)(..)(..)(..)(..)(..)/ ;
				#iTunesUpdateMsg "$year-$month-$day update: $hr:$min:$sec\n";
				$status = $trackHandle->{playedDate} = "$year-$month-$day $hr:$min:$sec";
				#iTunesUpdateMsg("Modified playedDate\n");
			}
		}
		if ($data{rating} ne "") {
			iTunesUpdateMsg("Updating rating in iTunes\n");
			$status = $trackHandle->{rating} = $data{rating};
		}
		#iTunes doesn't support to write to the dateAdded field so this will not work
		#if($data{added} ne "") {
		#	$status = $trackHandle->{dateAdded} = $data{added};
		#}
	} else {
		iTunesUpdateMsg("Track not found in iTunes\n");
	}

	return 0;
}



sub _searchiTunesWin {
	my %searchTerms=@_;
	my $IITrackKindFile = 1;
	my $ITPlaylistSearchFieldVisible = 1;
	my $status;
	
	# don't bother unless we have a location and at least one of title/artist/album
	return 0 unless $searchTerms{location} and ($searchTerms{title} or $searchTerms{artist} or $searchTerms{album});
	
	_openiTunesWin() or return 0;
	
	# reverse the slashes in case SlimServer is running on UNIX
	$searchTerms{location} =~ s/\//\\/g; 
	#replace \\ with \ - not consistent within iTunes (not in my library at least)
	$searchTerms{location} =~ s/\\\\/\\/;

	my $mainLibrary = $iTunesHandle->LibraryPlaylist;	
	my $tracks = $mainLibrary->Tracks;

	#now find it
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
	iTunesUpdateMsg( "Searching iTunes for *$searchString*\n");
	my $trackCollection = $mainLibrary->Search($searchString,
							$ITPlaylistSearchFieldVisible);

	if ($trackCollection)
	{
		iTunesUpdateMsg("Found ",$trackCollection->Count," track(s) in iTunes\n");
		iTunesUpdateMsg("Checking for: *$searchTerms{location}*\n");
		for (my $j = 1; $j <= $trackCollection->Count ; $j++) {
			#change double \\ to \ 
			my $iTunesLoc = lc $trackCollection->Item($j)->Location;
			$iTunesLoc =~ s/\\\\/\\/;
			# escape all problem characters for search coming up
			my $searchLocation = lc $searchTerms{location};
			$searchLocation =~ s/(\W)/\\$1/g;
			
			#check the location
			if ($trackCollection->Item($j)->Kind == $IITrackKindFile
				and  $iTunesLoc =~ m|$searchLocation$|i)
			{
				#we have the file (hopefully)
				iTunesUpdateMsg("Found track in iTunes\n");
				return $trackCollection->Item($j);
			} 
			else {
				iTunesUpdateMsg("$j - False match: *$iTunesLoc*\n");
			}
		}
	}
	return 0;
}




sub _openiTunesWin {
	my $failure;
	
	unless ($iTunesHandle) {
		iTunesUpdateMsg ("Attempting to make connection to iTunes...\n");
		$iTunesHandle = Win32::OLE->GetActiveObject('iTunes.Application');
		unless ($iTunesHandle) {
			$iTunesHandle = new Win32::OLE( "iTunes.Application") 
				or	$failure = 1;
 			if ($failure) {
				warn "Failed to launch iTunes through OLE!!!\n";
				return 0;
			}
		my $iTunesVersion = $iTunesHandle->Version;
		iTunesUpdateMsg ("OLE connection established to iTunes: $iTunesVersion\n");
		}
	} else {
		#iTunesUpdateMsg ("iTunes already open: testing connection\n");
		$iTunesHandle->Version or $failure = 1;	
		if ($failure) {
			iTunesUpdateMsg ("iTunes dead: reopening...\n");
			undef $iTunesHandle;
			return _openiTunesWin();
		}
	}
	return 1;
}


