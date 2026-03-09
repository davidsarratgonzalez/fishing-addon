-- Fishing Addon - Lure Management
-- Auto-applies selected fishing lure between casts.
-- Includes a small config UI toggled via /fa lure.

local FA = FishingAddon

---------------------------------------------------------------------------
-- Lure database
-- category: "crafted" (30 min, target fish), "throwback" (stacking buff),
--           "legacy" (old-style pole enchant)
---------------------------------------------------------------------------
local LURES = {
    -- Midnight crafted lures
    { itemID = 241147, name = "Blood Hunter Lure",         duration = 1800, category = "crafted",    expansion = "Midnight" },
    { itemID = 241145, name = "Lucky Loa Lure",            duration = 1800, category = "crafted",    expansion = "Midnight" },
    { itemID = 241149, name = "Ominous Octopus Lure",      duration = 1800, category = "crafted",    expansion = "Midnight" },
    { itemID = 241150, name = "Sunwell Fish Lure",         duration = 1800, category = "crafted",    expansion = "Midnight" },

    -- TWW crafted lures
    { itemID = 219002, name = "Specular Rainbowfish Lure", duration = 1800, category = "crafted",    expansion = "TWW" },
    { itemID = 219003, name = "Quiet River Bass Lure",     duration = 1800, category = "crafted",    expansion = "TWW" },
    { itemID = 219004, name = "Dornish Pike Lure",         duration = 1800, category = "crafted",    expansion = "TWW" },
    { itemID = 219005, name = "Arathor Hammerfish Lure",   duration = 1800, category = "crafted",    expansion = "TWW" },
    { itemID = 219006, name = "Roaring Anglerseeker Lure", duration = 1800, category = "crafted",    expansion = "TWW" },

    -- Midnight throwback fish (short stacking buffs)
    { itemID = 238365, name = "Sin'dorei Swarmer",  duration = 30, category = "throwback", expansion = "Midnight", effect = "+25 Fishing",     maxStacks = 10 },
    { itemID = 238382, name = "Gore Guppy",          duration = 30, category = "throwback", expansion = "Midnight", effect = "+25 Fishing",     maxStacks = 10 },
    { itemID = 238381, name = "Hollow Grouper",      duration = 30, category = "throwback", expansion = "Midnight", effect = "+45 Perception",  maxStacks = 10 },
    { itemID = 238371, name = "Arcane Wyrmfish",     duration = 30, category = "throwback", expansion = "Midnight", effect = "+150 Perception", maxStacks = 10 },
    { itemID = 238366, name = "Lynxfish",            duration = 30, category = "throwback", expansion = "Midnight", effect = "+150 Perception", maxStacks = 10 },
    { itemID = 238367, name = "Root Crab",           duration = 30, category = "throwback", expansion = "Midnight", effect = "+150 Perception", maxStacks = 10 },
    { itemID = 238370, name = "Shimmer Spinefish",   duration = 30, category = "throwback", expansion = "Midnight", effect = "+150 Perception", maxStacks = 10 },
    { itemID = 238374, name = "Tender Lumifin",      duration = 30, category = "throwback", expansion = "Midnight", effect = "+150 Perception", maxStacks = 10 },

    -- Legacy lures (pole enchant style)
    { itemID = 6529,  name = "Shiny Bauble",              duration = 600, category = "legacy", expansion = "Classic",    effect = "+3 Fishing" },
    { itemID = 6530,  name = "Nightcrawlers",              duration = 600, category = "legacy", expansion = "Classic",    effect = "+5 Fishing" },
    { itemID = 6532,  name = "Bright Baubles",             duration = 600, category = "legacy", expansion = "Classic",    effect = "+7 Fishing" },
    { itemID = 6533,  name = "Aquadynamic Fish Attractor", duration = 600, category = "legacy", expansion = "Classic",    effect = "+9 Fishing" },
    { itemID = 68049, name = "Heat-Treated Spinning Lure", duration = 900, category = "legacy", expansion = "Cataclysm", effect = "+10 Fishing" },
}

local LURE_BY_ID = {}
for _, lure in ipairs(LURES) do
    LURE_BY_ID[lure.itemID] = lure
end

---------------------------------------------------------------------------
-- Internal state
---------------------------------------------------------------------------
local lastLureApplyTime = 0
local applyingLure = false

---------------------------------------------------------------------------
-- Bag helpers
---------------------------------------------------------------------------
local function FindItemInBags(itemID)
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID then
                return bag, slot, info.stackCount or 1
            end
        end
    end
    return nil
end

local function GetAvailableLures()
    local available = {}
    for _, lure in ipairs(LURES) do
        local bag, slot, count = FindItemInBags(lure.itemID)
        if bag then
            table.insert(available, {
                lure  = lure,
                bag   = bag,
                slot  = slot,
                count = count,
            })
        end
    end
    return available
