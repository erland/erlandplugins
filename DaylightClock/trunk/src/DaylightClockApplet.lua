
--[[
=head1 NAME

applets.DaylightClock.DaylightClockApplet - Screensaver displaying a daylight map of earth together with a clock

=head1 DESCRIPTION

Daylight Clock is a screen saver for Jive. It is an applet that implements a screen saver
which displays a daylight map of the earth together with a clock.

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. DaylightClockApplet overrides the
following methods:

=cut
--]]


-- stuff we use
local pairs, ipairs, tostring, tonumber = pairs, ipairs, tostring, tonumber

local oo               = require("loop.simple")
local os               = require("os")

local datetime         = require("jive.utils.datetime")

local Applet           = require("jive.Applet")
local Window           = require("jive.ui.Window")
local Group            = require("jive.ui.Group")
local Label            = require("jive.ui.Label")
local Icon             = require("jive.ui.Icon")
local Font             = require("jive.ui.Font")
local Tile             = require("jive.ui.Tile")
local Surface          = require("jive.ui.Surface")
local Framework        = require("jive.ui.Framework")

local SocketHttp       = require("jive.net.SocketHttp")
local RequestHttp       = require("jive.net.RequestHttp")

local appletManager    = appletManager
local jiveMain         = jiveMain
local jnt              = jnt

local WH_FILL           = jive.ui.WH_FILL
local LAYOUT_NORTH      = jive.ui.LAYOUT_NORTH
local LAYOUT_SOUTH      = jive.ui.LAYOUT_SOUTH
local LAYOUT_CENTER     = jive.ui.LAYOUT_CENTER
local LAYOUT_WEST       = jive.ui.LAYOUT_WEST
local LAYOUT_EAST       = jive.ui.LAYOUT_EAST
local LAYOUT_NONE       = jive.ui.LAYOUT_NONE

module(..., Framework.constants)
oo.class(_M, Applet)


----------------------------------------------------------------------------------------
-- Helper Functions
--

-- display
-- the main applet function, the meta arranges for it to be called
-- by the ScreenSaversApplet.
function openScreensaver(self)

        -- Create the main window if it doesn't already exist
	if not self.window then
		self.window = Window("window")
		self.window:setSkin(self:_getClockSkin(jiveMain:getSelectedSkin()))
		self.window:reSkin()
		self.window:setShowFrameworkWidgets(false)

		local timeItems = {
			time = Label("time","")
		}
		self.timeLabel = Group("time",timeItems)

		local copyrightItems = {
			copyright = Label("copyright","http://www.die.net/earth")
		}
		self.copyrightLabel = Group("copyright",copyrightItems)

		local wallpaperItems = {
			wallpaper = Icon("background")
		}
		self.wallpaperImage = Group("background",wallpaperItems)

		self.window:addWidget(self.timeLabel)
		self.window:addWidget(self.copyrightLabel)
		self.window:addWidget(self.wallpaperImage)

		-- register window as a screensaver, unless we are explicitly not in that mode
		local manager = appletManager:getAppletInstance("ScreenSavers")
		manager:screensaverWindow(self.window)
		self.window:addTimer(1000, function() self:_tick() end)
	end
	self.lastminute = 0
	self:_tick(1)

	-- Show the window
	self.window:show(Window.transitionFadeIn)
end

local function _loadFont(fontSize)
        return Font:load("fonts/FreeSans.ttf", fontSize)
end

-- Update the time and if needed also the wallpaper
function _tick(self,forcedWallpaperUpdate)
	log:debug("Updating time")

	if datetime:getHours()==12 then
		self.timeLabel:setWidgetValue("time",os.date("%I:%M"))
	else
		self.timeLabel:setWidgetValue("time",os.date("%H:%M"))
	end

	local minute = os.date("%M")
	if forcedWallpaperUpdate or (minute % 1 == 0 and self.lastminute!=minute) then
		log:info("Initiating wallpaper update")
		local width,height = Framework.getScreenSize()
		local http = SocketHttp(jnt, "static.die.net", 80)
		local req = RequestHttp(function(chunk, err)
				if chunk then
				        local image = Surface:loadImageData(chunk, #chunk)
					local w,h = image:getSize()
					local zoom = width/w;
					image = image:rotozoom(0,zoom,1)
				        self.wallpaperImage:setWidgetValue("wallpaper",image)
				        log:debug("image ready")
				elseif err then
				        log:debug("error loading picture")
				end
			end,
			'GET', "/earth/mercator/480.jpg")
		http:fetch(req)
	end
	self.lastminute = minute
end

function _getClockSkin(self,skin)
	local s = {}
	local width,height = Framework.getScreenSize()
	local extraHeight
	local extraSize = 0
	local extraCopyrightPositioning = 0
	if width/height >= 1.7 then
		extraHeight = 0
	elseif width/height >= 1.3 then
		extraHeight = 40
		extraSize = 20
	else
		extraHeight = (height-width)+70
		extraSize = 40
		extraCopyrightPositioning = 20
	end

	s.window = {
		copyright = {
			position = LAYOUT_NONE,
			x = 5,
			y = height-40-20-extraHeight+extraCopyrightPositioning,
			copyright = {
				font = _loadFont(15),
				align = 'left',
				w = WH_FILL,
				h = 20,
				fg = { 0xaa, 0xaa, 0xaa },
			},
			zOrder = 3,
		},
		time = {
			position = LAYOUT_SOUTH,
			border = {0,10,0,0},
			time = {
				font = _loadFont(40+extraSize),
				align = 'center',
				w = WH_FILL,
				h = 40+extraHeight,
				fg = { 0xcc, 0xcc, 0xcc },
			},
			bgImg = Tile:fillColor(0x000000ff),
			zOrder = 2,
		},
		background = {
			position = LAYOUT_NORTH,
			zOrder = 1,
		},			
	}
	return s
end

--[[

=head1 LICENSE

Copyright (C) 2009 Erland Isaksson (erland_i@hotmail.com)

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

=cut
--]]


