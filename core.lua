-- Fishing Addon - Core
-- Shared state, constants, and initialization.

FishingAddon = FishingAddon or {}

FishingAddon.PREFIX = "|cff00ccff[FishingAddon]|r "
FishingAddon.isActive = false
FishingAddon.isMuting = false
FishingAddon.isCurrentlyFishing = false
FishingAddon.lastCastTime = 0

-- Saved variables (persisted between sessions)
FishingAddonDB = FishingAddonDB or {
    enabled = false,
}

---------------------------------------------------------------------------
-- Init on login
---------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")

initFrame:SetScript("OnEvent", function()
    FishingAddonDB = FishingAddonDB or { enabled = false }

    FishingAddon.ApplySoftTargeting()

    if FishingAddonDB.enabled then
        FishingAddon.EnableSoundMuting()
    else
        print(FishingAddon.PREFIX .. "Loaded (disabled). Type /fa to enable.")
    end
end)
