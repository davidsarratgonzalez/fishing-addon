-- Fishing Addon - Navigation
-- Saves a position and navigates back to it via pixel-encoded commands.
-- The Python bot reads nav pixels and sends arrow key inputs.
--
-- Pixel layout:
--   (0,0) = State pixel (IDLE/FISHING/etc, existing)
--   (1,0) = Nav command:  R=step(0-4), G=action(0-3), B=frameCounter(0-255)
--   (2,0) = Distance:     R=yards_int, G=yards_frac, B=flags
--   (3,0) = Angle:        R=degrees_int, G=degrees_frac, B=direction(0=CW/right, 1=CCW/left)
--
-- Steps: 0=IDLE, 1=ROTATE_TO_TARGET, 2=WALK, 3=ROTATE_TO_FACING, 4=DONE
-- Actions (pixel G): 0=NONE, 1=TURN_LEFT, 2=TURN_RIGHT, 3=MOVE_FORWARD
--
-- Distance flags (pixel 2 B channel):
--   bit 0: close mode (dist < 2 yards)
--   bit 1: very close mode (dist < 0.5 yards — arrived)
--   bit 2: heading behind player (> 90°)

local FA = FishingAddon

-- Nav state
local NAV_STEP_IDLE = 0
local NAV_STEP_ROTATE_TO_TARGET = 1
local NAV_STEP_WALK = 2
local NAV_STEP_ROTATE_TO_FACING = 3
local NAV_STEP_DONE = 4

local NAV_ACTION_NONE = 0
local NAV_ACTION_TURN_LEFT = 1
local NAV_ACTION_TURN_RIGHT = 2
local NAV_ACTION_MOVE_FORWARD = 3

-- Thresholds
local ANGLE_THRESHOLD = 0.03   -- radians (~1.7°) — matches minimum pulse resolution
local DIST_THRESHOLD  = 0.5    -- yards — tight positional accuracy
local HEADING_GATE    = 0.26   -- radians (~15°) — stop walking and re-rotate if heading drifts

-- Saved position
FA.savedNav = nil  -- { mapID, x, y, facing }
FA.navActive = false
FA.navStep = NAV_STEP_IDLE

---------------------------------------------------------------------------
-- Math helpers
---------------------------------------------------------------------------
local PI = math.pi
local TWO_PI = 2 * PI

local function NormalizeAngle(a)
    a = a % TWO_PI
    if a < 0 then a = a + TWO_PI end
    return a
end

local function AngleDiff(from, to)
    local diff = NormalizeAngle(to) - NormalizeAngle(from)
    if diff > PI then diff = diff - TWO_PI end
    if diff < -PI then diff = diff + TWO_PI end
    return diff
end

local function AngleToTarget(myY, myX, targetY, targetX)
    local dx = targetX - myX
    local dy = targetY - myY
    return NormalizeAngle(math.atan2(dx, dy))
end

local function Distance(myY, myX, targetY, targetX)
    local dx = targetX - myX
    local dy = targetY - myY
    return math.sqrt(dx * dx + dy * dy)
end

---------------------------------------------------------------------------
-- Encode values into pixel colors (0.0-1.0 range, maps to 0-255 in GDI)
---------------------------------------------------------------------------
local navFrameCounter = 0

local function EncodeNavCommand(step, action)
    navFrameCounter = (navFrameCounter + 1) % 256
    FA.SetNavPixel(1, step / 255, action / 255, navFrameCounter / 255)
end

local function EncodeDistance(yards, headingAbsDiff)
    local clamped = math.min(yards, 255.99)
    local int_part = math.floor(clamped)
    local frac_part = math.floor((clamped - int_part) * 255)
    -- Distance flags in B channel
    local flags = 0
    if yards < 2 then flags = flags + 1 end       -- close mode
    if yards < DIST_THRESHOLD then flags = flags + 2 end  -- arrived
    if headingAbsDiff and headingAbsDiff > 1.57 then flags = flags + 4 end  -- target behind
    FA.SetNavPixel(2, int_part / 255, frac_part / 255, flags / 255)
end

local function EncodeAngle(radians, direction)
    local degrees = math.abs(radians) * 180 / PI
    local clamped = math.min(degrees, 255.99)
    local int_part = math.floor(clamped)
    local frac_part = math.floor((clamped - int_part) * 255)
    local dirVal = (direction > 0) and 1 or 0
    FA.SetNavPixel(3, int_part / 255, frac_part / 255, dirVal / 255)
end

local function ClearNavPixels()
    FA.SetNavPixel(1, 0, 0, 0)
    FA.SetNavPixel(2, 0, 0, 0)
    FA.SetNavPixel(3, 0, 0, 0)
end

---------------------------------------------------------------------------
-- Save position: /fa save
---------------------------------------------------------------------------
function FA.SaveNavPosition()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then
        print(FA.PREFIX .. "Cannot determine current map.")
        return
    end

    local y, x = UnitPosition("player")
    if not y or not x then
        print(FA.PREFIX .. "Cannot read position (are you in an instance?).")
        return
    end

    local facing = GetPlayerFacing()
    if not facing then
        print(FA.PREFIX .. "Cannot read facing.")
        return
    end

    FA.savedNav = {
        mapID = mapID,
        x = x,
        y = y,
        facing = facing,
    }

    print(FA.PREFIX .. string.format(
        "Position saved: (%.1f, %.1f) facing %.1f° on map %d",
        x, y, facing * 180 / PI, mapID
    ))
