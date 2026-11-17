-- Bird Blocks: screen layout and scene drawing.
--
-- Two profiles, each with its own palette and proportions:
--   gb   - 160x144, four shades of green, 10x18 field (Tetris on Game Boy)
--   snes - 256x224, coloured pieces, 10x20 field (Tetris on NES)
-- All sizes are virtual pixels; Render multiplies them by the zoom factor.

local ADDON = ...
BirdBlocks = BirdBlocks or {}
local BB = BirdBlocks

local View = {}
View.__index = View
BB.View = View

local floor = math.floor

local function hex(s)
	return {
		tonumber(s:sub(1, 2), 16) / 255,
		tonumber(s:sub(3, 4), 16) / 255,
		tonumber(s:sub(5, 6), 16) / 255,
	}
end

local GB = {
	darkest = hex("0f380f"),
	dark = hex("306230"),
	light = hex("8bac0f"),
	lightest = hex("9bbc0f"),
}

local SNES = {
	black = hex("000000"),
	backdrop = hex("08080f"),
	grid = hex("22222e"),
	frame = hex("b8b8c8"),
	grey = hex("787888"),
	white = hex("f8f8f8"),
}

View.GB = GB
View.SNES = SNES

-- NES Tetris piece colours (the SNES/NES family palette).
local PIECE = {
	I = hex("00e8e8"),
	J = hex("0048f0"),
	L = hex("f08000"),
	O = hex("f0f000"),
	S = hex("00d800"),
	T = hex("c000f0"),
	Z = hex("f00000"),
}
View.PIECE = PIECE

local LAYOUT = {
	gb = {
		w = 160, h = 144,
		field = { x = 32, y = 0, w = 80, h = 144 },
		border = 1,
		panel = { x = 120 },
		cell = 8,
		tile = "gb_block",
		hud = GB.darkest,
		nextCell = 8,
		nextBox = { x = 118, y = 86, w = 40, h = 36 },
	},
	snes = {
		w = 256, h = 224,
		field = { x = 88, y = 24, w = 80, h = 160 },
		border = 4,
		panel = { x = 180 },
		cell = 8,
		tile = "snes_block",
		hud = SNES.white,
		nextCell = 12,
		nextBox = { x = 176, y = 32, w = 64, h = 48 },
	},
}
View.LAYOUT = LAYOUT

function View.new(render, profileID)
	local self = setmetatable({}, View)
	self.render = render
	self:setProfile(profileID or "gb")
	self.frame = 0
	return self
end

function View:setProfile(id)
	self.profile = LAYOUT[id] and id or "gb"
	self.layout = LAYOUT[self.profile]
	self.render:setScreen(self.layout.w, self.layout.h)
	return self
end

function View:screenSize()
	return self.layout.w, self.layout.h
end

--------------------------------------------------------------------------- text

local function pad(n, width)
	local s = tostring(floor(n or 0))
	while #s < width do s = "0" .. s end
	if #s > width then s = s:sub(#s - width + 1) end
	return s
end
View.pad = pad

function View:label(text, x, y, ts, color, layer)
	local c = color or self.layout.hud
	self.render:text(text, x, y, ts or 1, c[1], c[2], c[3], 1, layer)
end

--------------------------------------------------------------------------- pieces

-- Draws a set of cells ({x,y} pairs) with the block tile.
function View:drawCells(cells, ox, oy, cell, color, alpha)
	local r = self.render
	local col = color or { 1, 1, 1 }
	for i = 1, #cells do
		local x, y = cells[i][1], cells[i][2]
		if y >= 0 then
			r:tile(self.layout.tile, ox + x * cell, oy + y * cell, cell, cell,
				col[1], col[2], col[3], alpha or 1)
		end
	end
end

function View:pieceColor(kind)
	if self.profile == "gb" then return { 1, 1, 1 } end
	return PIECE[kind] or { 1, 1, 1 }
end

--------------------------------------------------------------------------- board

