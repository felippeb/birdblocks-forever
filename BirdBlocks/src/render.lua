-- Bird Blocks: texture backend.
--
-- Everything the game shows is a quad cut out of one 256x256 TGA atlas
-- (tiles.tga, built by tools/make_assets.py). Quads are recycled: each layer
-- keeps a pool of WoW textures and only the ones used this frame are shown.
-- Pixel art needs NEAREST filtering, no texel snapping, and integer scaling,
-- so coordinates are virtual pixels multiplied by an integer scale.
--
-- This file is mock-friendly: it only touches texture objects handed to it by
-- its parent frame, so tests can capture the draw list instead of drawing.

local ADDON = ...
BirdBlocks = BirdBlocks or {}
local BB = BirdBlocks

local Render = {}
Render.__index = Render
BB.Render = Render

local ATLAS = BirdBlocksAtlas
Render.ATLAS = ATLAS

local floor = math.floor
local ceil = math.ceil

-- layer ids: higher draws on top
Render.LAYER_BG = 1
Render.LAYER_FIELD = 2
Render.LAYER_PIECE = 3
Render.LAYER_HUD = 4
Render.LAYER_OVERLAY = 5

local function newTexture(layer)
	local t = layer.frame:CreateTexture(nil, "ARTWORK")
	if t.SetSnapToPixelGrid then
		t:SetSnapToPixelGrid(false)
		t:SetTexelSnappingBias(0)
	end
	if t.SetBlendMode then t:SetBlendMode("BLEND") end
	t:Hide()
	layer.tex[#layer.tex + 1] = t
	return t
end

function Render.new(parent)
	local self = setmetatable({}, Render)
	self.parent = parent
	self.layers = {}
	self.layerList = {}
	self.scale = 1
	self.vw, self.vh = 160, 144
	self.ox, self.oy = 0, 0
	self.stats = { quads = 0, textures = 0 }
	self.baseLevel = (parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 1
	return self
end

function Render:layer(id)
	local lay = self.layers[id]
	if lay then return lay end
	local f = CreateFrame("Frame", nil, self.parent)
	f:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 0, 0)
	f:SetSize(1, 1)
	f:SetFrameLevel(self.baseLevel + id)
	lay = { frame = f, tex = {}, n = 0, used = 0, id = id }
	self.layers[id] = lay
	self.layerList[#self.layerList + 1] = lay
	table.sort(self.layerList, function(a, b) return a.id < b.id end)
	return lay
end

function Render:setScreen(w, h)
	if self.vw == w and self.vh == h then return end
	self.vw, self.vh = w, h
	self:invalidate()
end

function Render:setScale(scale)
	scale = floor(scale + 0.5)
	if scale < 1 then scale = 1 end
	if scale == self.scale then return end
	self.scale = scale
	self:invalidate()
end

function Render:getScale() return self.scale end
function Render:pixelWidth() return self.vw * self.scale end
function Render:pixelHeight() return self.vh * self.scale end

-- Drop cached positions so the next frame re-anchors everything.
function Render:invalidate()
	for _, lay in ipairs(self.layerList) do
		for _, t in ipairs(lay.tex) do
			t.dx1, t.dy1, t.dw, t.dh = nil, nil, nil, nil
		end
	end
end

function Render:resizeFrame()
	if self.parent.SetSize then
		self.parent:SetSize(self:pixelWidth(), self:pixelHeight())
	end
end

function Render:beginFrame()
	for _, lay in ipairs(self.layerList) do
		lay.n = 0
	end
	self.stats.quads = 0
end

function Render:finish()
	for _, lay in ipairs(self.layerList) do
		for i = lay.n + 1, lay.used do
			local t = lay.tex[i]
			if t and t.shown then
				t.shown = false
				t:Hide()
			end
		end
		lay.used = lay.n
	end
end

local function anchor(lay, t, x, y, w, h, scale, ox, oy)
	local px = floor(ox + x * scale + 0.5)
	local py = floor(oy + y * scale + 0.5)
	if t.dx1 ~= px or t.dy1 ~= py then
		t.dx1, t.dy1 = px, py
		t:SetPoint("TOPLEFT", lay.frame, "TOPLEFT", px, -py)
	end
	if t.dw ~= w or t.dh ~= h then
		t.dw, t.dh = w, h
		t:SetSize(w, h)
	end
end

-- One atlas tile. `name` is a key in BirdBlocksAtlas.slots.
function Render:tile(name, x, y, w, h, r, g, b, a)
	local rect = ATLAS.slots[name]
	if not rect then return end
	local lay = self:layer(self.LAYER_FIELD)
	local n = lay.n + 1
	lay.n = n
	local t = lay.tex[n] or newTexture(lay)
	local s = self.scale
	local pw, ph = w * s, h * s
	anchor(lay, t, x, y, pw, ph, s, self.ox, self.oy)
	if not t.atlas then
		t.atlas = true
		t:SetTexture(ATLAS.path, "CLAMP", "CLAMP", "NEAREST")
	end
	t:SetTexCoord(rect[1], rect[2], rect[1], rect[4], rect[3], rect[2], rect[3], rect[4])
	if t.dr ~= r or t.dg ~= g or t.db ~= b or t.da ~= a then
		t.dr, t.dg, t.db, t.da = r, g, b, a
		t:SetVertexColor(r, g, b, a)
	end
	if not t.shown then
		t.shown = true
		t:Show()
	end
	self.stats.quads = self.stats.quads + 1
end

-- Solid colour rectangle (the "shell" around the pixel art).
function Render:rect(x, y, w, h, r, g, b, a, layerID)
	local lay = self:layer(layerID or self.LAYER_BG)
	local n = lay.n + 1
	lay.n = n
	local t = lay.tex[n] or newTexture(lay)
	local s = self.scale
	anchor(lay, t, x, y, w * s, h * s, s, self.ox, self.oy)
	if t.atlas then
		t.atlas = nil
		t:SetTexCoord(0, 1, 0, 1)
	end
	if t.dr ~= r or t.dg ~= g or t.db ~= b or t.da ~= a then
		t.dr, t.dg, t.db, t.da = r, g, b, a
		t:SetColorTexture(r, g, b, a)
		t:SetVertexColor(1, 1, 1, 1)
	end
	if not t.shown then
		t.shown = true
		t:Show()
	end
	self.stats.quads = self.stats.quads + 1
end

-- One 5x7 glyph from the atlas. ts is an integer size multiplier.
function Render:glyph(ch, x, y, ts, r, g, b, a, layerID)
	local rect = ATLAS.slots["glyph:" .. ch]
	if not rect then return end
	local lay = self:layer(layerID or self.LAYER_HUD)
	local n = lay.n + 1
	lay.n = n
	local t = lay.tex[n] or newTexture(lay)
	local s = self.scale * (ts or 1)
	anchor(lay, t, x, y, 8 * s, 8 * s, self.scale, self.ox, self.oy)
	if not t.atlas then
		t.atlas = true
		t:SetTexture(ATLAS.path, "CLAMP", "CLAMP", "NEAREST")
	end
	t:SetTexCoord(rect[1], rect[2], rect[1], rect[4], rect[3], rect[2], rect[3], rect[4])
	if t.dr ~= r or t.dg ~= g or t.db ~= b or t.da ~= a then
		t.dr, t.dg, t.db, t.da = r, g, b, a
		t:SetVertexColor(r, g, b, a)
	end
	if not t.shown then
		t.shown = true
		t:Show()
	end
	self.stats.quads = self.stats.quads + 1
end

Render.CHAR_ADVANCE = 6

function Render:measure(text, ts)
	ts = ts or 1
	return #text * self.CHAR_ADVANCE * ts
end

function Render:text(text, x, y, ts, r, g, b, a, layerID)
	ts = ts or 1
	text = tostring(text or "")
	local cx = x
	for i = 1, #text do
		local ch = text:sub(i, i)
		if ch ~= " " then self:glyph(ch, cx, y, ts, r, g, b, a, layerID) end
		cx = cx + self.CHAR_ADVANCE * ts
	end
	return cx - x
end

function Render:textCentered(text, cx, y, ts, r, g, b, a, layerID)
	local w = self:measure(text, ts)
	self:text(text, cx - w / 2, y, ts, r, g, b, a, layerID)
end

return Render
