
-- Checks the contacts of the entities with ink periodically, on the server and on each client separately.
-- The server also calls PhysicsCollide of the modules for the collisions of physics objects with ink,
-- which start the contacts too.

---@class ss
local ss = SplashSWEPs
if not ss then return end

local ContactState = ss.import "splashsweps/shared/contact/contactstate"
local InkContact   = ss.import "splashsweps/shared/contact/inkcontact"
local InkType      = ss.import "splashsweps/shared/inktype"

---Seconds between the checks.
local CHECK_INTERVAL = 0.1

---Hammer units from the point of a collision toward the entity, where the contacts are read.
---The point can be behind the surface by the collision margins of the physics objects,
---and the contacts are those of the box around the reading point reaching the point of the collision.
local HIT_REACH = 2

---@class ss.EntityContactState
---@field Collisions     table<Entity, table<ss.IInkFeature, ss.InkContact[]>[]> Server only; the contacts of the collisions since the previous Think.
---@field LastCheckTime? number CurTime() of the previous check, or nil before the first one.
local state = ss.state("splashsweps/shared/contact/entity", { Collisions = {} })

hook.Add("Think", "SplashSWEPs: Check ink contacts of entities", function()
    if SERVER then
        for ent, collisions in pairs(state.Collisions) do
            if IsValid(ent) and InkContact.ShouldCheck(ent) then
                for _, groups in ipairs(collisions) do
                    ContactState.Enter(ent, groups)
                end
            end
        end

        table.Empty(state.Collisions)
    end

    local now = CurTime()
    local last = state.LastCheckTime or now
    if state.LastCheckTime and now - last < CHECK_INTERVAL then return end
    state.LastCheckTime = now

    for _, ent in ents.Iterator() do
        if (CLIENT and ent:IsDormant()) or not InkContact.ShouldCheck(ent) then
            ContactState.Stop(ent)
        else
            ContactState.Check(ent, InkContact.Find(ent, ent:WorldSpaceAABB()), now - last)
        end
    end
end)

if CLIENT then return end

hook.Add("EntityRemoved", "SplashSWEPs: Forget collisions", function(ent)
    state.Collisions[ent] = nil
end)

---Calls PhysicsCollide of the modules of the ink at the point of a collision,
---and records the contacts to call OnEnter in the next Think, after the physics simulation,
---as OnEnter may do what the callback does not allow, such as removing the entity.
---@param ent  Entity
---@param data Structure.CollisionData
local function OnPhysicsCollide(ent, data)
    if not InkContact.ShouldCheck(ent) then return end

    -- HitNormal points from the entity into what it hits.
    local center = data.HitPos - data.HitNormal * HIT_REACH
    local reach = Vector(HIT_REACH, HIT_REACH, HIT_REACH)
    local groups = InkContact.Find(ent, center - reach, center + reach)
    if not next(groups) then return end

    for _, feature in ipairs(InkType.Features) do
        local contacts = groups[feature]
        if contacts and feature.PhysicsCollide then
            feature.PhysicsCollide(ent, contacts, data)
        end
    end

    state.Collisions[ent] = state.Collisions[ent] or {}
    table.insert(state.Collisions[ent], groups)
end

-- The physics object of an entity is made after the entity is created, so it is checked in the next tick.
hook.Add("OnEntityCreated", "SplashSWEPs: Find collisions with ink", function(ent)
    timer.Simple(0, function()
        if IsValid(ent) and IsValid(ent:GetPhysicsObject()) then
            ent:AddCallback("PhysicsCollide", OnPhysicsCollide)
        end
    end)
end)
