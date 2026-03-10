-- Fishing Addon - Auto Logout
-- Sets a specific time (HH:MM:SS) to auto-logout via /camp.
-- When the time is reached, sets LOGOUT pixel state -> bot types /camp.
-- Configure via /fa logout HH:MM:SS or /fa logout off
--
-- Smart scheduling: computes the NEXT occurrence of the target time
-- relative to login. If you log in at 22:30 and set 02:30, it knows
-- that means tonight (tomorrow's 02:30). If you log in at 02:31,
-- it waits until the following day's 02:30.

local FA = FishingAddon

local logoutFrame = CreateFrame("Frame")
local checkInterval = 1.0  -- check every second
local elapsed = 0

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local logoutTriggered = false
local logoutTimestamp = nil  -- absolute epoch time to trigger logout

---------------------------------------------------------------------------
-- Compute the next target timestamp from HH:MM:SS
-- If the time has already passed today, schedule for tomorrow.
---------------------------------------------------------------------------
local function ComputeLogoutTimestamp()
    local target = FishingAddonDB.logoutTime
    if not target or target == "" then return nil end

    local h, m, s = target:match("^(%d+):(%d+):(%d+)$")
    if not h then return nil end

    local now = time()
    local today = date("*t", now)
    today.hour = tonumber(h)
    today.min = tonumber(m)
    today.sec = tonumber(s)

    local targetTime = time(today)
    if targetTime <= now then
        targetTime = targetTime + 86400  -- next occurrence = tomorrow
    end

    return targetTime
end

---------------------------------------------------------------------------
-- Check if it's time to logout
---------------------------------------------------------------------------
local function CheckLogoutTime()
    if logoutTriggered then return end
    if not logoutTimestamp then return end

    -- Don't logout during treasure hunting
    if FA.treasureHunting then return end

    if time() >= logoutTimestamp then
        logoutTriggered = true
        print(FA.PREFIX .. "|cffff4444Logout time reached! Sending /camp...|r")
        FA.SetPixelState("LOGOUT")
    end
end

logoutFrame:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed < checkInterval then return end
    elapsed = 0
    CheckLogoutTime()
end)

---------------------------------------------------------------------------
-- Slash command handler (called from commands.lua)
---------------------------------------------------------------------------
function FA.HandleLogoutCommand(arg)
    if not arg or arg == "" then
        local current = FishingAddonDB.logoutTime
        if current and current ~= "" then
            print(FA.PREFIX .. "Auto-logout set to: |cff00ff00" .. current .. "|r")
            if logoutTimestamp then
                local remaining = logoutTimestamp - time()
                if remaining > 0 then
                    local rh = math.floor(remaining / 3600)
                    local rm = math.floor((remaining % 3600) / 60)
                    print(FA.PREFIX .. string.format("  Time remaining: %dh %dm", rh, rm))
                end
            end
        else
            print(FA.PREFIX .. "Auto-logout: |cff888888disabled|r")
        end
        print(FA.PREFIX .. "Usage: /fa logout HH:MM:SS  or  /fa logout off")
        return
    end

    if arg == "off" or arg == "disable" or arg == "clear" then
        FishingAddonDB.logoutTime = ""
        logoutTriggered = false
        logoutTimestamp = nil
        print(FA.PREFIX .. "Auto-logout |cffff4444disabled|r.")
        return
    end

    -- Parse HH:MM:SS
    local h, m, s = arg:match("^(%d+):(%d+):(%d+)$")
    if not h then
        -- Also accept HH:MM (assume :00 seconds)
        h, m = arg:match("^(%d+):(%d+)$")
        s = "00"
    end

    if not h then
        print(FA.PREFIX .. "|cffff4444Invalid format.|r Use HH:MM:SS (e.g. 23:30:00)")
        return
    end

    h, m, s = tonumber(h), tonumber(m), tonumber(s)
    if h > 23 or m > 59 or s > 59 then
        print(FA.PREFIX .. "|cffff4444Invalid time.|r Hours 0-23, minutes/seconds 0-59.")
        return
    end

    FishingAddonDB.logoutTime = string.format("%02d:%02d:%02d", h, m, s)
    logoutTriggered = false
    logoutTimestamp = ComputeLogoutTimestamp()

    -- Show when it will trigger
    if logoutTimestamp then
        local remaining = logoutTimestamp - time()
        local rh = math.floor(remaining / 3600)
        local rm = math.floor((remaining % 3600) / 60)
        print(FA.PREFIX .. string.format(
            "Auto-logout set to |cff00ff00%s|r (in %dh %dm)",
            FishingAddonDB.logoutTime, rh, rm))
    end
end

---------------------------------------------------------------------------
-- Init: compute timestamp on login
---------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    FishingAddonDB.logoutTime = FishingAddonDB.logoutTime or ""
    logoutTriggered = false
    logoutTimestamp = ComputeLogoutTimestamp()

    if logoutTimestamp then
        local remaining = logoutTimestamp - time()
        local rh = math.floor(remaining / 3600)
        local rm = math.floor((remaining % 3600) / 60)
        print(FA.PREFIX .. string.format(
            "Auto-logout scheduled at %s (in %dh %dm)",
            FishingAddonDB.logoutTime, rh, rm))
    end
end)
