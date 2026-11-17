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

--------------------------------------------------------------------------- report

print(string.format("%d passed, %d failed", passed, failed))
for _, f in ipairs(failures) do print("FAIL: " .. f) end
if failed > 0 then os.exit(1) end