function View:drawField(engine, opts)
	local r = self.render
	local L = self.layout
	local f = L.field
	local pb

	if self.profile == "gb" then
		r:rect(0, 0, L.w, L.h, GB.light[1], GB.light[2], GB.light[3], 1)
		r:rect(f.x, f.y, f.w, f.h, GB.lightest[1], GB.lightest[2], GB.lightest[3], 1)
		local g = GB.light
		for x = 1, 9 do
			r:rect(f.x + x * L.cell, f.y, 1, f.h, g[1], g[2], g[3], 1)
		end
		for y = 1, 17 do
			r:rect(f.x, f.y + y * L.cell, f.w, 1, g[1], g[2], g[3], 1)
		end
	else
		r:rect(0, 0, L.w, L.h, SNES.backdrop[1], SNES.backdrop[2], SNES.backdrop[3], 1)
		r:rect(f.x - L.border, f.y - L.border, f.w + L.border * 2, f.h + L.border * 2,
			SNES.frame[1], SNES.frame[2], SNES.frame[3], 1)
		r:rect(f.x, f.y, f.w, f.h, 0, 0, 0, 1)
		-- dot grid, like the NES playfield
		local g = SNES.grid
		for x = 1, 9 do
			r:rect(f.x + x * L.cell, f.y, 1, f.h, g[1], g[2], g[3], 1)
		end
		for y = 1, 19 do
			r:rect(f.x, f.y + y * L.cell, f.w, 1, g[1], g[2], g[3], 1)
		end
	end

	-- settled blocks
	local flashOff = opts and opts.flashOff
	local clearing = {}
	if opts and opts.clearing then
		for i = 1, #opts.clearing do clearing[opts.clearing[i]] = true end
	end
	for y = 0, engine.rows - 1 do
		local row = engine.board[y]
		local hideRow = flashOff and clearing[y]
		if not hideRow then
			for x = 0, engine.cols - 1 do
				local kind = row[x]
				if kind then
					local col = self:pieceColor(kind)
					r:tile(L.tile, f.x + x * L.cell, f.y + y * L.cell, L.cell, L.cell,
						col[1], col[2], col[3], 1)
				end
			end
		end
	end

	-- active piece
	if engine.piece then
		local cells = engine:pieceCells()
		local col = self:pieceColor(engine.piece.type)
		for i = 1, #cells do
			local x, y = cells[i][1], cells[i][2]
			if y >= 0 then
				r:tile(L.tile, f.x + x * L.cell, f.y + y * L.cell, L.cell, L.cell,
					col[1], col[2], col[3], 1)
			end
		end
	end

	-- field frame on top of the blocks so the edges stay clean
	if self.profile == "gb" then
		local b = L.border
		local d = GB.darkest
		r:rect(f.x - b, f.y - b, f.w + b * 2, b, d[1], d[2], d[3], 1)
		r:rect(f.x - b, f.y + f.h, f.w + b * 2, b, d[1], d[2], d[3], 1)
		r:rect(f.x - b, f.y, b, f.h, d[1], d[2], d[3], 1)
		r:rect(f.x + f.w, f.y, b, f.h, d[1], d[2], d[3], 1)
	else
		-- inner 1px outline
		local f2 = SNES.frame
		r:rect(f.x - 1, f.y - 1, f.w + 2, 1, f2[1], f2[2], f2[3], 1)
		r:rect(f.x - 1, f.y + f.h, f.w + 2, 1, f2[1], f2[2], f2[3], 1)
		r:rect(f.x - 1, f.y, 1, f.h, f2[1], f2[2], f2[3], 1)
		r:rect(f.x + f.w, f.y, 1, f.h, f2[1], f2[2], f2[3], 1)
	end
end

function View:drawNext(engine, opts)
	local r = self.render
	local L = self.layout
	local box = L.nextBox
	if self.profile == "gb" then
		r:rect(box.x, box.y, box.w, box.h, GB.darkest[1], GB.darkest[2], GB.darkest[3], 1)
		r:rect(box.x + 1, box.y + 1, box.w - 2, box.h - 2,
			GB.lightest[1], GB.lightest[2], GB.lightest[3], 1)
	else
		r:rect(box.x, box.y, box.w, box.h, SNES.grey[1], SNES.grey[2], SNES.grey[3], 1)
		r:rect(box.x + 1, box.y + 1, box.w - 2, box.h - 2, 0, 0, 0, 1)
	end

	local cells = engine:nextCells()
	if #cells == 0 then return end
	local minx, maxx, miny, maxy = 99, -99, 99, -99
	for i = 1, #cells do
		local x, y = cells[i][1], cells[i][2]
		if x < minx then minx = x end
		if x > maxx then maxx = x end
		if y < miny then miny = y end
		if y > maxy then maxy = y end
	end
	local cell = L.nextCell
	local pw = (maxx - minx + 1) * cell
	local ph = (maxy - miny + 1) * cell
	local ox = box.x + floor((box.w - pw) / 2) - minx * cell
	local oy = box.y + floor((box.h - ph) / 2) - miny * cell
	local col = self:pieceColor(engine.nextType or "T")
	for i = 1, #cells do
		r:tile(L.tile, ox + cells[i][1] * cell, oy + cells[i][2] * cell, cell, cell,
			col[1], col[2], col[3], 1)
	end
end

