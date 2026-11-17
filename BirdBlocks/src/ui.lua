-- Bird Blocks: window, input, and the 60 Hz loop.
--
-- The game window is a plain movable frame with a thin bezel around a
-- pixel-exact view. It opens by itself when the player gets on a flight-path
-- taxi ("the bird"), pauses in combat, and everything is driven by real
-- keyboard input so it plays like the handheld.

local ADDON = ...
BirdBlocks = BirdBlocks or {}
local BB = BirdBlocks

local UI = {}
BB.UI = UI

local Engine, Render, View, Sound = BB.Engine, BB.Render, BB.View, BB.Sound
local floor, min, max = math.floor, math.min, math.max

local DEFAULTS = {
	profile = "gb",
	zoom = 0,          -- 0 = fit the screen
	sound = true,
	music = true,
	autoOpen = true,
	startLevel = 0,
	hi = {},
	games = 0,
	pos = nil,
}

local PAD = 6
local BAR = 22

-- key -> game action. Arrows move, Up/X rotate, Z/Ctrl rotate back.
local KEYMAP = {
	LEFT = "left", A = "left",
	RIGHT = "right", D = "right",
	DOWN = "down", S = "down",
	UP = "rotate_cw", W = "rotate_cw", X = "rotate_cw",
	Z = "rotate_ccw", LCTRL = "rotate_ccw", RCTRL = "rotate_ccw",
	P = "pause", PAUSE = "pause",
	SPACE = "start", ENTER = "start",
	M = "music",
	MINUS = "zoomout", NUMPADMINUS = "zoomout",
	EQUALS = "zoomin", PLUS = "zoomin", NUMPADPLUS = "zoomin",
}

local function clampLevel(n)
	return max(0, min(9, n))
end

function UI:Print(msg)
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage("|cff38c849Bird Blocks|r " .. tostring(msg))
	end
end

--------------------------------------------------------------------------- setup

function UI:Init()
	BirdBlocksDB = BirdBlocksDB or {}
	self.db = BirdBlocksDB
	for k, v in pairs(DEFAULTS) do
		if self.db[k] == nil then
			if type(v) == "table" then
				self.db[k] = {}
			else
				self.db[k] = v
			end
		end
	end
	self.db.hi = self.db.hi or {}
	if not View.LAYOUT[self.db.profile] then self.db.profile = "gb" end

	Sound.Init(BirdBlocksAudio, { sfx = self.db.sound, music = self.db.music })
	self:CreateFrame()
	self:SetProfile(self.db.profile, true)
	self:ApplyScale()
	self:ApplyPosition()
	self:RegisterSlash()

	self.shown = false
	self.accumulator = 0
	self.autoOpened = false
	self.taxiTime = 0
	self.taxiGone = 0
	self.rideOpened = false
	self.reopenAfterCombat = false
	self.keysHeld = {}
	self.ready = true
end

function UI:CreateFrame()
	if self.frame then return end
	local f = CreateFrame("Frame", "BirdBlocksFrame", UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:EnableMouseWheel(true)
	f:Hide()
	self.frame = f

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(f)
	bg:SetColorTexture(0.05, 0.06, 0.05, 0.94)
	self.bg = bg

	-- drag bar
	local bar = CreateFrame("Frame", nil, f)
	bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	bar:SetHeight(BAR)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() f:StartMoving() end)
	bar:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		UI:SavePosition()
	end)

	local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("LEFT", bar, "LEFT", 8, 0)
	title:SetText("|cff9bbc0fBIRD BLOCKS|r  |cff777777arrows move, up rotate, esc pause, m music, wheel zoom|r")
	self.titleText = title

	local close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
	close:SetPoint("RIGHT", bar, "RIGHT", 2, 0)
	close:SetScript("OnClick", function() UI:Close() end)

	local view = CreateFrame("Frame", nil, f)
	view:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(BAR + PAD))
	view:SetFrameLevel(f:GetFrameLevel() + 1)
	if view.SetClipsChildren then view:SetClipsChildren(true) end
	self.viewFrame = view

	local vbg = view:CreateTexture(nil, "BACKGROUND")
	vbg:SetAllPoints(view)
	vbg:SetColorTexture(0, 0, 0, 1)
	self.viewBg = vbg

	self.render = Render.new(view)
	self.screen = View.new(self.render, self.db.profile)

	f:SetScript("OnUpdate", function(_, elapsed) UI:OnUpdate(elapsed) end)
	f:SetScript("OnHide", function()
		if UI.engine and (UI.engine.phase == "falling" or UI.engine.phase == "are" or UI.engine.phase == "clearing") then
			UI.engine:togglePause()
		end
		Sound.StopMusic()
	end)
	f:EnableKeyboard(true)
	f:SetScript("OnKeyDown", function(_, key) UI:OnKeyDown(key) end)
	f:SetScript("OnKeyUp", function(_, key) UI:OnKeyUp(key) end)
	f:SetScript("OnMouseWheel", function(_, delta) UI:Zoom(delta) end)
	if f.SetPropagateKeyboardInput then f:SetPropagateKeyboardInput(false) end
