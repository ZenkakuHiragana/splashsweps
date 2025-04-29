
---@class ss
local ss = SplashSWEPs
if not ss then return end

---Defines how painted ink will behave with a set of functions.
---@class ss.IInkFeature
---@field Identifier string?
---Called when this type of ink is about to be painted.
---Return true to suppress painting.
---@field OnPaint? fun(pos: Vector, normal: Vector, transform: VMatrix): boolean?
---Called when some entity is touching on surface painted with this type of ink.
---Check the `normal` to determine if it's wall or ground.
---@field OnTouchEntity? fun(ent: Entity, normal: Vector)

---Reads all Lua files under specific path to define ink features (type of event handlers)
function ss.LoadInkFeatures()
    for f in ss.IterateFilesRecursive("splashsweps/ink", "LUA", "*.lua") do
        local feature = include(f) ---@type ss.IInkFeature
        local id = f:gsub("^splashsweps/ink/", "")
        if isstring(id) then
            feature.Identifier = id
            ss.InkFeatures[id] = feature
        end
    end
end
