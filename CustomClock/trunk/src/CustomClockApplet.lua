
--[[
=head1 NAME

applets.CustomClock.CustomClockApplet - Clock screensaver with customizable graphics

=head1 DESCRIPTION

Custom Clock is a screen saver for Squeezeplay. It is customizable so you can choose among
a number of different graphics and information to show

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. CustomClockApplet overrides the
following methods:

=cut
--]]


-- stuff we use
local pairs, ipairs, tostring, tonumber = pairs, ipairs, tostring, tonumber

local oo               = require("loop.simple")
local os               = require("os")
local math             = require("math")
local string           = require("string")
local table            = require("jive.utils.table")

local datetime         = require("jive.utils.datetime")

local Applet           = require("jive.Applet")
local Window           = require("jive.ui.Window")
local Group            = require("jive.ui.Group")
local Label            = require("jive.ui.Label")
local Canvas           = require("jive.ui.Canvas")
local Icon             = require("jive.ui.Icon")
local Font             = require("jive.ui.Font")
local Tile             = require("jive.ui.Tile")
local Popup            = require("jive.ui.Popup")
local Surface          = require("jive.ui.Surface")
local Framework        = require("jive.ui.Framework")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local RadioGroup       = require("jive.ui.RadioGroup")
local RadioButton      = require("jive.ui.RadioButton")

local SocketHttp       = require("jive.net.SocketHttp")
local RequestHttp      = require("jive.net.RequestHttp")
local json             = require("json")

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

	log:debug("Open screensaver")
        -- Create the main window if it doesn't already exist
	if not self.window then
		log:debug("Recreating screensaver window")
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

		local item4Items = {
			item4 = Label("item4","")
		}
		self.item4Label = Group("item4",item4Items)

		local backgroundItems = {
			background = Icon("background")
		}
		self.backgroundImage = Group("background",backgroundItems)

		self.canvas = Canvas('debug_canvas',function(screen)
				self:_reDrawAnalog(screen)
			end)
	
		self.window:addWidget(self.item1Label)
		self.window:addWidget(self.item2Label)
		self.window:addWidget(self.item3Label)
		self.window:addWidget(self.item4Label)
		self.window:addWidget(self.backgroundImage)
		self.window:addWidget(self.canvas)

		-- register window as a screensaver, unless we are explicitly not in that mode
		local manager = appletManager:getAppletInstance("ScreenSavers")
		manager:screensaverWindow(self.window)
		self.window:addTimer(1000, function() self:_tick() end)
		self.offset = math.random(15)
		self.images = {}
	end
	self.lastminute = 0
	self.nowPlaying = 0
	self:_tick(1)

	-- Show the window
	self.window:show(Window.transitionFadeIn)
end

function openSettings(self)
	log:debug("Custom Clock settings")
	local width,height = Framework.getScreenSize()
	if width == 480 then
		self.model = "touch"
	elseif width == 320 then
		self.model = "radio"
	else
		self.model = "controller"
	end

	local window = Window("text_list", self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS"), 'settingstitle')

	window:addWidget(SimpleMenu("menu",
	{
		{
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_STYLE"), 
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingStyle(menuItem)
				return EVENT_CONSUME
			end
		},
		{
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_MODE"), 
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingMode(menuItem)
				return EVENT_CONSUME
			end
		},
		{
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_ITEM1"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingItem(menuItem,"item1")
				return EVENT_CONSUME
			end
		},
		{
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_ITEM2"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingItem(menuItem,"item2")
				return EVENT_CONSUME
			end
		},
		{
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_ITEM3"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingItem(menuItem,"item3")
				return EVENT_CONSUME
			end
		},
		{
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_NOWPLAYING"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingNowPlaying(menuItem)
				return EVENT_CONSUME
			end
		},
	}))

	self:tieAndShowWindow(window)
	return window
end

function defineSettingMode(self, menuItem)
	local group = RadioGroup()

	local mode = self:getSettings()["mode"]

	local window = Window("text_list", menuItem.text, 'settingstitle')

	window:addWidget(SimpleMenu("menu",
	{
		{
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_MODE_DIGITAL"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["mode"] = "digital"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				mode == "digital"
			),
		},
		{
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_MODE_ANALOG"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["mode"] = "analog"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				mode == "analog"
			),
		},
	}))

	self:tieAndShowWindow(window)
	return window
end

