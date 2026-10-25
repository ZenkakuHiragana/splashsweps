
-- Ink features: event handlers that ink types can have, defined by Lua files under splashsweps/ink.

---@class ss
local ss = SplashSWEPs
local Util = ss.import "splashsweps/shared/util"

---@class ss.InkFeatureModule
local InkFeature = ss.module "splashsweps/shared/inkfeature"

---Defines how painted ink will behave with a set of functions.
---@class ss.IInkFeature
---@field Identifier string?
---Called when this type of ink is about to be painted.
---Return true to suppress painting.
---@field OnPaint? fun(pos: Vector, normal: Vector, transform: VMatrix): boolean?
---Called when some entity is touching on surface painted with this type of ink.
---Check the `normal` to determine if it's wall or ground.
---@field OnTouchEntity? fun(ent: Entity, normal: Vector)

---Defined ink features indexed by their identifiers.
InkFeature.Features = ss.state("splashsweps/shared/inkfeature", {}) ---@type table<string, ss.IInkFeature>

---Reads all Lua files under specific path to define ink features (type of event handlers)
function InkFeature.Load()
    for f in Util.IterateFilesRecursive("splashsweps/ink", "LUA", "*.lua") do
        local feature = include(f) ---@type ss.IInkFeature
        local id = f:gsub("^splashsweps/ink/", "")
        if isstring(id) then
            feature.Identifier = id
            InkFeature.Features[id] = feature
        end
    end
end

return InkFeature
