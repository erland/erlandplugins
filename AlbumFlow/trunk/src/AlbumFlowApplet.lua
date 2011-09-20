
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
local System        = require("jive.System")

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

function openScreensaver1(self)
	self:_initApplet(true,"config1")
end
function openScreensaver2(self)
	self:_initApplet(true,"config2")
end
function openScreensaver3(self)
	self:_initApplet(true,"config3")
end
function openScreensaver4(self)
	self:_initApplet(true,"config4")
end
function openScreensaver5(self)
	self:_initApplet(true,"config5")
end

-- display
-- the main applet function, the meta arranges for it to be called
-- by the ScreenSaversApplet.
function menu(self)
	self:_initApplet(false,"browsealbums")
end

function _initApplet(self, ss,config,forced)
	jnt:subscribe(self)

	self.config = config
	local mode = self:getSettings()[config.."mode"]
	self.style = self:getSettings()[config.."style"]
	self.speed = self:getSettings()[config.."speed"]

	local player = appletManager:callService("getCurrentPlayer")
	if self.player and player:getId() ~= self.player:getId() then
		self.window = nil
	end

	if not ss or (ss and not self.screensaver) or not self.window or self.mode ~= mode or forced then
		log:debug("Recreating screensaver window for "..config.." with mode "..mode)
		self.mode = mode
		local width,height = Framework.getScreenSize()
		if width == 480 then
			self.model = "touch"
		elseif width == 320 then
			self.model = "radio"
		elseif width == 240 then
			self.model = "controller"
		else
			self.model = "custom"
			self.width = width;
			self.height = height;
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
		self.images = {}
		self.artworkKeyMap = {}
		self.maxIndex = 0
		self.maxLoadedIndex = 0
		self.iconPool = {}
		if ss then
			self.animateRange = self:_getAnimRange(self.speed,self.style)
			self.screensaver = true
			self.currentScroll = 1
			self.currentDelta = self.animateRange
			self.currentPos = -1
		else
			self.animateRange = ANIM_RANGE
		end

		self.player = appletManager:callService("getCurrentPlayer")
		self.server = self.player:getSlimServer()

		-- Load images
		self:_loadImages(0)

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
		--					local album_id = self.images[self.selectedAlbum].params["album_id"]
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
		--							text = self.images[self.selectedAlbum].text,
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
	elseif self.mode and (self.mode == "currentartist" or self.mode == "currentgenre" or self.mode == "currentyear") then
		log:debug("Refreshing images in mode "..mode)
		self:_refreshImages(0)
	end

	self.timer = self.window:addTimer(1000, function() self:_retrieveMoreImages() end)

	collectgarbage()

	-- Show the window
	self.window:show(Window.transitionFadeIn)
end

function closeScreensaver(self)
	if self.window then
		self.window:hide();
	end
end

function _getAnimRange(self,speed,style)
	if not speed and style == "single" then
		speed = "slow"
	elseif not speed then
		speed = "medium"
	end

	if speed == "veryfast" then
		return SS_ANIM_RANGE/4
	elseif speed == "fast" then
		return SS_ANIM_RANGE/2
	elseif speed == "medium" then
		return SS_ANIM_RANGE
	elseif speed == "slow" then
		return SS_ANIM_RANGE*4
	else
		return SS_ANIM_RANGE*8
	end
end

function openScreensaverSettings(self)
	log:debug("Album Flow settings")
	local window = Window("text_list", self:string("SCREENSAVER_ALBUMFLOW_SETTINGS"), 'settingstitle')

	local menu = SimpleMenu("menu");
	for i = 1,5 do
		local name = ""
		if self:getSettings()["config"..i.."name"] then
			name = ": "..self:getSettings()["config"..i.."name"]
		elseif self:getSettings()["config"..i.."mode"] then
			name = ": "..self:getSettings()["config"..i.."mode"]
		end
		menu:addItem(
			{
				text = tostring(self:string("SCREENSAVER_ALBUMFLOW_SETTINGS_CONFIG")).." #"..i..name, 
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					self:defineSettingConfig(menuItem,"config"..i)
					return EVENT_CONSUME
				end
			})
	end	
	if System.getMachine() != "fab4" then
		menu:addItem(
			{
				text = tostring(self:string("SCREENSAVER_ALBUMFLOW_SETTINGS_BROWSE_ALBUMS")),
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					self:defineSettingStyle(menuItem, "browsealbums")
					return EVENT_CONSUME
				end
			})
	end
	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end