function defineSettingStyle(self, menuItem)
	local http = SocketHttp(jnt, "erlandplugins.googlecode.com", 80)
	local req = RequestHttp(function(chunk, err)
			if err then
				log:warn(err)
			elseif chunk then
				chunk = json.decode(chunk)
				self:defineSettingStyleSink(menuItem,chunk.data)
			end
		end,
		'GET', "/svn/CustomClock/trunk/clockstyles.json")
	http:fetch(req)
	
	-- create animiation to show while we get data from the server
        local popup = Popup("waiting_popup")
        local icon  = Icon("icon_connecting")
        local label = Label("text", self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_FETCHING"))
        popup:addWidget(icon)
        popup:addWidget(label)
        self:tieAndShowWindow(popup)

        self.popup = popup
end

function defineSettingStyleSink(self,menuItem,data)
	self.popup:hide()
	
	local style = self:getSettings()["style"]

	local window = Window("text_list", menuItem.text, 'settingstitle')
	local menu = SimpleMenu("menu")

	window:addWidget(menu)

	if data.item_loop then
		local group = RadioGroup()
		for _,entry in pairs(data.item_loop) do
			local isCompliant = true
			if entry.models then
				isCompliant = false
				for _,model in pairs(entry.models) do
					if model == self.model then
						isCompliant = true
					end
				end
			else
				log:debug("Supported on all models")
			end 
			if isCompliant then
				menu:addItem({
					text = entry.name,
					style = 'item_choice',
					check = RadioButton(
						"radio",
						group,
						function()
							self:getSettings()["style"] = entry.name
							if entry.background and entry.background != "" then
								self:getSettings()["background"] = entry.background
							else
								self:getSettings()["background"] = ""
							end
							if entry.clockimage and entry.clockimage != "" then
								self:getSettings()["clockimage"] = entry.clockimage
							else
								self:getSettings()["clockimage"] = ""
							end
							if entry.hourimage and entry.hourimage != "" then
								self:getSettings()["hourimage"] = entry.hourimage
							else
								self:getSettings()["hourimage"] = ""
							end
							if entry.minuteimage and entry.minuteimage != "" then
								self:getSettings()["minuteimage"] = entry.minuteimage
							else
								self:getSettings()["minuteimage"] = ""
							end
							if entry.secondimage and entry.secondimage != "" then
								self:getSettings()["secondimage"] = entry.secondimage
							else
								self:getSettings()["secondimage"] = ""
							end
							if entry.mode and entry.mode == "analog" then
								self:getSettings()["mode"] = "analog"
							else
								self:getSettings()["mode"] = "digital"
							end
							if entry.item1 and entry.item1 != "" then
								self:getSettings()["item1"] = entry.item1
							else
								self:getSettings()["item1"] = ""
							end
							if entry.item2 and entry.item2 != "" then
								self:getSettings()["item2"] = entry.item2
							else
								self:getSettings()["item2"] = ""
							end
							if entry.item3 and entry.item3 != "" then
								self:getSettings()["item3"] = entry.item3
							else
								self:getSettings()["item3"] = ""
							end
							if self.window then
								self.window:hide()
								self.window=nil
							end
							self:storeSettings()
						end,
						style == entry.name
					),
				})
			else
				log:debug("Skipping "..entry.name..", isn't supported on "..self.model)
			end
		end
	end

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
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_ITEM_EMPTY"),
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
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_ITEM_DAYMONTH"),
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
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_ITEM_DAYLONGMONTH"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[itemId] = "%d %B"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				item == "%d %B"
			),
		},           
		{
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_ITEM_WEEKDAY"),
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
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_ITEM_LONGWEEKDAY"),
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
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_ITEM_MONTH"),
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
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_ITEM_LONGMONTH"),
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
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_ITEM_MONTHDAY"),
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
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_ITEM_YEAR"),
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
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_ITEM_12HOURCLOCK"),
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
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_ITEM_24HOURCLOCK"),
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

function defineSettingNowPlaying(self, menuItem)
	local group = RadioGroup()

	local nowplaying = self:getSettings()["nowplaying"]

	local window = Window("text_list", menuItem.text, 'settingstitle')

	window:addWidget(SimpleMenu("menu",
	{
		{
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_NOWPLAYING_YES"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["nowplaying"] = true
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				nowplaying == true
			),
		},
		{
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_NOWPLAYING_NO"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()["nowplaying"] = false
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				nowplaying == false
			),
		},
	}))

	self:tieAndShowWindow(window)
	return window
