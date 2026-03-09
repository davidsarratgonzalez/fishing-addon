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

    else
        print(FA.PREFIX .. "Commands:")
        print("  /fa        - Toggle sound muting on/off")
        print("  /fa status - Show current state")
        print("  /fa save   - Save current position for navigation")
        print("  /fa nav    - Navigate back to saved position")
        print("  /fa stop   - Stop navigation")
    end
end
