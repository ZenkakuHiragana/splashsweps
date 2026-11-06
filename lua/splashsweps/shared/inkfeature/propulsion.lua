
-- Propulsion Gel of Portal 2: a player running on it speeds up, and slows down gradually after leaving it.
-- The ink material can change the values, which default to those of Portal 2:
--   $propulsion_maxspeed      The maximum speed on the gel in units per second (sv_speed_paint_max).
--   $propulsion_acceleration  How fast the speed limit rises on the gel and falls after it
--                             in units per second squared (sv_speed_paint_acceleration).

---@class ss
local ss = SplashSWEPs

---@class ss.PropulsionModule : ss.IInkFeature
local Propulsion = ss.module "splashsweps/shared/inkfeature/propulsion"

local DEFAULT_MAX_SPEED = 800
local DEFAULT_ACCELERATION = 500

---The minimum Z of the normal of a surface to stand on.
local MIN_FLOOR_NORMAL_Z = 0.7

Propulsion.PredictedVars = {
    -- The speed limit raised by the gel, or 0 for the usual one.
    SpeedLimit = "Float",
    -- How fast the raised limit falls, which the gel the player was on gives.
    Deceleration = "Float",
}

---Returns the ink material of the floor among the contacts, or nil if none of them is a floor.
---@param contacts ss.InkContact[]
---@return IMaterial?
local function findFloor(contacts)
    for _, contact in ipairs(contacts) do
        if contact.Normal.z >= MIN_FLOOR_NORMAL_Z then return contact.InkType.Material end
    end
end

function Propulsion.Move(ply, mv, contacts, vars)
    local usual = mv:GetMaxClientSpeed()
    local limit = vars.SpeedLimit ---@type number
    if ply:OnGround() then
        local dt = engine.TickInterval()
        local floorMaterial = findFloor(contacts)
        if floorMaterial then
            -- The limit rises from the current speed, so it keeps rising only while the player keeps running.
            local acceleration = floorMaterial:GetFloat "$propulsion_acceleration" or DEFAULT_ACCELERATION
            limit = math.min(math.max(mv:GetVelocity():Length2D(), usual) + acceleration * dt,
                floorMaterial:GetFloat "$propulsion_maxspeed" or DEFAULT_MAX_SPEED)
            vars.Deceleration = acceleration
        else
            limit = limit - vars.Deceleration * dt
        end
    end

    if limit <= usual then limit = 0 end
    vars.SpeedLimit = limit
    if limit > 0 then
        mv:SetMaxSpeed(limit)
        mv:SetMaxClientSpeed(limit)
    end
end

return Propulsion
