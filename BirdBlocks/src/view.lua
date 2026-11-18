-- Bird Blocks: screen layout and scene drawing.
--
-- Three profiles, each with its own palette and proportions:
--   gb     - 160x144, four shades of green, 10x18 field (Tetris on Game Boy)
--   snes   - 256x224, coloured pieces, 10x20 field (Tetris on NES)
--   modern - 320x240, neon arcade cabinet, 10x20 field, hold + 3-piece queue
-- All sizes are virtual pixels; Render multiplies them by the zoom factor.

local ADDON = ...
BirdBlocks = BirdBlocks or {}
local BB = BirdBlocks

local View = {}
View.__index = View
BB.View = View

local floor, min, max = math.floor, math.min, math.max

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

-- The neon cabinet: near-black screen, magenta well, amber highlights.
local NEON = {
	bg = hex("02040f"),
	panel = hex("050a1c"),
	ink = hex("ffffff"),
	dim = hex("8899aa"),
	amber = hex("ffcc55"),
	magenta = hex("ff00ff"),
	magenta_hot = hex("ff99ff"),
	cyan = hex("00ffff"),
	green = hex("00ff88"),
}

View.GB = GB
View.SNES = SNES
View.NEON = NEON

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

-- Neon arcade palette, one per piece, from the cabinet build.
local NEON_PIECE = {
	I = hex("00ffff"),
	J = hex("5a8bff"),
	L = hex("ff9f43"),
	O = hex("ffcc55"),
	S = hex("00ff00"),
	T = hex("ff00ff"),
	Z = hex("ff5f6d"),
}
View.NEON_PIECE = NEON_PIECE

local LAYOUT = {
	gb = {
		w = 160, h = 144,
		field = { x = 32, y = 0, w = 80, h = 144 },
		border = 1,
		panel = { x = 120 },
		cell = 8,
		tile = "gb_block",
		wellTile = "gb_well",
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
		wellTile = "snes_well",
		hud = SNES.white,
		nextCell = 12,
		nextBox = { x = 176, y = 32, w = 64, h = 48 },
	},
	modern = {
		w = 320, h = 240,
		field = { x = 110, y = 32, w = 100, h = 200 },
		border = 2,
		panel = { x = 16 },
		cell = 10,
		tile = "neon_block",
		ghostTile = "neon_ghost",
		wellTile = "neon_well",
		hud = NEON.ink,
		nextCell = 8,
		nextBox = { x = 240, y = 44, w = 64, h = 96 },
		holdBox = { x = 16, y = 44, w = 64, h = 56 },
	},
}
View.LAYOUT = LAYOUT

function View.new(render, profileID)
	local self = setmetatable({}, View)
	self.render = render
	self:setProfile(profileID or "modern")
	self.frame = 0
	self:resetFx()
	return self
end

function View:setProfile(id)
	self.profile = LAYOUT[id] and id or "modern"
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

function View:labelRight(text, right, y, ts, color, layer)
	local c = color or self.layout.hud
	local w = self.render:measure(text, ts or 1)
	self.render:text(text, right - w, y, ts or 1, c[1], c[2], c[3], 1, layer)
end

--------------------------------------------------------------------------- pieces

-- Draws a set of cells ({x,y} pairs) with the block tile.
function View:drawCells(cells, ox, oy, cell, color, alpha, tile)
	local r = self.render
	local col = color or { 1, 1, 1 }
	for i = 1, #cells do
		local x, y = cells[i][1], cells[i][2]
		if y >= 0 then
			r:tile(tile or self.layout.tile, ox + x * cell, oy + y * cell, cell, cell,
				col[1], col[2], col[3], alpha or 1)
		end
	end
end

function View:pieceColor(kind)
	if kind == "G" then
		-- Prefilled B-Type garbage: steel in the neon cabinet, grey on SNES.
		if self.profile == "modern" then return { 0.42, 0.48, 0.58 } end
		if self.profile == "gb" then return { 1, 1, 1 } end
		return { 0.55, 0.55, 0.60 }
	end
	if self.profile == "gb" then return { 1, 1, 1 } end
	if self.profile == "modern" then return NEON_PIECE[kind] or NEON.ink end
	return PIECE[kind] or { 1, 1, 1 }
end

--------------------------------------------------------------------------- effects

