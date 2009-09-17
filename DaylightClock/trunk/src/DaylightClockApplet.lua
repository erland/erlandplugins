
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
local math             = require("math")
local string           = require("string")

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
local SimpleMenu       = require("jive.ui.SimpleMenu")
local RadioGroup       = require("jive.ui.RadioGroup")
local RadioButton       = require("jive.ui.RadioButton")

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
		local width,height = Framework.getScreenSize()
		if width == 480 then
			self.model = "touch"
		elseif width == 320 then
			self.model = "radio"
		else
			self.model = "controller"
		end

		self.window = Window("window")
		self.window:setSkin(self:_getClockSkin(jiveMain:getSelectedSkin()))
		self.window:reSkin()
		self.window:setShowFrameworkWidgets(false)

		local item1Items = {
			item1 = Label("item1","")
		}
		self.item1Label = Group("item1",item1Items)

		local item2Items = {
			item2 = Label("item2","")
		}
		self.item2Label = Group("item2",item2Items)

		local item3Items = {
			item3 = Label("item3","")
		}
		self.item3Label = Group("item3",item3Items)

		local copyrightItems = {
			copyright = Label("copyright",self:getSettings()["copyright"])
		}
		self.copyrightLabel = Group("copyright",copyrightItems)

		local wallpaperItems = {
			background = Icon("background")
		}
		self.wallpaperImage = Group("background",wallpaperItems)

		self.window:addWidget(self.item1Label)
		self.window:addWidget(self.item2Label)
		self.window:addWidget(self.item3Label)
		self.window:addWidget(self.copyrightLabel)
		self.window:addWidget(self.wallpaperImage)

		-- register window as a screensaver, unless we are explicitly not in that mode
		local manager = appletManager:getAppletInstance("ScreenSavers")
		manager:screensaverWindow(self.window)
		self.window:addTimer(1000, function() self:_tick() end)
		self.offset = math.random(15)
	end
	self.lastminute = 0
	self:_tick(1)

	-- Show the window
	self.window:show(Window.transitionFadeIn)
end

function openSettings(self)
	log:debug("Daylight Clock settings")

	local window = Window("text_list", self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS"), 'settingstitle')

	window:addWidget(SimpleMenu("menu",
	{
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_PERSPECTIVE"), 
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingPerspective(menuItem)
				return EVENT_CONSUME
			end
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_ITEM1"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingItem(menuItem,"item1")
				return EVENT_CONSUME
			end
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_ITEM2"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingItem(menuItem,"item2")
				return EVENT_CONSUME
			end
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_ITEM3"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingItem(menuItem,"item3")
				return EVENT_CONSUME
			end
		},
	}))

	self:tieAndShowWindow(window)
	return window
end

