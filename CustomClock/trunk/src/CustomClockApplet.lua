
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
local pairs, ipairs, tostring, tonumber, package, type = pairs, ipairs, tostring, tonumber, package, type

local oo               = require("loop.simple")
local os               = require("os")
local io               = require("io")
local math             = require("math")
local string           = require("jive.utils.string")
local table            = require("jive.utils.table")
local zip              = require("zipfilter")

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
local Timer            = require("jive.ui.Timer")

local CustomVUMeter    = require("applets.CustomClock.CustomVUMeter")
local CustomSpectrumMeter    = require("applets.CustomClock.CustomSpectrumMeter")

local SocketHttp       = require("jive.net.SocketHttp")
local RequestHttp      = require("jive.net.RequestHttp")
local json             = require("json")

local ltn12            = require("ltn12")
local lfs              = require("lfs")
local iconbar          = iconbar
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
function openScreensaver1(self)
	self:openScreensaver("config1")
end
function openScreensaver2(self)
	self:openScreensaver("config2")
end
function openScreensaver3(self)
	self:openScreensaver("config3")
end
function openScreensaver4(self)
	self:openScreensaver("config4")
end
function openScreensaver5(self)
	self:openScreensaver("config5")
end
function goNowPlaying(self, transition)
	self:openScreensaver("confignowplaying",transition)
end
function openCustomClockAlarmWindow(self)
	self:openScreensaver("configalarmactive")
end

function openScreensaver(self,mode, transition)

	log:debug("Open screensaver "..tostring(mode))
	local player = appletManager:callService("getCurrentPlayer")
	local oldMode = self.mode
	self.mode = mode
	if oldMode and self.mode != oldMode and self.window then
		self.window:hide()
		self.window = nil
	end
	if mode != "configalarmactive" then
		self.prevmode = nil
	end
	self.titleformats = {}
	self.customtitleformats = {}
	if player then
		player:unsubscribe('/slim/customclock/titleformatsupdated')
		player:unsubscribe('/slim/customclock/changedstyles')
		player:subscribe(
			'/slim/customclock/changedstyles',
			function(chunk)
				for i,entry in pairs(chunk.data[3]) do
					local updateStyle = false
					local updatedModes = {}
					for attribute,value in pairs(self:getSettings()) do
						if string.find(attribute,"style$") and self:getSettings()[attribute] == entry.name then
							log:debug("Updating "..attribute.."="..tostring(value))
							local config = string.gsub(attribute,"style$","")
							updatedModes[config]=true
							for attribute,value in pairs(self:getSettings()) do
								if string.find(attribute,"^"..config) and attribute != config.."style" then
									self:getSettings()[attribute] = nil
								end
							end
							for attribute,value in pairs(entry) do
								self:getSettings()[config..attribute] = value
							end
							if self.images then
								for attribute,value in pairs(self.images) do
									if string.find(attribute,"^"..config) then
										self.images[attribute] = nil
									end
								end
							end
							updateStyle = true
						else
							log:debug("Ignoring "..attribute.."="..tostring(value))
						end
					end
					if updateStyle then
						log:debug("Storing modified styles")
						self:storeSettings()
						if updatedModes[mode] and self.window then
							log:debug("Reopening screen saver with mode: "..mode)
							self.window:hide()
							self.window=nil
							self:openScreensaver(mode)
						end
					end
				end

			end,
			player:getId(),
			{'customclock','changedstyles'}
		)
		player:subscribe(
			'/slim/customclock/titleformatsupdated',
			function(chunk)
				self.customtitleformats = chunk.data[3]
				for attribute,value in pairs(self.customtitleformats) do
					log:debug("Title format: "..tostring(attribute).."="..tostring(value))
				end
			end,
			player:getId(),
			{'customclock','titleformatsupdated'}
		)
	end
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
		self.configItems = self:getSettings()[self.mode.."items"]
		if not self.configItems then
			self.configItems = {
				{
					itemtype = "text",
					fontsize = 20,
					posy = 50,
					text = "Not configured"
				}
			}
		end
		self.window:setSkin(self:_getClockSkin(jiveMain:getSelectedSkin()))
		self.window:reSkin()
		self.window:setShowFrameworkWidgets(false)

		self.items = {}
		local no = 1
		self.switchingNowPlaying = false
		for _,item in pairs(self.configItems) do
			if string.find(item.itemtype,"^switchingtrack") then
				self.switchingNowPlaying = true
			end
			if string.find(item.itemtype,"text$") then
				local childItems = {
					itemno = Label("item"..no,"")
				}
				self.items[no] = Group("item"..no,childItems)
				self.window:addWidget(self.items[no])
			elseif string.find(item.itemtype,"icon$") then
				local childItems = {
					itemno = Icon("item"..no)
				}
				self.items[no] = Group("item"..no,childItems)
				self.window:addWidget(self.items[no])
			elseif string.find(item.itemtype,"digitalvumeter$") then
				local childItems = {
					itemno = CustomVUMeter("item"..no,"digital",_getString(item.channels,nil))
				}
				self.items[no] = Group("item"..no,childItems)
				self.window:addWidget(self.items[no])
			elseif string.find(item.itemtype,"analogvumeter$") then
				local childItems = {
					itemno = CustomVUMeter("item"..no,"analog",_getString(item.channels,nil))
				}
				self.items[no] = Group("item"..no,childItems)
				self.window:addWidget(self.items[no])
			elseif string.find(item.itemtype,"spectrummeter$") then
				local childItems = {
					itemno = CustomSpectrumMeter("item"..no,_getString(item.channels,nil))
				}
				for attr,value in pairs(item) do
					if string.find(attr,"color$") and _getString(value,nil) then
						local color = string.gsub(attr,"color$","")
						childItems["itemno"]:setColor(color,_getColorNumber(value))
					end
					if string.find(attr,"^attr.") and _getNumber(value,nil) then
						local size = string.gsub(attr,"^attr.","")
						childItems["itemno"]:setAttr(size,tonumber(value))
					end
				end
				self.items[no] = Group("item"..no,childItems)
				self.window:addWidget(self.items[no])
			end
			no = no +1
		end
		local backgroundItems = {
			background = Icon("background")
		}
		self.backgroundImage = Group("background",backgroundItems)
		self.wallpaperImage = Icon("wallpaper")

		self.canvas = Canvas('debug_canvas',function(screen)
				self:_reDrawAnalog(screen)
			end)
	
		local canvasItems = {
			canvas = self.canvas
		}
		local canvasGroup = Group("canvas",canvasItems)
		self.window:addWidget(self.backgroundImage)
		self.window:addWidget(canvasGroup)

		if mode == "configalarmactive" then
			self.window:setAllowScreensaver(false)
			self.window:addActionListener("power",self,function()
				self.window:hide()
				self.window = nil
				appletManager:callService("alarmOff",true)
				return EVENT_UNUSED
			end)
			self.window:addActionListener("back",self,function()
				self.window:hide()
				self.window = nil
				appletManager:callService("alarmOff",false)
				return EVENT_CONSUME
			end)
			self.window:addActionListener("mute",self,function()
				appletManager:callService("alarmSnooze",true)
				self.window:hide()
				self.window = nil
				if self.prevmode then
					self:openScreensaver(self.prevmode)
				end
				return EVENT_CONSUME
			end)

			self.window:ignoreAllInputExcept(
				--these actions are not ignored
				{ 'go', 'back', 'power', 'mute', 'volume_up', 'volume_down', 'pause' }, 
				-- consumeAction is the callback issued for all "ignored" input
				function()
					log:debug('Consuming this action')
					Framework:playSound("BUMP")
					window:bumpLeft()
					return EVENT_CONSUME
				end
			)
		else
			-- Register custom actions which we want to catch in the screen saver
			local showPlaylistAction = function (self)
				self.window:playSound("WINDOWSHOW")
				local player = appletManager:callService("getCurrentPlayer")
				if player then
					local playlistSize = player and player:getPlaylistSize()
					if playlistSize == 1 then
						appletManager:callService("showTrackOne")
					else
						appletManager:callService("showPlaylist")
					end
				end
				return EVENT_CONSUME
			end

			self.window:addActionListener("go", self, showPlaylistAction)
			self.window:addActionListener("go_now_playing_or_playlist", self, showPlaylistAction)
			self.window:addActionListener("go_home", self, function(self)
				appletManager:callService("goHome")
				return EVENT_CONSUME
			end)
			self.window:addActionListener("add", self, function(self)
				appletManager:callService("showTrackOne")
				return EVENT_CONSUME
			end)
			for i=1,6 do
				local action = 'set_preset_'..tostring(i)
				self.window:addActionListener(action, self, function()
					appletManager:callService("setPresetCurrentTrack",i)
					return EVENT_CONSUME
				end)
			end
			if mode ~= "confignowplaying" then
				-- register window as a screensaver
				local manager = appletManager:getAppletInstance("ScreenSavers")
				manager:screensaverWindow(self.window,nil,{'go','go_home','go_now_playing_or_playlist','add','set_preset_1','set_preset_2','set_preset_3','set_preset_4','set_preset_5','set_preset_6'})
			end
		end

		self.window:addTimer(1000, function() self:_tick() end)
		self.offset = math.random(15)
		self.images = {}
		self.vumeterimages = {}
		self.galleryimages = {}
		self.sdtimages = {}
		self.songinfoimages = {}
		if player then
			self:_checkAndUpdateTitleFormatInfo(player)
			self:_updateCustomTitleFormatInfo(player)
		end
	end
	self.sdtWeatherChecked = false
	self.sdtMacroChecked = false
	self.lastminute = 0
	self.nowPlaying = 1
	self:_tick(1)

	if not transition then
		transition = Window.transitionFadeIn
	end
	if self.window then
		-- Show the window
		self.window:show(transition)
		for no,item in pairs(self.configItems) do
			if string.find(item.itemtype,"text$") and _getString(item.animate,"true") == "true" then
				self.items[no]:getWidget("itemno"):animate(true)
			end
		end
	end