function View:resetFx()
	self.fx = { parts = {}, floats = {}, shake = 0, banner = 0, bannerLevel = 0 }
	return self.fx
end

function View:burst(x, y, count, color)
	local fx = self.fx
	local c = color or NEON.amber
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + (i % 7) * 0.31
		local speed = 30 + (i % 11) * 14
		fx.parts[#fx.parts + 1] = {
			x = x, y = y,
			vx = math.cos(a) * speed,
			vy = math.sin(a) * speed - 20,
			life = 0.35 + (i % 5) * 0.08,
			c = c,
		}
	end
end

function View:floater(x, y, text, color)
	self.fx.floats[#self.fx.floats + 1] = {
		x = x, y = y, text = text, life = 1.1, c = color or NEON.amber,
	}
end

-- Called from the UI when the engine reports something worth celebrating.
function View:celebrate(event, engine)
	if self.profile ~= "modern" then return end
	local fx = self.fx
	local f = self.layout.field
	local cx = f.x + f.w / 2
	if event.type == "line" then
		if event.tetris then
			fx.shake = 0.32
			self:floater(cx, f.y + f.h * 0.42, "QUAD!", NEON.amber)
			self:burst(cx, f.y + f.h * 0.55, 40, NEON.cyan)
		elseif event.tspin then
			self:floater(cx, f.y + f.h * 0.42, "T-SPIN!", NEON.magenta_hot)
			self:burst(cx, f.y + f.h * 0.6, 18, NEON.magenta_hot)
		elseif event.count >= 2 then
			self:floater(cx, f.y + f.h * 0.45, ({"", "", "DOUBLE", "TRIPLE"})[event.count] or "", NEON.cyan)
		end
	elseif event.type == "level" then
		fx.banner = 1.2
		fx.bannerLevel = event.level
	elseif event.type == "harddrop" and event.rows and event.rows >= 8 then
		fx.shake = max(fx.shake or 0, 0.12)
	end
end

function View:updateFx(dt)
	local fx = self.fx
	if not fx then return end
	if fx.shake > 0 then fx.shake = max(0, fx.shake - dt) end
	if fx.banner > 0 then fx.banner = max(0, fx.banner - dt) end
	for i = #fx.parts, 1, -1 do
		local p = fx.parts[i]
		p.life = p.life - dt
		if p.life <= 0 then
			table.remove(fx.parts, i)
		else
			p.x = p.x + p.vx * dt
			p.y = p.y + p.vy * dt
			p.vy = p.vy + 220 * dt
		end
	end
	for i = #fx.floats, 1, -1 do
		local f = fx.floats[i]
		f.life = f.life - dt
		if f.life <= 0 then
			table.remove(fx.floats, i)
		else
			f.y = f.y - 26 * dt
		end
	end
end

function View:drawFx()
	local fx = self.fx
	if not fx then return end
	local r = self.render
	local layer = r.LAYER_HUD
	for i = 1, #fx.parts do
		local p = fx.parts[i]
		local a = min(1, p.life * 2.5)
		r:rect(p.x, p.y, 2, 2, p.c[1], p.c[2], p.c[3], a, layer)
	end
	for i = 1, #fx.floats do
		local f = fx.floats[i]
		local a = min(1, f.life * 1.6)
		r:textCentered(f.text, f.x, f.y, 2, f.c[1], f.c[2], f.c[3], a, layer)
	end
	if fx.banner > 0 and floor(fx.banner * 8) % 2 == 0 then
		local L = self.layout
		r:textCentered("LEVEL " .. tostring(fx.bannerLevel), L.w / 2, L.field.y + 60, 4,
			NEON.cyan[1], NEON.cyan[2], NEON.cyan[3], 1, layer)
	end
end

--------------------------------------------------------------------------- board

