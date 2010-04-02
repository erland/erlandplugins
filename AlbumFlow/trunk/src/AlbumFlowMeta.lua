
--[[
=head1 NAME

applets.AlbumFlow.AlbumFlowMeta - Album Slide meta-info

=head1 DESCRIPTION

See L<applets.AlbumFlow.AlbumFlowApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]

local pairs,tostring = pairs,tostring

local oo            = require("loop.simple")
local datetime         = require("jive.utils.datetime")

local AppletMeta    = require("jive.AppletMeta")
local jul           = require("jive.utils.log")
local System        = require("jive.System")

local appletManager = appletManager
local jiveMain      = jiveMain


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(self)
	return 1, 1
end

function registerApplet(self)
	if System.getMachine() != "fab4" then
		jiveMain:addItem(self:menuItem('appletAlbumFlow', '_myMusic', "SCREENSAVER_ALBUMFLOW",
		        function(applet, ...) applet:menu(...) end, 30, nil, 'hm_myMusicAlbums'))
	end
end

function configureApplet(self)
	for i=1,5 do
		appletManager:callService("addScreenSaver", 
			tostring(self:string("SCREENSAVER_ALBUMFLOW")).." #"..i, 
			"AlbumFlow",
			"openScreensaver"..i, 
			self:string("SCREENSAVER_ALBUMFLOW_SETTINGS"), 
			"openScreensaverSettings", 
			90,
			"closeScreensaver")
	end
	if self:getSettings()["screensaverstyle"] then
		self:getSettings()["screensaverstyle"] = nil
		for attr,value in pairs(self:defaultSettings()) do
			self:getSettings()[attr] = value
		end
		self:storeSettings()
	end
	if not self:getSettings()["browsealbumsstyle"] then
		self:getSettings()["browsealbumsstyle"] = "circular"
		self:getSettings()["browsealbumsmode"] = "byartist"
		self:storeSettings()
	end
end

function defaultSettings(self)
        local defaultSetting = {}
        defaultSetting["config1style"] = "circular"
        defaultSetting["config2style"] = "circular"
        defaultSetting["config3style"] = "circular"
        defaultSetting["config4style"] = "circular"
        defaultSetting["config5style"] = "circular"
        defaultSetting["config1mode"] = "random"
        defaultSetting["config2mode"] = "currentplaylist"
        defaultSetting["config3mode"] = "currentartist"
        defaultSetting["config4mode"] = "currentgenre"
        defaultSetting["config5mode"] = "currentyear"
        defaultSetting["browsealbumsstyle"] = "circular"
        defaultSetting["browsealbumsmode"] = "byartist"
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

