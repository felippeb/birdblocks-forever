-- Bird Blocks: game engine.
--
-- Pure Lua: no WoW API in here, so tests can drive it from plain Lua 5.4.
-- Everything advances in 60 Hz "frames", the way the original games did, so
-- the timings below are the real frame counts from Tetris (Game Boy) and
-- Tetris (NES, Nintendo), not approximations in seconds.
--
-- Three rulesets live here:
--   gb     - Tetris (Game Boy, 1989): Nintendo rotation, no kicks, no lock delay
--   snes   - Tetris (NES, Nintendo, 1989): the same rules, different timings
--   modern - Tetris Guideline: SRS with wall kicks, 7-bag, hold, hard drop,
--            ghost piece, lock delay and the modern scoring table
--
-- On top of any profile, a game can start as "broken": the well is prefilled
-- with random garbage rows (the B-Type board from the original Game Boy) and
-- the run ends after a line goal.

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
-- Guideline gravity in frames per row: 1 s at level 1, falling away quickly.
local MODERN_GRAVITY = { 60, 48, 37, 28, 21, 16, 12, 9, 7, 5, 4, 3, 2, 2, 1, 1, 1, 1, 1, 1, 1 }

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

-- Super Rotation System: the four states of each piece, in screen coordinates
-- (y grows downward), so no pivot arithmetic is involved.
local SRS_SHAPES = {
	I = {
		{ { 0, 1 }, { 1, 1 }, { 2, 1 }, { 3, 1 } },
		{ { 2, 0 }, { 2, 1 }, { 2, 2 }, { 2, 3 } },
		{ { 0, 2 }, { 1, 2 }, { 2, 2 }, { 3, 2 } },
		{ { 1, 0 }, { 1, 1 }, { 1, 2 }, { 1, 3 } },
	},
	J = {
		{ { 0, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } },
		{ { 1, 0 }, { 2, 0 }, { 1, 1 }, { 1, 2 } },
		{ { 0, 1 }, { 1, 1 }, { 2, 1 }, { 2, 2 } },
		{ { 1, 0 }, { 1, 1 }, { 0, 2 }, { 1, 2 } },
	},
	L = {
		{ { 2, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } },
		{ { 1, 0 }, { 1, 1 }, { 1, 2 }, { 2, 2 } },
		{ { 0, 1 }, { 1, 1 }, { 2, 1 }, { 0, 2 } },
		{ { 0, 0 }, { 1, 0 }, { 1, 1 }, { 1, 2 } },
	},
	O = {
		{ { 1, 0 }, { 2, 0 }, { 1, 1 }, { 2, 1 } },
		{ { 1, 0 }, { 2, 0 }, { 1, 1 }, { 2, 1 } },
		{ { 1, 0 }, { 2, 0 }, { 1, 1 }, { 2, 1 } },
		{ { 1, 0 }, { 2, 0 }, { 1, 1 }, { 2, 1 } },
	},
	S = {
		{ { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 } },
		{ { 1, 0 }, { 1, 1 }, { 2, 1 }, { 2, 2 } },
		{ { 1, 1 }, { 2, 1 }, { 0, 2 }, { 1, 2 } },
		{ { 0, 0 }, { 0, 1 }, { 1, 1 }, { 1, 2 } },
	},
	T = {
		{ { 1, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } },
		{ { 1, 0 }, { 1, 1 }, { 2, 1 }, { 1, 2 } },
		{ { 0, 1 }, { 1, 1 }, { 2, 1 }, { 1, 2 } },
		{ { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, 2 } },
	},
	Z = {
		{ { 0, 0 }, { 1, 0 }, { 1, 1 }, { 2, 1 } },
		{ { 2, 0 }, { 1, 1 }, { 2, 1 }, { 1, 2 } },
		{ { 0, 1 }, { 1, 1 }, { 1, 2 }, { 2, 2 } },
		{ { 1, 0 }, { 0, 1 }, { 1, 1 }, { 0, 2 } },
	},
}

