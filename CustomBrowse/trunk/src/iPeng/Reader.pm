# 				iPeng::Reader module 
#
#    Copyright (c) 2008 Erland Isaksson (erland_i@hotmail.com)
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
                   
package Plugins::CustomBrowse::iPeng::Reader;

use File::Spec::Functions qw(:ALL);

use Slim::Utils::Log;

use File::Slurp;
use XML::Simple;

my $log   = logger('plugin.custombrowse');

sub read {
	my $plugin = shift;
	my $dir = shift;

	if(UNIVERSAL::can("Plugins::iPeng::Plugin","addCommand") && UNIVERSAL::can("Plugins::iPeng::Plugin","addSubSection")) {
		my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
		for my $plugindir (@pluginDirs) {
			$log->debug("Checking for dir: ".catdir($plugindir,$plugin,$dir)."\n");
			next unless -d catdir($plugindir,$plugin,$dir);
			readFromDir(catdir($plugindir,$plugin,$dir));
		}
	}
}

sub readFromDir {
	my $dir = shift;

	$log->debug("Loading iPeng configuration from: $dir\n");

	my @dircontents = Slim::Utils::Misc::readDirectory($dir,"ipeng.xml");
	my $extensionRegexp = "\\.ipeng\\.xml\$";

	# Iterate through all files in the specified directory
	for my $item (@dircontents) {
		next unless $item =~ /$extensionRegexp/;
		next if -d catdir($dir, $item);

		my $path = catfile($dir, $item);

		# Read the contents of the current file
		my $content = eval { read_file($path) };
		if ( $content ) {
			# Make sure to convert the file data to utf8
			my $encoding = Slim::Utils::Unicode::encodingFromString($content);
			if($encoding ne 'utf8') {
				$content = Slim::Utils::Unicode::latin1toUTF8($content);
				$content = Slim::Utils::Unicode::utf8on($content);
				$log->debug("Loading $item and converting from latin1\n");
			}else {
				$content = Slim::Utils::Unicode::utf8decode($content,'utf8');
				$log->debug("Loading $item without conversion with encoding ".$encoding."\n");
			}
		}

		# Parse the file using XML::Simple
		if ( $content ) {
                	$log->debug("Parsing file: $path\n");
			my $xml = eval { XMLin($content, forcearray => ["command","section","subsection"], keyattr => ["id"]) };
			if ($@) {
				$log->warn("Failed to parse configuration ($item) because:\n$@\n");
			}elsif(exists $xml->{'section'}){
				my $sections = $xml->{'section'};
				foreach my $sectionKey (keys %$sections) {
					my $subsections = $sections->{$sectionKey}->{'subsection'};
					foreach my $subsectionKey (keys %$subsections) {
						my $subsection = $subsections->{$subsectionKey};
						eval { Plugins::iPeng::Plugin::addSubSection($sectionKey,$subsectionKey,$subsection) };
						if ($@) {
							$log->warn("Failed to register iPeng sub section:\n$@");
						}
						my $commands = $subsections->{$subsectionKey}->{'command'};
						foreach my $commandKey (keys %$commands) {
							my $command = $commands->{$commandKey};

							eval { Plugins::iPeng::Plugin::addCommand($sectionKey,$subsectionKey,$commandKey,$command) };
							if ($@) {
								$log->warn("Failed to register iPeng command:\n$@");
							}
						}
					}
				}

			}else {
				$log->warn("Failed to parse configuration: missing section element");
			}
		}else {
			if ($@) {
				$log->warn("Unable to open file: $path\nBecause of:\n$@\n");
			}else {
				$log->warn("Unable to open file: $path\n");
			}
		}
	}
}

1;

__END__
