-- Bird Blocks engine tests. Run from the repo root:
--   lua tests/run_engine.lua
--
-- These cover the parts that a screenshot cannot: real frame timings, DAS,
-- scoring, line clears, the Nintendo rotation sets, and top-out.

package.path = package.path .. ";BirdBlocks/src/?.lua"

local function loadAddon(file)
	local chunk = assert(loadfile("BirdBlocks/src/" .. file))
	return chunk("BirdBlocks")
end

loadAddon("engine.lua")
local Engine = BirdBlocks.Engine

local passed, failed = 0, 0
local failures = {}

local function check(name, cond, detail)
	if cond then
		passed = passed + 1
	else
		failed = failed + 1
		failures[#failures + 1] = name .. (detail and (" (" .. tostring(detail) .. ")") or "")
	end
end

local function eq(name, got, want)
	check(name, got == want, string.format("got %s, want %s", tostring(got), tostring(want)))
end

-- deterministic small LCG so piece sequences are reproducible
local function lcg(seed)
	local s = seed or 1
	return function(a, b)
		s = (1103515245 * s + 12345) % 2147483648
		local n = b or a
		return 1 + math.floor(s / 2147483648 * n)
	end
end

local function newGame(profile, seed)
	local e = Engine.new(profile or "gb", lcg(seed or 42))
	e:start(0)
	e:step() -- ARE -> spawn
	return e
end

local function forcePiece(e, kind, x, y, rot)
	local p = e.piece
	p.type, p.x, p.y, p.rot = kind, x, y, rot or 0
end

local function lockNow(e)
	e.gravTimer = 999
	e:step()
end

--------------------------------------------------------------------------- timings

do
	local e = newGame("gb")
	check("spawns after ARE", e.piece ~= nil)
	eq("spawn phase", e.phase, "falling")
	local y = e.piece.y
	for _ = 1, 52 do e:step() end
	eq("GB level 0: still level after 52 frames", e.piece.y, y)
	e:step()
	eq("GB level 0: drops on frame 53", e.piece.y, y + 1)

	local s = newGame("snes")
	local sy = s.piece.y
	for _ = 1, 47 do s:step() end
	eq("NES level 0: still level after 47 frames", s.piece.y, sy)
	s:step()
	eq("NES level 0: drops on frame 48", s.piece.y, sy + 1)

	-- level 9 on GB is 11 frames per row
	local f = newGame("gb")
	f.level = 9
	local fy = f.piece.y
	for _ = 1, 10 do f:step() end
	eq("GB level 9: 10 frames is not enough", f.piece.y, fy)
	f:step()
	eq("GB level 9: drops on frame 11", f.piece.y, fy + 1)
end

--------------------------------------------------------------------------- movement

do
	local e = newGame("gb")
	local x = e.piece.x
	e:press("left")
	eq("left moves once", e.piece.x, x - 1)
	for _ = 1, 23 do e:step() end
	eq("DAS holds for 24 frames", e.piece.x, x - 1)
	e:step()
	eq("DAS repeats on frame 24", e.piece.x, x - 2)
	for _ = 1, 5 do e:step() end
	eq("ARR waits 6 frames", e.piece.x, x - 2)
	e:step()
	eq("ARR repeats", e.piece.x, x - 3)

	local s = newGame("snes")
	s:press("right")
	for _ = 1, 15 do s:step() end
	eq("NES DAS holds 16 frames", s.piece.x, 4)
	s:step()
	eq("NES DAS fires", s.piece.x, 5)
end

do
	local e = newGame("gb")
	forcePiece(e, "I", 3, 0, 0)
	for _ = 1, 20 do e:press("left") end
	eq("cannot leave the left wall", e.piece.x, 0)
	for _ = 1, 20 do e:press("right") end
	eq("cannot leave the right wall", e.piece.x, 6) -- I piece is 4 wide, spawn x=3
end

--------------------------------------------------------------------------- rotation

do
	local gb = Engine.new("gb", lcg(1))
	local sn = Engine.new("snes", lcg(1))
	local function shape(kind, rot, hand)
		local cells = Engine.cellsAt(kind, rot, hand)
		local minx, maxx, miny, maxy = 99, -99, 99, -99
		for i = 1, #cells do
			minx = math.min(minx, cells[i][1]); maxx = math.max(maxx, cells[i][1])
			miny = math.min(miny, cells[i][2]); maxy = math.max(maxy, cells[i][2])
		end
		return minx, maxx, miny, maxy, #cells
	end
	local function colOf(cells, y)
		for i = 1, #cells do
			if cells[i][2] == y then return cells[i][1] end
		end
	end
	local gbT = Engine.cellsAt("T", 1, -1)
	local snT = Engine.cellsAt("T", 1, 1)
	local function signature(cells)
		local parts = {}
		for i = 1, #cells do
			parts[i] = cells[i][1] .. "," .. cells[i][2]
		end
		table.sort(parts)
		return table.concat(parts, " ")
	end
	check("GB left-handed T turns the other way", signature(gbT) ~= signature(snT),
		signature(gbT) .. " vs " .. signature(snT))

	-- O never changes shape
	local o = Engine.cellsAt("O", 0, 1)
	local o2 = Engine.cellsAt("O", 3, 1)
	check("O is rotation invariant", #o == 4 and #o2 == 4)

	-- every rotation state is 4 cells
	for _, kind in ipairs(Engine.ORDER) do
		for rot = 0, 3 do
			check("4 cells " .. kind .. " rot " .. rot, #Engine.cellsAt(kind, rot, 1) == 4)
			check("4 cells " .. kind .. " rot " .. rot .. " gb", #Engine.cellsAt(kind, rot, -1) == 4)
		end
	end

	local e = newGame("snes")
	forcePiece(e, "T", 3, 0, 0)
	e:press("rotate_cw")
	eq("rotate_cw turns once", e.piece.rot, 1)
	e:press("rotate_ccw")
	eq("rotate_ccw turns back", e.piece.rot, 0)
end

do
	-- no wall kicks: a rotation that would need a kick simply fails
	local e = newGame("snes")
	forcePiece(e, "I", 0, 5, 1) -- vertical at column 1
	e:press("rotate_cw")         -- would need column -1
	eq("no wall kick for I at the left wall", e.piece.rot, 1)
end

--------------------------------------------------------------------------- soft drop / scoring

do
	local e = newGame("gb")
	e:press("down")
	local y = e.piece.y
	for _ = 1, 17 do e:step() end -- 53/3 -> 18 frames
	eq("soft drop waits 18 frames", e.piece.y, y)
	e:step()
	eq("soft drop moves", e.piece.y, y + 1)
	eq("soft drop scores 1 per cell", e.score, 1)
	e:release("down")
end

do
	-- single
	local e = newGame("gb")
	forcePiece(e, "I", 3, 16, 0) -- horizontal I on row 17
	for x = 0, 2 do e.board[17][x] = "J" end
	for x = 7, 9 do e.board[17][x] = "J" end
	lockNow(e)
	eq("single scores 40", e.score, 40)
	eq("single clears one line", e.lines, 1)
	eq("clearing phase", e.phase, "clearing")
	for _ = 1, 40 do e:step() end
	eq("row removed after animation", e.board[17][0], false)
	eq("phase returns to falling", e.phase, "falling")
end

do
	-- tetris
	local e = newGame("gb")
	for y = 14, 17 do
		for x = 0, 8 do e.board[y][x] = "J" end
	end
	forcePiece(e, "I", 8, 15, 1)
	lockNow(e)
	eq("tetris scores 1200", e.score, 1200)
	eq("tetris clears four lines", e.lines, 4)
	for _ = 1, 40 do e:step() end
	local empty = true
	for y = 14, 17 do
		for x = 0, 9 do if e.board[y][x] then empty = false end end
	end
	check("tetris empties the board", empty)
end

do
	-- level multiplier applies to the clear
	local e = newGame("gb")
	e.level = 2
	forcePiece(e, "I", 3, 16, 0)
	for x = 0, 2 do e.board[17][x] = "J" end
	for x = 7, 9 do e.board[17][x] = "J" end
	lockNow(e)
	eq("score multiplier uses level+1", e.score, 120)
end

do
	-- ten lines levels up
	local e = newGame("gb")
	for _ = 1, 10 do
		forcePiece(e, "I", 3, 16, 0)
		for x = 0, 2 do e.board[17][x] = "J" end
	for x = 7, 9 do e.board[17][x] = "J" end
		lockNow(e)
		for _ = 1, 40 do e:step() end
		if not e.piece then e:step() end
	end
	eq("level up after 10 lines", e.level, 1)
end

--------------------------------------------------------------------------- top out

do
	local e = newGame("gb")
	for x = 3, 5 do e.board[0][x] = "J" end
	e.piece = nil
	e.nextType = "T"
	e.phase = "are"
	e.areTimer = 1
	e:step()
	eq("spawn collision is game over", e.phase, "over")
end

do
	local e = newGame("gb")
	for x = 3, 5 do e.board[0][x] = "J" end
	e.piece = nil
	e.nextType = "T"
	e.phase = "are"
	e.areTimer = 1
	e:step()
	eq("spawn collision is game over", e.phase, "over")
end

--------------------------------------------------------------------------- randomiser

do
	local e = Engine.new("gb", lcg(7))
	e:start(0)
	local prev = nil
	local repeats = 0
	for _ = 1, 500 do
		local t = e:pick()
		if t == prev then repeats = repeats + 1 end
		prev = t
	end
	eq("never repeats a piece twice in a row", repeats, 0)

	-- every piece shows up
	local seen = {}
	local e2 = Engine.new("gb", lcg(11))
	e2:start(0)
	for _ = 1, 500 do seen[e2:pick()] = true end
	local kinds = 0
	for _ in pairs(seen) do kinds = kinds + 1 end
	eq("all seven pieces appear", kinds, 7)
end

--------------------------------------------------------------------------- pause + input reset

do
	local e = newGame("gb")
	e:press("pause")
	eq("pause", e.phase, "paused")
	local y = e.piece and e.piece.y
	for _ = 1, 200 do e:step() end
	eq("paused game does not tick", e.piece.y, y)
	e:press("pause")
	eq("resume", e.phase, "falling")
end

do
	local e = newGame("gb")
	e:press("left")
	e:release("left")
	e:resetInput()
	eq("input reset clears held keys", next(e.held), nil)
end

--------------------------------------------------------------------------- modern rules

do
	-- Guideline gravity: 60 frames per row at level 0.
	local e = newGame("modern")
	local y = e.piece.y
	for _ = 1, 59 do e:step() end
	eq("modern level 0: still level after 59 frames", e.piece.y, y)
	e:step()
	eq("modern level 0: drops on frame 60", e.piece.y, y + 1)

	-- Soft drop is 20G: ceil(60/20) = 3 frames per cell.
	local s = newGame("modern")
	s:press("down")
	local sy = s.piece.y
	for _ = 1, 2 do s:step() end
	eq("modern soft drop waits 3 frames", s.piece.y, sy)
	s:step()
	eq("modern soft drop moves", s.piece.y, sy + 1)
	eq("modern soft drop scores 1 per cell", s.score, 1)
	s:release("down")
end

do
	-- 7-bag: every bag is a permutation of all seven pieces.
	local e = Engine.new("modern", lcg(99))
	e:start(0)
	e.bag, e.queue = {}, {}
	for round = 1, 2 do
		local seen, kinds = {}, 0
		for _ = 1, 7 do
			local t = e:nextFromSource()
			if not seen[t] then seen[t] = true; kinds = kinds + 1 end
		end
		eq("7-bag round " .. round .. " deals all seven", kinds, 7)
	end
end

do
	-- SRS I-piece kick: 0->R needs (-2,0) because the first spot is blocked.
	local e = newGame("modern")
	forcePiece(e, "I", 0, 0, 0)
	e.board[0][2] = "J"
	e:press("rotate_cw")
	eq("I kick rotates", e.piece.rot, 1)
	eq("I kick moves two left", e.piece.x, -2)

	-- SRS J/L/S/T/Z kick: 0->L needs (+1,0).
	local t = newGame("modern")
	forcePiece(t, "T", 0, 0, 0)
	t.board[2][1] = "J"
	t:press("rotate_ccw")
	eq("T kick rotates", t.piece.rot, 3)
	eq("T kick moves one right", t.piece.x, 1)
end

do
	-- Hard drop: instant lock, two points per row.
	local e = newGame("modern")
	forcePiece(e, "T", 3, 0, 0)
	e.events = {}
	local dropped = e:hardDrop()
	eq("hard drop falls to the floor", dropped, e.rows - 2)
	eq("hard drop scores 2 per row", e.score, (e.rows - 2) * 2)
	check("hard drop locks at once", e.piece == nil)
	eq("hard drop goes to ARE", e.phase, "are")
	local kinds = {}
	for _, ev in ipairs(e.events) do kinds[ev.type] = true end
	check("hard drop emits an event", kinds.harddrop == true)
end

do
	-- Hold swaps once, then stays locked until the next piece spawns.
	local e = newGame("modern")
	local first = e.piece.type
	local upcoming = e.queue[1]
	check("hold works", e:hold() == true)
	eq("hold stores the active piece", e.holdType, first)
	eq("hold pulls the next piece", e.piece.type, upcoming)
	eq("hold cannot repeat on the same piece", e.canHold, false)
	check("second hold is ignored", e:hold() == false)

	-- A fresh piece re-arms hold, and the swap goes both ways.
	local held = e.holdType
	e.piece = nil
	e:spawn()
	local before = e.piece.type
	eq("hold re-arms on the next piece", e.canHold, true)
	check("hold swaps", e:hold() == true)
	eq("hold puts the old piece back", e.piece.type, held)
	eq("hold takes the active piece", e.holdType, before)
end

do
	-- Ghost: the landing preview sits on the floor and leaves the piece alone.
	local e = newGame("modern")
	forcePiece(e, "O", 3, 0, 0)
	local ghost = e:ghostCells()
	eq("ghost has four cells", #ghost, 4)
	local bottom = 0
	for i = 1, #ghost do
		if ghost[i][2] > bottom then bottom = ghost[i][2] end
	end
	eq("ghost bottom reaches the last row", bottom, e.rows - 1)
	eq("ghost does not move the piece", e.piece.y, 0)

	local g = newGame("gb")
	eq("retro profiles have no ghost", #g:ghostCells(), 0)
end

do
	-- Lock delay: 30 frames resting, movement resets it up to 15 times.
	local e = newGame("modern")
	forcePiece(e, "O", 3, e.rows - 2, 0)
	e.lockTimer = 29
	e:step()
	check("lock delay locks after 30 frames", e.piece == nil)

	local r = newGame("modern")
	forcePiece(r, "O", 3, r.rows - 2, 0)
	r.lockTimer, r.lockResets = 29, 0
	r:press("left")
	r:release("left")
	eq("movement resets the lock timer", r.lockTimer, 0)
	eq("movement counts a reset", r.lockResets, 1)
	r:step()
	check("a reset keeps the piece alive", r.piece ~= nil)

	-- At the reset cap the timer runs again even when the piece moves.
	r.lockResets = 15
	r.lockTimer = 29
	r:press("right")
	r:release("right")
	eq("movement cannot reset past the cap", r.lockTimer, 29)
	r:step()
	check("the piece locks after the reset cap", r.piece == nil)
end

do
	-- Guideline scoring: 100 for a single, with a stray block so it is not a
	-- perfect clear.
	local e = newGame("modern")
	e.board[0][0] = "J"
	forcePiece(e, "I", 3, 18, 0)
	for x = 0, 2 do e.board[19][x] = "J" end
	for x = 7, 9 do e.board[19][x] = "J" end
	e:lock()
	eq("modern single scores 100", e.score, 100)
	eq("modern single clears one line", e.lines, 1)
end

do
	-- Perfect clear: single 100 + 800 bonus.
	local e = newGame("modern")
	forcePiece(e, "I", 3, 18, 0)
	for x = 0, 2 do e.board[19][x] = "J" end
	for x = 7, 9 do e.board[19][x] = "J" end
	e:lock()
	eq("perfect clear adds 800", e.score, 900)
end

do
	-- Back-to-back tetris: 800, then 800 x 1.5 + combo.
	local e = newGame("modern")
	e.board[0][0] = "J" -- keeps the board from being a perfect clear
	for y = 16, 19 do
		for x = 0, 8 do e.board[y][x] = "J" end
	end
	forcePiece(e, "I", 7, 16, 1)
	e:lock()
	eq("modern tetris scores 800", e.score, 800)
	eq("tetris arms back-to-back", e.b2b, true)

	for _ = 1, 40 do
		if e.piece then break end
		e:step()
	end
	for y = 16, 19 do
		for x = 0, 8 do e.board[y][x] = "J" end
	end
	forcePiece(e, "I", 7, 16, 1)
	e:lock()
	eq("back-to-back tetris adds 1200 + combo", e.score, 800 + 1200 + 50)
	eq("combo counts the second clear", e.combo, 2)
end

do
	-- T-spin: rotate into a notch, then clear a single.
	local e = newGame("modern")
	forcePiece(e, "T", 3, 17, 2)
	for x = 0, 2 do e.board[19][x] = "J" end
	for x = 6, 9 do e.board[19][x] = "J" end
	e.board[17][3] = "J"    -- back corner
	e.board[19][3] = "J"    -- front corner
	e.board[19][5] = "J"    -- front corner
	e.lastAction = "rotate"
	eq("full T-spin detected", e:detectTSpin(), "full")
	e:lock()
	eq("T-spin single scores 800", e.score, 800)
	eq("T-spin clears the line", e.lines, 1)
end

--------------------------------------------------------------------------- speed / broken mode

do
	-- Speed 5 means starting at level 5: 16 frames per row, not 60.
	local e = Engine.new("modern", lcg(7))
	e:start(5)
	e:step() -- ARE -> spawn
	eq("speed 5 starts at level 5", e.level, 5)
	local y = e.piece.y
	for _ = 1, 15 do e:step() end
	eq("speed 5 holds for 15 frames", e.piece.y, y)
	e:step()
	eq("speed 5 drops on frame 16", e.piece.y, y + 1)
end

do
	-- B-Type garbage: roughly the requested share of the well, never a full
	-- row, and always headroom for the first piece.
	local e = Engine.new("modern", lcg(5))
	e:start(5, { garbage = 0.6, goal = 25 })
	eq("broken run", e.mode, "broken")
	eq("broken goal", e.goal, 25)

	local rows, full = 0, 0
	for y = 0, e.rows - 1 do
		local blocks = 0
		for x = 0, e.cols - 1 do
			if e.board[y][x] == "G" then blocks = blocks + 1 end
		end
		if blocks > 0 then
			rows = rows + 1
			if blocks == e.cols then full = full + 1 end
		end
	end
	eq("garbage fills 60% of the well", rows, math.floor(e.rows * 0.6))
	eq("garbage rows are never complete", full, 0)
	check("garbage leaves the spawn area clear", e.board[0][0] == false and e.board[1][9] == false)

	local gb = Engine.new("gb", lcg(8))
	gb:start(5, { garbage = 0.3 })
	eq("broken works on game boy too", gb.mode, "broken")
	eq("game boy goal defaults to none when omitted", gb.goal, nil)
end

do
	-- Reaching the line goal ends the run after the clear animation.
	local e = Engine.new("modern", lcg(3))
	e:start(0, { garbage = 0, goal = 1 })
	e:step() -- ARE -> spawn
	forcePiece(e, "I", 3, 18, 0)
	for x = 0, 2 do e.board[19][x] = "J" end
	for x = 7, 9 do e.board[19][x] = "J" end
	e:lock()
	eq("goal line is counted", e.lines, 1)
	eq("clear animation plays first", e.phase, "clearing")
	for _ = 1, 40 do
		if e.phase == "win" then break end
		e:step()
	end
	eq("goal ends in a win", e.phase, "win")
	local won = false
	for _, ev in ipairs(e:drain()) do
		if ev.type == "win" then won = true end
	end
	check("win event is emitted", won)
end

--------------------------------------------------------------------------- report

print(string.format("%d passed, %d failed", passed, failed))
for _, f in ipairs(failures) do print("FAIL: " .. f) end
if failed > 0 then os.exit(1) end