end

function closeScreensaver(self)
	if self.window then
		self.window:hide()
		self.window = nil
	end
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

	self.settingsWindow = Window("text_list", self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS"), 'settingstitle')

	local menu = SimpleMenu("menu")
	for i = 1,5 do
		menu:addItem(
			{
				text = tostring(self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_CONFIG")).." #"..i, 
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					self:defineSettingStyle("config"..i,menuItem)
					return EVENT_CONSUME
				end
			})
	end	
	menu:addItem(
		{
			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_NOWPLAYING"), 
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSettingStyle("confignowplaying",menuItem)
				return EVENT_CONSUME
			end
		})
	if appletManager:callService("isPatchInstalled","60a51265-1938-4fd7-b703-12d3725870da") then
		menu:addItem(
			{
				text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_ALARM_ACTIVE"), 
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					self:defineSettingStyle("configalarmactive",menuItem)
					return EVENT_CONSUME
				end
			})
	end

	local luadir = _getLuaDir()
	if lfs.attributes(luadir.."share/jive/applets/CustomClock/fonts") or lfs.attributes(luadir.."share/jive/applets/CustomClock/images") then
		menu:addItem(
			{
				text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_CLEAR_CACHE"), 
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					os.execute("rm -rf \""..luadir.."share/jive/applets/CustomClock/fonts\"")
					os.execute("rm -rf \""..luadir.."share/jive/applets/CustomClock/images\"")
					self.settingsWindow:hide()
					self.settingsWindow = nil
					self:openSettings()
					return EVENT_CONSUME
				end
			})
	end

--	menu:addItem(
--		{
--			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_ALARM"), 
--			sound = "WINDOWSHOW",
--			callback = function(event, menuItem)
--				self:defineSettingStyle("configalarm",menuItem)
--				return EVENT_CONSUME
--			end
--		})
	self.settingsWindow:addWidget(menu)
	self:tieAndShowWindow(self.settingsWindow)
	return self.settingsWindow
end

function init(self)
	jnt:subscribe(self)
	self.titleformats = self.titleformats or {}
	self.customtitleformats = self.customtitleformats or {}
end

function _installCustomNowPlaying(self)
	-- We need to delay this a bit so standard Now Playing applet gets to do its stuff first
	local timer = Timer(100, function() 
			local item = jiveMain:getMenuItem('appletNowPlaying')
			if item then
				log:debug("Setting custom callback to Now Playing menu")
				item.callback = function(event, menuItem)
					self:goNowPlaying(Window.transitionPushLeft)
				end
			end
		end,
		true)
	timer:start()
end

function notify_playerCurrent(self,player)
	if self:getSettings()["confignowplayingstyle"] then
		self:_installCustomNowPlaying()
	end
end

function notify_playerTrackChange(self,player,nowPlaying)
	self:_checkAndUpdateTitleFormatInfo(player)
	self:_updateSongInfoIcons(player)
end

function _updateSongInfoIcons(self,player)
	if self.configItems then
		local width,height = Framework.getScreenSize()
		for no,item in pairs(self.configItems) do
			if item.itemtype == "songinfoicon" then
				self:_updateSongInfoIcon(self.items[no],no,_getNumber(item.width,width),_getNumber(item.height,height),item.songinfomodule,"true")
			end
		end
	end
end

function _checkAndUpdateTitleFormatInfo(self,player)
	local requestData = false
	if self.configItems then
		for _,item in pairs(self.configItems) do
			if string.find(item.itemtype,"^track") and string.find(item.itemtype,"text$") then
				if string.find(item.text,"BAND") or string.find(item.text,"COMPOSER") or string.find(item.text,"CONDUCTOR") or string.find(item.text,"ALBUMARTIST") or string.find(item.text,"TRACKARTIST") or string.find(item.text,"TRACKNUM") or string.find(item.text,"DISC") or string.find(item.text,"DISCCOUNT") then
					requestData = true
					break
				end
			elseif item.itemtype == "ratingicon" or item.itemtype == "ratingplayingicon" or item.itemtype == "ratingstoppedicon" then
				requestData = true
				break
			end
		end	
		if not requestData then
			log:debug("Track changed, updating extended title formats")
			self:_updateTitleFormatInfo(player)
		else
			log:debug("Track changed but extended title formats doesn't have to be updated")
		end
	end
end

function _updateCustomTitleFormatInfo(self,player)
	local server = player:getSlimServer()
	if server then
		server:userRequest(function(chunk,err)
				if err then
					log:warn(err)
				else
					server:userRequest(function(chunk,err)
							if err then
								log:warn(err)
							else
								self.customtitleformats = chunk.data.titleformats
								for attribute,value in pairs(self.customtitleformats) do
									log:debug("Title format: "..tostring(attribute).."="..tostring(value))
								end
							end
						end,
						player and player:getId(),
						{'customclock','titleformats'}
					)
				end
			end,
			player and player:getId(),
			{'can','customclock','titleformats','?'}
		)
	end
end

function _updateTitleFormatInfo(self,player)
	local server = player:getSlimServer()
	if server then
		server:userRequest(function(chunk,err)
				if err then
					log:warn(err)
				else
					local index = chunk.data.playlist_cur_index
					if index and chunk.data.playlist_loop[index+1] then
						self.titleformats["BAND"] = chunk.data.playlist_loop[index+1].band
						self.titleformats["COMPOSER"] = chunk.data.playlist_loop[index+1].composer
						self.titleformats["CONDUCTOR"] = chunk.data.playlist_loop[index+1].conductor
						self.titleformats["TRACKARTIST"] = chunk.data.playlist_loop[index+1].trackartist
						self.titleformats["ALBUMARTIST"] = chunk.data.playlist_loop[index+1].albumartist
						self.titleformats["RATING"] = chunk.data.playlist_loop[index+1].rating
						self.titleformats["TRACKNUM"] = chunk.data.playlist_loop[index+1].tracknum
						self.titleformats["DISC"] = chunk.data.playlist_loop[index+1].disc
						self.titleformats["DISCCOUNT"] = chunk.data.playlist_loop[index+1].disccount
					else
						self.titleformats = {}
					end
				end
			end,
			player and player:getId(),
			{'status','0','100','tags:AtiqR'}
		)
	end
end

function defineSettingStyle(self,mode,menuItem)
	
	local player = appletManager:callService("getCurrentPlayer")
	local server = player:getSlimServer()
	server:userRequest(function(chunk,err)
			if err then
				log:warn(err)
			else
				if tonumber(chunk.data._can) == 1 then
					log:info("CustomClockHelper is installed retrieving local styles")
					server:userRequest(function(chunk,err)
							if err then
								log:warn(err)
							else
								self:defineSettingStyleSink(menuItem.text,mode,chunk.data)
							end
						end,
						player and player:getId(),
						{'customclock','styles'}
					)
				else
					log:debug("CustomClockHelper isn't installed retrieving online styles")
					local http = SocketHttp(jnt, "erlandplugins.googlecode.com", 80)
					local req = RequestHttp(function(chunk, err)
							if err then
								log:warn(err)
							elseif chunk then
								chunk = json.decode(chunk)
								self:defineSettingStyleSink(menuItem.text,mode,chunk.data)
							end
						end,
						'GET', "/svn/CustomClock/trunk/clockstyles4.json")
					http:fetch(req)
				end
			end
		end,
		player and player:getId(),
		{'can','customclock','styles','?'}
	)
	
	-- create animiation to show while we get data from the server
        local popup = Popup("waiting_popup")
        local icon  = Icon("icon_connecting")
        local label = Label("text", self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_FETCHING"))
        popup:addWidget(icon)
        popup:addWidget(label)
        self:tieAndShowWindow(popup)

        self.popup = popup
end

function defineSettingStyleSink(self,title,mode,data)
	self.popup:hide()
	
	local style = self:getSettings()[mode.."style"]

	local window = Window("text_list", title, 'settingstitle')
	local menu = SimpleMenu("menu")

	window:addWidget(menu)
	local group = RadioGroup()
	if mode == "confignowplaying" then
		menu:addItem({
			text = tostring(self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_NOWPLAYING_STYLE")),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[mode.."style"] = nil
					self:storeSettings()
					log:info("Changing to standard Now Playing applet")
					appletManager:registerService("NowPlaying",'goNowPlaying')
				end,
				style == nil
			),
		})
	elseif mode == "configalarmactive" then
		menu:addItem({
			text = tostring(self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_NONE")),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:getSettings()[mode.."style"] = nil
					self:storeSettings()
					appletManager:callService("registerAlternativeAlarmWindow",nil)
				end,
				style == nil
			),
		})
	end

	local player = appletManager:callService("getCurrentPlayer")
	local server = player:getSlimServer()
	server:userRequest(function(chunk,err)
			if err then
				log:warn(err)
			else
				local galleryitems = false
				if tonumber(chunk.data._can) == 1 then
					galleryitems = true
				end
				if data.item_loop then
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
						
						if isCompilant and not galleryItems and entry.items then
							for _,item in pairs(entry.items) do
								for attr,value in pairs(item) do
									if attr == "itemtype" and value == "galleryicon" then
										isCompliant = false
									end
								end
							end
						end
						if isCompliant then
							menu:addItem({
								text = entry.name,
								style = 'item_choice',
								check = RadioButton(
									"radio",
									group,
									function()
										for attribute,value in pairs(self:getSettings()) do
											if string.find(attribute,"^"..mode) then
												self:getSettings()[attribute] = nil
											end
										end
										self:getSettings()[mode.."style"] = entry.name
										for attribute,value in pairs(entry) do
											self:getSettings()[mode..attribute] = value
										end
										if self.images then
											for attribute,value in pairs(self.images) do
												if string.find(attribute,"^"..mode) then
													self.images[attribute] = nil
												end
											end
										end
										if self.window then
											self.window:hide()
											self.window=nil
										end
										self:storeSettings()
										if mode == "confignowplaying" then
											log:info("Changing to custom Now Playing applet")
											appletManager:registerService("CustomClock",'goNowPlaying')
											self:_installCustomNowPlaying()
										elseif mode == "configalarmactive" then
											appletManager:callService("registerAlternativeAlarmWindow","openCustomClockAlarmWindow")
										end
									end,
									style == entry.name
								),
							})
						else
							log:debug("Skipping "..entry.name..", isn't supported on "..self.model)
						end
					end
				end
			end
		end,
		nil,
		{'can','gallery','random','?'}
	)

	self:tieAndShowWindow(window)
	return window
end

function _getMode(self)
	local player = appletManager:callService("getCurrentPlayer")
	local mode = "off"
	if player then
		local playerStatus = player:getPlayerStatus()
		local alarmstate = playerStatus["alarm_state"]
		if alarmstate == "active" then
			mode = "alarm"
		elseif playerStatus.mode == 'play' then
			mode = "playing"
		elseif playerStatus.mode == "stop" or playerStatus.mode == "pause" then
			mode = "stopped"
		end
	end
	if self:getSettings()[mode.."items"] then
		return mode
	else
		return "default"
	end
end

function _getLuaDir()
	local luadir = nil
	if lfs.attributes("/usr/share/jive/applets") ~= nil then
		luadir = "/usr/"
	else
		-- find the main lua directory
		for dir in package.path:gmatch("([^;]*)%?[^;]*;") do
			local mode = lfs.attributes(dir .. "share", "mode")
			if mode == "directory" then
				luadir = dir
				break
			end
		end
	end
	return luadir
end

function _retrieveFont(self,fonturl,fontfile,fontSize)
	if fonturl and string.find(fonturl,"^http") then
		if not _getString(fontfile,nil) then
			local name = string.sub(fonturl,string.find(fonturl,"/[^/]+$"))
			fontfile = string.gsub(name,"^/","")
		end

		local luadir = _getLuaDir()
		os.execute("mkdir -p \""..luadir.."share/jive/applets/CustomClock/fonts\"")
		if lfs.attributes(luadir.."share/jive/applets/CustomClock/fonts/"..fontfile) ~= nil then
			return self:_loadFont("applets/CustomClock/fonts/"..fontfile,fontSize)
		elseif lfs.attributes(luadir.."share/jive/fonts/"..fontfile) ~= nil then
			return self:_loadFont("fonts/"..fontfile,fontSize)
		else
			local req = nil
			log:debug("Getting "..fonturl)
			if not string.find(fonturl,"%.ttf$") and not string.find(fonturl,"%.TTF$")then
				local sink = ltn12.sink.chain(zip.filter(),self:_downloadFontZipFile(luadir.."share/jive/applets/CustomClock/fonts/"))
				req = RequestHttp(sink, 'GET', fonturl, {stream = true})
			else
				req = RequestHttp(self:_downloadFontFile(luadir.."share/jive/applets/CustomClock/fonts/",fontfile), 'GET', fonturl, {stream = true})
			end
			local uri = req:getURI()

			local http = SocketHttp(jnt, uri.host, uri.port, uri.host)
			http:fetch(req)
			return nil
		end
	else
		return self:_loadFont("fonts/"..fontfile,fontSize)
	end
end

function _downloadFontZipFile(self, dir)
        local fh = nil

        return function(chunk)

                if chunk == nil then
                        if fh and fh ~= 'DIR' then
                                fh:close()
                        end
                        fh = nil
			log:debug("Downloaded fonts in "..dir)
			if self.window then
				log:debug("Refreshing skin")
				self.window:setSkin(self:_getClockSkin(jiveMain:getSelectedSkin()))
				self.window:reSkin()
			end
                        return nil

                elseif type(chunk) == "table" then

                        if fh and fh ~= 'DIR' then
		                fh:close()
			end
                        fh = nil
                        local filename = dir .. chunk.filename
                        if string.sub(filename, -1) == "/" then
                                log:debug("creating directory: " .. filename)
                                lfs.mkdir(filename)
                                fh = 'DIR'
                        elseif string.find(filename,"%.ttf") or string.find(filename,"%.TTF") then
                                log:debug("Extracting font file: " .. filename)
                                fh = io.open(filename, "w")
			else
				log:debug("ignoring file: "..filename)
                        end

                else
                        if fh and fh ~= 'DIR' then
                                fh:write(chunk)
                        end
                end

                return 1
        end
end

function _downloadFontFile(self,dir,filename)
        local fh = nil

        return function(chunk)
                if chunk == nil then
                        if fh and fh ~= DIR then
                                fh:close()
                                fh = nil
				log:debug("Downloaded "..dir..filename)
				if self.window then
					log:debug("Refreshing skin")
					self.window:setSkin(self:_getClockSkin(jiveMain:getSelectedSkin()))
					self.window:reSkin()
				end
                                return nil
                        end

                else
                        if fh == nil then
	                        fh = io.open(dir .. filename, "w")
                        end

                        fh:write(chunk)
                end

                return 1
        end
end

function _loadFont(self,font,fontSize)
	log:debug("Loading font: "..font.." of size "..fontSize)
        return Font:load(font, fontSize)
end

-- Get usable wallpaper area
function _getUsableWallpaperArea(self)
	local width,height = Framework.getScreenSize()
	return width,height
end

function _extractTrackInfo(_track, _itemType)
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

function _updateRatingIcon(self,widget,id,mode)
	local player = appletManager:callService("getCurrentPlayer")
	if player then
		local playerStatus = player:getPlayerStatus()
		if not mode or (mode == 'play' and playerStatus.mode == 'play') or (mode != 'play' and playerStatus.mode != 'play') then
			local rating = self.titleformats["RATING"]
			local trackstatrating = self.customtitleformats["TRACKSTATRATINGNUMBER"]
			if trackstatrating then
				if self.images[self.mode..id.."."..trackstatrating] then
					widget:setWidgetValue("itemno",self.images[self.mode..id.."."..trackstatrating])
				else
					widget:setWidgetValue("itemno",nil)
				end
			elseif rating then
				rating = math.floor((rating + 10)/ 20)
				if self.images[self.mode..id.."."..rating] then
					widget:setWidgetValue("itemno",self.images[self.mode..id.."."..rating])
				else
					widget:setWidgetValue("itemno",nil)
				end
			else
				if self.images[self.mode..id..".0"] then
					widget:setWidgetValue("itemno",self.images[self.mode..id..".0"])
				else
					widget:setWidgetValue("itemno",nil)
				end
			end
		end
	else
		widget:setWidgetValue("itemno",nil)
	end
end
function _updateNowPlaying(itemType,widget,id,mode)
	local player = appletManager:callService("getCurrentPlayer")
	if player then
		local playerStatus = player:getPlayerStatus()
		if not mode or (mode == 'play' and playerStatus.mode == 'play') or (mode != 'play' and playerStatus.mode != 'play') then
			if playerStatus.item_loop then
				local trackInfo = _extractTrackInfo(playerStatus.item_loop[1],itemType)
				if trackInfo != "" then
					widget:setWidgetValue(id,trackInfo)
				end
			else
				widget:setWidgetValue(id,"")
			end
		else
			widget:setWidgetValue(id,"")
		end
	else
		widget:setWidgetValue(id,"")
	end
end

function _updateStaticNowPlaying(self,widget,id,format,mode)
	local player = appletManager:callService("getCurrentPlayer")
	if player then
		local playerStatus = player:getPlayerStatus()
		if not mode or (mode == 'play' and playerStatus.mode == 'play') or (mode != 'play' and playerStatus.mode != 'play') then
			if playerStatus.item_loop then
				local text = self:_replaceTitleKeywords(playerStatus.item_loop[1], format ,playerStatus.item_loop[1].track)
				text = self:_replaceCustomTitleFormats(text)
				text = self:_replaceTitleFormatKeyword(text,"BAND")
				text = self:_replaceTitleFormatKeyword(text,"CONDUCTOR")
				text = self:_replaceTitleFormatKeyword(text,"COMPOSER")
				text = self:_replaceTitleFormatKeyword(text,"TRACKARTIST")
				text = self:_replaceTitleFormatKeyword(text,"ALBUMARTIST")
				text = self:_replaceTitleFormatKeyword(text,"TRACKNUM")
				text = self:_replaceTitleFormatKeyword(text,"DISCCOUNT")
				text = self:_replaceTitleFormatKeyword(text,"DISC")

				local elapsed, duration = player:getTrackElapsed()
				
				if duration then
					text = string.gsub(text,"DURATION",_secondsToString(duration))
				else
					text = string.gsub(text,"DURATION","")
				end
				if elapsed then
					text = string.gsub(text,"ELAPSED",_secondsToString(elapsed))
					if duration then
						text = string.gsub(text,"REMAINING",_secondsToString(duration-elapsed))
					else
						text = string.gsub(text,"REMAINING","")
					end
				else
					text = string.gsub(text,"ELAPSED","")
					text = string.gsub(text,"REMAINING","")
				end

				local playlistsize = player:getPlaylistSize()
				local playlistcurrent = player:getPlaylistCurrentIndex()

				if playlistcurrent>=1 and playlistsize>=1 then
					text = string.gsub(text,"X_Y",tostring(self:string("SCREENSAVER_CUSTOMCLOCK_X_Y",playlistcurrent,playlistsize)))
					text = string.gsub(text,"X_OF_Y",tostring(self:string("SCREENSAVER_CUSTOMCLOCK_X_OF_Y",playlistcurrent,playlistsize)))
				else
					text = string.gsub(text,"X_Y","")
					text = string.gsub(text,"X_OF_Y","")
				end

				widget:setWidgetValue(id,text)
			else
				widget:setWidgetValue(id,"")
			end
		else
			widget:setWidgetValue(id,"")
		end
	else
		widget:setWidgetValue(id,"")
	end
end

function _replaceTitleFormatKeyword(self,text,keyword)
	if self.titleformats[keyword] then
		text = string.gsub(text,keyword,self.titleformats[keyword])
	else
		text = string.gsub(text,keyword,"")
	end
	return text
end

function _replaceCustomTitleFormats(self,text)
	if self.customtitleformats then
		for attr,value in pairs(self.customtitleformats) do
			text = string.gsub(text,attr,value)
		end
	end
	return text
end

function _replaceTitleKeywords(self,_track, text, replaceNonTracks)
	if _track.track then
		text = string.gsub(text,"ARTIST",_track.artist)
		text = string.gsub(text,"ALBUM",_track.album)
		text = string.gsub(text,"TITLE",_track.track)
	elseif replaceNoneTracks then
		text = _track.text
	else
		text = ""
	end
	return text
end

function _getCoverSize(self,size)
	local result = _getNumber(size,nil)
	if result then
		return result
	else
		if self.model == "controller" then
			return 240
		elseif self.model == "radio" then
			return 240
		elseif self.model == "touch" then
			return 272
		end
	end
end

function _updateSDTText(self,widget,format,period)
	local player = appletManager:callService("getCurrentPlayer")
	period = _getString(period,nil) or 0 
	local server = player:getSlimServer()
	if not self.sdtMacroChecked then
		server:userRequest(function(chunk,err)
				if err then
					log:warn(err)
				else
					self.sdtMacroChecked = true
					if tonumber(chunk.data._can) == 1 then
						self.sdtMacroInstalled = true
						self:_updateSDTText(widget,format,period)
					else	
						self.sdtMacroInstalled = false
					end
					
				end
			end,
			nil,
			{'can','sdtMacroString', '?'}
		)
	elseif self.sdtMacroInstalled then
		server:userRequest(
			function(chunk, err)
				if err then
					log:warn(err)
				elseif chunk then
					local text = chunk.data.macroString
					-- Lets allow time keywords to be specified as %$M instead of %M
					text = string.gsub(text,"%%%$","%%")
					text = self:_getLocalizedDateInfo(nil,_getString(text,""))
					widget:setWidgetValue("itemno",text)
					log:debug("Result from macroString: "..text)
				end
			end,
			player and player:getId(),
			{ 'sdtMacroString', 'format:'..format, 'period:'..tostring(period)}
		)
	end
end

function _updateSDTSportText(self,widget,id,sport,status,prefix)
	local player = appletManager:callService("getCurrentPlayer")
	period = _getString(period,nil) or 0 
	local server = player:getSlimServer()
	if not self.sdtWeatherChecked then
		server:userRequest(function(chunk,err)
				if err then
					log:warn(err)
				else
					self.sdtWeatherChecked = true
					if tonumber(chunk.data._can) == 1 then
						self.sdtWeatherInstalled = true
						self:_updateSDTSportText(widget,id,sport,status,prefix)
					else	
						self.sdtWeatherInstalled = false
					end
					
				end
			end,
			nil,
			{'can','SuperDateTime', '?'}
		)
	elseif self.sdtWeatherInstalled and sport then
		server:userRequest(
			function(chunk, err)
				if err then
					log:warn(err)
				elseif chunk then
					local sportsData = chunk.data.sportsData
					if sportsData[string.upper(sport)] then
						server:userRequest(
							function(chunk, err)
								if err then
									log:warn(err)
								elseif chunk.data then
									local games = {}
									local no = 1
									for _,value in pairs(sportsData[string.upper(sport)]) do
										for _,enabledTeam in pairs(chunk.data["_p2"]) do
											if tostring(enabledTeam) == "1" or value.awayTeam == enabledTeam or value.homeTeam == enabledTeam then
												if not status or 
													(string.find(status,"final$") and _getNumber(games[no].homeScore,nil) and games[no].gameTime == "F") or 
													(string.find(status,"^active") and _getNumber(games[no].homeScore,nil) and games[no].gameTime ~= "F") then
													games[no] = value
													no = no + 1
												end
												break
											end
										end
									end
									self.configItems[id].results = games
									if #games>0 then
										self.configItems[id].currentResult = 1
										widget:setWidgetValue("itemno",self:_getGamesString(self.configItems[id].results,1,_getNumber(self.configItems[id].noofscores,1),prefix))
									else
										widget:setWidgetValue("itemno","")
										self.configItems[id].currentResult = nil
									end
								end
							end,
							player and player:getId(),
							{ 'pref', 'plugin.superdatetime:'..sport,'?'}
						)
					end
				end
			end,
			player and player:getId(),
			{ 'SuperDateTime', 'sports'}
		)
	end
end

function _getGamesString(self,results,first,length,prefix)
	local result = ""
	for i=first,(first+length-1) do
		if #results>=i then
			if i>first then
				result = result.."\n"
			end
			if _getNumber(results[i].homeScore,nil) then
				result = result..tostring(results[i].homeTeam).." ".._getNumber(results[i].homeScore,0).." @ "..tostring(results[i].awayTeam).." ".._getNumber(results[i].awayScore,0).." ("..tostring(results[i].gameTime)..")"
			else
				result = result.._getString(prefix,"")..tostring(results[i].homeTeam).." @ "..tostring(results[i].awayTeam).." ("..tostring(results[i].gameTime)..")"
			end
		end
	end
	return result
end

function _updateSDTIcon(self,widget,id,width,height,period,dynamic)
	local player = appletManager:callService("getCurrentPlayer")
	period = _getString(period,nil) or 0 
	local server = player:getSlimServer()
	if not self.sdtWeatherChecked then
		server:userRequest(function(chunk,err)
				if err then
					log:warn(err)
				else
					self.sdtWeatherChecked = true
					if tonumber(chunk.data._can) == 1 then
						self.sdtWeatherInstalled = true
						self:_updateSDTIcon(widget,id,width,height,period,dynamic)
					else	
						self.sdtWeatherInstalled = false
					end
					
				end
			end,
			nil,
			{'can','SuperDateTime', '?'}
		)
	elseif self.sdtWeatherInstalled then
		server:userRequest(function(chunk,err)
				if err then
					log:warn(err)
				else
					local url = nil
					if chunk.data.wetData[tostring(period)] and chunk.data.wetData[tostring(period)].forecastIconURLSmall then
						url = chunk.data.wetData[tostring(period)].forecastIconURLSmall
					elseif chunk.data.wetData[tostring(period)] and chunk.data.wetData[tostring(period)].forecastIcon then
						url = "/plugins/SuperDateTime/html/images/"..chunk.data.wetData[tostring(period)].forecastIcon..".png"
					end
					if url then
						local ip,port = server:getIpPort()
						url = "http://"..ip..":"..port..url
						if width and height then
							url = string.gsub(url,".png$","_"..width.."x"..height.."_p.png")
							url = string.gsub(url,".jpg$","_"..width.."x"..height.."_p.jpg")
							url = string.gsub(url,".jpeg$","_"..width.."x"..height.."_p.jpeg")
						end
						self.sdtimages[self.mode.."item"..id] = id
						self:_retrieveImage(url,self.mode.."item"..id,dynamic)
					end
				end
			end,
			player and player:getId(),
			{'SuperDateTime','weather'}
		)
	end
end

function _updateSongInfoIcon(self,widget,id,width,height,module,dynamic)
	local player = appletManager:callService("getCurrentPlayer")
	local server = player:getSlimServer()
	if not self.sdtSongInfoChecked then
		server:userRequest(function(chunk,err)
				if err then
					log:warn(err)
				else
					self.sdtSongInfoChecked = true
					if tonumber(chunk.data._can) == 1 then
						self.sdtSongInfoInstalled = true
						self:_updateSongInfoIcon(widget,id,width,height,module,dynamic)
					else	
						self.sdtSongInfoInstalled = false
					end
					
				end
			end,
			nil,
			{'can','songinfoitems', '?'}
		)
	elseif self.sdtSongInfoInstalled and _getString(module,nil) then
		server:userRequest(function(chunk,err)
				if err then
					log:warn(err)
				else
					if chunk.data.item_loop then
						self.configItems[id].urls = {}
						for no,item in ipairs(chunk.data.item_loop) do
							self.configItems[id].urls[no] = item.url
						end
						local imageNo = math.random(1,#self.configItems[id].urls)
						self.songinfoimages[self.mode.."item"..id] = id
						self:_retrieveImage(self.configItems[id].urls[imageNo],self.mode.."item"..id,dynamic,_getNumber(width,nil),_getNumber(height,nil))
					else
						self.configItems[id].urls = nil
					end
				end
			end,
			player and player:getId(),
			{'songinfoitems','0','100','module:'..module}
		)
	end
end

function _updateGalleryImage(self,widget,id,width,height,favorite)
	local player = appletManager:callService("getCurrentPlayer")
	local server = player:getSlimServer()
	if server then
		server:userRequest(function(chunk,err)
				if err then
					log:warn(err)
				else
					local cmd = {'gallery','random'}
					if _getNumber(favorite,nil) then
						cmd = {'gallery','random','favid:'.._getNumber(favorite,nil)}
					end
					server:userRequest(function(chunk,err)
							if err then
								log:warn(err)
							else
								local maxwidth,maxheight = self:_getUsableWallpaperArea()
								local url = string.gsub(chunk.data.image,"{resizeParams}","_".._getNumber(width,maxwidth).."x".._getNumber(height,maxheight).."_p")
								local ip,port = server:getIpPort()
								url = "http://"..ip..":"..port.."/"..url
								self.galleryimages[self.mode.."item"..id] = id
								self:_retrieveImage(url,self.mode.."item"..id,true)
							end
						end,
						nil,
						cmd
					)
				end
			end,
			nil,
			{'can','gallery','random','?'}
		)
	end
end

function _updateAlbumCover(self,widget,id,size,mode,index)
	local player = appletManager:callService("getCurrentPlayer")
	if player then
		local playerStatus = player:getPlayerStatus()
		if not mode or (mode == 'play' and playerStatus.mode == 'play') or (mode != 'play' and playerStatus.mode != 'play') then
			if playerStatus.item_loop then
				local iconId = nil
				if playerStatus.item_loop[index] then
					iconId = playerStatus.item_loop[index]["icon-id"] or playerStatus.item_loop[index]["icon"]
				end
				local server = player:getSlimServer()
				if _getNumber(size,nil) then
					if iconId then
						log:debug("Get fresh artwork for icon-id "..tostring(iconId))
						if widget then
							server:fetchArtwork(iconId,widget:getWidget(id),size)
						else
							server:fetchArtwork(iconId,Icon("artwork"),size)
						end
					elseif playerStatus.item_loop[index] and playerStatus.item_loop[index]["params"]["track_id"] then
						log:debug("Get fresh artwork for track_id "..tostring(playerStatus.item_loop[index]["params"]["track_id"]))
						if widget then
							server:fetchArtwork(playerStatus.item_loop[index]["params"]["track_id"],widget:getWidget(id),self:_getCoverSize(size),'png')
						else
							server:fetchArtwork(playerStatus.item_loop[index]["params"]["track_id"],Icon("artwork"),size)
						end
					elseif widget then
						widget:setWidgetValue(nil)
					end
				else
					if iconId then
						if widget then
							server:fetchArtwork(iconId,widget:getWidget(id),self:_getCoverSize(size))
						else
							server:fetchArtwork(iconId,Icon("artwork"),self:_getCoverSize(size))
						end
					elseif playerStatus.item_loop[index] and playerStatus.item_loop[index]["params"]["track_id"] then
						if widget then
							server:fetchArtwork(playerStatus.item_loop[index]["params"]["track_id"],widget:getWidget(id),self:_getCoverSize(size),'png')
						else
							server:fetchArtwork(playerStatus.item_loop[index]["params"]["track_id"],Icon("artwork"),self:_getCoverSize(size),'png')
						end
					elseif widget then
						widget:setWidgetValue(nil)
					end
				end
			elseif widget then
				widget:setWidgetValue(id,nil)
			end
		elseif widget then
			widget:setWidgetValue(id,nil)
		end
	elseif widget then
		widget:setWidgetValue(id,nil)
	end
end

-- Update the time and if needed also the wallpaper
function _tick(self,forcedUpdate)
	log:debug("Updating time")

	local second = os.date("%S")
	if second % 3 == 0 then
		if self.nowPlaying>=3 then
			self.nowPlaying = 1
		else
			self.nowPlaying = self.nowPlaying + 1
		end
	end

	local player = appletManager:callService("getCurrentPlayer")
	if self.mode == "configalarmactive" and player then
		local alarmstate = player:getPlayerStatus()["alarm_state"]
		if not alarmstate or alarmstate != "active" then
			self:closeScreensaver()
		end
	end

	local minute = os.date("%M")

	local no = 1
	for _,item in pairs(self.configItems) do
		if item.itemtype == "timetext" then
			self.items[no]:setWidgetValue("itemno",self:_getLocalizedDateInfo(nil,_getString(item.text,"%H:%M")))
		elseif item.itemtype == "text" then
			self.items[no]:setWidgetValue("itemno",item.text)
		elseif item.itemtype == "alarmtimetext" then
			if player then
				local alarmtime = player:getPlayerStatus()["alarm_next"]
				local alarmstate = player:getPlayerStatus()["alarm_state"]

				if alarmstate=="set" then
					self.items[no]:setWidgetValue("itemno",self:_getLocalizedDateInfo(alarmtime,_getString(item.text,"%H:%M")))
				else
					self.items[no]:setWidgetValue("itemno","")
				end
			else
				self.items[no]:setWidgetValue("itemno","")
			end
		elseif item.itemtype == "wirelessicon" then
			local wirelessMode = string.gsub(iconbar.iconWireless:getStyle(),"^button_wireless_","")
			log:debug("Wireless status is "..tostring(wirelessMode))
			if self.images[self.mode.."item"..no.."."..wirelessMode] then
				log:debug("Wireless status is "..wirelessMode)
				self.items[no]:setWidgetValue("itemno",self.images[self.mode.."item"..no.."."..wirelessMode])
			elseif wirelessMode != "NONE" then
				self.items[no]:setWidgetValue("itemno",self.images[self.mode.."item"..no])
			else
				self.items[no]:setWidgetValue("itemno",nil)
			end
		elseif item.itemtype == "batteryicon" then
			local batteryMode = string.gsub(iconbar.iconBattery:getStyle(),"^button_battery_","")
			log:debug("Battery status is "..tostring(batteryMode))
			if self.images[self.mode.."item"..no.."."..batteryMode] then
				self.items[no]:setWidgetValue("itemno",self.images[self.mode.."item"..no.."."..batteryMode])
			elseif batteryMode != "NONE" then
				self.items[no]:setWidgetValue("itemno",self.images[self.mode.."item"..no])
			else
				self.items[no]:setWidgetValue("itemno",nil)
			end
		elseif item.itemtype == "alarmicon" then
			if player then
				local alarmstate = player:getPlayerStatus()["alarm_state"]

				log:debug("Alarm state is "..tostring(alarmstate))
				if alarmstate=="active" or alarmstate=="snooze" or alarmstate=="set" then
					if self.images[self.mode.."item"..no.."."..alarmstate] then
						self.items[no]:setWidgetValue("itemno",self.images[self.mode.."item"..no.."."..alarmstate])
					else
						self.items[no]:setWidgetValue("itemno",self.images[self.mode.."item"..no])
					end
				else
					self.items[no]:setWidgetValue("itemno",nil)
				end
			else
				self.items[no]:setWidgetValue("itemno",nil)
			end
		elseif item.itemtype == "shufflestatusicon" then
			if player then
				local status = tonumber(player:getPlayerStatus()["playlist shuffle"])
				if status == 1 then
					status = "songs"
				elseif status == 2 then
					status = "albums"
				else
					status = nil
				end
				log:debug("Shuffle state is "..tostring(status))
				if status and self.images[self.mode.."item"..no.."."..status] then
					self.items[no]:setWidgetValue("itemno",self.images[self.mode.."item"..no.."."..status])
				else
					self.items[no]:setWidgetValue("itemno",nil)
				end
			else
				self.items[no]:setWidgetValue("itemno",nil)
			end
		elseif item.itemtype == "repeatstatusicon" then
			if player then
				local status = tonumber(player:getPlayerStatus()["playlist repeat"])
				if status == 1 then
					status = "song"
				elseif status == 2 then
					status = "playlist"
				else
					status = nil
				end
				log:debug("Repeat state is "..tostring(status))
				if status and self.images[self.mode.."item"..no.."."..status] then
					self.items[no]:setWidgetValue("itemno",self.images[self.mode.."item"..no.."."..status])
				else
					self.items[no]:setWidgetValue("itemno",nil)
				end
			else
				self.items[no]:setWidgetValue("itemno",nil)
			end
		elseif item.itemtype == "playstatusicon" then
			if player then
				local mode = player:getPlayerStatus()["mode"]
				log:debug("Play state is "..tostring(mode))
				if mode and self.images[self.mode.."item"..no.."."..mode] then
					self.items[no]:setWidgetValue("itemno",self.images[self.mode.."item"..no.."."..mode])
				else
					self.items[no]:setWidgetValue("itemno",nil)
				end
			else
				self.items[no]:setWidgetValue("itemno",nil)
			end
		elseif item.itemtype == "timeicon" then
			if _getString(item.text,nil) ~= nil then
				local number = _getNumber(os.date(item.text),0)
				if self.images[self.mode.."item"..no] then
					local w,h = self.images[self.mode.."item"..no]:getSize()
					if self.items[no]:getWidget("itemno"):getImage() == nil then
						self.items[no]:setWidgetValue("itemno",Surface:newRGB(item.width,h))
					end
					if self.images[self.mode.."item"..no..".background"] ~= nil then
						self.images[self.mode.."item"..no..".background"]:blit(self.items[no]:getWidget("itemno"):getImage(),0,0)
					end
					if number*item.width<w then
						self.images[self.mode.."item"..no]:blitClip(number*item.width,0,item.width,h,self.items[no]:getWidget("itemno"):getImage(),0,0)
					end
				end
			end
		elseif item.itemtype == "ratingicon" then
			self:_updateRatingIcon(self.items[no],"item"..no,nil)
		elseif item.itemtype == "ratingplayingicon" then
			self:_updateRatingIcon(self.items[no],"item"..no,"play")
		elseif item.itemtype == "ratingstoppedicon" then
			self:_updateRatingIcon(self.items[no],"item"..no,"stop")
		elseif item.itemtype == "switchingtrackplayingtext" then
			_updateNowPlaying(self.nowPlaying,self.items[no],"itemno","stop")
		elseif item.itemtype == "switchingtrackstoppedtext" then
			_updateNowPlaying(self.nowPlaying,self.items[no],"itemno","play")
		elseif item.itemtype == "switchingtracktext" then
			_updateNowPlaying(self.nowPlaying,self.items[no],"itemno")
		elseif item.itemtype == "tracktext" then
			self:_updateStaticNowPlaying(self.items[no],"itemno",item.text)
		elseif item.itemtype == "trackplayingtext" then
			self:_updateStaticNowPlaying(self.items[no],"itemno",item.text,"play")
		elseif item.itemtype == "trackstoppedtext" then
			self:_updateStaticNowPlaying(self.items[no],"itemno",item.text,"stop")
		elseif item.itemtype == "sdttext" then
			if forcedUpdate or self.lastminute!=minute then
				self:_updateSDTText(self.items[no],item.sdtformat,item.period)
			end
		elseif item.itemtype == "sdtsporttext" then
			if forcedUpdate or self.lastminute!=minute then
				self:_updateSDTSportText(self.items[no],no,_getString(item.sport,nil),_getString(item.gamestatus,nil),_getString(item.text,""))
			elseif second % _getNumber(item.interval,3) == 0 then
				if item.results and #item.results>0 then
					if #item.results > (item.currentResult+_getNumber(item.noofscores,1)-1) then
						item.currentResult = item.currentResult + _getNumber(item.noofscores,1)
					else
						item.currentResult = 1
					end
					self.items[no]:setWidgetValue("itemno",self:_getGamesString(item.results,item.currentResult,_getNumber(item.noofscores,1),item.text))
				else
					self.items[no]:setWidgetValue("itemno","")
				end
			end
		elseif item.itemtype == "covericon" then
			self:_updateAlbumCover(self.items[no],"itemno",item.size,nil,1)
			-- Pre-load next artwork
			self:_updateAlbumCover(nil,"itemno",item.size,nil,2)
		elseif item.itemtype == "coverplayingicon" then
			self:_updateAlbumCover(self.items[no],"itemno",item.size,"play",1)
			-- Pre-load next artwork
			self:_updateAlbumCover(nil,"itemno",item.size,"play",2)
		elseif item.itemtype == "coverstoppedicon" then
			self:_updateAlbumCover(self.items[no],"itemno",item.size,"stop",1)
			-- Pre-load next artwork
			self:_updateAlbumCover(nil,"itemno",item.size,"stop",2)
		elseif item.itemtype == "covernexticon" then
			self:_updateAlbumCover(self.items[no],"itemno",item.size,nil,2)
		elseif item.itemtype == "covernextplayingicon" then
			self:_updateAlbumCover(self.items[no],"itemno",item.size,"play",2)
		elseif item.itemtype == "covernextstoppedicon" then
			self:_updateAlbumCover(self.items[no],"itemno",item.size,"stop",2)
		elseif item.itemtype == "galleryicon" then
			if forcedUpdate or self.lastminute!=minute then
				self:_updateGalleryImage(self.items[no],no,item.width,item.height,item.favorite)
			end
		elseif item.itemtype == "sdticon" then
			if forcedUpdate or self.lastminute!=minute then
				self:_updateSDTIcon(self.items[no],no,_getNumber(item.width,nil),_getNumber(item.height,nil),item.period,_getString(item.dynamic,"false"))
			end
		elseif item.itemtype == "songinfoicon" then
			if forcedUpdate or (minute % 3 == 0 and self.lastminute!=minute) then
				local width,height = Framework.getScreenSize()
				self:_updateSongInfoIcon(self.items[no],no,_getNumber(item.width,width),_getNumber(item.height,height),item.songinfomodule,"true")
			elseif second % _getNumber(item.interval,10) == 0 and item.urls and #item.urls>0 then
				local width,height = Framework.getScreenSize()
				local imageNo = math.random(1,#item.urls)
				self.songinfoimages[self.mode.."item"..no] = no
				self:_retrieveImage(item.urls[imageNo],self.mode.."item"..no,"true",_getNumber(item.width,width),_getNumber(item.height,height))
			end
		end
		no = no +1
	end

	if forcedUpdate or ((minute + self.offset) % 15 == 0 and self.lastminute!=minute) then
		self:_imageUpdate()
	end
	self.lastminute = minute

	local hasImages = false
	for key,image in pairs(self.images) do
		if string.find(key,"image$") then
			hasImages = true
			break
		end
	end	
	if hasImages then
		self.canvas:reSkin()
		self.canvas:reDraw()
	end
end

function _getLocalizedDateInfo(self,time,text)
	local weekday = os.date("%w",time)
	local month = os.date("%m",time)
	if text and string.find(text,"%%A") then
		text = string.gsub(text,"%%A",tostring(self:string("WEEKDAY_"..weekday)))
	end
	if text and string.find(text,"%%a") then
		text = string.gsub(text,"%%a",tostring(self:string("WEEKDAY_SHORT_"..weekday)))
	end
	if text and string.find(text,"%%B") then
		text = string.gsub(text,"%%B",tostring(self:string("MONTH_"..month)))
	end
	if text and string.find(text,"%%b") then
		text = string.gsub(text,"%%b",tostring(self:string("MONTH_SHORT_"..month)))
	end
	if text and string.find(text,"%%H1") then
		local hour = os.date("%H",time)
		text = string.gsub(text,"%%H1",tostring(tonumber(hour)))
	end
	if text and string.find(text,"%%I1") then
		local hour = os.date("%I",time)
		text = string.gsub(text,"%%I1",tostring(tonumber(hour)))
	end
	if text and string.find(text,"%%m1") then
		local month = os.date("%m",time)
		text = string.gsub(text,"%%m1",tostring(tonumber(month)))
	end
	if text and string.find(text,"%%d1") then
		local month = os.date("%d",time)
		text = string.gsub(text,"%%d1",tostring(tonumber(month)))
	end
	text = os.date(text,time)
	return text
end

function _secondsToString(seconds)
        local hrs = math.floor(seconds / 3600)
        local min = math.floor((seconds / 60) - (hrs*60))
        local sec = math.floor( seconds - (hrs*3600) - (min*60) )

        if hrs > 0 then
                return string.format("%d:%02d:%02d", hrs, min, sec)
        else
                return string.format("%d:%02d", min, sec)
        end
end

function _blitImage(self,screen,id,posx,posy,angle)
	log:debug("Updating "..tostring(id).." at "..tostring(angle)..", "..tostring(x)..", "..tostring(y))
	local tmp = self.images[id]
	if angle and angle!=0 then
		tmp = tmp:rotozoom(-angle, 1, 5)
	end
	local facew, faceh = tmp:getSize()
	x = math.floor(posx - (facew/2))
	y = math.floor(posy - (faceh/2))
	tmp:blit(screen, x, y)
	if angle and angle!=0 then
		tmp:release()
	end
end

function _reDrawAnalog(self,screen) 
	local m = os.date("%M")
	local h = os.date("%I")
	local s = os.date("%S")
	local ah = nil
	local am = nil
	
	local player = appletManager:callService("getCurrentPlayer")
	if player then
		local alarmstate = player:getPlayerStatus()["alarm_state"]
		if alarmstate and alarmstate == "set" then
			local alarmtime = player:getPlayerStatus()["alarm_next"]
			ah = os.date("%I",alarmtime)
			am = os.date("%M",alarmtime)
		end
	end

	local width,height = self:_getUsableWallpaperArea()
	
	local defaultposx = (width/2)
	local defaultposy = (height/2)

	for no,item in pairs(self.configItems) do
		if item.itemtype == "clockimage" then
			local posx = _getNumber(_getNumber(item.posx,self:getSettings()[self.mode.."clockposx"]),defaultposx)
			local posy = _getNumber(_getNumber(item.posy,self:getSettings()[self.mode.."clockposy"]),defaultposy)
			if self.images[self.mode.."item"..no]  then
				self:_blitImage(screen,
					self.mode.."item"..no,
					posx,
					posy)
			end
			if self.images[self.mode.."item"..no..".alarmhour"] and ah and am then
				self:_blitImage(screen,
					self.mode.."item"..no..".alarmhour",
					posx,
					posy,
					(360 / 12) * (ah + (am/60)))
			end
			if self.images[self.mode.."item"..no..".alarmminute"] and am then
				self:_blitImage(screen,
					self.mode.."item"..no..".alarmminute",
					posx,
					posy,
					(360 / 60) * am)
			end
			if self.images[self.mode.."item"..no..".hour"]  then
				self:_blitImage(screen,
					self.mode.."item"..no..".hour",
					posx,
					posy,
					(360 / 12) * (h + (m/60)))
			end
			if self.images[self.mode.."item"..no..".minute"]  then
				self:_blitImage(screen,
					self.mode.."item"..no..".hour",
					posx,
					posy,
					(360 / 60) * m)
			end
			if self.images[self.mode.."item"..no..".second"]  then
				self:_blitImage(screen,
					self.mode.."item"..no..".hour",
					posx,
					posy,
					(360 / 60) * s)
			end
		end
	end

	for no,item in pairs(self.configItems) do
		if item.itemtype == "hourimage" then
			local posx = _getNumber(_getNumber(item.posx,self:getSettings()[self.mode.."clockposx"]),defaultposx)
			local posy = _getNumber(_getNumber(item.posy,self:getSettings()[self.mode.."clockposy"]),defaultposy)
			if self.images[self.mode.."item"..no]  then
				self:_blitImage(screen,
					self.mode.."item"..no,
					posx,
					posy,
					(360 / 12) * (h + (m/60)))
			end
		end
	end

	for no,item in pairs(self.configItems) do
		if item.itemtype == "minuteimage" then
			local posx = _getNumber(_getNumber(item.posx,self:getSettings()[self.mode.."clockposx"]),defaultposx)
			local posy = _getNumber(_getNumber(item.posy,self:getSettings()[self.mode.."clockposy"]),defaultposy)
			if self.images[self.mode.."item"..no]  then
				self:_blitImage(screen,
					self.mode.."item"..no,
					posx,
					posy,
					(360 / 60) * m)
			end
		end
	end

	for no,item in pairs(self.configItems) do
		if item.itemtype == "secondimage" then
			local posx = _getNumber(_getNumber(item.posx,self:getSettings()[self.mode.."clockposx"]),defaultposx)
			local posy = _getNumber(_getNumber(item.posy,self:getSettings()[self.mode.."clockposy"]),defaultposy)
			if self.images[self.mode.."item"..no]  then
				self:_blitImage(screen,
					self.mode.."item"..no,
					posx,
					posy,
					(360 / 60) * s)
			end
		end
	end

	local imageType = "stopped"
	if player then
		local playerStatus = player:getPlayerStatus()
		if playerStatus.mode == 'play' then
			imageType = "playing"
		end
	end
	local duration = 0
	local elapsed = 1
	if player then
		elapsed,duration = player:getTrackElapsed()
	end
	if not duration or duration == 0 then
		duration = 1
		elapsed = 0
	end
	for no,item in pairs(self.configItems) do
		if string.find(item.itemtype,"^rotatingimage") then
			local id = ""
			local rotating = 1
			if _getString(item["url."..imageType.."rotating"],nil) then
				id = "."..imageType.."rotating"
			elseif _getString(item["url."..imageType],nil) then
				id = "."..imageType
				rotating = 0
			end

			if self.images[self.mode.."item"..no..id] then
				local speed = _getNumber(item.speed,10)
				local angle = (360 / 60) * s * speed * rotating

				self:_blitImage(screen,
					self.mode.."item"..no..id,
					_getNumber(item.posx,defaultposx),
					_getNumber(item.posy,defaultposy),
					angle)
			end
		elseif string.find(item.itemtype,"^elapsedimage") then
			local id = ""
			if _getString(item["url."..imageType.."rotating"],nil) then
				id = "."..imageType.."rotating"
			elseif _getString(item["url.rotating"],nil) then
				id = ".rotating"
			end

			if self.images[self.mode.."item"..no..id] then
				local range = (_getNumber(item.finalangle,360)-_getNumber(item.initialangle,0))
				if range<0 then
					range = -range
				end
				local angle = _getNumber(item.initialangle,0) + (range / duration) * elapsed

				self:_blitImage(screen,
					self.mode.."item"..no..id,
					_getNumber(item.posx,defaultposx),
					_getNumber(item.posy,defaultposy),
					angle)
			end

			id = ""
			if _getString(item["url."..imageType.."clippingx"],nil) then
				id = "."..imageType.."clippingx"
			elseif _getString(item["url.clippingx"],nil) then
				id = ".clippingx"
			end

			if self.images[self.mode.."item"..no..id] then
				local tmp = self.images[self.mode.."item"..no..id]
				local facew, faceh = tmp:getSize()
				x = _getNumber(item.posx,0)
				y = _getNumber(item.posy,0)
				local clipwidth = math.floor(_getNumber(item.width,width) * elapsed / duration)
				log:debug("Updating clipping elapsed image at "..x..", "..y.." with width "..clipwidth)
				tmp:blitClip(0, 0,clipwidth,faceh,screen, x,y)
			end

			id = ""
			if _getString(item["url."..imageType.."slidingx"],nil) then
				id = "."..imageType.."slidingx"
			elseif _getString(item["url.slidingx"],nil) then
				id = ".slidingx"
			end

			if self.images[self.mode.."item"..no..id] then
				local tmp = self.images[self.mode.."item"..no..id]
				local facew, faceh = tmp:getSize()
				local posx = math.floor(_getNumber(item.width,width-facew) * elapsed / duration)
				posx = _getNumber(item.posx,0) + posx
				x = _getNumber(posx,0)
				y = _getNumber(item.posy,0)
				log:debug("Updating sliding elapsed image at "..x..", "..y)
				tmp:blit(screen, x, y)
			end
		end
	end
end

function _retrieveImage(self,url,imageType,dynamic,width,height)
	local imagehost = ""
	local imageport = tonumber("80")
	local imagepath = ""

	local start,stop,value = string.find(url,"http://([^/]+)")
	if value and value != "" then
		imagehost = value
		local start, stop,value = string.find(imagehost,":(.+)$")
		if value and value != "" then
			imageport = tonumber(value)
			imagehost = string.gsub(imagehost,":"..imageport,"")
		end
	end
	start,stop,value = string.find(url,"http://[^/]+(.+)")
	if value and value != "" then
		imagepath = value
	end

	if imagepath != "" and imagehost != "" then
 		if string.find(url, "^http://192%.168") or
			string.find(url, "^http://172%.16%.") or
			string.find(url, "^http://10%.") then
			-- Use direct url
		else
                        imagehost = jnt:getSNHostname()
			imagepath = '/public/imageproxy?u=' .. string.urlEncode(url)
			if width then
				imagepath = imagepath.."&w="..width
			end				
			if height then
				imagepath = imagepath.."&h="..height
			end
			if width or height then
				imagepath = imagepath.."&m=p"
			end				
                end
		log:debug("Getting image for "..imageType.." from "..imagehost.." and "..imageport.." and "..imagepath)
		local luadir = _getLuaDir()
		local cacheName = string.urlEncode(url)
		if width then
			cacheName = cacheName.."-w"..width
		end
		if height then
			cacheName = cacheName.."-h"..height
		end
		if _getString(dynamic,"false") == "false" and lfs.attributes(luadir.."share/jive/applets/CustomClock/images/"..cacheName) then
			log:debug("Image found in cache")
			local fh = io.open(luadir.."share/jive/applets/CustomClock/images/"..cacheName, "rb")
			local chunk = fh:read("*all")
			fh:close()
			self:_retrieveImageData(url,imageType,chunk)
		else
			local http = SocketHttp(jnt, imagehost, imageport)
			local req = RequestHttp(function(chunk, err)
					if chunk then
						if _getString(dynamic,"false") == "false" then
							os.execute("mkdir -p \""..luadir.."share/jive/applets/CustomClock/images\"")
					                local fh = io.open(luadir.."share/jive/applets/CustomClock/images/"..string.urlEncode(url), "w")
					                fh:write(chunk)
							fh:close()
						end
						self:_retrieveImageData(url,imageType,chunk)
					elseif err then
						log:warn("error loading picture " .. url)
					end
				end,
				'GET', imagepath)
			http:fetch(req)
		end
	else
		local luadir = _getLuaDir()
		if lfs.attributes(luadir.."share/jive/"..url) ~= nil then
			local fh = io.open(luadir.."share/jive/"..url, "rb")
			local chunk = fh:read("*all")
			fh:close()
			self:_retrieveImageData(url,imageType,chunk)
		else 
			log:warn("Unable to parse url "..url..", got: "..imagehost..", "..imagepath)
		end
	end
end

function _retrieveImageData(self,url,imageType,chunk)
	local width,height = self:_getUsableWallpaperArea()
	local image = Surface:loadImageData(chunk, #chunk)
	if string.find(imageType,"background$") then
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
		self.wallpaperImage:setValue(image)
	end
	log:debug("Storing downloaded image for "..imageType)
	self.images[imageType] = image
	if self.vumeterimages[imageType] ~= nil then
		local id = "background"
		if string.find(imageType,"%.") then
			id = string.gsub(imageType,"^.*%.","")
		end
		log:debug("Setting visualizer image: "..id)
		self.items[self.vumeterimages[imageType]]:getWidget("itemno"):setImage(id,image)
	elseif self.galleryimages[imageType] ~= nil then
		self.items[self.galleryimages[imageType]]:getWidget("itemno"):setValue(image)
	elseif self.sdtimages[imageType] ~= nil then
		self.items[self.sdtimages[imageType]]:getWidget("itemno"):setValue(image)
	elseif self.songinfoimages[imageType] ~= nil then
		self.items[self.songinfoimages[imageType]]:getWidget("itemno"):setValue(image)
	end
	log:debug("image ready")
end

function _imageUpdate(self)
	log:debug("Initiating image update (offset="..self.offset.. " minutes)")

	local no = 1
	for _,item in pairs(self.configItems) do
		if string.find(item.itemtype,"icon$") then
			for attr,value in pairs(item) do
				if attr == "url" then
					if _getString(item.url,nil) then
						self:_retrieveImage(item.url,self.mode.."item"..no,item.dynamic)
					else
						self.images[self.mode.."item"..no] = nil
					end
				elseif string.find(attr,"^url%.") then
					local id = string.gsub(attr,"^url%.","")
					if _getString(value,nil) then
						self:_retrieveImage(value,self.mode.."item"..no.."."..id,item.dynamic)
					else
						self.images[self.mode.."item"..no.."."..id] = nil
					end
				end
			end
		elseif string.find(item.itemtype,"image$") then
			for attr,value in pairs(item) do
				if attr == "url" then
					if _getString(item.url,nil) then
						self:_retrieveImage(item.url,self.mode.."item"..no,item.dynamic)
					else
						self.images[self.mode.."item"..no] = nil
					end
				elseif string.find(attr,"^url%.") then
					local id = string.gsub(attr,"^url%.","")
					if _getString(value,nil) then
						self:_retrieveImage(value,self.mode.."item"..no.."."..id,item.dynamic)
					else
						self.images[self.mode.."item"..no.."."..id] = nil
					end
				end
			end
		elseif string.find(item.itemtype,"vumeter$") then
			for attr,value in pairs(item) do
				if attr == "url" then
					self.vumeterimages[self.mode.."item"..no] = no
					if _getString(item.url,nil) then
						self:_retrieveImage(item.url,self.mode.."item"..no,item.dynamic)
					else
						self.images[self.mode.."item"..no] = nil
					end
				elseif string.find(attr,"^url%.") then
					local id = string.gsub(attr,"^url%.","")
					self.vumeterimages[self.mode.."item"..no.."."..id] = no
					if _getString(value,nil) then
						self:_retrieveImage(value,self.mode.."item"..no.."."..id,item.dynamic)
					else
						self.images[self.mode.."item"..no.."."..id] = nil
					end
				end
			end
		end
		no = no +1
	end
	if _getString(self:getSettings()[self.mode.."background"],nil) then
		self:_retrieveImage(self:getSettings()[self.mode.."background"],self.mode.."background",self:getSettings()[self.mode.."backgrounddynamic"])
	else
		self.images[self.mode.."background"] = nil
	end
end

function _getColor(color)
	if color == "white" then
		return {0xff, 0xff, 0xff}
	elseif color =="lightgray" then
		return {0xcc, 0xcc, 0xcc}
	elseif color =="gray" then
		return {0x88, 0x88, 0x88}
	elseif color =="darkgray" then
		return {0x44, 0x44, 0x44}
	elseif color =="black" then
		return {0x00, 0x00, 0x00}
	elseif color == "lightred" then
		return {0xff, 0x00, 0x00}
	elseif color == "red" then
		return {0xcc, 0x00, 0x00}
	elseif color == "darkred" then
		return {0x88, 0x00, 0x00} 
	elseif color == "lightyellow" then
		return {0xff, 0xff, 0x00}
	elseif color == "yellow" then
		return {0xcc, 0xcc, 0x00}
	elseif color == "darkyellow" then
		return {0x88, 0x88, 0x00} 
	elseif color == "lightblue" then
		return {0x00, 0x00, 0xff}
	elseif color == "blue" then
		return {0x00, 0x00, 0xcc}
	elseif color == "darkblue" then
		return {0x00, 0x00, 0x88} 
	elseif color == "lightgreen" then
		return {0x00, 0xff, 0x00}
	elseif color == "green" then
		return {0x00, 0xcc, 0x00}
	elseif color == "darkgreen" then
		return {0x00, 0x88, 0x00} 
	elseif color and string.find(color,"^0x") then
		color = string.gsub(color,"^0x","")
		local number = tonumber(color,16)
		return {number/(256*256*256*256),number/(256*256*256),number/(256*256)}
	else
		return {0xcc, 0xcc, 0xcc}
	end
end

function _getColorNumber(color)
	if color == "white" then
		return 0xffffffff
	elseif color =="lightgray" then
		return 0xccccccff
	elseif color =="gray" then
		return 0x888888ff
	elseif color =="darkgray" then
		return 0x444444ff
	elseif color =="black" then
		return 0x000000ff
	elseif color == "lightred" then
		return 0xff0000ff
	elseif color == "red" then
		return 0xcc0000ff
	elseif color == "darkred" then
		return 0x880000ff 
	elseif color == "lightyellow" then
		return 0xffff00ff
	elseif color == "yellow" then
		return 0xcccc00ff
	elseif color == "darkyellow" then
		return 0x888800ff 
	elseif color == "lightblue" then
		return 0x0000ffff
	elseif color == "blue" then
		return 0x0000ccff
	elseif color == "darkblue" then
		return 0x000088ff 
	elseif color == "lightgreen" then
		return 0x00ff00ff
	elseif color == "green" then
		return 0x00cc00ff
	elseif color == "darkgreen" then
		return 0x008800ff 
	elseif string.find(color,"^0x") then
		color = string.gsub(color,"^0x","")
		return tonumber(color,16)
	else
		return 0xccccccff
	end
end

function _getNumber(value,default)
	value = tonumber(value)
	if value then
		return value
	else
		return default
	end
end

function _getString(value,default)
	if value and value != "" then
		return value
	else
		return default
	end
end

function _getClockSkin(self,skin)
	local s = {}
	local width,height = Framework.getScreenSize()

	s.window = {
		canvas = {
			zOrder = 3,
		},
		background = {
			position = LAYOUT_NONE,
			x = 0,
			y = 0,
			background = {
				w = WH_FILL,
				align = 'center',
			},
			zOrder = 1,
		},			
	}
	
	local no = 1
	for _,item in pairs(self.configItems) do
		if string.find(item.itemtype,"text$") then
			s.window["item"..no] = {
				position = LAYOUT_NONE,
				y = _getNumber(item.posy,0),
				x = _getNumber(item.posx,0),
				zOrder = _getNumber(item.order,4),
			}
			local font = nil
			if _getString(item.fonturl,nil) then
				font = self:_retrieveFont(item.fonturl,item.fontfile,_getNumber(item.fontsize,20))
			end
			if not font then
				font = self:_loadFont(self:getSettings()["font"],_getNumber(item.fontsize,20))
			end
			s.window["item"..no]["item"..no] = {
					border = {_getNumber(item.margin,10),0,_getNumber(item.margin,10),0},
					font = font,
					align = _getString(item.align,"center"),
					w = _getNumber(item.width,WH_FILL),
					h = _getNumber(item.height,_getNumber(item.fontsize,20)),
					fg = _getColor(item.color),
				}
			if _getNumber(item.lineheight,nil) then
				s.window["item"..no]["item"..no].lineHeight = _getNumber(item.lineheight,nil)
			end
		elseif string.find(item.itemtype,"^cover") then
			local defaultSize = WH_FILL
			if _getNumber(item.posx,nil) then
				defaultSize = self:_getCoverSize(item.size)
			end
			s.window["item"..no] = {
				position = LAYOUT_NONE,
				x = _getNumber(item.posx,0),
				y = _getNumber(item.posy,0),
				zOrder = _getNumber(item.order,2),
			}
			s.window["item"..no]["item"..no] = {
					align = _getString(item.align,"center"),
					w = _getNumber(item.size,defaultSize)
				}
		elseif string.find(item.itemtype,"icon$") then
			s.window["item"..no] = {
				position = LAYOUT_NONE,
				x = _getNumber(item.posx,0),
				y = _getNumber(item.posy,0),
				zOrder = _getNumber(item.order,4),
			}
			s.window["item"..no]["item"..no] = {
					align = 'center',
				}
			if _getNumber(item.framewidth,nil) ~= nil then
				s.window["item"..no]["item"..no].frameWidth = _getNumber(item.framewidth,nil)
			end
			if _getNumber(item.framerate,nil) ~= nil then
				s.window["item"..no]["item"..no].frameRate = _getNumber(item.framerate,nil)
			end
		elseif string.find(item.itemtype,"vumeter$") or string.find(item.itemtype,"spectrummeter$") then
			s.window["item"..no] = {
				position = LAYOUT_NONE,
				x = _getNumber(item.posx,0),
				y = _getNumber(item.posy,0),
				w = _getNumber(item.width,width),
				h = _getNumber(item.height,height),
				zOrder = _getNumber(item.order,4),
			}
			s.window["item"..no]["item"..no] = {
					align = 'center',
					x = _getNumber(item.posx,0),
					y = _getNumber(item.posy,0),
					w = _getNumber(item.width,width),
					h = _getNumber(item.height,height),
				}
		end
		no = no +1
	end

	if self:getSettings()[self.mode.."backgroundtype"] == "black" then
		s.window.bgImg= Tile:fillColor(0x000000ff)
		s.window.background.bgImg= Tile:fillColor(0x000000ff)
	elseif self:getSettings()[self.mode.."backgroundtype"] == "white" then
		s.window.bgImg= Tile:fillColor(0xffffffff)
		s.window.background.bgImg= Tile:fillColor(0x000000ff)
	elseif self:getSettings()[self.mode.."backgroundtype"] == "lightgray" then
		s.window.bgImg= Tile:fillColor(0xccccccff)
		s.window.background.bgImg= Tile:fillColor(0x000000ff)
	elseif self:getSettings()[self.mode.."backgroundtype"] == "darkgray" then
		s.window.bgImg= Tile:fillColor(0x444444ff)
		s.window.background.bgImg= Tile:fillColor(0x000000ff)
	elseif self:getSettings()[self.mode.."backgroundtype"] == "gray" then
		s.window.bgImg= Tile:fillColor(0x888888ff)
		s.window.background.bgImg= Tile:fillColor(0x000000ff)
	end
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


