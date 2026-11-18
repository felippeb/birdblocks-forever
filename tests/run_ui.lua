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
eq("default profile", UI.db.profile, "modern")
eq("default speed", UI.db.speed, 5)
eq("normal mode by default", UI.db.mode, "normal")
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

-- speed select on the title
UI:Close()
UI:Open(false)
UI.engine.phase = "title"
Mock.SendKey(UI.frame, "RIGHT", true)
Mock.SendKey(UI.frame, "RIGHT", false)
eq("right raises speed", UI.db.speed, 6)
Mock.SendKey(UI.frame, "LEFT", true)
Mock.SendKey(UI.frame, "LEFT", false)
eq("left lowers speed", UI.db.speed, 5)

-- key repeat is ignored, so holding right does not race the speed selector
Mock.SendKey(UI.frame, "RIGHT", true)
Mock.SendKey(UI.frame, "RIGHT", true)
eq("held key is not repeated", UI.db.speed, 6)
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

-- Escape belongs to the client: it is never swallowed, and the game menu
-- pauses the run while it is open.
Mock.SendKey(UI.frame, "ESCAPE", true)
Mock.SendKey(UI.frame, "ESCAPE", false)
eq("escape leaves the game running", e.phase, "falling")
eq("escape propagates to the client", UI.frame.propagate, true)
check("window stays open under escape", UI:IsShown())

GameMenuFrame:Show()
eq("the game menu pauses the run", e.phase, "paused")
check("the menu takes the keyboard", UI.frame.keyboard == false)
check("the cabinet steps aside for the menu", UI.frame.shown == false)
GameMenuFrame:Hide()
eq("closing the menu resumes the run", e.phase, "falling")
check("the keyboard comes back", UI.frame.keyboard == true)
check("the cabinet comes back", UI.frame.shown == true)

Mock.SendKey(UI.frame, "P", true)
Mock.SendKey(UI.frame, "P", false)
eq("P pauses", e.phase, "paused")
UI:Close()
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

-- Closing the window mid-flight is final for that flight: it must not pop
-- back open a second later, but the next flight must still open normally.
Mock.taxi = true
advance(2.0)
check("opens on the next flight", UI:IsShown())
UI:Close()
advance(4.0)
check("closing mid-flight keeps it closed", not UI:IsShown())
Mock.taxi = false
advance(3.0)
Mock.taxi = true
advance(2.0)
check("the flight after that opens again", UI:IsShown())
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

SlashCmdList["BIRDBLOCKS"]("modern")
eq("slash returns to modern", UI.db.profile, "modern")
eq("manual profile choice is remembered", UI.db.profilePicked, true)
eq("modern has 20 rows", UI.engine.rows, 20)

SlashCmdList["BIRDBLOCKS"]("zoom 6")
eq("zoom saved", UI.db.zoom, 6)
eq("render scale applied", UI.render:getScale(), 6)
SlashCmdList["BIRDBLOCKS"]("zoom 0")
check("auto zoom", UI.render:getScale() >= 2)

SlashCmdList["BIRDBLOCKS"]("speed 7")
eq("speed setting", UI.db.speed, 7)
SlashCmdList["BIRDBLOCKS"]("level 5")
eq("level is a speed alias", UI.db.speed, 5)
SlashCmdList["BIRDBLOCKS"]("reset")
eq("high scores cleared", next(UI.db.hi), nil)

SlashCmdList["BIRDBLOCKS"]("auto")
eq("auto-open toggled off", UI.db.autoOpen, false)
SlashCmdList["BIRDBLOCKS"]("auto")
eq("auto-open toggled on", UI.db.autoOpen, true)

--------------------------------------------------------------------------- modern input

UI:Open(false)
UI:StartGame()
local me = UI.engine
me.areTimer = 1
me:step()
eq("modern is the default engine", me.profile.id, "modern")
eq("modern starts at speed 5", me.level, 5)

-- Space is a hard drop: the piece locks at once and scores two per row.
me.piece.type, me.piece.x, me.piece.y, me.piece.rot = "T", 3, 0, 0
me.score = 0
Mock.SendKey(UI.frame, "SPACE", true)
Mock.SendKey(UI.frame, "SPACE", false)
check("space hard drops", me.piece == nil, me.phase)
check("space hard drop scores", me.score > 0, me.score)
UI:Tick()
check("hard drop sound", Mock.CountSounds("hard") >= 1)