end

function UI:SetProfile(id, initial)
	if not View.LAYOUT[id] then id = "gb" end
	local changed = self.db.profile ~= id or not self.engine
	self.db.profile = id
	if not changed and not initial then return end
	self.screen:setProfile(id)
	self.engine = Engine.new(id)
	self.engine.phase = "title"
	if initial then
		self.db.startLevel = clampLevel(self.db.startLevel or 0)
	end
	self:ApplyScale()
	self:ApplyTheme()
	if self.shown then self:Draw() end
end

function UI:ApplyTheme()
	if not self.bg then return end
	if self.db.profile == "gb" then
		self.bg:SetColorTexture(0.10, 0.20, 0.10, 0.95)
	else
		self.bg:SetColorTexture(0.03, 0.03, 0.05, 0.95)
	end
end

function UI:AutoScale()
	local sw = (UIParent and UIParent:GetWidth()) or 1024
	local sh = (UIParent and UIParent:GetHeight()) or 768
	if sw < 100 then sw = 1024 end
	if sh < 100 then sh = 768 end
	local vw, vh = self.screen:screenSize()
	local s = floor(min((sw * 0.70) / vw, (sh * 0.78) / vh))
	return max(2, min(8, s))
end

function UI:CurrentScale()
	local z = tonumber(self.db.zoom) or 0
	if z >= 1 then return max(1, min(8, floor(z))) end
	return self:AutoScale()
end

function UI:ApplyScale()
	if not self.render then return end
	local s = self:CurrentScale()
	self.render:setScale(s)
	self.render:resizeFrame()
	local vw, vh = self.screen:screenSize()
	local pw, ph = vw * s, vh * s
	if self.viewFrame then self.viewFrame:SetSize(pw, ph) end
	if self.frame then self.frame:SetSize(pw + PAD * 2, ph + PAD * 2 + BAR) end
end

function UI:ApplyPosition()
	if not self.frame then return end
	self.frame:ClearAllPoints()
	local p = self.db.pos
	if p and p.x and p.y then
		self.frame:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
	else
		self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
end

function UI:SavePosition()
	if not self.frame or not self.frame:IsShown() then return end
	local cx, cy = self.frame:GetCenter()
	local sw = (UIParent and UIParent:GetWidth()) or 1024
	local sh = (UIParent and UIParent:GetHeight()) or 768
	if cx and cy then
		self.db.pos = { x = floor(cx - sw / 2 + 0.5), y = floor(cy - sh / 2 + 0.5) }
	end
end

function UI:Zoom(delta)
	local s = self:CurrentScale() + (delta > 0 and 1 or -1)
	s = max(1, min(8, s))
	self.db.zoom = s
	self:ApplyScale()
	if self.shown then self:Draw() end
end

--------------------------------------------------------------------------- visibility

function UI:IsShown()
	return self.shown and self.frame and self.frame:IsShown()
end

