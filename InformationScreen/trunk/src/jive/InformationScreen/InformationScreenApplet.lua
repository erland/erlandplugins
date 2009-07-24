
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
local pairs, ipairs, tostring, tonumber = pairs, ipairs, tostring, tonumber

local oo               = require("loop.simple")

local Applet           = require("jive.Applet")
local Window           = require("jive.ui.Window")
local Label            = require("jive.ui.Label")
local Button           = require("jive.ui.Button")
local Icon             = require("jive.ui.Icon")
local Group            = require("jive.ui.Group")
local Slider           = require("jive.ui.Slider")
local Framework        = require("jive.ui.Framework")

local log              = require("jive.utils.log").logger("applets.screensavers")

local appletManager    = appletManager
local jiveMain         = jiveMain
local JIVE_VERSION      = jive.JIVE_VERSION

module(...)
oo.class(_M, Applet)


----------------------------------------------------------------------------------------
-- Helper Functions
--

-- display
-- the main applet function, the meta arranges for it to be called
-- by the ScreenSaversApplet.
function openScreensaver(self)

	-- if we're opening this after freeing the applet, grab the player again
	if not self.player then
		self.player = appletManager:callService("getCurrentPlayer")
	end
  
        -- Create the main window if it doesn't already exist
	if not self.window then
		self.window = _createUI(self)
	end

	-- Show the window
	self.window:show(Window.transitionFadeIn)

	-- Retrieve information from the server
	self:_getInformation()
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
		{ 'informationscreen', 'items','skin:' .. jiveMain:getSelectedSkin()}
	)
	return true
end

function _getInformationResponse(self, result)
	log:info("received information")

	-- Update screen with new information
	if not result.item_loop then
		log:info("Got no items!")
	else
		local style = nil
		if result.style then
			style = result.style
		end
		if self.layout != result.layout or self.layoutChangedTime != result.layoutChangedTime then
			log:info("Re-creating widgets")
			self:_createUIItems(style,result.item_loop)
			self.layoutChangedTime = result.layoutChangedTime;
			self.layout = result.layout
		else 
			log:info("Updating widgets")
			self:_updateUIItems(style,result.item_loop)
		end
	end
	-- Start time to make sure new information is requested from server in a while
	if self.timer then
		self.window:removeTimer(self.timer)
	end
	self.timer = self.window:addTimer(5000, function() self:_getInformation() end, true)
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

function _createUIItems(self,style,groups)
	local window = nil
	if style then
		log:info("Creating window with style: " .. style)
		window = Window(style)
	else
		log:info("Creating window with default style")
		window = Window("window")
	end
	self.groups = {}
	for index,group in ipairs(groups) do
		log:info("Handling group " .. index .. ": " .. group.id)
		local items = {}
		for itemIndex,item in ipairs(group.item) do
			local itemObj = nil
			local itemStyle = item.id
			if item.style then
				itemStyle = item.style
			end
			if item.type == "label" and item.value then
				log:info("Creating Label(" .. item.id .. "," .. item.value .. ")")
				itemObj = Label(itemStyle,item.value)
			elseif item.type == "slider" and item.value then
				if not item.min then
					item.min = 0
				end
				if not item.max then
					item.max = 100
				end
				log:info("Creating Slider(" .. itemStyle .. "," .. item.min .. "," .. item.max .. "," .. item.value .. ")")
				itemObj = Slider(itemStyle,tonumber(item.min),tonumber(item.max),tonumber(item.value))
			elseif item.type == "defaultleftbutton" then
				log:info("Creating default left button")
				itemObj = window:createDefaultLeftButton()
			elseif item.type == "defaultrightbutton" then
				log:info("Creating default left button")
				itemObj = window:createDefaultRightButton()
			elseif item.type == "button" and (item.action or item.service) then
				local action = nil
				if item.action then
					log:info("Configuring action ".. item.action);
					action = function()
						Framework:pushAction(item.action)
						return EVENT_CONSUME
					end
				elseif item.service then
					log:info("Configuring service ".. item.service);
					action = function()
						appletManager:callService(item.service)
						return EVENT_CONSUME
					end
				end
				local holdAction = nil
				if item.holdAction then
					log:info("Configuring holdAction ".. item.holdAction);
					holdAction = function()
						Framework:pushAction(item.holdAction)
						return EVENT_CONSUME
					end
				elseif item.holdService then
					log:info("Configuring holdService ".. item.holdService);
					holdAction = function()
						appletManager:callService(item.holdService)
						return EVENT_CONSUME
					end
				end
				local longHoldAction = nil
				if item.longHoldAction then
					log:info("Configuring longHoldAction ".. item.longHoldAction);
					longHoldAction = function()
						Framework:pushAction(item.longHoldAction)
						return EVENT_CONSUME
					end
				elseif item.longHoldService then
					log:info("Configuring longHoldService ".. item.longHoldService);
					longHoldAction = function()
						appletManager:callService(item.longHoldService)
						return EVENT_CONSUME
					end
				end
				local buttonWidget = nil
				if item.icon or item.groupIcon then
					local buttonIcon = nil
					if item.groupIcon and item.style then
						log:info("Creating Button Group("..item.style..", Icon(" .. item.groupIcon .. "))")
						buttonWidget = Group(item.style,{Icon(item.groupIcon)})
					else
						log:info("Creating Button Icon(" .. item.icon .. ")")
						buttonWidget = Icon(item.icon)
					end
				elseif item.value then
					log:info("Creating Button Label(" .. itemStyle .. "," .. item.value .. ")")
					buttonWidget = Label(itemStyle, item.value)
				end
				if buttonWidget then
					itemObj = Button(
						buttonWidget,
						action,
						holdAction,
						longHoldAction
					)
				end
			elseif item.type == "icon" and item.icon then
				log:info("Creating Icon(" .. item.icon .. ")")
				itemObj = Icon(item.icon)
			elseif item.type == "icon" and item.preprocessing and item.preprocessing == "artwork" then
				log:info("Creating artwork Icon(artwork)");
				itemObj = Icon("artwork")
				self:_getIcon(item,itemObj)
			elseif item.type == "button" then
				if item.icon then
					log:info("Creating Icon(" .. item.icon .. ")")
					itemObj = Icon(item.icon)
				elseif item.value then
					log:info("Creating Label(" .. item.id .. "," .. item.value .. ")")
					itemObj = Label(item.id,item.value)
				end
			end
			if itemObj then
				if item.style then
					log:info("Set style of ".. item.id .. " to " .. item.style)
					itemObj:setStyle(item.style)
				end
				items[item.id] = itemObj
			end
		end
		self.groups[group.id] = Group(group.id,items)
		if group.flatten then
			log:info("Flatten group " .. group.id)
			for itemIndex,item in pairs(items) do
				log:info("Adding widget " .. itemIndex)
				window:addWidget(item)
			end
		else 
			log:info("Adding group widget " .. group.id)
			window:addWidget(self.groups[group.id])
		end
	end

	local first = 1
	for index,group in ipairs(self.groups) do
		if first then
			log:info("Setting focus to " .. group.id)
			window:focusWidget(self.groups[group.id])
		end
		first = nil
	end

	log:info("Replacing window and returning")
	window:show(Window.transitionFadeIn)
	self.window:hide()
	self.window = window
