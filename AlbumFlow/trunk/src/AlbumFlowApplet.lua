
--[[
=head1 NAME

applets.AlbumFlow.AlbumFlowApplet - An applet that makes it possible to browse your albums similar to Apple's cover flow

=head1 DESCRIPTION

Album Slide is an applet for Squeezeplay that makes it possible to browse through
your albums using a similar view as Apple's cover flow view

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 

=cut
--]]


-- stuff we use
local pairs, ipairs, tostring, tonumber,collectgarbage = pairs, ipairs, tostring, tonumber,collectgarbage

local oo               = require("loop.simple")
local os               = require("os")
local math             = require("math")
local string           = require("jive.utils.string")
local table            = require("jive.utils.table")
local debug            = require("jive.utils.debug")

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

local FRAME_RATE	= jive.ui.FRAME_RATE

local ANIM_RANGE	= 6
local SS_ANIM_RANGE	= 40
local IMG_PATH          = "applets/AlbumFlow/"

module(..., Framework.constants)
oo.class(_M, Applet)


----------------------------------------------------------------------------------------
-- Helper Functions
--

function openScreensaver(self)
	self:_initApplet(true)
end
-- display
-- the main applet function, the meta arranges for it to be called
-- by the ScreenSaversApplet.
function menu(self)
	self:_initApplet(false)
end

function _initApplet(self, ss)
	log:debug("Recreating screensaver window")
	local width,height = Framework.getScreenSize()
	if width == 480 then
		self.model = "touch"
	elseif width == 320 then
		self.model = "radio"
	else
		self.model = "controller"
	end

	self.images = {}

	self.window = Window("window")
	self.window:setSkin(self:_getSkin(jiveMain:getSelectedSkin()))
	self.window:reSkin()

	local backgroundItems = {
		background = Icon("background")
	}
	self.backgroundImage = Group("background",backgroundItems)

	self.canvas = Canvas('debug_canvas',function(screen)
			self:_reDrawCanvas(screen)
		end)

	local canvasItems = {
		canvas = self.canvas
	}
	local canvasGroup = Group("canvas",canvasItems)

	local titleItems = {
		albumtext = Label("albumtext"," ")
	}
	self.titleGroup = Group("albumtext",titleItems)

	self.window:addWidget(self.backgroundImage)
	self.window:addWidget(canvasGroup)
	self.window:addWidget(self.titleGroup)
	self.window:focusWidget(self.titleGroup)

	self.right = true
	self.currentPos = -1
	self.currentDelta = 0
	self.currentScroll = 0
	self.loading =  false
	self.screensaver = false
	self.albums = {}
	self.maxIndex = 0
	self.iconPool = {}
	if ss then
		self.screensaver = true
		self.currentScroll = 1
		self.currentDelta = SS_ANIM_RANGE
		self.currentPos = -1
		self.animateRange = SS_ANIM_RANGE
	else
		self.animateRange = ANIM_RANGE
	end

	self.player = appletManager:callService("getCurrentPlayer")
	self.server = self.player:getSlimServer()

	-- Load albums
	self:_loadAlbums(0)

	self.canvas:addAnimation(
		function()
			self:_refresh()
		end,
		FRAME_RATE
	)
	if not ss then
		self.titleGroup:addListener(EVENT_KEY_PRESS | EVENT_SCROLL,
			function(event)
				local type = event:getType()
				if type == EVENT_KEY_PRESS then
					local keycode = event:getKeycode()
					log:debug("GOT key="..keycode)
					if keycode == KEY_GO then
	--					local album_id = self.albums[self.selectedAlbum].params["album_id"]
	--					local jsonAction = {
	--						actions = {
	--							go = {
	--								cmd = {"tracks"},
	--								itemParams = "params",
	--								params = {
	--									menu = "trackinfo",
	--									menu_all = 1,
	--									sort = "tracknum",
	--									album_id = album_id,
	--								},
	--							},
	--						},
	--						window = {
	--							text = self.albums[self.selectedAlbum].text,
	--							titleStyle = "album",
	--						},
	--					}
	--					appletManager:callService("browserActionRequest",self.server,jsonAction,nil)
						log:debug("Got GO event, issue play for now")
						return self:_playFunction()
					elseif keycode == KEY_UP then
						return self:_handleScroll(-1)
					elseif keycode == KEY_DOWN then
						return self:_handleScroll(1)
					end
				elseif type == EVENT_SCROLL then
					return self:_handleScroll(event)
				end
				return EVENT_UNUSED
			end
		)

		self.titleGroup:addActionListener("play",self.titleGroup,function()
				return self:_playFunction()
			end
		)
	else
		local manager = appletManager:getAppletInstance("ScreenSavers")
		manager:screensaverWindow(self.window)
	end
	self.timer = self.window:addTimer(1000, function() self:_retrieveMoreAlbums() end)

	collectgarbage()

	-- Show the window
	self.window:show(Window.transitionFadeIn)