function UI:Open(auto)
	if not self.ready then return end
	if self.shown then return end
	self.shown = true
	self.autoOpened = auto and true or false
	self.accumulator = 0
	self.keysHeld = {}
	-- One automatic open per flight: if the player closes the window while
	-- still flying, leave it closed until the next taxi.
	if UnitOnTaxi and UnitOnTaxi("player") then
		self.rideOpened = true
	end
	self.frame:Show()
	self.frame:EnableKeyboard(true)
	-- Reopening always resumes a paused game: otherwise landing and taking
	-- off again would greet the player with a PAUSE box.
	if self.engine.phase == "paused" then
		self.engine:togglePause()
	end
	-- On the bird there is no menu: a fresh flight starts a fresh game.
	if auto and (self.engine.phase == "title" or self.engine.phase == "over") then
		self:StartGame()
	end
	self:Draw()
end

function UI:Close()
	if not self.ready or not self.shown then return end
	self:SavePosition()
	self.shown = false
	self.autoOpened = false
	self.keysHeld = {}
	if self.engine and (self.engine.phase == "falling" or self.engine.phase == "are" or self.engine.phase == "clearing") then
		self.engine:togglePause()
	end
	self.frame:EnableKeyboard(false)
	self.frame:Hide()
	Sound.StopMusic()
end

function UI:Toggle()
	if self:IsShown() then self:Close() else self:Open(false) end
end

function UI:StartGame()
	if not self.engine then return end
	self.engine:start(self.db.startLevel)
	Sound.Play("start")
	if self.db.music then Sound.StartMusic() end
end

function UI:RecordScore()
	local e = self.engine
	if not e then return end
	local hi = self.db.hi[e.profile.id] or 0
	if e.score > hi then
		self.db.hi[e.profile.id] = e.score
		self:Print(string.format("new high score: %d", e.score))
	end
	self.db.games = (self.db.games or 0) + 1
end

--------------------------------------------------------------------------- input

function UI:OnKeyDown(key)
	if not self.shown then return end
	if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() then return end
	if self.keysHeld[key] then return end
	self.keysHeld[key] = true
	if self.frame and self.frame.SetPropagateKeyboardInput then
		self.frame:SetPropagateKeyboardInput(false)
	end

	local e = self.engine
	if not e then return end

	if key == "ESCAPE" then
		if e.phase == "falling" or e.phase == "are" or e.phase == "clearing" then
			e:togglePause()
			Sound.Play("pause")
			self:Draw()
		else
			self:Close()
		end
		return
	end

	local action = KEYMAP[key]
	if not action then return end

	if action == "music" then
		self.db.music = not self.db.music
		Sound.SetMusic(self.db.music)
		self:Print("music " .. (self.db.music and "on" or "off"))
		return
	elseif action == "zoomin" then
		self:Zoom(1)
		return
	elseif action == "zoomout" then
		self:Zoom(-1)
		return
	end

	if e.phase == "title" then
		if action == "left" then
			self.db.startLevel = clampLevel((self.db.startLevel or 0) - 1)
			self:Draw()
		elseif action == "right" then
			self.db.startLevel = clampLevel((self.db.startLevel or 0) + 1)
			self:Draw()
		elseif action == "start" then
			self:StartGame()
			self:Draw()
		end
		return
	end

	if e.phase == "over" then
		if action == "start" then
			self:StartGame()
			self:Draw()
		end
		return
	end

	if action == "start" and e.phase == "paused" then
		e:togglePause()
		Sound.Play("pause")
		self:Draw()
		return
	end

	if e.phase == "paused" then
		if action == "pause" then
			e:togglePause()
			Sound.Play("pause")
			self:Draw()
		end
		return
	end

	if action == "start" or action == "pause" then
		if action == "pause" then
			e:togglePause()
			Sound.Play("pause")
			self:Draw()
		end
		return
	end

	e:press(action)
end

function UI:OnKeyUp(key)
	if not self.engine then return end
	self.keysHeld[key] = nil
	if not self.shown then return end
	local action = KEYMAP[key]
	if action == "left" or action == "right" or action == "down" then
		self.engine:release(action)
	end
