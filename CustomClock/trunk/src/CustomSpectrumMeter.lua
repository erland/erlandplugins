local tostring, tonumber = tostring, tonumber

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
local log           = require("jive.utils.log").logger("audio.decode")

local FRAME_RATE    = jive.ui.FRAME_RATE


module(...)
oo.class(_M, Icon)


function __init(self, style, channels)
	local obj = oo.rawnew(self, Icon(style))

	obj.val = { 0, 0 }

	obj:addAnimation(function() obj:reDraw() end, FRAME_RATE)

	obj.channels = "left+right"
	if channels and channels != "" then
		obj.channels=channels
	end

	obj.sizes = {}

	obj.colors = {}
	obj.colors["bar"] = 0x14bcbcff
	obj.colors["cap"] = 0xb456a1ff

	return obj
end


function _skin(self)
	Icon._skin(self)
end

function setAttr(self, id, size)
	self.sizes[id] = size
end

function setColor(self, id, color)
	self.colors[id] = color
end

function _layout(self)
	local x,y,w,h = self:getBounds()
	local l,t,r,b = self:getPadding()

	-- When used in NP screen _layout gets called with strange values
	if (w <= 0 or w > 480) and (h <= 0 or h > 272) then
		return
	end

	self.capHeight = {}
	self.capSpace = {}

	self.channelWidth = {}
	self.channelFlipped = {}
	self.barsInBin = {}
	self.barWidth = {}
	self.barSpace = {}
	self.binSpace = {}
	self.clipSubbands = {}

	if self.channels == "mono" then
		self.isMono =  1
	else
		self.isMono =  0
	end

	self.capHeight = self.sizes["capHeight"] or 4
	self.capSpace = self.sizes["capSpace"] or 4
	self.channelFlipped = {0,1} -- self:styleValue("channelFlipped")
	self.barsInBin = self.sizes["barsInBin"] or 2
	self.barWidth = self.sizes["barWidth"] or 1
	self.barSpace = self.sizes["barSpace"] or 3
	self.binSpace = self.sizes["binSpace"] or 6
	self.clipSubbands = self.sizes["clipSubbands"] or 1

	if self.barsInBin < 1 then
		self.barsInBin = 1
	end
	if self.barWidth < 1 then
		self.barWidth = 1
	end

	local barSize = self.barWidth * self.barsInBin + self.barSpace * (self.barsInBin - 1) + self.binSpace

	self.channelWidth = (w - l - r) / 2

	local numBars = {}

	numBars = decode:spectrum_init(
		self.isMono,

		self.channelWidth,
		self.channelFlipped[1],
		barSize,
		self.clipSubbands,

		self.channelWidth,
		self.channelFlipped[2],
		barSize,
		self.clipSubbands
	)

	local barHeight = h - t - b - self.capHeight - self.capSpace

	-- max bin value from C code is 31
	self.barHeightMulti =  barHeight / 31

	self.x1 = x + l + self.channelWidth - numBars[1] * barSize
	self.x2 = x + l + self.channelWidth + self.binSpace

	self.y = y + h - b

	self.cap = { {}, {} }
	for i = 1, numBars[1] do
		self.cap[1][i] = 0
	end

	for i = 1, numBars[2] do
		self.cap[2][i] = 0
	end

end


function draw(self, surface)
-- Black background instead of image
--	self.bgImg:blit(surface, self:getBounds())
	local x, y, w, h = self:getBounds()
	if self.colors["background"] then
		surface:filledRectangle(x, y, x + w, y + h, self.colors["background"])
	end


	local bins = { {}, {}}

	bins[1], bins[2] = decode:spectrum()

	if string.find(self.channels,'^left') or self.channels == "mono" then
		_drawBins(
			self, surface, bins, 1, self.x1, self.y, self.barsInBin,
			self.barWidth, self.barSpace, self.binSpace,
			self.barHeightMulti, self.capHeight, self.capSpace
		)
	end
	if string.find(self.channels,'right$') then
		_drawBins(
			self, surface, bins, 2, self.x2, self.y, self.barsInBin,
			self.barWidth, self.barSpace, self.binSpace,
			self.barHeightMulti, self.capHeight, self.capSpace
		)
	end
end


function _drawBins(self, surface, bins, ch, x, y, barsInBin, barWidth, barSpace, binSpace, barHeightMulti, capHeight, capSpace)
	local bch = bins[ch]
	local cch = self.cap[ch]
	local barSize = barWidth + barSpace

	for i = 1, #bch do
		-- Uncomment to simulate in SqueezePlay
		-- bch[i] = math.random(31)
		bch[i] = bch[i] * barHeightMulti

		-- bar
		if bch[i] > 0 and self.colors["bar"] then
			for k = 0, barsInBin - 1 do
				surface:filledRectangle(
					x + (k * barSize),
					y,
					x + (barWidth - 1) + (k * barSize),
					y - bch[i] + 1,
					self.colors["bar"]
				)
			end
		end
		
		if bch[i] >= cch[i] then
			cch[i] = bch[i]
		elseif cch[i] > 0 then
			cch[i] = cch[i] - barHeightMulti
			if cch[i] < 0 then
				cch[i] = 0
			end
		end

		-- cap
		if capHeight > 0 and self.colors["cap"] then
			for k = 0, barsInBin - 1 do
				surface:filledRectangle(
					x + (k * barSize),
					y - cch[i] - capSpace,
					x + (barWidth - 1) + (k * barSize),
					y - cch[i] - capHeight - capSpace,
					self.colors["cap"]
				)
			end
		end

		x = x + barWidth * barsInBin + barSpace * (barsInBin - 1) + binSpace
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

