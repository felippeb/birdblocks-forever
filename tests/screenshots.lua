-- Renders real addon frames against the WoW mock and writes draw lists that
-- tests/rasterize.py turns into PNGs.
--
--   lua tests/screenshots.lua
--   python tests/rasterize.py tests/out
--
-- The point is to see the actual layout and atlas, not a mock-up: these are
-- the same quad calls the game makes in game.

local Mock = dofile("tests/wow_mock.lua")
Mock.Reset()

local ADDON = "BirdBlocks"
local files = {
	"generated_atlas.lua",
	"generated_audio.lua",
	"engine.lua",
	"render.lua",
	"view.lua",
	"sound.lua",
	"ui.lua",
}
for _, name in ipairs(files) do
	local chunk = assert(loadfile("BirdBlocks/src/" .. name))
	chunk(ADDON)
end

Mock.FireEvent("ADDON_LOADED", ADDON)

local UI = BirdBlocks.UI
local outdir = "tests/out/"
os.execute("mkdir " .. outdir .. " 2>nul")

local function frame(name)
	UI:Draw()
	local draws = Mock.Capture(UI.render)
	local w, h = UI.render:pixelWidth(), UI.render:pixelHeight()
	Mock.WriteDraws(outdir .. name .. ".txt", draws, w, h)
	print(string.format("%-14s %dx%d  %d quads", name, w, h, #draws))
end

local function paint(engine, rows)
	local legend = { I = "I", J = "J", L = "L", O = "O", S = "S", T = "T", Z = "Z", X = "T" }
	for y = 1, #rows do
		local row = rows[y]
		for x = 1, #row do
			local ch = row:sub(x, x)
			if ch ~= "." then
				engine.board[y - 1][x - 1] = legend[ch] or "T"
			end
		end
	end
end

local NICE_MODERN = {
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"........L.",
	".......LLL",
	"...S....L.",
	"...SS.ZZ..",
	".JJSSZZTT.",
	"JJJOOZZTTT",
}

local NICE_GB = {
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"....T.....",
	"...TTT....",
	"..........",
	"..........",
	"....L.....",
	"...LLL....",
	".S..L.....",
	"SS.SLL..J.",
	"SSZZ.L..JJ",
}

local NICE_SNES = {
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	".......L..",
	"......LLL.",
	"....Z..L..",
	"..ZZOOT...",
	"..ZOOOOT..",
	"..ZOO.SST.",
	"..ISSSSITT",
}

local function title(name, profile, time)
	UI:SetProfile(profile)
	Mock.time = time
	frame(name)
end

local function play(name, profile, nice, score, lines, level, piece, hold, opts)
	UI:SetProfile(profile)
	local e = UI.engine
	e:start(level, opts)
	e.areTimer = 1
	e:step() -- ARE -> spawn
	paint(e, nice)
	e.score, e.lines, e.level = score, lines, level
	e.piece = piece
	if hold then
		e.holdType = hold
		e.canHold = false
	end
	frame(name)
	return e
end

-- Modern neon cabinet. The default (classic) rules: one piece ahead, no hold.
title("modern_title", "modern", 0.2)
local m = play("modern_game", "modern", NICE_MODERN, 4850, 12, 5,
	{ type = "I", x = 3, y = 2, rot = 0 }, nil,
	{ preview = 1, hold = false, mode = "classic" })

-- B-Type start: random garbage, 25-line goal.
UI:SetProfile("modern")
local b = UI.engine
b:start(5, { garbage = 0.5, goal = 25, preview = 1, hold = false, mode = "broken" })
b.areTimer = 1
b:step()
b.score, b.lines, b.level = 2480, 9, 5
b.piece = { type = "T", x = 3, y = 2, rot = 0 }
frame("modern_broken")

m:togglePause()
frame("modern_pause")
m:togglePause()

m.phase = "clearing"
m.clearTimer = 18
m.clearRows = { 18, 19 }
m.piece = nil
frame("modern_clear")

m.phase = "over"
m.score = 128450
frame("modern_over")

-- Game Boy, for the 1989 ruleset.
title("gb_title", "gb", 0.2)
local g = play("gb_game", "gb", NICE_GB, 12340, 37, 4,
	{ type = "I", x = 5, y = 3, rot = 1 })

g:togglePause()
frame("gb_pause")
g:togglePause()

g.phase = "clearing"
g.clearTimer = 34
g.clearRows = { 16 }
g.piece = nil
frame("gb_clear")

g.phase = "over"
g.score = 98760
frame("gb_over")

-- SNES / NES, same rules, different timings and palette.
title("snes_title", "snes", 0.4)
local s = play("snes_game", "snes", NICE_SNES, 54320, 88, 8,
	{ type = "L", x = 3, y = 4, rot = 1 })

s:togglePause()
frame("snes_pause")
s:togglePause()

s.phase = "over"
s.score = 246800
frame("snes_over")

print("\nwrote draw lists to " .. outdir)