end

function _loadFont(self,fontSize)
        return Font:load(self:getSettings()["font"], fontSize)
end

-- Get usable wallpaper area
function _getUsableWallpaperArea(self)
	local width,height = Framework.getScreenSize()
	return width,height
end

function _extractTrackInfo(self, _track, _itemType)
        if _track.track then
		if _itemType == 1 then
			return _track.artist
		elseif _itemType == 2 then
			return _track.album
		else 
			return _track.track
		end
        else
                return _track.text
        end
end

function _updateNowPlaying(self,itemType)
	local player = appletManager:callService("getCurrentPlayer")
	local playerStatus = player:getPlayerStatus()
	if playerStatus.mode == 'play' then
		if playerStatus.item_loop then
		        local trackInfo = self:_extractTrackInfo(playerStatus.item_loop[1],itemType)
			if trackInfo != "" then
				self.item4Label:setWidgetValue("item4",trackInfo)
				if self:getSettings()["mode"] == "analog" then
					if self.model == "touch" then
						--self.item2Label:setWidgetValue("item2","")
						--self.item3Label:setWidgetValue("item3","")
					elseif self.model == "controller" then
						self.item2Label:setWidgetValue("item2","")
					elseif self.model == "radio" then
						self.item2Label:setWidgetValue("item2","")
					end
				else
					if self.model == "radio" then
						self.item2Label:setWidgetValue("item2","")
					end
				end
			end
		else
			self.item4Label:setWidgetValue("item4","")
		end
	else
		self.item4Label:setWidgetValue("item4","")
	end
end

-- Update the time and if needed also the wallpaper
function _tick(self,forcedBackgroundUpdate)
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

	if self:getSettings()["mode"] == "analog" then
		self.item1Label:setWidgetValue("item1","")
	end

	local second = os.date("%S")
	if second % 3 == 0 then
		if self.nowPlaying>=3 then
			if (self.model == "touch" or self.model == "controller") and self:getSettings()["mode"] == "digital" then
				self.nowPlaying = 1
			else
				self.nowPlaying = 0
			end
		else
			self.nowPlaying = self.nowPlaying + 1
		end
	end
	if self.nowPlaying>0 and self:getSettings()["nowplaying"] == true then
		self:_updateNowPlaying(self.nowPlaying)
	else
		self.item4Label:setWidgetValue("item4","")	
	end

	local minute = os.date("%M")
	if forcedBackgroundUpdate or ((minute + self.offset) % 15 == 0 and self.lastminute!=minute) then
		self:_imageUpdate()
	end
	self.lastminute = minute

	if self:getSettings()["mode"] == "analog" or self.images["clock"] then
		self.canvas:reSkin()
		self.canvas:reDraw()
	end
end

function _reDrawAnalog(self,screen) 
	local m = os.date("%M")
	local h = os.date("%I")
	local s = os.date("%S")

	local width,height = self:_getUsableWallpaperArea()

	if self.images["clock"] then
		local tmp = self.images["clock"]:rotozoom(0, 1, 5)
		local facew, faceh = tmp:getSize()
		x = math.floor((width/2) - (facew/2))
		y = math.floor((height/2) - (faceh/2))
		log:debug("Updating clock face at "..x..", "..y)
		tmp:blit(screen, x, y)
		tmp:release()
	end

	if self:getSettings()["mode"] == "analog" and self.images["hour"] then
		local angle = (360 / 12) * (h + (m/60))

		local tmp = self.images["hour"]:rotozoom(-angle, 1, 5)
		local facew, faceh = tmp:getSize()
		x = math.floor((width/2) - (facew/2))
		y = math.floor((height/2) - (faceh/2))
		log:debug("Updating hour pointer at "..angle..", "..x..", "..y)
		tmp:blit(screen, x, y)
		tmp:release()
	end

	if self:getSettings()["mode"] == "analog" and self.images["minute"] then
		local angle = (360 / 60) * m

		local tmp = self.images["minute"]:rotozoom(-angle, 1, 5)
		local facew, faceh = tmp:getSize()
		x = math.floor((width/2) - (facew/2))
		y = math.floor((height/2) - (faceh/2))
		log:debug("Updating minute pointer at "..angle..", "..x..", "..y)
		tmp:blit(screen, x, y)
		tmp:release()
	end

	if self:getSettings()["mode"] == "analog" and self.images["second"] then
		local angle = (360 / 60) * s

		local tmp = self.images["second"]:rotozoom(-angle, 1, 5)
		local facew, faceh = tmp:getSize()
		x = math.floor((width/2) - (facew/2))
		y = math.floor((height/2) - (faceh/2))
		log:debug("Updating second pointer at "..angle..", "..x..", "..y)
		tmp:blit(screen, x, y)
		tmp:release()
	end
