
-- Types of ink, defined by vmt files under materials/splashsweps/inktypes.

---@class ss
local ss = SplashSWEPs
local Util = ss.import "splashsweps/shared/util"

---@class ss.InkTypeModule
local InkType = ss.module "splashsweps/shared/inktype"

---Ink type definition for the appearance and interactions.
---@class ss.InkType
---@field Index           integer   Internal index number used by networking.
---@field Identifier      string    The name of the material defining this type of ink.
---@field Features        string[]  List of features this type of ink will have.
---@field BaseUV          number[]? Atlas range (minU, minV, maxU, maxV) of $basetexture; negative minU encodes transposition
---@field TintUV          number[]? Atlas range (minU, minV, maxU, maxV) of $tinttexture; negative minU encodes transposition
---@field DetailBlendMode integer   $detailblendmode written to the ink map, 0 if the detail is disabled.

---@class ss.InkTypeModule.State
---@field Types             ss.InkType[]           Defined ink types indexed by their internal index.
---@field IdentifierToIndex table<string, integer> Conversion table from identifier string to internal index.
---@field NumBits           integer                Required bits to transfer an ink type index as an unsigned integer.
local state = ss.state("splashsweps/shared/inktype", { Types = {}, IdentifierToIndex = {} }) ---@type ss.InkTypeModule.State

---Defined ink types indexed by their internal index.
InkType.Types = state.Types

---JSON scheme for ink type definition.
---@class ss.InkType.JSON
---@field name?        string   The identifier.
---@field features?    string[] List of features this type of ink will have.
---@field basetexture? string   The albedo texture to render this ink type.
---@field tinttexture? string   Color tint texture applied to the ground.
---@field detail?      string   Detail texture.

---Converts ink type identifier (string) into internal index.
---@param identifier string
---@return integer?
function InkType.FindIndex(identifier)
    return state.IdentifierToIndex[identifier]
end

---Reads all JSON files and defines all ink types used in this addon.
function InkType.Load()
    -- Load custom ink detail updaters recursively. splashsweps_includes.lua sends them to clients.
    if CLIENT then
        for lua in Util.IterateFilesRecursive("splashsweps/client/inktypes", "LUA") do
            include(lua)
        end
    end

    local inktypeCount = 0
    for f in Util.IterateFilesRecursive("materials/splashsweps/inktypes", "GAME", "*.vmt") do
        local mat = Material(f:sub(11))
        if mat and not mat:IsError() then
            inktypeCount = inktypeCount + 1
            local name = mat:GetName()
            state.Types[inktypeCount] = {
                Index = inktypeCount,
                Identifier = name,
                Features = (mat:GetString "$features" or ""):Split "%s+",
                DetailBlendMode = 0,
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