end

---------------------------------------------------------------------------
-- Buff check (timer-based for crafted/legacy; always true-to-use for throwback)
---------------------------------------------------------------------------
local function IsLureBuffActive(lureData)
    if not lureData then return false end
    if lureData.category == "crafted" or lureData.category == "legacy" then
        if lastLureApplyTime == 0 then return false end
        return (GetTime() - lastLureApplyTime) < (lureData.duration - 300)
    end
    -- Throwback: always worth using if we have some
    return false
end

---------------------------------------------------------------------------
-- Apply lure via the FA macro (protected-safe)
-- Sets LURE pixel → bot presses cast key → item gets used → reset
---------------------------------------------------------------------------
local MACRO_NAME = "FA"
local MACRO_ICON = "INV_FISHINGPOLE_02"

local function DoApplyLure(itemName)
    if applyingLure or InCombatLockdown() then return end

    local idx = GetMacroIndexByName(MACRO_NAME)
    if idx == 0 then return end

    applyingLure = true
    EditMacro(idx, MACRO_NAME, MACRO_ICON, "/use " .. itemName)
    FA.SetPixelState("LURE")       -- bot presses cast key once, then waits

    -- After GCD resolves, reset macro and go IDLE
    C_Timer.After(2.0, function()
        applyingLure = false
        FA.ResetMacro()
        FA.SetPixelState("IDLE")
    end)
end

---------------------------------------------------------------------------
-- Decision: should we apply a lure right now?
---------------------------------------------------------------------------
local function ShouldApplyCraftedLure()
    if not FishingAddonDB.autoLure then return false end
    local id = FishingAddonDB.selectedLure
    if not id then return false end
    if FA.isSelling or FA.navActive or FA.treasureHunting then return false end
    if InCombatLockdown() or applyingLure then return false end

    local data = LURE_BY_ID[id]
    if not data then return false end
    if IsLureBuffActive(data) then return false end
    return FindItemInBags(id) ~= nil
end

local function ShouldApplyThrowback()
    if not FishingAddonDB.autoThrowback then return false end
    local id = FishingAddonDB.selectedThrowback
    if not id then return false end
    if FA.isSelling or FA.navActive or FA.treasureHunting then return false end
    if InCombatLockdown() or applyingLure then return false end
    return FindItemInBags(id) ~= nil
end

function FA.CheckAndApplyLure()
    if ShouldApplyCraftedLure() then
        local data = LURE_BY_ID[FishingAddonDB.selectedLure]
        print(FA.PREFIX .. "Applying lure: " .. data.name)
        lastLureApplyTime = GetTime()
        DoApplyLure(data.name)
        return true
    end
    if ShouldApplyThrowback() then
        local data = LURE_BY_ID[FishingAddonDB.selectedThrowback]
        DoApplyLure(data.name)
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Hook: after fishing channel ends, apply lure before next cast
---------------------------------------------------------------------------
local lureFrame = CreateFrame("Frame")
lureFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")

lureFrame:SetScript("OnEvent", function(_, _, unit, _, spellID)
    if unit ~= "player" then return end
    local name = C_Spell.GetSpellName(spellID)
    if not name or not name:find("Fishing") then return end

    -- Tiny delay so spawn_detection / vendor can set their state first
    C_Timer.After(0.15, function()
        if not FA.treasureHunting and not FA.isSelling and not FA.navActive then
            FA.CheckAndApplyLure()
        end
    end)
end)

---------------------------------------------------------------------------
-- UI  —  /fa lure
---------------------------------------------------------------------------
local panel        = nil
local uiRows       = {}   -- reusable row frames
local uiHeaders    = {}   -- reusable header strings
local uiEmptyText  = nil

local function HideAllRows()
    for _, r in ipairs(uiRows) do r:Hide() end
    for _, h in ipairs(uiHeaders) do h:Hide() end
    if uiEmptyText then uiEmptyText:Hide() end
end

-- Get or create a header FontString at index i
local function GetHeader(parent, i)
    if uiHeaders[i] then return uiHeaders[i] end
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    uiHeaders[i] = fs
    return fs
end