end

--------------------------------------------------------------------------- loop

-- Music belongs to the game, not the window: it plays while a piece is in
-- play and stops on pause, game over, title and close. Keeping it in one
-- place means every path (key, taxi, combat) behaves the same way.
function UI:SyncAudio()
	if not Sound.audio then return end
	local e = self.engine
	local active = self.shown and e and
		(e.phase == "falling" or e.phase == "are" or e.phase == "clearing")
	if active and self.db.music then
		if not Sound.playing and Sound.CanStart() then Sound.StartMusic() end
	elseif Sound.playing then
		Sound.StopMusic()
	end
end

function UI:OnUpdate(elapsed)
	if not self.shown then return end
	self:SyncAudio()
	if elapsed > 0.25 then elapsed = 0.25 end
	self.accumulator = self.accumulator + elapsed
	local ticks = floor(self.accumulator * 60)
	if ticks < 1 then return end
	if ticks > 6 then
		ticks = 6
		self.accumulator = 0
	else
		self.accumulator = self.accumulator - ticks / 60
	end
	for _ = 1, ticks do self:Tick() end
	self:Draw()
	Sound.Tick()
end

function UI:Tick()
	local e = self.engine
	if not e then return end
	if e.phase == "title" or e.phase == "over" then return end
	if e.phase ~= "paused" then e:step() end
	for _, ev in ipairs(e:drain()) do
		if ev.type == "move" then
			Sound.Play("move")
		elseif ev.type == "rotate" then
			Sound.Play("rotate")
		elseif ev.type == "lock" then
			Sound.Play("lock")
		elseif ev.type == "line" then
			Sound.Play(ev.tetris and "tetris" or "line")
		elseif ev.type == "level" then
			Sound.Play("level")
		elseif ev.type == "over" then
			Sound.Play("over")
			self:RecordScore()
		end
	end
end

function UI:Blink()
	local t = GetTime and GetTime() or 0
	return floor(t * 1.6) % 2 == 0
end

function UI:Draw()
	if not self.render or not self.engine then return end
	local r = self.render
	local e = self.engine
	local hi = self.db.hi[e.profile.id] or 0

	r:beginFrame()
	if e.phase == "title" then
		self.screen:drawTitle(e, {
			frame = floor((GetTime and GetTime() or 0) * 60),
			highScore = hi,
			startLevel = self.db.startLevel,
			blink = self:Blink(),
		})
	else
		local flashOff = false
		if e.phase == "clearing" then
			flashOff = floor((e.clearTimer or 0) / 4) % 2 == 1
		end
		self.screen:drawGame(e, {
			highScore = hi,
			clearing = e.clearRows,
			flashOff = flashOff,
		})
		if e.phase == "paused" then
			self.screen:drawBox({ { "PAUSE", 2 }, { "P TO RESUME", 1 } })
		elseif e.phase == "over" then
			self.screen:drawBox({
				{ "GAME OVER", 2 },
				{ "SCORE " .. View.pad(e.score, 6), 1 },
				{ "PRESS ENTER", 1 },
			})
		end
	end
	r:finish()
end

--------------------------------------------------------------------------- taxi / combat

function UI:OnCombat()
	if not self:IsShown() then return end
	self.reopenAfterCombat = self.autoOpened or (UnitOnTaxi and UnitOnTaxi("player"))
	if self.engine and (self.engine.phase == "falling" or self.engine.phase == "are" or self.engine.phase == "clearing") then
		self.engine:togglePause()
	end
	self:Close()
end

