
--[[
=head1 NAME

applets.AlbumFlow.AlbumFlowMeta - Album Slide meta-info

=head1 DESCRIPTION

See L<applets.AlbumFlow.AlbumFlowApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]


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
        jiveMain:addItem(self:menuItem('appletAlbumFlow', '_myMusic', "SCREENSAVER_ALBUMFLOW",
                function(applet, ...) applet:menu(...) end, 30, nil, 'hm_myMusicAlbums'))
end

function configureApplet(self)
end

function defaultSettings(self)
        local defaultSetting = {}
        defaultSetting["mode"] = "digital"
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

