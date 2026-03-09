-- Fishing Addon - Sell Greys
-- Automatically sells all grey (Poor quality) items when opening a vendor.
-- Uses C_MerchantFrame.SellAllJunkItems() (Blizzard built-in) with a
-- manual fallback via UseContainerItem for older clients.

local FA = FishingAddon

local frame = CreateFrame("Frame")
frame:RegisterEvent("MERCHANT_SHOW")

frame:SetScript("OnEvent", function()
    -- Try the built-in junk sell first (added in Dragonflight)
    if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
        C_MerchantFrame.SellAllJunkItems()
        print(FA.PREFIX .. "Selling junk items...")
        return
    end

    -- Fallback: manual sell via UseContainerItem
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