function View:drawField(engine, opts)
	local r = self.render
	local L = self.layout
	local f = L.field
	local cell = L.cell

	-- backdrop
	if self.profile == "modern" then
		r:rect(0, 0, L.w, L.h, NEON.bg[1], NEON.bg[2], NEON.bg[3], 1)
	elseif self.profile == "gb" then
		r:rect(0, 0, L.w, L.h, GB.light[1], GB.light[2], GB.light[3], 1)
	else
		r:rect(0, 0, L.w, L.h, SNES.backdrop[1], SNES.backdrop[2], SNES.backdrop[3], 1)
		r:rect(f.x - L.border, f.y - L.border, f.w + L.border * 2, f.h + L.border * 2,
			SNES.frame[1], SNES.frame[2], SNES.frame[3], 1)
	end

	-- The well is one tile per cell. The grid line is part of the tile, so it
	-- stays exactly one pixel wide at any zoom and cannot alias away.
	for y = 0, engine.rows - 1 do
		local ty = f.y + y * cell
		for x = 0, engine.cols - 1 do
			r:tile(L.wellTile, f.x + x * cell, ty, cell, cell, 1, 1, 1, 1)
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
					r:tile(L.tile, f.x + x * cell, f.y + y * cell, cell, cell,
						col[1], col[2], col[3], 1)
				end
			end
		end
	end

	-- landing preview, under the piece
	if L.ghostTile and engine.profile and engine.profile.ghost then
		local ghost = engine:ghostCells()
		if #ghost > 0 then
			local col = NEON.amber
			self:drawCells(ghost, f.x, f.y, cell, col, 0.9, L.ghostTile)
		end
	end

	-- active piece
	if engine.piece then
		local cells = engine:pieceCells()
		local col = self:pieceColor(engine.piece.type)
		self:drawCells(cells, f.x, f.y, cell, col, 1)
	end

	-- white flash across rows that are about to disappear
	if opts and opts.clearing and flashOff == false then
		for i = 1, #opts.clearing do
			local y = opts.clearing[i]
			local col = self.profile == "modern" and NEON.ink or SNES.white
			if self.profile == "gb" then col = GB.darkest end
			r:rect(f.x + 1, f.y + y * cell + 1, f.w - 2, cell - 2, col[1], col[2], col[3], 1)
		end
	end

	-- field frame on top of the blocks so the edges stay clean
	if self.profile == "modern" then
		local b = L.border
		local m = NEON.magenta
		r:rect(f.x - b, f.y - b, f.w + b * 2, b, m[1], m[2], m[3], 1)
		r:rect(f.x - b, f.y + f.h, f.w + b * 2, b, m[1], m[2], m[3], 1)
		r:rect(f.x - b, f.y, b, f.h, m[1], m[2], m[3], 1)
		r:rect(f.x + f.w, f.y, b, f.h, m[1], m[2], m[3], 1)
		-- brighter ground line, like the cabinet build
		local g = NEON.magenta_hot
		r:rect(f.x, f.y + f.h - b, f.w, b, g[1], g[2], g[3], 1)
	elseif self.profile == "gb" then
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

-- Fits a piece's cells into a box, returns the origin to draw them at.
local function boxed(cells, cell, box)
	if #cells == 0 then return nil end
	local minx, maxx, miny, maxy = 99, -99, 99, -99
	for i = 1, #cells do
		local x, y = cells[i][1], cells[i][2]
		if x < minx then minx = x end
		if x > maxx then maxx = x end
		if y < miny then miny = y end
		if y > maxy then maxy = y end
	end
	local pw = (maxx - minx + 1) * cell
	local ph = (maxy - miny + 1) * cell
	return box.x + floor((box.w - pw) / 2) - minx * cell,
		box.y + floor((box.h - ph) / 2) - miny * cell
end

