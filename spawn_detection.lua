-- Fishing Addon - Spawn Detection
-- Detects Patient Treasure, Root Crab, and Blood Hunter Spirit spawns.
-- Based on PatientTreasureChestAlerts by Creep-SteamwheedleCartel.
--
-- Treasure automation flow:
--   1. TREASURE_SPAWN  → save position, start scanning, bot spins + presses macro
--   2. TREASURE_TARGET → treasure found, bot presses interact repeatedly
--   3. LOOT_CLOSED     → treasure done, auto-start NAV back to fishing spot
--   Timeout (3 min)    → give up, reset to IDLE

local FA = FishingAddon

-- Treasure hunting state
FA.treasureHunting = false

-- Scan timeout: max time from treasure spawn to give up (3 minutes)
local TREASURE_TIMEOUT = 180

---------------------------------------------------------------------------
-- Fishing state tracking (used by Root Crab detection + pixel state)
---------------------------------------------------------------------------
local fishingFrame = CreateFrame("Frame")
fishingFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
fishingFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")

fishingFrame:SetScript("OnEvent", function(self, event, unit, _, spellID)
    if unit ~= "player" then return end
    local name = C_Spell.GetSpellName(spellID)
    if not name or not name:find("Fishing") then return end

    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        FA.isCurrentlyFishing = true
        if not FA.treasureHunting then
            FA.SetPixelState("FISHING")
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        FA.isCurrentlyFishing = false
        FA.lastCastTime = GetTime()
        if not FA.treasureHunting then
            FA.SetPixelState("IDLE")
        end
    end
end)

---------------------------------------------------------------------------
-- Alert helper
---------------------------------------------------------------------------
local function Alert(eventTag, title, color)
    PlaySound(8959, "Master")
    RaidNotice_AddMessage(RaidWarningFrame, color .. title .. "|r", ChatTypeInfo["RAID_WARNING"])
    print(FA.PREFIX .. color .. title .. "|r")
    print("FISHING_ADDON_EVENT:" .. eventTag)
end

---------------------------------------------------------------------------
-- Treasure detection: robust multi-method scanner
---------------------------------------------------------------------------
local scanFrame = CreateFrame("Frame")
local treasureStartTime = 0

-- Loose name match: handles locale differences, partial names, etc.
local TREASURE_NAMES = {
    "patient treasure",
    "tesoro paciente",       -- Spanish
    "trésor patient",        -- French
    "geduldiger schatz",     -- German
    "treasure",              -- fallback partial match
}

local function IsTreasureName(name)
    if not name then return false end
    local lower = name:lower()
    for _, pattern in ipairs(TREASURE_NAMES) do
        if lower:find(pattern) then return true end
    end
    return false
end

local function CheckSoftTarget()
    if UnitExists("softinteract") then
        local name = UnitName("softinteract")
        if IsTreasureName(name) then
            return true
        end
    end
    -- Also check generic soft-target tokens
    if UnitExists("softenemy") then
        local name = UnitName("softenemy")
        if IsTreasureName(name) then return true end
    end
    return false
end

-- Note: Patient Treasure is a game object, NOT a unit.
-- /target doesn't work on it. Detection is via soft-interact only.

---------------------------------------------------------------------------
-- Treasure found → stop scanning, set interact pixel
---------------------------------------------------------------------------
local treasureFrame = CreateFrame("Frame")

local function OnTreasureFound()
    -- Stop scanning
    scanFrame:SetScript("OnUpdate", nil)

    FA.SetPixelState("TREASURE_TARGET")

    -- Listen for loot completion
    treasureFrame:RegisterEvent("LOOT_CLOSED")

    Alert("TREASURE_TARGETED",
        "PATIENT TREASURE FOUND! Pressing interact...",
        "|cff00ff00")
end

---------------------------------------------------------------------------
-- Treasure timeout → give up, resume fishing
---------------------------------------------------------------------------
local function RestoreInteractRange()
    SetCVar("SoftTargetInteractRange", "10")
end

local function OnTreasureTimeout()
    scanFrame:SetScript("OnUpdate", nil)
    FA.treasureHunting = false
    RestoreInteractRange()
    FA.SetPixelState("IDLE")
    print(FA.PREFIX .. "|cffff4444Treasure search timed out (" .. TREASURE_TIMEOUT .. "s). Resuming fishing.|r")
end

---------------------------------------------------------------------------
-- Treasure return: after looting, navigate back to fishing spot
---------------------------------------------------------------------------
local function StartTreasureReturn()
    if not FA.treasureHunting then return end
    FA.treasureHunting = false
    treasureFrame:UnregisterEvent("LOOT_CLOSED")
    RestoreInteractRange()

    -- Small delay to let loot finish, then start nav
    C_Timer.After(1.5, function()
        if FA.savedNav then
            print(FA.PREFIX .. "Treasure looted! Returning to fishing spot...")
            FA.StartNavigation()
        else
            FA.SetPixelState("IDLE")
        end
    end)
end

---------------------------------------------------------------------------
-- Start treasure scanning (called when TREASURE_SPAWN detected)
---------------------------------------------------------------------------
local function StartTreasureScan()
    treasureStartTime = GetTime()

    -- Boost soft-target interact range for treasure searching
    SetCVar("SoftTargetInteractRange", "40")

    -- OnUpdate scanner: checks every frame for soft-interact treasure
    scanFrame:SetScript("OnUpdate", function()
        -- Timeout check
        if GetTime() - treasureStartTime > TREASURE_TIMEOUT then
            OnTreasureTimeout()
            return
        end

        -- Check soft-target (interact, enemy)
        if CheckSoftTarget() then
            OnTreasureFound()
            return
        end
    end)
end

---------------------------------------------------------------------------
-- Spawn detection via CHAT_MSG_MONSTER_EMOTE + soft-target event
---------------------------------------------------------------------------
local spawnFrame = CreateFrame("Frame")
spawnFrame:RegisterEvent("CHAT_MSG_MONSTER_EMOTE")
spawnFrame:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")

spawnFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_MONSTER_EMOTE" then
        local text = ...
        if not text then return end
        local msg = text:lower()
        local playerName = UnitName("player"):lower()

        if msg:find("treasure chest") and msg:find(playerName) then
            -- Auto-save fishing position before going to treasure
            FA.SaveNavPosition()
            FA.treasureHunting = true
            FA.SetPixelState("TREASURE_SPAWN")
            StartTreasureScan()
            Alert("TREASURE_SPAWNED",
                "PATIENT TREASURE SPAWNED! Searching...",
                "|cffff00ff")

        elseif msg:find("blood hunter spirit") and msg:find(playerName) then
            FA.SetPixelState("SPIRIT_SPAWN")
            Alert("SPIRIT_SPAWNED",
                "BLOOD HUNTER SPIRIT SPAWNED!",
                "|cffff4444")

        elseif msg:find("root crab") then
            if FA.isCurrentlyFishing or (GetTime() - FA.lastCastTime < 15) then
                FA.SetPixelState("CRAB_SPAWN")
                Alert("CRAB_SPAWNED",
                    "ROOT CRAB DETECTED NEARBY!",
                    "|cffff8800")
            end
        end

    elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
        -- Backup detection via event (in addition to OnUpdate scanner)
        if FA.treasureHunting and CheckSoftTarget() then
            OnTreasureFound()
        end
    end
end)

treasureFrame:SetScript("OnEvent", function(self, event)
    if event == "LOOT_CLOSED" and FA.treasureHunting then
        StartTreasureReturn()
    end
end)
