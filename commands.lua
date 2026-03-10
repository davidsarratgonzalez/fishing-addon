-- Fishing Addon - Slash Commands
-- /fa to toggle sound muting, /fa status for info.

local FA = FishingAddon

SLASH_FISHINGADDON1 = "/fa"
SLASH_FISHINGADDON2 = "/fishingaddon"

SlashCmdList["FISHINGADDON"] = function(msg)
    local cmd = (msg or ""):lower():trim()

    if cmd == "save" then
        FA.SaveNavPosition()
        return
    elseif cmd == "nav" then
        FA.StartNavigation()
        return
    elseif cmd == "stop" then
        FA.StopNavigation()
        return
    elseif cmd == "sell" then
        FA.StartSellSequence()
        return
    elseif cmd == "lure" then
        FA.ToggleLurePanel()
        return
    elseif cmd:sub(1, 6) == "logout" then
        local arg = cmd:sub(8):trim()
        FA.HandleLogoutCommand(arg)
        return
    elseif cmd == "soft" then
        -- Debug: print current soft-target info (interact, enemy, friend)
        print(FA.PREFIX .. "=== SOFT TARGET DEBUG ===")
        for _, token in ipairs({"softinteract", "softenemy", "softfriend"}) do
            if UnitExists(token) then
                local name = UnitName(token) or "?"
                local guid = UnitGUID(token) or "?"
                print(string.format("  %s: |cff00ff00%s|r  GUID: %s", token, name, guid))
            else
                print(string.format("  %s: |cff888888(none)|r", token))
            end
        end
        -- Also check hard target
        if UnitExists("target") then
            print(string.format("  target: |cffffcc00%s|r  GUID: %s", UnitName("target") or "?", UnitGUID("target") or "?"))
        else
            print("  target: |cff888888(none)|r")
        end
        -- Show relevant CVars
        print(string.format("  SoftTargetInteract: %s", GetCVar("SoftTargetInteract")))
        print(string.format("  SoftTargetInteractRange: %s", GetCVar("SoftTargetInteractRange")))
        print(string.format("  SoftTargetInteractArc: %s", GetCVar("SoftTargetInteractArc")))
        print(string.format("  SoftTargetIconInteract: %s", GetCVar("SoftTargetIconInteract")))
        print(string.format("  SoftTargetIconGameObject: %s", GetCVar("SoftTargetIconGameObject")))
        print("  ==========================")
        return

    elseif cmd == "softwatch" then
        -- Toggle live soft-target watcher (prints every change)
        if FA._softWatchFrame then
            FA._softWatchFrame:UnregisterAllEvents()
            FA._softWatchFrame:SetScript("OnEvent", nil)
            FA._softWatchFrame = nil
            print(FA.PREFIX .. "Soft-target watcher |cffff4444OFF|r")
        else
            local f = CreateFrame("Frame")
            f:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
            f:RegisterEvent("PLAYER_SOFT_ENEMY_CHANGED")
            f:RegisterEvent("PLAYER_SOFT_FRIEND_CHANGED")
            f:SetScript("OnEvent", function(_, event)
                local token = "softinteract"
                if event == "PLAYER_SOFT_ENEMY_CHANGED" then token = "softenemy" end
                if event == "PLAYER_SOFT_FRIEND_CHANGED" then token = "softfriend" end
                if UnitExists(token) then
                    local name = UnitName(token) or "?"
                    local guid = UnitGUID(token) or "?"
                    print(FA.PREFIX .. string.format("|cff00ff00[%s]|r %s → %s (GUID: %s)", event, token, name, guid))
                else
                    print(FA.PREFIX .. string.format("|cff888888[%s]|r %s → (cleared)", event, token))
                end
            end)
            FA._softWatchFrame = f
            print(FA.PREFIX .. "Soft-target watcher |cff00ff00ON|r — will print every change. Use /fa softwatch to stop.")
        end
        return

    elseif cmd == "debug" then
        local state = "unknown"
        for name, c in pairs(FA.PIXEL_COLORS) do
            state = name  -- just show last, real check is pixel
        end
        print(FA.PREFIX .. "=== DEBUG ===")
        print("  isActive: " .. tostring(FA.isActive))
        print("  isSelling: " .. tostring(FA.isSelling))
        print("  sellStep: " .. tostring(FA.sellStep))
        print("  navActive: " .. tostring(FA.navActive))
        print("  treasureHunting: " .. tostring(FA.treasureHunting))
        print("  isCurrentlyFishing: " .. tostring(FA.isCurrentlyFishing))
        print("  Vendor mount: " .. (FA.HasVendorMount() and "yes" or "no"))
        print("  Free bag slots: " .. FA.GetFreeBagSlots())
        print("  Macro 'FA' index: " .. tostring(GetMacroIndexByName("FA")))
        local idx = GetMacroIndexByName("FA")
        if idx > 0 then
            local name, _, body = GetMacroInfo(idx)
            print("  Macro body: " .. tostring(body))
        end
        print("  IsMounted: " .. tostring(IsMounted()))
        print("  Target: " .. tostring(UnitName("target") or "none"))
        print("  =============")
        return
    end

    if FA.isMuting then
        print(FA.PREFIX .. "Please wait, still processing sounds...")
        return
    end

    if cmd == "" or cmd == "toggle" then
        FishingAddonDB.enabled = not FishingAddonDB.enabled
        if FishingAddonDB.enabled then
            FA.EnableSoundMuting()
        else
            FA.DisableSoundMuting()
        end

    elseif cmd == "status" then
        print(FA.PREFIX .. "Status:")
        print("  Sound muting: " .. tostring(FishingAddonDB.enabled))
        print("  Active: " .. tostring(FA.isActive))
        print("  Sound IDs loaded: " .. FA.GetSoundIDCount())
        print("  Currently fishing: " .. tostring(FA.isCurrentlyFishing))
        if FA.savedNav then
            print(string.format("  Saved pos: (%.1f, %.1f) facing %.1f°",
                FA.savedNav.x, FA.savedNav.y, FA.savedNav.facing * 180 / math.pi))
        end
        print("  Nav active: " .. tostring(FA.navActive))
        print("  Vendor mount: " .. (FA.HasVendorMount() and "yes" or "no"))
        print("  Selling: " .. tostring(FA.isSelling))
        print("  Free bag slots: " .. FA.GetFreeBagSlots())

    else
        print(FA.PREFIX .. "Commands:")
        print("  /fa        - Toggle sound muting on/off")
        print("  /fa status - Show current state")
        print("  /fa save   - Save current position for navigation")
        print("  /fa nav    - Navigate back to saved position")
        print("  /fa stop   - Stop navigation")
        print("  /fa sell   - Summon vendor mount and sell greys")
        print("  /fa lure   - Open lure selection panel")
        print("  /fa logout HH:MM:SS - Set auto-logout time (or 'off')")
        print("  /fa soft   - Debug: show current soft-target info")
        print("  /fa softwatch - Toggle live soft-target change logger")
    end
end