function View:drawNext(engine, opts)
	local r = self.render
	local L = self.layout
	local box = L.nextBox
	local cell = L.nextCell

	if self.profile == "modern" then
		r:rect(box.x, box.y, box.w, box.h, 0, 0, 0, 1)
		local m = NEON.magenta
		r:rect(box.x, box.y, box.w, 1, m[1], m[2], m[3], 1)
		r:rect(box.x, box.y + box.h - 1, box.w, 1, m[1], m[2], m[3], 1)
		r:rect(box.x, box.y, 1, box.h, m[1], m[2], m[3], 1)
		r:rect(box.x + box.w - 1, box.y, 1, box.h, m[1], m[2], m[3], 1)
		local count = engine:queueSize()
		local slotH = floor(box.h / max(1, count))
		for i = 1, count do
			local cells = engine:queueCells(i)
			local slot = { x = box.x, y = box.y + (i - 1) * slotH + 2, w = box.w, h = slotH - 4 }
			local ox, oy = boxed(cells, cell, slot)
			if ox then
				local kind = engine:queueType(i)
				local col = self:pieceColor(kind)
				self:drawCells(cells, ox - 0, oy - 0, cell, col, 1 - (i - 1) * 0.18)
			end
		end
		return
	end

	if self.profile == "gb" then
		r:rect(box.x, box.y, box.w, box.h, GB.darkest[1], GB.darkest[2], GB.darkest[3], 1)
		r:rect(box.x + 1, box.y + 1, box.w - 2, box.h - 2,
			GB.lightest[1], GB.lightest[2], GB.lightest[3], 1)
	else
		r:rect(box.x, box.y, box.w, box.h, SNES.grey[1], SNES.grey[2], SNES.grey[3], 1)
		r:rect(box.x + 1, box.y + 1, box.w - 2, box.h - 2, 0, 0, 0, 1)
	end

	local cells = engine:nextCells()
	local ox, oy = boxed(cells, cell, box)
	if not ox then return end
	local col = self:pieceColor(engine.nextType or "T")
	for i = 1, #cells do
		r:tile(L.tile, ox + cells[i][1] * cell, oy + cells[i][2] * cell, cell, cell,
			col[1], col[2], col[3], 1)
	end
end

function View:drawHold(engine)
	local L = self.layout
	if not L.holdBox then return end
	local r = self.render
	local box = L.holdBox
	local cell = L.nextCell
	local dim = NEON.amber
	local active = engine and engine.canHold

	r:rect(box.x, box.y, box.w, box.h, 0, 0, 0, 1)
	local edge = active and NEON.magenta or NEON.dim
	r:rect(box.x, box.y, box.w, 1, edge[1], edge[2], edge[3], 1)
	r:rect(box.x, box.y + box.h - 1, box.w, 1, edge[1], edge[2], edge[3], 1)
	r:rect(box.x, box.y, 1, box.h, edge[1], edge[2], edge[3], 1)
	r:rect(box.x + box.w - 1, box.y, 1, box.h, edge[1], edge[2], edge[3], 1)

	local cells = engine and engine:holdCells() or {}
	local ox, oy = boxed(cells, cell, box)
	if not ox then return end
	local kind = engine and engine.holdType
	local col = kind and self:pieceColor(kind) or dim
	local alpha = engine and engine.canHold and 1 or 0.45
	for i = 1, #cells do
		r:tile(L.tile, ox + cells[i][1] * cell, oy + cells[i][2] * cell, cell, cell,
			col[1], col[2], col[3], alpha)
	end
end

