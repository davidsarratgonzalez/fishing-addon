-- Fishing Addon - Navigation
-- Saves a position and navigates back to it via pixel-encoded commands.
-- The Python bot reads nav pixels and sends arrow key inputs.
--
-- Pixel layout:
--   (0,0) = State pixel (IDLE/FISHING/etc, existing)
--   (1,0) = Nav command:  R=step(0-3), G=action(0-3), B=0
--   (2,0) = Distance:     R=yards_int(0-255), G=yards_frac(0-255), B=0
--   (3,0) = Angle:        R=degrees_int(0-255), G=degrees_frac(0-255), B=direction(0=CW/right, 1=CCW/left)
--
-- Steps: 0=IDLE, 1=ROTATE_TO_TARGET, 2=WALK, 3=ROTATE_TO_FACING, 4=DONE
-- Actions (pixel G): 0=NONE, 1=TURN_LEFT, 2=TURN_RIGHT, 3=MOVE_FORWARD, 4=MOVE_BACKWARD

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
local NAV_ACTION_MOVE_BACKWARD = 4

-- Thresholds
local ANGLE_THRESHOLD = 0.03   -- radians (~1.7 degrees) — tight facing accuracy
local DIST_THRESHOLD = 1.0     -- yards — tight position accuracy

-- Saved position
FA.savedNav = nil  -- { mapID, x, y, facing }
FA.navActive = false
FA.navStep = NAV_STEP_IDLE

---------------------------------------------------------------------------
-- Math helpers
---------------------------------------------------------------------------
local PI = math.pi
local TWO_PI = 2 * PI

-- Normalize angle to [0, 2π)
local function NormalizeAngle(a)
    a = a % TWO_PI
    if a < 0 then a = a + TWO_PI end
    return a
end

-- Shortest signed angle from 'from' to 'to' (positive = CCW, negative = CW)
local function AngleDiff(from, to)
    local diff = NormalizeAngle(to) - NormalizeAngle(from)
    if diff > PI then diff = diff - TWO_PI end
    if diff < -PI then diff = diff + TWO_PI end
    return diff
end

-- Angle from current position to target position
-- WoW: UnitPosition returns (y, x) in yards. GetPlayerFacing: 0=North, increases CCW.
local function AngleToTarget(myY, myX, targetY, targetX)
    local dx = targetX - myX
    local dy = targetY - myY
    -- atan2(dx, dy) gives angle from north, increasing CCW (matches WoW convention)
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
local function EncodeNavCommand(step, action)
    FA.SetNavPixel(1, step / 255, action / 255, 0)
end

local function EncodeDistance(yards)
    local clamped = math.min(yards, 255.99)
    local int_part = math.floor(clamped)
    local frac_part = math.floor((clamped - int_part) * 255)
    FA.SetNavPixel(2, int_part / 255, frac_part / 255, 0)
end

local function EncodeAngle(radians, direction)
    -- Convert to degrees for easier reading on the Python side
    local degrees = math.abs(radians) * 180 / PI
    local clamped = math.min(degrees, 255.99)
    local int_part = math.floor(clamped)
    local frac_part = math.floor((clamped - int_part) * 255)
    -- B channel: 0 = CW (turn right), 1 = CCW (turn left)
    local dirVal = (direction > 0) and 1 or 0
    FA.SetNavPixel(3, int_part / 255, frac_part / 255, dirVal / 255)
end

local function ClearNavPixels()
    EncodeNavCommand(NAV_STEP_IDLE, NAV_ACTION_NONE)
    EncodeDistance(0)
    EncodeAngle(0, 0)
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
-- Navigation loop: /fa nav
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
            -- Already close enough, skip to facing correction
            FA.navStep = NAV_STEP_ROTATE_TO_FACING
            return
        end

        local targetAngle = AngleToTarget(myY, myX, saved.y, saved.x)
        local diff = AngleDiff(facing, targetAngle)

        if math.abs(diff) <= ANGLE_THRESHOLD then
            -- Aligned, start walking
            FA.navStep = NAV_STEP_WALK
            EncodeNavCommand(NAV_STEP_WALK, NAV_ACTION_MOVE_FORWARD)
            EncodeDistance(dist)
            EncodeAngle(0, 0)
        else
            -- Need to turn: diff > 0 = CCW = turn left, diff < 0 = CW = turn right
            local action = (diff > 0) and NAV_ACTION_TURN_LEFT or NAV_ACTION_TURN_RIGHT
            EncodeNavCommand(NAV_STEP_ROTATE_TO_TARGET, action)
            EncodeDistance(dist)
            EncodeAngle(diff, (diff > 0) and 1 or -1)
        end

    elseif FA.navStep == NAV_STEP_WALK then
        -- Step 2: Walk toward target, self-correcting heading
        if dist <= DIST_THRESHOLD then
            -- Arrived, correct facing
            FA.navStep = NAV_STEP_ROTATE_TO_FACING
            EncodeNavCommand(NAV_STEP_ROTATE_TO_FACING, NAV_ACTION_NONE)
            return
        end

        -- Recalculate heading while walking
        local targetAngle = AngleToTarget(myY, myX, saved.y, saved.x)
        local diff = AngleDiff(facing, targetAngle)
        local absDiff = math.abs(diff)

        local action
        if absDiff > 2.1 then
            -- Target is behind us (>120°) — walk backward instead of turning around
            -- This happens when we overshoot the target
            action = NAV_ACTION_MOVE_BACKWARD
        elseif absDiff > ANGLE_THRESHOLD then
            -- Need course correction: combine turning with walking
            action = (diff > 0) and NAV_ACTION_TURN_LEFT or NAV_ACTION_TURN_RIGHT
        else
            action = NAV_ACTION_MOVE_FORWARD
        end

        EncodeNavCommand(NAV_STEP_WALK, action)
        EncodeDistance(dist)
        EncodeAngle(diff, (diff > 0) and 1 or -1)

    elseif FA.navStep == NAV_STEP_ROTATE_TO_FACING then
        -- Step 3: Rotate to match saved facing direction
        local diff = AngleDiff(facing, saved.facing)

        if math.abs(diff) <= ANGLE_THRESHOLD then
            -- Done!
            FA.navStep = NAV_STEP_DONE
            EncodeNavCommand(NAV_STEP_DONE, NAV_ACTION_NONE)
            EncodeDistance(0)
            EncodeAngle(0, 0)
            StopNav("Arrived at saved position!")
            return
        end

        local action = (diff > 0) and NAV_ACTION_TURN_LEFT or NAV_ACTION_TURN_RIGHT
        EncodeNavCommand(NAV_STEP_ROTATE_TO_FACING, action)
        EncodeDistance(0)
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
        "Navigating to saved position (%.1f, %.1f)...",
        FA.savedNav.x, FA.savedNav.y
    ))

    navFrame:SetScript("OnUpdate", function()
        NavUpdate()
    end)
end

function FA.StopNavigation()
    StopNav("Navigation cancelled.")
end
