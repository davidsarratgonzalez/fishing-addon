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
    -- Avoid RaidNotice_AddMessage — it touches RaidWarningFrame (secure frame)
    -- which can propagate taint and cause "blocked from Blizzard UI" errors.
    UIErrorsFrame:AddMessage(color .. title .. "|r", 1, 1, 1, 1, 5)
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
    -- Range is kept at 40 permanently (set at login) — nothing to restore.
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

    -- Stop treasure state but DON'T set IDLE yet — keep TREASURE_SPAWN
    -- so the bot stays in the treasure handler and doesn't cast sideways.
    scanFrame:SetScript("OnUpdate", nil)
    ClearTreasureAction()
    lootFrame:UnregisterAllEvents()
    lootFrame:SetScript("OnUpdate", nil)
    FA.treasureHunting = false
    treasureFound = false
    RestoreInteractRange()

    print(FA.PREFIX .. "Treasure collected! Preparing to return...")

    if hasSavedNav then
        -- Delay to let loot finish, then nav back (pixel stays TREASURE_SPAWN → NAV)
        C_Timer.After(1.5, function()
            if FA.savedNav then
                print(FA.PREFIX .. "Navigating back to fishing spot...")
                FA.StartNavigation()  -- sets pixel to NAV, bot follows
            else
                FA.SetPixelState("IDLE")
            end
        end)
    else
        -- No saved nav, just go IDLE
        FA.SetPixelState("IDLE")
    end
end

---------------------------------------------------------------------------
-- Treasure timeout
---------------------------------------------------------------------------
local function OnTreasureTimeout()
    print(FA.PREFIX .. "|cffff4444Treasure search timed out (" .. TREASURE_TIMEOUT .. "s). Resuming.|r")
    -- Defer to next frame since we're called from inside scanFrame OnUpdate
    C_Timer.After(0, function()
        StartTreasureReturn()
    end)
end

---------------------------------------------------------------------------
-- Treasure scan: spin + interact spam + loot detection (all at once)
--
-- Detection methods (all active from the start):
--   1. LOOT_CLOSED event — treasure looted directly (close range)
--   2. GetUnitSpeed > 0 — click-to-move triggered, stop spin
--   3. Soft-target appeared then disappeared — treasure collected
--   4. Master timeout — give up after TREASURE_TIMEOUT seconds
---------------------------------------------------------------------------
local softTargetSeen = false

local function StartTreasureScan()
    treasureStartTime = GetTime()
    treasureFound = false
    softTargetSeen = false

    -- SpellStopCasting() is protected — bot's rotation cancels fishing automatically.
    if FA.isCurrentlyFishing then
        print(FA.PREFIX .. "Fishing active — bot rotation will cancel it.")
    end

    -- Random spin direction
    local spinAction = (math.random(1, 2) == 1) and ACTION_TURN_LEFT or ACTION_TURN_RIGHT
    local dirName = (spinAction == ACTION_TURN_LEFT) and "left" or "right"
    print(FA.PREFIX .. "Spinning " .. dirName .. "...")
    SetTreasureAction(spinAction)

    -- Register loot events immediately (not after speed detection)
    lootFrame:RegisterEvent("LOOT_OPENED")
    lootFrame:RegisterEvent("LOOT_CLOSED")
    lootFrame:SetScript("OnEvent", function(self, event)
        if not FA.treasureHunting then return end
        print(FA.PREFIX .. "Treasure loot event: " .. event)
        if event == "LOOT_OPENED" then
            -- Treasure is being looted — stop spinning NOW
            treasureFound = true
            SetTreasureAction(ACTION_NONE)
            print(FA.PREFIX .. "|cff00ff00Loot window opened! Stopping spin.|r")
        elseif event == "LOOT_CLOSED" then
            C_Timer.After(0.5, function()
                if FA.treasureHunting then
                    StartTreasureReturn()
                end
            end)
        end
    end)

    -- Main scan loop
    scanFrame:SetScript("OnUpdate", function()
        if not FA.treasureHunting then return end

        -- Master timeout
        if GetTime() - treasureStartTime > TREASURE_TIMEOUT then
            OnTreasureTimeout()
            return
        end

        -- Track soft-target: if treasure appeared then disappeared = looted
        if CheckSoftTarget() then
            if not softTargetSeen then
                softTargetSeen = true
                print(FA.PREFIX .. "Soft-target: treasure detected!")
            end
        elseif softTargetSeen and not treasureFound then
            -- Soft-target was there but now it's gone — treasure was looted
            -- (could happen if treasure is right next to us: interact → loot → gone)
            print(FA.PREFIX .. "Soft-target disappeared. Treasure collected!")
            treasureFound = true
            SetTreasureAction(ACTION_NONE)
            C_Timer.After(1.0, function()
                if FA.treasureHunting then
                    StartTreasureReturn()
                end
            end)
            return
        end

        if not treasureFound then
            -- Detect click-to-move: player starts walking (speed > 0)
            local speed = GetUnitSpeed("player")
            if speed > 0 then
                treasureFound = true
                SetTreasureAction(ACTION_NONE)  -- stop spinning
                print(FA.PREFIX .. "|cff00ff00Player moving (click-to-move)! Stopping spin...|r")
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
            if FA.treasureHunting then return end  -- don't re-trigger
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