end

function _handleScroll(self, event, keyScroll)
	local scroll = keyScroll
	if not scroll then
		scroll = event:getScroll()
	end
	if scroll>0 and self.currentDelta == 0 and self.currentPos<self.maxIndex-2 then
		self.currentDelta = self.animateRange
		self.currentPos = self.currentPos + 1
	elseif scroll<0 and self.currentDelta == self.animateRange and self.currentPos>0 then
		self.currentDelta = 0
		self.currentPos = self.currentPos - 1
	end
	if self.currentScroll>0 and scroll>0 then
		self.currentScroll = self.currentScroll + scroll
		if self.currentScroll > 4 then
			self.currentScroll = 4
		end
	elseif self.currentScroll<0 and scroll<0 then
		self.currentScroll = self.currentScroll + scroll
		if self.currentScroll < -4 then
			self.currentScroll = -4
		end
	else
		self.currentScroll = scroll
	end
	return EVENT_CONSUME
end

function _playFunction(self) 
	if self.albums and self.albums[self.selectedAlbum] then
		log:debug("Play album "..self.albums[self.selectedAlbum].text)
		local album_id = self.albums[self.selectedAlbum].params["album_id"]
		self.server:userRequest(function(chunk,err)
				if err then
					log:debug(err)
				else
					appletManager:callService("goNowPlaying")
				end
			end,
			self.player and self.player:getId(),
			{'playlistcontrol','cmd:load','album_id:'..album_id}
		)
		return EVENT_CONSUME
	else
		return EVENT_UNUSED
	end
end
function _refresh(self)
	local delta = self.currentDelta;
	local pos = self.currentPos;

	-- Scrolling to left (cover moving to right)
	if self.currentScroll < 0 then
		delta = delta - self.currentScroll
		if delta > self.animateRange then
			if not self.screensaver then
				self.currentScroll = self.currentScroll + 1
			end
			pos = pos - 1
			if pos<0 then
				collectgarbage()
				pos = 0
				self.right = false
				delta = self.animateRange
				if self.screensaver then
					self.currentScroll = 1
				end
			else
				delta = 1
			end
			self:_updateCovers(pos)
		end

	-- Scrolling to right (cover moving to left)
	elseif self.currentScroll > 0 then
		delta = delta - self.currentScroll
		if delta < 0 then
			if not self.screensaver then
				self.currentScroll = self.currentScroll -1
			end
			pos = pos + 1
			if pos > self.maxIndex-2 then
				collectgarbage()
				pos = pos -1
				self.right = true
				delta = 0
				if self.screensaver then
					self.currentScroll = -1
				end
			else
				delta = self.animateRange-1
			end
			self:_updateCovers(pos)
		end
	end

	self.currentDelta = delta
	self.currentPos = pos
	self.selectedAlbum = pos

	local text = self.titleGroup:getWidgetValue("albumtext")
	if delta>self.animateRange/2 and self.currentScroll<0 then
		if self.albums and self.maxIndex>self.currentPos and self.albums[self.currentPos+1] and self.albums[self.currentPos+1].text then
			text = self.albums[self.currentPos+1].text
			self.selectedAlbum = self.currentPos+1
		end
	elseif delta<self.animateRange/2 and self.currentScroll>0 then
		if self.albums and self.maxIndex>self.currentPos+1 and self.albums[self.currentPos+2] and self.albums[self.currentPos+2].text then
			text = self.albums[self.currentPos+2].text
			self.selectedAlbum = self.currentPos+2
		end
	elseif delta == 0 then
		if self.albums and table.getn(self.albums)>self.currentPos+1 and self.albums[self.currentPos+2] and self.albums[self.currentPos+2].text then
			text = self.albums[self.currentPos+2].text
			self.selectedAlbum = self.currentPos+2
		end
	elseif delta == self.animateRange then
		if self.albums and self.maxIndex>self.currentPos and self.albums[self.currentPos+1] and self.albums[self.currentPos+1].text then
			text = self.albums[self.currentPos+1].text
			self.selectedAlbum = self.currentPos+1
		end
	end
	if self.model == "touch" then
		local textWithoutLinebreak = string.gsub(text,"\n"," - ")
		self.titleGroup:setWidgetValue("albumtext",textWithoutLinebreak)
	else
		self.titleGroup:setWidgetValue("albumtext",text)
	end

	self.canvas:reSkin()
