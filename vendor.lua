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
local DEFAULT_MACRO_BODY = "/cleartarget\n/cast Fishing"

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
        local stepStart = GetTime()

        -- Watch for mount
        sellFrame:SetScript("OnUpdate", function()
            if IsMounted() then
                sellFrame:SetScript("OnUpdate", nil)
                FA.SetPixelState("SELL_WAIT")
                sellTimer = C_Timer.NewTimer(2.0, function()
                    FA.sellStep = SELL_STEP_TARGET
                    AdvanceSellStep()
                end)
            elseif GetTime() - stepStart > 15 then
                StopSellSequence("Mount timeout — couldn't summon mount.")
            end
        end)

    elseif FA.sellStep == SELL_STEP_TARGET then
        -- Set macro to target vendor NPC — keep spamming SELL_ACTION
        -- until the NPC actually gets targeted (they take time to spawn)
        SetMacroBody("/target " .. vendorMount.vendorName)
        FA.SetPixelState("SELL_ACTION")
        local stepStart = GetTime()

        sellFrame:SetScript("OnUpdate", function()
            local target = UnitName("target")
            if target and target == vendorMount.vendorName then
                sellFrame:SetScript("OnUpdate", nil)
                FA.SetPixelState("SELL_WAIT")
                sellTimer = C_Timer.NewTimer(0.5, function()
                    FA.sellStep = SELL_STEP_INTERACT
                    AdvanceSellStep()
                end)
            elseif GetTime() - stepStart > 15 then
                StopSellSequence("Target timeout — vendor NPC not found.")
            else
                FA.SetPixelState("SELL_ACTION")
            end
        end)

    elseif FA.sellStep == SELL_STEP_INTERACT then
        -- Bot needs to press interact key (F) to open vendor
        FA.SetPixelState("SELL_INTERACT")
        local stepStart = GetTime()

        -- Watch for merchant window
        sellFrame:RegisterEvent("MERCHANT_SHOW")
        sellFrame:SetScript("OnEvent", function(self, event)
            if event == "MERCHANT_SHOW" then
                self:UnregisterEvent("MERCHANT_SHOW")
                self:SetScript("OnUpdate", nil)
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

        -- Timeout after 15s
        sellFrame:SetScript("OnUpdate", function()
            if GetTime() - stepStart > 15 then
                sellFrame:SetScript("OnUpdate", nil)
                sellFrame:UnregisterEvent("MERCHANT_SHOW")
                StopSellSequence("Interact timeout — merchant didn't open.")
            end
        end)

    elseif FA.sellStep == SELL_STEP_DISMOUNT then
        SetMacroBody("/dismount")
        FA.SetPixelState("SELL_ACTION")
        local stepStart = GetTime()

        -- Watch for dismount
        sellFrame:SetScript("OnUpdate", function()
            if not IsMounted() then
                sellFrame:SetScript("OnUpdate", nil)
                FA.sellStep = SELL_STEP_DONE
                AdvanceSellStep()
            elseif GetTime() - stepStart > 10 then
                StopSellSequence("Dismount timeout.")
            end
        end)

    elseif FA.sellStep == SELL_STEP_DONE then
        FA.isSelling = false
        FA.sellStep = SELL_STEP_NONE
        sellFrame:UnregisterAllEvents()
        sellFrame:SetScript("OnUpdate", nil)
        FA.ResetMacro()

        -- Navigate back to fishing spot if we have one saved
        if FA.savedNav then
            print(FA.PREFIX .. "Sell done! Returning to fishing spot...")
            FA.StartNavigation()
        else
            FA.SetPixelState("IDLE")
            print(FA.PREFIX .. "Sell done! Resuming fishing.")
        end
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

local function CountGreyItems()
    local count = 0
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == Enum.ItemQuality.Poor and (info.sellPrice or 0) > 0 then
                count = count + 1
            end
        end
    end
    return count
end

function FA.ShouldAutoSell()
    return vendorMount ~= nil
        and not FA.isSelling
        and not FA.navActive
        and not FA.treasureHunting
        and not InCombatLockdown()
        and FA.GetFreeBagSlots() == 0
        and CountGreyItems() > 0
end

---------------------------------------------------------------------------
-- Auto-sell: trigger when bags full + greys exist
---------------------------------------------------------------------------
local bagFrame = CreateFrame("Frame")
bagFrame:RegisterEvent("BAG_UPDATE_DELAYED")

bagFrame:SetScript("OnEvent", function()
    if FA.ShouldAutoSell() then
        print(FA.PREFIX .. "Bags full with grey items — auto-selling!")
        -- Save position before selling so we can nav back
        if not FA.savedNav then
            FA.SaveNavPosition()
        end
        FA.StartSellSequence()
    end
end)

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    EnsureMacro()
    DetectVendorMount()
end)