-- Get or create a row Button at index i
local function GetRow(parent, i)
    if uiRows[i] then return uiRows[i] end

    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(28)

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    row.check = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.check:SetPoint("LEFT", 2, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", 20, 0)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWidth(155)

    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.info:SetPoint("RIGHT", -6, 0)

    uiRows[i] = row
    return row
end

local function RefreshPanel()
    if not panel then return end
    HideAllRows()

    local content  = panel.content
    local available = GetAvailableLures()
    local y         = -4
    local rowIdx    = 1
    local hdrIdx    = 1

    local function AddSection(title, category, selectedKey)
        local items = {}
        for _, info in ipairs(available) do
            if info.lure.category == category then
                table.insert(items, info)
            end
        end
        if #items == 0 then return end

        -- Header
        local hdr = GetHeader(content, hdrIdx)
        hdrIdx = hdrIdx + 1
        hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 10, y)
        hdr:SetText("|cffffcc00" .. title .. "|r")
        hdr:Show()
        y = y - 18

        for _, info in ipairs(items) do
            local isSelected = (FishingAddonDB[selectedKey] == info.lure.itemID)

            local row = GetRow(content, rowIdx)
            rowIdx = rowIdx + 1
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y)
            row:SetPoint("RIGHT", content, "RIGHT", -8, 0)

            row.check:SetText(isSelected and "|cff00ff00\226\156\147|r" or "   ")

            local tex = C_Item.GetItemIconByID(info.lure.itemID)
            row.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")

            local display = info.lure.name
            if info.count > 1 then display = display .. " |cffaaaaaa(x" .. info.count .. ")|r" end
            row.label:SetText(display)

            row.info:SetText(info.lure.effect and ("|cff888888" .. info.lure.effect .. "|r") or "")

            row:SetScript("OnClick", function()
                if FishingAddonDB[selectedKey] == info.lure.itemID then
                    FishingAddonDB[selectedKey] = nil
                else
                    FishingAddonDB[selectedKey] = info.lure.itemID
                    if selectedKey == "selectedLure" then
                        lastLureApplyTime = 0   -- force re-apply
                    end
                end
                RefreshPanel()
            end)

            row:Show()
            y = y - 30
        end
        y = y - 4
    end

    AddSection("Crafted Lures (30 min)",    "crafted",   "selectedLure")
    AddSection("Throwback Fish (stacking)", "throwback", "selectedThrowback")
    AddSection("Legacy Lures",              "legacy",    "selectedLure")

    -- Nothing in bags?
    if rowIdx == 1 then
        if not uiEmptyText then
            uiEmptyText = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        end
        uiEmptyText:SetPoint("CENTER", content)
        uiEmptyText:SetText("|cff888888No lures found in bags|r")
        uiEmptyText:Show()
    end
end

local function CreatePanel()
    if panel then
        panel:SetShown(not panel:IsShown())
        if panel:IsShown() then RefreshPanel() end
        return
    end

    local f = CreateFrame("Frame", "FishingAddonLurePanel", UIParent, "BackdropTemplate")
    f:SetSize(340, 420)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.12, 0.92)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cff00ccffFishing Lures|r")

    -- Close
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- Auto-lure checkbox
    local autoCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    autoCheck:SetPoint("TOPLEFT", 10, -34)
    autoCheck:SetSize(26, 26)
    autoCheck.label = autoCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    autoCheck.label:SetPoint("LEFT", autoCheck, "RIGHT", 2, 0)
    autoCheck.label:SetText("Auto-apply lures between casts")
    autoCheck:SetChecked(FishingAddonDB.autoLure)
    autoCheck:SetScript("OnClick", function(self)
        FishingAddonDB.autoLure = self:GetChecked()
        print(FA.PREFIX .. "Auto-lure: " .. (FishingAddonDB.autoLure and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
    end)

    -- Auto-throwback checkbox
    local throwCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    throwCheck:SetPoint("TOPLEFT", 10, -58)
    throwCheck:SetSize(26, 26)
    throwCheck.label = throwCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    throwCheck.label:SetPoint("LEFT", throwCheck, "RIGHT", 2, 0)
    throwCheck.label:SetText("Auto-throwback fish for buffs")
    throwCheck:SetChecked(FishingAddonDB.autoThrowback)
    throwCheck:SetScript("OnClick", function(self)
        FishingAddonDB.autoThrowback = self:GetChecked()
        print(FA.PREFIX .. "Auto-throwback: " .. (FishingAddonDB.autoThrowback and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
    end)

    -- Scrollable content
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -88)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 8)
    f.content = content

    -- Refresh on bag changes
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:SetScript("OnEvent", function()
        if f:IsShown() then RefreshPanel() end
    end)

    panel = f
    RefreshPanel()
end

function FA.ToggleLurePanel()
    CreatePanel()
end

---------------------------------------------------------------------------
-- Init saved vars
---------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    if FishingAddonDB.autoLure == nil then FishingAddonDB.autoLure = false end
    if FishingAddonDB.autoThrowback == nil then FishingAddonDB.autoThrowback = false end

    if FishingAddonDB.selectedLure then
        local data = LURE_BY_ID[FishingAddonDB.selectedLure]
        if data then
            print(FA.PREFIX .. "Lure: " .. data.name .. (FishingAddonDB.autoLure and " |cff00ff00(auto)|r" or " |cff888888(manual)|r"))
        end
    end
end)
