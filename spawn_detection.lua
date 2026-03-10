-- Fishing Addon - Spawn Detection
-- Detects Patient Treasure, Root Crab, and Blood Hunter Spirit spawns.
--
-- Treasure automation flow:
--   1. TREASURE_SPAWN → cancel fishing, boost interact range
--   2. Continuous spin + bot spams interact every ~100ms
--      Nav pixel 1 action: 1=turn_left, 0=stop_turning
--      Bot ALWAYS spams interact (F) during TREASURE_SPAWN regardless of action
--   3. Addon detects soft-target → action=0 (stop spin, interact spam continues)
--      Click-to-move walks player to treasure, interact loots it
--   4. Loot detected → nav back to fishing spot
--   5. 3-min master timeout → give up, reset to IDLE

local FA = FishingAddon

-- Treasure hunting state
FA.treasureHunting = false

-- Config
local TREASURE_TIMEOUT = 180   -- 3 min master timeout

-- Nav pixel action values (bot reads G channel of pixel 1)
local ACTION_NONE       = 0
local ACTION_TURN_LEFT  = 1
local ACTION_TURN_RIGHT = 2

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
-- Soft-target detection
-- Patient Treasure is a game object — /target doesn't work.
---------------------------------------------------------------------------
local TREASURE_NAMES = {
    "patient treasure",
    "tesoro paciente",
    "trésor patient",
    "geduldiger schatz",
    "treasure",
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
        if IsTreasureName(name) then return true end
    end
    if UnitExists("softenemy") then
        local name = UnitName("softenemy")
        if IsTreasureName(name) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Nav pixel helper
---------------------------------------------------------------------------
local function SetTreasureAction(action)
    FA.SetNavPixel(1, 1 / 255, action / 255, 0)
end

local function ClearTreasureAction()
    FA.SetNavPixel(1, 0, 0, 0)
end

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------
local scanFrame = CreateFrame("Frame")
local lootFrame = CreateFrame("Frame")
local treasureStartTime = 0
local treasureFound = false

local function RestoreInteractRange()
    SetCVar("SoftTargetInteractRange", "10")
end

local function StopTreasureHunting()
    scanFrame:SetScript("OnUpdate", nil)
    ClearTreasureAction()
    lootFrame:UnregisterAllEvents()
    lootFrame:SetScript("OnUpdate", nil)
    FA.treasureHunting = false
    treasureFound = false
    RestoreInteractRange()
end

---------------------------------------------------------------------------
-- Treasure return: after looting, navigate back to fishing spot
---------------------------------------------------------------------------
local function StartTreasureReturn()
    if not FA.treasureHunting then return end
    local hasSavedNav = FA.savedNav ~= nil
    StopTreasureHunting()

    -- Set IDLE immediately so bot exits treasure handler cleanly
    FA.SetPixelState("IDLE")
    print(FA.PREFIX .. "Treasure collected! Preparing to return...")

    if hasSavedNav then
        -- Delay to let loot finish, then start nav back (position + facing)
        C_Timer.After(1.5, function()
            if FA.savedNav then
                print(FA.PREFIX .. "Navigating back to fishing spot...")
                FA.StartNavigation()  -- sets pixel to NAV, bot follows
            end
        end)
    end
end

---------------------------------------------------------------------------
-- Treasure timeout
---------------------------------------------------------------------------
local function OnTreasureTimeout()
    StopTreasureHunting()
    FA.SetPixelState("IDLE")
    print(FA.PREFIX .. "|cffff4444Treasure search timed out (" .. TREASURE_TIMEOUT .. "s). Resuming fishing.|r")
end

---------------------------------------------------------------------------
-- Loot detection (multiple methods)
---------------------------------------------------------------------------
local function SetupLootDetection()
    lootFrame:RegisterEvent("LOOT_OPENED")
    lootFrame:RegisterEvent("LOOT_CLOSED")

    lootFrame:SetScript("OnEvent", function(self, event)
        if not FA.treasureHunting then return end
        print(FA.PREFIX .. "Treasure loot event: " .. event)
        if event == "LOOT_CLOSED" then
            C_Timer.After(0.5, function()
                if FA.treasureHunting then
                    StartTreasureReturn()
                end
            end)
        end
    end)

    -- Also poll: if softinteract disappears after being found, treasure was looted
    local pollStart = GetTime()
    lootFrame:SetScript("OnUpdate", function(self)
        if not FA.treasureHunting then
            self:SetScript("OnUpdate", nil)
            return
        end
        -- After treasure was found and a few seconds passed, check if gone
        if treasureFound and not CheckSoftTarget() and (GetTime() - pollStart > 3.0) then
            self:SetScript("OnUpdate", nil)
            print(FA.PREFIX .. "Treasure soft-target gone. Assuming looted.")
            if FA.treasureHunting then
                StartTreasureReturn()
            end
        end
        -- Safety timeout for interact phase
        if GetTime() - pollStart > 60 then
            self:SetScript("OnUpdate", nil)
            print(FA.PREFIX .. "Treasure interact timeout (60s).")
            if FA.treasureHunting then
                StartTreasureReturn()
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Treasure scan: spin + interact spam (addon controls turn via pixel)
--
-- Phase 1 (scanning): action=TURN_LEFT → bot turns + spams interact
-- Phase 2 (found):    action=NONE      → bot stops turning, keeps spamming
--                     click-to-move walks to treasure, interact loots it
---------------------------------------------------------------------------
local function StartTreasureScan()
    treasureStartTime = GetTime()
    treasureFound = false

    -- Cancel fishing if active
    if FA.isCurrentlyFishing then
        SpellStopCasting()
        print(FA.PREFIX .. "Cancelled fishing for treasure hunt.")
    end

    -- Boost soft-interact range
    SetCVar("SoftTargetInteractRange", "40")

    -- Random spin direction
    local spinAction = (math.random(1, 2) == 1) and ACTION_TURN_LEFT or ACTION_TURN_RIGHT
    local dirName = (spinAction == ACTION_TURN_LEFT) and "left" or "right"
    print(FA.PREFIX .. "Spinning " .. dirName .. "...")
    SetTreasureAction(spinAction)

    scanFrame:SetScript("OnUpdate", function()
        -- Master timeout
        if GetTime() - treasureStartTime > TREASURE_TIMEOUT then
            OnTreasureTimeout()
            return
        end

        if not treasureFound then
            -- Detect click-to-move: player starts walking (speed > 0)
            -- This means the interact spam caught the treasure and triggered movement
            local speed = GetUnitSpeed("player")
            if speed > 0 then
                treasureFound = true
                SetTreasureAction(ACTION_NONE)  -- stop spinning
                print(FA.PREFIX .. "|cff00ff00Player moving (click-to-move)! Stopping spin, walking to treasure...|r")
                SetupLootDetection()
            end
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
        -- Just log for debug, movement detection handles stopping
        if FA.treasureHunting and not treasureFound and CheckSoftTarget() then
            print(FA.PREFIX .. "Soft-target: treasure in range!")
        end
    end
end)