function View:drawHud(engine, opts)
	local r = self.render
	local L = self.layout
	local px = L.panel.x
	local hi = opts and opts.highScore or 0

	if self.profile == "modern" then
		self:label("SCORE", 8, 4, 1, NEON.dim)
		self:label(pad(engine.score, 6), 8, 13, 2, NEON.ink)
		self:labelRight("HI " .. pad(hi, 6), L.w - 8, 13, 2, NEON.amber)
		self:label("HOLD", px, 30, 1, NEON.dim)
		self:drawHold(engine)
		self:label("LINES", px, 108, 1, NEON.dim)
		local lineText, lineScale = pad(engine.lines, 3), 2
		if engine.goal then
			lineText = lineText .. "/" .. engine.goal
			lineScale = 1
		end
		self:label(lineText, px, 117, lineScale, NEON.ink)
		self:label("LEVEL", px, 146, 1, NEON.dim)
		self:label(pad(engine.level, 2), px, 155, 2, NEON.amber)
		self:label("NEXT", L.nextBox.x, 30, 1, NEON.dim)
		self:drawNext(engine, opts)
		self:label("SPACE DROP  C HOLD", px, 196, 1, NEON.dim)
		if engine.goal then
			self:label("BROKEN  GOAL " .. engine.goal, px, 208, 1, NEON.amber)
		end
		return
	end

	if self.profile == "gb" then
		self:label("SCORE", px, 4, 1)
		self:label(pad(engine.score, 6), px, 12, 1)
		self:label("LINES", px, 30, 1)
		self:label(pad(engine.lines, 3) .. (engine.goal and ("/" .. engine.goal) or ""), px, 38, 1)
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
		self:label(pad(engine.lines, 3) .. (engine.goal and ("/" .. engine.goal) or ""), px, 134,
			engine.goal and 1 or 2)
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
	if self.profile == "modern" then self:drawFx() end
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

	if self.profile == "modern" then
		r:rect(0, 0, L.w, L.h, NEON.bg[1], NEON.bg[2], NEON.bg[3], 1)
		-- cabinet edge and a perspective-ish floor, entirely out of quads
		local m = NEON.magenta
		r:rect(0, 0, L.w, 2, m[1], m[2], m[3], 1)
		r:rect(0, L.h - 2, L.w, 2, m[1], m[2], m[3], 1)
		r:rect(0, 0, 2, L.h, m[1], m[2], m[3], 1)
		r:rect(L.w - 2, 0, 2, L.h, m[1], m[2], m[3], 1)
		for i = 1, 7 do
			local y = L.h - 8 - i * 7
			local a = 0.22 * (1 - i / 8)
			r:rect(16, y, L.w - 32, 1, m[1], m[2], m[3], a)
		end
		r:textCentered("HI " .. pad(opts.highScore or 0, 6), L.w / 2, 12, 1, NEON.amber[1], NEON.amber[2], NEON.amber[3], 1)
		r:textCentered("BIRD", L.w / 2, 30, 5, NEON.cyan[1], NEON.cyan[2], NEON.cyan[3], 1)
		r:textCentered("BLOCKS", L.w / 2, 74, 5, NEON.magenta[1], NEON.magenta[2], NEON.magenta[3], 1)
		r:textCentered("NEON BLOCK CLASSIC", L.w / 2, 116, 1, NEON.dim[1], NEON.dim[2], NEON.dim[3], 1)
		r:tile(birdFrame(frame), 136, 126, 48, 32, NEON.cyan[1], NEON.cyan[2], NEON.cyan[3], 1)
		if opts.blink ~= false then
			r:textCentered("PRESS ENTER", L.w / 2, 172, 2, NEON.amber[1], NEON.amber[2], NEON.amber[3], 1)
		end
		r:textCentered("SPEED " .. pad(opts.speed or 5, 2) .. "  " ..
			(opts.broken and "BROKEN" or "NORMAL") .. "   ARROWS MOVE  UP ROTATE",
			L.w / 2, 196, 1, NEON.dim[1], NEON.dim[2], NEON.dim[3], 1)
		r:textCentered("SPACE DROP  C HOLD  B MODE  P PAUSE  M MUSIC", L.w / 2, 208, 1,
			NEON.dim[1], NEON.dim[2], NEON.dim[3], 1)
		return
	end

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
		r:textCentered("SPEED " .. tostring(opts.speed or 5) ..
			(opts.broken and "  BROKEN" or ""), L.w / 2, 130, 1, GB.darkest[1], GB.darkest[2], GB.darkest[3], 1)
	else
		r:rect(0, 0, L.w, L.h, SNES.backdrop[1], SNES.backdrop[2], SNES.backdrop[3], 1)
		r:textCentered("HI " .. pad(opts.highScore or 0, 6), L.w / 2, 8, 1, SNES.grey[1], SNES.grey[2], SNES.grey[3], 1)
		r:textCentered("BIRD", L.w / 2, 24, 4, SNES.white[1], SNES.white[2], SNES.white[3], 1)
		r:textCentered("BLOCKS", L.w / 2, 62, 4, SNES.white[1], SNES.white[2], SNES.white[3], 1)
		r:tile(birdFrame(frame), 80, 100, 96, 64, 1, 1, 1, 1)
		if opts.blink ~= false then
			r:textCentered("PRESS ENTER", L.w / 2, 178, 2, SNES.white[1], SNES.white[2], SNES.white[3], 1)
		end
		r:textCentered("SPEED " .. tostring(opts.speed or 5) ..
			(opts.broken and "  BROKEN" or ""), L.w / 2, 206, 1, SNES.grey[1], SNES.grey[2], SNES.grey[3], 1)
	end
end

function View:drawBox(lines, opts)
	opts = opts or {}
	local r = self.render
	local L = self.layout
	local modern = self.profile == "modern"
	local big = self.profile == "snes" or modern
	local w = modern and 200 or (big and 208 or 128)
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
	if modern then
		fg = NEON.magenta
		bg = NEON.panel
	end
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
