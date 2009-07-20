
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

	self.window = _createUI(self)

	-- if we have data, then update and display it
	if _currentInformation then
		self:_updateInformation(_currentInformation)

		self:_getInformation()

	-- otherwise punt
	else
		self:_getInformation()
		self:_updateInformation()
	end

	self.window:show(Window.transitionFadeIn)
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
		self:_updateInformation(result.item_loop)
	end
end

function _updateInformation(self, items)
	if not items then
		return
	end

	local itemtext
	for _,entry in ipairs(items) do
		if entry.text then
			log:info("Handling",entry.text)
			if itemtext then
				itemtext = itemtext .. "\n"
			else
				itemtext = ""
			end
			itemtext = itemtext .. entry.text
		end
	end

	if self.trackGroup then
		log:info("Setting value to ",itemtext)
		self.trackGroup:setWidgetValue("text", itemtext)
	end
end

----------------------------------------------------------------------------------------
-- Screen Saver Display 
--

function _createUI(self)
	local window = Window("window")

	self.titleGroup = Group("title", {
		text = Label("text", self:string("SCREENSAVER_INFORMATIONSCREEN")),
	})

	self.trackGroup = Group("multilineitem", {
		text = Label("text", ""),
	})
	self.trackGroup2 = Group("multilineitem", {
		text = Label("text", "A\nB\nC"),
	})
	self.trackGroup3 = Group("multilineitem", {
		text = Label("text", "D\nE\nF"),
	})
	self.trackGroup4 = Group("multilineitem", {
		text = Label("text", "G\nH\nI"),
	})
	
	-- window:addWidget(self.titleGroup)
	window:addWidget(self.trackGroup)
	window:addWidget(self.trackGroup2)
	window:addWidget(self.trackGroup3)
	window:addWidget(self.trackGroup4)

	window:focusWidget(self.trackGroup)

	-- register window as a screensaver, unless we are explicitly not in that mode
	local manager = appletManager:getAppletInstance("ScreenSavers")
	manager:screensaverWindow(window)

	return window
end

--[[

=head1 LICENSE

This source code is public domain. It is intended for you to use as a starting
point to create your own applet.

=cut
--]]


