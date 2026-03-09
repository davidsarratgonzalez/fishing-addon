-- Fishing Addon - Sell Greys
-- Automatically sells all grey (Poor quality) items when opening a vendor.

local FA = FishingAddon

local frame = CreateFrame("Frame")
frame:RegisterEvent("MERCHANT_SHOW")

frame:SetScript("OnEvent", function()
    local itemsSold = 0

    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == Enum.ItemQuality.Poor and (info.sellPrice or 0) > 0 then
                C_Container.UseContainerItem(bag, slot)
                itemsSold = itemsSold + 1
            end
        end
    end

    if itemsSold > 0 then
        print(FA.PREFIX .. "Sold " .. itemsSold .. " grey items.")
    end
end)
