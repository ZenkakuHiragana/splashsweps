
-- Types of ink, each defined by an ink material: a vmt file under materials/splashsweps/inks.

---@class ss
local ss = SplashSWEPs
local Util = ss.import "splashsweps/shared/util"

---@class ss.InkTypeModule
local InkType = ss.module "splashsweps/shared/inktype"

---A module defining how painted ink behaves with a set of functions.
---The `$features` parameter of an ink material names these modules as ss.import does, separated by spaces.
---The modules are imported in both realms.
---@class ss.IInkFeature
---Called when this type of ink is about to be painted.
---Return true to suppress painting.
---@field OnPaint? fun(pos: Vector, normal: Vector, transform: VMatrix): boolean?
---Called when some entity is touching on surface painted with this type of ink.
---Check the `normal` to determine if it's wall or ground.
---@field OnTouchEntity? fun(ent: Entity, normal: Vector)

---A type of ink.
---@class ss.InkType
---@field Index      integer          Internal index number used by networking.
---@field Identifier string           The name of the ink material defining this type of ink.
---@field Features   ss.IInkFeature[] Modules named by `$features` of the ink material.

---@class ss.InkTypeModule.State
---@field Types             ss.InkType[]           Defined ink types indexed by their internal index.
---@field IdentifierToIndex table<string, integer> Conversion table from identifier string to internal index.
---@field NumBits           integer                Required bits to transfer an ink type index as an unsigned integer.
local state = ss.state("splashsweps/shared/inktype", { Types = {}, IdentifierToIndex = {} }) ---@type ss.InkTypeModule.State

---Defined ink types indexed by their internal index.
InkType.Types = state.Types

---Converts ink type identifier (string) into internal index.
---@param identifier string
---@return integer?
function InkType.FindIndex(identifier)
    return state.IdentifierToIndex[identifier]
end

---Reads all ink materials and defines the ink types.
function InkType.Load()
    local inktypeCount = 0
    for f in Util.IterateFilesRecursive("materials/splashsweps/inks", "GAME", "*.vmt") do
        local mat = Material(f:sub(11))
        if mat and not mat:IsError() then
            inktypeCount = inktypeCount + 1
            local name = mat:GetName()
            local features = {} ---@type ss.IInkFeature[]
            for feature in (mat:GetString "$features" or ""):gmatch "%S+" do
                features[#features + 1] = ss.import(feature)
            end
            state.Types[inktypeCount] = {
                Index = inktypeCount,
                Identifier = name,
                Features = features,
            }
            state.IdentifierToIndex[name] = inktypeCount
        end
    end

    state.NumBits = math.max(select(2, math.frexp(inktypeCount - 1)), 1)
end

---Returns the required bits to transfer an ink type index as an unsigned integer.
---@return integer
function InkType.GetNumBits()
    return state.NumBits
end

return InkType
