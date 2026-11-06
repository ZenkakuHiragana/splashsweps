
-- The variables the ink feature modules declare for Move, kept for each player and predicted as the movement is.
-- They are in the data tables of the entities the server creates for each ready player,
-- which the client predicting the player makes predictable, so that the engine restores and corrects them.
--
-- An entity has a limited number of slots for each type, so the modules are put into groups of slots.
-- Each module declaring variables goes into the first group with enough slots, in the order of InkType.Features,
-- and a player has an entity for each group.
-- So modules share an entity while it has slots, a module without variables makes no entity,
-- and a module an entity cannot hold is left out without affecting the others.
-- The variables are read and written by the DT functions of Entity, which Entity:NetworkVar is built on,
-- as they depend on the loaded modules, while NetworkVar declares the same variables for every entity of a class.

---@class ss
local ss = SplashSWEPs
local InkType = ss.import "splashsweps/shared/inktype"

---@class ss.PredictedVarsModule
local PredictedVars = ss.module "splashsweps/shared/contact/predictedvars"

---The class of the entities, defined in lua/entities.
PredictedVars.CLASS_NAME = "splashsweps_predictedvars"

---The slot of Int an entity has its group in.
PredictedVars.GROUP_SLOT = 0

local EntityMeta = FindMetaTable "Entity" --[[@as Entity]]

---The DT functions and the number of slots of an entity for each type.
local TYPES = {
    String = { Get = EntityMeta.GetDTString, Set = EntityMeta.SetDTString, Slots = 4 },
    Bool   = { Get = EntityMeta.GetDTBool,   Set = EntityMeta.SetDTBool,   Slots = 32 },
    Float  = { Get = EntityMeta.GetDTFloat,  Set = EntityMeta.SetDTFloat,  Slots = 32 },
    Int    = { Get = EntityMeta.GetDTInt,    Set = EntityMeta.SetDTInt,    Slots = 32 },
    Vector = { Get = EntityMeta.GetDTVector, Set = EntityMeta.SetDTVector, Slots = 32 },
    Angle  = { Get = EntityMeta.GetDTAngle,  Set = EntityMeta.SetDTAngle,  Slots = 32 },
    Entity = { Get = EntityMeta.GetDTEntity, Set = EntityMeta.SetDTEntity, Slots = 32 },
}

---A variable of a module in the data table of an entity.
---@class ss.PredictedVars.Var
---@field Get  fun(ent: Entity, slot: integer): any The DT function to read it, such as Entity.GetDTFloat.
---@field Set  fun(ent: Entity, slot: integer, value: any)
---@field Slot integer

---Where the variables of a module are.
---@class ss.PredictedVars.Layout
---@field Group integer The group of the entity having them.
---@field Vars  table<string, ss.PredictedVars.Var> Variable name --> where it is.

---@class ss.PredictedVarsModule.State
---@field Layouts   table<ss.IInkFeature, ss.PredictedVars.Layout> Module --> where its variables are.
---@field NumGroups integer
---@field Entities  table<Player, table<integer, ss.PredictedVars.Entity>> Player --> group --> the entity.
---@field Vars      table<Player, table<ss.IInkFeature, table<string, any>>> Player --> module --> the table given to it.
local state = ss.state("splashsweps/shared/contact/predictedvars", {
    Layouts = {},
    NumGroups = 0,
    Entities = {},
    Vars = {},
})

---Player --> group --> the entity having the variables of the group for the player.
PredictedVars.Entities = state.Entities

---Returns the number of groups, which is the number of the entities for each player.
---@return integer
function PredictedVars.GetNumGroups()
    return state.NumGroups
end