end

function _restoreIcon(self,icon)
	local i=1
	while self.iconPool[i] do
		i=i+1
	end
	icon:setValue(self:_loadImage("album"..self.model..".png"))
	log:debug("Restore existing icon "..i)
	self.iconPool[i] = icon
end

function _getIcon(self)
	local i=1
	while self.iconPool[i] do
		i=i+1
	end
	if i==1 then
		log:debug("Allocate new icon")
		return Icon("artwork",self:_loadImage("album"..self.model..".png"))
	else
		log:debug("Reuse existing icon "..(i-1))
		local icon = self.iconPool[(i-1)]
		self.iconPool[(i-1)] = nil
		return icon
	end
end

function _updateCovers(self,pos)
	local leftSlide = pos - 1
	local rightSlide = pos + 4
	local ARTWORK_SIZE = self:_getArtworkSize()

	if leftSlide < 1 then
		leftSlide = 1
	end
	if rightSlide > self.maxIndex then
		rightSlide = self.maxIndex
	end

	if leftSlide>1 then
		local i = leftSlide-1
		while i>0 and self.albums[i].iconArtwork do
			log:debug("Deallocating artwork for "..self.albums[i].text)
			self:_restoreIcon(self.albums[i].iconArtwork)
			self.albums[i].iconArtwork = nil
			i = i - 1
		end
	end

	if rightSlide<self.count then
		local i = rightSlide+1
		while i<=self.maxIndex and self.albums[i].iconArtwork do
			log:debug("Deallocating artwork for "..self.albums[i].text)
			self:_restoreIcon(self.albums[i].iconArtwork)
			self.albums[i].iconArtwork = nil
			i=i+1
		end
	end

	local result = true
	for i=leftSlide,rightSlide do
		if not self.albums[i].iconArtwork then
			result = false
			self.albums[i].iconArtwork=self:_getIcon()
			local iconId = self.albums[i]["icon-id"]
			if iconId then
				self.server:fetchArtwork(iconId,self.albums[i].iconArtwork,ARTWORK_SIZE)
				log:debug("Fetching artwork for "..i..":"..self.albums[i].text.." with icon-id:"..iconId)
			else
				self.server:fetchArtwork(0,self.albums[i].iconArtwork,ARTWORK_SIZE,'png')
				log:debug("Got album "..i..":"..self.albums[i].text.." without icon-id")
			end
		elseif not self.albums[i].iconArtwork:getImage() then
			result = false
		end
	end
	return result
end

function _retrieveMoreAlbums(self)
	if self.albums and self.maxIndex == tonumber(self.count) and self.maxIndex>0 then
		self.window:removeTimer(self.timer)
		return
	end 

	if self.albums and (self.maxIndex < tonumber(self.count)) and not self.loading then
		log:debug("Getting more albums")
		self:_loadAlbums(self.maxIndex)
	end
end

