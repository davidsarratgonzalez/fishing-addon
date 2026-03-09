-- Fishing Addon - Fast Loot
-- Instantly loots all items when the loot window opens.

local lastLootTime = 0
local LOOT_DEBOUNCE = 0.3

local frame = CreateFrame("Frame")
frame:RegisterEvent("LOOT_READY")

frame:SetScript("OnEvent", function()
    if (GetTime() - lastLootTime) < LOOT_DEBOUNCE then return end
    if GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") then
        for i = GetNumLootItems(), 1, -1 do
            LootSlot(i)
        end
        lastLootTime = GetTime()
    end
end)
