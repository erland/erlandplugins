
--[[
=head1 NAME

applets.ScreenSwitcher.ScreenSwitcherApplet - A screensaver that switches between other screensavers

=head1 DESCRIPTION

Screen Switcher is a screen saver for Squeezeplay. It is customizable so you can make it switch
between a number of screen savers continously.

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. ScreenSwitcherApplet overrides the
following methods:

=cut
--]]


-- stuff we use
local pairs, ipairs, tostring, tonumber, setmetatable, type, pcall = pairs, ipairs, tostring, tonumber, setmetatable, type, pcall

local oo               = require("loop.simple")
local os               = require("os")
local math             = require("math")
local string           = require("jive.utils.string")
local table            = require("jive.utils.table")

local datetime         = require("jive.utils.datetime")

local Applet           = require("jive.Applet")
local System           = require("jive.System")
local Window           = require("jive.ui.Window")
local Group            = require("jive.ui.Group")
local Framework        = require("jive.ui.Framework")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local RadioGroup       = require("jive.ui.RadioGroup")
local RadioButton      = require("jive.ui.RadioButton")
local Timer            = require("jive.ui.Timer")
local Checkbox         = require("jive.ui.Checkbox")
local Timeinput         = require("jive.ui.Timeinput")
local DateTime               = require("jive.utils.datetime")

local appletManager    = appletManager
local jiveMain         = jiveMain
local jnt              = jnt
local jive             = jive

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
function openRandomScreensaver(self,random)
	openScreensaver(self,true)
end

function openScreensaver(self,random)
	self.random = false
	self.player = appletManager:callService("getCurrentPlayer")
	if random then
		self.random = true
	end
	if not self.currentPosition then
		self.currentPosition = {
			off = nil,
			stopped = nil,
			playing = nil,
		}
	end
	if self.timer then
		self.timer:stop()
	end

	self:_updateScreensaver(true)
end

function closeScreensaver(self)
	if self.timer then
		self.timer:stop()
	end
	self.currentScreensaver = nil
end

