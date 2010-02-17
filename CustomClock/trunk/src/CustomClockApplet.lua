
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
local string           = require("jive.utils.string")
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

--local Networking       = require("jive.net.Networking")

local SocketHttp       = require("jive.net.SocketHttp")
local RequestHttp      = require("jive.net.RequestHttp")
local json             = require("json")

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
function openScreensaver(self,mode)

	log:debug("Open screensaver "..tostring(mode))
	local player = appletManager:callService("getCurrentPlayer")
	local oldMode = self.mode
	self.mode = mode
	if oldMode and self.mode != oldMode and self.window then
		self.window:hide()
		self.window = nil
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

		-- register window as a screensaver, unless we are explicitly not in that mode
		local manager = appletManager:getAppletInstance("ScreenSavers")
		manager:screensaverWindow(self.window)
		self.window:addTimer(1000, function() self:_tick() end)
		self.offset = math.random(15)
		self.images = {}
		if player then
			self:_checkAndUpdateTitleFormatInfo(player)
			self:_updateCustomTitleFormatInfo(player)
		end
	end
	self.lastminute = 0
	self.nowPlaying = 1
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
--	menu:addItem(
--		{
--			text = self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS_ALARM"), 
--			sound = "WINDOWSHOW",
--			callback = function(event, menuItem)
--				self:defineSettingStyle("configalarm",menuItem)
--				return EVENT_CONSUME
--			end
--		})
	window:addWidget(menu)
	self:tieAndShowWindow(window)
	return window
end

function init(self)
	jnt:subscribe(self)
	self.titleformats = self.titleformats or {}
	self.customtitleformats = self.customtitleformats or {}
end

function notify_playerTrackChange(self,player,nowPlaying)
	self:_checkAndUpdateTitleFormatInfo(player)
end

function _checkAndUpdateTitleFormatInfo(self,player)
	local requestData = false
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

function _updateCustomTitleFormatInfo(self,player)
	local server = player:getSlimServer()
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

function _updateTitleFormatInfo(self,player)
	local server = player:getSlimServer()
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
					log:info("CustomClockHelper isn't installed retrieving online styles")
					local http = SocketHttp(jnt, "erlandplugins.googlecode.com", 80)
					local req = RequestHttp(function(chunk, err)
							if err then
								log:warn(err)
							elseif chunk then
								chunk = json.decode(chunk)
								self:defineSettingStyleSink(menuItem.text,mode,chunk.data)
							end
						end,
						'GET', "/svn/CustomClock/trunk/clockstyles2.json")
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

function _loadFont(self,fontSize)
        return Font:load(self:getSettings()["font"], fontSize)
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
end
function _updateNowPlaying(itemType,widget,id,mode)
	local player = appletManager:callService("getCurrentPlayer")
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
end

function _updateStaticNowPlaying(self,widget,id,format,mode)
	local player = appletManager:callService("getCurrentPlayer")
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

function _updateAlbumCover(self,widget,id,size,mode,index)
	local player = appletManager:callService("getCurrentPlayer")
	local playerStatus = player:getPlayerStatus()
	if not mode or (mode == 'play' and playerStatus.mode == 'play') or (mode != 'play' and playerStatus.mode != 'play') then
		if playerStatus.item_loop then
			local iconId = nil
			if playerStatus.item_loop[index] then
				iconId = playerStatus.item_loop[index]["icon-id"]
			end
			if iconId then
				local server = player:getSlimServer()
				if _getNumber(size,nil) then
					server:fetchArtwork(iconId,widget:getWidget(id),size)
				else
					if self.model == "controller" then
						server:fetchArtwork(iconId,widget:getWidget(id),self:_getCoverSize(size))
					elseif self.model == "radio" then
						server:fetchArtwork(iconId,widget:getWidget(id),self:_getCoverSize(size))
					elseif self.model == "touch" then
						server:fetchArtwork(iconId,widget:getWidget(id),self:_getCoverSize(size))
					end
				end
			else 
				widget:setWidgetValue(id,nil)
			end
		else
			widget:setWidgetValue(id,nil)
		end
	else
		widget:setWidgetValue(id,nil)
	end
end