-- C holds the active piece, once.
UI:StartGame()
local he = UI.engine
he.areTimer = 1
he:step()
local first = he.piece.type
Mock.SendKey(UI.frame, "C", true)
Mock.SendKey(UI.frame, "C", false)
eq("C holds a piece", he.holdType, first)
eq("C disables hold until lock", he.canHold, false)
UI:Tick()
check("hold sound", Mock.CountSounds("hold") >= 1)

-- The modern screen draws a ghost, a hold box and a three-piece queue.
check("modern has a ghost", #he:ghostCells() == 4)
eq("modern queues three pieces", he:queueSize(), 3)
check("modern draws a hold box", UI.screen.layout.holdBox ~= nil)
eq("modern uses neon blocks", UI.screen.layout.tile, "neon_block")
eq("modern has a ghost tile", UI.screen.layout.ghostTile, "neon_ghost")

-- Space also starts a game from the title and restarts after game over.
UI:Close()
UI:Open(false)
UI.engine.phase = "title"
Mock.SendKey(UI.frame, "SPACE", true)
Mock.SendKey(UI.frame, "SPACE", false)
check("space starts from the title", UI.engine.phase ~= "title", UI.engine.phase)
UI.engine.phase = "over"
Mock.SendKey(UI.frame, "SPACE", true)
Mock.SendKey(UI.frame, "SPACE", false)
check("space restarts after game over", UI.engine.phase ~= "over", UI.engine.phase)
UI:Close()

--------------------------------------------------------------------------- broken mode

UI:Open(false)
UI.engine.phase = "title"
Mock.SendKey(UI.frame, "B", true)
Mock.SendKey(UI.frame, "B", false)
eq("B toggles broken mode on the title", UI.db.mode, "broken")
UI:StartGame()
local be = UI.engine
eq("broken run", be.mode, "broken")
eq("broken goal", be.goal, 25)
local garbage = 0
for y = 0, be.rows - 1 do
	for x = 0, be.cols - 1 do
		if be.board[y][x] == "G" then garbage = garbage + 1 end
	end
end
check("broken starts with garbage", garbage > 0)
check("broken leaves headroom", be.board[0][0] == false)
be.score = 4321
UI:RecordScore()
eq("broken high scores are separate", UI.db.hi["modern:broken"], 4321)
check("normal high score is untouched", UI.db.hi["modern"] ~= 4321)

SlashCmdList["BIRDBLOCKS"]("normal")
eq("normal mode selected", UI.db.mode, "normal")
UI:StartGame()
eq("normal run starts clean", UI.engine.mode, "normal")
UI:Close()

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

-- The theme is re-armed just before it ends, not after a gap of silence.
local themed = Mock.CountSounds("theme")
Mock.time = Mock.time + (BirdBlocksAudio.themeLength - 0.2)
UI:SyncAudio()
BirdBlocks.Sound.Tick()
check("theme loops before it runs out", Mock.CountSounds("theme") > themed)

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

--------------------------------------------------------------------------- renderer pooling

-- A texture reused as a solid rect after drawing atlas art must switch back
-- to colour mode even when the requested colour equals the tile's vertex
-- colour; otherwise the previous frame's tile shows through the bezel.
local R = BirdBlocks.Render
local layer = UI.render:layer(R.LAYER_FIELD)
UI.render:beginFrame()
UI.render:tile("gb_block", 0, 0, 8, 8, 1, 1, 1, 1)
UI.render:finish()
UI.render:beginFrame()
UI.render:rect(0, 0, 8, 8, 1, 1, 1, 1, R.LAYER_FIELD)
local tex = layer.tex[1]
check("rect after tile switches to colour mode", tex.colorMode == true)
check("rect after tile resets the atlas UV", tex.uv ~= nil and tex.uv[1] == 0 and tex.uv[3] == 1)
UI.render:finish()

--------------------------------------------------------------------------- report

print(string.format("%d passed, %d failed", passed, failed))
for _, f2 in ipairs(failures) do print("FAIL: " .. f2) end
if failed > 0 then os.exit(1) end