-- SRS wall kicks, written the way the tables are published (y grows upward)
-- and negated on use. Indexed "from>to".
local KICKS = {
	JLSTZ = {
		["0>1"] = { { 0, 0 }, { -1, 0 }, { -1, 1 }, { 0, -2 }, { -1, -2 } },
		["1>0"] = { { 0, 0 }, { 1, 0 }, { 1, -1 }, { 0, 2 }, { 1, 2 } },
		["1>2"] = { { 0, 0 }, { 1, 0 }, { 1, -1 }, { 0, 2 }, { 1, 2 } },
		["2>1"] = { { 0, 0 }, { -1, 0 }, { -1, 1 }, { 0, -2 }, { -1, -2 } },
		["2>3"] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, -2 }, { 1, -2 } },
		["3>2"] = { { 0, 0 }, { -1, 0 }, { -1, -1 }, { 0, 2 }, { -1, 2 } },
		["3>0"] = { { 0, 0 }, { -1, 0 }, { -1, -1 }, { 0, 2 }, { -1, 2 } },
		["0>3"] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, -2 }, { 1, -2 } },
	},
	I = {
		["0>1"] = { { 0, 0 }, { -2, 0 }, { 1, 0 }, { -2, -1 }, { 1, 2 } },
		["1>0"] = { { 0, 0 }, { 2, 0 }, { -1, 0 }, { 2, 1 }, { -1, -2 } },
		["1>2"] = { { 0, 0 }, { -1, 0 }, { 2, 0 }, { -1, 2 }, { 2, -1 } },
		["2>1"] = { { 0, 0 }, { 1, 0 }, { -2, 0 }, { 1, -2 }, { -2, 1 } },
		["2>3"] = { { 0, 0 }, { 2, 0 }, { -1, 0 }, { 2, 1 }, { -1, -2 } },
		["3>2"] = { { 0, 0 }, { -2, 0 }, { 1, 0 }, { -2, -1 }, { 1, 2 } },
		["3>0"] = { { 0, 0 }, { 1, 0 }, { -2, 0 }, { 1, -2 }, { -2, 1 } },
		["0>3"] = { { 0, 0 }, { -1, 0 }, { 2, 0 }, { -1, 2 }, { 2, -1 } },
	},
}

Engine.SHAPES = SHAPES
Engine.SRS_SHAPES = SRS_SHAPES
Engine.KICKS = KICKS
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
		queue = 1,
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
		queue = 1,
	},
	modern = {
		id = "modern",
		name = "MODERN",
		rows = 20,
		cols = COLS,
		gravity = MODERN_GRAVITY,
		das = 10,          -- 167 ms, close to the guideline's 133
		arr = 1,           -- one cell per frame once charged
		are = 4,
		clear = 18,
		softRatio = 20,    -- soft drop is 20G
		hand = 1,
		maxLevel = 20,
		queue = 3,         -- pieces shown in NEXT
		modern = true,
		srs = true,
		bag = true,        -- 7-bag randomiser
		hold = true,
		ghost = true,
		hardDrop = true,
		lockDelay = 30,    -- 0.5 s, Guideline
		maxResets = 15,
		tspin = true,
	},
}
Engine.PROFILES = PROFILES

-- Nintendo scoring, shared by the two retro profiles.
local LINE_SCORE = { 40, 100, 300, 1200 }
-- Guideline line scores, multiplied by the level.
local MODERN_SCORE = { 100, 300, 500, 800 }
-- T-spin scores indexed by lines cleared (0..3).
local TSPIN_SCORE = {
	mini = { 100, 200, 400, 0 },
	full = { 400, 800, 1200, 1600 },
}
-- Perfect clear bonus indexed by lines cleared minus one.
local PERFECT_SCORE = { 800, 1200, 1800, 2000 }

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

-- SRS states never rotate, they are looked up, so kicks and rotations always
-- agree with the published tables.
local function srsCells(kind, rot)
	local key = "srs:" .. kind .. ":" .. rot
	local hit = cache[key]
	if hit then return hit end
	local base = SRS_SHAPES[kind][(rot % 4) + 1]
	local cells = {}
	for i = 1, #base do cells[i] = { base[i][1], base[i][2] } end
	cache[key] = cells
	return cells
end
Engine.srsCells = srsCells

function Engine.new(profileID, rng)
	local profile = PROFILES[profileID] or PROFILES.modern
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
	self.queue, self.bag = {}, {}
	self.holdType, self.canHold = nil, true
	self.lockTimer, self.lockResets = 0, 0
	self.lastAction = nil
	self.combo, self.b2b = 0, false
	self.lastClear = 0
	self.goal, self.mode = nil, "normal"
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

-- Guideline: shuffle all seven pieces, deal them, reshuffle when empty. Every
-- piece appears once per bag, so droughts are bounded at twelve pieces.
function Engine:fillBag()
	local bag = {}
	for i = 1, #ORDER do bag[i] = ORDER[i] end
	for i = #bag, 2, -1 do
		local j = self.rng(1, i)
		bag[i], bag[j] = bag[j], bag[i]
	end
	self.bag = bag
end

