
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

module(..., Framework.constants)
oo.class(_M, Applet)


----------------------------------------------------------------------------------------
-- Helper Functions
--

-- display
-- the main applet function, the meta arranges for it to be called
-- by the ScreenSaversApplet.
function openScreensaver(self)

	log:debug("Open screensaver")
	local player = appletManager:callService("getCurrentPlayer")
	if player then
		player:unsubscribe('/slim/customclock/changedstyles')
		player:subscribe(
			'/slim/customclock/changedstyles',
			function(chunk)
				for i,entry in pairs(chunk.data[3]) do
					if entry.name == self:getSettings()["style"] then
						for attribute,value in pairs(self:getSettings()) do
							if attribute != "style" and attribute != "font" then
								self:getSettings()[attribute] = ""
							elseif attribute == "font" then
								self:getSettings()[attribute] = "fonts/FreeSans.ttf"
							end
						end
						for attribute,value in pairs(entry) do
							self:getSettings()[attribute] = value
						end
						self:storeSettings()
						if self.window then
							self.window:hide()
							self.window=nil
							self:openScreensaver(self)
						end
					end
				end

			end,
			player:getId(),
			{'customclock','changedstyles'}
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
		self.window:setSkin(self:_getClockSkin(jiveMain:getSelectedSkin()))
		self.window:reSkin()
		self.window:setShowFrameworkWidgets(false)

		local item1Items = {
			item1 = Label("item1","")
		}
		self.item1Label = Group("item1",item1Items)

		local item2Items = {
			item2 = Label("item2","")
		}
		self.item2Label = Group("item2",item2Items)

		local item3Items = {
			item3 = Label("item3","")
		}
		self.item3Label = Group("item3",item3Items)

		local item4Items = {
			item4 = Label("item4","")
		}
		self.item4Label = Group("item4",item4Items)
		if self:getSettings()["alarmtime"] != "" then
			local alarmtimeItems = {
				alarmtime = Label("alarmtime","")
			}
			self.alarmtimeLabel = Group("alarmtime",alarmtimeItems)
		end
		if self:getSettings()["nowplaying2"] != "" then
			local nowplayingItems = {
				nowplaying2 = Label("nowplaying2","")
			}
			self.nowplaying2Label = Group("nowplaying2",nowplayingItems)
		end
		if self:getSettings()["nowplaying3"] != "" then
			local nowplayingItems = {
				nowplaying3 = Label("nowplaying3","")
			}
			self.nowplaying3Label = Group("nowplaying3",nowplayingItems)
		end
		if self:getSettings()["nowplaying4"] != "" then
			local nowplayingItems = {
				nowplaying4 = Label("nowplaying4","")
			}
			self.nowplaying4Label = Group("nowplaying4",nowplayingItems)
		end
		local backgroundItems = {
			background = Icon("background")
		}
		self.backgroundImage = Group("background",backgroundItems)
		local coverItems = {
			cover = Icon("cover")
		}
		self.coverImage = Group("cover",coverItems)
		if self:getSettings()["playstatusplayimage"] != "" or self:getSettings()["playstatuspauseimage"] != "" or self:getSettings()["playstatusstopimage"] != "" then
			local playstatusItems = {
				playstatus = Icon("playstatus")
			}
			self.playStatusImage = Group("playstatus",playstatusItems)
		end
		if self:getSettings()["alarmimage"] != "" or self:getSettings()["alarmactiveimage"] != "" then
			local alarmItems = {
				alarm = Icon("alarm")
			}
			self.alarmImage = Group("alarm",alarmItems)
		end
		if self:getSettings()["shufflestatusoffimage"] != "" or self:getSettings()["shufflestatussongsimage"] != "" or self:getSettings()["shufflestatusalbumsimage"] != "" then
			local shufflestatusItems = {
				shufflestatus = Icon("shufflestatus")
			}
			self.shuffleStatusImage = Group("shufflestatus",shufflestatusItems)
		end
		if self:getSettings()["repeatstatusoffimage"] != "" or self:getSettings()["repeatstatussongimage"] != "" or self:getSettings()["repeatstatusplaylistimage"] != "" then
			local repeatstatusItems = {
				repeatstatus = Icon("repeatstatus")
			}
			self.repeatStatusImage = Group("repeatstatus",repeatstatusItems)
		end
		self.wallpaperImage = Icon("wallpaper")

		self.canvas = Canvas('debug_canvas',function(screen)
				self:_reDrawAnalog(screen)
			end)
	
		local canvasItems = {
			canvas = self.canvas
		}
		local canvasGroup = Group("canvas",canvasItems)
		self.window:addWidget(self.item1Label)
		self.window:addWidget(self.item2Label)
		self.window:addWidget(self.item3Label)
		self.window:addWidget(self.item4Label)
		if self:getSettings()["alarmtime"] and self:getSettings()["alarmtime"] != "" then
			self.window:addWidget(self.alarmtimeLabel)
		end
		if self:getSettings()["nowplaying2"] and self:getSettings()["nowplaying2"] != "" then
			self.window:addWidget(self.nowplaying2Label)
		end
		if self:getSettings()["nowplaying3"] and self:getSettings()["nowplaying3"] != "" then
			self.window:addWidget(self.nowplaying3Label)
		end
		if self:getSettings()["nowplaying4"] and self:getSettings()["nowplaying4"] != "" then
			self.window:addWidget(self.nowplaying4Label)
		end
		if (self:getSettings()["alarmimage"] and self:getSettings()["alarmimage"] != "") or (self:getSettings()["alarmactiveimage"] and self:getSettings()["alarmactiveimage"] != "") then
			self.window:addWidget(self.alarmImage)
		end
		if (self:getSettings()["playstatusplayimage"] and self:getSettings()["playstatusplayimage"] != "") or (self:getSettings()["playstatuspauseimage"] and self:getSettings()["playstatuspauseimage"] != "") or (self:getSettings()["playstatusstopimage"] and self:getSettings()["playstatusstopimage"] != "") then
			self.window:addWidget(self.playStatusImage)
		end
		if (self:getSettings()["shufflestatusoffimage"] and self:getSettings()["shufflestatusoffimage"] != "") or (self:getSettings()["shufflestatussongsimage"] and self:getSettings()["shufflestatussongsimage"] != "") or (self:getSettings()["shufflestatusalbumsimage"] and self:getSettings()["shufflestatusalbumsimage"] != "") then
			self.window:addWidget(self.shuffleStatusImage)
		end
		if (self:getSettings()["repeatstatusoffimage"] and self:getSettings()["repeatstatusoffimage"] != "") or (self:getSettings()["repeatstatussongimage"] and self:getSettings()["repeatstatussongimage"] != "") or (self:getSettings()["repeatstatusplaylistimage"] and self:getSettings()["repeatstatusplaylistimage"] != "") then
			self.window:addWidget(self.repeatStatusImage)
		end
		self.window:addWidget(self.coverImage)
		self.window:addWidget(self.backgroundImage)
		self.window:addWidget(canvasGroup)

		-- register window as a screensaver, unless we are explicitly not in that mode
		local manager = appletManager:getAppletInstance("ScreenSavers")
		manager:screensaverWindow(self.window)
		self.window:addTimer(1000, function() self:_tick() end)
		self.offset = math.random(15)
		self.images = {}
	end
	self.lastminute = 0
	self.nowPlaying = 0
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
								self:defineSettingStyleSink(tostring(self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS")),chunk.data)
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
								self:defineSettingStyleSink(tostring(self:string("SCREENSAVER_CUSTOMCLOCK_SETTINGS")),chunk.data)
							end
						end,
						'GET', "/svn/CustomClock/trunk/clockstyles.json")
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

function defineSettingStyleSink(self,title,data)
	self.popup:hide()
	
	local style = self:getSettings()["style"]

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
							self:getSettings()["style"] = entry.name
							for attribute,value in pairs(self:getSettings()) do
								if attribute != "style" and attribute != "nowplaying" and attribute != "font" then
									self:getSettings()[attribute] = ""
								elseif attribute == "font" then
									self:getSettings()[attribute] = "fonts/FreeSans.ttf"
								elseif attribute == "backgroundtype" then
									self:getSettings()[attribute] = ""
								end
							end
							for attribute,value in pairs(entry) do
								self:getSettings()[attribute] = value
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



function _loadFont(self,fontSize)
        return Font:load(self:getSettings()["font"], fontSize)
end

-- Get usable wallpaper area
function _getUsableWallpaperArea(self)
	local width,height = Framework.getScreenSize()
	return width,height
end

function _extractTrackInfo(self, _track, _itemType)
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

function _updateNowPlaying(self,itemType)
	local player = appletManager:callService("getCurrentPlayer")
	local playerStatus = player:getPlayerStatus()
	if playerStatus.mode == 'play' then
		if playerStatus.item_loop then
			if self:getSettings()["nowplaying"] and self:getSettings()["nowplaying"] != ""  then
				local trackInfo = self:_extractTrackInfo(playerStatus.item_loop[1],itemType)
				if trackInfo != "" then
					self.item4Label:setWidgetValue("item4",trackInfo)
					if self:getSettings()["nowplayingreplacement"] == "" or self:getSettings()["nowplayingreplacement"] == "auto" then
						if self:getSettings()["mode"] == "analog" then
							if self.model == "touch" then
								--self.item2Label:setWidgetValue("item2","")
								--self.item3Label:setWidgetValue("item3","")
							elseif self.model == "controller" then
								self.item2Label:setWidgetValue("item2","")
							elseif self.model == "radio" then
								self.item2Label:setWidgetValue("item2","")
							end
						else
							if self.model == "radio" then
								self.item2Label:setWidgetValue("item2","")
							end
						end
					end
				end
			end
		else
			self.item4Label:setWidgetValue("item4","")
		end
	else
		self.item4Label:setWidgetValue("item4","")
	end
end

function _updateStaticNowPlaying(self)
	local player = appletManager:callService("getCurrentPlayer")
	local playerStatus = player:getPlayerStatus()
	if playerStatus.mode == 'play' then
		if playerStatus.item_loop then
			if self:getSettings()["nowplaying2"] and self:getSettings()["nowplaying2"] != "" then
				self.nowplaying2Label:setWidgetValue("nowplaying2",self:_replaceTitleKeywords(playerStatus.item_loop[1], self:getSettings()["nowplaying2"],playerStatus.item_loop[1].track))
			end
			if self:getSettings()["nowplaying3"] and self:getSettings()["nowplaying3"] != "" then
				self.nowplaying3Label:setWidgetValue("nowplaying3",self:_replaceTitleKeywords(playerStatus.item_loop[1], self:getSettings()["nowplaying3"],false))
			end
			if self:getSettings()["nowplaying4"] and self:getSettings()["nowplaying4"] != "" then
				self.nowplaying4Label:setWidgetValue("nowplaying4",self:_replaceTitleKeywords(playerStatus.item_loop[1], self:getSettings()["nowplaying4"],false))
			end
		else
			if self:getSettings()["nowplaying2"] and self:getSettings()["nowplaying2"] != "" then
				self.nowplaying2Label:setWidgetValue("nowplaying2","")
			end
			if self:getSettings()["nowplaying3"] and self:getSettings()["nowplaying3"] != "" then
				self.nowplaying3Label:setWidgetValue("nowplaying3","")
			end
			if self:getSettings()["nowplaying4"] and self:getSettings()["nowplaying4"] != "" then
				self.nowplaying4Label:setWidgetValue("nowplaying4","")
			end
		end
	else
		if self:getSettings()["nowplaying2"] and self:getSettings()["nowplaying2"] != "" then
			self.nowplaying2Label:setWidgetValue("nowplaying2","")
		end
		if self:getSettings()["nowplaying3"] and self:getSettings()["nowplaying3"] != "" then
			self.nowplaying3Label:setWidgetValue("nowplaying3","")
		end
		if self:getSettings()["nowplaying4"] and self:getSettings()["nowplaying4"] != "" then
			self.nowplaying4Label:setWidgetValue("nowplaying4","")
		end
	end
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

function _getCoverSize(self)
	if self:getSettings()["coversize"] and self:getSettings()["coversize"] != "" then
		return tonumber(self:getSettings()["coversize"])
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

function _updateAlbumCover(self)
	local player = appletManager:callService("getCurrentPlayer")
	local playerStatus = player:getPlayerStatus()
	if playerStatus.mode == 'play' then
		if playerStatus.item_loop then
			local iconId = playerStatus.item_loop[1]["icon-id"]
			if iconId then
				local server = player:getSlimServer()
				if self:getSettings()["coversize"] and self:getSettings()["coversize"] != "" then
					server:fetchArtwork(iconId,self.coverImage:getWidget("cover"),self:_getCoverSize())
				else
					if self.model == "controller" then
						server:fetchArtwork(iconId,self.coverImage:getWidget("cover"),self:_getCoverSize())
					elseif self.model == "radio" then
						server:fetchArtwork(iconId,self.coverImage:getWidget("cover"),self:_getCoverSize())
					elseif self.model == "touch" then
						server:fetchArtwork(iconId,self.coverImage:getWidget("cover"),self:_getCoverSize())
					end
				end
			else 
				self.coverImage:setWidgetValue("cover",nil)
			end
		else
			self.coverImage:setWidgetValue("cover",nil)
		end
	else
		self.coverImage:setWidgetValue("cover",nil)
	end
end

-- Update the time and if needed also the wallpaper
function _tick(self,forcedBackgroundUpdate)
	log:debug("Updating time")

	if self:getSettings()["item1"] and self:getSettings()["item1"] != "" then
		self.item1Label:setWidgetValue("item1",os.date(self:getSettings()["item1"]))
	end
	if self:getSettings()["item2"] and self:getSettings()["item2"] != "" then
		self.item2Label:setWidgetValue("item2",os.date(self:getSettings()["item2"]))
	end
	if self:getSettings()["item3"] and self:getSettings()["item3"] != "" then
		self.item3Label:setWidgetValue("item3",os.date(self:getSettings()["item3"]))
	end

	if self:getSettings()["mode"] and self:getSettings()["mode"] == "analog" then
		self.item1Label:setWidgetValue("item1","")
	end

	local second = os.date("%S")
	if second % 3 == 0 then
		if self.nowPlaying>=3 then
			if self:getSettings()["nowplayingreplacement"] == "none" or ((self.model == "touch" or self.model == "controller") and self:getSettings()["mode"] == "digital") then
				self.nowPlaying = 1
			else
				self.nowPlaying = 0
			end
		else
			self.nowPlaying = self.nowPlaying + 1
		end
	end
	if self.nowPlaying>0 and (self:getSettings()["nowplaying"] == true or self:getSettings()["nowplaying"] == "true") then
		self:_updateNowPlaying(self.nowPlaying)
	else
		self.item4Label:setWidgetValue("item4","")	
	end
	if (self:getSettings()["nowplaying2"] and self:getSettings()["nowplaying2"] != "") or (self:getSettings()["nowplaying3"] and self:getSettings()["nowplaying3"] != "") or (self:getSettings()["nowplaying4"] and self:getSettings()["nowplaying4"] != "") then
		self:_updateStaticNowPlaying()
	end

	if self:getSettings()["cover"] or self:getSettings()["backgroundtype"] == "cover" or self:getSettings()["backgroundtype"] == "coverblack" then
		self:_updateAlbumCover()
	end

	local minute = os.date("%M")
	if forcedBackgroundUpdate or ((minute + self.offset) % 15 == 0 and self.lastminute!=minute) then
		self:_imageUpdate()
	end
	self.lastminute = minute
	local player = appletManager:callService("getCurrentPlayer")
	local playstatus = player:getPlayerStatus()["mode"]
	local shufflestatus = tonumber(player:getPlayerStatus()["playlist shuffle"])
	local repeatstatus = tonumber(player:getPlayerStatus()["playlist repeat"])

	if (self:getSettings()["playstatusplayimage"] and self:getSettings()["playstatusplayimage"] != "") or (self:getSettings()["playstatuspauseimage"] and self:getSettings()["playstatuspauseimage"] != "") or (self:getSettings()["playstatusstopimage"] and self:getSettings()["playstatusstopimage"] != "") then
		self.playStatusImage:setWidgetValue("playstatus",self.images[playstatus])
	else
		self.playStatusImage:setWidgetValue("playstatus",nil)
	end

	if shufflestatus == 0 and self:getSettings()["shufflestatusoffimage"] and self:getSettings()["shufflestatusoffimage"] != "" then
		self.shuffleStatusImage:setWidgetValue("shufflestatus",self.images["shuffleoff"])
	elseif shufflestatus==1 and self:getSettings()["shufflestatussongsimage"] and self:getSettings()["shufflestatussongsimage"] != "" then
		self.shuffleStatusImage:setWidgetValue("shufflestatus",self.images["shufflesongs"])
	elseif shufflestatus==2 and self:getSettings()["shufflestatusalbumsimage"] and self:getSettings()["shufflestatusalbumsimage"] != "" then
		self.shuffleStatusImage:setWidgetValue("shufflestatus",self.images["shufflealbums"])
	else	
		self.shuffleStatusImage:setWidgetValue("shufflestatus",nil)
	end

	if repeatstatus == 0 and self:getSettings()["repeatstatusoffimage"] and self:getSettings()["repeatstatusoffimage"] != "" then
		self.repeatStatusImage:setWidgetValue("repeatstatus",self.images["repeatoff"])
	elseif repeatstatus == 1 and self:getSettings()["repeatstatussongimage"] and self:getSettings()["repeatstatussongimage"] != "" then
		self.repeatStatusImage:setWidgetValue("repeatstatus",self.images["repeatsong"])
	elseif repeatstatus == 2 and self:getSettings()["repeatstatusplaylistimage"] and self:getSettings()["repeatstatusplaylistimage"] != "" then
		self.repeatStatusImage:setWidgetValue("repeatstatus",self.images["repeatplaylist"])
	else
		self.repeatStatusImage:setWidgetValue("repeatstatus",nil)
	end

	local alarmtime = player:getPlayerStatus()["alarm_next"]
	local alarmstate = player:getPlayerStatus()["alarm_state"]

	if alarmstate=="set" or alarmstate=="snooze" then
		if self:getSettings()["alarmtime"] and self:getSettings()["alarmtime"] != "" then
			self.alarmtimeLabel:setWidgetValue("alarmtime",os.date(self:getSettings()["alarmtime"],alarmtime))
		end
		if self:getSettings()["alarmimage"] and self:getSettings()["alarmimage"] != "" then
			self.alarmImage:setWidgetValue("alarm",self.images["alarm"])
		elseif (self:getSettings()["alarmimage"] and self:getSettings()["alarmimage"] != "")  or (self:getSettings()["alarmactiveimage"] and self:getSettings()["alarmactiveimage"] != "") then
			self.alarmImage:setWidgetValue("alarm",nil)
		end
	elseif alarmstate=="active" then
		if self:getSettings()["alarmtime"] and self:getSettings()["alarmtime"] != "" then
			self.alarmtimeLabel:setWidgetValue("alarmtime","")
		end
		if self:getSettings()["alarmactiveimage"] and self:getSettings()["alarmactiveimage"] != "" then
			self.alarmImage:setWidgetValue("alarm",self.images["alarmactive"])
		elseif self:getSettings()["alarmimage"] and self:getSettings()["alarmimage"] != "" then
			self.alarmImage:setWidgetValue("alarm",self.images["alarm"])
		elseif (self:getSettings()["alarmimage"] and self:getSettings()["alarmimage"] != "")  or (self:getSettings()["alarmactiveimage"] and self:getSettings()["alarmactiveimage"] != "") then
			self.alarmImage:setWidgetValue("alarm",nil)
		end
	else
		if self:getSettings()["alarmtime"] and self:getSettings()["alarmtime"] != "" then
			self.alarmtimeLabel:setWidgetValue("alarmtime","")
		end
		if (self:getSettings()["alarmimage"] and self:getSettings()["alarmimage"] != "") or (self:getSettings()["alarmactiveimage"] and self:getSettings()["alarmactiveimage"] != "") then
			self.alarmImage:setWidgetValue("alarm",nil)
		end
	end
	


	if self:getSettings()["mode"] == "analog" or self.images["clock"] then
		self.canvas:reSkin()
		self.canvas:reDraw()
	end
end

function _reDrawAnalog(self,screen) 
	local m = os.date("%M")
	local h = os.date("%I")
	local s = os.date("%S")

	local width,height = self:_getUsableWallpaperArea()

	if self.images["clock"] then
		local tmp = self.images["clock"]:rotozoom(0, 1, 5)
		local facew, faceh = tmp:getSize()
		x = math.floor((width/2) - (facew/2))
		y = math.floor((height/2) - (faceh/2))
		log:debug("Updating clock face at "..x..", "..y)
		tmp:blit(screen, x, y)
		tmp:release()
	end

	if self:getSettings()["mode"] == "analog" and self.images["hour"] then
		local angle = (360 / 12) * (h + (m/60))

		local tmp = self.images["hour"]:rotozoom(-angle, 1, 5)
		local facew, faceh = tmp:getSize()
		x = math.floor((width/2) - (facew/2))
		y = math.floor((height/2) - (faceh/2))
		log:debug("Updating hour pointer at "..angle..", "..x..", "..y)
		tmp:blit(screen, x, y)
		tmp:release()
	end

	if self:getSettings()["mode"] == "analog" and self.images["minute"] then
		local angle = (360 / 60) * m

		local tmp = self.images["minute"]:rotozoom(-angle, 1, 5)
		local facew, faceh = tmp:getSize()
		x = math.floor((width/2) - (facew/2))
		y = math.floor((height/2) - (faceh/2))
		log:debug("Updating minute pointer at "..angle..", "..x..", "..y)
		tmp:blit(screen, x, y)
		tmp:release()
	end

	if self:getSettings()["mode"] == "analog" and self.images["second"] then
		local angle = (360 / 60) * s

		local tmp = self.images["second"]:rotozoom(-angle, 1, 5)
		local facew, faceh = tmp:getSize()
		x = math.floor((width/2) - (facew/2))
		y = math.floor((height/2) - (faceh/2))
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
					if imageType == "background" then
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
						if self:getSettings()["backgroundtype"] and self:getSettings()["backgroundtype"] != "" then
							self.backgroundImage:setWidgetValue("background",image)
						end
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
function _getImage(self,attribute,id)
	local img = self:getSettings()[attribute]
	if img and img != "" then
		self:_retrieveImage(img,id)
	else
		self.images[id] = nil
	end
end

function _imageUpdate(self)
	log:info("Initiating wallpaper update (offset="..self.offset.. " minutes)")

	self:_getImage("background","background")
	self:_getImage("clockimage","clock")
	self:_getImage("alarmimage","alarm")
	self:_getImage("alarmactiveimage","alarmactive")
	self:_getImage("playstatusplayimage","play")
	self:_getImage("playstatusstopimage","stop")
	self:_getImage("playstatuspauseimage","pause")
	self:_getImage("shufflestatusoffimage","shuffleoff")
	self:_getImage("shufflestatussongsimage","shufflesongs")
	self:_getImage("shufflestatusalbumsimage","shufflealbums")
	self:_getImage("repeatstatusoffimage","repeatoff")
	self:_getImage("repeatstatussongimage","repeatsong")
	self:_getImage("repeatstatusplaylistimage","repeatplaylist")

	if self:getSettings()["mode"] == "analog" then
		self:_getImage("hourimage","hour")
		self:_getImage("minuteimage","minute")
		self:_getImage("secondimage","second")
	else
		self.images["hour"] = nil
		self.images["minute"] = nil
		self.images["second"] = nil
	end
end

function _getColor(self,color)
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

function _getClockSkin(self,skin)
	local s = {}
	local width,height = Framework.getScreenSize()
	local primaryAlign = 'center'
	local primaryItemHeight
	local primaryItemFont
	local secondary2ItemHeight
	local secondary2ItemFont
	local secondary2Position
	local secondary3ItemHeight
	local secondary3ItemFont
	local secondary3Position
	local secondary2Align = 'left'
	local secondary3Align = 'right'
	local nowPlayingPosition
	local nowPlayingFont
	local nowPlayingHeight
	local item1Margin = 10
	local item2Margin = 5
	local item3Margin = 5
	local nowPlayingMargin = 5
	if self:getSettings()["mode"] == "digital" then
		if self.model == "touch" then
			secondary2ItemHeight = 40
			secondary3ItemHeight = 40
			secondary2ItemFont = 30
			secondary3ItemFont = 30
			primaryItemHeight = 180
			primaryItemFont = 170
			primaryItemPosition = height-primaryItemHeight-secondary2ItemHeight
			secondary2Position = height-secondary2ItemHeight-5
			secondary3Position = height-secondary2ItemHeight-5
			if (self:getSettings()["item2"] != "" and self:getSettings()["item3"] == "") or (self:getSettings()["item3"] != "" and self:getSettings()["item2"] == "") then
				secondary2Align = 'center'
				secondary3Align = 'center'
			end
			item2Margin = 10
			item3Margin = 10
			nowPlayingMargin = 10
			nowPlayingHeight = 30
			nowPlayingPosition = height-primaryItemHeight-secondary2ItemHeight-nowPlayingHeight
			nowPlayingFont = secondary2ItemFont
		elseif self.model == "radio" then
			secondary2ItemHeight = 50
			secondary2ItemFont = 35
			secondary3ItemHeight = 50
			secondary3ItemFont = 35
			primaryItemHeight = 110
			primaryItemFont = 110
			primaryItemPosition = height-primaryItemHeight-secondary2ItemHeight-20
			secondary2Position = height-primaryItemHeight-secondary2ItemHeight-secondary3ItemHeight-20
			secondary2Align = 'center'
			secondary3Position = height-secondary3ItemHeight-20
			secondary3Align = 'center'
			nowPlayingPosition = secondary2Position+20
			nowPlayingHeight = 25
			nowPlayingFont = 23
		else
			secondary2ItemHeight = 50
			secondary2ItemFont = 35
			secondary3ItemHeight = 50
			secondary3ItemFont = 35
			primaryItemHeight = 80
			primaryItemFont = 80
			primaryItemPosition = height-primaryItemHeight-secondary2ItemHeight
			secondary2Position = height-primaryItemHeight-secondary2ItemHeight-secondary3ItemHeight
			secondary2Align = 'center'
			secondary3Position = height-secondary2ItemHeight
			secondary3Align = 'center'
			nowPlayingHeight = 30
			nowPlayingPosition = secondary2Position-nowPlayingHeight
			nowPlayingFont = 20
		end
	else
		if self.model == "touch" then
			secondary2ItemHeight = 30
			secondary2ItemFont = 25
			secondary3ItemHeight = 30
			secondary3ItemFont = 25
			primaryItemHeight = 180
			primaryItemFont = 170
			primaryItemPosition = height-primaryItemHeight-secondary2ItemHeight
			secondary2Position = height-secondary2ItemHeight-5
			secondary3Position = height-secondary3ItemHeight-5
			if (self:getSettings()["item2"] != "" and self:getSettings()["item3"] == "") or (self:getSettings()["item3"] != "" and self:getSettings()["item2"] == "") then
				secondary2Align = 'center'
				secondary3Align = 'center'
			end
			item2Margin = 10
			item3Margin = 10
			nowPlayingMargin = 10
			nowPlayingHeight = 30
			nowPlayingPosition = 5
			nowPlayingFont = secondary2ItemFont
		elseif self.model == "radio" then
			secondary2ItemHeight = 35
			secondary2ItemFont = 23
			secondary3ItemHeight = 35
			secondary3ItemFont = 23
			primaryItemHeight = 110
			primaryItemFont = 110
			primaryItemPosition = height-primaryItemHeight-secondary2ItemHeight-20
			secondary2Position = 0
			secondary2Align = 'center'
			secondary3Position = height-secondary3ItemHeight
			secondary3Align = 'center'
			nowPlayingPosition = 0
			nowPlayingHeight = 35
			nowPlayingFont = 23
		else
			secondary2ItemHeight = 50
			secondary2ItemFont = 25
			secondary3ItemHeight = 50
			secondary3ItemFont = 25
			primaryItemHeight = 80
			primaryItemFont = 80
			primaryItemPosition = height-primaryItemHeight-secondary2ItemHeight
			secondary2Position = 5
			secondary2Align = 'center'
			secondary3Position = height-secondary3ItemHeight
			secondary3Align = 'center'
			nowPlayingHeight = 30
			nowPlayingPosition = 10
			nowPlayingFont = 20
		end
	end

	local text1Color = { 0xcc, 0xcc, 0xcc }
	local text2Color = { 0xcc, 0xcc, 0xcc }
	local text3Color = { 0xcc, 0xcc, 0xcc }
	local nowPlayingColor = { 0xcc, 0xcc, 0xcc }
	local alarmtimeColor = { 0xcc, 0xcc, 0xcc }
	local nowplaying2Color = { 0xcc, 0xcc, 0xcc }
	local nowplaying3Color = { 0xcc, 0xcc, 0xcc }
	local nowplaying4Color = { 0xcc, 0xcc, 0xcc }

	if self:getSettings()["item1color"] and self:getSettings()["item1color"] != "" then
		text1Color = self:_getColor(self:getSettings()["item1color"])
	end
	if self:getSettings()["item2color"] and self:getSettings()["item2color"] != "" then
		text2Color = self:_getColor(self:getSettings()["item2color"])
	end
	if self:getSettings()["item3color"] and self:getSettings()["item3color"] != "" then
		text3Color = self:_getColor(self:getSettings()["item3color"])
	end
	if self:getSettings()["nowplayingcolor"] and self:getSettings()["nowplayingcolor"] != "" then
		nowPlayingColor = self:_getColor(self:getSettings()["nowplayingcolor"])
	end
	if self:getSettings()["alarmtimecolor"] and self:getSettings()["alarmtimecolor"] != "" then
		alarmtimeColor = self:_getColor(self:getSettings()["alarmtimecolor"])
	end
	if self:getSettings()["nowplaying2color"] and self:getSettings()["nowplaying2color"] != "" then
		nowplaying2Color = self:_getColor(self:getSettings()["nowplaying2color"])
	end
	if self:getSettings()["nowplaying3color"] and self:getSettings()["nowplaying3color"] != "" then
		nowplaying3Color = self:_getColor(self:getSettings()["nowplaying3color"])
	end
	if self:getSettings()["nowplaying4color"] and self:getSettings()["nowplaying4color"] != "" then
		nowplaying4Color = self:_getColor(self:getSettings()["nowplaying4color"])
	end

	if self:getSettings()["item1position"] and self:getSettings()["item1position"] != "" then
		primaryItemPosition = tonumber(self:getSettings()["item1position"])
	end
	if self:getSettings()["item2position"] and self:getSettings()["item2position"] != "" then
		secondary2Position = tonumber(self:getSettings()["item2position"])
	end
	if self:getSettings()["item3position"] and self:getSettings()["item3position"] != "" then
		secondary3Position = tonumber(self:getSettings()["item3position"])
	end
	if self:getSettings()["nowplayingposition"] and self:getSettings()["nowplayingposition"] != "" then
		nowPlayingPosition = tonumber(self:getSettings()["nowplayingposition"])
	end
	if self:getSettings()["item1height"] and self:getSettings()["item1height"] != "" then
		primaryItemHeight = tonumber(self:getSettings()["item1height"])
	end
	if self:getSettings()["item2height"] and self:getSettings()["item2height"] != "" then
		secondary2Height = tonumber(self:getSettings()["item2height"])
	end
	if self:getSettings()["item3height"] and self:getSettings()["item3height"] != "" then
		secondary3Height = tonumber(self:getSettings()["item3height"])
	end
	if self:getSettings()["nowplayingheight"] and self:getSettings()["nowplayingheight"] != "" then
		nowPlayingHeight = tonumber(self:getSettings()["nowplayingheight"])
	end

	if self:getSettings()["item1size"] and self:getSettings()["item1size"] != "" then
		primaryItemFont = tonumber(self:getSettings()["item1size"])
	end
	if self:getSettings()["item2size"] and self:getSettings()["item2size"] != "" then
		secondary2ItemFont = tonumber(self:getSettings()["item2size"])
	end
	if self:getSettings()["item3size"] and self:getSettings()["item3size"] != "" then
		secondary3ItemFont = tonumber(self:getSettings()["item3size"])
	end
	if self:getSettings()["nowplayingsize"] and self:getSettings()["nowplayingsize"] != "" then
		nowPlayingFont = tonumber(self:getSettings()["nowplayingsize"])
	end

	if self:getSettings()["item1align"] and self:getSettings()["item1align"] != "" then
		primaryAlign = self:getSettings()["item1align"]
	end
	if self:getSettings()["item2align"] and self:getSettings()["item2align"] != "" then
		secondary2Align = self:getSettings()["item2align"]
	end
	if self:getSettings()["item3align"] and self:getSettings()["item3align"] != "" then
		secondary3Align = self:getSettings()["item3align"]
	end

	if self:getSettings()["item1margin"] and self:getSettings()["item1margin"] != "" then
		item1Margin = self:getSettings()["item1margin"]
	end
	if self:getSettings()["item2margin"] and self:getSettings()["item2margin"] != "" then
		item2Margin = self:getSettings()["item2margin"]
	end
	if self:getSettings()["item3margin"] and self:getSettings()["item3margin"] != "" then
		item3Margin = self:getSettings()["item3margin"]
	end
	if self:getSettings()["nowplayingmargin"] and self:getSettings()["nowplayingmargin"] != "" then
		nowPlayingMargin = self:getSettings()["nowplayingmargin"]
	end

	local item1Style = nil
	if self:getSettings()["item1"] and self:getSettings()["item1"] != "" then
		item1Style = {
				position = LAYOUT_NONE,
				y = primaryItemPosition,
				x = 0,
				item1 = {
					border = {item1Margin,0,item1Margin,0},
					font = self:_loadFont(primaryItemFont),
					align = primaryAlign,
					w = WH_FILL,
					h = primaryItemHeight,
					fg = text1Color,
				},
				zOrder = 4,
		}
	end
		
	local item2Style = nil
	if self:getSettings()["item2"] and self:getSettings()["item2"] != "" then
		item2Style = {
				position = LAYOUT_NONE,
				y = secondary2Position,
				x = 0,
				item2 = {
					border = {item2Margin,0,item2Margin,0},
					font = self:_loadFont(secondary2ItemFont),
					align = secondary2Align,
					w = WH_FILL,
					h = secondary2ItemHeight,
					fg = text2Color,
				},
				zOrder = 4,
		}
	end

	local item3Style = nil
	if self:getSettings()["item3"] and self:getSettings()["item3"] != "" then
		item3Style = {
				position = LAYOUT_NONE,
				y = secondary3Position,
				x = 0,
				item3 = {
					border = {item3Margin,0,item3Margin,0},
					font = self:_loadFont(secondary3ItemFont),
					align = secondary3Align,
					w = WH_FILL,
					h = secondary3ItemHeight,
					fg = text3Color,
				},
				zOrder = 4,
		}
	end

	local item4Style = nil
	if self:getSettings()["nowplaying"] == true or self:getSettings()["nowplaying"] == "true" then
		item4Style = {
				position = LAYOUT_NONE,
				y = nowPlayingPosition,
				x = 0,
				item4 = {
					border = {nowPlayingMargin,0,nowPlayingMargin,0},
					font = self:_loadFont(nowPlayingFont),
					align = 'center',
					w = WH_FILL,
					h = nowPlayingHeight,
					fg = nowPlayingColor,
				},
				zOrder = 4,
		}
	end

	local playStatusStyle = nil
	if (self:getSettings()["playstatusplayimage"] and self:getSettings()["playstatusplayimage"] != "") or (self:getSettings()["playstatuspauseimage"] and self:getSettings()["playstatuspauseimage"] != "") or (self:getSettings()["playstatusstopimage"] and self:getSettings()["playstatusstopimage"] != "") then
		local posx = 0
		local posy = 0
		if self:getSettings()["playstatuspositionx"] and self:getSettings()["playstatuspositionx"] != "" then
			posx = tonumber(self:getSettings()["playstatuspositionx"])
		end
		if self:getSettings()["playstatuspositiony"] and self:getSettings()["playstatuspositiony"] != "" then
			posy = tonumber(self:getSettings()["playstatuspositiony"])
		end
		playStatusStyle = {
			position = LAYOUT_NONE,
			x = posx,
			y = posy,
			playstatus = {
				align = 'center',
			},
			zOrder = 4,
		}
	end
	local shuffleStatusStyle = nil
	if (self:getSettings()["shufflestatusoffimage"] and self:getSettings()["shufflestatusoffimage"] != "") or (self:getSettings()["shufflestatussongsimage"] and self:getSettings()["shufflestatussongsimage"] != "") or (self:getSettings()["shufflestatusalbumsimage"] and self:getSettings()["shufflestatusalbumsimage"] != "") then
		local posx = 0
		local posy = 0
		if self:getSettings()["shufflestatuspositionx"] and self:getSettings()["shufflestatuspositionx"] != "" then
			posx = tonumber(self:getSettings()["shufflestatuspositionx"])
		end
		if self:getSettings()["shufflestatuspositiony"] and self:getSettings()["shufflestatuspositiony"] != "" then
			posy = tonumber(self:getSettings()["shufflestatuspositiony"])
		end
		shuffleStatusStyle = {
			position = LAYOUT_NONE,
			x = posx,
			y = posy,
			shufflestatus = {
				align = 'center',
			},
			zOrder = 4,
		}
	end
	local repeatStatusStyle = nil
	if (self:getSettings()["repeatstatusoffimage"] and self:getSettings()["repeatstatusoffimage"] != "") or (self:getSettings()["repeatstatussongimage"] and self:getSettings()["repeatstatussongimage"] != "") or (self:getSettings()["repeatstatusplaylistimage"] and self:getSettings()["repeatstatusplaylistimage"] != "") then
		local posx = 0
		local posy = 0
		if self:getSettings()["repeatstatuspositionx"] and self:getSettings()["repeatstatuspositionx"] != "" then
			posx = tonumber(self:getSettings()["repeatstatuspositionx"])
		end
		if self:getSettings()["repeatstatuspositiony"] and self:getSettings()["repeatstatuspositiony"] != "" then
			posy = tonumber(self:getSettings()["repeatstatuspositiony"])
		end
		repeatStatusStyle = {
			position = LAYOUT_NONE,
			x = posx,
			y = posy,
			repeatstatus = {
				align = 'center',
			},
			zOrder = 4,
		}
	end

	local alarmStyle = nil
	if (self:getSettings()["alarmimage"] and self:getSettings()["alarmimage"] != "") or (self:getSettings()["alarmactiveimage"] and self:getSettings()["alarmactiveimage"] != "") then
		local posx = 0
		local posy = 0
		if self:getSettings()["alarmimagepositionx"] and self:getSettings()["alarmimagepositionx"] != "" then
			posx = tonumber(self:getSettings()["alarmimagepositionx"])
		end
		if self:getSettings()["alarmimagepositiony"] and self:getSettings()["alarmimagepositiony"] != "" then
			posy = tonumber(self:getSettings()["alarmimagepositiony"])
		end
		alarmStyle = {
			position = LAYOUT_NONE,
			x = posx,
			y = posy,
			alarm = {
				align = 'center',
			},
			zOrder = 4,
		}
	end
	local alarmtimeStyle = nil
	if self:getSettings()["alarmtime"] and self:getSettings()["alarmtime"] != "" then
		local posx = 0
		local posy = 0
		if self:getSettings()["alarmtimepositionx"] and self:getSettings()["alarmtimepositionx"] != "" then
			posx = tonumber(self:getSettings()["alarmtimepositionx"])
		end
		if self:getSettings()["alarmtimepositiony"] and self:getSettings()["alarmtimepositiony"] != "" then
			posy = tonumber(self:getSettings()["alarmtimepositiony"])
		end
		local alarmtimeFont = secondary2ItemFont
		if self:getSettings()["alarmtimesize"] and self:getSettings()["alarmtimesize"] != "" then
			alarmtimeFont = tonumber(self:getSettings()["alarmtimesize"])
		end
		alarmtimeStyle = {
				position = LAYOUT_NONE,
				x = posx,
				y = posy,
				alarmtime = {
					border = {0,0,0,0},
					font = self:_loadFont(alarmtimeFont),
					align = 'center',
					h = alarmtimeFont,
					fg = alarmtimeColor,
				},
				zOrder = 4,
		}
	end

	local nowplaying2Style = nil
	if self:getSettings()["nowplaying2"] and self:getSettings()["nowplaying2"] != "" then
		local posx = 0
		local posy = 0
		if self:getSettings()["nowplaying2positionx"] and self:getSettings()["nowplaying2positionx"] != "" then
			posx = tonumber(self:getSettings()["nowplaying2positionx"])
		end
		if self:getSettings()["nowplaying2positiony"] and self:getSettings()["nowplaying2positiony"] != "" then
			posy = tonumber(self:getSettings()["nowplaying2positiony"])
		end
		local font = secondary2ItemFont
		if self:getSettings()["nowplaying2size"] and self:getSettings()["nowplaying2size"] != "" then
			font = tonumber(self:getSettings()["nowplaying2size"])
		end
		local nowplaying2Align = 'center'
		if self:getSettings()["nowplaying2align"] and self:getSettings()["nowplaying2align"] != "" then
			nowplaying2Align = self:getSettings()["nowplaying2align"]
		end
		local width = WH_FILL
		if self:getSettings()["nowplaying2width"] and self:getSettings()["nowplaying2width"] != "" then
			width = tonumber(self:getSettings()["nowplaying2width"])
		end
		nowplaying2Style = {
				position = LAYOUT_NONE,
				x = posx,
				y = posy,
				nowplaying2 = {
					border = {nowPlayingMargin,0,nowPlayingMargin,0},
					w = width,
					font = self:_loadFont(font),
					align = nowplaying2Align,
					h = font,
					fg = nowplaying2Color,
				},
				zOrder = 4,
		}
	end

	local nowplaying3Style = nil
	if self:getSettings()["nowplaying3"] and self:getSettings()["nowplaying3"] != "" then
		local posx = 0
		local posy = 0
		if self:getSettings()["nowplaying3positionx"] and self:getSettings()["nowplaying3positionx"] != "" then
			posx = tonumber(self:getSettings()["nowplaying3positionx"])
		end
		if self:getSettings()["nowplaying3positiony"] and self:getSettings()["nowplaying3positiony"] != "" then
			posy = tonumber(self:getSettings()["nowplaying3positiony"])
		end
		local font = secondary2ItemFont
		if self:getSettings()["nowplaying3size"] and self:getSettings()["nowplaying3size"] != "" then
			font = tonumber(self:getSettings()["nowplaying3size"])
		end
		local nowplaying3Align = 'center'
		if self:getSettings()["nowplaying3align"] and self:getSettings()["nowplaying3align"] != "" then
			nowplaying3Align = self:getSettings()["nowplaying3align"]
		end
		local width = WH_FILL
		if self:getSettings()["nowplaying3width"] and self:getSettings()["nowplaying3width"] != "" then
			width = tonumber(self:getSettings()["nowplaying3width"])
		end
		nowplaying3Style = {
				position = LAYOUT_NONE,
				x = posx,
				y = posy,
				nowplaying3 = {
					border = {nowPlayingMargin,0,nowPlayingMargin,0},
					w = width,
					font = self:_loadFont(font),
					align = nowplaying3Align,
					h = font,
					fg = nowplaying3Color,
				},
				zOrder = 4,
		}
	end

	local nowplaying4Style = nil
	if self:getSettings()["nowplaying4"] and self:getSettings()["nowplaying4"] != "" then
		local posx = 0
		local posy = 0
		if self:getSettings()["nowplaying4positionx"] and self:getSettings()["nowplaying4positionx"] != "" then
			posx = tonumber(self:getSettings()["nowplaying4positionx"])
		end
		if self:getSettings()["nowplaying4positiony"] and self:getSettings()["nowplaying4positiony"] != "" then
			posy = tonumber(self:getSettings()["nowplaying4positiony"])
		end
		local font = secondary2ItemFont
		if self:getSettings()["nowplaying4size"] and self:getSettings()["nowplaying4size"] != "" then
			font = tonumber(self:getSettings()["nowplaying4size"])
		end
		local nowplaying4Align = 'center'
		if self:getSettings()["nowplaying4align"] and self:getSettings()["nowplaying4align"] != "" then
			nowplaying4Align = self:getSettings()["nowplaying4align"]
		end
		local width = WH_FILL
		if self:getSettings()["nowplaying4width"] and self:getSettings()["nowplaying4width"] != "" then
			width = tonumber(self:getSettings()["nowplaying4width"])
		end
		nowplaying4Style = {
				position = LAYOUT_NONE,
				x = posx,
				y = posy,
				nowplaying4 = {
					border = {nowPlayingMargin,0,nowPlayingMargin,0},
					w = width,
					font = self:_loadFont(font),
					align = nowplaying4Align,
					h = font,
					fg = nowplaying4Color,
				},
				zOrder = 4,
		}
	end

	local coverStyle = nil
	if self:getSettings()["cover"] or self:getSettings()["backgroundtype"] == 'cover' or self:getSettings()["backgroundtype"] == 'coverblack' then
		local coverXPos = 0
		local coverYPos = 0
		local coverSize = WH_FILL
		if self:getSettings()["coverpositionx"] and self:getSettings()["coverpositionx"] != "" then
			coverXPos = tonumber(self:getSettings()["coverpositionx"])
			coverSize = self:_getCoverSize()
		end
		if self:getSettings()["coverpositiony"] and self:getSettings()["coverpositiony"] != "" then
			coverYPos = tonumber(self:getSettings()["coverpositiony"])
		end
		coverStyle = {
			position = LAYOUT_NONE,
			x = coverXPos,
			y = coverYPos,
			cover = {
				w = coverSize,
				align = 'center',
			},
			zOrder = 2,
		}
	end

	s.window = {
		item1 = item1Style,
		item2 = item2Style,
		item3 = item3Style,
		item4 = item4Style,
		nowplaying2 = nowplaying2Style,
		nowplaying3 = nowplaying3Style,
		nowplaying4 = nowplaying4Style,
		canvas = {
			zOrder = 3,
		},
		cover = coverStyle,
		playstatus = playStatusStyle,
		shufflestatus = shuffleStatusStyle,
		repeatstatus = repeatStatusStyle,
		alarm = alarmStyle,
		alarmtime = alarmtimeStyle,
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
	if self:getSettings()["backgroundtype"] == "solidblack" or self:getSettings()["backgroundtype"] == "coverblack" then
		s.window.bgImg= Tile:fillColor(0x000000ff)
		s.window.background.bgImg= Tile:fillColor(0x000000ff)
	elseif self:getSettings()["backgroundtype"] == "solidwhite" then
		s.window.bgImg= Tile:fillColor(0xffffffff)
		s.window.background.bgImg= Tile:fillColor(0x000000ff)
	elseif self:getSettings()["backgroundtype"] == "solidlightgray" then
		s.window.bgImg= Tile:fillColor(0xccccccff)
		s.window.background.bgImg= Tile:fillColor(0x000000ff)
	elseif self:getSettings()["backgroundtype"] == "soliddarkgray" then
		s.window.bgImg= Tile:fillColor(0x444444ff)
		s.window.background.bgImg= Tile:fillColor(0x000000ff)
	elseif self:getSettings()["backgroundtype"] == "solidgray" then
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


