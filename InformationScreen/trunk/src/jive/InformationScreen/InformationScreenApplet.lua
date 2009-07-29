
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
local Tile             = require("jive.ui.Tile")
local Font             = require("jive.ui.Font")
local SimpleMenu       = require("jive.ui.SimpleMenu")

local appletManager    = appletManager
local jiveMain         = jiveMain
local JIVE_VERSION      = jive.JIVE_VERSION
local WH_FILL		= jive.ui.WH_FILL
local LAYOUT_NORTH	= jive.ui.LAYOUT_NORTH
local LAYOUT_SOUTH	= jive.ui.LAYOUT_SOUTH
local LAYOUT_CENTER	= jive.ui.LAYOUT_CENTER
local LAYOUT_WEST	= jive.ui.LAYOUT_WEST
local LAYOUT_EAST	= jive.ui.LAYOUT_EAST

local fontpath = "fonts/"
local FONT_NAME = "FreeSans"
local BOLD_PREFIX = "Bold"

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

	log:debug("requesting information")
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
	log:debug("received information")

	-- Update screen with new information
	if not result.item_loop then
		log:debug("Got no items!")
	else
		local style = nil
		if result.style then
			style = result.style
		end
		local skin = nil
		if result.skin then
			skin = result.skin
		end
		if self.layout != result.layout or self.layoutChangedTime != result.layoutChangedTime or self.layoutSkin != jiveMain:getSelectedSkin() then
			log:debug("Re-creating widgets")
			self:_createUIItems(skin,style,result.item_loop)
			self.layoutChangedTime = result.layoutChangedTime;
			self.layout = result.layout
			self.layoutSkin = jiveMain:getSelectedSkin()
		else 
			log:debug("Updating widgets")
			self:_updateUIItems(style,result.item_loop)
		end
	end
	-- Start time to make sure new information is requested from server in a while
	if self.timer then
		self.window:removeTimer(self.timer)
	end
	if result.remainingtime then
		local remainingtime = result.remainingtime
		if remainingtime>60 then
			-- We want to update at least every minute
			remainingtime = 60
		end
		self.timer = self.window:addTimer(remainingtime*1000, function() self:_getInformation() end, true)
	else
		self.timer = self.window:addTimer(5000, function() self:_getInformation() end, true)
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

function _createUIItems(self,skin,style,groups)
	local window = nil
	local path = nil
	if style then
		log:debug("Creating window with style: " .. style)
		window = Window(style)
		path = style
	else
		log:debug("Creating window with default style")
		window = Window("window")
		path = "window"
	end
	if skin and skin == "getClockStyles" then
		log:debug("Creating window with skin styles: " .. skin)
		window:setSkin(self:_getClockStyles(jiveMain:getSelectedSkin()))
		window:reSkin()
	elseif skin and skin == "getStandardStyles" then
		log:debug("Creating window with skin styles: " .. skin)
		window:setSkin(self:_getStandardStyles(jiveMain:getSelectedSkin()))
		window:reSkin()
	end
	self.groups = {}
	for index,group in ipairs(groups) do
		log:debug("Handling group " .. index .. ": " .. group.id)
		local groupItems = self:_createGroupItems(window,group,path.."."..group.id)
		self.groups[group.id] = Group(group.id,groupItems)
		if group.type == "simplemenu" then
			log:debug("Creating SimpleMenu(" .. group.id..") with path "..path.."."..group.id)
			self.groups[group.id] = SimpleMenu(group.id)
			log:debug("Setting menu items")
			self.groups[group.id]:setItems(self:_createMenuItemsArray(groupItems))
			window:addWidget(self.groups[group.id])
		elseif group.flatten then
			log:debug("Flatten group " .. group.id)
			for itemIndex,item in pairs(groupItems) do
				log:debug("Adding item widget "..itemIndex)
				window:addWidget(item)
			end
		else 
			log:debug("Creating Group("..group.id..", ... ) with path " .. path .. "." .. group.id)
			log:debug("Adding group widget")
			window:addWidget(self.groups[group.id])
		end
	end

	local first = 1
	for index,group in ipairs(self.groups) do
		if first then
			log:debug("Setting focus to " .. group.id)
			window:focusWidget(self.groups[group.id])
		end
		first = nil
	end

	log:debug("Replacing window and returning")
	window:show(Window.transitionFadeIn)
	self.window:hide()
	self.window = window
end

