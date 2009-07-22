
--[[
=head1 NAME

applets.InformationScreen.InformationScreenApplet - Screensaver displaying information configured in Information Screen plugin

=head1 DESCRIPTION

Information Screen is a screen saver for Jive. It is an applet that implements a screen saver
which displays the information configured in the Information Screen plugin.

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. InformationScreenApplet overrides the
following methods:

=cut
--]]


-- stuff we use
local pairs, ipairs, tostring = pairs, ipairs, tostring

local oo               = require("loop.simple")

local Applet           = require("jive.Applet")
local Window           = require("jive.ui.Window")
local Label            = require("jive.ui.Label")
local Icon             = require("jive.ui.Icon")
local Group            = require("jive.ui.Group")

local log              = require("jive.utils.log").logger("applets.screensavers")

local appletManager    = appletManager

local _currentInformation

module(...)
oo.class(_M, Applet)


----------------------------------------------------------------------------------------
-- Helper Functions
--

-- display
-- the main applet function, the meta arranges for it to be called
-- by the ScreenSaversApplet.
function openScreensaver(self, style, transition)

	-- if we're opening this after freeing the applet, grab the player again
	if not self.player then
		self.player = appletManager:callService("getCurrentPlayer")
	end

	local playerStatus = self.player and self.player:getPlayerStatus()

	log:info("style=", style)
	log:info("transition=", transition)
	log:info("player=", self.player, " status=", playerStatus)

	if not self.window then
		self.window = _createUI(self)
		self.window:show(Window.transitionFadeIn)
	end

	self:_getInformation()
	self.window:addTimer(5000, function() self:_getInformation() end)

	return window
end

function _getInformation(self)
	local server = self.player:getSlimServer()

	log:info("requesting information")
	server:userRequest(
		function(chunk, err)
			if err then
				log:debug(err)
			elseif chunk then
				self:_getInformationResponse(chunk.data)
			end
		end,
		self.player and self.player:getId(),
		{ 'informationscreen', 'items'}
	)
end

function _getInformationResponse(self, result)
	local id

	-- cancel the warning for no response
	if self.timer then
		self.timer:stop()
		self.timer = nil
	end

	log:info("received information")

	_currentInformation = result.item_loop

	-- itterate though response - handle leaves as well as branches
	if result.item_loop then
		log:info("update based on received information")
		self:_updateInformation(result.layout,result.item_loop)
	end
end

function _updateInformation(self, layout, items)
	if not items then
		log:info("Got no items!")
		return
	end

	if self.layout != layout then
		log:info("Re-creating widgets")
		self:_createUIItems(layout,items)
	else
		log:info("Updating widgets")
		self:_updateUIItems(layout,items)
	end
	
end

----------------------------------------------------------------------------------------
-- Screen Saver Display 
--

function _createUI(self)
	local window = Window("window")


	-- register window as a screensaver, unless we are explicitly not in that mode
	local manager = appletManager:getAppletInstance("ScreenSavers")
	manager:screensaverWindow(window)

	return window
end

function _createUIItems(self,layout,items)
	local window = Window("window")
	self.items = {}
	for index,item in ipairs(items) do
		log:info("Handling item " .. index .. ": " .. item.align)
		local style = "title"
		if item.align == "rightlist" or item.align == "leftlist" then
			style = "multilineitem"
		end
		if item.text then
			self.items[index] = Group(style, {
				text = Label("text",item.text)
			})
			log:info("Creating text item with style=" .. style .. " and data: " .. item.text)
		elseif item.icon then
			self.items[index] = Group(style, {
				text = Label("text",item.icon)
			})		
			log:info("Creating icon item with style=" .. style .. " and data: " .. item.icon)
		end
	end
	for index,item in ipairs(self.items) do
		if item then
			window:addWidget(item)
			log:info("adding widget " .. index)
		end
	end

	window:focusWidget(self.items[1])

	log:info("Replacing window and returning")
	window:replace(self.window)
	self.layout = layout
	self.window = window
end

local _counter = 0
function _updateUIItems(self,layout,items)
	for index,item in ipairs(items) do
		if item.text then
			log:info("Updating item " .. index .." with previous data:" .. self.items[index]:getWidgetValue("text"))
			self.items[index]:setWidgetValue("text",item.text .. _counter)
			log:info("Updating item " .. index .." with data:" .. item.text)
		elseif item.icon then
			log:info("Updating item " .. index .." with previous data:" .. self.items[index]:getWidgetValue("text"))
			self.items[index]:setWidgetValue("text",item.icon .. _counter)
			log:info("Updating item " .. index .." with data:" .. item.icon)
		end
	end
	_counter = _counter +1
end

--[[

=head1 LICENSE

This source code is public domain. It is intended for you to use as a starting
point to create your own applet.

=cut
--]]