-- Update the time and if needed also the wallpaper
function _tick(self,forcedBackgroundUpdate)
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
	local no = 1
	for _,item in pairs(self.configItems) do
		if item.itemtype == "timetext" then
			self.items[no]:setWidgetValue("itemno",os.date(_getString(item.text,"%H:%M")))
		elseif item.itemtype == "text" then
			self.items[no]:setWidgetValue("itemno",item.text)
		elseif item.itemtype == "alarmnexttext" then
			local alarmtime = player:getPlayerStatus()["alarm_next"]
			local alarmstate = player:getPlayerStatus()["alarm_state"]

			if alarmstate=="set" then
				self.items[no]:setWidgetValue("itemno",os.date(item.text,alarmtime))
			else
				self.items[no]:setWidgetValue("itemno","")
			end
		elseif item.itemtype == "wirelessicon" then
			local wirelessMode = string.gsub(iconbar.iconBattery:getStyle(),"^button_wireless_","")
			log:debug("Wireless status is "..tostring(wirelessMode))
			if images[self.mode.."item"..no.."."..wirelessMode] then
				log:debug("Battery status is "..batteryMode)
				self.items[no]:setWidgetValue("itemno",images[self.mode.."item"..no.."."..wirelessMode])
			elseif batteryMode != "NONE" then
				self.items[no]:setWidgetValue("itemno",images[self.mode.."item"..no])
			else
				self.items[no]:setWidgetValue("itemno",nil)
			end
		elseif item.itemtype == "batteryicon" then
			local batteryMode = string.gsub(iconbar.iconBattery:getStyle(),"^button_battery_","")
			log:debug("Battery status is "..tostring(batteryMode))
			if images[self.mode.."item"..no.."."..batteryMode] then
				self.items[no]:setWidgetValue("itemno",images[self.mode.."item"..no.."."..batteryMode])
			elseif batteryMode != "NONE" then
				self.items[no]:setWidgetValue("itemno",images[self.mode.."item"..no])
			else
				self.items[no]:setWidgetValue("itemno",nil)
			end
		elseif item.itemtype == "alarmicon" then
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
		elseif item.itemtype == "shufflestatusicon" then
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
		elseif item.itemtype == "repeatstatusicon" then
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
		elseif item.itemtype == "playstatusicon" then
			local mode = player:getPlayerStatus()["mode"]
			log:debug("Play state is "..tostring(mode))
			if mode and self.images[self.mode.."item"..no.."."..mode] then
				self.items[no]:setWidgetValue("itemno",self.images[self.mode.."item"..no.."."..mode])
			else
				self.items[no]:setWidgetValue("itemno",nil)
			end
		elseif item.itemtype == "ratingicon" then
			self:_updateRatingIcon(self.items[no],"item"..no,nil)
		elseif item.itemtype == "ratingplayingicon" then
			self:_updateRatingIcon(self.items[no],"item"..no,"play")
		elseif item.itemtype == "ratingstoppedicon" then
			self:_updateRatingIcon(self.items[no],"item"..no,"stop")
		elseif item.itemtype == "switchingtrackplayingtext" then
			_updateNowPlaying(player,self.nowPlaying,self.items[no],"itemno","stop")
		elseif item.itemtype == "switchingtrackstoppedtext" then
			_updateNowPlaying(player,self.nowPlaying,self.items[no],"itemno","play")
		elseif item.itemtype == "switchingtracktext" then
			_updateNowPlaying(player,self.nowPlaying,self.items[no],"itemno")
		elseif item.itemtype == "tracktext" then
			self:_updateStaticNowPlaying(self.items[no],"itemno",item.text)
		elseif item.itemtype == "trackplayingtext" then
			self:_updateStaticNowPlaying(self.items[no],"itemno",item.text,"play")
		elseif item.itemtype == "trackstoppedtext" then
			self:_updateStaticNowPlaying(self.items[no],"itemno",item.text,"stop")
		elseif item.itemtype == "covericon" then
			self:_updateAlbumCover(self.items[no],"itemno",item.size,nil,1)
		elseif item.itemtype == "coverplayingicon" then
			self:_updateAlbumCover(self.items[no],"itemno",item.size,"play",1)
		elseif item.itemtype == "coverstoppedicon" then
			self:_updateAlbumCover(self.items[no],"itemno",item.size,"stop",1)
		elseif item.itemtype == "covernexticon" then
			self:_updateAlbumCover(self.items[no],"itemno",item.size,nil,2)
		elseif item.itemtype == "covernextplayingicon" then
			self:_updateAlbumCover(self.items[no],"itemno",item.size,"play",2)
		elseif item.itemtype == "covernextstoppedicon" then
			self:_updateAlbumCover(self.items[no],"itemno",item.size,"stop",2)
		end
		no = no +1
	end

	local minute = os.date("%M")
	if forcedBackgroundUpdate or ((minute + self.offset) % 15 == 0 and self.lastminute!=minute) then
		self:_imageUpdate()
	end
	self.lastminute = minute

	if self.images[self.mode.."clockimage"] or self.images[self.mode.."hourimage"] or self.images[self.mode.."minuteimage"] or self.images[self.mode.."secondimage"] then
		self.canvas:reSkin()
		self.canvas:reDraw()
	end
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

