# 				MenuPlaylistTemplate module 
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

use strict;
use warnings;
                   
package Plugins::TrackStat::Template::Reader;

use Slim::Player::Client;
use File::Spec::Functions qw(:ALL);

use Slim::Utils::Misc;

use File::Slurp;
use XML::Simple;

use FindBin qw($Bin);

sub getTemplates {
	my $client = shift;
	my $mainPlugin = shift;
	my $directory = shift;
	my $extension = shift;
	my @result = ();
	my @pluginDirs = ();
	if ($::VERSION ge '6.5') {
		@pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	}else {
		@pluginDirs = catdir($Bin, "Plugins");
	}
	for my $plugindir (@pluginDirs) {
		my $templateDir = catdir($plugindir,$mainPlugin,$directory);
		next unless -d $templateDir;
		my @dircontents = Slim::Utils::Misc::readDirectory($templateDir,$extension);
		for my $item (@dircontents) {
			next if -d catdir($templateDir,$item);
			my $templateId = $item;
			$templateId =~ s/\.$extension$//;
			my $template = readTemplateConfiguration($templateId,catdir($templateDir,$item));
			if(defined($template)) {
				my %templateItem = (
					'id' => $templateId,
					'type' => 'template',
					'template' => $template
				);
				push @result,\%templateItem;
			}
		}
	}
	return \@result;
}

sub readTemplateData {
	my $mainPlugin = shift;
	my $dir = shift;
	my $template = shift;
	#debugMsg("Loading template data for $template\n");

	my @pluginDirs = ();
	if ($::VERSION ge '6.5') {
		@pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	}else {
		@pluginDirs = catdir($Bin, "Plugins");
	}
	my $templateDir = undef;
	for my $plugindir (@pluginDirs) {
		next unless -d catdir($plugindir,$mainPlugin,$dir);
		$templateDir = catdir($plugindir,$mainPlugin,$dir);
	}
	my $path = catfile($templateDir, $template.".template");

	# read_file from File::Slurp
	my $content = eval { read_file($path) };
	return $content;
}

sub readTemplateConfiguration {
	my $templateId = shift;
	my $path = shift;
	#debugMsg("Loading template configuration for $templateId\n");

	# read_file from File::Slurp
	my $content = eval { read_file($path) };
	my $template = parseTemplateContent($templateId,$content);
	if(!$template) {
		msg("Unable to read template: $path\n");
	}
	return $template;
}

sub parseTemplateContent {
	my $id = shift;
	my $content = shift;

	my $template = undef;

        if ( $content ) {
	    $content = Slim::Utils::Unicode::utf8decode($content,'utf8');
            my $xml = eval { 	XMLin($content, forcearray => ["parameter"], keyattr => []) };
            #debugMsg(Dumper($xml));
            if ($@) {
                    msg("Failed to parse template configuration for $id because:\n$@\n");
            }else {
		my $include = isTemplateEnabled($xml);
		if(defined($xml->{'template'})) {
			$xml->{'template'}->{'id'} = $id;
		}
		if($include && defined($xml->{'template'})) {
	                $template = $xml->{'template'};
		}
            }
    
            # Release content
            undef $content;
        }else {
            if ($@) {
                    msg("Unable to read template configuration for $id:\n$@\n");
            }else {
                msg("Unable to to read template configuration for $id\n");
            }
        }
	return $template;
}

sub isTemplateEnabled {
	my $xml = shift;

	my $include = 1;
	if(defined($xml->{'minslimserverversion'})) {
		if($::VERSION lt $xml->{'minslimserverversion'}) {
			$include = 0;
		}
	}
	if(defined($xml->{'maxslimserverversion'})) {
		if($::VERSION gt $xml->{'maxslimserverversion'}) {
			$include = 0;
		}
	}
	if(defined($xml->{'database'}) && $include) {
		$include = 0;
		my $driver = Slim::Utils::Prefs::get('dbsource');
		$driver =~ s/dbi:(.*?):(.*)$/$1/;
		if($driver eq $xml->{'database'}) {
			$include = 1;
		}
	}
	return $include;
}

1;

__END__
