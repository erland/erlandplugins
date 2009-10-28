
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
local pairs, ipairs, tostring, tonumber, pcall = pairs, ipairs, tostring, tonumber, pcall

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
		if self.currentScreensaver then
			local oldSSData = screensaversApplet["screensavers"][self.currentScreensaver]
			if oldSSData.applet then
				local oldSSApplet = appletManager:loadApplet(oldSSData.applet)
				if oldSSData.closeMethod then
					log:debug("Closing screensaver "..self.currentScreensaver)
					oldSSApplet[oldSSData.closeMethod](oldSSApplet, oldSSData.methodParam)
				end
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
		for i,window in ipairs(windowsToHide) do
			-- We do this with pcall just for safety to make sure our switching isn't stopped if there is an error
			log:debug("Hiding windows...")
			local status,err = pcall(Window.hide,window,Window.transitionNone)
		end
	end
	if ss then
		log:debug("Start new timer, trigger after "..ss.delay.." seconds")
		self.timer = Timer(ss.delay*1000, function() 
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

function openSettings(self)
	log:debug("Screen Switcher settings")

	local window = Window("text_list", self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS"), 'settingstitle')

	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	menu:addItem(
		{
			text = self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_PLAYING"), 
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingScreens(menuItem,"playing")
				return EVENT_CONSUME
			end
		}
	)

	menu:addItem(
		{
			text = self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_STOPPED"), 
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingScreens(menuItem,"stopped")
				return EVENT_CONSUME
			end
		}
	)
	if System:getMachine() ~= "jive" then
		menu:addItem(
			{
				text = self:string("SCREENSAVER_SCREENSWITCHER_SETTINGS_OFF"), 
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					self:defineSettingScreens(menuItem,"off")
					return EVENT_CONSUME
				end
			}
		)
	end

	self:tieAndShowWindow(window)
	return window
end

function defineSettingScreens(self, menuItem, state)
	local screens = self:getSettings()[state.."screens"]

	local window = Window("text_list", menuItem.text, 'settingstitle')

	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	local screensaversApplet = appletManager:loadApplet("ScreenSavers")
	local screensavers = screensaversApplet["screensavers"]

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
	local group = RadioGroup()

	window:addWidget(menu)

	local screensaversApplet = appletManager:loadApplet("ScreenSavers")
	local screensavers = screensaversApplet["screensavers"]

	for _,screensaver in pairs(screensavers) do
		if screensaver.applet ~= "ScreenSwitcher" then
			if screensaver.applet then
				menu:addItem({
					text = screensaver.displayName,
					style = 'item_choice',
					check = RadioButton(
						"radio",
						group,
						function()
							local delay = 30
							if screen then
								delay = screen.delay
							end
							self:getSettings()[state.."screens"][index] = {
								screensaver = self:getKey(screensaver.applet,screensaver.method,screensaver.additionalKey),
								delay = delay
							}
							self:storeSettings()
						end,
						screen and screen.screensaver == self:getKey(screensaver.applet,screensaver.method,screensaver.additionalKey)
					),
				})
			else
				menu:addItem({
					text = screensaver.displayName,
					style = 'item_choice',
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

function _getNextScreensaver(self,state)
	local screenSaverList = self:getSettings()[state.."screens"]
	local currentPos = self.currentPosition[state]

	if not currentPos then
		currentPos = 1
	else
		currentPos = currentPos +1
	end

	if not screenSaverList[currentPos] or not screenSaverList[currentPos].screensaver then
		currentPos = 1
	end

	self.currentPosition[state] = currentPos

	if screenSaverList and screenSaverList[currentPos] and screenSaverList[currentPos].screensaver then
		log:debug("Getting "..state.." screensaver from position "..currentPos)
		log:debug("Returning screen saver "..screenSaverList[currentPos].screensaver)
		return screenSaverList[currentPos]
	end
	log:debug("No "..state.." screensaver defined for position "..currentPos..", returning blank screensaver")
	return nil
end

function _getRandomScreensaver(self,state)
	local screensaversApplet = appletManager:loadApplet("ScreenSavers") 
	local screenSaverList = screensaversApplet["screensavers"]

	local localScreenSaverList = {}
	local i = 1
	for _,saver in pairs(screenSaverList) do
		if state ~= "off" and saver.applet and self:getKey(saver.applet,saver.method,saver.additionalKey) ~= "BlankScreen:openScreensaver" and saver.applet ~= "ScreenSwitcher" then
			localScreenSaverList[i] = saver
			i = i+1
		elseif state == "off" and saver.applet and self:getKey(saver.applet,saver.method,saver.additionalKey) ~= "BlankScreen:openScreensaver" and saver.applet ~= "ScreenSwitcher" and saver.applet ~= "NowPlaying" then
			localScreenSaverList[i] = saver
			i = i+1
		else 
			log:debug("Skipping "..state.." saver "..self:getKey(saver.applet,saver.method,saver.additionalKey))
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


