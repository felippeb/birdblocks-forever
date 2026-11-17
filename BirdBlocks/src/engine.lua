-- Bird Blocks: game engine.
--
-- Pure Lua: no WoW API in here, so tests can drive it from plain Lua 5.4.
-- Everything advances in 60 Hz "frames", the way the original games did, so
-- the timings below are the real frame counts from Tetris (Game Boy) and
-- Tetris (NES, Nintendo), not approximations in seconds.

local ADDON = ...
BirdBlocks = BirdBlocks or {}
local BB = BirdBlocks

local Engine = {}
Engine.__index = Engine
BB.Engine = Engine

local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max

local COLS = 10

-- Tetris (Game Boy): frames per row, levels 0..20.
local GB_GRAVITY = { 53, 49, 45, 41, 37, 33, 28, 22, 17, 11, 10, 9, 8, 7, 6, 6, 5, 5, 4, 4, 3 }
-- Tetris (NES): frames per row, levels 0..29.
local NES_GRAVITY = { 48, 43, 38, 33, 28, 23, 18, 13, 8, 6, 5, 5, 5, 4, 4, 4, 3, 3, 3, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }

-- Nintendo rotation system: every piece spawns flat, then turns about the
-- cell below its centre. dir = +1 turns clockwise in screen space and gives
-- the NES set; dir = -1 gives the Game Boy (left-handed) set. No wall kicks,
-- exactly like the originals.
local SHAPES = {
	I = { { 0, 1 }, { 1, 1 }, { 2, 1 }, { 3, 1 } },
	J = { { 0, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } },
	L = { { 2, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } },
	O = { { 1, 0 }, { 2, 0 }, { 1, 1 }, { 2, 1 } },
	S = { { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 } },
	T = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } },
	Z = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 2, 1 } },
}
local ORDER = { "I", "J", "L", "O", "S", "T", "Z" }
local PIVOT = 1
local SPAWN_X = 3

Engine.SHAPES = SHAPES
Engine.ORDER = ORDER
Engine.COLS = COLS

local PROFILES = {
	gb = {
		id = "gb",
		name = "GAME BOY",
		rows = 18,
		cols = COLS,
		gravity = GB_GRAVITY,
		das = 24,          -- frames before auto-shift starts
		arr = 6,           -- frames between repeats once charged
		are = 2,           -- frames between pieces
		clear = 34,        -- line clear animation length
		softRatio = 3,     -- soft drop is 1/3 G
		hand = -1,         -- left-handed Nintendo rotation
		maxLevel = 20,
	},
	snes = {
		id = "snes",
		name = "SNES",
		rows = 20,
		cols = COLS,
		gravity = NES_GRAVITY,
		das = 16,
		arr = 6,
		are = 12,
		clear = 20,
		softRatio = 2,     -- soft drop is 1/2 G
		hand = 1,          -- right-handed Nintendo rotation
		maxLevel = 29,
	},
}
Engine.PROFILES = PROFILES

local LINE_SCORE = { 40, 100, 300, 1200 }

local cache = {}

local function cellsAt(kind, rot, hand)
	local key = kind .. ":" .. rot .. ":" .. hand
	local hit = cache[key]
	if hit then return hit end

	local base = SHAPES[kind]
	local cells = {}
	for i = 1, #base do cells[i] = { base[i][1], base[i][2] } end
	if kind ~= "O" then
		local times = (rot * hand) % 4
		for _ = 1, times do
			for i = 1, #cells do
				local dx, dy = cells[i][1] - PIVOT, cells[i][2] - PIVOT
				-- screen space: y grows downward
				cells[i][1], cells[i][2] = -dy + PIVOT, dx + PIVOT
			end
		end
	end
	cache[key] = cells
	return cells
end
Engine.cellsAt = cellsAt

function Engine.new(profileID, rng)
	local profile = PROFILES[profileID] or PROFILES.gb
	local self = setmetatable({}, Engine)
	self.profile = profile
	self.rng = rng or math.random
	self.cols = profile.cols
	self.rows = profile.rows
	self.phase = "title"
	self.board = {}
	self:clearBoard()
	self.score, self.lines, self.level, self.startLevel = 0, 0, 0, 0
	self.piece, self.nextType = nil, nil
	self.gravTimer, self.dasDir, self.dasTimer = 0, nil, 0
	self.held = {}
	self.events = {}
	self.clearRows = {}
	self.frames = 0
	self.lastLockHeight = 0
	return self
end

function Engine:clearBoard()
	for y = 0, self.rows - 1 do
		local row = {}
		for x = 0, self.cols - 1 do row[x] = false end
		self.board[y] = row
	end
