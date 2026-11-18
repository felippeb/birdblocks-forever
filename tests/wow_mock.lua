-- Minimal WoW client mock for offline tests.
--
-- Enough of the 1.16 frame API to load the addon, fire events, send keys and
-- capture every texture the renderer touched. Textures record their position,
-- size, UV rect and vertex colour so tests/rasterize.py can turn a frame into
-- a PNG and a human can look at it.

local Mock = {}

Mock.time = 0
Mock.frames = {}
Mock.textures = {}
Mock.sounds = {}
Mock.messages = {}
Mock.taxi = false
Mock.combat = false
Mock.clock = 0

local function copy(t)
	local out = {}
	for k, v in pairs(t) do out[k] = v end
	return out
end

local nextID = 0
local function id(prefix)
	nextID = nextID + 1
	return prefix .. nextID
end

--------------------------------------------------------------------------- texture

local Texture = {}
Texture.__index = Texture

function Texture:SetPoint(point, rel, relPoint, x, y)
	self.point, self.rel, self.relPoint = point, rel, relPoint
	-- WoW call shapes: (point, x, y) or (point, rel, relPoint, x, y)
	if y == nil then
		self.x, self.y = rel or 0, relPoint or 0
	else
		self.x, self.y = x or 0, y or 0
	end
end

function Texture:SetSize(w, h)
	self.w, self.h = w, h
end

function Texture:SetWidth(w) self.w = w end
function Texture:SetHeight(h) self.h = h end
function Texture:Show() self.shown = true end
function Texture:Hide() self.shown = false end
function Texture:IsShown() return self.shown and true or false end

function Texture:SetTexture(path, wrap, wrap2, filter)
	self.path = path
	self.colorMode = false
end

function Texture:SetColorTexture(r, g, b, a)
	self.colorMode = true
	self.fill = { r, g, b, a or 1 }
end

function Texture:SetTexCoord(...)
	local n = select("#", ...)
	local a = { ... }
	if n >= 8 then
		-- ULx, ULy, LLx, LLy, URx, URy, LRx, LRy
		self.uv = { a[1], a[2], a[5], a[8] }
	elseif n >= 4 then
		-- left, right, top, bottom
		self.uv = { a[1], a[3], a[2], a[4] }
	else
		self.uv = nil
	end
end

function Texture:SetVertexColor(r, g, b, a)
	self.color = { r, g, b, a or 1 }
end

function Texture:SetAlpha(a) self.alpha = a end
function Texture:SetAllPoints() end
function Texture:SetSnapToPixelGrid() end
function Texture:SetTexelSnappingBias() end
function Texture:SetBlendMode(m) self.blend = m end
function Texture:SetDrawLayer() end

--------------------------------------------------------------------------- frame

local Frame = {}
Frame.__index = Frame

function Frame:SetPoint(point, rel, relPoint, x, y)
	self.point, self.rel, self.relPoint = point, rel, relPoint
	if y == nil then
		self.x, self.y = rel or 0, relPoint or 0
	else
		self.x, self.y = x or 0, y or 0
	end
end

function Frame:ClearAllPoints() self.point, self.rel = nil, nil end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:SetWidth(w) self.w = w end
function Frame:SetHeight(h) self.h = h end
function Frame:GetWidth() return self.w or 0 end
function Frame:GetHeight() return self.h or 0 end
function Frame:GetLeft() return 0 end
function Frame:GetTop() return self.h or 0 end
function Frame:GetCenter() return (self.w or 0) / 2, (self.h or 0) / 2 end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:SetFrameLevel(n) self.level = n end
function Frame:SetFrameStrata(s) self.strata = s end
function Frame:SetToplevel(v) self.toplevel = v end
function Frame:SetClampedToScreen(v) self.clamped = v end
function Frame:SetMovable(v) self.movable = v end
function Frame:EnableMouse(v) self.mouse = v end
function Frame:EnableMouseWheel(v) self.wheel = v end
function Frame:EnableKeyboard(v) self.keyboard = v end
function Frame:SetPropagateKeyboardInput(v) self.propagate = v end
function Frame:StartMoving() self.moving = true end
function Frame:StopMovingOrSizing() self.moving = false end
function Frame:RegisterForDrag() end
function Frame:SetClipsChildren(v) self.clips = v end
function Frame:SetAllPoints() end

function Frame:Show()
	local was = self.shown
	self.shown = true
	if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end

function Frame:Hide()
	local was = self.shown
	self.shown = false
	if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end

function Frame:IsShown() return self.shown and true or false end

function Frame:RegisterEvent(event)
	self.events = self.events or {}
	self.events[event] = true
end

function Frame:UnregisterEvent(event)
	if self.events then self.events[event] = nil end
end

function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, fn)
	local previous = self.scripts[name]
	if previous then
		self.scripts[name] = function(...)
			previous(...)
			fn(...)
		end
	else
		self.scripts[name] = fn
	end
end

