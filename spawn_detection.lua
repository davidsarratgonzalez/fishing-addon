-- Fishing Addon - Spawn Detection
-- Detects Patient Treasure, Root Crab, and Blood Hunter Spirit spawns.
-- Based on PatientTreasureChestAlerts by Creep-SteamwheedleCartel.
-- Also detects when Patient Treasure enters soft-target range.

local FA = FishingAddon

---------------------------------------------------------------------------
-- Fishing state tracking (used by Root Crab detection)
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
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        FA.isCurrentlyFishing = false
        FA.lastCastTime = GetTime()
    end
end)

---------------------------------------------------------------------------
-- Alert helper
---------------------------------------------------------------------------
local function Alert(eventTag, title, color)
    PlaySound(8959, "Master")
    RaidNotice_AddMessage(RaidWarningFrame, color .. title .. "|r", ChatTypeInfo["RAID_WARNING"])
    print(FA.PREFIX .. color .. title .. "|r")
    -- Machine-readable line for the Python bot (via WoW chat log)
    print("FISHING_ADDON_EVENT:" .. eventTag)
end

---------------------------------------------------------------------------
-- Spawn detection via CHAT_MSG_MONSTER_EMOTE + soft-target
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
            Alert("TREASURE_SPAWNED",
                "PATIENT TREASURE SPAWNED! Look around and press interact!",
                "|cffff00ff")

        elseif msg:find("blood hunter spirit") and msg:find(playerName) then
            Alert("SPIRIT_SPAWNED",
                "BLOOD HUNTER SPIRIT SPAWNED!",
                "|cffff4444")

        elseif msg:find("root crab") then
            if FA.isCurrentlyFishing or (GetTime() - FA.lastCastTime < 15) then
                Alert("CRAB_SPAWNED",
                    "ROOT CRAB DETECTED NEARBY!",
                    "|cffff8800")
            end
        end

    elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
        if UnitExists("softinteract") and UnitName("softinteract") == "Patient Treasure" then
            Alert("TREASURE_TARGETED",
                "PATIENT TREASURE TARGETED - PRESS INTERACT!",
                "|cff00ff00")
        end
    end
end)