function _reDrawAnalog(self,screen) 
	local m = os.date("%M")
	local h = os.date("%I")
	local s = os.date("%S")

	local width,height = self:_getUsableWallpaperArea()
	
	local defaultposx = (width/2)
	local defaultposy = (height/2)
	if self.images[self.mode.."clockimage"] then
		local tmp = self.images[self.mode.."clockimage"]:rotozoom(0, 1, 5)
		local facew, faceh = tmp:getSize()
		x = math.floor(_getNumber(self:getSettings()[self.mode.."clockposx"],defaultposx) - (facew/2))
		y = math.floor(_getNumber(self:getSettings()[self.mode.."clockposy"],defaultposy) - (faceh/2))
		log:debug("Updating clock face at "..x..", "..y)
		tmp:blit(screen, x, y)
		tmp:release()
	end

	if self.images[self.mode.."hourimage"] then
		local angle = (360 / 12) * (h + (m/60))

		local tmp = self.images[self.mode.."hourimage"]:rotozoom(-angle, 1, 5)
		local facew, faceh = tmp:getSize()
		x = math.floor(_getNumber(self:getSettings()[self.mode.."clockposx"],defaultposx) - (facew/2))
		y = math.floor(_getNumber(self:getSettings()[self.mode.."clockposy"],defaultposy) - (faceh/2))
		log:debug("Updating hour pointer at "..angle..", "..x..", "..y)
		tmp:blit(screen, x, y)
		tmp:release()
	end

	if self.images[self.mode.."minuteimage"] then
		local angle = (360 / 60) * m

		local tmp = self.images[self.mode.."minuteimage"]:rotozoom(-angle, 1, 5)
		local facew, faceh = tmp:getSize()
		x = math.floor(_getNumber(self:getSettings()[self.mode.."clockposx"],defaultposx) - (facew/2))
		y = math.floor(_getNumber(self:getSettings()[self.mode.."clockposy"],defaultposy) - (faceh/2))
		log:debug("Updating minute pointer at "..angle..", "..x..", "..y)
		tmp:blit(screen, x, y)
		tmp:release()
	end

	if self.images[self.mode.."secondimage"] then
		local angle = (360 / 60) * s

		local tmp = self.images[self.mode.."secondimage"]:rotozoom(-angle, 1, 5)
		local facew, faceh = tmp:getSize()
		x = math.floor(_getNumber(self:getSettings()[self.mode.."clockposx"],defaultposx) - (facew/2))
		y = math.floor(_getNumber(self:getSettings()[self.mode.."clockposy"],defaultposy) - (faceh/2))
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
 		if string.find(url, "^http://192%.168") or
			string.find(url, "^http://172%.16%.") or
			string.find(url, "^http://10%.") then
			-- Use direct url
		else
                        imagehost = jnt:getSNHostname()
			imagepath = '/public/imageproxy?u=' .. string.urlEncode(url)				
                end
		log:info("Getting image for "..imageType.." from "..imagehost.." and "..imagepath)
		local http = SocketHttp(jnt, imagehost, imageport)
		local req = RequestHttp(function(chunk, err)
				if chunk then
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
	log:debug("Initiating image update (offset="..self.offset.. " minutes)")

	local no = 1
	for _,item in pairs(self.configItems) do
		if string.find(item.itemtype,"icon$") then
			for attr,value in pairs(item) do
				if attr == "url" then
					if _getString(item.url,nil) then
						self:_retrieveImage(item.url,self.mode.."item"..no)
					else
						self.images[self.mode.."item"..no] = nil
					end
				elseif string.find(attr,"^url%.") then
					local id = string.gsub(attr,"^url%.","")
					if _getString(value,nil) then
						self:_retrieveImage(value,self.mode.."item"..no.."."..id)
					else
						self.images[self.mode.."item"..no.."."..id] = nil
					end
				end
			end
		elseif string.find(item.itemtype,"image$") then
			if _getString(item.url,nil) then
				self:_retrieveImage(item.url,self.mode..item.itemtype)
			else
				self.images[self.mode..item.itemtype] = nil
			end
		end
		no = no +1
	end
	if _getString(self:getSettings()[self.mode.."background"],nil) then
		self:_retrieveImage(self:getSettings()[self.mode.."background"],self.mode.."background")
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
	else
		return {0xcc, 0xcc, 0xcc}
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
			s.window["item"..no]["item"..no] = {
					border = {_getNumber(item.margin,10),0,_getNumber(item.margin,10),0},
					font = self:_loadFont(_getNumber(item.fontsize,20)),
					align = _getString(item.align,"center"),
					w = _getNumber(item.width,WH_FILL),
					h = _getNumber(item.fontsize,20),
					fg = _getColor(item.color),
				}
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


