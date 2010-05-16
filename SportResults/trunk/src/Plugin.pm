# 				Sport Results plugin 
#
#    Copyright (c) 2010 Erland Isaksson (erland_i@hotmail.com)
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
                   
package Plugins::SportResults::Plugin;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);

use Plugins::SportResults::Settings;

use Data::Dumper;

my $prefs = preferences('plugin.sportresults');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.sportresults',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_SPORTRESULTS',
});

my $PLUGINVERSION = undef;

my $availableCountries = {};
my $availableSports = {};
my $availableLeagues = {};

sub getDisplayName()
{
	return string('PLUGIN_SPORTRESULTS'); 
}

sub initPlugin
{
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	Plugins::SuperDateTime::Plugin::registerProvider(\&getSportResults);
	Plugins::SportResults::Settings->new($class);
}

sub getSportResults {
	my $timer = shift;
	my $client = shift;
	my $refreshId = shift;
	
	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&getSportResultsResponse, \&gotErrorViaHTTP, {
		client => $client,
		refreshId => $refreshId,
        });

	$log->debug("Making call to: http://www.goalwire.com/en/livescore");
	$http->get("http://www.goalwire.com/en/livescore/", 'User-Agent' => 'Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.0)');
#	$http->get("http://www.goalwire.com/en/results/2010-05-13/", 'User-Agent' => 'Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.0)');
}

sub getSportResultsResponse {
	my $http = shift;
	my $params = $http->params();

	my $client = $params->{'client'};
	my $refreshId = $params->{'refreshId'};

	my $content = $http->content();
	my @result = ();
	my $logoURLs = {};
	if(defined($content)) {
		my $tree = HTML::TreeBuilder->new;
		$tree->parse($content);
		$tree->eof();
		
		for my $sport (values %$availableLeagues) {
			Plugins::SuperDateTime::Plugin::delCustomSport($sport);
		}

		my @league_tables = $tree->look_down("_tag", "table", "class", "ch");
		my @result = ();
		$availableCountries = {};
		$availableLeagues = {};
		for my $league_table (@league_tables) {
			my @league_tag = $league_table->look_down("_tag","th", "class","label");
			my @league_list = $league_tag[0]->content_list;
			my $league = $league_list[1];
			$log->debug("******** $league ********");
			my @game_rows = $league_table->look_down("_tag","tr", "id",qr{gw_match});
			for my $game_row (@game_rows) {
				my @time_tag = $game_row->look_down("_tag","td","class","gw_date");
				my @time_list = $time_tag[0]->content_list;
				my $time = $time_list[0];

				my $hometeam = "";
				my $homescore = "";
				my $awayteam = "";
				my $awayscore = "";
				my $status = "";
				my $sport = "";
				my $country = "";

				my @hometeam_tag = $game_row->look_down("_tag","td","class","gw_hometeam");

				if(scalar(@hometeam_tag)>0) {
					my @hometeamname_tag = $hometeam_tag[0]->look_down("_tag","a");
					my $url = $hometeamname_tag[0]->attr('href');
					if($url =~ /\/statistics_and_tables\/([^\/]+)\//) {
						$sport = $1;
					}
					if($url =~ /\/statistics_and_tables\/[^\/]+\/([^\/]+)/) {
						$country = $1;
					}
					my @hometeam_list = $hometeamname_tag[0]->content_list;
					if(scalar(@hometeam_list)>1) {
						$hometeam = Slim::Utils::Unicode::utf8decode_guess($hometeam_list[1]);
					}else {
						$hometeam = Slim::Utils::Unicode::utf8decode_guess($hometeam_list[0]);
					}
					if($hometeam ne "") {
						my @homescore_tag = $game_row->look_down("_tag","span","class","gw_score_home");
						if(scalar(@homescore_tag)>0) {
							my @homescore_list = $homescore_tag[0]->content_list;
							if(scalar(@homescore_list)>0) {
								$homescore = $homescore_list[0];
							}
						}
					}

					my @awayteam_tag = $game_row->look_down("_tag","td","class","gw_awayteam");
					if(scalar(@awayteam_tag)>0) {
						my @awayteamname_tag = $awayteam_tag[0]->look_down("_tag","a");
						my @awayteam_list = $awayteamname_tag[0]->content_list;
						if(scalar(@awayteam_list)>1) {
							$awayteam = Slim::Utils::Unicode::utf8decode_guess($awayteam_list[1]);
						}else {
							$awayteam = Slim::Utils::Unicode::utf8decode_guess($awayteam_list[0]);
						}
						if($awayteam ne "") {
							my @awayscore_tag = $game_row->look_down("_tag","span","class","gw_score_away");
							if(scalar(@awayscore_tag)>0) {
								my @awayscore_list = $awayscore_tag[0]->content_list;
								if(scalar(@awayscore_list)>0) {
									$awayscore = $awayscore_list[0];
								}
							}
						}

						my @status_tag = $game_row->look_down("_tag","span","class","gw_status_label");
						if(scalar(@status_tag)>0) {
							my @status_list = $status_tag[0]->content_list;
							$status = $status_list[0];
						}
					}
				}

				my $timeStatus = $time;
				if($status eq "Ended") {
					$timeStatus = "F";
				}elsif($status eq "Postponed") {
					$timeStatus = "P";
				}
				my $game = undef;
				my $countryString = $country;
				$countryString =~ s/_/ /g;
				my $sportString = $sport;
				$sportString =~ s/_/ /g;
				if($hometeam ne "" && $awayteam ne "") {
					$availableCountries->{escape($country)} = ucfirst($countryString);
					$availableSports->{escape($sport)} = ucfirst($sportString);
					$availableLeagues->{escape($sport.$country.$league)} = getSportName($sport, $country, $league);
				}
				if(isCountryEnabled($country) && isSportEnabled($sport) && isLeagueEnabled($sport,$country,$league)) {
					if(!defined($logoURLs->{getSportName($sport,$country,$league)})) {
						my $logo = getLeagueLogo($sport, $country, $league);
						if(defined($logo)) {
							$logoURLs->{getSportName($sport,$country,$league)} = $logo;
						}
					}
					if($homescore ne "" || ($hometeam ne "" && $awayteam ne "")) {
						$log->debug("$sport $country $league: $time $hometeam - $awayteam ($homescore-$awayscore) $status");
						$game = {
							sport => getSportName($sport, $country, $league),
							gameID => $hometeam.$awayteam.$time,
							gameTime => $timeStatus,
							homeTeam => $hometeam,
							homeLogoURL => getTeamLogo($sport, escape($country), escape($league),escape($hometeam)),
							homeScore => $homescore,
							awayTeam => $awayteam,
							awayLogoURL => getTeamLogo($sport, escape($country), escape($league),escape($awayteam)),
							awayScore => $awayscore,
						};
						push @result,$game;
					}
				}
			}
		}
		for my $game (@result) {
			if(defined($logoURLs->{$game->{'sport'}})) {
				Plugins::SuperDateTime::Plugin::addCustomSportLogo($game->{'sport'},$logoURLs->{$game->{'sport'}});
			}else {
				Plugins::SuperDateTime::Plugin::addCustomSportLogo($game->{'sport'},"plugins/SportResults/html/images/goalwire_button80.jpg");
			}
			Plugins::SuperDateTime::Plugin::addCustomSportScore($game);
		}
		Plugins::SuperDateTime::Plugin::refreshData(undef,$client,$refreshId);
	}else {
		$log->warn("Error, got no results");
	}
}