function _updateScreensaver(self, forced)
	local ss
	log:debug("Updating random="..tostring(self.random))
	if not self:isSoftPowerOn() and System:getMachine() ~= "jive" then
		if self.random then
		        ss = self:_getRandomScreensaver("off")
		else
		        ss = self:_getNextScreensaver("off")
		end
	else
	        if self.player and self.player:getPlayMode() == "play" then
			if self.random then
			        ss = self:_getRandomScreensaver("playing")
			else
			        ss = self:_getNextScreensaver("playing")
			end
	        else
			if self.random then
			        ss = self:_getRandomScreensaver("stopped")
			else
			        ss = self:_getNextScreensaver("stopped")
			end
	        end
	end

	local ssKey = "BlankScreen:openScreensaver"
	if ss and ss.screensaver then
		ssKey = ss.screensaver
	end

	if self.currentScreensaver ~= ssKey or forced then
		local screensaversApplet = appletManager:loadApplet("ScreenSavers") 
		local ssData = screensaversApplet["screensavers"][ssKey]
		local ssApplet = appletManager:loadApplet(ssData.applet)

		local windowsToHide = {}
		local prevSSData = nil
		if self.currentScreensaver then
			local oldSSData = screensaversApplet["screensavers"][self.currentScreensaver]
			if oldSSData.applet then
				prevSSData = oldSSData
				local activeWindows = screensaversApplet["active"]
				if activeWindows and #activeWindows > 0 then
					for i, window in ipairs(activeWindows) do
						--window:hide(Window.transitionFadeIn)
						windowsToHide[i] = window;
					end
				end
			end
		end

		-- We do this with pcall just for safety to make sure our switching isn't stopped if there is an error 
		-- (switching from analog clock will cause error messages due to canvas usage)
		local status,err = pcall(ssApplet[ssData.method], ssApplet, force, ssData.methodParam)
		self.currentScreensaver = ssKey
	        log:debug("activating " .. ssData.applet .. " "..tostring(ssData.displayName).." screensaver")
		local timer = Timer(400,function()
			if prevSSData then
				local oldSSApplet = appletManager:loadApplet(prevSSData.applet)
				if prevSSData.closeMethod then
					log:debug("Closing screensaver "..self.currentScreensaver)
					oldSSApplet[prevSSData.closeMethod](oldSSApplet, prevSSData.methodParam)
				end
			end
			for i,window in ipairs(windowsToHide) do
				-- We do this with pcall just for safety to make sure our switching isn't stopped if there is an error
				log:debug("Hiding windows...")
				local status,err = pcall(Window.hide,window,Window.transitionNone)
			end
		end,true)
		timer:start()
	end
	if ss then
		log:debug("Start new timer, trigger after "..ss.delay.." seconds")
		self.timer = Timer(5*1000, function() 
			local screensaversApplet = appletManager:loadApplet("ScreenSavers") 
			local activeWindows = screensaversApplet["active"]
			if #activeWindows>0 then
				log:debug("Got "..#activeWindows.." active screensaver windows")
				self:_updateScreensaver() 
			else
				self:closeScreensaver()
			end
		end, true)

		self.timer:start()
	else
		log:warn("Can't start new timer, switching disabled")
	end
end

function isSoftPowerOn(self)
        return jiveMain:getSoftPowerState() == "on"
end

function _uses(parent, value)
        if parent == nil then
                log:warn("nil parent in _uses")
        end
        local style = {}
        setmetatable(style, { __index = parent })
        for k,v in pairs(value or {}) do
                if type(v) == "table" and type(parent[k]) == "table" then
                        -- recursively inherrit from parent style
                        style[k] = _uses(parent[k], v)
                else
                        style[k] = v
                end
        end

        return style
end

function _getDateTimeSelectionString(self,state)
	local name = ""
	local starttime = self:getSettings()[state.."starttime"] or 0
	starttime = tonumber(starttime)
	local endtime = self:getSettings()[state.."endtime"] or 0
	endtime = tonumber(endtime)

	if self:getSettings()[state.."enabled"] then
		if starttime != 0 or endtime != 0 then
			if starttime != 0 then
				local time = DateTime:timeTableFromSFM(starttime, '24')
				if time.minute<10 then
					name = name..time.hour..":0"..time.minute.."-"
				else
					name = name..time.hour..":"..time.minute.."-"
				end
			end
			if endtime != 0 then
				local time = DateTime:timeTableFromSFM(endtime, '24')
				if starttime == 0 then
					name = name.."0:00-"
				end
				if time.minute<10 then
					name = name..time.hour..":0"..time.minute
				else
					name = name..time.hour..":"..time.minute
				end
			else
				name = name .. "0:00"
			end
		end

		local weekdays = self:getSettings()[state.."weekdays"]
		if weekdays then
			local alldays = true
			for i = 0,6 do
				if not weekdays[i] then
					alldays = false
				end
			end
			if not alldays then
				if name ~= "" then
					name = name .." "
				end
				local first = true
				for i = 0,6 do
					if weekdays[i] then
						if not first then
							name = name.. ","
						end
						name = name .. tostring(self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_WEEKDAYS_SHORT_"..i))
						first = false
					end
				end
			end
		end
		if name == "" then
			name = tostring(self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_ALWAYS"))
		end
	else
		name = tostring(self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_DISABLED"))
	end
	return name
end

function openSettings(self)
	log:debug("Screen Switcher settings")

	jive.ui.style.item_no_icon = _uses(jive.ui.style.item, {
		order = { 'text', 'check' },
	})
	jive.ui.style.icon_list.menu.item_no_icon = _uses(jive.ui.style.icon_list.menu.item, {
		order = { 'text', 'check' },
	})
	jive.ui.style.icon_list.menu.selected.item_no_icon = _uses(jive.ui.style.icon_list.menu.selected.item, {
		order = { 'text', 'check' },
	})
	jive.ui.style.icon_list.menu.pressed.item_no_icon = _uses(jive.ui.style.icon_list.menu.pressed.item, {
	})
	local window = Window("icon_list", self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS"), 'settingstitle')

	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	for i = 1,3 do
		local name = " "
		local timelimited = true
		local no = i
		if i == 3 then
			name = tostring(self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_DEFAULT"))
			timelimited = false
			no = ""
		else
			name = name .. self:_getDateTimeSelectionString("playing"..i)
		end
		menu:addItem(
			{
				text = tostring(self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_PLAYING")).." #"..i.."\n"..name, 
				style = 'item_no_icon',
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					self:defineSettingScreens(menuItem,"playing"..no,timelimited)
					return EVENT_CONSUME
				end
			}
		)
	end
	for i = 1,3 do
		local name = ""
		local timelimited = true
		local no = i
		if i == 3 then
			name = tostring(self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_DEFAULT"))
			timelimited = false
			no = ""
		else
			name = name .. self:_getDateTimeSelectionString("stopped"..i)
		end
		menu:addItem(
			{
				text = tostring(self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_STOPPED")).." #"..i.."\n"..name, 
				style = 'item_no_icon',
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					self:defineSettingScreens(menuItem,"stopped"..no,timelimited)
					return EVENT_CONSUME
				end
			}
		)
	end
	if System:getMachine() ~= "jive" then
		for i = 1,3 do
			local name = ""
			local timelimited = true
			local no = i
			if i == 3 then
				name = tostring(self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_DEFAULT"))
				timelimited = false
				no = ""
			else
				name = name .. self:_getDateTimeSelectionString("off"..i)
			end
			menu:addItem(
				{
					text = tostring(self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_OFF")).." #"..i.."\n"..name, 
					style = 'item_no_icon',
					sound = "WINDOWSHOW",
					callback = function(event, menuItem)
						self:defineSettingScreens(menuItem,"off"..no,timelimited)
						return EVENT_CONSUME
					end
				}
			)
		end
	end

	self:tieAndShowWindow(window)
	return window
end

function defineSettingScreens(self, menuItem, state,timelimited)
	local screens = self:getSettings()[state.."screens"]
	if not screens then
		self:getSettings()[state.."screens"] = {}
		screens = {}
	end

	local window = Window("text_list", menuItem.text, 'settingstitle')

	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	local screensaversApplet = appletManager:loadApplet("ScreenSavers")
	local screensavers = screensaversApplet["screensavers"]

	if timelimited then
		menu:addItem({
			text = self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_ENABLE"), 
			style = 'item_choice',
			check = Checkbox(
				"checkbox",
				function(object, isSelected)
					self:getSettings()[state.."enabled"] = isSelected
					self:storeSettings()
				end,
				self:getSettings()[state.."enabled"]
			)
                })
		menu:addItem({
			text = tostring(self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_WEEKDAYS")),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingWeekdays(menuItem,state)
				return EVENT_CONSUME
			end
		})
		menu:addItem({
			text = tostring(self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_STARTTIME")),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingTime(menuItem,state.."starttime",0)
				return EVENT_CONSUME
			end
		})
		menu:addItem({
			text = tostring(self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_ENDTIME")),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingTime(menuItem,state.."endtime",0)
				return EVENT_CONSUME
			end
		})
	end

	local index = 0
	for _,screen in pairs(screens) do
		local displayName = tostring(self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_NONE"))
		if screensavers[screen.screensaver] then
			displayName = tostring(screensavers[screen.screensaver].displayName)
		end
		local idx = index
		menu:addItem({
			text = tostring(self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_SCREEN")).." "..(index+1)..": "..displayName.." ("..screen.delay..")",
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingScreen(menuItem,state,idx+1)
				return EVENT_CONSUME
			end
		})
		index = index + 1
	end
	if index < 10 then
		while index<10 do
			local idx = index
			menu:addItem({
				text = tostring(self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_SCREEN")).." "..(index+1)..": "..tostring(self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_NONE")),
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					self:defineSettingScreen(menuItem,state,idx+1)
					return EVENT_CONSUME
				end
			})
			index = index+1
		end
	end

	self:tieAndShowWindow(window)
	return window
end

local function _getTimeFormat()
        local SetupDateTimeSettings = appletManager:callService("setupDateTimeSettings")
        local format = '12'
        if SetupDateTimeSettings and SetupDateTimeSettings['hours'] then
                format = SetupDateTimeSettings['hours']
        end
        return format
end

function defineSettingTime(self, menuItem, timeattribute,default,seconds)
	local time = self:getSettings()[timeattribute] or default
	local window = nil
	local timeStruct = nil
--	if _getTimeFormat() == "12" then
		window = Window("input_time_12h", menuItem.text, 'settingstitle')
		timeStruct = DateTime:timeTableFromSFM(tonumber(time), '12')
--	else
--		window = Window("input_time_24h", menuItem.text, 'settingstitle')
--		timeStruct = DateTime:timeTableFromSFM(tonumber(time), '24')
--	end
        local input = Timeinput(window, 
                                function(hour, minute, ampm)
					if ampm then
						local time = tonumber(hour)*3600+tonumber(minute)*60
						if ampm == "AM" and tonumber(hour) == 12 then
		                                        time = tonumber(minute)*60
						elseif ampm == "PM" and tonumber(hour)<12 then
		                                        time = time + 43200
						end
						self:getSettings()[timeattribute] = time
					else
	                                        self:getSettings()[timeattribute] = tonumber(hour)*3600+tonumber(minute*60)
					end
					self:storeSettings()
                                end,
				timeStruct)

	self:tieAndShowWindow(window)
	return window
end

function defineSettingWeekdays(self, menuItem, state)
	local weekdays = self:getSettings()[state.."weekdays"]
	if not weekdays then
		weekdays = {}
		for i = 0,6 do
			weekdays[i] = true
		end
	end
	local window = Window("text_list", menuItem.text, 'settingstitle')

	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	local availableWeekdays = {}
	for i = 0,6 do
		availableWeekdays[i] = self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_WEEKDAYS_"..i)
	end

	for dayno,daytext in pairs(availableWeekdays) do
		menu:addItem({
			text = daytext,
			style = 'item_choice',
			check = Checkbox(
				"checkbox",
				function(object, isSelected) 
					weekdays[tonumber(dayno)] = isSelected
					self:getSettings()[state.."weekdays"] = weekdays
					self:storeSettings()
				end,
				weekdays[tonumber(dayno)]
			)
		})
	end

	self:tieAndShowWindow(window)
	return window
end

function defineSettingScreen(self, menuItem, state, index)
	local screen = self:getSettings()[state.."screens"][index]

	local window = Window("text_list", menuItem.text, 'settingstitle')

	window:addWidget(SimpleMenu("menu",
	{
		{
			text = self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_SCREENSAVER"), 
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingScreensaver(menuItem,state,index)
				return EVENT_CONSUME
			end
		},
		{
			text = self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_DELAY"), 
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingDelay(menuItem,state,index)
				return EVENT_CONSUME
			end
		},
	}))

	self:tieAndShowWindow(window)
	return window
end

function getKey(self, appletName, method, additionalKey)
        local key = tostring(appletName) .. ":" .. tostring(method)
        if additionalKey then
                key = key .. ":" .. tostring(additionalKey)
        end
        return key
end

function defineSettingScreensaver(self,menuItem,state,index)
	local screen = self:getSettings()[state.."screens"][index]

	local window = Window("text_list", menuItem.text, 'settingstitle')
	local menu = SimpleMenu("menu")
	menu:setComparator(menu.itemComparatorWeightAlpha)
	local group = RadioGroup()

	window:addWidget(menu)

	local screensaversApplet = appletManager:loadApplet("ScreenSavers")
	local screensavers = screensaversApplet["screensavers"]

	for key,screensaver in pairs(screensavers) do
		if screensaver.applet ~= "ScreenSwitcher" then
			if screensaver.applet then
				menu:addItem({
					text = screensaver.displayName,
					style = 'item_choice',
					weight = 2,
					check = RadioButton(
						"radio",
						group,
						function()
							local delay = 30
							if screen then
								delay = screen.delay
							end
							self:getSettings()[state.."screens"][index] = {
								screensaver = key,
								delay = delay
							}
							self:storeSettings()
						end,
						screen and screen.screensaver == key
					),
				})
			else
				menu:addItem({
					text = screensaver.displayName,
					style = 'item_choice',
					weight = 1,
					check = RadioButton(
						"radio",
						group,
						function()
							table.remove(self:getSettings()[state.."screens"],index)
							self:storeSettings()
						end,
						screen == nil
					),
				})
			end
		end
	end

	self:tieAndShowWindow(window)
	return window
end

function defineSettingDelay(self,menuItem,state,index)
	local screen = self:getSettings()[state.."screens"][index]

	local window = Window("text_list", menuItem.text, 'settingstitle')
	local menu = SimpleMenu("menu")
	local group = RadioGroup()

	window:addWidget(menu)

	local delays = {5,10,15,20,30,60}
	for _,delay in pairs(delays) do
		menu:addItem({
			text = delay.." "..tostring(self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_SECONDS")),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					local screensaver = nil
					if screen then
						screensaver = screen.screensaver
					end
					self:getSettings()[state.."screens"][index] = {
						screensaver = screensaver,
						delay = delay
					}
					self:storeSettings()
				end,
				screen and screen.delay == delay
			),
		})
	end

	self:tieAndShowWindow(window)
	return window
end

function _getConfiguration(self, state)
	local weekday = os.date("%w")
	local now = os.time()
	local midnight = os.date("*t")
	midnight.hour = 0
	midnight.min = 0
	midnight.sec = 0
	local secFromMidnight = now - os.time(midnight)

	for i = 1,2 do
		if self:getSettings()[state..i.."enabled"] then
			local weekdays = self:getSettings()[state..i.."weekdays"]
			if not weekdays or weekdays[tonumber(weekday)] then
				local starttime = self:getSettings()[state..i.."starttime"] or 0
				local endtime = self:getSettings()[state..i.."endtime"] or 0
				if endtime == 0 then
					endtime = (24*3600)
				end
				endtime = endtime -1
				if starttime<=endtime and (secFromMidnight>=starttime) and (secFromMidnight<=endtime) then
					return state..i
				elseif starttime>endtime and (secFromMidnight>=starttime or secFromMidnight<=endtime) then
					return state..i
				end
			end
		end
	end
	return state
end
function _getNextScreensaver(self,state)
	local config = self:_getConfiguration(state)
	local screenSaverList = self:getSettings()[config.."screens"] or {}
	local currentPos = self.currentPosition[config]

	if not currentPos then
		currentPos = 1
	else
		currentPos = currentPos +1
	end

	if not screenSaverList[currentPos] or not screenSaverList[currentPos].screensaver then
		currentPos = 1
	end

	self.currentPosition[config] = currentPos

	if screenSaverList and screenSaverList[currentPos] and screenSaverList[currentPos].screensaver then
		log:debug("Getting "..config.." screensaver from position "..currentPos)
		log:debug("Returning screen saver "..screenSaverList[currentPos].screensaver)
		return screenSaverList[currentPos]
	end
	log:debug("No "..config.." screensaver defined for position "..currentPos..", returning blank screensaver")
	return nil
end

function _getRandomScreensaver(self,state)
	local screensaversApplet = appletManager:loadApplet("ScreenSavers") 
	local screenSaverList = screensaversApplet["screensavers"]

	local localScreenSaverList = {}
	local i = 1
	for key,saver in pairs(screenSaverList) do
		local additionalKey = nil
		if string.find(key,"^.*:.*:")  then
			additionalKey = string.gsub(key,"^.*:.*:","")
		end
		if not string.find(state,"^off") and saver and saver.applet and self:getKey(saver.applet,saver.method,additionalKey) ~= "BlankScreen:openScreensaver" and saver.applet ~= "ScreenSwitcher" then
			localScreenSaverList[i] = saver
			localScreenSaverList[i].additionalKey = additionalKey
			i = i+1
		elseif string.find(state,"^off") and saver and saver.applet and self:getKey(saver.applet,saver.method,additionalKey) ~= "BlankScreen:openScreensaver" and saver.applet ~= "ScreenSwitcher" and saver.applet ~= "NowPlaying" then
			localScreenSaverList[i] = saver
			localScreenSaverList[i].additionalKey = additionalKey
			i = i+1
		else 
			log:debug("Skipping "..state.." saver "..self:getKey(saver.applet,saver.method,additionalKey))
		end
	end
	log:debug("Choosing among "..#localScreenSaverList.." screensavers")
	local currentPos = math.random(#localScreenSaverList)

	if localScreenSaverList and localScreenSaverList[currentPos] then
		log:debug("Getting random "..state.." screensaver from position "..currentPos)
		log:debug("Returning screen saver "..self:getKey(localScreenSaverList[currentPos].applet,localScreenSaverList[currentPos].method,localScreenSaverList[currentPos].additionalKey))
		local result = {
			screensaver = self:getKey(localScreenSaverList[currentPos].applet,localScreenSaverList[currentPos].method,localScreenSaverList[currentPos].additionalKey),
			delay = 60,
		}
		return result
	end
	log:debug("No "..state.." screensaver defined for position "..currentPos..", returning blank screensaver")
	return nil
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


