-- Randomised playthrough against the mock client.
--
--   lua tests/run_stress.lua
--
-- Drives the real addon with deterministic pseudo-random input for 20,000
-- frames (a bit over five minutes of play), cycling through game over, restart
-- and pause, and checks that the engine state stays inside the board. Anything
-- nil, out of range or inconsistent throws here rather than in game.

local Mock = dofile("tests/wow_mock.lua")
Mock.Reset()

local ADDON = "BirdBlocks"
for _, name in ipairs({
	"generated_atlas.lua",
	"generated_audio.lua",
	"engine.lua",
	"render.lua",
	"view.lua",
	"sound.lua",
	"ui.lua",
}) do
	assert(loadfile("BirdBlocks/src/" .. name))(ADDON)
end

Mock.FireEvent("ADDON_LOADED", ADDON)
local UI = BirdBlocks.UI
local Sound = BirdBlocks.Sound

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

local function lcg(seed)
	local s = seed
	return function(n)
		s = (1103515245 * s + 12345) % 2147483648
		return 1 + math.floor(s / 2147483648 * n)
	end
end
local rand = lcg(20261117)

UI:Open(false)
Mock.SendKey(UI.frame, "ENTER", true)
Mock.SendKey(UI.frame, "ENTER", false)
Mock.Advance(1 / 60)

local ACTIONS = { "LEFT", "RIGHT", "DOWN", "UP", "Z" }
local held = {}
local overs, restarts = 0, 0
local lastPhase = UI.engine.phase

local function releaseAll()
	for key in pairs(held) do
		Mock.SendKey(UI.frame, key, false)
		held[key] = nil
	end
end

local function size(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

local function checkBoard(tag)
	local e = UI.engine
	-- Board rows and cells are 0-indexed, so the # operator is not reliable.
	if size(e.board) ~= e.rows then
		check(tag .. ": board rows", false, size(e.board))
		return
	end
	for y = 0, e.rows - 1 do
		if size(e.board[y]) ~= e.cols then
			check(tag .. ": board cols at " .. y, false, size(e.board[y]))
			return
		end
	end
	if e.piece then
		local cells = e:pieceCells()
		for i = 1, #cells do
			local x, y = cells[i][1], cells[i][2]
			if x < 0 or x >= e.cols or y >= e.rows then
				check(tag .. ": piece inside the field", false, x .. "," .. y)
				return
			end
		end
	end
	if e.score < 0 or e.score > 999999 then
		check(tag .. ": score range", false, e.score)
	end
	if e.level < 0 or e.level > e.profile.maxLevel then
		check(tag .. ": level range", false, e.level)
	end
	check(tag .. ": state consistent", true)
end

for frame = 1, 20000 do
	-- Random taps with short holds, like a real player.
	if frame % 5 == 0 then
		releaseAll()
	end
	if frame % 3 == 0 then
		local key = ACTIONS[rand(#ACTIONS)]
		if not held[key] then
			Mock.SendKey(UI.frame, key, true)
			held[key] = true
		end
	end

	local phase = UI.engine.phase
	if phase ~= lastPhase then
		if phase == "over" then
			overs = overs + 1
		elseif lastPhase == "over" then
			restarts = restarts + 1
		end
		lastPhase = phase
	end

	-- Recover from pause and game over so the run keeps cycling.
	if phase == "paused" and frame % 11 == 0 then
		releaseAll()
		Mock.SendKey(UI.frame, "P", true)
		Mock.SendKey(UI.frame, "P", false)
	elseif phase == "over" and frame % 17 == 0 then
		releaseAll()
		Mock.SendKey(UI.frame, "ENTER", true)
		Mock.SendKey(UI.frame, "ENTER", false)
	end

	Mock.Advance(1 / 60)

	if frame % 250 == 0 then
		checkBoard("frame " .. frame)
	end
end

releaseAll()

check("the run reached game over at least once", overs >= 1, overs)
check("the run restarted at least once", restarts >= 1, restarts)
check("sound stayed enabled", Sound.sfxEnabled == true)
check("window still open", UI:IsShown())

-- One last frame of drawing after all that state churn.
UI:Draw()
check("draw survives a full session", #Mock.Capture(UI.render) > 0)

print(string.format("%d passed, %d failed (%d game overs, %d restarts)",
	passed, failed, overs, restarts))
for _, f in ipairs(failures) do print("FAIL: " .. f) end
if failed > 0 then os.exit(1) end