sub getLeagueLogo {
	my $sport = shift;
	my $country = shift;
	my $league = shift;

	if(!defined($prefs->get('leaguelogos'))) {
		return undef;
	}
	if(defined($prefs->get('leaguelogos')->{$sport."_".$country."_".$league})) {
		return $prefs->get('leaguelogos')->{$sport."_".$country."_".$league};
	}elsif(defined($prefs->get('leaguelogos')->{$sport."_".$league})) {
		return $prefs->get('leaguelogos')->{$sport."_".$league};
	}else {
		return undef;
	}
}

sub getTeamLogo {
	my $sport = shift;
	my $country = shift;
	my $league = shift;
	my $team = shift;

	if(!defined($prefs->get('teamlogos'))) {
		return undef;
	}
	if(defined($prefs->get('teamlogos')->{$sport."_".$country."_".$league."_".$team})) {
		return $prefs->get('teamlogos')->{$sport."_".$country."_".$league."_".$team};
	}elsif(defined($prefs->get('teamlogos')->{$sport."_".$league."_".$team})) {
		return $prefs->get('teamlogos')->{$sport."_".$league."_".$team};
	}else {
		return undef;
	}
}

sub getAvailableCountries {
	return $availableCountries;
}

sub getAvailableSports {
	return $availableSports;
}

sub getAvailableLeagues {
	return $availableLeagues;
}

sub isCountryEnabled {
	my $country = shift;
	if(defined($prefs->get("disabledcountries")) && $prefs->get("disabledcountries")->{escape($country)}) {
		return 0;
	}
	return 1;
}

sub isSportEnabled {
	my $sport = shift;
	if(defined($prefs->get("disabledsports")) && $prefs->get("disabledsports")->{escape($sport)}) {
		return 0;
	}
	return 1;
}

sub isLeagueEnabled {
	my $sport = shift;
	my $country = shift;
	my $league = shift;
	if(defined($prefs->get("disabledleagues")) && $prefs->get("disabledleagues")->{escape($sport.$country.$league)}) {
		return 0;
	}
	return 1;
}

sub getSportName {
	my $sport = shift;
	my $country = shift;
	my $league = shift;

	$sport = ucfirst($sport);
	$sport =~ s/_/ /g;

	$country = ucfirst($country);
	$country =~ s/_/ /g;

	$league = Slim::Utils::Unicode::utf8decode_guess($league);

	return "$sport ($country, $league)"
}

sub gotErrorViaHTTP {
	my $http = shift;
	my $params = $http->params();

	my $client = $params->{'client'};
	my $refreshId = $params->{'refreshId'};

	$log->warn("Error retrieving results");
	Plugins::SuperDateTime::Plugin::refreshData(undef,$client,$refreshId);
}

*escape   = \&URI::Escape::uri_escape_utf8;

1;

__END__