function defineSettingConfig(self,menuItem,mode)
	local window = Window("text_list", menuItem.text, 'settingstitle')

	window:addWidget(SimpleMenu("menu",
	{
		{
			text = self:string("SCREENSAVER_ALBUMFLOW_SETTINGS_SPEED"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingSpeed(menuItem, mode)
				return EVENT_CONSUME
			end
		},
		{
			text = self:string("SCREENSAVER_ALBUMFLOW_SETTINGS_STYLE"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingStyle(menuItem, mode)
				return EVENT_CONSUME
			end
		},
		{
			text = self:string("SCREENSAVER_ALBUMFLOW_SETTINGS_MODE"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingMode(menuItem, mode)
				return EVENT_CONSUME
			end
		},
	}))

	self:tieAndShowWindow(window)
end

function defineSettingMode(self,menuItem,mode)
	
	local player = appletManager:callService("getCurrentPlayer")
	if player then
		local server = player:getSlimServer()
		if server then
			server:userRequest(function(chunk,err)
					if err then
						log:warn(err)
					else
						if tonumber(chunk.data._can) == 1 then
							log:info("SongInfo is installed retrieving additional modes")
							server:userRequest(function(chunk,err)
									if err then
										log:warn(err)
									else
										self:fetchGalleryFavorites(menuItem.text,mode,chunk.data)
									end
								end,
								player and player:getId(),
								{'songinfomodules','type:image'}
							)
						else
							log:debug("SongInfo is NOT installed ignoring Song Info modes")
							self:fetchGalleryFavorites(menuItem.text,mode)
						end
					end
				end,
				player and player:getId(),
				{'can','songinfomodules','type:image','?'}
			)
			-- create animiation to show while we get data from the server
			local popup = Popup("waiting_popup")
			local icon  = Icon("icon_connecting")
			local label = Label("text", self:string("SCREENSAVER_ALBUMFLOW_SETTINGS_FETCHING"))
			popup:addWidget(icon)
			popup:addWidget(label)
			self:tieAndShowWindow(popup)

			self.popup = popup
		else
			log:info("No connection to server, ignoring Song Info and Picture Gallery modes")
			self:defineSettingModeSink(menuItem.text,mode)
		end
	else
		log:info("No connection to server, ignoring Song Info and Picture Gallery modes")
		self:defineSettingModeSink(menuItem.text,mode)
	end
end

function fetchGalleryFavorites(self,title,mode,songInfoItems)
	local player = appletManager:callService("getCurrentPlayer")
	local server = player:getSlimServer()
	server:userRequest(function(chunk,err)
			if err then
				log:warn(err)
			else
				if tonumber(chunk.data._can) == 1 then
					server:userRequest(function(chunk,err)
							if err then
								log:warn(err)
							else
								if tonumber(chunk.data._can) == 1 then
									log:info("Picture Galley is installed retrieving additional modes")
									server:userRequest(function(chunk,err)
											if err then
												log:warn(err)
											else
												self:defineSettingModeSink(title,mode,songInfoItems,chunk.data)
											end
										end,
										nil,
										{'gallery','favorites'}
									)
								else
									log:debug("Picture Gallery is NOT installed ignoring Picture Gallery modes")
									self:defineSettingModeSink(title,mode,songInfoItems)
								end
							end
						end,
						nil,
						{'can','gallery','favorites','?'}
					)
				else
					log:debug("Picture Gallery is NOT installed ignoring Picture Gallery modes")
					self:defineSettingModeSink(title,mode,songInfoItems)
				end
			end
		end,
		nil,
		{'can','gallery','random','?'}
	)
end

function updateMenuName(self,mode)
	local name = ""
	if self:getSettings()[mode.."name"] then
		name = ": "..self:getSettings()[mode.."name"]
	end
	appletManager:callService("addScreenSaver", 
		tostring(self:string("SCREENSAVER_ALBUMFLOW")).." #"..string.gsub(mode,"^config","")..name, 
		"AlbumFlow",
		"openScreensaver"..string.gsub(mode,"^config",""), 
		self:string("SCREENSAVER_ALBUMFLOW_SETTINGS"), 
		"openScreensaverSettings", 
		nil,
		"closeScreensaver")
end

function defineSettingModeSink(self,title,mode,songInfoItems,pictureGalleryItems)
	if self.popup then
		self.popup:hide()
	end
	
	local modesetting = self:getSettings()[mode.."mode"]

	local window = Window("text_list", title, 'settingstitle')
	local menu = SimpleMenu("menu")

	window:addWidget(menu)
	local group = RadioGroup()

	menu:addItem({
		text = self:string("SCREENSAVER_ALBUMFLOW_VIEW_ALBUM"),
		style = 'item_choice',
		check = RadioButton(
			"radio",
			group,
			function()
				self:getSettings()[mode.."mode"] = "album"
				self:getSettings()[mode.."name"] = tostring(self:string("SCREENSAVER_ALBUMFLOW_VIEW_ALBUM"))
				if self.window then
					self.window:hide()
					self.window = nil
				end
				self:storeSettings()
				self:updateMenuName(mode)
			end,
			modesetting == "album"
		),
	})
	menu:addItem({
		text = self:string("SCREENSAVER_ALBUMFLOW_VIEW_RANDOM"),
		style = 'item_choice',
		check = RadioButton(
			"radio",
			group,
			function()
				self:getSettings()[mode.."mode"] = "random"
				self:getSettings()[mode.."name"] = tostring(self:string("SCREENSAVER_ALBUMFLOW_VIEW_RANDOM"))
				if self.window then
					self.window:hide()
					self.window = nil
				end
				self:storeSettings()
				self:updateMenuName(mode)
			end,
			modesetting == "random"
		),
	})
	menu:addItem({
		text = self:string("SCREENSAVER_ALBUMFLOW_VIEW_ARTIST"),
		style = 'item_choice',
		check = RadioButton(
			"radio",
			group,
			function()
				self:getSettings()[mode.."mode"] = "byartist"
				self:getSettings()[mode.."name"] = tostring(self:string("SCREENSAVER_ALBUMFLOW_VIEW_ARTIST"))
				if self.window then
					self.window:hide()
					self.window = nil
				end
				self:storeSettings()
				self:updateMenuName(mode)
			end,
			modesetting == "byartist"
		),
	})
	menu:addItem({
		text = self:string("SCREENSAVER_ALBUMFLOW_VIEW_CURRENTPLAYLIST"),
		style = 'item_choice',
		check = RadioButton(
			"radio",
			group,
			function()
				self:getSettings()[mode.."mode"] = "currentplaylist"
				self:getSettings()[mode.."name"] = tostring(self:string("SCREENSAVER_ALBUMFLOW_VIEW_CURRENTPLAYLIST"))
				if self.window then
					self.window:hide()
					self.window = nil
				end
				self:storeSettings()
				self:updateMenuName(mode)
			end,
			modesetting == "currentplaylist"
		),
	})
	menu:addItem({
		text = self:string("SCREENSAVER_ALBUMFLOW_VIEW_CURRENTARTIST"),
		style = 'item_choice',
		check = RadioButton(
			"radio",
			group,
			function()
				self:getSettings()[mode.."mode"] = "currentartist"
				self:getSettings()[mode.."name"] = tostring(self:string("SCREENSAVER_ALBUMFLOW_VIEW_CURRENTARTIST"))
				if self.window then
					self.window:hide()
					self.window = nil
				end
				self:storeSettings()
				self:updateMenuName(mode)
			end,
			modesetting == "currentartist"
		),
	})
	menu:addItem({
		text = self:string("SCREENSAVER_ALBUMFLOW_VIEW_CURRENTGENRE"),
		style = 'item_choice',
		check = RadioButton(
			"radio",
			group,
			function()
				self:getSettings()[mode.."mode"] = "currentgenre"
				self:getSettings()[mode.."name"] = tostring(self:string("SCREENSAVER_ALBUMFLOW_VIEW_CURRENTGENRE"))
				if self.window then
					self.window:hide()
					self.window = nil
				end
				self:storeSettings()
				self:updateMenuName(mode)
			end,
			modesetting == "currentgenre"
		),
	})
	menu:addItem({
		text = self:string("SCREENSAVER_ALBUMFLOW_VIEW_CURRENTYEAR"),
		style = 'item_choice',
		check = RadioButton(
			"radio",
			group,
			function()
				self:getSettings()[mode.."mode"] = "currentyear"
				self:getSettings()[mode.."name"] = tostring(self:string("SCREENSAVER_ALBUMFLOW_VIEW_CURRENTYEAR"))
				if self.window then
					self.window:hide()
					self.window = nil
				end
				self:storeSettings()
				self:updateMenuName(mode)
			end,
			modesetting == "currentyear"
		),
	})

	if songInfoItems and songInfoItems.item_loop then
		for _,entry in pairs(songInfoItems.item_loop) do
			if entry.id == "lastfmartistimages" then
				menu:addItem({
					text = self:string("SCREENSAVER_ALBUMFLOW_VIEW_ARTISTS"),
					style = 'item_choice',
					check = RadioButton(
						"radio",
						group,
						function()
							self:getSettings()[mode.."mode"] = "artists"
							self:getSettings()[mode.."name"] = tostring(self:string("SCREENSAVER_ALBUMFLOW_VIEW_ARTISTS"))
							if self.window then
								self.window:hide()
								self.window = nil
							end
							self:storeSettings()
							self:updateMenuName(mode)
						end,
						modesetting == "artists"
					),
				})
				menu:addItem({
					text = self:string("SCREENSAVER_ALBUMFLOW_VIEW_RANDOMARTISTS"),
					style = 'item_choice',
					check = RadioButton(
						"radio",
						group,
						function()
							self:getSettings()[mode.."mode"] = "randomartists"
							self:getSettings()[mode.."name"] = tostring(self:string("SCREENSAVER_ALBUMFLOW_VIEW_RANDOMARTISTS"))
							if self.window then
								self.window:hide()
								self.window = nil
							end
							self:storeSettings()
							self:updateMenuName(mode)
						end,
						modesetting == "randomartists"
					),
				})
			end
			menu:addItem({
				text = entry.name.." "..tostring(self:string("SCREENSAVER_ALBUMFLOW_VIEW_SONGINFO")),
				style = 'item_choice',
				check = RadioButton(
					"radio",
					group,
					function()
						self:getSettings()[mode.."mode"] = "songinfo"..entry.id
						self:getSettings()[mode.."name"] = entry.name.." "..tostring(self:string("SCREENSAVER_ALBUMFLOW_VIEW_SONGINFO"))
						if self.window then
							self.window:hide()
							self.window = nil
						end
						self:storeSettings()
						self:updateMenuName(mode)
					end,
					modesetting == "songinfo"..entry.id
				),
			})
		end
	end
	if pictureGalleryItems and pictureGalleryItems.item_loop then
		for _,entry in pairs(pictureGalleryItems.item_loop) do
			menu:addItem({
				text = tostring(self:string("SCREENSAVER_ALBUMFLOW_VIEW_PICTURE_GALLERY"))..": "..entry.title,
				style = 'item_choice',
				check = RadioButton(
					"radio",
					group,
					function()
						self:getSettings()[mode.."mode"] = "picturegallery"..entry.id
						self:getSettings()[mode.."name"] = tostring(self:string("SCREENSAVER_ALBUMFLOW_VIEW_PICTURE_GALLERY"))..": "..entry.title
						if self.window then
							self.window:hide()
							self.window = nil
						end
						self:storeSettings()
						self:updateMenuName(mode)
					end,
					modesetting == "picturegallery"..entry.id
				),
			})
		end
	end
	self:tieAndShowWindow(window)
	return window
end

function defineSettingStyle(self, menuItem, mode)
	local group = RadioGroup()

	local style = self:getSettings()[mode.."style"]

	local window = Window("text_list", menuItem.text, 'settingstitle')

	window:addWidget(SimpleMenu("menu",
	{
		{
			text = self:string("SCREENSAVER_ALBUMFLOW_SETTINGS_STYLE_CIRCULAR"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[mode.."style"] = "circular"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				style == "circular"
			),
		},
		{
			text = self:string("SCREENSAVER_ALBUMFLOW_SETTINGS_STYLE_SHRINKEDSLIDE"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[mode.."style"] = "shrinkedslide"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				style == "shrinkedslide"
			),
		},
		{
			text = self:string("SCREENSAVER_ALBUMFLOW_SETTINGS_STYLE_STRETCHEDSLIDE"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[mode.."style"] = "stretchedslide"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				style == "stretchedslide"
			),
		},
		{
			text = self:string("SCREENSAVER_ALBUMFLOW_SETTINGS_STYLE_SLIDE"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[mode.."style"] = "slide"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				style == "slide"
			),
		},
		{
			text = self:string("SCREENSAVER_ALBUMFLOW_SETTINGS_STYLE_SINGLE"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[mode.."style"] = "single"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				style == "single"
			),
		},
	}))

	self:tieAndShowWindow(window)
	return window
end

function defineSettingSpeed(self, menuItem, mode)
	local group = RadioGroup()

	local speed = self:getSettings()[mode.."speed"]
	if not speed and self:getSettings()[mode.."style"] == "single" then
		speed = "slow"
	elseif not speed then
		speed = "medium"
	end

	local window = Window("text_list", menuItem.text, 'settingstitle')

	window:addWidget(SimpleMenu("menu",
	{
		{
			text = self:string("SCREENSAVER_ALBUMFLOW_SETTINGS_SPEED_VERY_FAST"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[mode.."speed"] = "veryfast"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				speed == "veryfast"
			),
		},
		{
			text = self:string("SCREENSAVER_ALBUMFLOW_SETTINGS_SPEED_FAST"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[mode.."speed"] = "fast"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				speed == "fast"
			),
		},
		{
			text = self:string("SCREENSAVER_ALBUMFLOW_SETTINGS_SPEED_MEDIUM"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[mode.."speed"] = "medium"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				speed == "medium"
			),
		},
		{
			text = self:string("SCREENSAVER_ALBUMFLOW_SETTINGS_SPEED_SLOW"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[mode.."speed"] = "slow"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				speed == "slow"
			),
		},
		{
			text = self:string("SCREENSAVER_ALBUMFLOW_SETTINGS_SPEED_VERY_SLOW"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[mode.."speed"] = "veryslow"
					if self.window then
						self.window:hide()
						self.window = nil
					end
					self:storeSettings()
				end,
				speed == "veryslow"
			),
		},
	}))

	self:tieAndShowWindow(window)
	return window
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
	if self.images and self.images[self.selectedAlbum] and self.images[self.selectedAlbum]["album_id"] then
		log:debug("Play album "..self.images[self.selectedAlbum].text)
		local album_id = self.images[self.selectedAlbum]["album_id"]
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

	if self.maxIndex > 1 then
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
						if self.mode and (string.find(self.mode,"^songinfo") or string.find(self.mode,"^picturegallery") or string.find(self.mode,"random$") or self.mode == "currentplaylist" or self.mode == "currentartist" or self.mode == "currentgenre" or self.mode == "currentyear") then
							self:_sortByRandom(self.images,self.currentPos)
						end
					end
				else
					if self.screensaver then
						delta = 1
					else
						delta = 0
					end
				end
				if self.count then
					self:_updateCoversAndData(pos)
				end
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
						if self.mode and (string.find(self.mode,"^songinfo") or string.find(self.mode,"^picturegallery") or string.find(self.mode,"random$") or self.mode == "currentplaylist" or self.mode == "currentartist" or self.mode == "currentgenre" or self.mode == "currentyear") then
							self:_sortByRandom(self.images,self.currentPos)
						end
					end
				else
					if self.screensaver then
						delta = self.animateRange-1
					else 
						delta = self.animateRange
					end
				end
				if self.count then
					self:_updateCoversAndData(pos)
				end
			elseif delta == (self.animateRange - 1 - self.currentScroll) then
				if self.count then
					self:_updateCoversAndData(pos)
				end
			end
		end

		self.currentDelta = delta
		self.currentPos = pos
		self.selectedAlbum = pos
	elseif self.maxIndex == 1 then
		self.currentDelta = self.animateRange
		self.currentPos = 0
		self:_updateCoversAndData(self.currentPos)
	end

	local text = self.titleGroup:getWidgetValue("albumtext")
	if delta>self.animateRange/2 and self.currentScroll<0 then
		if self.images and self.maxIndex>self.currentPos and self.images[self.currentPos+1] and self.images[self.currentPos+1].text then
			text = self.images[self.currentPos+1].text
			self.selectedAlbum = self.currentPos+1
		end
	elseif delta<self.animateRange/2 and self.currentScroll>0 then
		if self.images and self.maxIndex>self.currentPos+1 and self.images[self.currentPos+2] and self.images[self.currentPos+2].text then
			text = self.images[self.currentPos+2].text
			self.selectedAlbum = self.currentPos+2
		end
	elseif delta == 0 then
		if self.images and table.getn(self.images)>self.currentPos+1 and self.images[self.currentPos+2] and self.images[self.currentPos+2].text then
			text = self.images[self.currentPos+2].text
			self.selectedAlbum = self.currentPos+2
		end
	elseif delta == self.animateRange then
		if self.images and self.maxIndex>self.currentPos and self.images[self.currentPos+1] and self.images[self.currentPos+1].text then
			text = self.images[self.currentPos+1].text
			self.selectedAlbum = self.currentPos+1
		end
	end
	if self.style == "single" then
		self.titleGroup:setWidgetValue("albumtext","")
	else
		if self.model == "touch" or self.model == "custom" then
			local textWithoutLinebreak = string.gsub(text,"\n"," - ")
			self.titleGroup:setWidgetValue("albumtext",textWithoutLinebreak)
		else
			self.titleGroup:setWidgetValue("albumtext",text)
		end
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
function notify_playerCurrent(self,player)
	log:debug("Got a playerCurrent event for: "..player:getId())
	if self.player:getId() ~= player:getId() then
		self.player = player
		self.server = self.player:getSlimServer()
		if self.mode then
			self.window:hide()
			self.window = nil
		end
	end
end

function notify_playerTrackChange(self,player,nowPlaying)
	log:debug("*** Got a playerTrackChange event")
	if self.player:getId() == player:getId() and self.mode and (string.find(self.mode,"^songinfo") or self.mode == "currentplaylist" or self.mode == "currentartist" or self.mode == "currentgenre" or self.mode == "currentyear") then
		self:_refreshImages(0)
		self.timer = self.window:addTimer(1000, function() self:_retrieveMoreRefreshImages() end)
	end
end

function _updateCoversAndData(self,pos)
	local leftSlide = pos - 1
	local rightSlide = pos + 4
	local ARTWORK_SIZE = self:_getArtworkSize()

	if self.mode and (self.mode == "currentplaylist") and self.player:getPlayerStatus()["playlist_timestamp"] ~= self.lastUpdate and not self.timer then
		log:debug("Refreshing images, playlist changed")
		self:_refreshImages(0)
		self.timer = self.window:addTimer(1000, function() self:_retrieveMoreRefreshImages() end)
	end

	if leftSlide < 1 then
		leftSlide = 1
	end
	if rightSlide > self.maxIndex then
		rightSlide = self.maxIndex
	end

	if leftSlide>1 then
		local i = leftSlide-1
		while i>0 and self.images[i].iconArtwork do
			log:debug("Deallocating artwork for "..self.images[i].text)
			self:_restoreIcon(self.images[i].iconArtwork)
			self.images[i].iconArtwork = nil
			i = i - 1
		end
	end

	if rightSlide<self.count then
		local i = rightSlide+1
		while i<=self.maxIndex and self.images[i].iconArtwork do
			log:debug("Deallocating artwork for "..self.images[i].text)
			self:_restoreIcon(self.images[i].iconArtwork)
			self.images[i].iconArtwork = nil
			i=i+1
		end
	end

	local result = true
	for i=leftSlide,rightSlide do
		if not self.images[i].iconArtwork then
			result = false
			self.images[i].iconArtwork=self:_getIcon()
			local iconId = self.images[i]["icon-id"]
			if iconId then
				self.server:fetchArtwork(iconId,self.images[i].iconArtwork,ARTWORK_SIZE)
				log:debug("Fetching artwork for "..i..":"..self.images[i].text.." with icon-id:"..iconId)
			elseif self.images[i]["icon-url"] then
				self.server:fetchArtwork(self.images[i]["icon-url"],self.images[i].iconArtwork,ARTWORK_SIZE)
				log:debug("Fetching artwork for "..i..":"..self.images[i].text.." with icon-url:"..self.images[i]["icon-url"])
			elseif self.images[i]["artist_id"] then
				self:_loadArtistImageUrl(self.images[i]["artist_id"],self.images[i])
				log:debug("Got artist image for "..i..":"..self.images[i].text.." without icon-url")
			else
				self.server:fetchArtwork(0,self.images[i].iconArtwork,ARTWORK_SIZE,'png')
				log:debug("Got album "..i..":"..self.images[i].text.." without icon-id")
			end
		elseif not self.images[i].iconArtwork:getImage() then
			result = false
		end
	end
	return result
end

function _retrieveMoreImages(self)
	if self.images and self.maxLoadedIndex == self.count and self.maxLoadedIndex>0 then
		if self.timer then
			self.window:removeTimer(self.timer)
			self.timer = nil
		end
		return
	end 

	if self.images and (not self.count or (self.maxLoadedIndex < self.count)) and not self.loading then
		log:debug("Getting more images")
		self:_loadImages(self.maxLoadedIndex,self.mode)
	end
end
function _finishRefreshImages(self)
	local newKeys = {}
	for _,item in ipairs(self.refreshImages) do
		if item["icon-id"] then
			newKeys[item["icon-id"]] = 1
		else
			newKeys[item["icon-url"]] = 1
		end
	end
	local oldKeys = {}
	local newImages = {}
	for index,item in ipairs(self.images) do
		if (item["icon-id"] and not newKeys[item["icon-id"]]) or (item["icon-url"] and not newKeys[item["icon-url"]]) then
			self.currentPos = self.currentPos -1
		else
			newImages[#newImages+1] = item
			if item["icon-id"] then
				oldKeys[item["icon-id"]] = 1
			else
				oldKeys[item["icon-url"]] = 1
			end
		end
	end
	for index,item in ipairs(self.refreshImages) do
		if (item["icon-id"] and not oldKeys[item["icon-id"]]) or (item["icon-url"] and not oldKeys[item["icon-url"]]) then
			table.insert(newImages,item)
		end
	end
	self.images=newImages

	newImages=nil
	oldKeys=nil
	newKeys=nil
	if self.currentPos<0 and #self.images>0 then
		self.currentPos = 0
	end
	self.maxIndex = #self.images
	self.maxLoadedIndex = self.refreshCount
	self.count = self.refreshCount
	if self.timer then
		self.window:removeTimer(self.timer)
		self.timer = nil
	end
end

function _retrieveMoreRefreshImages(self)
	if self.refreshImages and self.refreshMaxLoadedIndex == self.refreshCount and self.refreshMaxLoadedIndex>0 then
		log:debug("All images retrieved, finishing refresh")
		self:_finishRefreshImages()
		return
	end 

	if self.refreshImages and (not self.refreshCount or (self.refreshMaxLoadedIndex < self.refreshCount)) and not self.loading then
		log:debug("Getting more refresh images")
		self:_refreshImages(self.refreshMaxLoadedIndex,self.mode)
	else
		log:debug("Retrying to retrieve more images a bit later")
	end
end

function _reDrawCanvas(self,screen)
	local size = string.match(self:_getArtworkSize(),"(%d+)x%d+") or self:_getArtworkSize()
	local sizeby8 = size/8
	local sizeby4 = size/4
	local sizeby2 = size/2

	local zoomx
	local zoomy
	local posx
	local posy

	if self.style == "single" then
		local selectedAlbum = self.selectedAlbum
		if selectedAlbum and selectedAlbum<1 then
			selectedAlbum = self.lastSelectedAlbum or 1
		end
		if selectedAlbum and self.images[selectedAlbum] then
			self.lastSelectedAlbum = selectedAlbum
			-- width = 100%
			-- height = 100%
			-- left = -360
			-- right = -120
			-- top = 0
			zoomx = 1
			zoomy = 1
			posx = 0
			posy = 0
			self:_drawArtwork(screen,self.images[selectedAlbum],zoomx,zoomy,posy,posx)
		end
	elseif self.style == "circular" then
		if self.images[self.currentPos] then
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
				self:_drawArtwork(screen,self.images[self.currentPos],zoomy,zoomx,posy+60,posx)
			else
				self:_drawArtwork(screen,self.images[self.currentPos],zoomx,zoomy,posx,posy)
			end
		end
		if self.images[self.currentPos+3] then
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
				self:_drawArtwork(screen,self.images[self.currentPos+3],zoomy,zoomx,posy+60,posx)
			else
				self:_drawArtwork(screen,self.images[self.currentPos+3],zoomx,zoomy,posx,posy)
			end
		end
		if self.images[self.currentPos+1] then
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
				self:_drawArtwork(screen,self.images[self.currentPos+1],zoomy,zoomx,posy+60,posx)
			else
				self:_drawArtwork(screen,self.images[self.currentPos+1],zoomx,zoomy,posx,posy)
			end
		end
		if self.images[self.currentPos+2] then
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
				self:_drawArtwork(screen,self.images[self.currentPos+2],zoomy,zoomx,posy+60,posx)
			else
				self:_drawArtwork(screen,self.images[self.currentPos+2],zoomx,zoomy,posx,posy)
			end
		end
	elseif self.style == "slide" then
		if self.images[self.currentPos] then
			-- width = 100%
			-- height = 100%
			-- left = -360 -> -120
			-- right = -120 -> 120
			-- top = 0
			zoomx = 1
			zoomy = 1
			posx = -size-sizeby2+size*self.currentDelta/self.animateRange
			posy = 0
			if self.model == "controller" then
				self:_drawArtwork(screen,self.images[self.currentPos],zoomy,zoomx,posy+60,posx)
			else
				self:_drawArtwork(screen,self.images[self.currentPos],zoomx,zoomy,posx,posy)
			end
		end
		if self.images[self.currentPos+1] then
			-- width = 100%
			-- height = 100%
			-- left = -120 -> 120
			-- right = 120 -> 360
			-- top = 0
			zoomx = 1
			zoomy = 1
			posx = -sizeby2+size*self.currentDelta/self.animateRange
			posy = 0
			if self.model == "controller" then
				self:_drawArtwork(screen,self.images[self.currentPos+1],zoomy,zoomx,posy+60,posx)
			else
				self:_drawArtwork(screen,self.images[self.currentPos+1],zoomx,zoomy,posx,posy)
			end
		end
		if self.images[self.currentPos+2] then
			-- width = 100%
			-- height = 100%
			-- left = 120 -> 360
			-- right = 360 -> 600
			-- top = 0
			zoomx = 1
			zoomy = 1
			posx = sizeby2+size*self.currentDelta/self.animateRange
			posy = 0
			if self.model == "controller" then
				self:_drawArtwork(screen,self.images[self.currentPos+2],zoomy,zoomx,posy+60,posx)
			else
				self:_drawArtwork(screen,self.images[self.currentPos+2],zoomx,zoomy,posx,posy)
			end
		end
		if self.images[self.currentPos+3] then
			-- width = 100%
			-- height = 100%
			-- left = 360 -> 600
			-- right = 600 -> 840
			-- top = 0
			zoomx = 1
			zoomy = 1
			posx = size+sizeby2+size*self.currentDelta/self.animateRange
			posy = 0
			if self.model == "controller" then
				self:_drawArtwork(screen,self.images[self.currentPos+3],zoomy,zoomx,posy+60,posx)
			else
				self:_drawArtwork(screen,self.images[self.currentPos+3],zoomx,zoomy,posx,posy)
			end
		end
	elseif self.style == "shrinkedslide" then
		if self.images[self.currentPos] then
			-- width = 0% -> 50%
			-- height = 100%
			-- left = 0
			-- right = 0 -> 120
			-- top = 0
			zoomx = (self.currentDelta/2)/self.animateRange
			zoomy = 1
			posx = 0
			posy = 0
			if self.model == "controller" then
				self:_drawArtwork(screen,self.images[self.currentPos],zoomy,zoomx,posy+60,posx)
			else
				self:_drawArtwork(screen,self.images[self.currentPos],zoomx,zoomy,posx,posy)
			end
		end
		if self.images[self.currentPos+3] then
			-- width = 50% -> 0%
			-- height = 100%
			-- left = 360 -> 480
			-- right = 480
			-- top = 0
			zoomx = ((self.animateRange/2)-(self.currentDelta/2))/self.animateRange
			zoomy = 1
			posx = size+sizeby2+sizeby2*(self.currentDelta/self.animateRange)
			posy = 0
			if self.model == "controller" then
				self:_drawArtwork(screen,self.images[self.currentPos+3],zoomy,zoomx,posy+60,posx)
			else
				self:_drawArtwork(screen,self.images[self.currentPos+3],zoomx,zoomy,posx,posy)
			end
		end
		if self.images[self.currentPos+1] then
			-- width = 50% -> 100%
			-- height = 100%
			-- left = 0 -> 120
			-- right = 120 -> 360
			-- top = 0
			zoomx = (self.currentDelta/2)/self.animateRange+(self.animateRange/2)/self.animateRange
			zoomy = 1
			posx = sizeby2*(self.currentDelta/self.animateRange)
			posy = 0
			if self.model == "controller" then
				self:_drawArtwork(screen,self.images[self.currentPos+1],zoomy,zoomx,posy+60,posx)
			else
				self:_drawArtwork(screen,self.images[self.currentPos+1],zoomx,zoomy,posx,posy)
			end
		end
		if self.images[self.currentPos+2] then
			-- width = 100% -> 50%
			-- height = 100%
			-- left = 120 -> 360
			-- right = 360 -> 480
			-- top = 0
			zoomx = 1-(self.currentDelta/2)/self.animateRange
			zoomy = 1
			posx = sizeby2+size*(self.currentDelta/self.animateRange)
			posy = 0
			if self.model == "controller" then
				self:_drawArtwork(screen,self.images[self.currentPos+2],zoomy,zoomx,posy+60,posx)
			else
				self:_drawArtwork(screen,self.images[self.currentPos+2],zoomx,zoomy,posx,posy)
			end
		end
	elseif self.style == "stretchedslide" then
		if self.images[self.currentPos] then
			-- width = 0% -> 0% -> 0% -> 50%
			-- height = 100%
			-- left = 0
			-- right = 0 -> 0 -> 0 -> 120
			-- top = 0
			if self.currentDelta>2*self.animateRange/3 then
				zoomx = ((3*(self.currentDelta-2*self.animateRange/3))/2)/self.animateRange
			else
				zoomx = 0
			end
			zoomy = 1
			posx = 0
			posy = 0
			if self.model == "controller" then
				self:_drawArtwork(screen,self.images[self.currentPos],zoomy,zoomx,posy+60,posx)
			else
				self:_drawArtwork(screen,self.images[self.currentPos],zoomx,zoomy,posx,posy)
			end
		end
		if self.images[self.currentPos+1] then
			-- width = 50% -> 50% -> 150% -> 100%
			-- height = 100%
			-- left = 0 -> 0 -> 0 -> 120
			-- right = 120 -> 120 -> 360 -> 360
			-- top = 0
			if self.currentDelta>2*self.animateRange/3 then
				zoomx = ((3*(self.animateRange-self.currentDelta))/2)/self.animateRange+1
			elseif self.currentDelta>self.animateRange/3 then
				zoomx = (3*(self.currentDelta-self.animateRange/3))/self.animateRange+0.5
			else
				zoomx = 0.5
			end
			zoomy = 1
			if self.currentDelta>2*self.animateRange/3 then
				posx = size*(1.5-zoomx)
			else
				posx = 0
			end
			posy = 0
			if self.model == "controller" then
				self:_drawArtwork(screen,self.images[self.currentPos+1],zoomy,zoomx,posy+60,posx)
			else
				self:_drawArtwork(screen,self.images[self.currentPos+1],zoomx,zoomy,posx,posy)
			end
		end
		if self.images[self.currentPos+2] then
			-- width = 100% -> 150% -> 50% -> 50%
			-- height = 100%
			-- left = 120 -> 120 -> 360 -> 360
			-- right = 360 -> 480 -> 480 -> 480
			-- top = 0
			if self.currentDelta>2*self.animateRange/3 then
				zoomx = 0.5
			elseif self.currentDelta>self.animateRange/3 then
				zoomx = (3*(2*self.animateRange/3-self.currentDelta))/self.animateRange+0.5
			else
				zoomx = (3*(self.currentDelta/self.animateRange)/2)+1
			end
			zoomy = 1
			if self.currentDelta>2*self.animateRange/3 then
				posx = size+sizeby2
			elseif self.currentDelta>self.animateRange/3 then
				posx = sizeby2+(1.5-zoomx)*size
			else
				posx = sizeby2
			end
			posy = 0
			if self.model == "controller" then
				self:_drawArtwork(screen,self.images[self.currentPos+2],zoomy,zoomx,posy+60,posx)
			else
				self:_drawArtwork(screen,self.images[self.currentPos+2],zoomx,zoomy,posx,posy)
			end
		end
		if self.images[self.currentPos+3] then
			-- width = 50% -> 0% -> 0% -> 0%
			-- height = 100%
			-- left = 360 -> 480 -> 480 -> 480
			-- right = 480
			-- top = 0
			if self.currentDelta>self.animateRange/3 then
				zoomx = 0
			else
				zoomx = (3*(self.animateRange/3-self.currentDelta)/2)/self.animateRange
			end
			zoomy = 1
			if self.currentDelta>self.animateRange/3 then
				posx=size+size
			else
				posx=size+sizeby2+size*(0.5-zoomx)
			end
			posy = 0
			if self.model == "controller" then
				self:_drawArtwork(screen,self.images[self.currentPos+3],zoomy,zoomx,posy+60,posx)
			else
				self:_drawArtwork(screen,self.images[self.currentPos+3],zoomx,zoomy,posx,posy)
			end
		end
	end
end

function _drawArtwork(self,screen,album,zoomx,zoomy,positionx,positiony)
	if album.iconArtwork and album.iconArtwork:getImage() then
		if zoomx == 1 and zoomy == 1 then
			album.iconArtwork:getImage():blit(screen,positionx,positiony)
		else
			local tmp = album.iconArtwork:getImage():zoom(zoomx,zoomy,1)
			tmp:blit(screen,positionx,positiony)
			tmp:release()
		end
	else
		if zoomx == 1 and zoomy == 1 then
			self:_loadImage("album"..self.model..".png"):blit(screen,positionx,positiony)
		else
			local tmp = self:_loadImage("album"..self.model..".png"):zoom(zoomx,zoomy,1)
			tmp:blit(screen,positionx,positiony)
			tmp:release()
		end
	end
end
function _loadArtistImageUrl(self,artist,image)
	self.server:userRequest(function(chunk,err)
			if err then
				log:debug(err)
			elseif chunk then
				self:_loadArtistImageUrlSink(chunk.data,image)
			end
		end,
		self.player and self.player:getId(),
		{'songinfoitems','lastfmartistimages','artist:'..artist}
	)
end

function _loadArtistImageUrlSink(self,result,image)
	local ARTWORK_SIZE = self:_getArtworkSize()
	if result.item_loop then
		for _,item in ipairs(result.item_loop) do
			if not string.find(item.url,"KeepStatsClean.jpg$") and not string.find(item.url,"keep_stats_clean.png$") then
				image["icon-url"] = item.url
				log:debug("Getting image of "..image.text.." from "..image["icon-url"]);
				self.server:fetchArtwork(image["icon-url"],image.iconArtwork,ARTWORK_SIZE)
				break
			end
		end
	end
end

function _loadImages(self,offset)
	if offset == 0 then
		self.images = {}
		self.artworkKeyMap = {}
		self.maxIndex = 0
		self.maxLoadedIndex = 0
	end
	log:debug("Sending command, requesting "..offset)
	self.loading = true
	local amount = 5
	if offset>0 then
		amount = 100
	end
	if not self.mode or self.mode == "random" or self.mode == "album" then
		log:debug("Loading album from main list")
		self.server:userRequest(function(chunk,err)
				if err then
					log:debug(err)
				elseif chunk then
					self:_loadAlbumsSink(chunk.data,offset)
				end
				self.loading =  false
			end,
			self.player and self.player:getId(),
			{'albums',offset,amount,'tags:tj'}
		)
	elseif self.mode == "byartist" then
		log:debug("Loading album from main list sort by artist")
		self.server:userRequest(function(chunk,err)
				if err then
					log:debug(err)
				elseif chunk then
					self:_loadAlbumsSink(chunk.data,offset)
				end
				self.loading =  false
			end,
			self.player and self.player:getId(),
			{'albums',offset,amount,'tags:tj','sort:artflow'}
		)
	elseif self.mode == "currentplaylist" then
		log:debug("Loading album from current playlist")
		self.server:userRequest(function(chunk,err)
				if err then
					log:debug(err)
				elseif chunk then
					self:_loadCPAlbumsSink(chunk.data,offset)
				end
				self.loading =  false
			end,
			self.player and self.player:getId(),
			{'status',offset,amount,"tags:aJKlex"}
		)
	elseif self.mode == "currentartist" then
		log:debug("Loading album for current artist")
		if self.player:getPlayerStatus()["count"] and tonumber(self.player:getPlayerStatus()["count"]) >=1 then
			local track_id = self.player:getPlayerStatus().item_loop[1].params.track_id
			self.server:userRequest(function(chunk,err)
					if err then
						log:debug(err)
					elseif chunk then
						self:_loadCurrentContextSink(chunk.data,"artist_id")
					end
					self.loading =  false
				end,
				self.player and self.player:getId(),
				{'status','-',amount,"tags:s"}
			)
		end
	elseif self.mode == "currentgenre" then
		log:debug("Loading album for current genre")
		if self.player:getPlayerStatus()["count"] and tonumber(self.player:getPlayerStatus()["count"]) >=1 then
			local track_id = self.player:getPlayerStatus().item_loop[1].params.track_id
			self.server:userRequest(function(chunk,err)
					if err then
						log:debug(err)
					elseif chunk then
						self:_loadCurrentContextSink(chunk.data,"genre_id")
					end
					self.loading =  false
				end,
				self.player and self.player:getId(),
				{'status','-',amount,"tags:p"}
			)
		end
	elseif self.mode == "currentyear" then
		log:debug("Loading album for current year")
		if self.player:getPlayerStatus()["count"] and tonumber(self.player:getPlayerStatus()["count"]) >=1 then
			local track_id = self.player:getPlayerStatus().item_loop[1].params.track_id
			self.server:userRequest(function(chunk,err)
					if err then
						log:debug(err)
					elseif chunk then
						self:_loadCurrentContextSink(chunk.data,"year")
					end
					self.loading =  false
				end,
				self.player and self.player:getId(),
				{'status','-',amount,"tags:y"}
			)
		end
	elseif self.mode == "artists" or self.mode == "randomartists" then
		log:debug("Loading artists from main list")
		self.server:userRequest(function(chunk,err)
				if err then
					log:debug(err)
				elseif chunk then
					self:_loadArtistsSink(chunk.data,offset)
				end
				self.loading =  false
			end,
			self.player and self.player:getId(),
			{'artists',offset,amount}
		)
	elseif string.find(self.mode,"^songinfo") then
		log:debug("Loading "..self.mode.." for current song")
		if self.player:getPlayerStatus()["count"] and tonumber(self.player:getPlayerStatus().count) >=1 then
			self.refreshImages = {}
			self.artworkKeyMap = {}
			self.refreshMaxLoadedIndex = 0
			self.refreshCount = 0
			local songinfomode = string.gsub(self.mode,"^songinfo","")
			local track_id = self.player:getPlayerStatus().item_loop[1].params.track_id
			log:debug("Issuing server call: songinfoitems "..songinfomode.." track:"..track_id)
			self.server:userRequest(function(chunk,err)
					if err then
						log:debug(err)
					elseif chunk then
						self:_loadSongInfoSink(chunk.data)
					end
				end,
				self.player and self.player:getId(),
				{'songinfoitems',songinfomode,"track:"..track_id}
			)
		end
	elseif string.find(self.mode,"^picturegallery") then
		local favorite = string.gsub(self.mode,"^picturegallery","")
		log:debug("Loading "..self.mode.." for favorite: "..favorite)
		self.server:userRequest(function(chunk,err)
				if err then
					log:debug(err)
				elseif chunk then
					self:_loadPictureGallerySink(chunk.data)
				end
			end,
			nil,
			{'gallery','slideshow','favid:'..favorite}
		)
	else
		log:warn("Unknown view, don't load any albums: "..self.mode)
	end
	log:debug("Sent command")
end

function _refreshImages(self,offset)
	if not offset or offset == 0 then
		self.refreshImages = {}
		self.artworkKeyMap = {}
		self.refreshMaxLoadedIndex = 0
		self.refreshCount = 0
	end
	log:debug("Sending command, requesting "..offset)
	self.loading = true
	local amount = 5
	if offset>0 then
		amount = 100
	end
	if self.mode and self.mode == "currentplaylist" then
		log:debug("Loading album from current playlist")
		self.server:userRequest(function(chunk,err)
				if err then
					log:debug(err)
				elseif chunk then
					self:_loadCPRefreshAlbumsSink(chunk.data,offset)
					self:_sortByRandom(self.refreshImages)
				end
				self.loading =  false
			end,
			self.player and self.player:getId(),
			{'status',offset,amount,"tags:aJKlex"}
		)
	elseif self.mode and self.mode == "currentartist" then
		log:debug("Loading album for current artist")
		if self.player:getPlayerStatus().count and tonumber(self.player:getPlayerStatus().count) >=1 then
			local track_id = self.player:getPlayerStatus().item_loop[1].params.track_id
			self.server:userRequest(function(chunk,err)
					if err then
						log:debug(err)
					elseif chunk then
						self:_loadCurrentContextSink(chunk.data,"artist_id")
					end
				end,
				self.player and self.player:getId(),
				{'status','-',amount,"tags:s"}
			)
		else
			self:_finishRefreshImages()
		end
	elseif self.mode and self.mode == "currentgenre" then
		log:debug("Loading album for current genre")
		if self.player:getPlayerStatus().count and tonumber(self.player:getPlayerStatus().count) >=1 then
			local track_id = self.player:getPlayerStatus().item_loop[1].params.track_id
			self.server:userRequest(function(chunk,err)
					if err then
						log:debug(err)
					elseif chunk then
						self:_loadCurrentContextSink(chunk.data,"genre_id")
					end
				end,
				self.player and self.player:getId(),
				{'status','-',amount,"tags:p"}
			)
		else
			self:_finishRefreshImages()
		end
	elseif self.mode and self.mode == "currentyear" then
		log:debug("Loading album for current year")
		if self.player:getPlayerStatus().count and tonumber(self.player:getPlayerStatus().count) >=1 then
			local track_id = self.player:getPlayerStatus().item_loop[1].params.track_id
			self.server:userRequest(function(chunk,err)
					if err then
						log:debug(err)
					elseif chunk then
						self:_loadCurrentContextSink(chunk.data,"year")
					end
				end,
				self.player and self.player:getId(),
				{'status','-',amount,"tags:y"}
			)
		else
			self:_finishRefreshImages()
		end
	elseif self.mode and string.find(self.mode,"^songinfo") then
		log:debug("Loading "..self.mode.." for current song")
		if self.player:getPlayerStatus().count and tonumber(self.player:getPlayerStatus().count) >=1 then
			local songinfomode = string.gsub(self.mode,"^songinfo","")
			local track_id = self.player:getPlayerStatus().item_loop[1].params.track_id
			self.server:userRequest(function(chunk,err)
					if err then
						log:debug(err)
					elseif chunk then
						self:_loadSongInfoSink(chunk.data)
					end
				end,
				self.player and self.player:getId(),
				{'songinfoitems',songinfomode,"track:"..track_id}
			)
		else
			self:_finishRefreshImages()
		end
	else
		log:debug("This view doesn't need refresh")
	end
	log:debug("Sent command")
end

function _getArtworkSize(self)
	if self.model == "touch" then
		if self.style == "single" then
			return "480x272"
		else
			return 240
		end			
	elseif self.model == "radio" then
		if self.style == "single" then
			return "320x216"
		else
			return 160
		end
	elseif self.model == "controller" then
		if self.style == "single" then
			return "240x296"
		else
			return 120
		end
	else 
		if self.style == "single" then
			return self.width.."x"..self.height
		else
			return self.width / 2
		end
	end		
end

function _loadAlbumsSink(self,result,offset)
	local lastIndex = 1
	self.count = tonumber(result.count)
	local index=1

	self.lastUpdate = os.time()

	local items

	for _,item in ipairs(result.albums_loop) do
		self.maxLoadedIndex = self.maxLoadedIndex + 1
		if not self.screensaver or item["artwork_track_id"] then
			self.maxIndex = #self.images + 1
			local entry = {}
			entry.text = item["title"]
			entry.album_id = item["id"]
			entry["icon-id"] = item["artwork_track_id"]
			self.images[self.maxIndex] = entry
			index = index + 1
		end
	end

	if self.mode and self.mode == "random" then
		self:_sortByRandom(self.images,self.currentPos)
	end
end

function _loadArtistsSink(self,result,offset)
	local lastIndex = 1
	self.count = tonumber(result.count)
	local index=1

	self.lastUpdate = os.time()
	for _,item in ipairs(result.artists_loop) do
		self.maxLoadedIndex = self.maxLoadedIndex + 1
		self.maxIndex = #self.images + 1
		local entry = {}
		entry.text = item["artist"]
		entry.artist_id = item["id"]
		self.images[self.maxIndex] = entry
		index = index + 1
	end

	if self.mode and self.mode == "randomartists" then
		self:_sortByRandom(self.images,self.currentPos)
	end
end

function _loadCurrentContextSink(self,result,param)
	local lastIndex = 1
	local trackCount = tonumber(result.playlist_tracks)
	if trackCount>=1 then
		local param_id = result.playlist_loop[1][param]
		if param_id then
			self.lastUpdate=result.playlist_timestamp
			self.refreshImages = {}
			self.artworkKeyMap = {}
			self.refreshMaxLoadedIndex = 0
			self.refreshCount = 0
			self.loading = true
			self.server:userRequest(function(chunk,err)
					if err then
						log:debug(err)
					elseif chunk then
						self:_loadRefreshAlbumsSink(chunk.data,param..":"..param_id)
						self:_sortByRandom(self.refreshImages,self.currentPos)
						if self.refreshCount == self.refreshMaxLoadedIndex then
							self:_finishRefreshImages()
						end
					end
					self.loading =  false
				end,
				self.player and self.player:getId(),
				{'albums',0,10,param..':'..param_id,'tags:tj'}
			)
		end
	end
end

function _loadSongInfoSink(self,result)
	local lastIndex = 1
	self.refreshCount = tonumber(result.count)
	local index=1

	self.lastUpdate = os.time()
	if result.item_loop then
		for _,item in ipairs(result.item_loop) do
			self.refreshMaxLoadedIndex = self.refreshMaxLoadedIndex + 1
			if not string.find(item.url,"KeepStatsClean.jpg$") and not string.find(item.url,"keep_stats_clean.png$") then
				local entry = {}
				log:debug("Storing image with text: "..item.text)
				entry.text = item.text
				entry["icon-url"] = item.url
				self.refreshImages[#self.refreshImages + 1] = entry
			end
			index = index + 1
		end
	end

	self:_sortByRandom(self.refreshImages,self.currentPos)
	self:_finishRefreshImages()
end

function _loadPictureGallerySink(self,result)
	local lastIndex = 1
	if result.count then
		self.count = tonumber(result.count)
	elseif result.data then
		self.count = #result.data
	else
		self.count = 0
	end
	local index=1
	self.lastUpdate = os.time()
	if result.data then
		for _,item in ipairs(result.data) do
			self.maxIndex = #self.images + 1
			local entry = {}
			log:debug("Storing image with text: "..item.caption)
			entry.text = item.caption
			local WIDTH = string.match(self:_getArtworkSize(),"(%d+)x%d+") or self:_getArtworkSize()
			local HEIGHT = string.match(self:_getArtworkSize(),"%d+x(%d+)") or self:_getArtworkSize()
			local url = string.gsub(item.image,"{resizeParams}","_"..WIDTH.."x"..HEIGHT.."_p")
			local ip,port = self.server:getIpPort()
			url = "http://"..ip..":"..port.."/"..url
			entry["icon-url"] = url
			self.images[self.maxIndex] = entry
			index = index + 1
		end
	end

	self:_sortByRandom(self.images,self.currentPos)
end

function _sortByRandom(self,array,pos)
	local i = #array-1
	while i>0 do
		local j = math.random(i+1)
		if pos and (i<=pos or i>pos+3) and (j<=pos or j>pos+3) then
			local item1 = array[i]
			local item2 = array[j]
			array[i] = item2
			array[j] = item1
		end
		i = i - 1
	end
end

function _loadCPAlbumsSink(self,result,offset)
	local lastIndex = 1
	self.count = tonumber(result.playlist_tracks)
	local index=1

	self.lastUpdate=result.playlist_timestamp

	for _,item in ipairs(result.playlist_loop) do
		self.maxLoadedIndex = self.maxLoadedIndex + 1
		if not self.screensaver or item["artwork_track_id"] or item["artwork_url"] then
			local artworkKey = nil
			if item["artwork_track_id"] then
				artworkKey = item["artwork_track_id"]
			elseif item["artwork_url"] then
				artworkKey = item["artwork_url"]
			end
			if not self.screensaver or not self.artworkKeyMap[artworkKey] then
				self.artworkKeyMap[artworkKey] = 1
				self.maxIndex = #self.images + 1
				local entry = {}
				if item.album then
					entry.text = item.album.." - "..item.artist
				elseif item.artist then
					entry.text = item.artist
				else
					entry.text = item.title
				end
				entry.album_id = item["album_id"]
				if item["artwork_track_id"] then
					entry["icon-id"] = item["artwork_track_id"]
				else
					entry["icon-url"] = item["artwork_url"]
				end
				self.images[self.maxIndex] = entry
				index = index + 1
			end
		end
	end
	self:_sortByRandom(self.images,self.currentPos)
end

function _loadRefreshAlbumsSink(self,result,params)
	local lastIndex = 1
	self.refreshCount = tonumber(result.count)
	local index=1
	for _,item in ipairs(result.albums_loop) do
		self.refreshMaxLoadedIndex = self.refreshMaxLoadedIndex + 1
		if not self.screensaver or item["artwork_track_id"] then
			local entry = {}
			entry.text = item["title"]
			entry.album_id = item["id"]
			entry["icon-id"] = item["artwork_track_id"]
			self.refreshImages[#self.refreshImages + 1] = entry
			index = index + 1
		end
	end
	if self.refreshCount>self.refreshMaxLoadedIndex then
		self.loading = true
		self.server:userRequest(function(chunk,err)
				if err then
					log:debug(err)
				elseif chunk then
					self:_loadRefreshAlbumsSink(chunk.data,params)
					self:_sortByRandom(self.refreshImages,self.currentPos)
					if self.refreshCount == self.refreshMaxLoadedIndex then
						self:_finishRefreshImages()
					end
				end
				self.loading =  false
			end,
			self.player and self.player:getId(),
			{'albums',self.refreshMaxLoadedIndex,200,params,'tags:tj'}
		)
	end
end

function _loadCPRefreshAlbumsSink(self,result,offset)
	local lastIndex = 1
	self.refreshCount = tonumber(result.playlist_tracks)
	local index=1

	self.lastUpdate=result.playlist_timestamp

	for _,item in ipairs(result.playlist_loop) do
		self.refreshMaxLoadedIndex = self.refreshMaxLoadedIndex + 1
		if not self.screensaver or item["artwork_track_id"] or item["artwork_url"] then
			local artworkKey = nil
			if item["artwork_track_id"] then
				artworkKey = item["artwork_track_id"]
			elseif item["artwork_url"] then
				artworkKey = item["artwork_url"]
			end
			if not self.screensaver or not self.artworkKeyMap[artworkKey] then
				self.artworkKeyMap[artworkKey] = 1
				local entry = {}
				if item.album then
					entry.text = item.album.." - "..item.artist
				elseif item.artist then
					entry.text = item.artist
				else
					entry.text = item.title
				end
				entry.album_id = item["album_id"]
				if item["artwork_track_id"] then
					entry["icon-id"] = item["artwork_track_id"]
				else
					entry["icon-url"] = item["artwork_url"]
				end
				self.refreshImages[#self.refreshImages + 1] = entry
				index = index + 1
			end
		end
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
	if self.model == "touch" or self.model == "custom" then
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