function _createMenuItemsArray(self,items)
	local itemArray = {}
	for index,item in pairs(items) do
		itemArray[#itemArray +1] = item
	end
	return itemArray
end

function _createGroupItems(self,window,group,path)
	local items = {}
	for itemIndex,item in ipairs(group.item) do
		local itemObj = nil
		local itemStyle = item.id
		if item.style then
			itemStyle = item.style
		end
		log:debug("Handling item " .. item.id)
		if item.type == "label" and item.value then
			log:debug("Creating Label(" .. itemStyle .. "," .. item.value .. ") with path "..path.."."..itemStyle)
			itemObj = Label(itemStyle,item.value)
		elseif item.type == "text" then
			log:debug("Creating text item")
			if not item.value then
				item.value = ""
			end
			itemObj = item.value
		elseif item.type == "slider" and item.value then
			if not item.min then
				item.min = 0
			end
			if not item.max then
				item.max = 100
			end
			log:debug("Creating Slider(" .. itemStyle .. "," .. item.min .. "," .. item.max .. "," .. item.value .. ") with path "..path.."."..itemStyle)
			itemObj = Slider(itemStyle,tonumber(item.min),tonumber(item.max),tonumber(item.value))
		elseif item.type == "defaultleftbutton" then
			log:debug("Creating default left button")
			itemObj = window:createDefaultLeftButton()
		elseif item.type == "defaultrightbutton" then
			log:debug("Creating default left button")
			itemObj = window:createDefaultRightButton()
		elseif item.type == "button" and (item.action or item.service) then
			local action = nil
			if item.action then
				log:debug("Configuring action ".. item.action);
				action = function()
					Framework:pushAction(item.action)
					return EVENT_CONSUME
				end
			elseif item.service then
				log:debug("Configuring service ".. item.service);
				action = function()
					appletManager:callService(item.service)
					return EVENT_CONSUME
				end
			end
			local holdAction = nil
			if item.holdAction then
				log:debug("Configuring holdAction ".. item.holdAction);
				holdAction = function()
					Framework:pushAction(item.holdAction)
					return EVENT_CONSUME
				end
			elseif item.holdService then
				log:debug("Configuring holdService ".. item.holdService);
				holdAction = function()
					appletManager:callService(item.holdService)
					return EVENT_CONSUME
				end
			end
			local longHoldAction = nil
			if item.longHoldAction then
				log:debug("Configuring longHoldAction ".. item.longHoldAction);
				longHoldAction = function()
					Framework:pushAction(item.longHoldAction)
					return EVENT_CONSUME
				end
			elseif item.longHoldService then
				log:debug("Configuring longHoldService ".. item.longHoldService);
				longHoldAction = function()
					appletManager:callService(item.longHoldService)
					return EVENT_CONSUME
				end
			end
			local buttonWidget = nil
			if item.icon or item["icon-id"] or item.groupIcon then
				local buttonIcon = nil
				if item.groupIcon and item.style then
					log:debug("Creating Button Group("..item.style..", Icon(" .. item.groupIcon .. ")) with path "..path.."."..item.style)
					if item.preprocessing and item.preprocessing == "artwork" then
						buttonWidget = Group(item.style,{self:_getArtwork(item,Icon(item.groupIcon))})
					else
						buttonWidget = Group(item.style,{Icon(item.groupIcon)})
					end
				else
					local iconId = nil
					if item.icon then
						iconId = item.icon
					else
						iconId = item["icon-id"]
					end
					log:debug("Creating Button Icon(" .. iconId .. ") with path "..path)
					if item.preprocessing and item.preprocessing == "artwork" then
						buttonWidget = self:_getArtwork(item,Icon(tostring(iconId)))
					else
						buttonWidget = Icon(iconId)
					end
				end
			elseif item.value then
				log:debug("Creating Button Label(" .. itemStyle .. "," .. item.value .. ") with path "..path.."."..itemStyle)
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
		elseif item.type == "icon" and item.preprocessing and item.preprocessing == "artwork" then
			log:debug("Creating artwork Icon(artwork) with path "..path..".artwork");
			itemObj = self:_getArtwork(item,Icon("artwork"))
		elseif item.type == "icon" and item.icon then
			log:debug("Creating Icon(" .. item.icon .. ") with path "..path.."."..item.icon)
			itemObj = Icon(item.icon)
		elseif item.type == "button" then
			if item.icon then
				log:debug("Creating Icon(" .. item.icon .. ") with path "..path.."."..item.icon)
				itemObj = Icon(item.icon)
			elseif item.value then
				log:debug("Creating Label(" .. item.id .. "," .. item.value .. ") with path "..path.."."..item.id)
				itemObj = Label(item.id,item.value)
			end
		elseif item.type == "group" or not item.type then
			log:debug("Reading group items")
			local groupItems = self:_createGroupItems(window,item,path.."."..item.id)
			log:debug("Creating Group(" .. item.id..") with path "..path.."."..item.id)
			itemObj = Group(item.id,groupItems)
		elseif item.type == "menuitem" then
			log:debug("Creating menu item ".. item.id.." for path "..path.."."..item.id)
			itemObj = self:_createGroupItems(window,item,path.."."..item.id)
		elseif item.type == "simplemenu" then
			log:debug("Reading menu items")
			local menuItems = self:_createGroupItems(window,item,path.."."..item.id)
			log:debug("Creating SimpleMenu(" .. item.id..") with path "..path.."."..item.id)
			itemObj = SimpleMenu(item.id)
			log:debug("Setting menu items")
			itemObj:setItems(self:_createMenuItemsArray(menuItems))
		end
		if itemObj then
			if item.style and item.type != "menuitem" then
				log:debug("Set style of ".. item.id .. " to " .. item.style)
				itemObj:setStyle(item.style)
			elseif item.style and item.type == "menuitem" then
				log:debug("Set style of ".. item.id .. " to " .. item.style)
				itemObj['style'] = item.style
			end
			log:debug("Adding item ".. item.id)
			items[item.id] = itemObj
		end
	end
	return items
end

function _getArtwork(self,item,icon)
	if item.preprocessingData and item.preprocessingData == "fullscreen" then
		local width,height = Framework.getScreenSize()
		local usableHeight = height
		local skinName = jiveMain:getSelectedSkin()
		if skinName == "QVGAlandscapeSkin" or skinName == "QVGAportraitSkin" then
			usableHeight = usableHeight-24
		end
		if width<usableHeight then 
			self:_getIcon(item,icon,width)
		else
			self:_getIcon(item,icon,usableHeight)
		end
	elseif item.preprocessingData and item.preprocessingData == "thumb" then
		self:_getIcon(item,icon,jiveMain:getSkinParam("THUMB_SIZE"))
	else
		self:_getIcon(item,icon)
	end
	return icon
end
function _updateUIItems(self,style,groups)
	if style and style != self.window:getStyle() then
		log:debug("Setting window style to: " .. style)
		self.window:setStyle(style)
	end
	for index,group in ipairs(groups) do
		if not group.type or group.type != "simplemenu" then
			log:debug("Updating group items for "..group.id)
			self:_updateGroupItems(group)
		elseif group.type and group.type == "simplemenu" then
			log:debug("Updating menu items for menu "..group.id)
			local menuItems = self:_createGroupItems(self.window,group,group.id)
			local itemObj = self.groups[group.id]
			if itemObj then
				log:debug("Setting menuItems for " .. group.id)
				itemObj:setItems(self:_createMenuItemsArray(menuItems))
			end
		else
			log:debug("Invalid item on top "..group.id)
		end
	end
end

function _updateGroupItems(self,group)
	for itemIndex,item in ipairs(group.item) do
		if item.type == "label" then
			log:debug("Updating item " .. item.id .." with value:" .. item.value)
			self.groups[group.id]:setWidgetValue(item.id,item.value)
		elseif item.type == "icon" and item.value then
			log:debug("Updating item " .. item.id .." with value:" .. item.value)
			self.groups[group.id]:setWidgetValue(item.id,item.value)
		elseif item.type == "slider" and item.value then
			log:debug("Updating item " .. item.id .." with value:" .. item.value)
			if not item.min then
				item.min = 0
			end
			if not item.max then
				item.max = 100
			end
			self.groups[group.id]:getWidget(item.id):setRange(tonumber(item.min),tonumber(item.max),tonumber(item.value))
		elseif item.type == "icon" and item.preprocessing and item.preprocessing == "artwork" then
			log:debug("Updating artwork Icon(artwork)");
			self:_getArtwork(item,self.groups[group.id]:getWidget(item.id))
		elseif item.type == "button" and item.value then
			log:debug("Updating item " .. item.id .." with value:" .. item.value)
			if item.preprocessing and item.preprocessing == "artwork" then
				if item.groupIcon then
					self:_getArtwork(item,self.groups[group.id]:getWidget(item.id):getWidget(0))
				elseif item.icon or item["icon-id"] then
					self:_getArtwork(item,self.groups[group.id]:getWidget(item.id))
				end
			end
			self.groups[group.id]:setWidgetValue(item.id,item.value)
		elseif item.type == "group" or not item.type then
			log:debug("Handling sub groups under " .. item.id)
			self:_updateGroupItems(item)
		end
		if item.type and item.type != "group" and item.type != "menuitem" then
			local widget = self.groups[group.id]:getWidget(item.id)
			if item.style and item.type != "menuitem" and item.style != widget:getStyle() then
				log:debug("Updating item style " .. item.id ..":" .. item.style)
				widget:setStyle(item.style)
			end
		end
	end
end

function _getIcon(self, item, icon, size)
	local server = self.player:getSlimServer()

	local ARTWORK_SIZE = nil
	if size then
		ARTWORK_SIZE = size
	else
		ARTWORK_SIZE = jiveMain:getSkinParam("nowPlayingBrowseArtworkSize")
	end

	if item and item["icon-id"] then
		-- Fetch an image from Squeezebox Server
		log:debug("Fetch image from server");
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
				log:debug("Fetch remote image from url");
				server:fetchArtworkURL(item["icon"], icon, ARTWORK_SIZE)
			else
				log:debug("Fetch remote image from server");
				server:fetchArtworkThumb(item["icon"], icon, ARTWORK_SIZE)
			end
		else 
				log:debug("Fetch image from server");
				server:fetchArtwork(item["icon"], icon, ARTWORK_SIZE)
		end
	elseif icon then
		log:debug("Disable image");
		icon:setValue(nil)
	end
end

local function _boldfont(fontSize)
        return Font:load(fontpath .. FONT_NAME .. BOLD_PREFIX .. ".ttf", fontSize)
end

local function _font(fontSize)
        return Font:load(fontpath .. FONT_NAME .. ".ttf", fontSize)
end

function _getClockStyles(self, skinName)
	local s = {}
	local width,height = Framework.getScreenSize()
	s.InformationScreenClock = {
		time = {
			position = LAYOUT_NORTH,
			border = {0,40,0,40},
			time = {
				font = _font(width*3/8),
				align = 'center',
				w = WH_FILL,
				fg = { 0xcc,0xcc,0xcc },
			},
		},
		date = {
			position = LAYOUT_SOUTH,
			border = {0,0,0,15},
			date = {
				font = _font(40),
				align = 'center',
				w = WH_FILL,
				h = 70,
				fg = { 0xcc, 0xcc, 0xcc },
			},
		}
	}
	s.InformationScreenClockBlack = {
		bgImg = Tile:fillColor(0x000000ff),
		time = {
			position = LAYOUT_NORTH,
			border = {0,40,0,40},
			time = {
				font = _font(width*3/8),
				align = 'center',
				w = WH_FILL,
				fg = { 0xcc,0xcc,0xcc },
			},
		},
		date = {
			position = LAYOUT_SOUTH,
			border = {0,0,0,15},
			date = {
				font = _font(40),
				align = 'center',
				w = WH_FILL,
				h = 70,
				fg = { 0xcc, 0xcc, 0xcc },
			},
		}
	}
	s.InformationScreenClockAndNowPlaying = {
		playingtitle = {
			position = LAYOUT_NORTH,
			border = {0,15,0,0},
			playingtitle = {
				font = _font(width/20),
				lineHeight = width/20,
				align = 'center',
				w = WH_FILL,
				fg = { 0xcc,0xcc,0xcc },
			},
		},
		time = {
			position = LAYOUT_CENTER,
			border = {0,20,0,20},
			time = {
				font = _font(width*3/8-10),
				align = 'center',
				w = WH_FILL,
				fg = { 0xcc,0xcc,0xcc },
			},
		},
		date = {
			position = LAYOUT_SOUTH,
			border = {0,30,0,20},
			date = {
				font = _font(width/10),
				align = 'center',
				w = WH_FILL,
				h = 70,
				fg = { 0xcc, 0xcc, 0xcc },
			},
		}
	}
	s.InformationScreenClockAndNowPlayingBlack = {
		bgImg = Tile:fillColor(0x000000ff),
		playingtitle = {
			position = LAYOUT_NORTH,
			border = {0,15,0,0},
			playingtitle = {
				font = _font(width/20),
				lineHeight = width/20,
				align = 'center',
				w = WH_FILL,
				fg = { 0xcc,0xcc,0xcc },
			},
		},
		time = {
			position = LAYOUT_CENTER,
			border = {0,20,0,20},
			time = {
				font = _font(width*3/8-10),
				align = 'center',
				w = WH_FILL,
				fg = { 0xcc,0xcc,0xcc },
			},
		},
		date = {
			position = LAYOUT_SOUTH,
			border = {0,30,0,20},
			date = {
				font = _font(width/10),
				align = 'center',
				w = WH_FILL,
				h = 70,
				fg = { 0xcc, 0xcc, 0xcc },
			},
		}
	}
	return s;		
end

function _getStandardStyles(self, skinName)
	local s = {}
	local width,height = Framework.getScreenSize()
	local threeRowFont = width/14;

	local screenInformationHugeText = {
		font = _boldfont(threeRowFont*3),
		align = 'center',
		w = WH_FILL,
		h = WH_FILL,
		fg = { 0xcc,0xcc,0xcc },
		lineHeight = threeRowFont*3 + threeRowFont*3/10
	}
	local screenInformationLargeText = {
		font = _boldfont(threeRowFont*1.5),
		align = 'center',
		w = WH_FILL,
		h = WH_FILL,
		fg = { 0xcc,0xcc,0xcc },
		lineHeight = threeRowFont*2 + threeRowFont*2/10
	}
	local screenInformationMediumText = {
		font = _font(threeRowFont),
		align = 'center',
		w = WH_FILL,
		h = WH_FILL,
		fg = { 0xcc,0xcc,0xcc },
		lineHeight = threeRowFont + threeRowFont/10
	}
	local screenInformationSmallText = {
		font = _font(threeRowFont*2/3),
		align = 'center',
		w = WH_FILL,
		h = WH_FILL,
		fg = { 0xcc,0xcc,0xcc },
		lineHeight = threeRowFont*2/3 + (threeRowFont*2/3)/10
	}

	local usableHeight = height-height*0.2-20
	if skinName == "QVGAlandscapeSkin" or skinName == "QVGAportraitSkin" then
		usableHeight = usableHeight-24
	end
	local threeRowHeight = (usableHeight)/3
	log:debug("Using row height of: "..threeRowHeight)
	-- Three lines with equally sized text
	s.InformationScreenThreeLineText = {
		bgImg = Tile:fillColor(0x00000055),
		top = {
			h = threeRowHeight,
			border = {10,height*0.1,10,5},
			screenInformationHugeText = screenInformationHugeText,
			screenInformationLargeText = screenInformationLargeText,
			screenInformationMediumText = screenInformationMediumText,
			screenInformationSmallText = screenInformationSmallText
		},
		center = {
			h = threeRowHeight,
			border = {10,5,10,5},
			screenInformationHugeText = screenInformationHugeText,
			screenInformationLargeText = screenInformationLargeText,
			screenInformationMediumText = screenInformationMediumText,
			screenInformationSmallText = screenInformationSmallText
		},
		bottom = {
			h = threeRowHeight,
			border = {10,5,10,height*0.1},
			screenInformationHugeText = screenInformationHugeText,
			screenInformationLargeText = screenInformationLargeText,
			screenInformationMediumText = screenInformationMediumText,
			screenInformationSmallText = screenInformationSmallText
		}
	}
	s.InformationScreenThreeLineTextBlack = {
		bgImg = Tile:fillColor(0x000000ff),
		top = {
			h = threeRowHeight,
			border = {10,height*0.1,10,5},
			screenInformationHugeText = screenInformationHugeText,
			screenInformationLargeText = screenInformationLargeText,
			screenInformationMediumText = screenInformationMediumText,
			screenInformationSmallText = screenInformationSmallText
		},
		center = {
			h = threeRowHeight,
			border = {10,5,10,5},
			screenInformationHugeText = screenInformationHugeText,
			screenInformationLargeText = screenInformationLargeText,
			screenInformationMediumText = screenInformationMediumText,
			screenInformationSmallText = screenInformationSmallText
		},
		bottom = {
			h = threeRowHeight,
			border = {10,5,10,height*0.1},
			screenInformationHugeText = screenInformationHugeText,
			screenInformationLargeText = screenInformationLargeText,
			screenInformationMediumText = screenInformationMediumText,
			screenInformationSmallText = screenInformationSmallText
		}
	}

	local leftImageBorder = 0
	local usableImageHeight = height

	if skinName == "QVGAlandscapeSkin" or skinName == "QVGAportraitSkin" then
		usableImageHeight = height-24
	end
	if width > usableImageHeight then
		leftImageBorder = ((width-usableImageHeight)/2)
	end

	s.InformationScreenImage = {
		image = {
			border = {leftImageBorder,0,leftImageBorder,0},
		}
	}
	s.InformationScreenImageBlack = {
		bgImg = Tile:fillColor(0x000000ff),
		image = {
			border = {leftImageBorder,0,leftImageBorder,0},
		}
	}
	return s;		
end

--[[

=head1 LICENSE

This source code is public domain. It is intended for you to use as a starting
point to create your own applet.

=cut
--]]