end

---------------------------------------------------------------------------
-- Navigation loop
---------------------------------------------------------------------------
local navFrame = CreateFrame("Frame")

local function StopNav(reason)
    FA.navActive = false
    FA.navStep = NAV_STEP_IDLE
    navFrame:SetScript("OnUpdate", nil)
    ClearNavPixels()
    FA.SetPixelState("IDLE")
    if reason then
        print(FA.PREFIX .. "Nav: " .. reason)
    end
end

local function NavUpdate()
    if not FA.navActive or not FA.savedNav then
        StopNav("No target.")
        return
    end

    local saved = FA.savedNav
    local myY, myX = UnitPosition("player")
    if not myY or not myX then
        StopNav("Lost position.")
        return
    end

    local facing = GetPlayerFacing()
    if not facing then
        StopNav("Lost facing.")
        return
    end

    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID ~= saved.mapID then
        StopNav("Different map!")
        return
    end

    local dist = Distance(myY, myX, saved.y, saved.x)

    if FA.navStep == NAV_STEP_ROTATE_TO_TARGET then
        -- Step 1: Rotate to face the target position
        if dist <= DIST_THRESHOLD then
            FA.navStep = NAV_STEP_ROTATE_TO_FACING
            return
        end

        local targetAngle = AngleToTarget(myY, myX, saved.y, saved.x)
        local diff = AngleDiff(facing, targetAngle)

        if math.abs(diff) <= ANGLE_THRESHOLD then
            -- Aligned, start walking
            FA.navStep = NAV_STEP_WALK
            EncodeNavCommand(NAV_STEP_WALK, NAV_ACTION_MOVE_FORWARD)
            EncodeDistance(dist, 0)
            EncodeAngle(0, 0)
        else
            local action = (diff > 0) and NAV_ACTION_TURN_LEFT or NAV_ACTION_TURN_RIGHT
            EncodeNavCommand(NAV_STEP_ROTATE_TO_TARGET, action)
            EncodeDistance(dist, math.abs(diff))
            EncodeAngle(diff, (diff > 0) and 1 or -1)
        end

    elseif FA.navStep == NAV_STEP_WALK then
        -- Step 2: Walk toward target with live steering
        if dist <= DIST_THRESHOLD then
            FA.navStep = NAV_STEP_ROTATE_TO_FACING
            EncodeNavCommand(NAV_STEP_ROTATE_TO_FACING, NAV_ACTION_NONE)
            return
        end

        local targetAngle = AngleToTarget(myY, myX, saved.y, saved.x)
        local diff = AngleDiff(facing, targetAngle)
        local absDiff = math.abs(diff)

        if absDiff > HEADING_GATE then
            -- Heading drifted too far: stop walking, re-rotate
            FA.navStep = NAV_STEP_ROTATE_TO_TARGET
            local action = (diff > 0) and NAV_ACTION_TURN_LEFT or NAV_ACTION_TURN_RIGHT
            EncodeNavCommand(NAV_STEP_ROTATE_TO_TARGET, action)
            EncodeDistance(dist, absDiff)
            EncodeAngle(diff, (diff > 0) and 1 or -1)
        elseif absDiff > ANGLE_THRESHOLD then
            -- Mild steering correction while walking
            local action = (diff > 0) and NAV_ACTION_TURN_LEFT or NAV_ACTION_TURN_RIGHT
            EncodeNavCommand(NAV_STEP_WALK, action)
            EncodeDistance(dist, absDiff)
            EncodeAngle(diff, (diff > 0) and 1 or -1)
        else
            -- On course, walk straight
            EncodeNavCommand(NAV_STEP_WALK, NAV_ACTION_MOVE_FORWARD)
            EncodeDistance(dist, 0)
            EncodeAngle(0, 0)
        end

    elseif FA.navStep == NAV_STEP_ROTATE_TO_FACING then
        -- Step 3: Rotate to match saved facing direction
        local diff = AngleDiff(facing, saved.facing)

        if math.abs(diff) <= ANGLE_THRESHOLD then
            -- Done!
            FA.navStep = NAV_STEP_DONE
            EncodeNavCommand(NAV_STEP_DONE, NAV_ACTION_NONE)
            EncodeDistance(0, 0)
            EncodeAngle(0, 0)
            StopNav("Arrived at saved position!")
            return
        end

        local action = (diff > 0) and NAV_ACTION_TURN_LEFT or NAV_ACTION_TURN_RIGHT
        EncodeNavCommand(NAV_STEP_ROTATE_TO_FACING, action)
        EncodeDistance(0, math.abs(diff))
        EncodeAngle(diff, (diff > 0) and 1 or -1)
    end
end

function FA.StartNavigation()
    if not FA.savedNav then
        print(FA.PREFIX .. "No saved position! Use /fa save first.")
        return
    end

    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID ~= FA.savedNav.mapID then
        print(FA.PREFIX .. "You are on a different map than the saved position!")
        return
    end

    FA.navActive = true
    FA.navStep = NAV_STEP_ROTATE_TO_TARGET
    FA.SetPixelState("NAV")

    print(FA.PREFIX .. string.format(
        "Navigating to (%.1f, %.1f) facing %.1f°...",
        FA.savedNav.x, FA.savedNav.y, FA.savedNav.facing * 180 / PI
    ))

    navFrame:SetScript("OnUpdate", function()
        NavUpdate()
    end)
end

function FA.StopNavigation()
    StopNav("Navigation cancelled.")
end