function View:drawHud(engine, opts)
	local r = self.render
	local L = self.layout
	local px = L.panel.x
	local hi = opts and opts.highScore or 0

	if self.profile == "gb" then
		self:label("SCORE", px, 4, 1)
		self:label(pad(engine.score, 6), px, 12, 1)
		self:label("LINES", px, 30, 1)
		self:label(pad(engine.lines, 3), px, 38, 1)
		self:label("LEVEL", px, 54, 1)
		self:label(pad(engine.level, 2), px, 62, 1)
		self:label("NEXT", px, 76, 1)
		self:drawNext(engine, opts)
		self:label("HI", px, 126, 1)
		self:label(pad(hi, 6), px, 134, 1)
	else
		self:label("NEXT", px, 20, 1)
		self:drawNext(engine, opts)
		self:label("SCORE", px, 88, 1)
		self:label(pad(engine.score, 6), px, 98, 2)
		self:label("LINES", px, 124, 1)
		self:label(pad(engine.lines, 3), px, 134, 2)
		self:label("HI", px, 160, 1)
		self:label(pad(hi, 6), px, 170, 2)
		self:label("LEVEL", px, 196, 1)
		self:label(pad(engine.level, 2), px, 206, 2)
	end
end

function View:drawGame(engine, opts)
	opts = opts or {}
	self:drawField(engine, opts)
	self:drawHud(engine, opts)
end

--------------------------------------------------------------------------- title / overlays

local function birdFrame(frame)
	return (floor(frame / 10) % 2 == 0) and "bird_a" or "bird_b"
end

function View:drawTitle(engine, opts)
	opts = opts or {}
	local r = self.render
	local L = self.layout
	local GBp = self.profile == "gb"
	local frame = opts.frame or 0

	if GBp then
		r:rect(0, 0, L.w, L.h, GB.light[1], GB.light[2], GB.light[3], 1)
		r:rect(0, 0, L.w, 2, GB.darkest[1], GB.darkest[2], GB.darkest[3], 1)
		r:textCentered("HI " .. pad(opts.highScore or 0, 6), L.w / 2, 6, 1, GB.darkest[1], GB.darkest[2], GB.darkest[3], 1)
		r:textCentered("BIRD", L.w / 2, 22, 3, GB.darkest[1], GB.darkest[2], GB.darkest[3], 1)
		r:textCentered("BLOCKS", L.w / 2, 46, 3, GB.darkest[1], GB.darkest[2], GB.darkest[3], 1)
		r:tile(birdFrame(frame), 56, 76, 48, 32, GB.darkest[1], GB.darkest[2], GB.darkest[3], 1)
		if opts.blink ~= false then
			r:textCentered("PRESS ENTER", L.w / 2, 116, 1, GB.darkest[1], GB.darkest[2], GB.darkest[3], 1)
		end
		r:textCentered("LEVEL " .. pad(opts.startLevel or 0, 1), L.w / 2, 130, 1, GB.darkest[1], GB.darkest[2], GB.darkest[3], 1)
	else
		r:rect(0, 0, L.w, L.h, SNES.backdrop[1], SNES.backdrop[2], SNES.backdrop[3], 1)
		r:textCentered("HI " .. pad(opts.highScore or 0, 6), L.w / 2, 8, 1, SNES.grey[1], SNES.grey[2], SNES.grey[3], 1)
		r:textCentered("BIRD", L.w / 2, 24, 4, SNES.white[1], SNES.white[2], SNES.white[3], 1)
		r:textCentered("BLOCKS", L.w / 2, 62, 4, SNES.white[1], SNES.white[2], SNES.white[3], 1)
		r:tile(birdFrame(frame), 80, 100, 96, 64, 1, 1, 1, 1)
		if opts.blink ~= false then
			r:textCentered("PRESS ENTER", L.w / 2, 178, 2, SNES.white[1], SNES.white[2], SNES.white[3], 1)
		end
		r:textCentered("LEVEL " .. pad(opts.startLevel or 0, 1), L.w / 2, 206, 1, SNES.grey[1], SNES.grey[2], SNES.grey[3], 1)
	end
end

function View:drawBox(lines, opts)
	opts = opts or {}
	local r = self.render
	local L = self.layout
	local big = self.profile == "snes"
	local w = big and 208 or 128
	local heights, total = {}, 0
	for i = 1, #lines do
		local line = lines[i]
		local ts = type(line) == "table" and line[2] or 1
		heights[i] = 7 * ts + 4
		total = total + heights[i]
	end
	local h = total + 12
	local x = floor((L.w - w) / 2)
	local y = floor((L.h - h) / 2)
	local fg = big and SNES.white or GB.darkest
	local bg = big and SNES.backdrop or GB.lightest
	local layer = r.LAYER_OVERLAY

	r:rect(x, y, w, h, fg[1], fg[2], fg[3], 1, layer)
	r:rect(x + 2, y + 2, w - 4, h - 4, bg[1], bg[2], bg[3], 1, layer)

	local cy = y + 6
	for i = 1, #lines do
		local line = lines[i]
		local text = type(line) == "table" and line[1] or line
		local ts = type(line) == "table" and line[2] or 1
		r:textCentered(text, L.w / 2, cy, ts, fg[1], fg[2], fg[3], 1, layer)
		cy = cy + heights[i]
	end
end

return View
