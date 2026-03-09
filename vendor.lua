-- Fishing Addon - Vendor Mount Sell Sequence
-- Creates a macro "FA" that the bot presses. The addon changes its content
-- at each step to: summon mount → target vendor → interact → sell → dismount.
--
-- Pixel states during sell:
--   SELL_ACTION   → bot presses cast key (macro does the right thing)
--   SELL_INTERACT → bot presses interact key (open vendor)
--   SELL_WAIT     → bot does nothing (waiting for result)
--   IDLE          → done, resume fishing

local FA = FishingAddon

---------------------------------------------------------------------------
-- Vendor mount database
---------------------------------------------------------------------------
local VENDOR_MOUNTS = {
    {
        spellID = 61425,  -- Traveler's Tundra Mammoth
        name = "Traveler's Tundra Mammoth",
        vendors = {
            Alliance = "Hakmud of Argus",
            Horde    = "Drix Blackwrench",
        },
    },
    {
        spellID = 122708,  -- Grand Expedition Yak
        name = "Grand Expedition Yak",
        vendors = {
            Alliance = "Cousin Slowhands",
            Horde    = "Cousin Slowhands",
        },
    },
}

-- Detected at login
local vendorMount = nil   -- { spellID, name, vendorName }

local function DetectVendorMount()
    local faction = UnitFactionGroup("player")
    if not faction then return end

    for _, mount in ipairs(VENDOR_MOUNTS) do
        -- Check via mount journal (spell IDs don't show in IsSpellKnown for mounts)
        local mountID = C_MountJournal.GetMountFromSpell(mount.spellID)
        if mountID then
            local _, _, _, _, isUsable, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            if isCollected then
                local vendorName = mount.vendors[faction]
                if vendorName then
                    vendorMount = {
                        spellID = mount.spellID,
                        name = mount.name,
                        vendorName = vendorName,
                    }
                    print(FA.PREFIX .. "Vendor mount: " .. mount.name .. " (vendor: " .. vendorName .. ")")
                    return
                end
            end
        end
    end
    print(FA.PREFIX .. "No vendor mount found (Mammoth or Yak needed for auto-sell).")
end

function FA.HasVendorMount()
    return vendorMount ~= nil
end

---------------------------------------------------------------------------
-- Macro management
---------------------------------------------------------------------------
local MACRO_NAME = "FA"
local MACRO_ICON = "INV_FISHINGPOLE_02"
local DEFAULT_MACRO_BODY = "/cast Fishing"

local function EnsureMacro()
    local idx = GetMacroIndexByName(MACRO_NAME)
    if idx == 0 then
        CreateMacro(MACRO_NAME, MACRO_ICON, DEFAULT_MACRO_BODY, false)
        print(FA.PREFIX .. "Created macro '" .. MACRO_NAME .. "'. Put it on your action bar (cast key).")
    end
end

local function SetMacroBody(body)
    local idx = GetMacroIndexByName(MACRO_NAME)
    if idx > 0 then
        EditMacro(idx, MACRO_NAME, MACRO_ICON, body)
    end
end

function FA.ResetMacro()
    SetMacroBody(DEFAULT_MACRO_BODY)
end

---------------------------------------------------------------------------
-- Sell sequence state machine
---------------------------------------------------------------------------
local SELL_STEP_NONE     = 0
local SELL_STEP_MOUNT    = 1  -- summon vendor mount
local SELL_STEP_TARGET   = 2  -- target vendor NPC
local SELL_STEP_INTERACT = 3  -- open vendor window
local SELL_STEP_SELLING  = 4  -- sell_greys running
local SELL_STEP_DISMOUNT = 5  -- dismount
local SELL_STEP_DONE     = 6

FA.sellStep = SELL_STEP_NONE
FA.isSelling = false

local sellFrame = CreateFrame("Frame")
local sellTimer = nil

local function StopSellSequence(reason)
    FA.isSelling = false
    FA.sellStep = SELL_STEP_NONE
    sellFrame:UnregisterAllEvents()
    sellFrame:SetScript("OnUpdate", nil)
    if sellTimer then sellTimer:Cancel(); sellTimer = nil end
    FA.ResetMacro()
    FA.SetPixelState("IDLE")
    if reason then
        print(FA.PREFIX .. "Sell: " .. reason)
    end
end

local function AdvanceSellStep()
    if not FA.isSelling then return end

    if FA.sellStep == SELL_STEP_MOUNT then
        -- Set macro to summon mount
        SetMacroBody("/cast " .. vendorMount.name)
        FA.SetPixelState("SELL_ACTION")

        -- Watch for mount
        sellFrame:RegisterEvent("UNIT_AURA")
        sellFrame:SetScript("OnUpdate", function()
            if IsMounted() then
                sellFrame:UnregisterEvent("UNIT_AURA")
                sellFrame:SetScript("OnUpdate", nil)
                FA.SetPixelState("SELL_WAIT")
                -- Small delay for mount to fully load NPCs
                sellTimer = C_Timer.NewTimer(2.0, function()
                    FA.sellStep = SELL_STEP_TARGET
                    AdvanceSellStep()
                end)
            end
        end)

    elseif FA.sellStep == SELL_STEP_TARGET then
        -- Set macro to target vendor NPC
        SetMacroBody("/target " .. vendorMount.vendorName)
        FA.SetPixelState("SELL_ACTION")

        -- Small delay then move to interact
        sellTimer = C_Timer.NewTimer(1.0, function()
            FA.sellStep = SELL_STEP_INTERACT
            AdvanceSellStep()
        end)

    elseif FA.sellStep == SELL_STEP_INTERACT then
        -- Bot needs to press interact key (F) to open vendor
        FA.SetPixelState("SELL_INTERACT")

        -- Watch for merchant window
        sellFrame:RegisterEvent("MERCHANT_SHOW")
        sellFrame:SetScript("OnEvent", function(self, event)
            if event == "MERCHANT_SHOW" then
                self:UnregisterEvent("MERCHANT_SHOW")
                FA.sellStep = SELL_STEP_SELLING
                FA.SetPixelState("SELL_WAIT")
                -- sell_greys.lua handles MERCHANT_SHOW automatically
                -- Wait a moment for selling to complete, then close and dismount
                sellTimer = C_Timer.NewTimer(2.0, function()
                    CloseMerchant()
                    FA.sellStep = SELL_STEP_DISMOUNT
                    AdvanceSellStep()
                end)
            end
        end)

        -- Timeout: if merchant doesn't open in 5s, retry
        sellTimer = C_Timer.NewTimer(5.0, function()
            if FA.sellStep == SELL_STEP_INTERACT then
                -- Retry interact
                AdvanceSellStep()
            end
        end)

    elseif FA.sellStep == SELL_STEP_DISMOUNT then
        SetMacroBody("/dismount")
        FA.SetPixelState("SELL_ACTION")

        -- Watch for dismount
        sellFrame:SetScript("OnUpdate", function()
            if not IsMounted() then
                sellFrame:SetScript("OnUpdate", nil)
                FA.sellStep = SELL_STEP_DONE
                AdvanceSellStep()
            end
        end)

    elseif FA.sellStep == SELL_STEP_DONE then
        StopSellSequence("Done! Resuming fishing.")
    end
end

function FA.StartSellSequence()
    if FA.isSelling then
        print(FA.PREFIX .. "Already selling.")
        return
    end
    if not vendorMount then
        print(FA.PREFIX .. "No vendor mount available!")
        return
    end
    if InCombatLockdown() then
        print(FA.PREFIX .. "Can't sell during combat (EditMacro is protected).")
        return
    end

    FA.isSelling = true
    FA.sellStep = SELL_STEP_MOUNT
    print(FA.PREFIX .. "Starting sell sequence...")
    AdvanceSellStep()
end

---------------------------------------------------------------------------
-- Bag space check
---------------------------------------------------------------------------
function FA.GetFreeBagSlots()
    local free = 0
    for bag = 0, 4 do
        free = free + C_Container.GetContainerNumFreeSlots(bag)
    end
    return free
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    EnsureMacro()
    DetectVendorMount()
end)
