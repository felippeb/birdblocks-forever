-- Integration tests: the whole addon against the mock client.
--   lua tests/run_ui.lua

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

local function advance(seconds)
	local step = 1 / 30
	local t = 0
	while t < seconds do
		Mock.Advance(step)
		t = t + step
	end
end

--------------------------------------------------------------------------- init

check("initialised", UI._initialized())
check("window starts hidden", not UI:IsShown())
eq("default profile", UI.db.profile, "gb")
eq("auto-open on by default", UI.db.autoOpen, true)
eq("saved variables written", type(BirdBlocksDB), "table")
check("engine exists", UI.engine ~= nil)
eq("engine starts on title", UI.engine.phase, "title")

--------------------------------------------------------------------------- manual open

UI:Open(false)
check("open shows the window", UI:IsShown())
check("keyboard enabled while open", UI.frame.keyboard == true)
check("key input does not leak to the world", UI.frame.propagate == false)
check("title screen is silent", Mock.CountSounds("theme") == 0)
eq("title screen first", UI.engine.phase, "title")

Mock.SendKey(UI.frame, "ENTER", true)
Mock.SendKey(UI.frame, "ENTER", false)
advance(0.1)
check("enter starts a game", UI.engine.phase == "falling" or UI.engine.phase == "are")
check("start jingle plays", Mock.CountSounds("start") >= 1)
check("music starts with the game", Mock.CountSounds("theme") >= 1)

-- level select on the title
UI:Close()
UI:Open(false)
UI.engine.phase = "title"
Mock.SendKey(UI.frame, "RIGHT", true)
Mock.SendKey(UI.frame, "RIGHT", false)
eq("right raises start level", UI.db.startLevel, 1)
Mock.SendKey(UI.frame, "LEFT", true)
Mock.SendKey(UI.frame, "LEFT", false)
eq("left lowers start level", UI.db.startLevel, 0)

-- key repeat is ignored, so holding right does not race the level selector
Mock.SendKey(UI.frame, "RIGHT", true)
Mock.SendKey(UI.frame, "RIGHT", true)
eq("held key is not repeated", UI.db.startLevel, 1)
Mock.SendKey(UI.frame, "RIGHT", false)

--------------------------------------------------------------------------- play + pause

Mock.SendKey(UI.frame, "ENTER", true)
Mock.SendKey(UI.frame, "ENTER", false)
advance(0.05)
local e = UI.engine
e:step()
local x = e.piece.x
Mock.SendKey(UI.frame, "LEFT", true)
check("left key moves the piece", e.piece.x == x - 1, e.piece.x)
Mock.SendKey(UI.frame, "LEFT", false)

Mock.SendKey(UI.frame, "P", true)
Mock.SendKey(UI.frame, "P", false)
eq("P pauses", e.phase, "paused")
check("pause sound", Mock.CountSounds("pause") >= 1)

local y = e.piece.y
advance(2)
eq("paused game does not fall", e.piece.y, y)

Mock.SendKey(UI.frame, "P", true)
Mock.SendKey(UI.frame, "P", false)
eq("P resumes", e.phase, "falling")

-- escape pauses while playing, escape again closes
Mock.SendKey(UI.frame, "ESCAPE", true)
Mock.SendKey(UI.frame, "ESCAPE", false)
eq("escape pauses", e.phase, "paused")
Mock.SendKey(UI.frame, "ESCAPE", true)
Mock.SendKey(UI.frame, "ESCAPE", false)
check("escape closes when paused", not UI:IsShown())
check("keyboard released on close", UI.frame.keyboard == false)
check("music stopped on close", BirdBlocks.Sound.playing == false)

--------------------------------------------------------------------------- music toggle

