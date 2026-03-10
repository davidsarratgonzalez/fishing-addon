-- Fishing Addon - Pixel Bridge
-- Renders a small colored pixel at the top-left corner of the screen.
-- Used as a communication channel between the addon and the Python bot.
-- Requires: CVar gxMaximize=0 (windowed/borderless), RenderInBackground=1

local FA = FishingAddon

---------------------------------------------------------------------------
-- Ensure WoW keeps rendering when in background / minimized
---------------------------------------------------------------------------
local function ApplyRenderSettings()
    SetCVar("RAIDsettingsEnabled", "0")
    SetCVar("RenderInBackground", "1")
    SetCVar("MaxFPSBk", "999")  -- uncapped background FPS
end

---------------------------------------------------------------------------
-- Pixel frames: 4 adjacent 1-screen-pixel blocks at top-left.
-- Uses 1/GetEffectiveScale() so each frame is exactly 1 WoW screen pixel.
-- Python auto-calibrates from the blue block to find actual capture positions.
---------------------------------------------------------------------------
local NUM_PIXELS = 4

local textures = {}

local function CreatePixelFrames()
    local scale = UIParent:GetEffectiveScale()
    local px = 1 / scale  -- 1 screen pixel in UI units

    for i = 0, NUM_PIXELS - 1 do
        local f = CreateFrame("Frame", "FishingAddonPixel" .. i, UIParent)
        f:SetSize(px, px)
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", i * px, 0)
        f:SetFrameStrata("TOOLTIP")
        f:SetFrameLevel(9999)
        local tex = f:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetAllPoints(f)
        tex:SetColorTexture(0, 0, 0, 1)
        f:SetClampedToScreen(true)
        f:EnableMouse(false)
        f:Show()
        textures[i] = tex
    end

    -- Default pixel 0 to blue (idle)
    textures[0]:SetColorTexture(0, 0, 1, 1)
end

---------------------------------------------------------------------------
-- Public API: set pixel colors (r, g, b each 0.0-1.0)
---------------------------------------------------------------------------
function FA.SetPixelColor(r, g, b)
    textures[0]:SetColorTexture(r, g, b, 1)
end

function FA.SetNavPixel(index, r, g, b)
    if textures[index] then
        textures[index]:SetColorTexture(r, g, b, 1)
    end
end

-- Predefined states as colors
FA.PIXEL_COLORS = {
    IDLE            = { 0, 0, 1 },       -- Blue: nothing happening
    FISHING         = { 0, 1, 0 },       -- Green: currently fishing
    NAV             = { 0, 1, 1 },       -- Cyan: navigating to saved position
    TREASURE_SPAWN  = { 1, 0, 1 },       -- Magenta: patient treasure spawned
    TREASURE_TARGET = { 1, 1, 0 },       -- Yellow: treasure in soft-target
    SPIRIT_SPAWN    = { 1, 0, 0 },       -- Red: blood hunter spirit
    CRAB_SPAWN      = { 1, 0.5, 0 },     -- Orange: root crab
    SELL_ACTION     = { 0.5, 0, 1 },     -- Purple: press cast key (macro)
    SELL_INTERACT   = { 0.5, 1, 0 },     -- Lime: press interact key
    SELL_WAIT       = { 0.5, 0.5, 0 },   -- Olive: wait, don't press anything
    LURE            = { 0, 0.5, 0.5 },   -- Teal: press cast key (applies lure via macro)
}

function FA.SetPixelState(state)
    local c = FA.PIXEL_COLORS[state]
    if c then
        FA.SetPixelColor(c[1], c[2], c[3])
    end
    -- Safety: whenever returning to IDLE, ensure macro is reset to fishing
    if state == "IDLE" and FA.ResetMacro and not InCombatLockdown() then
        FA.ResetMacro()
    end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    ApplyRenderSettings()
    CreatePixelFrames()
    FA.SetPixelState("IDLE")
    local scale = UIParent:GetEffectiveScale()
    print(FA.PREFIX .. string.format("Pixel bridge active (scale=%.2f, 4 pixels at top-left)", scale))
end)
