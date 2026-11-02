
-- Records which ink feature modules each entity is touching, and calls their OnEnter, OnStay, and OnExit.

---@class ss
local ss = SplashSWEPs
local InkType = ss.import "splashsweps/shared/inktype"

---@class ss.ContactStateModule
local ContactState = ss.module "splashsweps/shared/touch/contactstate"

---@class ss.ContactStateModule.State
---@field Touching table<Entity, table<ss.IInkFeature, true>> Entity --> the modules of the ink it is touching.
local state = ss.state("splashsweps/shared/touch/contactstate", { Touching = {} })

---Calls OnEnter of the modules an entity starts touching. The modules it is already touching are not called.
---@param ent      Entity
---@param groups table<ss.IInkFeature, ss.InkContact[]> The contacts InkContact.Find returns.
function ContactState.Enter(ent, groups)
    if not next(groups) then return end
    local touching = state.Touching[ent] or {}
    state.Touching[ent] = touching
    for _, feature in ipairs(InkType.Features) do
        local contacts = groups[feature]
        if contacts and not touching[feature] then
            touching[feature] = true
            if feature.OnEnter then feature.OnEnter(ent, contacts) end
        end
    end
end

---Calls OnEnter, OnStay, or OnExit of the modules for the contacts an entity has at a check.
---@param ent    Entity
---@param groups table<ss.IInkFeature, ss.InkContact[]> The contacts InkContact.Find returns.
---@param dt     number Seconds since the previous check.
function ContactState.Check(ent, groups, dt)
    ContactState.Enter(ent, groups)
    local touching = state.Touching[ent]
    if not touching then return end
    for _, feature in ipairs(InkType.Features) do
        local contacts = groups[feature]
        if contacts then
            if feature.OnStay then feature.OnStay(ent, contacts, dt) end
        elseif touching[feature] then
            touching[feature] = nil
            if feature.OnExit then feature.OnExit(ent) end
        end
    end

    if not next(touching) then state.Touching[ent] = nil end
end

---Calls OnExit of the modules an entity is touching.
---@param ent Entity
function ContactState.Stop(ent)
    local touching = state.Touching[ent]
    if not touching then return end
    state.Touching[ent] = nil
    for _, feature in ipairs(InkType.Features) do
        if touching[feature] and feature.OnExit then feature.OnExit(ent) end
    end
end

hook.Add("EntityRemoved", "SplashSWEPs: Stop touching ink", ContactState.Stop)

return ContactState