end

function _updateUIItems(self,style,groups)
	if style and style != self.window:getStyle() then
		log:info("Setting window style to: " .. style)
		self.window:setStyle(style)
	end
	for index,group in ipairs(groups) do
		for itemIndex,item in ipairs(group.item) do
			if item.type == "label" then
				log:info("Updating item " .. item.id .." with value:" .. item.value)
				self.groups[group.id]:setWidgetValue(item.id,item.value)
			elseif item.type == "icon" and item.value then
				log:info("Updating item " .. item.id .." with value:" .. item.value)
				self.groups[group.id]:setWidgetValue(item.id,item.value)
			elseif item.type == "slider" and item.value then
				log:info("Updating item " .. item.id .." with value:" .. item.value)
				if not item.min then
					item.min = 0
				end
				if not item.max then
					item.max = 100
				end
				self.groups[group.id]:getWidget(item.id):setRange(tonumber(item.min),tonumber(item.max),tonumber(item.value))
			elseif item.type == "icon" and item.preprocessing and item.preprocessing == "artwork" then
				log:info("Updating artwork Icon(artwork)");
				self:_getIcon(item,self.groups[group.id]:getWidget(item.id))
			elseif item.type == "button" and item.value then
				log:info("Updating item " .. item.id .." with value:" .. item.value)
				self.groups[group.id]:setWidgetValue(item.id,item.value)
			end
			local widget = self.groups[group.id]:getWidget(item.id)
			if item.style and item.style != widget:getStyle() then
				log:info("Updating item style " .. item.id ..":" .. item.style)
				widget:setStyle(item.style)
			end
		end
	end
end

function _getIcon(self, item, icon)
	local server = self.player:getSlimServer()

	local ARTWORK_SIZE = jiveMain:getSkinParam("nowPlayingBrowseArtworkSize")
	if item and item["icon-id"] then
		-- Fetch an image from Squeezebox Server
		log:info("Fetch image from server");
		if JIVE_VERSION < "7.4 r6069" then
			server:fetchArtworkThumb(item["icon-id"], icon, ARTWORK_SIZE) 
		else
			server:fetchArtwork(item["icon-id"], icon, ARTWORK_SIZE) 
		end
	elseif item and item["icon"] then
		if JIVE_VERSION < "7.4 r6069" then
			-- Fetch a remote image URL, sized to ARTWORK_SIZE x ARTWORK_SIZE
			local remoteContent = string.find(item['icon'], 'http://')
			-- sometimes this is static content
			if remoteContent then
				log:info("Fetch remote image from url");
				server:fetchArtworkURL(item["icon"], icon, ARTWORK_SIZE)
			else
				log:info("Fetch remote image from server");
				server:fetchArtworkThumb(item["icon"], icon, ARTWORK_SIZE)
			end
		else 
				log:info("Fetch image from server");
				server:fetchArtwork(item["icon"], icon, ARTWORK_SIZE)
		end
	elseif icon then
		log:info("Disable image");
		icon:setValue(nil)
	end
end

--[[

=head1 LICENSE

This source code is public domain. It is intended for you to use as a starting
point to create your own applet.

=cut
--]]


