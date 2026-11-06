
-- Records which ink feature modules each entity is in contact with, and calls their OnEnter, OnStay, and OnExit.

---@class ss
local ss = SplashSWEPs
local InkType = ss.import "splashsweps/shared/inktype"

---@class ss.ContactStateModule
local ContactState = ss.module "splashsweps/shared/contact/contactstate"

---@class ss.ContactStateModule.State
---@field InContact table<Entity, table<ss.IInkFeature, true>> Entity --> the modules of the ink it is in contact with.
local state = ss.state("splashsweps/shared/contact/contactstate", { InContact = {} })

---Calls OnEnter of the modules an entity comes into contact with. The modules it is already in contact with are not called.
---@param ent      Entity
---@param groups table<ss.IInkFeature, ss.InkContact[]> The contacts InkContact.Find returns.
function ContactState.Enter(ent, groups)
    if not next(groups) then return end
    local inContact = state.InContact[ent] or {}
    state.InContact[ent] = inContact
    for _, feature in ipairs(InkType.Features) do
        local contacts = groups[feature]
        if contacts and not inContact[feature] then
            inContact[feature] = true
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
    local inContact = state.InContact[ent]
    if not inContact then return end
    for _, feature in ipairs(InkType.Features) do
        local contacts = groups[feature]
        if contacts then
            if feature.OnStay then feature.OnStay(ent, contacts, dt) end
        elseif inContact[feature] then
            inContact[feature] = nil
            if feature.OnExit then feature.OnExit(ent) end
        end
    end

    if not next(inContact) then state.InContact[ent] = nil end
end

---Calls OnExit of the modules an entity is in contact with.
---@param ent Entity
function ContactState.Stop(ent)
    local inContact = state.InContact[ent]
    if not inContact then return end
    state.InContact[ent] = nil
    for _, feature in ipairs(InkType.Features) do
        if inContact[feature] and feature.OnExit then feature.OnExit(ent) end
    end
end

hook.Add("EntityRemoved", "SplashSWEPs: Stop ink contacts", ContactState.Stop)

return ContactState
