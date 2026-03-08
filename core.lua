-- Fishing Addon
-- Mutes ALL game sounds except the fishing bobber splash (SoundKit 3355).
-- Uses MuteSoundFile() on ~270k individual sound FileDataIDs (split in 6 chunks).
-- Toggle with /fa. State persists between sessions.

local PREFIX = "|cff00ccff[FishingAddon]|r "

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
FishingAddonDB = FishingAddonDB or {
    enabled = false,
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local isActive = false
local isMuting = false

---------------------------------------------------------------------------
-- Collect all chunk tables into one list
---------------------------------------------------------------------------
local allSoundIDs = {}

local function BuildSoundIDList()
    if #allSoundIDs > 0 then return true end

    -- Scan for chunk globals (FISHING_ADDON_MUTE_IDS_0, _1, _2, ...)
    local chunkCount = 0
    while _G["FISHING_ADDON_MUTE_IDS_" .. chunkCount] do
        chunkCount = chunkCount + 1
    end

    print(PREFIX .. "DEBUG: Found " .. chunkCount .. " sound chunks.")

    if chunkCount == 0 then
        print(PREFIX .. "ERROR: No sound data loaded. Check that sound_ids_*.lua files exist.")
        return false
    end

    for c = 0, chunkCount - 1 do
        local chunk = _G["FISHING_ADDON_MUTE_IDS_" .. c]
        for _, id in ipairs(chunk) do
            allSoundIDs[#allSoundIDs + 1] = id
        end
        _G["FISHING_ADDON_MUTE_IDS_" .. c] = nil
    end

    print(PREFIX .. "Loaded " .. #allSoundIDs .. " sound IDs to mute.")
    return true
end

---------------------------------------------------------------------------
-- CVars saved/restored alongside the per-file mutes
---------------------------------------------------------------------------
local savedCVars = {}

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

    -- Critical: hear sound when WoW is minimized/background
    Sound_EnableSoundWhenGameIsInBG = "1",
}

---------------------------------------------------------------------------
-- Mute / Unmute all sounds (spread across frames to avoid freezing)
---------------------------------------------------------------------------
local BATCH_SIZE = 5000

local function ProcessSounds(func, callback)
    local total = #allSoundIDs
    if total == 0 then
        if callback then callback() end
        return
    end

    local index = 1
    isMuting = true

    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local batchEnd = math.min(index + BATCH_SIZE - 1, total)
        for i = index, batchEnd do
            func(allSoundIDs[i])
        end
        index = batchEnd + 1

        if index > total then
            ticker:Cancel()
            isMuting = false
            if callback then callback() end
        end
    end)
end

---------------------------------------------------------------------------
-- Enable / Disable
---------------------------------------------------------------------------

local function Enable()
    if not BuildSoundIDList() then return end

    -- Save current CVars
    savedCVars = {}
    for cvar, _ in pairs(CVAR_PROFILE) do
        savedCVars[cvar] = GetCVar(cvar)
    end

    -- Apply fishing CVar profile
    for cvar, value in pairs(CVAR_PROFILE) do
        SetCVar(cvar, value)
    end

    -- Mute all individual sound files (except bobber splash)
    print(PREFIX .. "Muting ~270k sounds... game may stutter briefly.")
    ProcessSounds(MuteSoundFile, function()
        isActive = true
        print(PREFIX .. "ON - Only the bobber splash is audible.")
    end)
end

local function Disable()
    -- Unmute all individual sound files
    print(PREFIX .. "Unmuting sounds...")
    ProcessSounds(UnmuteSoundFile, function()
        -- Restore CVars
        for cvar, value in pairs(savedCVars) do
            if value then
                SetCVar(cvar, value)
            end
        end
        savedCVars = {}
        isActive = false
        print(PREFIX .. "OFF - All audio restored.")
    end)
end

---------------------------------------------------------------------------
-- Fast Loot: instantly loot all items when the loot window opens
---------------------------------------------------------------------------
local fastLootFrame = CreateFrame("Frame")
local lastLootTime = 0
local LOOT_DEBOUNCE = 0.3

fastLootFrame:RegisterEvent("LOOT_READY")
fastLootFrame:SetScript("OnEvent", function()
    if (GetTime() - lastLootTime) < LOOT_DEBOUNCE then return end
    if GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") then
        for i = GetNumLootItems(), 1, -1 do
            LootSlot(i)
        end
        lastLootTime = GetTime()
    end
end)

---------------------------------------------------------------------------
-- Auto-sell grey items when opening a vendor
---------------------------------------------------------------------------
local sellGreysFrame = CreateFrame("Frame")

sellGreysFrame:RegisterEvent("MERCHANT_SHOW")
sellGreysFrame:SetScript("OnEvent", function()
    local itemsSold = 0

    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == Enum.ItemQuality.Poor and (info.sellPrice or 0) > 0 then
                C_Container.UseContainerItem(bag, slot)
                itemsSold = itemsSold + 1
            end
        end
    end

    if itemsSold > 0 then
        print(PREFIX .. "Sold " .. itemsSold .. " grey items.")
    end
end)

---------------------------------------------------------------------------
-- Soft Targeting: max range/arc so interact key finds nearby objects
---------------------------------------------------------------------------
local SOFT_TARGET_CVARS = {
    SoftTargetInteract          = "3",
    SoftTargetInteractRange     = "10",
    SoftTargetInteractArc       = "2",
    SoftTargetIconGameObject    = "1",
    SoftTargetIconInteract      = "1",
    SoftTargetLowPriorityIcons  = "1",
}

local function ApplySoftTargeting()
    for cvar, value in pairs(SOFT_TARGET_CVARS) do
        SetCVar(cvar, value)
    end
end

---------------------------------------------------------------------------
-- Fishing event detection (used by treasure/crab spawn logic)
---------------------------------------------------------------------------
local isCurrentlyFishing = false
local lastCastTime = 0

local fishingStateFrame = CreateFrame("Frame")
fishingStateFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
fishingStateFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")

fishingStateFrame:SetScript("OnEvent", function(self, event, unit, _, spellID)
    if unit ~= "player" then return end
    local name = C_Spell.GetSpellName(spellID)
    if not name or not name:find("Fishing") then return end

    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        isCurrentlyFishing = true
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        isCurrentlyFishing = false
        lastCastTime = GetTime()
    end
end)

---------------------------------------------------------------------------
-- Spawn detection: Patient Treasure, Root Crab, Blood Hunter Spirit
-- Based on PatientTreasureChestAlerts by Creep-SteamwheedleCartel
-- Detection via CHAT_MSG_MONSTER_EMOTE string matching
---------------------------------------------------------------------------
local spawnFrame = CreateFrame("Frame")
spawnFrame:RegisterEvent("CHAT_MSG_MONSTER_EMOTE")

-- Soft-target detection for Patient Treasure
spawnFrame:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")

local function Alert(eventTag, title, color)
    PlaySound(8959, "Master")  -- Raid warning sound
    RaidNotice_AddMessage(RaidWarningFrame, color .. title .. "|r", ChatTypeInfo["RAID_WARNING"])
    print(PREFIX .. color .. title .. "|r")
    -- Machine-readable line for the Python bot (via WoW chat log)
    print("FISHING_ADDON_EVENT:" .. eventTag)
end

spawnFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_MONSTER_EMOTE" then
        local text = ...
        if not text then return end
        local msg = text:lower()
        local playerName = UnitName("player"):lower()

        if msg:find("treasure chest") and msg:find(playerName) then
            Alert("TREASURE_SPAWNED",
                "PATIENT TREASURE SPAWNED! Look around and press interact!",
                "|cffff00ff")

        elseif msg:find("blood hunter spirit") and msg:find(playerName) then
            Alert("SPIRIT_SPAWNED",
                "BLOOD HUNTER SPIRIT SPAWNED!",
                "|cffff4444")

        elseif msg:find("root crab") then
            -- Root Crab only counts if we are fishing or fished recently
            if isCurrentlyFishing or (GetTime() - lastCastTime < 15) then
                Alert("CRAB_SPAWNED",
                    "ROOT CRAB DETECTED NEARBY!",
                    "|cffff8800")
            end
        end

    elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
        if UnitExists("softinteract") then
            local name = UnitName("softinteract")
            if name == "Patient Treasure" then
                Alert("TREASURE_TARGETED",
                    "PATIENT TREASURE TARGETED - PRESS INTERACT!",
                    "|cff00ff00")
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Auto-apply on login
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        FishingAddonDB = FishingAddonDB or { enabled = false }

        -- Always apply soft targeting and treasure detection
        ApplySoftTargeting()

        if FishingAddonDB.enabled then
            Enable()
        else
            print(PREFIX .. "Loaded (disabled). Type /fa to enable.")
        end
    end
end)

---------------------------------------------------------------------------
-- Slash command: /fa
---------------------------------------------------------------------------
SLASH_FISHINGADDON1 = "/fa"
SLASH_FISHINGADDON2 = "/fishingaddon"

SlashCmdList["FISHINGADDON"] = function(msg)
    local cmd = (msg or ""):lower():trim()

    if isMuting then
        print(PREFIX .. "Please wait, still processing sounds...")
        return
    end

    if cmd == "" or cmd == "toggle" then
        FishingAddonDB.enabled = not FishingAddonDB.enabled
        if FishingAddonDB.enabled then
            Enable()
        else
            Disable()
        end

    elseif cmd == "status" then
        print(PREFIX .. "Status:")
        print("  Enabled: " .. tostring(FishingAddonDB.enabled))
        print("  Active: " .. tostring(isActive))
        print("  Sound IDs loaded: " .. #allSoundIDs)

    else
        print(PREFIX .. "Commands:")
        print("  /fa        - Toggle on/off")
        print("  /fa status - Show current state")
    end
end