function _reDrawCanvas(self,screen)
	local size = self:_getArtworkSize();
	local sizeby8 = size/8
	local sizeby4 = size/4
	local sizeby2 = size/2

	local zoomx
	local zoomy
	local posx
	local posy

	if self.albums[self.currentPos] then
		-- width = 0% -> 50%
		-- height = 50% -> 75%
		-- left = 0
		-- right = 0 -> 120
		-- top = 60 -> 30
		zoomx = (self.currentDelta/2)/self.animateRange
		zoomy = ((self.currentDelta/4)/self.animateRange)+0.5
		posx = 0
		posy = sizeby4-sizeby8*(self.currentDelta/self.animateRange)
		if self.model == "controller" then
			self:_drawArtwork(screen,self.albums[self.currentPos],zoomy,zoomx,posy+60,posx)
		else
			self:_drawArtwork(screen,self.albums[self.currentPos],zoomx,zoomy,posx,posy)
		end
	end
	if self.albums[self.currentPos+1] then
		-- width = 50% -> 100%
		-- height = 75% -> 100%
		-- left = 0 -> 120
		-- right = 120 -> 360
		-- top = 30 -> 0
		zoomx = (self.currentDelta/2)/self.animateRange+(self.animateRange/2)/self.animateRange
		zoomy = ((self.currentDelta/4)/self.animateRange)+0.75
		posx = sizeby2*(self.currentDelta/self.animateRange)
		posy = sizeby8-sizeby8*(self.currentDelta/self.animateRange)
		if self.model == "controller" then
			self:_drawArtwork(screen,self.albums[self.currentPos+1],zoomy,zoomx,posy+60,posx)
		else
			self:_drawArtwork(screen,self.albums[self.currentPos+1],zoomx,zoomy,posx,posy)
		end
	end
	if self.albums[self.currentPos+2] then
		-- width = 100% -> 50%
		-- height = 100% -> 75%
		-- left = 120 -> 360
		-- right = 360 -> 480
		-- top = 0 -> 30
		zoomx = 1-(self.currentDelta/2)/self.animateRange
		zoomy = 1-((self.currentDelta/4)/self.animateRange)
		posx = sizeby2+size*(self.currentDelta/self.animateRange)
		posy = sizeby8*(self.currentDelta/self.animateRange)
		if self.model == "controller" then
			self:_drawArtwork(screen,self.albums[self.currentPos+2],zoomy,zoomx,posy+60,posx)
		else
			self:_drawArtwork(screen,self.albums[self.currentPos+2],zoomx,zoomy,posx,posy)
		end
	end
	if self.albums[self.currentPos+3] then
		-- width = 50% -> 0%
		-- height = 75% -> 50%
		-- left = 360 -> 480
		-- right = 480
		-- top = 30 -> 60
		zoomx = ((self.animateRange/2)-(self.currentDelta/2))/self.animateRange
		zoomy = 0.75-((self.currentDelta/4)/self.animateRange)
		posx = size+sizeby2+sizeby2*(self.currentDelta/self.animateRange)
		posy = sizeby8+sizeby8*(self.currentDelta/self.animateRange)
		if self.model == "controller" then
			self:_drawArtwork(screen,self.albums[self.currentPos+3],zoomy,zoomx,posy+60,posx)
		else
			self:_drawArtwork(screen,self.albums[self.currentPos+3],zoomx,zoomy,posx,posy)
		end
	end
end

function _drawArtwork(self,screen,album,zoomx,zoomy,positionx,positiony)
	if album.iconArtwork and album.iconArtwork:getImage() then
		local tmp = album.iconArtwork:getImage():zoom(zoomx,zoomy,1)
		tmp:blit(screen,positionx,positiony)
		tmp:release()
	else
		local tmp = self:_loadImage("album"..self.model..".png"):zoom(zoomx,zoomy,1)
		tmp:blit(screen,positionx,positiony)
		tmp:release()
	end
end

function _loadAlbums(self,offset)
	if offset == 0 then
		self.albums = {}
		self.maxIndex = 0
	end
	log:debug("Sending command, requesting "..offset)
	self.loading = true
	local amount = 5
	if offset>0 then
		amount = 100
	end
	self.server:userRequest(function(chunk,err)
			if err then
				log:debug(err)
			elseif chunk then
				self:_loadAlbumsSink(chunk.data,offset)
			end
			self.loading =  false
		end,
		self.player and self.player:getId(),
		{'albums',offset,amount,'menu:menu'}
	)
	log:debug("Sent command")
end

function _getArtworkSize(self)
	if self.model == "touch" then
		return 240
	elseif self.model == "radio" then
		return 160
	else
		return 120
	end		
end

function _loadAlbumsSink(self,result,offset)
	local lastIndex = 1
	self.count = result.count
	for index,item in ipairs(result.item_loop) do
		self.maxIndex = tonumber(index)+offset
		self.albums[self.maxIndex] = item
	end
end

function _loadFont(self,fontSize)
        return Font:load("fonts/FreeSans.ttf", fontSize)
end

function _loadImage(self,file)
	if not self.images[file] then
		self.images[file] = Surface:loadImage(IMG_PATH .. file)
	end
	return self.images[file]
end

function _getSkin(self,skin)
	local s = {}
	local width,height = Framework.getScreenSize()

	local textPosition
	if self.model == "touch" then
		textPosition = height-30
	elseif self.model == "radio" then
		textPosition = height-65
	else
		textPosition = height-65
	end

	s.window = {
		bgImg= Tile:fillColor(0x000000ff),
		canvas = {
			zOrder = 2,
		},
		albumtext = {
			position = LAYOUT_NONE,
			y = textPosition,
			x = 0,
			albumtext = {
				border = {10,0,10,0},
				font = self:_loadFont(20),
				align = 'center',
				w = WH_FILL,
				h = 30,
				lineHeight = 25,
				fg = { 0xcc, 0xcc, 0xcc },
			},
			zOrder = 3,
		},
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