function defineSettingPerspective(self, menuItem)
	local group = RadioGroup()

	local perspective = self:getSettings()["perspective"]

	local window = Window("text_list", menuItem.text, 'settingstitle')

	window:addWidget(SimpleMenu("menu",
	{
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_PERSPECTIVE_MERCATOR"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["perspective"] = "/earth/mercator"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				perspective == "/earth/mercator"
			),
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_PERSPECTIVE_MERCATOR_CLOUDLESS"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["perspective"] = "/earth/mercator-cloudless"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				perspective == "/earth/mercator-cloudless"
			),
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_PERSPECTIVE_PETERS"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["perspective"] = "/earth/peters"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				perspective == "/earth/peters"
			),
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_PERSPECTIVE_PETERS_CLOUDLESS"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["perspective"] = "/earth/peters-cloudless"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				perspective == "/earth/peters-cloudless"
			),
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_PERSPECTIVE_EQUIRECTANGULAR"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["perspective"] = "/earth/rectangular"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				perspective == "/earth/rectangular"
			),
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_PERSPECTIVE_EQUIRECTANGULAR_CLOUDLESS"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["perspective"] = "/earth/rectangular-cloudless"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				perspective == "/earth/rectangular-cloudless"
			),
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_PERSPECTIVE_MOLLWEIDE"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["perspective"] = "/earth/mollweide"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				perspective == "/earth/mollweide"
			),
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_PERSPECTIVE_MOLLWEIDE_CLOUDLESS"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["perspective"] = "/earth/mollweide-cloudless"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self.window = nil
				end,
				perspective == "/earth/mollweide-cloudless"
			),
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_PERSPECTIVE_HEMISPHERE"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["perspective"] = "/earth/hemisphere"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				perspective == "/earth/hemisphere"
			),
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_PERSPECTIVE_HEMISPHERE_CLOUDLESS"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["perspective"] = "/earth/hemisphere-cloudless"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				perspective == "/earth/hemisphere-cloudless"
			),
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_PERSPECTIVE_HEMISPHERE_DAWN"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["perspective"] = "/earth/hemispheredawn"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				perspective == "/earth/hemispheredawn"
			),
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_PERSPECTIVE_HEMISPHERE_DAWN_CLOUDLESS"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["perspective"] = "/earth/hemispheredawn-cloudless"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				perspective == "/earth/hemispheredawn-cloudless"
			),
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_PERSPECTIVE_HEMISPHERE_DUSK"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["perspective"] = "/earth/hemispheredusk"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				perspective == "/earth/hemispheredusk"
			),
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_PERSPECTIVE_HEMISPHERE_DUSK_CLOUDLESS"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["perspective"] = "/earth/hemispheredusk-cloudless"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				perspective == "/earth/hemispheredusk-cloudless"
			),
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_PERSPECTIVE_MOON"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["perspective"] = "/moon"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				perspective == "/moon"
			),
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_PERSPECTIVE_HEMISPHERE_DAWNDUSKMOON"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["perspective"] = "/earth/hemispheredawnduskmoon"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				perspective == "/earth/hemispheredawnduskmoon"
			),
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_PERSPECTIVE_HEMISPHERE_DAWNDUSKMOON_CLOUDLESS"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["perspective"] = "/earth/hemispheredawnduskmoon-cloudless"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				perspective == "/earth/hemispheredawnduskmoon-cloudless"
			),
		},
	}))

	self:tieAndShowWindow(window)
	return window
end


function defineSettingItem(self, menuItem, itemId)
	local group = RadioGroup()

	local item = self:getSettings()[itemId]

	local window = Window("text_list", menuItem.text, 'settingstitle')

	window:addWidget(SimpleMenu("menu",
	{
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_ITEM_EMPTY"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[itemId] = ""
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				item == ""
			),
		},
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_ITEM_DAYMONTH"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[itemId] = "%d %b"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				item == "%d %b"
			),
		},           
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_ITEM_WEEKDAY"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[itemId] = "%a"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				item == "%a"
			),
		},           
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_ITEM_LONGWEEKDAY"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[itemId] = "%A"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				item == "%A"
			),
		},           
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_ITEM_MONTH"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[itemId] = "%b"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				item == "%b"
			),
		},           
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_ITEM_LONGMONTH"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[itemId] = "%B"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				item == "%B"
			),
		},           
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_ITEM_MONTHDAY"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[itemId] = "%d"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				item == "%d"
			),
		},           
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_ITEM_YEAR"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[itemId] = "%Y"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				item == "%Y"
			),
		},           
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_ITEM_12HOURCLOCK"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[itemId] = "%I:%M"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				item == "%I:%M"
			),
		},           
		{
			text = self:string("SCREENSAVER_DAYLIGHTCLOCK_SETTINGS_ITEM_24HOURCLOCK"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[itemId] = "%H:%M"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				item == "%H:%M"
			),
		},           
	}))

	self:tieAndShowWindow(window)
	return window
end

local function _loadFont(fontSize)
        return Font:load("fonts/FreeSans.ttf", fontSize)
end

