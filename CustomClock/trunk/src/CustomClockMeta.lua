
--[[
=head1 NAME

applets.CustomClock.CustomClockMeta - Daylight Clock meta-info

=head1 DESCRIPTION

See L<applets.CustomClock.CustomClockApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]

local tostring = tostring

local oo            = require("loop.simple")
local datetime         = require("jive.utils.datetime")

local AppletMeta    = require("jive.AppletMeta")
local jul           = require("jive.utils.log")

local appletManager = appletManager
local jiveMain      = jiveMain


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(self)
	return 1, 1
end

function registerApplet(self)
	jiveMain:addItem(self:menuItem('appletCustomClock', 'home', "SCREENSAVER_CUSTOMCLOCK", function(applet, ...) applet:openMenu(...) end, 900))
	jiveMain:disableItemById('appletCustomClock')
	jiveMain:addItem(self:menuItem('appletExtrasCustomClock', 'extras', "SCREENSAVER_CUSTOMCLOCK", function(applet, ...) applet:openMenu(...) end, 900))
end

function configureApplet(self)
	for i=1,9 do
		appletManager:callService("addScreenSaver", 
			tostring(self:string("SCREENSAVER_CUSTOMCLOCK")).."#"..i..": "..self:getSettings()["config"..i.."style"], 
			"CustomClock",
			"openScreensaver"..i, 
			self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS"), 
			"openSettings", 
			90,
			"closeScreensaver")
	end
	if self:getSettings()["confignowplayingstyle"] then
		log:info("Registering custom Now Playing screen")
		self:registerService('goNowPlaying')
		appletManager:loadApplet("CustomClock")
	else
		log:info("Using standard Now Playing screen")
	end
	if appletManager:callService("isPatchInstalled","60a51265-1938-4fd7-b703-12d3725870da") then
		if self:getSettings()["configalarmactivestyle"] then
			self:registerService("openCustomClockAlarmWindow")
			appletManager:callService("registerAlternativeAlarmWindow","openCustomClockAlarmWindow")
		end
	end
end

function defaultSettings(self)
        local defaultSetting = {}
	defaultSetting["font"] = "fonts/FreeSans.ttf"
        return defaultSetting
end

--[[

=head1 LICENSE

Copyright (C) 2009 Erland Isaksson (erland_i@hotmail.com)

This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.
   
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.
    
You should have received a copy of the GNU Lesser General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

=cut
--]]

