
---@class ss
local ss = SplashSWEPs
if not ss then return end
local locals = ss.Locals ---@class ss.Locals
if not locals.InkTypeIdentifierToIndex then
    locals.InkTypeIdentifierToIndex = {}
end

---Conversion table from identifier string to internal index for ink type.
---@type table<string, integer>
local InkTypeIdentifierToIndex = locals.InkTypeIdentifierToIndex

---Ink type definition for the appearance and interactions.
---@class ss.InkType
---@field Index      integer   Internal index number used by networking.
---@field Identifier string    The identifier of this type of ink as the key of ss.InkTypes.
---@field Features   string[]  List of features this type of ink will have.
---@field BaseUV     number[]? UV range (minU, minV, maxU, maxV) of $basetexture
---@field TintUV     number[]? UV range (minU, minV, maxU, maxV) of $tinttexture
---@field DetailUV   number[]? UV range (minU, minV, maxU, maxV) of $details
ss.struct "InkType" {
    Index = 0,
    Identifier = "",
    Features = {},
    BaseUV = nil,
    TintUV = nil,
    DetailUV = nil,
}

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
function ss.FindInkTypeID(identifier)
    return InkTypeIdentifierToIndex[identifier]
end

---Reads all JSON files and defines all ink types used in this addon.
function ss.LoadInkTypes()
    local inktypeCount = 0
    for f in ss.IterateFilesRecursive("materials/splashsweps/inktypes", "GAME", "*.vmt") do
        local mat = Material(f:sub(11))
        if mat and not mat:IsError() then
            inktypeCount = inktypeCount + 1
            local name = mat:GetName()
            local inktype = ss.new "InkType"
            inktype.Index = inktypeCount
            inktype.Identifier = name
            inktype.Features = (mat:GetString "$features" or ""):Split "%s+"
            ss.InkTypes[inktypeCount] = inktype
            InkTypeIdentifierToIndex[name] = inktypeCount
        end
    end

    ---Total number of defined ink types.
    ss.NumInkTypes = inktypeCount

    ---Required bits to transfer ink type as an unsigned integer.
    ss.MAX_INKTYPE_BITS = math.max(select(2, math.frexp(inktypeCount - 1)), 1)
end