-- Get usable wallpaper area
function _getUsableWallpaperArea(self)
	local width,height = Framework.getScreenSize()

	if self.model == "touch" then
		height = height-45
	elseif self.model == "radio" then
		if string.find(self:getSettings()["perspective"],"dusk") or string.find(self:getSettings()["perspective"],"dawn") or string.find(self:getSettings()["perspective"],"moon") then
			height = height - 45
		else
			height = height - 85
		end
	elseif self.model == "controller" then
		if string.find(self:getSettings()["perspective"],"dusk") or string.find(self:getSettings()["perspective"],"dawn") or string.find(self:getSettings()["perspective"],"moon") then
			height = height - 45
		else
			height = height - 155
		end
	end
	return width,height
end

-- Update the time and if needed also the wallpaper
function _tick(self,forcedWallpaperUpdate)
	log:debug("Updating time")

	if self:getSettings()["item1"] != "" then
		self.item1Label:setWidgetValue("item1",os.date(self:getSettings()["item1"]))
	end
	if self:getSettings()["item2"] != "" then
		self.item2Label:setWidgetValue("item2",os.date(self:getSettings()["item2"]))
	end
	if self:getSettings()["item3"] != "" then
		self.item3Label:setWidgetValue("item3",os.date(self:getSettings()["item3"]))
	end

	local minute = os.date("%M")
	if forcedWallpaperUpdate or ((minute + self.offset) % 15 == 0 and self.lastminute!=minute) then
		log:info("Initiating wallpaper update")

		local width,height = self:_getUsableWallpaperArea()

		local perspective = self:getSettings()["perspective"]
		local perspectiveurl = perspective
		if string.find(perspective,"dawnduskmoon") then
			local hour = tonumber(os.date("%H"))
			if hour >= 21 or hour <= 3 then
				perspectiveurl = "/moon"
				perspective = perspectiveurl
			elseif hour >= 3 and hour <= 12 then
				perspectiveurl = string.gsub(perspectiveurl,"dawnduskmoon","")
				perspective = string.gsub(perspective,"dawnduskmoon","dawn")
			else
				perspectiveurl = string.gsub(perspectiveurl,"dawnduskmoon","")
				perspective = string.gsub(perspective,"dawnduskmoon","dusk")
			end
		else
			perspectiveurl = string.gsub(perspectiveurl,"dawn","")
			perspectiveurl = string.gsub(perspectiveurl,"dusk","")
		end

		local http = SocketHttp(jnt, "static.die.net", 80)
		local req = RequestHttp(function(chunk, err)
				if chunk then
				        local image = Surface:loadImageData(chunk, #chunk)
					local w,h = image:getSize()
					if string.find(perspective,"dawn") then
						local newImg = Surface:newRGBA(w/2, h)
				                newImg:filledRectangle(0, 0, w/2, h, 0x000000FF)
						image:blit(newImg,0,0)
						image = newImg
						w,h = image:getSize()
					elseif string.find(perspective,"dusk") then 
						local newImg = Surface:newRGBA(w/2, h)
				                newImg:filledRectangle(0, 0, w/2, h, 0x000000FF)
						image:blit(newImg,-w/2,0)
						image = newImg
						w,h = image:getSize()
					end

					if self.model == "controller" and string.find(perspectiveurl,"moon") then
						width = width -15
					end

					local zoom
					if w>h or self.model == "controller" then
						log:debug("width based zoom ".. width .. "/" .. w .. "=" .. (width/w))
						zoom = width/w
					else
						log:debug("height based zoom ".. height .. "/" .. h .. "=" .. (height/h))
						zoom = height/h
					end
					image = image:rotozoom(0,zoom,1)
				        self.wallpaperImage:setWidgetValue("background",image)
				        log:debug("image ready")
				elseif err then
				        log:error("error loading picture " .. perspectiveurl)
				end
			end,
			'GET', perspectiveurl .. "/480.jpg")
		http:fetch(req)
	end
	self.lastminute = minute
end

function _getClockSkin(self,skin)
	local s = {}
	local width,height = Framework.getScreenSize()
	local primaryItemHeight
	local primaryItemFont
	local secondaryItemHeight
	local secondaryItemFont
	local secondary2Position
	local secondary3Position
	local secondary2Align = 'left'
	local secondary3Align = 'right'
	local copyrightPosition
	local copyrightFont = 15
	local copyrightHeight = 20
	if self.model == "touch" then
		primaryItemHeight = 40
		primaryItemFont = 40
		secondaryItemHeight = 40
		secondaryItemFont = 40
		secondary2Position = 0
		secondary3Position = 0
		copyrightPosition = height-primaryItemHeight-copyrightHeight-5
	elseif self.model == "radio" then
		if string.find(self:getSettings()["perspective"],"dusk") or string.find(self:getSettings()["perspective"],"dawn") or string.find(self:getSettings()["perspective"],"moon") then
			primaryItemHeight = 40
			primaryItemFont = 40
			secondary2Position = 10
			secondary3Position = 10
			copyrightPosition = height-primaryItemHeight-copyrightHeight-5
		else
			primaryItemHeight = 80
			primaryItemFont = 60
			secondary2Position = 60
			secondary3Position = 60
			copyrightPosition = height-primaryItemHeight-copyrightHeight-10
		end
		secondaryItemHeight = 25
		secondaryItemFont = 25
	else
		if string.find(self:getSettings()["perspective"],"dusk") or string.find(self:getSettings()["perspective"],"dawn") or string.find(self:getSettings()["perspective"],"moon") then
			primaryItemHeight = 70
			primaryItemFont = 70
			secondary2Position = 60
			secondary3Position = 60
			secondaryItemHeight = 25
			secondaryItemFont = 25
		else
			primaryItemHeight = 150
			primaryItemFont = 80
			secondary2Position = 10
			secondary2Align = 'center'
			secondary3Position = 110
			secondary3Align = 'center'
			secondaryItemHeight = 35
			secondaryItemFont = 35
		end
		copyrightPosition = height-primaryItemHeight-copyrightHeight-5
	end


	local item1Style = nil
	if self:getSettings()["item1"] != "" then
		item1Style = {
				bgImg = Tile:fillColor(0x000000ff),
				position = LAYOUT_SOUTH,
				border = {0,10,0,5},
				item1 = {
					font = _loadFont(primaryItemFont),
					align = 'center',
					w = WH_FILL,
					h = primaryItemHeight,
					fg = { 0xcc, 0xcc, 0xcc },
				},
				zOrder = 2,
		}
	end
		
	local item2Style = nil
	if self:getSettings()["item2"] != "" then
		item2Style = {
				position = LAYOUT_SOUTH,
				border = {10,10+secondary2Position,0,5},
				item2 = {
					font = _loadFont(secondaryItemFont),
					align = secondary2Align,
					w = WH_FILL,
					h = secondaryItemHeight,
					fg = { 0xcc, 0xcc, 0xcc },
				},
				zOrder = 2,
		}
	end

	local item3Style = nil
	if self:getSettings()["item3"] != "" then
		item3Style = {
				position = LAYOUT_SOUTH,
				border = {0,10+secondary3Position,10,5},
				item3 = {
					font = _loadFont(secondaryItemFont),
					align = secondary3Align,
					w = WH_FILL,
					h = secondaryItemHeight,
					fg = { 0xcc, 0xcc, 0xcc },
				},
				zOrder = 2,
		}
	end

	s.window = {
		bgImg = Tile:fillColor(0x000000ff),
		copyright = {
			position = LAYOUT_NONE,
			x = 5,
			y = copyrightPosition,
			copyright = {
				font = _loadFont(copyrightFont),
				align = 'left',
				w = WH_FILL,
				h = copyrightHeight,
				fg = { 0xaa, 0xaa, 0xaa },
			},
			zOrder = 3,
		},
		item1 = item1Style,
		item2 = item2Style,
		item3 = item3Style,
		background = {
			bgImg = Tile:fillColor(0x000000ff),
			position = LAYOUT_NORTH,
			background = {
				w = WH_FILL,
				align = 'center',
			},
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


