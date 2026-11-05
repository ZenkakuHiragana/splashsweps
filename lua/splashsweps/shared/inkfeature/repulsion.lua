
-- Repulsion Gel of Portal 2: players and physics objects bounce on it.
-- A player bounces when landing on it, running into it on a wall, or jumping on it, unless crouching.
-- The ink material can change the values, which default to those of Portal 2:
--   $repulsion_minspeed         The minimum speed away from the surface after bouncing
--                               in units per second (bounce_paint_min_speed).
--   $repulsion_wallupwardspeed  The upward speed added when bouncing on a wall
--                               in units per second (bounce_paint_wall_jump_upward_speed).

---@class ss
local ss = SplashSWEPs

---@class ss.RepulsionModule : ss.IInkFeature
local Repulsion = ss.module "splashsweps/shared/inkfeature/repulsion"

local DEFAULT_MIN_SPEED = 500
local DEFAULT_WALL_UPWARD_SPEED = 275

---The minimum Z of the normal of a surface to stand on, and the maximum absolute Z of that of a wall.
local MIN_FLOOR_NORMAL_Z = 0.7

---Returns the contact the velocity goes into the most, and the speed into it.
---@param contacts ss.InkContact[]
---@param velocity Vector
---@return ss.InkContact
---@return number
local function findIncoming(contacts, velocity)
    local incoming, speed = contacts[1], -math.huge
    for _, contact in ipairs(contacts) do
        local s = -velocity:Dot(contact.Normal)
        if s > speed then incoming, speed = contact, s end
    end

    return incoming, speed
end

---Returns the velocity reflected on the surface of the contact, going away from it at least at the minimum speed.
---@param velocity Vector
---@param contact  ss.InkContact
---@param speed    number The speed into the surface, 0 or more.
---@return Vector
local function bounce(velocity, contact, speed)
    local material = contact.InkType.Material
    local away = math.max(speed, material:GetFloat "$repulsion_minspeed" or DEFAULT_MIN_SPEED)
    local result = velocity + contact.Normal * (speed + away)
    if math.abs(contact.Normal.z) < MIN_FLOOR_NORMAL_Z then
        result.z = result.z + (material:GetFloat "$repulsion_wallupwardspeed" or DEFAULT_WALL_UPWARD_SPEED)
    end

    return result
end

function Repulsion.Move(ply, mv, contacts, vars)
    if #contacts == 0 or mv:KeyDown(IN_DUCK) then return end
    local velocity = mv:GetVelocity()
    local contact, speed = findIncoming(contacts, velocity)
    local isFloor = contact.Normal.z >= MIN_FLOOR_NORMAL_Z
    local isJumping = isFloor and ply:OnGround() and mv:KeyPressed(IN_JUMP)
    local isHitting = speed > 0 and not (isFloor and ply:OnGround())
    if not (isJumping or isHitting) then return end

    mv:SetVelocity(bounce(velocity, contact, math.max(speed, 0)))
    -- Leaving the ground keeps the engine from taking away the upward velocity.
    ply:SetGroundEntity(NULL)
end

function Repulsion.PhysicsCollide(ent, contacts, data)
    -- An impact is reported for each of its contact points in the same tick,
    -- and the later ones, whose DeltaTime is shorter than a tick, have the velocity in the middle of the impact.
    if data.DeltaTime < engine.TickInterval() then return end
    local velocity = data.OurOldVelocity
    local contact, speed = findIncoming(contacts, velocity)
    data.PhysObject:SetVelocity(bounce(velocity, contact, math.max(speed, 0)))
end

return Repulsion