---Decides where the variables of the modules are, in the order of InkType.Features and then of the names,
---which is the same in both realms. Call this after InkType.Load.
function PredictedVars.Setup()
    table.Empty(state.Layouts)
    table.Empty(state.Vars)
    local groups = {} ---@type table<string, integer>[] Group --> type --> the next slot.
    for _, feature in ipairs(InkType.Features) do
        local declared = feature.PredictedVars
        if declared then
            local names = table.GetKeys(declared) ---@type string[]
            table.sort(names)
            local counts = {} ---@type table<string, integer>
            for _, name in ipairs(names) do
                counts[declared[name]] = (counts[declared[name]] or 0) + 1
            end

            ---@param group table<string, integer>
            ---@return boolean
            local function fits(group)
                for vartype, count in pairs(counts) do
                    local t = TYPES[vartype]
                    if not t or (group[vartype] or 0) + count > t.Slots then return false end
                end

                return true
            end

            local index = #groups + 1
            for i, group in ipairs(groups) do
                if fits(group) then
                    index = i
                    break
                end
            end

            local group = groups[index] or { Int = PredictedVars.GROUP_SLOT + 1 }
            if fits(group) then
                groups[index] = group
                local vars = {} ---@type table<string, ss.PredictedVars.Var>
                for _, name in ipairs(names) do
                    local vartype = declared[name]
                    local slot = group[vartype] or 0
                    group[vartype] = slot + 1
                    vars[name] = { Get = TYPES[vartype].Get, Set = TYPES[vartype].Set, Slot = slot }
                end

                state.Layouts[feature] = { Group = index, Vars = vars }
            else
                ErrorNoHalt(string.format(
                    "SplashSWEPs: An entity cannot have the predicted variables %s of an ink feature module.\n",
                    table.concat(names, ", ")))
            end
        end
    end

    state.NumGroups = #groups
end

---Makes the table to read and write the variables of a module in an entity.
---@param ent  Entity
---@param vars table<string, ss.PredictedVars.Var>
---@return table<string, any>
local function newVars(ent, vars)
    ---@param name string
    ---@return ss.PredictedVars.Var
    local function findVar(name)
        return vars[name] or error(string.format("SplashSWEPs: Undeclared predicted variable %q", name), 3)
    end

    return setmetatable({}, {
        __index = function(_, name)
            local var = findVar(name)
            return var.Get(ent, var.Slot)
        end,
        __newindex = function(_, name, value)
            local var = findVar(name)
            var.Set(ent, var.Slot, value)
        end,
    })
end

---Returns the table to read and write the variables a module declares for a player, or nil
---if the module declares none, an entity cannot have them, or the entity having them does not exist in this realm.
---Reading or writing a name the module does not declare is an error.
---@param ply     Player
---@param feature ss.IInkFeature
---@return table<string, any>?
function PredictedVars.Get(ply, feature)
    local cached = state.Vars[ply]
    local vars = cached and cached[feature]
    if vars then return vars end

    local layout = state.Layouts[feature]
    local entities = state.Entities[ply]
    local ent = layout and entities and entities[layout.Group]
    if not ent then return nil end

    vars = newVars(ent, layout.Vars)
    state.Vars[ply] = cached or {}
    state.Vars[ply][feature] = vars
    return vars
end

---Starts using an entity for its owner. The entity calls this when it initializes.
---@param ent ss.PredictedVars.Entity
function PredictedVars.Add(ent)
    local owner = ent:GetOwner() --[[@as Player]]
    state.Entities[owner] = state.Entities[owner] or {}
    state.Entities[owner][ent:GetGroup()] = ent
    state.Vars[owner] = nil
end

---Stops using an entity. The entity calls this when it is removed.
---The owner is found by the entity, as it can be invalid already when the player has left.
---@param ent ss.PredictedVars.Entity
function PredictedVars.Remove(ent)
    local group = ent:GetGroup()
    for ply, entities in pairs(state.Entities) do
        if entities[group] == ent then
            entities[group] = nil
            state.Vars[ply] = nil
            if not next(entities) then state.Entities[ply] = nil end
        end
    end
end

return PredictedVars