function UI:PollTaxi(elapsed)
	if not self.db.autoOpen then
		self.taxiTime = 0
		self.rideOpened = false
		return
	end
	local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
	if onTaxi then
		self.taxiGone = 0
		self.taxiTime = self.taxiTime + elapsed
		-- One automatic open per flight: closing the window mid-air means the
		-- player is done playing, not that they want it back a second later.
		if self.taxiTime >= 1.5 and not self.shown
			and not self.rideOpened and not self.reopenAfterCombat then
			if not (InCombatLockdown and InCombatLockdown()) then
				self.rideOpened = true
				self:Open(true)
			end
		end
	else
		self.taxiTime = 0
		self.rideOpened = false
		if self.shown and self.autoOpened then
			self.taxiGone = self.taxiGone + elapsed
			if self.taxiGone >= 2 then
				self.taxiGone = 0
				self:Close()
			end
		end
	end
end

--------------------------------------------------------------------------- slash

function UI:RegisterSlash()
	local function handler(msg)
		msg = tostring(msg or ""):lower()
		local cmd, rest = msg:match("^(%S*)%s*(.*)$")
		if cmd == "" or cmd == "toggle" then
			self:Toggle()
		elseif cmd == "gb" or cmd == "gameboy" then
			self:SetProfile("gb")
			self:Print("Game Boy mode")
		elseif cmd == "snes" or cmd == "nes" then
			self:SetProfile("snes")
			self:Print("SNES mode")
		elseif cmd == "auto" then
			self.db.autoOpen = not self.db.autoOpen
			self:Print("auto-open on taxi " .. (self.db.autoOpen and "on" or "off"))
		elseif cmd == "music" then
			self.db.music = not self.db.music
			Sound.SetMusic(self.db.music)
			self:Print("music " .. (self.db.music and "on" or "off"))
		elseif cmd == "sound" then
			self.db.sound = not self.db.sound
			Sound.SetSFX(self.db.sound)
			self:Print("sound " .. (self.db.sound and "on" or "off"))
		elseif cmd == "zoom" then
			local n = tonumber(rest)
			if n then
				if n <= 0 then
					self.db.zoom = 0
				else
					self.db.zoom = max(1, min(8, floor(n)))
				end
				self:ApplyScale()
				if self.shown then self:Draw() end
				self:Print("zoom " .. self:CurrentScale() .. (self.db.zoom == 0 and " (auto)" or ""))
			else
				self:Print("zoom: " .. self:CurrentScale() .. " (use /blocks zoom 4)")
			end
		elseif cmd == "level" then
			local n = tonumber(rest)
			if n then
				self.db.startLevel = clampLevel(floor(n))
				self:Print("start level " .. self.db.startLevel)
			end
		elseif cmd == "reset" then
			self.db.hi = {}
			self:Print("high scores cleared")
		elseif cmd == "help" then
			self:Print("/blocks - open or close")
			self:Print("/blocks gb|snes - pick the version")
			self:Print("/blocks auto - auto-open on taxi")
			self:Print("/blocks music|sound - toggle audio")
			self:Print("/blocks zoom N - 1..8, 0 = fit screen")
			self:Print("/blocks level N - starting level 0..9")
			self:Print("/blocks reset - clear high scores")
		else
			self:Print("unknown option; try /blocks help")
		end
	end
	SLASH_BIRDBLOCKS1 = "/blocks"
	SLASH_BIRDBLOCKS2 = "/bb"
	SlashCmdList["BIRDBLOCKS"] = handler
end

--------------------------------------------------------------------------- bootstrap

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_REGEN_DISABLED")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")

local initialized = false
loader:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		if name ~= ADDON then return end
		initialized = true
		UI:Init()
	elseif event == "PLAYER_REGEN_DISABLED" then
		if UI.ready then UI:OnCombat() end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if not UI.ready then return end
		local reopen = UI.reopenAfterCombat
		UI.reopenAfterCombat = false
		if reopen and UI.db.autoOpen and (UnitOnTaxi and UnitOnTaxi("player")) then
			UI:Open(true)
		end
	end
end)

local poll = 0
loader:SetScript("OnUpdate", function(_, elapsed)
	if not initialized then return end
	poll = poll + elapsed
	if poll < 0.25 then return end
	UI:PollTaxi(poll)
	poll = 0
end)

-- exposed for tests
UI._initialized = function() return initialized end
UI._KEYMAP = KEYMAP
