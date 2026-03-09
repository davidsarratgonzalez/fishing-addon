-- Fishing Addon - Spawn Detection
-- Detects Patient Treasure, Root Crab, and Blood Hunter Spirit spawns.
-- Based on PatientTreasureChestAlerts by Creep-SteamwheedleCartel.
-- Also detects when Patient Treasure enters soft-target range.
--
-- Treasure automation flow:
--   1. TREASURE_SPAWN  → auto-save fishing position, pixel = magenta
--   2. TREASURE_TARGET → soft-target found treasure, pixel = yellow
--   3. Python presses F (click-to-move walks + loots)
--   4. LOOT_CLOSED     → treasure done, auto-start NAV back to fishing spot

local FA = FishingAddon

-- Treasure hunting state
FA.treasureHunting = false

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
-- Treasure return: after looting, navigate back to fishing spot
---------------------------------------------------------------------------
local treasureFrame = CreateFrame("Frame")

local function StartTreasureReturn()
    if not FA.treasureHunting then return end
    FA.treasureHunting = false
    treasureFrame:UnregisterEvent("LOOT_CLOSED")

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
            -- Auto-save fishing position before going to treasure
            FA.SaveNavPosition()
            FA.treasureHunting = true
            FA.SetPixelState("TREASURE_SPAWN")
            Alert("TREASURE_SPAWNED",
                "PATIENT TREASURE SPAWNED! Bot will search...",
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
        if FA.treasureHunting and UnitExists("softinteract")
                and UnitName("softinteract") == "Patient Treasure" then
            FA.SetPixelState("TREASURE_TARGET")
            -- Listen for loot completion
            treasureFrame:RegisterEvent("LOOT_CLOSED")
            Alert("TREASURE_TARGETED",
                "PATIENT TREASURE FOUND - Walking to it!",
                "|cff00ff00")
        end
    end
end)

treasureFrame:SetScript("OnEvent", function(self, event)
    if event == "LOOT_CLOSED" and FA.treasureHunting then
        StartTreasureReturn()
    end
end)