function Engine:nextFromSource()
	if self.profile.bag then
		if #self.bag == 0 then self:fillBag() end
		return table.remove(self.bag)
	end
	return self:pick()
end

function Engine:refillQueue()
	local size = self.profile.queue or 1
	while #self.queue < size do
		self.queue[#self.queue + 1] = self:nextFromSource()
	end
	self.nextType = self.queue[1]
end

function Engine:take()
	self:refillQueue()
	local kind = table.remove(self.queue, 1)
	self:refillQueue()
	return kind
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

local function shapeFor(profile, kind, rot)
	if profile.srs then return srsCells(kind, rot) end
	return cellsAt(kind, rot, profile.hand)
end
Engine.shapeFor = shapeFor

function Engine:cells(kind, rot, x, y)
	local cells = shapeFor(self.profile, kind, rot)
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
	local cells = shapeFor(self.profile, self.nextType, 0)
	local out = {}
	for i = 1, #cells do out[i] = { cells[i][1], cells[i][2] } end
	return out
end

-- Cells for one entry of the preview queue (1-based).
function Engine:queueCells(index)
	local kind = self.queue[index or 1]
	if not kind then return {} end
	local cells = shapeFor(self.profile, kind, 0)
	local out = {}
	for i = 1, #cells do out[i] = { cells[i][1], cells[i][2] } end
	return out
end

function Engine:queueType(index)
	return self.queue[index or 1]
end

function Engine:queueSize()
	return self.profile.queue or 1
end

function Engine:holdCells()
	if not self.holdType then return {} end
	local cells = shapeFor(self.profile, self.holdType, 0)
	local out = {}
	for i = 1, #cells do out[i] = { cells[i][1], cells[i][2] } end
	return out
end

-- Where the piece would come to rest: the ghost the modern profile draws.
function Engine:ghostCells()
	if not self.profile.ghost or not self.piece or self.phase ~= "falling" then return {} end
	local p = self.piece
	local y = p.y
	while not self:collides(p.type, p.rot, p.x, y + 1) do y = y + 1 end
	return self:cells(p.type, p.rot, p.x, y)
end

-- true when the piece would overlap a wall, the floor, or a settled block.
-- Cells above the top of the field are legal; that is where pieces spawn.
function Engine:collides(kind, rot, x, y)
	local cells = shapeFor(self.profile, kind, rot)
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

-- opts.garbage  fraction of the well to prefill (0..1), B-Type style
-- opts.goal     lines to clear for a win; nil means endless
function Engine:start(level, opts)
	opts = opts or {}
	self.startLevel = max(0, min(10, level or 0))
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
	self.queue, self.bag = {}, {}
	self.holdType, self.canHold, self.holdUsed = nil, true, false
	self.lockTimer, self.lockResets = 0, 0
	self.lastAction = nil
	self.combo, self.b2b = 0, false
	self.lastClear = 0
	self.goal = opts.goal
	self.mode = (opts.garbage and opts.garbage > 0) and "broken" or "normal"
	if self.mode == "broken" then self:fillGarbage(opts.garbage) end
	self:refillQueue()
	self.phase = "are"
	self.areTimer = 1
	self.topOut = false
end

-- B-Type start: full rows with random holes, up to the requested share of the
-- well. Rows never come out complete, so nothing clears for free, and the top
-- of the field stays open for the first pieces.
function Engine:fillGarbage(fraction)
	local count = floor(self.rows * max(0, min(1, fraction or 0)))
	if count < 1 then return end
	count = min(count, self.rows - 2)
	local previous = nil
	for i = 0, count - 1 do
		local row = self.board[self.rows - 1 - i]
		for x = 0, self.cols - 1 do row[x] = "G" end
		local hole
		repeat
			hole = self.rng(1, self.cols) - 1
		until hole ~= previous or self.cols < 3
		row[hole] = false
		if self.rng(1, 4) == 1 then
			local second
			repeat second = self.rng(1, self.cols) - 1 until second ~= hole
			row[second] = false
		end
		previous = hole
	end
end

function Engine:win()
	self.phase = "win"
	self.piece = nil
	self:emit({ type = "win", score = self.score, lines = self.lines })
end

function Engine:spawn(kind)
	kind = kind or self:take()
	if self:collides(kind, 0, SPAWN_X, 0) then
		self.piece = { type = kind, rot = 0, x = SPAWN_X, y = 0 }
		self:gameOver()
		return
	end
	self.piece = { type = kind, rot = 0, x = SPAWN_X, y = 0 }
	self.phase = "falling"
	self.gravTimer, self.lockTimer, self.lockResets = 0, 0, 0
	self.canHold = true
	self.lastAction = nil
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

-- Resting on the stack: count the lock delay, and let movement buy time a
-- bounded number of times so a piece cannot be held forever.
function Engine:resetLockTimer()
	local p = self.piece
	if not self.profile.lockDelay or not p then return end
	if self:collides(p.type, p.rot, p.x, p.y + 1) then
		if self.lockResets < (self.profile.maxResets or 15) then
			self.lockResets = self.lockResets + 1
			self.lockTimer = 0
		end
	else
		self.lockTimer = 0
	end
end

function Engine:tryMove(dx, dy)
	local p = self.piece
	if not p then return false end
	if self:collides(p.type, p.rot, p.x + dx, p.y + dy) then return false end
	p.x, p.y = p.x + dx, p.y + dy
	if self.profile.lockDelay then
		self.lastAction = "move"
		self:resetLockTimer()
	end
	return true
end

function Engine:kickOffsets(kind, from, to)
	local table_ = (kind == "I") and KICKS.I or KICKS.JLSTZ
	return table_[from .. ">" .. to]
end

function Engine:rotate(dir)
	local p = self.piece
	if not p or self.phase ~= "falling" then return end
	if p.type == "O" then return end
	local nr = (p.rot + (dir > 0 and 1 or 3)) % 4

	if not self.profile.srs then
		-- Nintendo: rotation is all-or-nothing, no kicks.
		if self:collides(p.type, nr, p.x, p.y) then return end
		p.rot = nr
		self:emit({ type = "rotate" })
		return
	end

	local kicks = self:kickOffsets(p.type, p.rot, nr)
	for i = 1, #kicks do
		local nx, ny = p.x + kicks[i][1], p.y - kicks[i][2]
		if not self:collides(p.type, nr, nx, ny) then
			p.x, p.y, p.rot = nx, ny, nr
			self.lastAction = "rotate"
			self:resetLockTimer()
			self:emit({ type = "rotate", kick = i })
			return
		end
	end
end

function Engine:hold()
	local p = self.piece
	if not self.profile.hold or not p or self.phase ~= "falling" then return false end
	if not self.canHold then return false end
	local current = p.type
	local swapped = self.holdType
	self.holdType = current
	self.canHold = false
	if swapped then
		if self:collides(swapped, 0, SPAWN_X, 0) then
			self.piece = { type = swapped, rot = 0, x = SPAWN_X, y = 0 }
			self:gameOver()
			return true
		end
		self.piece = { type = swapped, rot = 0, x = SPAWN_X, y = 0 }
		self.gravTimer, self.lockTimer, self.lockResets = 0, 0, 0
		self.lastAction = nil
	else
		-- First hold: stash it and pull the next piece straight from the queue.
		-- spawn() would re-arm hold, which is exactly what the guideline forbids
		-- until the new piece locks.
		self.piece = nil
		self:spawn()
		self.canHold = false
	end
	self:emit({ type = "hold" })
	return true
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
		self:rotate(self.profile.srs and 1 or self.profile.hand)
	elseif action == "rotate_ccw" then
		self:rotate(self.profile.srs and -1 or -self.profile.hand)
	elseif action == "harddrop" then
		self:hardDrop()
	elseif action == "hold" then
		self:hold()
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

-- Guideline gravity: falling never locks; resting starts the lock delay.
function Engine:stepGravityModern()
	local p = self.piece
	if not p then return end
	if self:collides(p.type, p.rot, p.x, p.y + 1) then
		self.gravTimer = 0
		self.lockTimer = self.lockTimer + 1
		if self.lockTimer >= self.profile.lockDelay then self:lock() end
		return
	end
	self.lockTimer = 0

	local interval = self:rowsPerFrame()
	if self.held.down then
		interval = max(1, ceil(interval / self.profile.softRatio))
	end
	self.gravTimer = self.gravTimer + 1
	if self.gravTimer >= interval then
		self.gravTimer = 0
		if self:tryMove(0, 1) then
			if self.held.down then
				self.score = min(999999, self.score + 1)
				self:emit({ type = "softdrop" })
			end
		end
	end
end

-- Space: drop to the floor and lock at once, two points per row.
function Engine:hardDrop()
	local p = self.piece
	if not p or self.phase ~= "falling" or not self.profile.hardDrop then return 0 end
	local rows = 0
	while not self:collides(p.type, p.rot, p.x, p.y + 1) do
		p.y = p.y + 1
		rows = rows + 1
	end
	if rows > 0 then
		self.score = min(999999, self.score + rows * 2)
	end
	self.lastAction = "drop"
	self:emit({ type = "harddrop", rows = rows })
	self:lock()
	return rows
end

--------------------------------------------------------------------------- locking

-- T-spin: the last action rotated the T and at least three of the four corners
-- around its centre are solid. Both front corners means a full T-spin, only
-- one means a mini.
function Engine:detectTSpin()
	if not self.profile.tspin or self.lastAction ~= "rotate" then return nil end
	local p = self.piece
	if not p or p.type ~= "T" then return nil end
	local cx, cy = p.x + 1, p.y + 1

	local function solid(x, y)
		if x < 0 or x >= self.cols or y >= self.rows then return true end
		if y < 0 then return false end
		return self.board[y][x] and true or false
	end

	local tl, tr = solid(cx - 1, cy - 1), solid(cx + 1, cy - 1)
	local bl, br = solid(cx - 1, cy + 1), solid(cx + 1, cy + 1)
	local corners = (tl and 1 or 0) + (tr and 1 or 0) + (bl and 1 or 0) + (br and 1 or 0)
	if corners < 3 then return nil end

	local front
	if p.rot == 0 then front = tl and tr
	elseif p.rot == 1 then front = tr and br
	elseif p.rot == 2 then front = br and bl
	else front = bl and tl end
	return front and "full" or "mini"
end

-- Guideline scoring: clear value × level, 1.5× for back-to-back, a combo
-- bonus, and a perfect-clear bonus when the well is emptied.
function Engine:modernScore(cleared, tspin)
	local mult = self.level + 1
	local base
	if tspin then
		base = TSPIN_SCORE[tspin][cleared + 1] or 0
	else
		base = MODERN_SCORE[cleared] or 0
	end

	local difficult = (cleared == 4) or (tspin ~= nil and cleared > 0)
	if difficult and self.b2b then base = floor(base * 1.5) end
	if cleared > 0 then self.b2b = difficult end

	local bonus = 0
	if cleared > 0 then
		if self.combo > 0 then bonus = 50 * self.combo * mult end
		self.combo = self.combo + 1
	elseif tspin then
		-- A T-spin with no clear keeps the combo alive, as in the guideline.
	else
		self.combo = 0
	end

	local perfect = false
	if cleared > 0 then
		perfect = true
		for y = 0, self.rows - 1 do
			if not self:isFull(self.board[y]) then
				for x = 0, self.cols - 1 do
					if self.board[y][x] then perfect = false break end
				end
			end
			if not perfect then break end
		end
		if perfect then bonus = bonus + PERFECT_SCORE[min(4, cleared)] * mult end
	end

	self.score = min(999999, self.score + base * mult + bonus)
	return perfect
end

function Engine:lock()
	local p = self.piece
	if not p then return end
	local tspin = self:detectTSpin()
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
	local cleared = #full
	self.lastClear = cleared

	if self.profile.modern then
		local perfect = self:modernScore(cleared, tspin)
		self.lines = self.lines + cleared
		if cleared > 0 then
			local target = min(self.profile.maxLevel, self.startLevel + floor(self.lines / 10))
			if target > self.level then
				self.level = target
				self:emit({ type = "level", level = self.level })
			end
		end
		if tspin then
			self:emit({ type = "tspin", kind = tspin, count = cleared })
		end
		if cleared > 0 then
			self.clearRows = full
			self.clearTimer = self.profile.clear
			self.phase = "clearing"
			local ev = { type = "line", count = cleared, rows = full, tspin = tspin, perfect = perfect }
			if cleared >= 4 then ev.tetris = true end
			self:emit(ev)
			return
		end
		if above then
			self:gameOver()
			return
		end
		self.phase = "are"
		self.areTimer = self.profile.are
		return
	end

	if cleared > 0 then
		self.clearRows = full
		self.clearTimer = self.profile.clear
		self.phase = "clearing"
		local base = LINE_SCORE[cleared] or 0
		self.score = min(999999, self.score + base * (self.level + 1))
		self.lines = self.lines + cleared
		local target = min(self.profile.maxLevel, self.startLevel + floor(self.lines / 10))
		if target > self.level then
			self.level = target
			self:emit({ type = "level", level = self.level })
		end
		local ev = { type = "line", count = cleared, rows = full }
		if cleared >= 4 then ev.tetris = true end
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
			if self.goal and self.lines >= self.goal then
				self:win()
				return
			end
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

	if self.profile.modern then
		self:stepGravityModern()
		return
	end

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