end

function _retrieveImage(self,url,imageType)
	local width,height = self:_getUsableWallpaperArea()
	local imagehost = ""
	local imageport = tonumber("80")
	local imagepath = ""

	local start,stop,value = string.find(url,"http://([^/]+)")
	if value and value != "" then
		imagehost = value
	end
	start,stop,value = string.find(url,"http://[^/]+(.+)")
	if value and value != "" then
		imagepath = value
	end

	if imagepath != "" and imagehost != "" then
		log:info("Getting image for "..imageType.." from "..imagehost.." and "..imagepath)
		local http = SocketHttp(jnt, imagehost, imageport)
		local req = RequestHttp(function(chunk, err)
				if chunk then
					local image = Surface:loadImageData(chunk, #chunk)
					if imageType == "background" then
						local w,h = image:getSize()

						local zoom
						if w>h or self.model == "controller" then
							log:debug("width based zoom ".. width .. "/" .. w .. "=" .. (width/w))
							zoom = width/w
						else
							log:debug("height based zoom ".. height .. "/" .. h .. "=" .. (height/h))
							zoom = height/h
						end
						image = image:rotozoom(0,zoom,1)
						self.backgroundImage:setWidgetValue("background",image)
					end
					log:debug("Storing downloaded image for "..imageType)
					self.images[imageType] = image
					log:debug("image ready")
				elseif err then
					log:warn("error loading picture " .. url)
				end
			end,
			'GET', imagepath)
		http:fetch(req)
	else
		log:warn("Unable to parse url "..url..", got: "..imagehost..", "..imagepath)
	end
end
function _imageUpdate(self)
	log:info("Initiating wallpaper update (offset="..self.offset.. " minutes)")

	local background = self:getSettings()["background"]
	if background != "" then
		self:_retrieveImage(background,"background")
	else
		self.images["backgroud"] = nil
	end

	if self:getSettings()["mode"] == "analog" then
		local hour = self:getSettings()["clockimage"]
		if hour != "" then
			self:_retrieveImage(hour,"clock")
		else
			self.images["clock"] = nil
		end

		local hour = self:getSettings()["hourimage"]
		if hour != "" then
			self:_retrieveImage(hour,"hour")
		else
			self.images["hour"] = nil
		end

		local minute = self:getSettings()["minuteimage"]
		if minute != "" then
			self:_retrieveImage(minute,"minute")
		else
			self.images["minute"] = nil
		end

		local second = self:getSettings()["secondimage"]
		if second != "" then
			self:_retrieveImage(second,"second")
		else
			self.images["second"] = nil
		end
	else
		self.images["clock"] = nil
		self.images["hour"] = nil
		self.images["minute"] = nil
		self.images["second"] = nil
	end
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
	local nowPlayingPosition
	local nowPlayingFont
	local nowPlayingHeight
	local margins = 5
	if self:getSettings()["mode"] == "digital" then
		if self.model == "touch" then
			secondaryItemHeight = 40
			secondaryItemFont = 30
			primaryItemHeight = 180
			primaryItemFont = 170
			primaryItemPosition = height-primaryItemHeight-secondaryItemHeight
			secondary2Position = height-secondaryItemHeight-5
			secondary3Position = height-secondaryItemHeight-5
			if (self:getSettings()["item2"] != "" and self:getSettings()["item3"] == "") or (self:getSettings()["item3"] != "" and self:getSettings()["item2"] == "") then
				secondary2Align = 'center'
				secondary3Align = 'center'
			end
			margins = 10
			nowPlayingHeight = 30
			nowPlayingPosition = height-primaryItemHeight-secondaryItemHeight-nowPlayingHeight
			nowPlayingFont = secondaryItemFont
		elseif self.model == "radio" then
			secondaryItemHeight = 50
			secondaryItemFont = 35
			primaryItemHeight = 110
			primaryItemFont = 110
			primaryItemPosition = height-primaryItemHeight-secondaryItemHeight-20
			secondary2Position = height-primaryItemHeight-secondaryItemHeight-secondaryItemHeight-20
			secondary2Align = 'center'
			secondary3Position = height-secondaryItemHeight-20
			secondary3Align = 'center'
			nowPlayingPosition = secondary2Position+20
			nowPlayingHeight = 25
			nowPlayingFont = 23
		else
			secondaryItemHeight = 50
			secondaryItemFont = 35
			primaryItemHeight = 80
			primaryItemFont = 80
			primaryItemPosition = height-primaryItemHeight-secondaryItemHeight
			secondary2Position = height-primaryItemHeight-secondaryItemHeight-secondaryItemHeight
			secondary2Align = 'center'
			secondary3Position = height-secondaryItemHeight
			secondary3Align = 'center'
			nowPlayingHeight = 30
			nowPlayingPosition = secondary2Position-nowPlayingHeight
			nowPlayingFont = 20
		end
	else
		if self.model == "touch" then
			secondaryItemHeight = 30
			secondaryItemFont = 25
			primaryItemHeight = 180
			primaryItemFont = 170
			primaryItemPosition = height-primaryItemHeight-secondaryItemHeight
			secondary2Position = height-secondaryItemHeight-5
			secondary3Position = height-secondaryItemHeight-5
			if (self:getSettings()["item2"] != "" and self:getSettings()["item3"] == "") or (self:getSettings()["item3"] != "" and self:getSettings()["item2"] == "") then
				secondary2Align = 'center'
				secondary3Align = 'center'
			end
			margins = 10
			nowPlayingHeight = 30
			nowPlayingPosition = 5
			nowPlayingFont = secondaryItemFont
		elseif self.model == "radio" then
			secondaryItemHeight = 35
			secondaryItemFont = 23
			primaryItemHeight = 110
			primaryItemFont = 110
			primaryItemPosition = height-primaryItemHeight-secondaryItemHeight-20
			secondary2Position = 0
			secondary2Align = 'center'
			secondary3Position = height-secondaryItemHeight
			secondary3Align = 'center'
			nowPlayingPosition = 0
			nowPlayingHeight = 35
			nowPlayingFont = 23
		else
			secondaryItemHeight = 50
			secondaryItemFont = 25
			primaryItemHeight = 80
			primaryItemFont = 80
			primaryItemPosition = height-primaryItemHeight-secondaryItemHeight
			secondary2Position = 5
			secondary2Align = 'center'
			secondary3Position = height-secondaryItemHeight
			secondary3Align = 'center'
			nowPlayingHeight = 30
			nowPlayingPosition = 10
			nowPlayingFont = 20
		end
	end

	local item1Style = nil
	if self:getSettings()["item1"] != "" then
		item1Style = {
				position = LAYOUT_NONE,
				y = primaryItemPosition,
				x = 0,
				border = {10,0,10,0},
				item1 = {
					font = self:_loadFont(primaryItemFont),
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
				position = LAYOUT_NONE,
				y = secondary2Position,
				x = 0,
				item2 = {
					border = {margins,0,margins,0},
					font = self:_loadFont(secondaryItemFont),
					align = secondary2Align,
					w = WH_FILL,
					h = secondaryItemHeight,
					fg = { 0xcc, 0xcc, 0xcc },
				},
				zOrder = 3,
		}
	end

	local item3Style = nil
	if self:getSettings()["item3"] != "" then
		item3Style = {
				position = LAYOUT_NONE,
				y = secondary3Position,
				x = 0,
				item3 = {
					border = {margins,0,margins,0},
					font = self:_loadFont(secondaryItemFont),
					align = secondary3Align,
					w = WH_FILL,
					h = secondaryItemHeight,
					fg = { 0xcc, 0xcc, 0xcc },
				},
				zOrder = 3,
		}
	end

	local item4Style = nil
	if self:getSettings()["nowplaying"] == true then
		item4Style = {
				position = LAYOUT_NONE,
				y = nowPlayingPosition,
				x = 0,
				item4 = {
					border = {margins,0,margins,0},
					font = self:_loadFont(nowPlayingFont),
					align = 'center',
					w = WH_FILL,
					h = nowPlayingHeight,
					fg = { 0xcc, 0xcc, 0xcc },
				},
				zOrder = 4,
		}
	end

	s.window = {
		item1 = item1Style,
		item2 = item2Style,
		item3 = item3Style,
		item4 = item4Style,
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


