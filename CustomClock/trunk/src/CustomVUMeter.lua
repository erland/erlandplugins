local oo            = require("loop.simple")
local math          = require("math")

local Framework     = require("jive.ui.Framework")
local Icon          = require("jive.ui.Icon")
local Surface       = require("jive.ui.Surface")
local Timer         = require("jive.ui.Timer")
local Widget        = require("jive.ui.Widget")

local string           = require("jive.utils.string")
local decode        = require("squeezeplay.decode")

local debug         = require("jive.utils.debug")
local log           = require("jive.utils.log").logger("applet.CustomClock")

local FRAME_RATE    = jive.ui.FRAME_RATE

module(...)
oo.class(_M, Icon)


function __init(self, style, mode, channels)
	local obj = oo.rawnew(self, Icon(style))

	obj.mode = mode

	obj.cap = { 0, 0 }

	obj:addAnimation(function() obj:reDraw() end, FRAME_RATE)

	obj.images = nil

	obj.channels = channels or "left+right"

	return obj
end


function _skin(self)
	Icon._skin(self)
end


function setImage(self, id, image)
	if self.images == nil then
		self.images = {}
	end
	self.images[id] = image
end

function _layout(self)
	local x,y,w,h = self:getBounds()
	local l,t,r,b = self:getPadding()
	-- When used in NP screen _layout gets called with strange values
	if (w <= 0 or w > 480) and (h <= 0 or h > 272) then
		return
	end

	if self.mode == "digital" and self.images and self.images["tickon"] then
		self.w = w - l - r
		self.h = h - t - b

		local tw,th = self.images["tickon"]:getSize()

		self.x1 = x + l + ((self.w - tw * 2) / 3)
		self.x2 = x + l + ((self.w - tw * 2) / 3) * 2 + tw

		self.bars = self.h / th
		self.y = y + t + (self.bars * th)

	elseif self.mode == "analog" then
		self.x1 = x
		self.x2 = x + (w / 2)
		self.y = y
		self.w = w / 2
		self.h = h
	end
end


function draw(self, surface)
	if self.images ~= nil then
		if self.mode == "spectrum" then
			self.images["background"]:blit(surface, self:getBounds())
		end

		local sampleAcc = decode:vumeter()
		-- Uncomment to simulate in SqueezePlay
		-- sampleAcc = {}
		-- sampleAcc[1] = math.random(3227)
		-- sampleAcc[2] = math.random(3227)

		if string.find(self.channels,'^left') or self.channels == "mono" then
			_drawMeter(self, surface, sampleAcc, 1, self.x1, self.y, self.w, self.h)
		end
		if string.find(self.channels,'right$') then
			if string.find(self.channels,"^right") then
				_drawMeter(self, surface, sampleAcc, 2, self.x1, self.y, self.w, self.h)
			else
				_drawMeter(self, surface, sampleAcc, 2, self.x2, self.y, self.w, self.h)
			end
		end
	end
end


-- FIXME dynamic based on number of bars
local RMS_MAP = {
	0, 2, 5, 7, 10, 21, 33, 45, 57, 82, 108, 133, 159, 200, 
	242, 284, 326, 387, 448, 509, 570, 652, 735, 817, 900, 
	1005, 1111, 1217, 1323, 1454, 1585, 1716, 1847, 2005, 
	2163, 2321, 2480, 2666, 2853, 3040, 3227, 
}


function _drawMeter(self, surface, sampleAcc, ch, x, y, w, h)
	local val = 1
	for i = #RMS_MAP, 1, -1 do
		if sampleAcc[ch] > RMS_MAP[i] then
			val = i
			break
		end
	end

	-- FIXME when rms map scaled
	val = math.floor(val / 2)
	if val >= self.cap[ch] then
		self.cap[ch] = val
	elseif self.cap[ch] > 0 then
		if self.mode == "digital" then
			self.cap[ch] = self.cap[ch] - 0.5
		else
			self.cap[ch] = self.cap[ch] - 1
		end
	end

	if self.mode == "digital" and self.images ~= nil and self.bars and self.images["tickon"] then
		local tw,th = self.images["tickon"]:getSize()

		local it = nil
		local last = true
		for i = 1, self.bars do
			it = i*272/self.h
			if it >= self.cap[ch] and last and self.images["tickcap"] ~= nil then
				self.images["tickcap"]:blit(surface, x, y)
				last = false
			elseif it < val and self.images["tickon"] ~= nil then
				self.images["tickon"]:blit(surface, x, y)
			elseif self.images["tickoff"] ~= nil then
				self.images["tickoff"]:blit(surface, x, y)
			end

			y = y - th
		end

	elseif self.mode == "analog" and self.images ~= nil and self.images["background"] ~= nil then

--		local x,y,w,h = self:getBounds()

		if ch == 1 then
			self.images["background"]:blitClip(self.cap[ch] * w, y, w, h, surface, x, y)
		else
			self.images["background"]:blitClip(self.cap[ch] * w, y, w, h, surface, x, y)
		end
	end
end


--[[

=head1 LICENSE

Copyright 2010, Erland Isaksson (erland_i@hotmail.com)
Copyright 2010, Logitech, inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Logitech nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL LOGITECH, INC BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut
--]]