function Frame:CreateTexture(name, layer)
	local t = setmetatable({ id = id("tex"), owner = self, layer = layer or "ARTWORK", shown = false }, Texture)
	Mock.textures[#Mock.textures + 1] = t
	return t
end

function Frame:CreateFontString()
	local fs = {
		id = id("fs"),
		shown = true,
		SetPoint = function(self) end,
		SetText = function(self, text) self.text = text end,
		SetFont = function() end,
		SetJustifyH = function() end,
		SetWidth = function() end,
		SetTextColor = function() end,
	}
	return fs
end

function Frame:SetParent(p) self.parent = p end

--------------------------------------------------------------------------- globals

function Mock.Reset()
	Mock.frames = {}
	Mock.textures = {}
	Mock.sounds = {}
	Mock.messages = {}
	Mock.time = 0
	Mock.taxi = false
	Mock.combat = false
	Mock.chatFocus = nil
	Mock.created = 0
	nextID = 0

	function Mock.CreateFrame(kind, name, parent, template)
		local f = setmetatable({
			id = name or id("frame"),
			kind = kind,
			parent = parent,
			scripts = {},
			shown = true,
			level = parent and (parent.level or 1) or 1,
			w = 100,
			h = 100,
			template = template,
			events = {},
		}, Frame)
		Mock.frames[#Mock.frames + 1] = f
		return f
	end

	Mock.UIParent = Mock.CreateFrame("Frame", "UIParent", nil)
	Mock.UIParent.w, Mock.UIParent.h = 1920, 1080
	Mock.GameMenuFrame = Mock.CreateFrame("Frame", "GameMenuFrame", Mock.UIParent)
	Mock.GameMenuFrame.shown = false
	Mock.popup = nil

	CreateFrame = Mock.CreateFrame
	UIParent = Mock.UIParent
	GameMenuFrame = Mock.GameMenuFrame
	StaticPopupDialogs = {}
	StaticPopup_Show = function(which)
		Mock.popup = which
		return true
	end
	StaticPopup_Hide = function(which)
		if Mock.popup == which then Mock.popup = nil end
	end
	GetTime = function() return Mock.time end
	UnitOnTaxi = function() return Mock.taxi end
	InCombatLockdown = function() return Mock.combat end
	GetCurrentKeyBoardFocus = function() return Mock.chatFocus end
	PlaySoundFile = function(path, channel)
		Mock.sounds[#Mock.sounds + 1] = { path = path, channel = channel }
		-- A real client returns a sound handle (a userdata) that StopSound can
		-- take later; a tmpfile is the closest thing in plain Lua.
		return true, io.tmpfile()
	end
	StopSound = function(handle) end
	SlashCmdList = {}
	DEFAULT_CHAT_FRAME = {
		AddMessage = function(_, msg) Mock.messages[#Mock.messages + 1] = msg end,
	}
end

function Mock.FireEvent(event, arg1)
	for _, f in ipairs(Mock.frames) do
		if f.events and f.events[event] and f.scripts.OnEvent then
			f.scripts.OnEvent(f, event, arg1)
		end
	end
end

function Mock.Advance(dt)
	Mock.time = Mock.time + dt
	for _, f in ipairs(Mock.frames) do
		if f.shown and f.scripts.OnUpdate then
			f.scripts.OnUpdate(f, dt)
		end
	end
end

function Mock.SendKey(frame, key, down)
	if down == false then
		if frame.scripts.OnKeyUp then frame.scripts.OnKeyUp(frame, key) end
	else
		if frame.scripts.OnKeyDown then frame.scripts.OnKeyDown(frame, key) end
	end
end

-- Click PLAY / NOT NOW on the last static popup the addon asked for.
function Mock.AcceptPopup()
	local which = Mock.popup
	Mock.popup = nil
	local dialog = which and StaticPopupDialogs[which]
	if dialog and dialog.OnAccept then dialog.OnAccept() end
	return which
end

function Mock.CancelPopup()
	local which = Mock.popup
	Mock.popup = nil
	local dialog = which and StaticPopupDialogs[which]
	if dialog and dialog.OnCancel then dialog.OnCancel() end
	return which
end

-- Sorted draw list for everything the renderer produced this frame.
function Mock.Capture(render)
	local out = {}
	for _, lay in ipairs(render.layerList) do
		for i = 1, lay.n do
			local t = lay.tex[i]
			if t and t.shown then
				local rec = {
					kind = t.colorMode and "rect" or "tile",
					x = t.x or 0,
					y = -(t.y or 0), -- TOPLEFT anchors carry a negative y offset
					w = t.w or 0,
					h = t.h or 0,
					uv = t.uv and copy(t.uv),
					color = t.color and copy(t.color) or { 1, 1, 1, 1 },
					fill = t.fill and copy(t.fill),
					layer = lay.id,
				}
				out[#out + 1] = rec
			end
		end
	end
	return out
end

function Mock.WriteDraws(path, draws, w, h)
	local lines = { string.format("SIZE %d %d", w, h) }
	for _, d in ipairs(draws) do
		if d.kind == "rect" then
			lines[#lines + 1] = string.format(
				"R %.3f %.3f %.3f %.3f %.4f %.4f %.4f %.4f",
				d.x, d.y, d.w, d.h, d.fill[1], d.fill[2], d.fill[3], d.fill[4])
		else
			local uv = d.uv or { 0, 0, 1, 1 }
			lines[#lines + 1] = string.format(
				"T %.3f %.3f %.3f %.3f %.8f %.8f %.8f %.8f %.4f %.4f %.4f %.4f",
				d.x, d.y, d.w, d.h, uv[1], uv[2], uv[3], uv[4],
				d.color[1], d.color[2], d.color[3], d.color[4])
		end
	end
	local f = assert(io.open(path, "w"))
	f:write(table.concat(lines, "\n"))
	f:write("\n")
	f:close()
end

function Mock.CountSounds(name)
	local n = 0
	for _, s in ipairs(Mock.sounds) do
		if s.path:match(name .. "%.ogg$") then n = n + 1 end
	end
	return n
end

function Mock.LastSound()
	local s = Mock.sounds[#Mock.sounds]
	return s and s.path or nil
end

return Mock