UI:Open(false)
local before = #Mock.sounds
Mock.SendKey(UI.frame, "M", true)
Mock.SendKey(UI.frame, "M", false)
eq("M turns music off", UI.db.music, false)
Mock.SendKey(UI.frame, "M", true)
Mock.SendKey(UI.frame, "M", false)
eq("M turns music back on", UI.db.music, true)
check("music restarted", #Mock.sounds > before)
UI:Close()

--------------------------------------------------------------------------- taxi

Mock.taxi = false
Mock.Advance(0.3)
advance(3)
check("does not open without a taxi", not UI:IsShown())

Mock.taxi = true
advance(2.0)
check("auto-opens on the taxi", UI:IsShown())
check("auto-open starts playing", UI.engine.phase ~= "title")

Mock.taxi = false
advance(3.0)
check("closes when the taxi ends", not UI:IsShown())

-- auto-open off
Mock.taxi = false
UI.db.autoOpen = false
Mock.taxi = true
advance(3.0)
check("respects autoOpen = false", not UI:IsShown())
UI.db.autoOpen = true
Mock.taxi = false
advance(3.0)

--------------------------------------------------------------------------- combat

Mock.taxi = true
advance(2.0)
check("on taxi again", UI:IsShown())
Mock.FireEvent("PLAYER_REGEN_DISABLED")
check("combat closes the game", not UI:IsShown())
Mock.FireEvent("PLAYER_REGEN_ENABLED")
advance(0.5)
check("reopens after combat while still flying", UI:IsShown())
Mock.taxi = false
advance(3.0)

--------------------------------------------------------------------------- scores

UI:Open(false)
UI:StartGame()
UI.engine.score = 777
UI.engine.phase = "over"
UI:RecordScore()
eq("high score saved", UI.db.hi[UI.db.profile], 777)
eq("game counted", UI.db.games, 1)
UI:RecordScore()
eq("lower score does not replace the high score", UI.db.hi[UI.db.profile], 777)

--------------------------------------------------------------------------- slash commands

SlashCmdList["BIRDBLOCKS"]("snes")
eq("slash switches profile", UI.db.profile, "snes")
eq("profile switches the engine", UI.engine.profile.id, "snes")
eq("snes has 20 rows", UI.engine.rows, 20)

SlashCmdList["BIRDBLOCKS"]("gb")
eq("back to game boy", UI.engine.profile.id, "gb")
eq("game boy has 18 rows", UI.engine.rows, 18)

SlashCmdList["BIRDBLOCKS"]("zoom 6")
eq("zoom saved", UI.db.zoom, 6)
eq("render scale applied", UI.render:getScale(), 6)
SlashCmdList["BIRDBLOCKS"]("zoom 0")
check("auto zoom", UI.render:getScale() >= 2)

SlashCmdList["BIRDBLOCKS"]("level 5")
eq("start level", UI.db.startLevel, 5)
SlashCmdList["BIRDBLOCKS"]("reset")
eq("high scores cleared", next(UI.db.hi), nil)

SlashCmdList["BIRDBLOCKS"]("auto")
eq("auto-open toggled off", UI.db.autoOpen, false)
SlashCmdList["BIRDBLOCKS"]("auto")
eq("auto-open toggled on", UI.db.autoOpen, true)

--------------------------------------------------------------------------- window geometry

UI:ApplyScale()
local vw, vh = UI.screen:screenSize()
local s = UI.render:getScale()
eq("view is virtual size times zoom", UI.viewFrame:GetWidth(), vw * s)
eq("frame is view plus bezel", UI.frame:GetWidth(), vw * s + 12)
check("frame height includes the drag bar", UI.frame:GetHeight() == vh * s + 12 + 22)

local f = UI.frame
f:Show()
f:SetPoint("CENTER", 0, 0)
UI:SavePosition()
check("position saved", UI.db.pos ~= nil and UI.db.pos.x ~= nil)

--------------------------------------------------------------------------- loop safety

-- a long stall must not run hundreds of game frames in one update
UI:Open(false)
UI:StartGame()
UI.engine:step()
local frames = UI.engine.frames
Mock.Advance(5.0)
check("stall is clamped", UI.engine.frames - frames <= 8, UI.engine.frames - frames)
UI:Close()

--------------------------------------------------------------------------- resume, audio and restart

UI:Open(false)
UI:StartGame()
UI.engine:step()
advance(0.1)
check("music plays while a piece is in play", BirdBlocks.Sound.playing)

Mock.SendKey(UI.frame, "P", true)
Mock.SendKey(UI.frame, "P", false)
advance(0.1)
check("pause stops the theme", not BirdBlocks.Sound.playing)

Mock.SendKey(UI.frame, "P", true)
Mock.SendKey(UI.frame, "P", false)
advance(0.1)
check("resume restarts the theme", BirdBlocks.Sound.playing)

UI:Close()
eq("closing pauses the run", UI.engine.phase, "paused")
UI:Open(false)
check("reopening resumes the run", UI.engine.phase == "falling" or UI.engine.phase == "are")

-- Game over, then the bird picks us up: a fresh flight starts a fresh run
-- instead of opening on a GAME OVER box.
UI.engine.phase = "over"
UI:Close()
Mock.taxi = true
advance(2.0)
check("taxi starts a new run after game over",
	UI:IsShown() and UI.engine.phase ~= "over")
Mock.taxi = false
advance(3.0)

--------------------------------------------------------------------------- report

print(string.format("%d passed, %d failed", passed, failed))
for _, f2 in ipairs(failures) do print("FAIL: " .. f2) end
if failed > 0 then os.exit(1) end
