-- Fishing Addon - Sound Muting
-- Mutes ALL game sounds except the fishing bobber splash (SoundKit 3355).
-- Uses MuteSoundFile() on ~270k individual sound FileDataIDs.

local FA = FishingAddon
local allSoundIDs = {}
local savedCVars = {}
local BATCH_SIZE = 5000

local CVAR_PROFILE = {
    -- Mute all channel-level audio
    Sound_EnableMusic              = "0",
    Sound_EnableAmbience           = "0",
    Sound_EnableDialog             = "0",
    Sound_EnableErrorSpeech        = "0",
    Sound_EnableEmoteSounds        = "0",
    Sound_EnablePetSounds          = "0",
    Sound_MusicVolume              = "0",
    Sound_AmbienceVolume           = "0",
    Sound_DialogVolume             = "0",

    -- Keep SFX on (bobber splash channel)
    Sound_EnableAllSound           = "1",
    Sound_EnableSFX                = "1",
    Sound_SFXVolume                = "1",
    Sound_MasterVolume             = "1",

    -- Sound when WoW is minimized/background
    Sound_EnableSoundWhenGameIsInBG = "1",
}

---------------------------------------------------------------------------
-- Build the full list from chunk globals set by sounds/sound_ids_*.lua
---------------------------------------------------------------------------
local function BuildSoundIDList()
    if #allSoundIDs > 0 then return true end

    local chunkCount = 0
    while _G["FISHING_ADDON_MUTE_IDS_" .. chunkCount] do
        chunkCount = chunkCount + 1
    end

    if chunkCount == 0 then
        print(FA.PREFIX .. "ERROR: No sound data loaded.")
        return false
    end

    for c = 0, chunkCount - 1 do
        local chunk = _G["FISHING_ADDON_MUTE_IDS_" .. c]
        for _, id in ipairs(chunk) do
            allSoundIDs[#allSoundIDs + 1] = id
        end
        _G["FISHING_ADDON_MUTE_IDS_" .. c] = nil
    end

    print(FA.PREFIX .. "Loaded " .. #allSoundIDs .. " sound IDs.")
    return true
end

---------------------------------------------------------------------------
-- Process sounds in batches to avoid freezing
---------------------------------------------------------------------------
local function ProcessSounds(func, callback)
    local total = #allSoundIDs
    if total == 0 then
        if callback then callback() end
        return
    end

    local index = 1
    FA.isMuting = true

    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local batchEnd = math.min(index + BATCH_SIZE - 1, total)
        for i = index, batchEnd do
            func(allSoundIDs[i])
        end
        index = batchEnd + 1

        if index > total then
            ticker:Cancel()
            FA.isMuting = false
            if callback then callback() end
        end
    end)
end

---------------------------------------------------------------------------
-- Public: Enable / Disable
---------------------------------------------------------------------------
function FA.EnableSoundMuting()
    if not BuildSoundIDList() then return end

    savedCVars = {}
    for cvar, _ in pairs(CVAR_PROFILE) do
        savedCVars[cvar] = GetCVar(cvar)
    end

    for cvar, value in pairs(CVAR_PROFILE) do
        SetCVar(cvar, value)
    end

    print(FA.PREFIX .. "Muting ~270k sounds... game may stutter briefly.")
    ProcessSounds(MuteSoundFile, function()
        FA.isActive = true
        print(FA.PREFIX .. "ON - Only the bobber splash is audible.")
    end)
end

function FA.DisableSoundMuting()
    print(FA.PREFIX .. "Unmuting sounds...")
    ProcessSounds(UnmuteSoundFile, function()
        for cvar, value in pairs(savedCVars) do
            if value then SetCVar(cvar, value) end
        end
        savedCVars = {}
        FA.isActive = false
        print(FA.PREFIX .. "OFF - Audio restored.")
    end)
end

function FA.GetSoundIDCount()
    return #allSoundIDs
end
