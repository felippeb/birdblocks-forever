-- Bird Blocks: sound.
--
-- All audio is synthesized by tools/make_assets.py and shipped as mono OGG
-- Vorbis: 8-bit style square/triangle blips and an original arrangement of
-- the public-domain folk tune Korobeiniki. No Nintendo samples involved.
--
-- PlaySoundFile plays a file once and returns a handle; the theme is re-armed
-- by the update loop when it runs out, which is how we get a seamless loop
-- without streaming APIs.

local ADDON = ...
BirdBlocks = BirdBlocks or {}
local BB = BirdBlocks

local Sound = {}
BB.Sound = Sound

local function now()
	if GetTime then return GetTime() end
	return os.clock()
end

-- PlaySoundFile returns (willPlay, handle) on this client, but older clients
-- return nothing and some reject a channel name. Try the requested channel,
-- then SFX (which Polestar proves works here), then the default channel.
local function rawPlay(path, channel)
	local ok, willPlay, handle = pcall(PlaySoundFile, path, channel)
	if ok and willPlay ~= false then return handle or true end
	return nil
end

local function playFile(path, channel)
	local handle = rawPlay(path, channel)
	if handle then return handle end
	if channel == "Music" then
		handle = rawPlay(path, "SFX")
		if handle then return handle end
	end
	if channel then return rawPlay(path, nil) end
	return nil
end

function Sound.Init(audio, opts)
	Sound.audio = audio or BirdBlocksAudio
	opts = opts or {}
	Sound.sfxEnabled = opts.sfx ~= false
	Sound.musicEnabled = opts.music ~= false
	Sound.playing = false
	Sound.handle = nil
	Sound.started = 0
end

function Sound.Play(name)
	if not Sound.sfxEnabled or not Sound.audio then return end
	local rel = Sound.audio.sfx and Sound.audio.sfx[name]
	if not rel then return end
	return playFile(Sound.audio.base .. rel, "SFX") ~= nil
end

function Sound.StopMusic()
	if Sound.handle and StopSound then
		pcall(StopSound, Sound.handle)
	end
	Sound.handle, Sound.playing = nil, false
end

function Sound.StartMusic()
	Sound.StopMusic()
	if not Sound.musicEnabled or not Sound.audio then return end
	local path = Sound.audio.base .. Sound.audio.theme
	local handle = playFile(path, "Music")
	if handle then
		Sound.playing = true
		Sound.handle = type(handle) == "userdata" and handle or nil
		Sound.started = now()
	end
end

-- Called every rendered frame. Restarts the theme when it reaches the end.
function Sound.Tick()
	if not Sound.playing then return end
	local length = (Sound.audio and Sound.audio.themeLength or 0) - 0.35
	if now() - Sound.started >= length then
		Sound.StartMusic()
	end
end

function Sound.SetMusic(on)
	Sound.musicEnabled = on and true or false
	if Sound.musicEnabled then
		if not Sound.playing then Sound.StartMusic() end
	else
		Sound.StopMusic()
	end
end

function Sound.SetSFX(on)
	Sound.sfxEnabled = on and true or false
end

return Sound
