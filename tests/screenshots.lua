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

-- 1. Game Boy title
UI:Open(false)
Mock.time = 0.2
frame("gb_title")

-- 2. Game Boy gameplay
Mock.SendKey(UI.frame, "ENTER", true)
Mock.SendKey(UI.frame, "ENTER", false)
local e = UI.engine
e:step() -- ARE -> spawn
paint(e, NICE_GB)
e.score, e.lines, e.level = 12340, 37, 4
e.nextType = "S"
e.piece = { type = "I", x = 5, y = 3, rot = 1 }
Mock.Advance(0.05)
frame("gb_game")

-- 3. Game Boy pause
e:togglePause()
frame("gb_pause")
e:togglePause()

-- 4. Game Boy line clear blink
e.phase = "clearing"
e.clearTimer = 34
e.clearRows = { 16 }
e.piece = nil
frame("gb_clear")
e.phase = "falling"
e.clearRows = {}
e.piece = { type = "T", x = 3, y = 6, rot = 0 }

-- 5. Game Boy game over
e.phase = "over"
e.score = 98760
frame("gb_over")

-- 6. SNES mode title + gameplay
UI:SetProfile("snes")
Mock.time = 0.4
frame("snes_title")

Mock.SendKey(UI.frame, "ENTER", true)
Mock.SendKey(UI.frame, "ENTER", false)
e = UI.engine
e:step() -- ARE -> spawn
paint(e, NICE_SNES)
e.score, e.lines, e.level = 54320, 88, 8
e.nextType = "Z"
e.piece = { type = "L", x = 3, y = 4, rot = 1 }
Mock.Advance(0.05)
frame("snes_game")

e:togglePause()
frame("snes_pause")

print("\nwrote draw lists to " .. outdir)