end

function Engine:emit(event)
	self.events[#self.events + 1] = event
end

function Engine:drain()
	local out = self.events
	self.events = {}
	return out
end

--------------------------------------------------------------------------- randomiser

-- Nintendo's games draw from a small history and reroll while the piece
-- matches the most recent one; a piece never repeats twice in a row. That
-- small rule is most of the "feel" of the original piece sequence.
function Engine:pick()
	local t
	local guard = 0
	repeat
		t = ORDER[self.rng(1, #ORDER)]
		guard = guard + 1
	until t ~= self.prevType or guard > 32
	self.prevType = t
	return t
end

--------------------------------------------------------------------------- queries

function Engine:rowsPerFrame()
	local g = self.profile.gravity
	local lv = self.level
	if lv > #g then lv = #g end
	return g[lv + 1] or g[#g]
end

function Engine:cellAt(x, y)
	if y < 0 or y >= self.rows or x < 0 or x >= self.cols then return false end
	return self.board[y][x]
end

function Engine:cells(kind, rot, x, y)
	local cells = cellsAt(kind, rot, self.profile.hand)
	local out = {}
	for i = 1, #cells do
		out[i] = { x + cells[i][1], y + cells[i][2] }
	end
	return out
end

function Engine:pieceCells()
	local p = self.piece
	if not p then return {} end
	return self:cells(p.type, p.rot, p.x, p.y)
end

function Engine:nextCells()
	if not self.nextType then return {} end
	local cells = cellsAt(self.nextType, 0, self.profile.hand)
	local out = {}
	for i = 1, #cells do out[i] = { cells[i][1], cells[i][2] } end
	return out
end

-- true when the piece would overlap a wall, the floor, or a settled block.
-- Cells above the top of the field are legal; that is where pieces spawn.
function Engine:collides(kind, rot, x, y)
	local cells = cellsAt(kind, rot, self.profile.hand)
	for i = 1, #cells do
		local wx, wy = x + cells[i][1], y + cells[i][2]
		if wx < 0 or wx >= self.cols or wy >= self.rows then return true end
		if wy >= 0 and self.board[wy][wx] then return true end
	end
	return false
end

function Engine:isFull(row)
	for x = 0, self.cols - 1 do
		if not row[x] then return false end
	end
	return true
end

--------------------------------------------------------------------------- lifecycle

function Engine:start(level)
	self.startLevel = max(0, min(9, level or 0))
	self.level = self.startLevel
	self.score, self.lines = 0, 0
	self.clearRows = {}
	self:clearBoard()
	self.piece = nil
	self.held = {}
	self.dasDir, self.dasTimer = nil, 0
	self.gravTimer = 0
	self.frames = 0
	self.prevType = nil
	self.nextType = self:pick()
	self.phase = "are"
	self.areTimer = 1
	self.topOut = false
end

function Engine:spawn()
	local kind = self.nextType or self:pick()
	self.nextType = self:pick()
	if self:collides(kind, 0, SPAWN_X, 0) then
		self.piece = { type = kind, rot = 0, x = SPAWN_X, y = 0 }
		self:gameOver()
		return
	end
	self.piece = { type = kind, rot = 0, x = SPAWN_X, y = 0 }
	self.phase = "falling"
	self.gravTimer = 0
end

function Engine:gameOver()
	self.phase = "over"
	self.piece = nil
	self:emit({ type = "over" })
end

function Engine:togglePause()
	if self.phase == "paused" then
		self.phase = self.pausedFrom or "falling"
	elseif self.phase == "falling" or self.phase == "are" or self.phase == "clearing" then
		self.pausedFrom = self.phase
		self.phase = "paused"
	end
end

--------------------------------------------------------------------------- movement

function Engine:tryMove(dx, dy)
	local p = self.piece
	if not p then return false end
	if self:collides(p.type, p.rot, p.x + dx, p.y + dy) then return false end
	p.x, p.y = p.x + dx, p.y + dy
	return true
end

function Engine:rotate(dir)
	local p = self.piece
	if not p or self.phase ~= "falling" then return end
	if p.type == "O" then return end
	local nr = (p.rot + (dir > 0 and 1 or 3)) % 4
	if self:collides(p.type, nr, p.x, p.y) then return end
	p.rot = nr
	self:emit({ type = "rotate" })
end

function Engine:press(action)
	if self.phase == "over" or self.phase == "title" then return end
	if self.phase == "paused" then
		if action == "pause" or action == "restart" then self:togglePause() end
		return
	end
	if action == "left" or action == "right" then
		local dir = action == "left" and -1 or 1
		self.held[action] = true
		self.dasDir, self.dasTimer = dir, 0
		if self.phase == "falling" and self:tryMove(dir, 0) then
			self:emit({ type = "move" })
		end
	elseif action == "down" then
		self.held.down = true
	elseif action == "rotate_cw" then
		self:rotate(self.profile.hand)
	elseif action == "rotate_ccw" then
		self:rotate(-self.profile.hand)
	elseif action == "pause" then
		self:togglePause()
		self:emit({ type = "pause" })
	end
end

function Engine:release(action)
	if action == "left" or action == "right" then
		self.held[action] = nil
		local dir = action == "left" and -1 or 1
		if self.dasDir == dir then
			local other = action == "left" and "right" or "left"
			if self.held[other] then
				self.dasDir = -dir
				self.dasTimer = 0
			else
				self.dasDir = nil
			end
		end
	elseif action == "down" then
		self.held.down = nil
	end
end

function Engine:resetInput()
	self.held = {}
	self.dasDir, self.dasTimer = nil, 0
end

function Engine:stepDAS()
	if not self.dasDir then return end
	self.dasTimer = self.dasTimer + 1
	local p = self.profile
	if self.dasTimer >= p.das then
		self.dasTimer = p.das - p.arr
		if self.phase == "falling" and self:tryMove(self.dasDir, 0) then
			self:emit({ type = "move" })
		end
	end
end

--------------------------------------------------------------------------- falling

function Engine:fall(soft)
	local p = self.piece
	if not p then return end
	if self:tryMove(0, 1) then
		if soft then
			self.score = min(999999, self.score + 1)
			self:emit({ type = "softdrop" })
		end
	else
		self:lock()
	end
end

function Engine:lock()
	local p = self.piece
	if not p then return end
	local cells = self:pieceCells()
	local above = false
	for i = 1, #cells do
		local x, y = cells[i][1], cells[i][2]
		if y < 0 then
			above = true
		elseif self.board[y][x] == false then
			self.board[y][x] = p.type
		else
			above = true
		end
	end
	self.lastLockHeight = p.y
	self.piece = nil
	self:emit({ type = "lock" })

	local full = {}
	for y = 0, self.rows - 1 do
		if self:isFull(self.board[y]) then full[#full + 1] = y end
	end

	if #full > 0 then
		self.clearRows = full
		self.clearTimer = self.profile.clear
		self.phase = "clearing"
		local base = LINE_SCORE[#full] or 0
		self.score = min(999999, self.score + base * (self.level + 1))
		self.lines = self.lines + #full
		local target = min(self.profile.maxLevel, self.startLevel + floor(self.lines / 10))
		if target > self.level then
			self.level = target
			self:emit({ type = "level", level = self.level })
		end
		local ev = { type = "line", count = #full, rows = full }
		if #full >= 4 then ev.tetris = true end
		self:emit(ev)
		return
	end

	if above then
		self:gameOver()
		return
	end

	self.phase = "are"
	self.areTimer = self.profile.are
end

function Engine:removeLines()
	local rows = self.clearRows
	if #rows == 0 then return end
	-- rows are in ascending order; removing from the top keeps indices valid
	for i = 1, #rows do
		local y = rows[i]
		for yy = y, 1, -1 do
			self.board[yy] = self.board[yy - 1]
		end
		local row = {}
		for x = 0, self.cols - 1 do row[x] = false end
		self.board[0] = row
	end
	self.clearRows = {}
end

--------------------------------------------------------------------------- tick

function Engine:step()
	self.frames = self.frames + 1
	local phase = self.phase

	if phase == "clearing" then
		self.clearTimer = self.clearTimer - 1
		if self.clearTimer <= 0 then
			self:removeLines()
			self.phase = "are"
			self.areTimer = self.profile.are
		end
		return
	end

	if phase == "are" then
		self.areTimer = self.areTimer - 1
		if self.areTimer <= 0 then self:spawn() end
		return
	end

	if phase ~= "falling" then return end

	self:stepDAS()

	local interval = self:rowsPerFrame()
	if self.held.down then
		interval = max(1, ceil(interval / self.profile.softRatio))
	end
	self.gravTimer = self.gravTimer + 1
	if self.gravTimer >= interval then
		self.gravTimer = 0
		self:fall(self.held.down and true or false)
	end
end

-- Highest row index that is occupied, used by tests and the "danger" hint.
function Engine:stackHeight()
	for y = 0, self.rows - 1 do
		for x = 0, self.cols - 1 do
			if self.board[y][x] then return self.rows - y end
		end
	end
	return 0
end

return Engine
